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
FAKE_TWILIO_SID = "AC" + "0" * 32  # format-valid, obviously fake (built at runtime)


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
                "FIREBASE_SERVICE_ACCOUNT_JSON", "YOUTUBE_API_KEY", "YOUTUBE_DATA_API_KEY", "RAILWAY_ENVIRONMENT_NAME", "SMS_API_KEY",
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
        "enabled": True, "mode": "test", "config": {"sender_id": "ASKDOX", "dlt_template_id": "flow001"},
        "secrets": {"api_key": "msg91-test-key-000000"}})
    http.responses = {"control.msg91.com": (200, {"type": "success", "message": "req-1"})}
    sms = client.post(f"{BASE}/integrations/sms/test-send", headers=OWNER, json={"to": "9876543210"}).json()
    assert sms["status"] == "SENT"
    assert http.calls[-1]["headers"] == {"authkey": "msg91-test-key-000000"}
    assert http.calls[-1]["json"]["template_id"] == "flow001"
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={"config": {"vendor": "twilio", "account_sid": FAKE_TWILIO_SID}})
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={"enabled": True, "mode": "test"})
    http.responses = {"api.twilio.com": (201, {"sid": "SM1"})}
    tw = client.post(f"{BASE}/integrations/sms/test-send", headers=OWNER, json={"to": "+15551234567"}).json()
    assert tw["status"] == "SENT" and http.calls[-1]["auth"] == (FAKE_TWILIO_SID, "msg91-test-key-000000")

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
                          "Affiliate partners", "Social auto-DM (Facebook / Instagram)", "Web search (Brave)"]
    dm = rows.pop("Social auto-DM (Facebook / Instagram)")
    assert dm["status"] == "NOT_CONFIGURED" and dm["mock_verified"] is False and "App Review" in dm["external_setup"]
    assert rows["Affiliate partners"]["product_apis"]["meesho"] == "NOT_AVAILABLE"
    # Web search reports the live provider's last answer (never a hand-set flag).
    web = rows.pop("Web search (Brave)")
    assert web["health"] in ("LIVE", "CONFIGURED", "DEGRADED", "NEEDS_CONFIGURATION", "CHECK_FAILED")
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


# ------------------------------------------------ validation / Razorpay ----

RZP_KEY_ID = "rzp_test_ABCDEFGH1234"
RZP_SECRET = "rzp-key-secret-" + "0" * 8
RZP_WEBHOOK = "rzp-webhook-secret-00000"


def test_malformed_credentials_are_rejected_without_echoing_them(api):
    client, _, _ = api
    bad = client.put(f"{BASE}/integrations/razorpay", headers=OWNER,
                     json={"config": {"key_id": "sk_live_WRONGFIELD"}})
    assert bad.status_code in (400, 409, 422) and "key_id" in bad.text and "WRONGFIELD" not in bad.text
    bad_fcm = client.put(f"{BASE}/integrations/fcm_push", headers=OWNER,
                         json={"secrets": {"service_account_json": '{"type": "not-a-service-account"}'}})
    assert bad_fcm.status_code in (400, 409, 422) and "service-account" in bad_fcm.text
    bad_mail = client.put(f"{BASE}/integrations/email", headers=OWNER, json={"config": {"from_address": "nope"}})
    assert bad_mail.status_code in (400, 409, 422)
    good = client.put(f"{BASE}/integrations/fcm_push", headers=OWNER, json={"secrets": {"service_account_json": json.dumps(
        {"type": "service_account", "project_id": "p", "client_email": "a@p.iam.gserviceaccount.com",
         "private_key": "-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----\n"})}})
    assert good.status_code == 200 and good.json()["missing"] == []


def _razorpay(client, http):
    client.put(f"{BASE}/integrations/razorpay", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"key_id": RZP_KEY_ID},
        "secrets": {"key_secret": RZP_SECRET, "webhook_secret": RZP_WEBHOOK}})
    http.responses = {"api.razorpay.com/v1/orders": (200, {"id": "order_TEST123", "status": "created"})}


def _signed(event: dict):
    import hashlib
    import hmac

    body = json.dumps(event).encode()
    return body, hmac.new(RZP_WEBHOOK.encode(), body, hashlib.sha256).hexdigest()


