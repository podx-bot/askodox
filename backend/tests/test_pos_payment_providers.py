"""Bank / provider-confirmed alerts: the shop's own Razorpay, signed webhook + API re-check, test vs live."""
import hashlib
import hmac
import json
from datetime import datetime, timezone

import pytest

from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_payment_providers import PosPaymentProviders
from app.services.pos_store import PosError, PosStore
from app.services.secret_box import SecretBox

OWNER = "app-phone-9400000401"
CASHIER = "app-phone-9400000402"
HOOK = "whsec-test-12345"


class FakeRazorpay:
    def __init__(self):
        self.calls = []
        self.payments = {}

    def __call__(self, method, url, **kw):
        self.calls.append((method, url, kw.get("auth")))
        if url.endswith("/payments") and method == "GET":
            return (200, {"items": []}) if kw["auth"][1] == "secret-good-123" else (401, {})
        if url.endswith("/payments/qr_codes"):
            return 200, {"id": "qr_TEST1", "image_url": "https://rzp.io/i/qr"}
        pid = url.rsplit("/", 1)[-1]
        if pid in self.payments:
            return 200, self.payments[pid]
        return 404, {}


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 26, 9, 0, tzinfo=timezone.utc))
    pushes = []
    alerts = PosPaymentAlerts(store, notify=lambda *a: pushes.append(a))
    rzp = FakeRazorpay()
    env_vars = {}
    providers = PosPaymentProviders(store, alerts, SecretBox("k" * 40), http=rzp, env=env_vars)
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000402", "cashier")
    store.business(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"enabled": True})
    alerts.register_device(biz, OWNER, {"device_key": "owner-phone-1"})
    alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-1"})
    return store, alerts, providers, rzp, biz, pushes, env_vars


def _connect(providers, biz, key="rzp_test_ABCDEF123"):
    return providers.connect(biz, OWNER, {"key_id": key, "key_secret": "secret-good-123", "webhook_secret": HOOK},
                             "https://api.example")


def _hook(providers, biz, payment, event="qr_code.credited", event_id="evt_1", secret=HOOK):
    body = json.dumps({"event": event, "payload": {"payment": {"entity": payment}}}).encode()
    sig = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return providers.webhook("razorpay", biz, body, sig, event_id)


def test_connect_stores_encrypted_never_returns_secrets(env):
    store, _, providers, _, biz, _, _ = env
    out = _connect(providers, biz)
    assert out["connected"] and out["mode"] == "test" and out["key_id_tail"] == "F123"
    assert out["webhook_url"] == f"https://api.example/api/pos/payment-webhooks/razorpay/{biz}"
    assert "secret-good-123" not in json.dumps(out) and HOOK not in json.dumps(out)
    with store._connect() as conn:
        row = conn.execute("SELECT key_secret, webhook_secret FROM pos_provider_accounts").fetchone()
    assert row[0].startswith("enc:v1:") and row[1].startswith("enc:v1:")


def test_bad_keys_live_keys_and_staff_refused(env):
    _, _, providers, _, biz, _, env_vars = env
    with pytest.raises(PosError) as e:
        providers.connect(biz, OWNER, {"key_id": "rzp_test_ABCDEF123", "key_secret": "secret-bad-123",
                                       "webhook_secret": HOOK})
    assert e.value.code == "keys_rejected"
    with pytest.raises(PosError) as e:
        _connect(providers, biz, key="rzp_live_ABCDEF123")
    assert e.value.code == "live_not_approved"
    env_vars["ASKODOX_POS_PROVIDER_LIVE_APPROVED"] = "yes"
    assert _connect(providers, biz, key="rzp_live_ABCDEF123")["mode"] == "live"
    with pytest.raises(PosError) as e:
        providers.connect(biz, CASHIER, {"key_id": "rzp_test_ABCDEF123", "key_secret": "secret-good-123",
                                         "webhook_secret": HOOK})
    assert e.value.status == 403


def test_signed_captured_payment_becomes_verified_alert_for_owner_and_staff(env):
    _, alerts, providers, rzp, biz, pushes, _ = env
    _connect(providers, biz)
    pay = {"id": "pay_ABC123", "amount": 50000, "currency": "INR", "status": "captured",
           "acquirer_data": {"rrn": "412345678901"}, "created_at": 1793000000}
    rzp.payments["pay_ABC123"] = pay
    out = _hook(providers, biz, pay)
    assert out["outcome"] == "recorded"
    event = alerts.events(biz, OWNER)["events"][0]
    assert event["status"] == "provider_verified" and event["verified"] is True
    assert event["test"] is True, "test-mode money is never counted"
    assert event["announcement"]["te"] == "టెస్ట్. మీకు 500 రూపాయలు అందాయి."
    assert event["reference_tail"] == "8901" and event["source_label"] == "Razorpay"
    assert sorted(p[0] for p in pushes) == sorted([OWNER, CASHIER])
    assert _hook(providers, biz, pay)["outcome"] == "replay"
    assert _hook(providers, biz, pay, event="payment.captured", event_id="evt_2")["outcome"] == "duplicate"
    assert len(pushes) == 2, "the same payment never alerts twice"


