"""Integration readiness without real credentials: existing deployment keys are
reused (never shown), unconfigured providers are never contacted, mock mode
proves the wiring without leaving ASKODOX, real providers get the exact
request shapes (recorded fake HTTP / SMTP -- no network), the sandbox gateway
never exists in production, direct UPI pays the seller's own UPI ID, and
discovered videos go through Pending Review with affiliate-ready routing.

Every credential, number and address here is a test fixture.
"""
import dataclasses
import json
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import external_call_budget, payment_gateway, rate_limit

OWNER_KEY = "owner-ir-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
BASE = "/admin/cc/platform"
FAKE_TOKEN = "EAAG-test-token-" + uuid.uuid4().hex


class FakeHttp:
    def __init__(self, responses=None):
        self.calls = []
        self.responses = responses or {}

    def __call__(self, method, url, **kwargs):
        self.calls.append({"method": method, "url": url, **kwargs})
        for fragment, response in self.responses.items():
            if fragment in url:
                return response
        return 500, {"error": {"message": "unexpected call"}}


class FakeSMTP:
    sent = []
    logins = []

    def __init__(self, host, port, timeout=None):
        self.host, self.port = host, port

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def starttls(self):
        pass

    def login(self, user, password):
        FakeSMTP.logins.append((user, bool(password)))

    def send_message(self, msg):
        FakeSMTP.sent.append({"to": msg["To"], "subject": msg["Subject"], "host": self.host})


@pytest.fixture(autouse=True)
def _fresh():
    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    FakeSMTP.sent, FakeSMTP.logins = [], []
    yield


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    for var in ("WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID", "WHATSAPP_API_VERSION", "WHATSAPP_APP_SECRET",
                "FIREBASE_SERVICE_ACCOUNT_JSON", "YOUTUBE_API_KEY", "RAILWAY_ENVIRONMENT_NAME", "SMS_API_KEY",
                "SMTP_PASSWORD", "SMTP_HOST", "EMAIL_FROM"):
        monkeypatch.delenv(var, raising=False)
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "ir.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    http = FakeHttp()
    monkeypatch.setattr(container, "comms_http", http, raising=False)
    monkeypatch.setattr(container, "smtp_factory", FakeSMTP, raising=False)
    monkeypatch.setattr(container, "integration_probes", None, raising=False)
    yield TestClient(app, follow_redirects=False), container, http
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None


def items(client):
    return {i["provider"]: i for i in client.get(f"{BASE}/integrations", headers=OWNER).json()["items"]}


def test_existing_deployment_keys_are_reused_and_never_shown(api, monkeypatch):
    client, container, http = api
    monkeypatch.setenv("WHATSAPP_ACCESS_TOKEN", FAKE_TOKEN)
    monkeypatch.setenv("WHATSAPP_PHONE_NUMBER_ID", "1234567890")
    container.platform = None
    wa = items(client)["whatsapp_cloud"]
    assert wa["missing"] == [] and wa["sources"]["access_token"] == "environment"
    assert wa["status"] == "DISABLED", "configured through the environment but off until an admin enables it"
    assert FAKE_TOKEN not in client.get(f"{BASE}/integrations", headers=OWNER).text
    assert wa["secret_names"] == ["access_token", "app_secret"] and "phone_number_id" in wa["config_keys"]
    assert not http.calls


def test_unconfigured_providers_are_never_contacted(api):
    client, _, http = api
    for provider, to in (("sms", "9876543210"), ("email", "owner@example.com"), ("whatsapp_cloud", "9876543210")):
        record = client.post(f"{BASE}/integrations/{provider}/test-send", headers=OWNER,
                             json={"to": to}).json()
        assert record["status"] == "SKIPPED_NEEDS_CONFIGURATION"
        assert to not in json.dumps(record), "recipient is masked"
    assert not http.calls and not FakeSMTP.sent


