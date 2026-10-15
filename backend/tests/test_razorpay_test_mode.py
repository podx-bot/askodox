"""Razorpay TEST mode end to end, with credentials coming ONLY from the
deployment variables RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET (as on Railway),
against recorded Razorpay request / response shapes (no network, no money):

hosted checkout page, server-side amounts, signature verification, invalid
signatures, cancellation, failed attempts with retry, pending + read-back
reconciliation, expiry, duplicate / mismatched webhooks, refund status read
back (never issued by reconciliation), Live keys locked, Radio billing off,
the public health row, and the audit trail."""
import dataclasses
import hashlib
import hmac
import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-rzp-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
KEY_ID, KEY_SECRET, WH_SECRET = "rzp_test_ENVKEY12345", "env-test-secret-0000000", "env-test-whsec-0000000"


class Razorpay:
    """Recorded Razorpay shapes; `attempts` / `refunds` are what Razorpay would report."""

    def __init__(self):
        self.calls, self.attempts, self.refunds, self.key_ok = [], {}, {}, True

    def __call__(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        assert kwargs.get("auth") == (KEY_ID, KEY_SECRET), "Basic auth with the env key pair"
        path = url.split("api.razorpay.com/v1", 1)[-1]
        if method == "GET" and path == "/payments":
            return (200, {"items": []}) if self.key_ok else (401, {"error": {"description": "Authentication failed"}})
        if method == "POST" and path == "/orders":
            return 200, {"id": "order_T" + uuid.uuid4().hex[:10], "status": "created",
                         "amount": kwargs["json"]["amount"]}
        if method == "GET" and path.startswith("/orders/") and path.endswith("/payments"):
            return 200, {"items": self.attempts.get(path.split("/")[2], [])}
        if method == "GET" and path.endswith("/refunds"):
            return 200, {"items": self.refunds.get(path.split("/")[2], [])}
        if method == "POST" and path.endswith("/refund"):
            return 200, {"id": "rfnd_T9", "status": "pending"}
        return 404, {}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "rzp.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    rzp = Razorpay()
    monkeypatch.setattr(container, "comms_http", rzp, raising=False)
    for attr in ("platform", "growth_repository", "travel_radio", "billing_store"):
        monkeypatch.setattr(container, attr, None, raising=False)
    for name in ("ASKODOX_PAYMENTS_LIVE_APPROVED", "ASKODOX_PAYMENT_PROVIDER", "CASHFREE_CLIENT_ID",
                 "CASHFREE_CLIENT_SECRET", "RAZORPAY_WEBHOOK_SECRET"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("RAZORPAY_KEY_ID", KEY_ID)
    monkeypatch.setenv("RAZORPAY_KEY_SECRET", KEY_SECRET)
    from app.api.routes import health

    health._RZP_HEALTH.clear()
    yield TestClient(app), container, rzp


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _tester(client, container):
    uid, me = _user(container)
    assert client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": uid}).status_code == 200
    return uid, me


def _buy(client, me, plan="plus"):
    r = client.post("/api/billing/checkout", headers=me, json={"plan_code": plan, "amount": 1})
    assert r.status_code == 200, r.text
    out = r.json()
    return out, out["pay_url"].split("?t=", 1)[1]


def _sig(order_id, pay_id):
    return hmac.new(KEY_SECRET.encode(), f"{order_id}|{pay_id}".encode(), hashlib.sha256).hexdigest()


def _webhook(client, event, event_id):
    body = json.dumps(event).encode()
    sig = hmac.new(WH_SECRET.encode(), body, hashlib.sha256).hexdigest()
    return client.post("/api/payments/webhook/razorpay", content=body,
                       headers={"x-razorpay-signature": sig, "x-razorpay-event-id": event_id})


def _captured(order_id, pay_id, paise, event="payment.captured"):
    return {"event": event, "payload": {"payment": {"entity": {"id": pay_id, "order_id": order_id, "amount": paise,
                                                               "currency": "INR", "status": "captured"}}}}


def test_env_keys_enable_test_mode_and_the_hosted_checkout_pays_on_a_verified_signature(env):
    client, container, rzp = env
    status = client.get("/admin/cc/billing/status", headers=OWNER).json()
    gw = {g["provider"]: g for g in status["gateways"]}["razorpay"]
    assert gw["status"] == "TEST" and gw["mode"] == "test" and gw["key_kind"] == "test"
    assert gw["enabled_by"] == "environment" and status["checkout_provider"] == "razorpay"
    assert "webhook_secret" not in gw["missing"], "optional: checkout signature + read-back still confirm"
    assert KEY_SECRET not in json.dumps(status)

    stranger, them = _user(container)
    opts = client.get("/api/billing/options", headers=them).json()
    assert opts["mode"] == "test" and not any(i["payable"] for i in opts["items"])
    assert client.post("/api/billing/checkout", headers=them, json={"plan_code": "plus"}).json()["detail"] == \
        "TEST_MODE_TESTERS_ONLY"

    uid, me = _tester(client, container)
    opts = {i["plan_code"]: i for i in client.get("/api/billing/options", headers=me).json()["items"]}
    assert opts["plus"]["payable"] is True and opts["free"]["reason"] == "FREE_PLAN_NO_PAYMENT"
    assert opts["radio_7d"]["reason"] == "RADIO_BILLING_OFF", "Radio billing stays disabled"

    out, token = _buy(client, me)
    assert out["amount"] == 499 and out["checkout"]["amount"] == 49900, "server price, client amount ignored"
    order = [c for c in rzp.calls if c[0] == "POST" and c[1].endswith("/orders")][-1]
    assert order[2]["json"]["amount"] == 49900 and order[2]["json"]["currency"] == "INR"
    pid, order_id = out["purchase_id"], out["checkout"]["order_id"]

    page = client.get(f"/billing/pay/{pid}?t={token}")
    assert page.status_code == 200 and "TEST MODE" in page.text and order_id in page.text and KEY_ID in page.text
    assert "49900" in page.text and KEY_SECRET not in page.text
    assert "checkout.razorpay.com" in page.headers["content-security-policy"]
    assert client.get(f"/billing/pay/{pid}?t=1.forged").status_code == 404
    assert client.get(f"/billing/pay/{pid}?t=1000.{token.split('.', 1)[1]}").status_code == 404, "expired link"

    bad = client.post(f"/api/billing/pay/{pid}/verify", json={
        "t": token, "razorpay_order_id": order_id, "razorpay_payment_id": "pay_A1", "razorpay_signature": "0" * 64})
    assert bad.status_code == 401
    other = client.post(f"/api/billing/pay/{pid}/verify", json={
        "t": token, "razorpay_order_id": "order_OTHER", "razorpay_payment_id": "pay_A1",
        "razorpay_signature": _sig("order_OTHER", "pay_A1")})
    assert other.status_code == 409, "a signature for another order never pays this one"
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "PENDING"

    good = {"t": token, "razorpay_order_id": order_id, "razorpay_payment_id": "pay_A1",
            "razorpay_signature": _sig(order_id, "pay_A1")}
    assert client.post(f"/api/billing/pay/{pid}/verify", json=good).json()["purchase"]["status"] == "TEST_PAID"
    assert client.post(f"/api/billing/pay/{pid}/verify", json=good).json()["purchase"]["status"] == "TEST_PAID"
    from app.api.routes.growth import growth

    subs = [s for s in growth(container).subscriptions() if s["user_id"] == uid]
    assert subs == [], "TEST money never creates a real paid entitlement (and replays change nothing)"
    detail = client.get(f"/admin/cc/billing/purchases/{pid}", headers=OWNER).json()
    events = [e["event"] for e in detail["events"]]
    assert events[0] == "checkout_started" and events.count("verify_rejected") == 2
    assert events.count("test_paid_no_entitlement") == 1 and "activated" not in events
    assert "4111" not in json.dumps(detail) and "cvv" not in json.dumps(detail).lower()
    assert [i["status"] for i in client.get("/api/billing/purchases/mine", headers=me).json()["items"]] == ["TEST_PAID"]


def test_cancel_then_late_capture_still_activates_and_duplicates_change_nothing(env, monkeypatch):
    client, container, rzp = env
    monkeypatch.setenv("RAZORPAY_WEBHOOK_SECRET", WH_SECRET)
    container.platform = None
    uid, me = _tester(client, container)
    out, token = _buy(client, me)
    pid, order_id = out["purchase_id"], out["checkout"]["order_id"]
    assert client.post(f"/api/billing/pay/{pid}/cancel", json={"t": token}).json()["purchase"]["status"] == \
        "CANCELLED"
    # A failed attempt: the customer may retry on the same order (payment stays PENDING).
    failed = _webhook(client, {"event": "payment.failed", "payload": {"payment": {"entity": {
        "id": "pay_F1", "order_id": order_id, "amount": 49900, "error_description": "Payment declined"}}}}, "evt_f1")
    assert failed.json()["attempt_failed"] is True and failed.json()["status"] == "PENDING"
    # Wrong amount: never PAID.
    wrong = _webhook(client, _captured(order_id, "pay_W1", 100), "evt_w1").json()
    assert wrong["mismatch"] is True and wrong["status"] == "PENDING"
    ok = _webhook(client, _captured(order_id, "pay_C1", 49900), "evt_c1").json()
    assert ok["status"] == "PAID"
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "TEST_PAID", \
        "money taken after the checkout was closed is honoured"
    again = _webhook(client, _captured(order_id, "pay_C1", 49900), "evt_c1").json()
    assert again["duplicate"] is True
    order_paid = _webhook(client, {"event": "order.paid", "payload": {
        "order": {"entity": {"id": order_id, "amount_paid": 49900, "currency": "INR"}},
        "payment": {"entity": {"id": "pay_C1", "order_id": order_id, "amount": 49900}}}}, "evt_o1").json()
    assert order_paid["duplicate"] is True, "second confirmation of the same payment changes nothing"
    body = json.dumps(_captured(order_id, "pay_C1", 49900)).encode()
    assert client.post("/api/payments/webhook/razorpay", content=body,
                       headers={"x-razorpay-signature": "f" * 64}).status_code == 401
    events = [e["event"] for e in client.get(f"/admin/cc/billing/purchases/{pid}", headers=OWNER).json()["events"]]
    assert events.count("test_paid_no_entitlement") == 1 and "checkout_closed" in events
    assert "attempt_failed" in events and "amount_mismatch" in events


def test_pending_is_read_back_from_razorpay_expires_and_refunds_are_only_read(env):
    client, container, rzp = env
    uid, me = _tester(client, container)
    out, _ = _buy(client, me)
    pid, order_id = out["purchase_id"], out["checkout"]["order_id"]
    # No webhook secret, app closed before the callback: still PENDING until Razorpay says captured.
    rzp.attempts[order_id] = [{"id": "pay_P1", "status": "authorized", "amount": 49900, "currency": "INR"}]
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "PENDING"
    rzp.attempts[order_id] = [{"id": "pay_P0", "status": "failed", "amount": 49900, "currency": "INR"},
                              {"id": "pay_P1", "status": "captured", "amount": 49900, "currency": "INR"}]
    assert client.get(f"/api/billing/purchases/{pid}", headers=me).json()["purchase"]["status"] == "TEST_PAID"

    # Refund status: read back only. Reconciliation never POSTs to Razorpay.
    posts_before = [c for c in rzp.calls if c[0] == "POST"]
    rzp.refunds["pay_P1"] = [{"id": "rfnd_X", "status": "processed", "amount": 49900}]
    assert client.post(f"/admin/cc/billing/purchases/{pid}/reconcile").status_code in (401, 403)
    rec = client.post(f"/admin/cc/billing/purchases/{pid}/reconcile", headers=OWNER).json()
    assert rec["purchase"]["status"] == "REFUNDED" and rec["gateway"]["gateway_state"] == "captured"
    assert [c for c in rzp.calls if c[0] == "POST"] == posts_before, "no refund / capture is ever issued"

    # A purchase nobody paid for expires after 24 h (a late capture would still count).
    out2, _ = _buy(client, me)
    from app.services import billing

    old = (datetime.now(timezone.utc) - timedelta(hours=25)).isoformat()
    billing.store(container).update(out2["purchase_id"], created_at=old)
    got = client.get(f"/api/billing/purchases/{out2['purchase_id']}", headers=me).json()["purchase"]
    assert got["status"] == "EXPIRED"
    assert client.get(f"/api/billing/purchases/{out2['purchase_id']}",
                      headers=_user(container)[1]).status_code == 404, "own purchases only"


def test_live_key_in_the_environment_is_locked_and_health_never_shows_secrets(env, monkeypatch):
    client, container, rzp = env
    rows = {r["integration"]: r for r in client.get("/health/integrations").json()["items"]}
    rz = rows["Razorpay"]
    assert rz["state"] == "TEST_MODE_READY" and rz["key_kind"] == "test" and rz["key_check"] == "OK"
    assert rz["webhook_signing"] == "not set" and rz["mode"] == "test" and rz["checkout_ready"] is True
    text = json.dumps(rows)
    assert KEY_SECRET not in text and KEY_ID not in text, "not even the public key id is published"

    monkeypatch.setenv("RAZORPAY_KEY_ID", "rzp_live_ENVKEY12345")
    container.platform = None
    from app.api.routes import health

    health._RZP_HEALTH.clear()
    calls = len(rzp.calls)
    rz = {r["integration"]: r for r in client.get("/health/integrations").json()["items"]}["Razorpay"]
    assert rz["state"] == "LIVE_MODE_LOCKED" and rz["key_kind"] == "live"
    assert len(rzp.calls) == calls, "a locked live key is never used"
    uid, me = _tester(client, container)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).json()["detail"] == \
        "NO_PAYMENT_GATEWAY"


def test_rejected_keys_show_key_check_failed(env):
    client, container, rzp = env
    rzp.key_ok = False
    rz = {r["integration"]: r for r in client.get("/health/integrations").json()["items"]}["Razorpay"]
    assert rz["state"] == "KEY_CHECK_FAILED" and rz["key_check"] == "FAILED"


def test_staff_configuration_overrides_the_environment(env):
    client, container, _ = env
    r = client.put("/admin/cc/platform/integrations/razorpay", headers=OWNER, json={"enabled": False})
    assert r.status_code == 200 and r.json()["status"] == "DISABLED", "staff switch-off wins over env credentials"
    uid, me = _tester(client, container)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).json()["detail"] == \
        "NO_PAYMENT_GATEWAY"


