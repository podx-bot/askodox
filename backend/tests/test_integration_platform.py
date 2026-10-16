"""Universal Integration Platform, phase 1: catalog statuses computed from live
state (zero-credential readiness), the Owner checklist, OTP delivery with
provider fallback, and no fixed-OTP demo bypass in production."""
import dataclasses
import json
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import integration_catalog as ic

OWNER_KEY = "owner-int-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
SECRET = "rzp-test-secret-should-never-leak"


class Http:
    def __init__(self):
        self.calls = []
        self.sms_ok = True

    def __call__(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if "api.razorpay.com" in url:
            return 200, {"items": []}
        if "msg91.com" in url:
            return (200, {"type": "success", "message": "req1"}) if self.sms_ok else (400, {"message": "bad"})
        if "graph.facebook.com" in url:
            return 200, {"messages": [{"id": "wamid.T"}]}
        return 404, {}


class FakeWhatsApp:
    def __init__(self, configured=True, ok=True):
        self.configured, self.ok, self.sent = configured, ok, []

    def is_configured(self):
        return self.configured

    def send_text_message(self, mobile, text):
        self.sent.append((mobile, text))
        return {"success": self.ok, "status": "SENT" if self.ok else "WINDOW_CLOSED"}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "int.db"),
                                   secrets_key=Fernet.generate_key().decode(), gemini_api_key="",
                                   openai_api_key="", sarvam_api_key="")
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    http = Http()
    monkeypatch.setattr(container, "comms_http", http, raising=False)
    monkeypatch.setattr(container, "whatsapp_service", FakeWhatsApp(configured=False), raising=False)
    for attr in ("platform", "billing_store"):
        monkeypatch.setattr(container, attr, None, raising=False)
    for name in ("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET", "CASHFREE_CLIENT_ID",
                 "CASHFREE_CLIENT_SECRET", "FIREBASE_SERVICE_ACCOUNT_JSON", "ASKODOX_OTP_CHANNELS",
                 "RAILWAY_ENVIRONMENT_NAME", "ASKODOX_ENV", "ASKODOX_DEMO_LOGIN", "ASKODOX_TEST_OTP_MODE"):
        monkeypatch.delenv(name, raising=False)
    from app.services import payment_gateway_health

    payment_gateway_health._CACHE.clear()
    from app.api.routes import onboarding_auth

    onboarding_auth._otps.clear()
    yield TestClient(app), container, http


def _rows(client):
    r = client.get("/admin/cc/integrations/catalog", headers=OWNER)
    assert r.status_code == 200, r.text
    return {i["key"]: i for i in r.json()["items"]}, r.json()


def test_catalog_with_zero_credentials_is_honest_and_needs_admin(env):
    client, _, _ = env
    assert client.get("/admin/cc/integrations/catalog").status_code in (401, 403)
    assert client.get("/admin/cc/integrations/owner-checklist").status_code in (401, 403)
    rows, body = _rows(client)
    assert set(body["categories"]) == {"auth", "kyc", "communication", "commerce", "app_monetization", "bfsi",
                                       "payments", "maps", "ai", "video"}
    assert all(r["status"] in ic.STATUSES for r in rows.values())
    assert {r["category"] for r in rows.values()} == set(body["categories"]), "every area has entries"
    # Not built is named honestly, never "ready".
    for key in ("kyc_face", "kyc_video", "google_sign_in", "passkeys", "phonepe"):
        assert rows[key]["status"] == ic.NOT_BUILT and rows[key]["adapter"] == "not_built"
    # KYC engine built, vendor adapter not: waits for a provider, never "verified".
    for key in ("kyc_pan", "kyc_digilocker", "kyc_gst", "kyc_bank"):
        assert rows[key]["adapter"] == "interface_ready" and rows[key]["status"] == ic.APPROVAL_REQUIRED
    assert rows["kyc_documents_review"]["status"] == ic.CODE_READY
    # Built adapters without credentials say what is missing.
    assert rows["razorpay"]["status"] == ic.APPROVAL_REQUIRED
    assert rows["gemini"]["status"] in (ic.ACCOUNT_REQUIRED, ic.CONFIG_REQUIRED)
    assert rows["otp_sms"]["status"] == ic.APPROVAL_REQUIRED
    assert rows["fcm_push"]["status"] in (ic.ACCOUNT_REQUIRED, ic.CONFIG_REQUIRED)
    assert not any(r["status"] in ic.DONE_STATUSES for r in rows.values()), "nothing is verified without a real call"
    checklist = client.get("/admin/cc/integrations/owner-checklist", headers=OWNER).json()
    keys = [a["key"] for a in checklist["owner_actions"]]
    assert "razorpay" in keys and "kyc_face" not in keys, "NOT BUILT is development work, not an Owner task"
    assert "kyc_face" in [d["key"] for d in checklist["development_pending"]]
    assert all(a["steps"] or a["how_to_test"] for a in checklist["owner_actions"] if a["status"] != ic.CODE_READY)