def test_razorpay_order_checkout_and_native_webhooks(api, monkeypatch):
    client, container, http = api
    _razorpay(client, http)
    payment = client.post(f"{BASE}/payments", headers=OWNER, json={
        "idempotency_key": "rzp-1", "method": "upi", "amount": 499.5, "provider": "razorpay",
        "order_ref": "order:77"}).json()
    call = http.calls[-1]
    assert call["url"] == "https://api.razorpay.com/v1/orders" and call["auth"] == (RZP_KEY_ID, RZP_SECRET)
    assert call["json"]["amount"] == 49950 and call["json"]["receipt"] == payment["id"]
    assert payment["checkout"] == {"provider": "razorpay", "key_id": RZP_KEY_ID, "order_id": "order_TEST123",
                                   "amount": 49950, "currency": "INR"}
    assert RZP_SECRET not in json.dumps(payment)

    synced = []
    monkeypatch.setattr(container, "order_repository",
                        type("Orders", (), {"update_fields": lambda self, oid, **kw: synced.append((oid, kw))})())
    event = {"entity": "event", "event": "payment.captured", "payload": {"payment": {"entity": {
        "id": "pay_TEST1", "order_id": "order_TEST123", "amount": 49950, "status": "captured"}}}}
    body, sig = _signed(event)
    assert client.post("/api/payments/webhook/razorpay", content=body,
                       headers={"x-razorpay-signature": "0" * 64}).status_code == 401
    ok = client.post("/api/payments/webhook/razorpay", content=body,
                     headers={"x-razorpay-signature": sig, "x-razorpay-event-id": "evt_1"}).json()
    assert ok["status"] == "PAID" and not ok["duplicate"]
    assert synced and synced[0][0] == 77 and synced[0][1]["payment_state"] == "VERIFIED" \
        and synced[0][1]["payment_verified_by"] == "gateway", "the customer's order is marked paid by the gateway"
    replay = client.post("/api/payments/webhook/razorpay", content=body,
                         headers={"x-razorpay-signature": sig, "x-razorpay-event-id": "evt_1"}).json()
    assert replay["duplicate"] is True
    refund = {"event": "refund.processed", "payload": {"refund": {"entity": {
        "id": "rfnd_1", "payment_id": "pay_TEST1", "amount": 10000}}}}
    body, sig = _signed(refund)
    refunded = client.post("/api/payments/webhook/razorpay", content=body,
                           headers={"x-razorpay-signature": sig, "x-razorpay-event-id": "evt_2"}).json()
    assert refunded["status"] == "PARTIALLY_REFUNDED"
    body, sig = _signed({"event": "settlement.processed", "payload": {}})
    assert client.post("/api/payments/webhook/razorpay", content=body,
                       headers={"x-razorpay-signature": sig}).json()["ignored"] is True


def test_razorpay_checkout_signature_verification(api):
    import hashlib
    import hmac

    client, container, http = api
    _razorpay(client, http)
    from app.api.routes.platform import platform

    pf = platform(container)
    payment = client.post(f"{BASE}/payments", headers=OWNER, json={
        "idempotency_key": "rzp-2", "method": "upi", "amount": 100, "provider": "razorpay"}).json()
    with pytest.raises(PermissionError):
        pf.razorpay.verify_checkout("order_TEST123", "pay_X", "0" * 64)
    good = hmac.new(RZP_SECRET.encode(), b"order_TEST123|pay_X", hashlib.sha256).hexdigest()
    result = pf.razorpay.verify_checkout("order_TEST123", "pay_X", good)
    assert result["payment"]["status"] == "PAID" and result["payment"]["id"] == payment["id"]
    assert pf.razorpay.verify_checkout("order_TEST123", "pay_X", good)["duplicate"] is True


def test_online_order_payment_is_refused_without_a_gateway(api):
    client, container, _ = api
    from app.api.routes.platform import platform

    assert platform(container).checkout_provider() is None, "no gateway configured -> no online payment offered"


# -------------------------------------------------- comms hardening ----

def test_whatsapp_webhook_signature_is_enforced_once_the_app_secret_is_set(api, monkeypatch):
    import hashlib
    import hmac

    client, container, http = api
    statuses = {"entry": [{"changes": [{"value": {"statuses": [{"id": "wamid.TEST", "status": "delivered",
                                                               "recipient_id": "919876543210"}]}}]}]}
    body = json.dumps(statuses).encode()
    assert client.post("/webhook", content=body, headers={"content-type": "application/json"}).status_code == 200, \
        "without an app secret the endpoint behaves exactly as before"
    monkeypatch.setenv("WHATSAPP_APP_SECRET", "meta-app-secret-000000")
    container.platform = None
    from app.api.routes.platform import platform

    pf = platform(container)
    pf.outbox.record(channel="whatsapp", provider="whatsapp_cloud", status="SENT", provider_ref="wamid.TEST",
                     title="t", body="b", to_masked="***3210")
    assert client.post("/webhook", content=body, headers={"content-type": "application/json"}).status_code == 401
    sig = "sha256=" + hmac.new(b"meta-app-secret-000000", body, hashlib.sha256).hexdigest()
    assert client.post("/webhook", content=body, headers={"content-type": "application/json",
                                                          "x-hub-signature-256": sig}).status_code == 200
    row = pf.outbox.list(channel="whatsapp")[0]
    assert row["delivery_status"] == "delivered", "provider receipts land on the message ASKODOX sent"