def test_gateway_check_is_read_only_shared_and_verifies_readiness(env, monkeypatch):
    client, container, rzp = env
    assert client.post("/admin/cc/api-billing/razorpay/check").status_code in (401, 403)
    posts = len([c for c in rzp.calls if c[0] == "POST"])
    out = client.post("/admin/cc/api-billing/razorpay/check", headers=OWNER).json()
    assert out["state"] == "TEST_MODE_VERIFIED" and out["key_check"] == "OK" and out["key_kind"] == "test"
    assert out["checkout_ready"] is True and out["webhook_signing"] == "not set"
    assert len([c for c in rzp.calls if c[0] == "POST"]) == posts, "the check never creates anything"
    gets = [c for c in rzp.calls if c[0] == "GET" and c[1].endswith("/payments")]
    assert gets and gets[-1][2]["params"] == {"count": 1}
    text = json.dumps(out)
    assert KEY_SECRET not in text and KEY_ID not in text
    again = client.post("/admin/cc/api-billing/razorpay/check", headers=OWNER).json()
    assert len([c for c in rzp.calls if c[0] == "GET" and c[1].endswith("/payments")]) == len(gets), \
        "at most one fresh call per minute"
    assert again["state"] == "TEST_MODE_VERIFIED"
    # The same state on API Health & Billing and Integration readiness (no more "not verified").
    row = {p["provider"]: p for p in client.get("/admin/cc/api-billing", headers=OWNER).json()["providers"]}["razorpay"]
    assert row["state"] == "TEST_MODE_VERIFIED" and row["gateway"]["key_check"] == "OK"
    assert row["failure_type"] is None and KEY_SECRET not in json.dumps(row)
    items = client.get("/admin/cc/platform/readiness", headers=OWNER).json()["items"]
    pay = {i["integration"]: i for i in items}["Payment gateway"]
    assert pay["status"] == "TEST_MODE_VERIFIED" and pay["health"] == "TEST_VERIFIED"
    # Recording the check keeps the env-enabled gateway usable.
    uid, me = _tester(client, container)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).status_code == 200


