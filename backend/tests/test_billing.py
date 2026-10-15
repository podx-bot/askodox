"""Subscription + Travel Radio billing on the ONE payment layer, in TEST
(sandbox) mode with recorded gateway shapes: testers only, activation only on
a gateway-confirmed PAID (verified checkout signature / signed webhook),
idempotent, refunds cancel only after the gateway confirms, Live mode locked,
Radio stays a separate add-on, no card data anywhere."""
import base64
import dataclasses
import hashlib
import hmac
import json
import time
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-bill-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
BASE = "/admin/cc/platform"
RZP_SECRET, RZP_WHSEC, CF_SECRET = "rzp-test-secret-000000", "rzp-test-whsec-000000", "cf-test-secret-0000000"


class FakeGateways:
    """Recorded request / response shapes of Razorpay and Cashfree."""

    def __init__(self):
        self.calls = []

    def __call__(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if "api.razorpay.com" in url and url.endswith("/orders"):
            return 200, {"id": "order_T" + uuid.uuid4().hex[:10], "status": "created"}
        if "api.razorpay.com" in url and url.endswith("/refund"):
            return 200, {"id": "rfnd_T1", "status": "processed"}
        if "cashfree.com" in url and url.endswith("/refunds"):
            return 200, {"refund_id": kwargs["json"]["refund_id"], "refund_status": "PENDING"}
        if "cashfree.com" in url and "/orders" in url:
            return 200, {"cf_order_id": 123, "order_id": url.rsplit("/", 1)[-1], "payment_session_id": "session_T1"}
        return 404, {}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "bill.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    gateways = FakeGateways()
    monkeypatch.setattr(container, "comms_http", gateways, raising=False)
    for attr in ("platform", "growth_repository", "travel_radio", "billing_store"):
        monkeypatch.setattr(container, attr, None, raising=False)
    monkeypatch.delenv("ASKODOX_PAYMENTS_LIVE_APPROVED", raising=False)
    monkeypatch.delenv("ASKODOX_PAYMENT_PROVIDER", raising=False)
    yield TestClient(app), container, gateways


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _razorpay(client):
    r = client.put(f"{BASE}/integrations/razorpay", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"key_id": "rzp_test_EXAMPLE123"},
        "secrets": {"key_secret": RZP_SECRET, "webhook_secret": RZP_WHSEC}})
    assert r.status_code == 200 and r.json()["status"] == "TEST", r.text


def test_test_mode_is_for_testers_only_and_activation_needs_a_verified_signature(env):
    client, container, gateways = env
    uid, me = _user(container)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "radio_7d"}).json()["detail"] == \
        "NO_PAYMENT_GATEWAY"
    _razorpay(client)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "radio_7d"}).json()["detail"] == \
        "TEST_MODE_TESTERS_ONLY"
    assert client.post("/admin/cc/billing/testers", json={"user_id": uid}).status_code in (401, 403)
    assert client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": uid}).status_code == 200
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "free"}).json()["detail"] == \
        "FREE_PLAN_NO_PAYMENT"
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "radio_7d"}).json()["detail"] == \
        "RADIO_BILLING_OFF", "Radio billing stays off (even for testers) until the Owner switches it on"
    from app.api.routes.command_center import command_center

    command_center(container).set_flag("billing.radio_checkout", True, "test")
    out = client.post("/api/billing/checkout", headers=me, json={"plan_code": "radio_7d"}).json()
    assert out["mode"] == "test" and out["kind"] == "radio" and out["amount"] == 149
    checkout = out["checkout"]
    assert checkout["provider"] == "razorpay" and checkout["key_id"] == "rzp_test_EXAMPLE123"
    assert checkout["amount"] == 14900, "paise"
    assert RZP_SECRET not in json.dumps(out), "secrets never leave the server"
    pid = out["purchase_id"]
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "PENDING"
    bad = client.post("/api/billing/razorpay/verify", headers=me, json={
        "purchase_id": pid, "razorpay_order_id": checkout["order_id"], "razorpay_payment_id": "pay_T1",
        "razorpay_signature": "0" * 64})
    assert bad.status_code == 401
    sig = hmac.new(RZP_SECRET.encode(), f"{checkout['order_id']}|pay_T1".encode(), hashlib.sha256).hexdigest()
    body = {"purchase_id": pid, "razorpay_order_id": checkout["order_id"], "razorpay_payment_id": "pay_T1",
            "razorpay_signature": sig}
    ok = client.post("/api/billing/razorpay/verify", headers=me, json=body).json()
    assert ok["purchase"]["status"] == "TEST_PAID", "TEST money never creates a real entitlement"
    assert client.post("/api/billing/razorpay/verify", headers=me, json=body).json()["purchase"]["status"] == \
        "TEST_PAID", "replays change nothing"
    from app.api.routes.radio import radio

    assert radio(container).current_pass(uid) is None, "TEST purchase: no Radio pass is created"
    other, them = _user(container)
    assert client.post("/api/billing/razorpay/verify", headers=them, json=body).status_code == 404, "own only"

    # Refund: confirmation required, the gateway is asked, the pass ends only on its signed webhook.
    assert client.post(f"/admin/cc/billing/purchases/{pid}/refund", headers=OWNER, json={}).status_code == 409
    asked = client.post(f"/admin/cc/billing/purchases/{pid}/refund", headers=OWNER, json={"confirm": True}).json()
    assert asked["requested"]["refund_id"] == "rfnd_T1"
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "TEST_PAID"
    event = json.dumps({"event": "refund.processed", "payload": {"refund": {"entity": {
        "id": "rfnd_T1", "payment_id": "pay_T1", "amount": 14900}}}}).encode()
    whsig = hmac.new(RZP_WHSEC.encode(), event, hashlib.sha256).hexdigest()
    assert client.post("/api/payments/webhook/razorpay", content=event,
                       headers={"x-razorpay-signature": "0" * 64}).status_code == 401
    done = client.post("/api/payments/webhook/razorpay", content=event,
                       headers={"x-razorpay-signature": whsig, "x-razorpay-event-id": "evt_rf_1"}).json()
    assert done["status"] == "REFUNDED"
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "REFUNDED"
    assert radio(container).current_pass(uid) is None, "still no pass after the refund"