def test_customer_opt_out_wins_and_contacts_resolve_from_the_real_id(api):
    client, container, _ = api
    from app.api.routes.platform import notify, platform
    from app.services.session_tokens import issue_token

    pf = platform(container)
    pf.resources.create("notification_templates", {"key": "offer", "channel": "sms", "language": "en",
                                                   "type": "offer", "title": "Offer", "body": "{x}"}, actor="t")
    pf.resources.create("notification_rules", {"name": "Offer", "event": "offer_live", "template_key": "offer",
                                               "channels": ["sms"]}, actor="t", status="ACTIVE")
    client.put(f"{BASE}/integrations/sms", headers=OWNER, json={"enabled": True, "mode": "mock"})
    user = "app-phone-919876543210"
    first = notify(container, "offer_live", user, {"x": "10% off"})
    assert first[0]["status"] == "mock_delivered", "the number is found from the real id, not the opaque ref"
    row = pf.outbox.list(channel="sms")[0]
    assert row["to_masked"] == "***3210" and row["user_ref"] != user, "outbox keeps only the opaque reference"
    headers = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    prefs = client.put("/api/me/notification-channels", headers=headers, json={"sms": False}).json()
    assert prefs["channels"]["sms"] is False and prefs["channels"]["whatsapp"] is True
    assert notify(container, "offer_live", user, {"x": "10% off"})[0]["status"] == "skipped_opted_out"
    assert client.get(f"{BASE}/outbox", headers=OWNER).json()["opt_outs"] == {"sms": 1}


def test_transient_provider_errors_are_retried_once(api, monkeypatch):
    client, container, http = api
    monkeypatch.setenv("WHATSAPP_ACCESS_TOKEN", FAKE_TOKEN)
    monkeypatch.setenv("WHATSAPP_PHONE_NUMBER_ID", "1234567890")
    container.platform = None
    client.put(f"{BASE}/integrations/whatsapp_cloud", headers=OWNER, json={"enabled": True, "mode": "test"})
    replies = [(503, {"error": {"message": "temporarily unavailable"}}), (200, {"messages": [{"id": "wamid.R"}]})]
    http.responses = {}
    http.__class__ = type("Seq", (FakeHttp,), {"__call__": lambda self, m, u, **k: (self.calls.append(u), replies.pop(0))[1]})
    sent = client.post(f"{BASE}/integrations/whatsapp_cloud/test-send", headers=OWNER, json={"to": "9876543210"}).json()
    assert sent["status"] == "SENT" and sent["attempts"] == 2
    replies[:] = [(400, {"error": {"message": "bad number"}})]
    failed = client.post(f"{BASE}/integrations/whatsapp_cloud/test-send", headers=OWNER,
                         json={"to": "9876543210"}).json()
    assert failed["status"] == "FAILED" and failed["attempts"] == 1, "a permanent error is not retried"


# ------------------------------------------------ YouTube quota / readiness --

def test_youtube_daily_quota_cap_falls_back_to_web_videos(api, monkeypatch):
    client, container, _ = api
    monkeypatch.setenv("YOUTUBE_API_KEY", "AIza" + "A" * 35)
    monkeypatch.setenv("ASKODOX_YOUTUBE_DAILY_UNITS", "150")
    container.platform = None
    from app.api.routes.platform import enrich_discovery_videos, platform

    calls = []
    monkeypatch.setattr(container, "video_fetcher", lambda url, params: (calls.append(url), (200, {"items": []}))[1],
                        raising=False)
    first = enrich_discovery_videos(container, {"subject": "redmi note 13"}, [], wants_videos=True)
    second = enrich_discovery_videos(container, {"subject": "tata nexon"}, [], wants_videos=True)
    assert first["youtube_data"] in ("ok", "no_results") and second["youtube_data"] == "quota_exhausted"
    status = platform(container).registry.status("youtube_data")
    assert status["quota"] == {"used_today": 101, "daily_cap": 150}


def test_public_readiness_shows_status_words_only(api, monkeypatch):
    client, container, _ = api
    monkeypatch.setenv("WHATSAPP_ACCESS_TOKEN", FAKE_TOKEN)
    container.platform = None
    body = client.get("/readiness").json()
    assert body["integrations"]["whatsapp_cloud"] == "NEEDS_CONFIGURATION"
    assert body["integrations"]["razorpay"] == "NEEDS_CONFIGURATION" and "direct_settlement" not in body["integrations"]
    assert FAKE_TOKEN not in json.dumps(body) and "missing" not in json.dumps(body)