def test_rejected_keys_switch_checkout_off_and_show_credential_error(env):
    client, container, rzp = env
    rzp.key_ok = False
    out = client.post("/admin/cc/api-billing/razorpay/check", headers=OWNER).json()
    assert out["state"] == "CREDENTIAL_ERROR" and out["checkout_ready"] is False
    uid, me = _tester(client, container)
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).json()["detail"] == \
        "NO_PAYMENT_GATEWAY", "keys Razorpay refused never start a checkout"


def test_webhook_evidence_counts_verified_and_rejected_deliveries(env, monkeypatch):
    client, container, _ = env
    monkeypatch.setenv("RAZORPAY_WEBHOOK_SECRET", WH_SECRET)
    container.platform = None
    from app.services import payment_gateway_health as gh

    before = gh.WEBHOOK_REJECTIONS["count"]
    uid, me = _tester(client, container)
    out, _ = _buy(client, me)
    order_id = out["checkout"]["order_id"]
    body = json.dumps(_captured(order_id, "pay_E1", 49900)).encode()
    assert client.post("/api/payments/webhook/razorpay", content=body,
                       headers={"x-razorpay-signature": "a" * 64}).status_code == 401
    assert _webhook(client, _captured(order_id, "pay_E1", 49900), "evt_e1").json()["status"] == "PAID"
    g = gh.check(container)
    assert g["webhook_signing"] == "set" and g["webhooks"]["verified_events"] == 1
    assert g["webhooks"]["last_verified_at"] and g["webhooks"]["rejected_signatures_since_deploy"] == before + 1
    rows = {r["integration"]: r for r in client.get("/health/integrations").json()["items"]}
    assert rows["Razorpay"]["webhook_events_verified"] == 1 and rows["Razorpay"]["webhook_signing"] == "set"