def test_forged_or_unconfirmed_webhooks_never_verify(env):
    _, alerts, providers, rzp, biz, pushes, _ = env
    _connect(providers, biz)
    pay = {"id": "pay_X1", "amount": 99900, "currency": "INR", "status": "captured"}
    with pytest.raises(PosError) as e:
        _hook(providers, biz, pay, secret="wrong-secret")
    assert e.value.status == 401
    assert _hook(providers, biz, pay, event_id="evt_9")["outcome"] == "verify_failed", "Razorpay API does not know it"
    rzp.payments["pay_X2"] = {"id": "pay_X2", "amount": 100, "currency": "INR", "status": "captured"}
    assert _hook(providers, biz, {"id": "pay_X2", "amount": 99900}, event_id="evt_10")["outcome"] == "amount_mismatch"
    rzp.payments["pay_X3"] = {"id": "pay_X3", "amount": 500, "currency": "INR", "status": "failed"}
    assert _hook(providers, biz, {"id": "pay_X3", "amount": 500}, event_id="evt_11")["outcome"] == "not_captured"
    assert _hook(providers, biz, {"id": "pay_X3"}, event="payment.failed", event_id="evt_12")["outcome"] == "ignored_event"
    assert alerts.events(biz, OWNER)["events"] == [] and pushes == []


def test_qr_and_disconnect(env):
    _, _, providers, rzp, biz, _, _ = env
    with pytest.raises(PosError):
        providers.create_qr(biz, OWNER)
    _connect(providers, biz)
    out = providers.create_qr(biz, OWNER)
    assert out["qr_id"] == "qr_TEST1" and out["qr_image_url"] == "https://rzp.io/i/qr"
    body = [c for c in rzp.calls if c[1].endswith("/qr_codes")]
    assert body and body[0][2] == ("rzp_test_ABCDEF123", "secret-good-123")
    assert providers.disconnect(biz, OWNER)["connected"] is False
    with pytest.raises(PosError) as e:
        _hook(providers, biz, {"id": "pay_Z"})
    assert e.value.code == "not_connected"


def test_http_webhook_route(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    rzp = FakeRazorpay()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_payment_alerts", None, raising=False)
    monkeypatch.setattr(container, "pos_payment_providers", None, raising=False)
    monkeypatch.setattr(container, "pos_provider_http", rzp, raising=False)
    from dataclasses import replace

    monkeypatch.setattr(container, "settings", replace(container.settings, secrets_key="k" * 40))
    secret = container.settings.session_token_secret
    owner = "app-phone-9411100401"
    auth = {"Authorization": f"Bearer {issue_token(owner, secret)}"}
    client = TestClient(app)
    biz = client.post("/api/pos/businesses", headers=auth, json={"name": "Shop", "state_code": "36"}).json()["id"]
    r = client.put(f"/api/pos/businesses/{biz}/payment-alerts/provider", headers=auth,
                   json={"key_id": "rzp_test_ABCDEF123", "key_secret": "secret-good-123", "webhook_secret": HOOK})
    assert r.status_code == 200 and r.json()["connected"] is True, r.text
    rzp.payments["pay_H1"] = {"id": "pay_H1", "amount": 1000, "currency": "INR", "status": "captured"}
    body = json.dumps({"event": "qr_code.credited", "payload": {"payment": {"entity": {"id": "pay_H1", "amount": 1000}}}})
    url = f"/api/pos/payment-webhooks/razorpay/{biz}"
    assert client.post(url, content=body, headers={"x-razorpay-signature": "bad"}).status_code == 401
    sig = hmac.new(HOOK.encode(), body.encode(), hashlib.sha256).hexdigest()
    ok = client.post(url, content=body, headers={"x-razorpay-signature": sig, "x-razorpay-event-id": "evt_h1"})
    assert ok.status_code == 200 and ok.json()["outcome"] == "recorded"
    events = client.get(f"/api/pos/businesses/{biz}/payment-alerts/events", headers=auth).json()["events"]
    assert events[0]["status"] == "provider_verified"
