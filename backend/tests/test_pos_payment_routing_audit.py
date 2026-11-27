"""Who hears a payment: owner, ticked staff only; never unticked / removed / other-shop / other staff."""
from datetime import datetime, timezone

import pytest

from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000401"
CASH_A = "app-phone-9400000402"   # cashier, payment sound ticked
CASH_B = "app-phone-9400000403"   # cashier, payment sound UNTICKED
KITCHEN = "app-phone-9400000404"  # kitchen role, never allowed
OTHER_OWNER = "app-phone-9400000409"
APP = "com.phonepe.app.business"


@pytest.fixture()
def env(tmp_path):
    now = datetime(2026, 11, 27, 5, 0, tzinfo=timezone.utc)
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now)
    pushes = []
    alerts = PosPaymentAlerts(store, notify=lambda *a: pushes.append(a), feature_on=lambda: True)
    biz = store.create_business(OWNER, {"name": "Audit Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000402", "cashier", tools=["payalerts", "sale"])
    store.set_member(biz, OWNER, "9400000403", "cashier", tools=["sale"])
    store.set_member(biz, OWNER, "9400000404", "kitchen", tools=["kitchen"])
    for u in (CASH_A, CASH_B, KITCHEN):
        store.business(biz, u)
    alerts.update_settings(biz, OWNER, {"enabled": True, "roles": ["manager", "cashier"]})
    devs = {OWNER: alerts.register_device(biz, OWNER, {"device_key": "owner-phone-01", "listener_on": True})["device_id"]}
    for u, k in ((CASH_A, "cash-a-phone-01"), (CASH_B, "cash-b-phone-01")):
        devs[u] = alerts.register_device(biz, u, {"device_key": k})["device_id"]
    return store, alerts, biz, devs, pushes


def _fire(alerts, biz, devs, who, n, **kw):
    ev = {"client_event_id": f"{APP}|k{n}|17299000{n}", "source_app": APP, "amount_paise": 10000 + int(n) * 100,
          "device_id": devs[who], "spoken": "announced"}
    ev.update(kw)
    return alerts.report(biz, who, ev)


def _heard(pushes):
    return sorted({p[0] for p in pushes})


def test_owner_payment_reaches_only_staff_with_the_payment_sound_tool(env):
    _, alerts, biz, devs, pushes = env
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "1")
    assert CASH_A in _heard(pushes)
    assert CASH_B not in _heard(pushes), "owner unticked Payment sound for this cashier -> silent"
    assert KITCHEN not in _heard(pushes)


def test_staff_payment_goes_to_owner_only_and_never_to_other_staff(env):
    _, alerts, biz, devs, pushes = env
    pushes.clear()
    _fire(alerts, biz, devs, CASH_A, "2")
    assert _heard(pushes) == [OWNER]


def test_removed_staff_and_other_shop_never_hear(env):
    store, alerts, biz, devs, pushes = env
    store.set_member(biz, OWNER, "9400000402", "removed")
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "3")
    assert CASH_A not in _heard(pushes)
    other = store.create_business(OTHER_OWNER, {"name": "Other", "state_code": "36"})["id"]
    alerts.update_settings(other, OTHER_OWNER, {"enabled": True})
    od = alerts.register_device(other, OTHER_OWNER, {"device_key": "other-owner-01", "listener_on": True})["device_id"]
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "4")
    assert OTHER_OWNER not in _heard(pushes)
    pushes.clear()
    alerts.report(other, OTHER_OWNER, {"client_event_id": f"{APP}|o1|1729900099", "source_app": APP,
                                       "amount_paise": 777700, "device_id": od, "spoken": "announced"})
    assert not ({OWNER, CASH_A, CASH_B} & set(_heard(pushes))), "another shop's payment never reaches this shop's people"


def _collect(alerts):
    alerts._collect_method = lambda conn, biz: {"upi_id": "audit@okhdfcbank", "payee_name": "Audit Kirana"}


def test_two_open_qrs_of_the_same_amount_get_a_paise_apart_and_only_owner_and_shower_hear(env):
    store, alerts, biz, devs, pushes = env
    _collect(alerts)
    a = alerts.create_request(biz, CASH_A, {"amount_paise": 25000, "label": "#1"})
    b = alerts.create_request(biz, CASH_B, {"amount_paise": 25000, "label": "#2"})
    assert (a["amount_paise"], b["amount_paise"]) == (25000, 25001), "same amount twice = the later one is +1 paisa"
    pushes.clear()
    with store._tx() as conn:
        alerts._match_request(conn, biz, "ppe_audit", 25001)
    told = {p[0] for p in pushes if "వచ్చింది" in p[1]}
    assert told == {OWNER, CASH_B}, "the owner and the person who showed THAT QR -- never the other cashier"
    assert alerts.requests(biz, OWNER)  # owner still sees both


def test_staff_of_another_shop_cannot_create_collect_requests_here(env):
    store, alerts, biz, devs, pushes = env
    _collect(alerts)
    with pytest.raises(PosError) as e:
        alerts.create_request(biz, OTHER_OWNER, {"amount_paise": 1000})
    assert e.value.status == 404


def test_owner_of_two_shops_each_payment_stays_in_its_own_shop(env):
    store, alerts, biz, devs, pushes = env
    second = store.create_business(OWNER, {"name": "Second Shop", "state_code": "37"})["id"]
    store.set_member(second, OWNER, "9400000405", "cashier", tools=["payalerts"])
    third = "app-phone-9400000405"
    store.business(second, third)
    alerts.update_settings(second, OWNER, {"enabled": True, "roles": ["cashier"]})
    od = alerts.register_device(second, OWNER, {"device_key": "owner-second-01", "listener_on": True})["device_id"]
    alerts.register_device(second, third, {"device_key": "third-phone-01"})
    pushes.clear()
    alerts.report(second, OWNER, {"client_event_id": f"{APP}|s1|1729900123", "source_app": APP, "amount_paise": 55500,
                                  "device_id": od, "spoken": "announced"})
    assert _heard(pushes) == [third], "second shop's staff hear it; first shop's cashiers never do"
    assert not ({CASH_A, CASH_B} & set(_heard(pushes)))


def test_same_notification_twice_is_one_voice_but_two_customers_same_amount_are_two(env):
    _, alerts, biz, devs, pushes = env
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "9", amount_paise=88800)
    first = len(pushes)
    _fire(alerts, biz, devs, OWNER, "9", amount_paise=88800)  # the app re-posts the very same notification
    assert first >= 1 and len(pushes) == first, "same notification key = never spoken twice"
    _fire(alerts, biz, devs, OWNER, "10", amount_paise=88800)  # a different notification, same amount
    assert len(pushes) > first, "two customers can pay the same amount: a second payment, a second voice"


def test_owner_ticking_and_unticking_changes_who_hears_at_once(env):
    store, alerts, biz, devs, pushes = env
    store.set_member(biz, OWNER, "9400000403", "cashier", tools=["sale", "payalerts"])
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "7")
    assert CASH_B in _heard(pushes)
    store.set_member(biz, OWNER, "9400000403", "cashier", tools=["sale"])
    pushes.clear()
    _fire(alerts, biz, devs, OWNER, "8")
    assert CASH_B not in _heard(pushes)