def test_only_a_live_purchase_activates_and_testers_can_be_added_by_phone(env):
    client, container, _ = env
    from app.api.routes.growth import growth
    from app.services import billing

    r = client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": "+91 98765 43210"})
    assert r.json()["user_id"] == "app-phone-919876543210"
    assert billing.tester_user_id("9876543210") == "app-phone-919876543210"
    assert billing.tester_user_id("app-phone-919876543210") == "app-phone-919876543210"
    # A LIVE purchase (only possible after every Owner approval) is the one path that activates.
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    live = billing.store(container).create(user_id=uid, plan_code="plus", kind="base", amount=499.0,
                                           provider="razorpay", mode="live", status="PENDING")
    test = billing.store(container).create(user_id=uid, plan_code="plus", kind="base", amount=499.0,
                                           provider="razorpay", mode="test", status="PENDING")
    assert billing.on_payment(container, {"id": "pay_T", "status": "PAID",
                                          "order_ref": f"billing:{test['id']}"})["status"] == "TEST_PAID"
    assert growth(container).current_subscription(uid) is None
    assert billing.on_payment(container, {"id": "pay_L", "status": "PAID",
                                          "order_ref": f"billing:{live['id']}"})["status"] == "ACTIVE"
    assert growth(container).current_subscription(uid)["plan_code"] == "plus"