def test_mock_mode_proves_the_wiring_without_credentials_or_network(api):
    client, _, http = api
    status = client.put(f"{BASE}/integrations/email", headers=OWNER, json={"enabled": True, "mode": "mock"}).json()
    assert status["status"] == "MOCK" and status["missing"], "mock works without credentials, still lists them"
    sent = client.post(f"{BASE}/integrations/email/test-send", headers=OWNER,
                       json={"to": "owner@example.com", "title": "Hi", "body": "Mock"}).json()
    assert sent["status"] == "MOCK_DELIVERED" and sent["to_masked"] == "ow***@example.com"
    bad = client.post(f"{BASE}/integrations/email/test-send", headers=OWNER, json={"to": "not-an-email"}).json()
    assert bad["status"] == "FAILED" and bad["error"] == "invalid recipient"
    check = client.post(f"{BASE}/integrations/email/check", headers=OWNER).json()
    assert "Mock mode never contacts" in check["note"]
    assert not http.calls and not FakeSMTP.sent, "mock never leaves ASKODOX"
    outbox = client.get(f"{BASE}/outbox", headers=OWNER).json()
    assert outbox["summary"]["email"]["MOCK_DELIVERED"] == 1


def test_whatsapp_real_request_shape_live_check_and_failure(api, monkeypatch):
    client, container, http = api
    monkeypatch.setenv("WHATSAPP_ACCESS_TOKEN", FAKE_TOKEN)
    monkeypatch.setenv("WHATSAPP_PHONE_NUMBER_ID", "1234567890")
    container.platform = None
    client.put(f"{BASE}/integrations/whatsapp_cloud", headers=OWNER, json={"enabled": True, "mode": "test"})
    http.responses = {"/1234567890/messages": (200, {"messages": [{"id": "wamid.TEST"}]}),
                      "/1234567890": (200, {"display_phone_number": "+91 98765 43210", "verified_name": "ASKODOX"})}
    sent = client.post(f"{BASE}/integrations/whatsapp_cloud/test-send", headers=OWNER,
                       json={"to": "9876543210", "title": "Order", "body": "Accepted"}).json()
    assert sent["status"] == "SENT" and sent["provider_ref"] == "wamid.TEST"
    call = http.calls[-1]
    assert call["url"] == "https://graph.facebook.com/v21.0/1234567890/messages"
    assert call["headers"]["Authorization"] == f"Bearer {FAKE_TOKEN}"
    assert call["json"]["to"] == "919876543210" and call["json"]["type"] == "text"
    assert FAKE_TOKEN not in client.get(f"{BASE}/outbox", headers=OWNER).text
    checked = client.post(f"{BASE}/integrations/whatsapp_cloud/check", headers=OWNER).json()
    assert checked["last_check_ok"] == 1 and checked["status"] == "TEST", "TEST until the mode is switched to live"
    live = client.put(f"{BASE}/integrations/whatsapp_cloud", headers=OWNER, json={"mode": "live"}).json()
    assert live["status"] == "TEST", "a config change clears the check"
    client.post(f"{BASE}/integrations/whatsapp_cloud/check", headers=OWNER)
    assert items(client)["whatsapp_cloud"]["status"] == "LIVE"
    http.responses = {"/messages": (401, {"error": {"message": "Invalid OAuth access token."}})}
    failed = client.post(f"{BASE}/integrations/whatsapp_cloud/test-send", headers=OWNER,
                         json={"to": "9876543210"}).json()
    assert failed["status"] == "FAILED" and "Invalid OAuth" in failed["error"]


def test_sms_vendors_and_email_smtp_request_shapes(api):
    client, _, http = api
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"sender_id": "ASKDOX", "dlt_template_id": "flow-1"},
        "secrets": {"api_key": "msg91-test"}})
    http.responses = {"control.msg91.com": (200, {"type": "success", "message": "req-1"})}
    sms = client.post(f"{BASE}/integrations/sms/test-send", headers=OWNER, json={"to": "9876543210"}).json()
    assert sms["status"] == "SENT"
    assert http.calls[-1]["headers"] == {"authkey": "msg91-test"}
    assert http.calls[-1]["json"]["template_id"] == "flow-1"
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={"config": {"vendor": "twilio", "account_sid": "AC1"}})
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={"enabled": True, "mode": "test"})
    http.responses = {"api.twilio.com": (201, {"sid": "SM1"})}
    tw = client.post(f"{BASE}/integrations/sms/test-send", headers=OWNER, json={"to": "+15551234567"}).json()
    assert tw["status"] == "SENT" and http.calls[-1]["auth"] == ("AC1", "msg91-test")

    client.put(f"{BASE}/integrations/email", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"host": "smtp.example.com", "from_address": "no-reply@example.com"},
        "secrets": {"password": "app-password"}})
    mail = client.post(f"{BASE}/integrations/email/test-send", headers=OWNER,
                       json={"to": "owner@example.com", "title": "Hello"}).json()
    assert mail["status"] == "SENT" and FakeSMTP.sent[-1] == {"to": "owner@example.com", "subject": "Hello",
                                                              "host": "smtp.example.com"}
    assert FakeSMTP.logins[-1] == ("no-reply@example.com", True)
    assert "app-password" not in client.get(f"{BASE}/integrations", headers=OWNER).text