# --- YouTube key under either Railway name (regression: staging console said
# "Missing: api_key" while production carried YOUTUBE_API_KEY). Keys below are
# format-valid fixtures built at runtime, never real.
FAKE_YT = "AIza" + "T" * 35
FAKE_YT_2 = "AIza" + "U" * 35


@pytest.mark.parametrize("names", [("YOUTUBE_API_KEY",), ("YOUTUBE_DATA_API_KEY",),
                                   ("YOUTUBE_API_KEY", "YOUTUBE_DATA_API_KEY")])
def test_youtube_key_under_either_name_is_configured_and_live_after_a_real_check(api, monkeypatch, caplog, names):
    """The exact path the console uses: GET /admin/cc/platform/integrations and
    POST /admin/cc/platform/integrations/youtube_data/check. No enable step:
    the runtime uses the key as soon as it exists, so the status must too."""
    import logging

    caplog.set_level(logging.DEBUG)
    client, container, http = api
    for var in names:
        monkeypatch.setenv(var, FAKE_YT)
    container.platform = None
    yt = items(client)["youtube_data"]
    assert yt["missing"] == [] and yt["sources"]["api_key"] == "environment"
    assert yt["status"] == "TEST" and yt["readiness"] == "CONFIGURED", "never LIVE before a real check"
    assert "YOUTUBE_DATA_API_KEY" in yt["env_aliases"]["api_key"]
    http.responses = {"youtube/v3/videos": (200, {"items": [{"id": "dQw4w9WgXcQ"}]})}
    checked = client.post(f"{BASE}/integrations/youtube_data/check", headers=OWNER)
    assert checked.status_code == 200 and FAKE_YT not in checked.text
    assert http.calls[-1]["params"]["key"] == FAKE_YT
    yt = items(client)["youtube_data"]
    assert yt["status"] == "LIVE" and yt["readiness"] == "LIVE" and yt["missing"] == []
    page = client.get(f"{BASE}/integrations", headers=OWNER).text
    public = client.get("/readiness").text
    assert FAKE_YT not in page and FAKE_YT not in public and "runtime" in page
    assert '"youtube_data":"LIVE"' in public.replace(" ", "")
    http.responses = {"youtube/v3/videos": (403, {"error": {"message": "API key not valid."}})}
    client.post(f"{BASE}/integrations/youtube_data/check", headers=OWNER)
    assert items(client)["youtube_data"]["readiness"] == "CHECK_FAILED"
    assert FAKE_YT not in caplog.text, "the key must never reach the logs"


def test_youtube_missing_only_when_neither_name_is_set(api):
    client, container, http = api
    yt = items(client)["youtube_data"]
    assert yt["missing"] == ["api_key"] and yt["readiness"] == "NOT_CONFIGURED"
    assert yt["status"] == "NEEDS_CONFIGURATION"
    checked = client.post(f"{BASE}/integrations/youtube_data/check", headers=OWNER).json()
    assert checked["last_check_detail"] == "missing: api_key" and not http.calls


def test_youtube_prefers_the_well_formed_key_when_both_names_are_set(monkeypatch):
    from app.services import commerce_finance as fin
    from app.services.social_video_api_service import SocialVideoApiService

    env = {"YOUTUBE_API_KEY": "not-a-key", "YOUTUBE_DATA_API_KEY": FAKE_YT_2}
    assert fin.youtube_api_key(env) == FAKE_YT_2
    assert fin.youtube_api_key({"YOUTUBE_API_KEY": FAKE_YT}) == FAKE_YT
    assert fin.youtube_api_key({}) == ""
    monkeypatch.delenv("YOUTUBE_API_KEY", raising=False)
    monkeypatch.setenv("YOUTUBE_DATA_API_KEY", FAKE_YT_2)
    assert SocialVideoApiService().status()[0]["configured"] is True


def test_classic_command_center_youtube_state_uses_the_same_resolution(api, monkeypatch):
    client, container, http = api
    from app.api.routes.command_center import _integration_states

    monkeypatch.setenv("YOUTUBE_API_KEY", FAKE_YT)
    state = next(s for s in _integration_states(container) if s["name"] == "youtube_data_api")
    assert state["configured"] is True
    monkeypatch.delenv("YOUTUBE_API_KEY")
    state = next(s for s in _integration_states(container) if s["name"] == "youtube_data_api")
    assert state["configured"] is False
