"""Owner 2026-11-18: each phone's payment sound -- working / permission off / not answering -- and ONE warning
to the owner (+ the phone's person) when a sent sound got no answer."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_payment_alerts import PosPaymentAlerts, missed_texts
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000401"
CASHIER = "app-phone-9400000402"
WAITER = "app-phone-9400000403"
PHONEPE = "com.phonepe.app.business"


class Clock:
    def __init__(self):
        self.now = datetime(2026, 11, 18, 5, 0, tzinfo=timezone.utc)

    def __call__(self):
        return self.now


@pytest.fixture()
def env(tmp_path):
    clock = Clock()
    store = PosStore(str(tmp_path / "pos.db"), clock=clock)
    alerts = PosPaymentAlerts(store, notify=lambda *a: None)
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000402", "cashier")
    store.set_member(biz, OWNER, "9400000403", "waiter")
    store.business(biz, CASHIER)
    store.business(biz, WAITER)
    alerts.update_settings(biz, OWNER, {"enabled": True, "roles": ["manager", "cashier", "waiter"]})
    owner_dev = alerts.register_device(biz, OWNER, {"device_key": "owner-phone-1", "label": "Counter"})["device_id"]
    cashier_dev = alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-1", "label": "Ravi"})["device_id"]
    waiter_dev = alerts.register_device(biz, WAITER, {"device_key": "waiter-phone-1", "label": "Sita"})["device_id"]
    return store, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock


def _pay(alerts, biz, dev, n="1", amount=35000):
    return alerts.report(biz, OWNER, {"client_event_id": f"{PHONEPE}|key{n}|17299{n}", "source_app": PHONEPE,
                                      "amount_paise": amount, "device_id": dev, "spoken": "announced"})


def _by_label(status):
    return {p["label"]: p for p in status["phones"]}


def test_unacked_sound_is_not_answering_and_warned_once(env):
    _, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock = env
    e = _pay(alerts, biz, owner_dev)
    alerts.ack(biz, CASHIER, e["id"], {"device_id": cashier_dev, "state": "announced"})
    clock.now += timedelta(minutes=1)
    assert alerts.missed_sounds() == [], "too early: the phone may still be speaking"
    clock.now += timedelta(minutes=3)
    phones = _by_label(alerts.phone_status(biz, OWNER))
    assert phones["Ravi"]["state"] == "working"
    assert phones["Sita"]["state"] == "not_answering" and phones["Sita"]["missed_amount_paise"] == 35000
    assert phones["Sita"]["hear_only"] is True
    missed = alerts.missed_sounds()
    assert [m["device_id"] for m in missed] == [waiter_dev]
    assert missed[0]["reason"] == "no_answer" and missed[0]["owner"] == OWNER
    assert alerts.missed_sounds() == [], "each miss is warned only once"
    t = missed_texts(missed[0])
    assert "₹350" in t["owner_body"] and "సౌండ్ రాలేదు" in t["owner_body"]
    assert "ఒక్క స్టెప్" in t["phone_body"]


def test_staff_sees_only_own_phone_and_owner_sees_all(env):
    _, alerts, biz, *_ = env
    assert {p["label"] for p in alerts.phone_status(biz, OWNER)["phones"]} == {"Counter", "Ravi", "Sita"}
    mine = alerts.phone_status(biz, WAITER)
    assert [p["label"] for p in mine["phones"]] == ["Sita"] and mine["hear_only"] is True
    assert alerts.phone_status(biz, CASHIER)["hear_only"] is False, "a cashier collects money: reports payments"


def test_heartbeat_permission_off_and_hear_only_needs_no_access(env):
    _, alerts, biz, owner_dev, *_ = env
    alerts.heartbeat(CASHIER, {"device_key": "cashier-phone-1", "health": "needs_access"})
    alerts.heartbeat(WAITER, {"device_key": "waiter-phone-1", "health": "needs_access"})
    phones = _by_label(alerts.phone_status(biz, OWNER))
    assert phones["Ravi"]["state"] == "permission_off" and phones["Ravi"]["reason"] == "needs_access"
    assert phones["Sita"]["state"] != "permission_off", "a hear-only phone does not need notification access"
    assert alerts.phone_status(biz, OWNER)["problems"] == 1
    # the phone fixed it and says so: working again
    alerts.heartbeat(CASHIER, {"device_key": "cashier-phone-1", "health": "ok"})
    assert _by_label(alerts.phone_status(biz, OWNER))["Ravi"]["state"] == "working"
    with pytest.raises(PosError):
        alerts.heartbeat(CASHIER, {"device_key": "cashier-phone-1", "health": "whatever"})


def test_answer_after_a_miss_clears_it(env):
    _, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock = env
    _pay(alerts, biz, owner_dev, "1")
    clock.now += timedelta(minutes=5)
    assert _by_label(alerts.phone_status(biz, OWNER))["Ravi"]["state"] == "not_answering"
    alerts.heartbeat(CASHIER, {"device_key": "cashier-phone-1", "health": "ok"})
    assert _by_label(alerts.phone_status(biz, OWNER))["Ravi"]["state"] == "working"


def test_voice_failure_is_a_miss_with_reason(env):
    _, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock = env
    e = _pay(alerts, biz, owner_dev)
    alerts.ack(biz, CASHIER, e["id"], {"device_id": cashier_dev, "state": "tts_failed"})
    clock.now += timedelta(minutes=4)
    assert _by_label(alerts.phone_status(biz, OWNER))["Ravi"]["reason"] == "no_voice"
    reasons = {m["device_id"]: m["reason"] for m in alerts.missed_sounds()}
    assert reasons[cashier_dev] == "no_voice"


def test_quiet_or_muted_answer_is_not_a_miss_and_new_phone_is_unknown(env):
    _, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock = env
    assert _by_label(alerts.phone_status(biz, OWNER))["Ravi"]["state"] == "unknown"
    e = _pay(alerts, biz, owner_dev)
    alerts.ack(biz, CASHIER, e["id"], {"device_id": cashier_dev, "state": "quiet_hours"})
    alerts.ack(biz, WAITER, e["id"], {"device_id": waiter_dev, "state": "muted"})
    clock.now += timedelta(minutes=4)
    assert alerts.missed_sounds() == []


def test_settings_say_whether_this_phone_reports_payments(env):
    _, alerts, biz, *_ = env
    assert alerts.settings(biz, OWNER)["reports_payments"] is True
    assert alerts.settings(biz, WAITER)["reports_payments"] is False


def test_http_heartbeat_and_phones(monkeypatch):
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
    owner = "app-phone-9411100401"
    biz = client.post("/api/pos/businesses", headers=auth(owner), json={"name": "Shop", "state_code": "36"}).json()["id"]
    base = f"/api/pos/businesses/{biz}/payment-alerts"
    client.put(f"{base}/settings", headers=auth(owner), json={"enabled": True})
    client.post(f"{base}/devices", headers=auth(owner), json={"device_key": "phone-key-456", "label": "Counter"})
    hb = client.post("/api/pos/me/payment-alerts/heartbeat", headers=auth(owner),
                     json={"device_key": "phone-key-456", "health": "needs_access"})
    assert hb.status_code == 200 and hb.json()["updated"] == 1
    phones = client.get(f"{base}/phones", headers=auth(owner)).json()
    assert phones["phones"][0]["state"] == "permission_off" and phones["problems"] == 1
    assert client.get(f"{base}/phones").status_code == 401


def test_periodic_job_is_registered_and_runs(env, monkeypatch):
    from types import SimpleNamespace

    from app.services import periodic_jobs

    store, alerts, biz, owner_dev, cashier_dev, waiter_dev, clock = env
    assert "payalert_missed" in [name for name, _, _ in periodic_jobs.default_jobs()]
    _pay(alerts, biz, owner_dev)
    clock.now += timedelta(minutes=5)
    sent = []

    class Push:
        def notify(self, user_id, **kw):
            sent.append((user_id, kw["route"], kw["body"]))
            return 1

    monkeypatch.setattr("app.services.push_service.push_service", lambda container: Push())
    out = periodic_jobs._payalert_missed(SimpleNamespace(pos_store=store, pos_payment_alerts=alerts))
    assert out["missed"] == 2
    owners = [s for s in sent if s[0] == OWNER]
    assert len(owners) == 2 and owners[0][1] == f"/me/payment-alerts/{biz}/who"
    assert {s[0] for s in sent} == {OWNER, CASHIER, WAITER}


def test_message_without_amount_is_never_spoken_on_other_phones(tmp_path):
    clock = Clock()
    store = PosStore(str(tmp_path / "pos2.db"), clock=clock)
    pushes = []
    alerts = PosPaymentAlerts(store, notify=lambda *a: pushes.append(a))
    biz = store.create_business(OWNER, {"name": "Shop", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000402", "cashier")
    store.business(biz, CASHIER)
    alerts.update_settings(biz, OWNER, {"enabled": True})
    dev = alerts.register_device(biz, OWNER, {"device_key": "owner-phone-9"})["device_id"]
    alerts.register_device(biz, CASHIER, {"device_key": "cashier-phone-9"})
    e = alerts.report(biz, OWNER, {"client_event_id": f"{PHONEPE}|nokey|1", "source_app": PHONEPE, "device_id": dev})
    assert e["status"] == "ambiguous"
    assert pushes == [], "no amount: kept in the history, no voice push"
    clock.now += timedelta(minutes=10)
    assert alerts.missed_sounds() == []