def test_real_checks_drive_status_and_secrets_never_leave(env, monkeypatch):
    client, container, _ = env
    monkeypatch.setenv("RAZORPAY_KEY_ID", "rzp_test_INTPLATFORM1")
    monkeypatch.setenv("RAZORPAY_KEY_SECRET", SECRET)
    container.platform = None
    rows, body = _rows(client)
    assert rows["razorpay"]["status"] == ic.SANDBOX_TESTED, "a real (read-only) gateway answer in TEST mode"
    assert SECRET not in json.dumps(body) and "rzp_test_INTPLATFORM1" not in json.dumps(body)
    # A mock-mode provider is wiring only: never SANDBOX TESTED / LIVE VERIFIED.
    r = client.put("/admin/cc/platform/integrations/sms", headers=OWNER, json={"enabled": True, "mode": "mock"})
    assert r.status_code == 200
    assert _rows(client)[0]["sms"]["status"] == ic.CODE_READY
    # Staff switch-off wins over configured credentials.
    r = client.put("/admin/cc/platform/integrations/sms", headers=OWNER, json={
        "enabled": False, "mode": "test", "config": {"sender_id": "ASKODX", "vendor": "msg91"},
        "secrets": {"api_key": "msg91-test-key-000000000"}})
    assert r.status_code == 200, r.text
    assert _rows(client)[0]["sms"]["status"] == ic.DISABLED


def test_evaluate_rules():
    built = dict(ic.CATALOG[0], approval_required=False, account_required=False, adapter="built")
    probe = lambda status: (lambda _src: {"kind": "registry", "status": status})  # noqa: E731
    assert ic.evaluate(built, probe({"missing": ["api_key"], "status": "NEEDS_CREDENTIALS"}))["status"] == \
        ic.CONFIG_REQUIRED
    assert ic.evaluate(built, probe({"missing": [], "status": "TEST", "last_check_ok": 1, "mode": "test"}))[
        "status"] == ic.SANDBOX_TESTED
    assert ic.evaluate(built, probe({"missing": [], "status": "LIVE", "last_check_ok": 1, "mode": "live"}))[
        "status"] == ic.LIVE_VERIFIED
    assert ic.evaluate(built, probe({"missing": [], "status": "TEST", "last_check_ok": 0}))["status"] == ic.ERROR
    assert ic.evaluate(built, probe({"missing": [], "status": "TEST"}))["status"] == ic.CODE_READY
    assert ic.evaluate(dict(built, adapter="not_built"), probe({}))["status"] == ic.NOT_BUILT
    assert ic.evaluate(built, lambda _s: (_ for _ in ()).throw(RuntimeError()))["status"] == ic.ERROR


def test_otp_falls_back_and_never_returns_the_code(env, monkeypatch):
    client, container, http = env
    send = lambda m: client.post("/onboarding/otp/send", json={"mobile": m})  # noqa: E731
    r = send("+91 98765 11111")
    assert r.status_code == 503 and "not configured" in r.json()["detail"]
    # Legacy WhatsApp configured but refuses (24 h window) -> SMS takes over.
    container.whatsapp_service = FakeWhatsApp(configured=True, ok=False)
    client.put("/admin/cc/platform/integrations/sms", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"sender_id": "ASKODX", "vendor": "msg91",
                                                    "dlt_template_id": "1207000000000000001"},
        "secrets": {"api_key": "msg91-test-key-000000000"}})
    from app.api.routes import onboarding_auth

    onboarding_auth._otps.clear()
    ok = send("+91 98765 22222")
    assert ok.status_code == 200 and ok.json()["channel"] == "sms", ok.text
    assert container.whatsapp_service.sent, "WhatsApp was tried first"
    sms = [c for c in http.calls if "msg91.com" in c[1]][-1]
    code = sms[2]["json"]["recipients"][0]["var"]
    assert any(ch.isdigit() for ch in code)
    shown = {k: v for k, v in ok.json().items() if k not in ("expires_in_seconds", "resend_after_seconds")}
    assert not any(ch.isdigit() for ch in json.dumps(shown)), "the code is never returned"
    # Channel order is configurable.
    monkeypatch.setenv("ASKODOX_OTP_CHANNELS", "sms")
    onboarding_auth._otps.clear()
    assert send("+91 98765 33333").json()["channel"] == "sms"


def test_demo_login_is_not_a_production_bypass(env, monkeypatch):
    client, container, _ = env
    from app.api.routes import onboarding_auth

    demo = {"mobile": "+91 99999 99999"}
    assert client.post("/onboarding/otp/send", json=demo).json()["channel"] == "test", "local / staging: allowed"
    onboarding_auth._otps.clear()
    monkeypatch.setenv("RAILWAY_ENVIRONMENT_NAME", "production")
    r = client.post("/onboarding/otp/send", json=demo)
    assert r.status_code == 503, "production: no fixed OTP; a real provider must deliver"
    assert client.post("/onboarding/otp/verify", json={**demo, "otp": "123456"}).status_code == 400
    monkeypatch.setenv("ASKODOX_DEMO_LOGIN", "yes")
    onboarding_auth._otps.clear()
    assert client.post("/onboarding/otp/send", json=demo).json()["channel"] == "test", "explicit Owner switch"
    v = client.post("/onboarding/otp/verify", json={**demo, "otp": "123456"}).json()
    assert v["app_user_id"] == "app-phone-919999999999"
    # Even then, the shared demo account can never become a tester.
    assert client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": "9999999999"}).status_code == 409