def test_notifications_dispatch_through_the_same_outbox(api):
    client, container, _ = api
    from app.api.routes.platform import platform

    pf = platform(container)
    pf.resources.create("notification_templates", {"key": "order_update", "channel": "whatsapp", "language": "en",
                                                   "type": "order", "title": "Order {id}", "body": "Now {state}"},
                        actor="test")
    pf.resources.create("notification_rules", {"name": "Order accepted", "event": "order_accepted",
                                               "template_key": "order_update",
                                               "channels": ["whatsapp"]}, actor="test", status="ACTIVE")
    off = pf.notifications.dispatch("order_accepted", user_ref="app-phone-919876543210", values={"id": 7, "state": "ok"})
    assert off[0]["status"] == "skipped_needs_configuration"
    client.put(f"{BASE}/integrations/whatsapp_cloud", headers=OWNER, json={"enabled": True, "mode": "mock"})
    mocked = pf.notifications.dispatch("order_accepted", user_ref="app-phone-919876543210",
                                       values={"id": 7, "state": "accepted"})
    assert mocked[0]["status"] == "mock_delivered"
    row = pf.outbox.list(channel="whatsapp")[0]
    assert row["title"] == "Order 7" and row["to_masked"] == "***3210" and row["event"] == "order_accepted"


def test_sandbox_gateway_runs_the_online_flow_and_never_exists_in_production(api, monkeypatch):
    client, container, _ = api
    assert items(client)["sandbox_gateway"]["status"] == "DISABLED"
    client.put(f"{BASE}/integrations/sandbox_gateway", headers=OWNER, json={"enabled": True, "mode": "test"})
    payment = client.post(f"{BASE}/payments", headers=OWNER, json={
        "idempotency_key": "sb-1", "method": "upi", "amount": 250, "provider": "sandbox_gateway"}).json()
    assert payment["status"] == "CREATED"
    paid = client.post(f"{BASE}/payments/{payment['id']}/simulate_paid", headers=OWNER, json={}).json()
    assert paid["status"] == "PAID" and paid["provider_ref"].startswith("sandbox_")
    refund = client.post(f"{BASE}/payments/{payment['id']}/refund", headers=OWNER, json={"confirm": True}).json()
    assert refund["status"] == "REFUNDED"
    ready = {r["integration"]: r for r in client.get(f"{BASE}/readiness", headers=OWNER).json()["items"]}
    assert ready["Payment gateway"]["mock_verified"] is True and ready["Payment gateway"]["status"] == "NOT_CONFIGURED"

    monkeypatch.setenv("RAILWAY_ENVIRONMENT_NAME", "production")
    container.platform = None
    assert items(client)["sandbox_gateway"]["status"] == "DISABLED"
    refused = client.post(f"{BASE}/payments", headers=OWNER, json={
        "idempotency_key": "sb-2", "method": "upi", "amount": 250, "provider": "sandbox_gateway"})
    assert refused.status_code == 409
    assert client.post(f"{BASE}/payments/{payment['id']}/simulate_paid", headers=OWNER, json={}).status_code == 409
    assert client.put(f"{BASE}/integrations/sandbox_gateway", headers=OWNER,
                      json={"enabled": True}).status_code == 503


def test_direct_upi_link_goes_to_the_sellers_own_upi_id():
    assert payment_gateway.valid_vpa("ravi.kumar@okicici") and not payment_gateway.valid_vpa("demo@")
    assert not payment_gateway.valid_vpa("javascript:alert(1)@x")
    link = payment_gateway.upi_intent("ravi.kumar@okicici", "Ravi Stores", 499.5, "ASKODOX order 12", "ASKODOX12")
    assert link == ("upi://pay?pa=ravi.kumar@okicici&pn=Ravi%20Stores&am=499.50&cu=INR"
                    "&tn=ASKODOX%20order%2012&tr=ASKODOX12")
    assert payment_gateway.upi_intent("", "x", 10, "n", "r") is None, "no seller UPI ID -> no link, never a demo VPA"