def test_live_mode_is_locked_without_owner_approval(env, monkeypatch):
    client, container, _ = env
    _razorpay(client)
    locked = client.put(f"{BASE}/integrations/razorpay", headers=OWNER, json={"mode": "live"})
    assert locked.status_code in (403, 503) and "LIVE_MODE_LOCKED" in locked.text
    live_key = client.put(f"{BASE}/integrations/razorpay", headers=OWNER,
                          json={"config": {"key_id": "rzp_live_EXAMPLE123"}})
    assert live_key.status_code in (403, 503) and "LIVE_MODE_LOCKED" in live_key.text
    status = client.get("/admin/cc/billing/status", headers=OWNER).json()
    assert status["live_payments_approved"] is False and status["flags"]["billing.live_pricing"] is False
    assert {g["provider"] for g in status["gateways"]} == {"razorpay", "cashfree"}
    assert status["firebase"]["state"] in ("NOT_CONFIGURED", "SERVER_READY_NO_DEVICES", "READY_UNVERIFIED")
    radio_prices = {p["code"]: (p["price"], p["on_sale"]) for p in status["plans"] if p["audience"] == "addon_radio"}
    assert radio_prices == {"radio_1d": (29, False), "radio_7d": (149, False), "radio_30d": (399, False)}
    # A live key that arrives through the environment is refused too (never takes money while locked).
    monkeypatch.setenv("RAZORPAY_KEY_ID", "rzp_live_FROMENV123")
    container.platform = None
    from app.api.routes.platform import platform

    platform(container).registry.env["RAZORPAY_KEY_ID"] = "rzp_live_FROMENV123"
    platform(container).registry.configure("razorpay", actor="t", config={"key_id": ""})
    st = platform(container).registry.status("razorpay")
    assert st["status"] == "ERROR" and st["readiness"] == "LIVE_MODE_LOCKED"


def test_cashfree_sandbox_base_plan_via_signed_webhook(env):
    client, container, gateways = env
    r = client.put(f"{BASE}/integrations/cashfree", headers=OWNER, json={
        "enabled": True, "mode": "test", "config": {"client_id": "TEST1234567890"},
        "secrets": {"client_secret": CF_SECRET}})
    assert r.status_code == 200 and r.json()["status"] == "TEST", r.text
    uid, me = _user(container)
    client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": uid})
    out = client.post("/api/billing/checkout", headers=me, json={"plan_code": "pro"}).json()
    assert out["checkout"]["provider"] == "cashfree" and out["checkout"]["environment"] == "sandbox"
    assert out["checkout"]["payment_session_id"] == "session_T1" and out["kind"] == "base"
    order_call = [c for c in gateways.calls if "sandbox.cashfree.com/pg/orders" in c[1]][0]
    assert order_call[2]["headers"]["x-api-version"] == "2023-08-01"
    assert order_call[2]["json"]["order_amount"] == 999
    order_id = order_call[2]["json"]["order_id"]
    event = json.dumps({"type": "PAYMENT_SUCCESS_WEBHOOK", "data": {
        "order": {"order_id": order_id}, "payment": {"cf_payment_id": 555, "payment_status": "SUCCESS"}}}).encode()
    ts = str(int(time.time() * 1000))
    sig = base64.b64encode(hmac.new(CF_SECRET.encode(), ts.encode() + event, hashlib.sha256).digest()).decode()
    assert client.post("/api/payments/webhook/cashfree", content=event, headers={
        "x-webhook-signature": "bad", "x-webhook-timestamp": ts}).status_code == 401
    old = str(int((time.time() - 3600) * 1000))
    old_sig = base64.b64encode(hmac.new(CF_SECRET.encode(), old.encode() + event, hashlib.sha256).digest()).decode()
    assert client.post("/api/payments/webhook/cashfree", content=event, headers={
        "x-webhook-signature": old_sig, "x-webhook-timestamp": old}).status_code == 401, "stale replays refused"
    ok = client.post("/api/payments/webhook/cashfree", content=event, headers={
        "x-webhook-signature": sig, "x-webhook-timestamp": ts}).json()
    assert ok["status"] == "PAID"
    assert client.get(f"/api/billing/purchases/{out['purchase_id']}", headers=me).json()["purchase"]["status"] == \
        "TEST_PAID"
    from app.api.routes.growth import growth

    sub = growth(container).current_subscription(uid)
    assert sub is None or sub["plan_code"] != "pro", "TEST money never activates a paid plan"
    again = client.post("/api/payments/webhook/cashfree", content=event, headers={
        "x-webhook-signature": sig, "x-webhook-timestamp": ts}).json()
    assert again["duplicate"] is True, "idempotent"
    # The Radio add-on never replaces the base plan.
    from app.services import billing

    assert billing.store(container).list(user_id=uid)[0]["kind"] == "base"


def test_no_card_data_is_ever_stored(env):
    client, container, _ = env
    _razorpay(client)
    uid, me = _user(container)
    client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": uid})
    client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"})
    import sqlite3

    with sqlite3.connect(container.settings.database_path) as conn:
        cols = {r[1] for t in ("billing_purchases", "pf_payments") for r in conn.execute(f"PRAGMA table_info({t})")}
    assert not cols & {"card_number", "cvv", "pan", "card", "upi_pin", "expiry"}