def test_tester_matches_the_phone_however_it_was_typed_at_sign_in(env):
    client, container, _ = env
    from app.services import billing

    # Signed in typing 10 digits (id app-phone-9876500001); staff typed +91 ...
    me = {"Authorization": f"Bearer {issue_token('app-phone-9876500001', container.settings.session_token_secret)}"}
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).json()["detail"] == \
        "TEST_MODE_TESTERS_ONLY"
    assert client.post("/admin/cc/billing/testers", headers=OWNER, json={"user_id": "+91 98765 00001"}).status_code == 200
    got = client.get("/api/billing/options", headers=me).json()
    opts = {i["plan_code"]: i for i in got["items"]}
    assert opts["plus"]["payable"] is True and opts["pro"]["payable"] is True
    assert opts["radio_7d"]["reason"] == "RADIO_BILLING_OFF"
    assert got["account"] == {"phone_last4": "0001", "billing_tester": True, "demo_account": False}, "masked: last 4 digits only"
    assert "9876500001" not in json.dumps(got)
    assert billing.store(container).is_tester("app-phone-919876500001")
    assert not billing.store(container).is_tester("app-phone-9876500002"), "a different number is not a tester"
    # Removing by any spelling revokes it fully.
    assert client.delete("/admin/cc/billing/testers/9876500001", headers=OWNER).json()["removed"] is True
    assert not billing.store(container).is_tester("app-phone-9876500001")
    assert client.post("/api/billing/checkout", headers=me, json={"plan_code": "plus"}).json()["detail"] == \
        "TEST_MODE_TESTERS_ONLY"


def test_shared_demo_login_is_never_a_tester_and_radio_testers_match_by_phone(env):
    client, container, _ = env
    from app.api.routes.radio import radio
    from app.services import billing

    demo = {"Authorization": f"Bearer {issue_token('app-phone-919999999999', container.settings.session_token_secret)}"}
    for path in ("/admin/cc/billing/testers", "/admin/cc/radio/testers"):
        r = client.post(path, headers=OWNER, json={"user_id": "9999999999"})
        assert r.status_code == 409 and "DEMO_ACCOUNT_NOT_ALLOWED" in r.text
    # Even a demo id stored some other way never counts.
    billing.store(container).add_tester("app-phone-919999999999", "test")
    got = client.get("/api/billing/options", headers=demo).json()
    assert got["account"] == {"phone_last4": "9999", "billing_tester": False, "demo_account": True}
    assert not any(i["payable"] for i in got["items"])
    # Radio testers use the same phone rule as billing testers.
    assert client.post("/admin/cc/radio/testers", headers=OWNER,
                       json={"user_id": "+91 98765 00007", "note": "owner phone"}).json()["user_id"] == \
        "app-phone-919876500007"
    assert radio(container).is_tester("app-phone-9876500007"), "signed in with 10 digits still matches"
    assert not radio(container).is_tester("app-phone-919999999999")
    assert client.delete("/admin/cc/radio/testers/9876500007", headers=OWNER).json()["removed"] is True
    assert not radio(container).is_tester("app-phone-919876500007")
