"""POS payment voice alerts: notification-only events, dedupe, staff fan-out, roles, kill switch."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_payment_alerts import PosPaymentAlerts, announcement
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000301"
CASHIER = "app-phone-9400000302"
ACCOUNTANT = "app-phone-9400000303"
STRANGER = "app-phone-9400000399"
PHONEPE = "com.phonepe.app.business"


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 26, 5, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now


@pytest.fixture()
def env(tmp_path):
    clock = Clock()
    store = PosStore(str(tmp_path / "pos.db"), clock=clock)
    pushes = []
    feature = {"on": True}
    alerts = PosPaymentAlerts(store, notify=lambda *a: pushes.append(a), feature_on=lambda: feature["on"])
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000302", "cashier")
    store.set_member(biz, OWNER, "9400000303", "accountant")
    # staff link their app identity the first time they open the shop
    store.business(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"enabled": True})
    owner_dev = alerts.register_device(biz, OWNER, {"device_key": "owner-phone-1", "label": "Counter phone",
                                                    "listener_on": True})["device_id"]
    cashier_dev = alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-1", "label": "Cashier"})["device_id"]
    return store, alerts, biz, owner_dev, cashier_dev, pushes, feature, clock


def _event(owner_dev, n="1", **kw):
    data = {"client_event_id": f"{PHONEPE}|key{n}|1729900000{n}", "source_app": PHONEPE, "amount_paise": 50000,
            "device_id": owner_dev, "spoken": "announced"}
    data.update(kw)
    return data


def test_valid_notification_is_unverified_and_fans_out_to_staff(env):
    store, alerts, biz, owner_dev, cashier_dev, pushes, _, _ = env
    e = alerts.report(biz, OWNER, _event(owner_dev, reference="T2410261234567890"))
    assert e["status"] == "notification_unverified" and e["verification"] == "notification_only"
    assert e["verified"] is False and e["duplicate"] is False
    assert e["reference_tail"] == "7890" and e["source_label"] == "PhonePe Business"
    assert e["receiving_device"] == "Counter phone"
    assert "బ్యాంకులో నిర్ధారించుకోండి" in e["announcement"]["te"], "unverified wording always asks to check the bank"
    assert [p[0] for p in pushes] == [CASHIER], "staff device gets the alert; the reporter does not"
    assert pushes[0][3] == f"/pos/{biz}/payment-alerts"
    assert e["delivery_pending"] == 1, "cashier device has not acknowledged yet"
    done = alerts.ack(biz, CASHIER, e["id"], {"device_id": cashier_dev, "state": "announced"})
    assert done["delivery_pending"] == 0 and done["status"] == "notification_unverified", "sharing never changes status"
    # nothing reached POS payments / revenue
    with store._connect() as conn:
        assert conn.execute("SELECT COUNT(*) FROM pos_payments").fetchone()[0] == 0


def test_duplicate_by_reference_and_by_event_id(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    a = alerts.report(biz, OWNER, _event(owner_dev, "1", reference="UTR998877665544"))
    b = alerts.report(biz, OWNER, _event(owner_dev, "2", reference="UTR998877665544"))  # update of same payment
    assert b["duplicate"] is True and b["id"] == a["id"]
    c = alerts.report(biz, OWNER, _event(owner_dev, "3"))
    d = alerts.report(biz, OWNER, _event(owner_dev, "3"))
    assert d["duplicate"] is True and d["id"] == c["id"]
    assert len(pushes) == 2, "a duplicate never alerts twice"
    assert alerts.events(biz, OWNER, status="duplicate")["events"][0]["duplicates"] >= 1


def test_repeated_same_amount_different_payments_are_separate(env):
    _, alerts, biz, owner_dev, _, _, _, _ = env
    a = alerts.report(biz, OWNER, _event(owner_dev, "1"))
    b = alerts.report(biz, OWNER, _event(owner_dev, "2"))
    assert a["id"] != b["id"] and not b["duplicate"]
    assert alerts.events(biz, OWNER)["last_24h"]["count"] == 2


def test_missing_amount_is_ambiguous_and_unsupported_app_refused(env):
    _, alerts, biz, owner_dev, _, _, _, _ = env
    e = alerts.report(biz, OWNER, _event(owner_dev, amount_paise=None, reason="amount_missing"))
    assert e["status"] == "ambiguous" and "మొత్తం స్పష్టంగా లేదు" in e["announcement"]["te"]
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "9", source_app="com.whatsapp"))
    assert err.value.code == "unsupported_app"


def test_client_can_never_claim_bank_verified(env):
    _, alerts, biz, owner_dev, _, _, _, _ = env
    for fake in ({"verification": "bank_verified"}, {"status": "provider_verified"}):
        with pytest.raises(PosError) as err:
            alerts.report(biz, OWNER, _event(owner_dev, **fake))
        assert err.value.code == "verification"


def test_test_event_works_even_before_enabling_and_is_labelled(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    alerts.update_settings(biz, OWNER, {"enabled": False})
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev))
    assert err.value.code == "not_enabled"
    t = alerts.report(biz, OWNER, {"client_event_id": "test-evt-000001", "amount_paise": 100, "test": True,
                                   "device_id": owner_dev})
    assert t["test"] is True and t["announcement"]["te"].startswith("టెస్ట్")
    assert alerts.events(biz, OWNER)["last_24h"]["count"] == 0, "test events are never counted"
    assert pushes and "(test)" in pushes[-1][1]


def test_roles_revocation_and_shop_isolation(env):
    store, alerts, biz, owner_dev, cashier_dev, pushes, _, _ = env
    with pytest.raises(PosError) as err:
        alerts.events(biz, STRANGER)
    assert err.value.status == 404
    store.business(biz, ACCOUNTANT)
    with pytest.raises(PosError) as err:
        alerts.events(biz, ACCOUNTANT)
    assert err.value.status == 403, "accountant is not in the default alert roles"
    alerts.update_settings(biz, OWNER, {"roles": ["manager"]})
    with pytest.raises(PosError):
        alerts.events(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"roles": ["manager", "cashier"]})
    with pytest.raises(PosError) as err:
        alerts.update_settings(biz, CASHIER, {"enabled": False})
    assert err.value.status == 403
    alerts.revoke_device(biz, OWNER, cashier_dev)
    pushes.clear()
    alerts.report(biz, OWNER, _event(owner_dev, "5"))
    assert pushes == [], "a revoked device's user gets no fan-out"
    with pytest.raises(PosError) as err:
        alerts.ack(biz, CASHIER, alerts.events(biz, OWNER)["events"][0]["id"], {"device_id": cashier_dev, "state": "seen"})
    assert err.value.code == "device_revoked"
    # second shop is isolated
    other = store.create_business(STRANGER, {"name": "Other", "state_code": "36"})["id"]
    alerts.update_settings(other, STRANGER, {"enabled": True})
    assert alerts.events(other, STRANGER)["events"] == []
    with pytest.raises(PosError):
        alerts.report(other, OWNER, _event(owner_dev, "6"))


def test_delayed_and_future_notifications(env):
    _, alerts, biz, owner_dev, _, _, _, clock = env
    late = (clock.now - timedelta(hours=5)).isoformat()
    e = alerts.report(biz, OWNER, _event(owner_dev, "7", detected_at=late))
    assert e["detected_at"] == late, "offline phone syncs later with its real detection time"
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "8", detected_at=(clock.now - timedelta(days=4)).isoformat()))
    assert err.value.code == "too_old"
    with pytest.raises(PosError):
        alerts.report(biz, OWNER, _event(owner_dev, "9", detected_at=(clock.now + timedelta(hours=1)).isoformat()))


def test_restart_keeps_history_and_retention_expires(env, tmp_path):
    store, alerts, biz, owner_dev, _, _, _, clock = env
    alerts.report(biz, OWNER, _event(owner_dev, "1"))
    again = PosPaymentAlerts(PosStore(store.db_path, clock=clock))  # backend restart
    assert len(again.events(biz, OWNER)["events"]) == 1
    clock.now += timedelta(days=91)
    assert again.events(biz, OWNER)["events"] == []


def test_push_failure_never_fails_report_and_kill_switch(env):
    store, _, biz, owner_dev, _, _, feature, clock = env

    def boom(*args):
        raise RuntimeError("FCM down")

    alerts = PosPaymentAlerts(store, notify=boom, feature_on=lambda: feature["on"])
    assert alerts.report(biz, OWNER, _event(owner_dev, "1"))["id"]
    feature["on"] = False
    with pytest.raises(PosError) as err:
        alerts.report(biz, OWNER, _event(owner_dev, "2"))
    assert err.value.status == 503 and alerts.settings(biz, OWNER)["feature_on"] is False


def test_settings_validation_and_announcements():
    assert announcement(50000, "te") == "500 రూపాయల పేమెంట్ నోటిఫికేషన్ వచ్చింది. బ్యాంకులో నిర్ధారించుకోండి."
    assert announcement(50000, "te", verified=True) == "మీకు 500 రూపాయలు అందాయి."
    assert announcement(12550, "en").startswith("Payment notification of 125 rupees 50 paise")
    assert "बैंक" in announcement(100, "hi")


def test_settings_rejects_bad_values(env):
    _, alerts, biz, *_ = env
    for bad in ({"quiet_start": "25:00", "quiet_end": "06:00"}, {"quiet_start": "22:00"}, {"apps": {"not a pkg": "x"}},
                {"language": "fr"}):
        with pytest.raises(PosError):
            alerts.update_settings(biz, OWNER, bad)
    s = alerts.update_settings(biz, OWNER, {"quiet_start": "22:00", "quiet_end": "06:00", "language": "hi"})
    assert s["quiet_start"] == "22:00" and s["language"] == "hi" and s["can_edit"] is True


def test_http_flow(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_payment_alerts", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner = "app-phone-9411100301"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Shop", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}/payment-alerts"
    assert client.get(f"{base}/settings").status_code == 401
    s = client.get(f"{base}/settings", headers=auth(owner)).json()
    assert s["enabled"] is False and PHONEPE in s["apps"] and s["language"] == "te"
    assert client.put(f"{base}/settings", headers=auth(owner), json={"enabled": True}).json()["enabled"] is True
    dev = client.post(f"{base}/devices", headers=auth(owner), json={"device_key": "phone-key-123", "label": "Counter",
                                                                     "listener_on": True}).json()["device_id"]
    r = client.post(f"{base}/events", headers=auth(owner), json={"client_event_id": "evt-http-0001", "source_app": PHONEPE,
                                                                 "amount_paise": 25000, "device_id": dev})
    assert r.status_code == 200 and r.json()["status"] == "notification_unverified"
    fake = client.post(f"{base}/events", headers=auth(owner), json={"client_event_id": "evt-http-0002",
                                                                    "source_app": PHONEPE, "amount_paise": 25000,
                                                                    "status": "provider_verified"})
    assert fake.status_code == 400
    listed = client.get(f"{base}/events", headers=auth(owner)).json()
    assert len(listed["events"]) == 1 and listed["last_24h"]["notified_total_paise"] == 25000
    csv = client.get(f"{base}/export.csv", headers=auth(owner))
    assert csv.status_code == 200 and "Not bank-verified" in csv.text and "250.00" in csv.text
    assert "pos.payment_alerts" in client.get("/api/flags").json()["flags"]


def test_alert_carries_speak_data_for_closed_app(env):
    _, alerts, biz, owner_dev, _, pushes, _, _ = env
    alerts.report(biz, OWNER, _event(owner_dev, "77"))
    speak = pushes[-1][5]
    assert speak["type"] == "payalert" and speak["verified"] == "0" and speak["language"] == "te"
    assert "బ్యాంకులో నిర్ధారించుకోండి" in speak["text"]


def test_push_service_data_message_is_high_priority_once(tmp_path):
    from app.services.push_service import PushService

    class Client:
        def __init__(self):
            self.sent = []

        def post(self, url, json=None, headers=None, data=None):
            self.sent.append(json)

            class R:
                status_code = 200
                text = ""
            return R()

    client = Client()
    push = PushService(str(tmp_path / "p.db"), service_account_json='{"project_id":"p","client_email":"e","private_key":"k"}',
                       client=client)
    push._access = ("tok", 9e12)
    push.register("u1", "fcm-token-1")
    n = push.send_data("u1", data={"type": "payalert", "text": "hi"}, event_key="payalert:e1")
    assert n == 1 and push.send_data("u1", data={"type": "payalert"}, event_key="payalert:e1") == 0
    msg = client.sent[0]["message"]
    assert msg["android"]["priority"] == "high" and "notification" not in msg and msg["data"]["type"] == "payalert"