def test_seller_profile_upi_id_is_validated(api):
    client, container, _ = api
    from app.services.session_tokens import issue_token

    token = issue_token("app-phone-919876543210", container.settings.session_token_secret)
    headers = {"Authorization": f"Bearer {token}"}
    assert client.put("/api/me/profile", headers=headers, json={"upi_id": "not a vpa"}).status_code == 422
    saved = client.put("/api/me/profile", headers=headers, json={"upi_id": "ravi.kumar@okicici"})
    assert saved.status_code == 200 and saved.json()["upi_id"] == "ravi.kumar@okicici"


def test_discovered_video_goes_to_review_and_affiliate_video_routes_through_tracked_link(api):
    client, container, _ = api
    from app.api.routes.platform import platform

    pf = platform(container)
    pf.web_videos.save({"ref": "yt_cgQhFuIFREs", "url": "https://www.youtube.com/watch?v=cgQhFuIFREs",
                        "platform": "youtube", "title": "Samsung 43 inch TV review", "creator": "Udrawat",
                        "thumbnail": "https://i.ytimg.com/vi/cgQhFuIFREs/hqdefault.jpg",
                        "products": ["samsung 43 inch tv"], "services": [], "source": "web_search"})
    listed = client.get(f"{BASE}/web-videos", headers=OWNER).json()["items"]
    assert listed[0]["ref"] == "yt_cgQhFuIFREs" and listed[0]["in_review_queue"] is False
    video = client.post(f"{BASE}/web-videos/yt_cgQhFuIFREs/promote", headers=OWNER, json={}).json()
    assert video["status"] == "PENDING_REVIEW" and video["data"]["source_ref"] == "yt_cgQhFuIFREs"
    assert client.post(f"{BASE}/web-videos/yt_cgQhFuIFREs/promote", headers=OWNER, json={}).status_code == 409
    assert pf.videos.rows({"subject": "samsung 43 inch tv"}) == [], "nothing shows before approval"

    program = pf.resources.create("affiliate_programs", {"name": "Test network", "network": "Test network",
                                                        "commission_type": "percent", "commission_percent": 2},
                                  actor="test", status="ACTIVE")
    link = pf.resources.create("affiliate_links", {"program_id": program["id"], "title": "Samsung 43 TV",
                                                   "link_type": "product", "affiliate_url": "https://shop.example.com/tv?tag=t1",
                                                   "keywords": ["samsung tv"]}, actor="test", status="ACTIVE")
    pf.resources.update("videos", video["id"], {"relationship": "affiliate", "affiliate_link_id": link["id"],
                                      "merchant_ref": "app-phone-919999999999"}, actor="test")
    pf.resources.action("videos", video["id"], "approve", actor="test")
    card = pf.videos.rows({"subject": "samsung 43 inch tv"})[0]
    assert card["disclosure"].startswith("Affiliate") and card["shop_redirect_path"].startswith("/go/af/")
    assert card["associated"] == {"seller": True, "provider": False, "creator": None}
    assert "919999999999" not in json.dumps(card), "seller refs never leave the server"
    opened = client.get(card["shop_redirect_path"])
    assert opened.status_code in (302, 307) and opened.headers["location"] == "https://shop.example.com/tv?tag=t1"


def test_readiness_is_computed_from_live_state_and_nothing_is_live(api):
    client, _, _ = api
    body = client.get(f"{BASE}/readiness", headers=OWNER).json()
    rows = {r["integration"]: r for r in body["items"]}
    assert list(rows) == ["Payment gateway", "WhatsApp", "SMS", "Email", "Firebase push", "YouTube Data API",
                          "Affiliate partners"]
    for row in rows.values():
        assert row["status"] != "LIVE" and row["real_credential_required"] is True
        assert row["backend_ready"] and row["admin_control_ready"]
    assert rows["Email"]["mock_verified"] is False
    client.put(f"{BASE}/integrations/email", headers=OWNER, json={"enabled": True, "mode": "mock"})
    client.post(f"{BASE}/integrations/email/test-send", headers=OWNER, json={"to": "owner@example.com"})
    rows = {r["integration"]: r for r in client.get(f"{BASE}/readiness", headers=OWNER).json()["items"]}
    assert rows["Email"]["mock_verified"] is True and rows["Email"]["status"] == "NOT_CONFIGURED", \
        "a mock delivery proves the wiring, never that email is live"
    assert rows["WhatsApp"]["credentials"]["whatsapp_cloud"]["env_vars"]["access_token"] == "WHATSAPP_ACCESS_TOKEN"
