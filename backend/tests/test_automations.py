"""Automations (owner 2026-11-25 / 26): habit card, low-stock order DRAFT, regulars not seen, stopped-shop help push,
AI cost guard. Drafts only; every card can be put away; a habit needs the same weekday three times."""
import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.services import platform_settings
from app.services.automations import AutomationError, Automations
from app.services.pos_frontdesk import PosFrontDesk
from app.services.pos_purchases import PosPurchases
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300001001"
CASHIER = "app-phone-9300001002"
BUYER = "app-phone-9300001003"
IST = timezone(timedelta(hours=5, minutes=30))
THURSDAY = datetime(2026, 11, 26, 11, 0, tzinfo=IST)


@pytest.fixture()
def env(tmp_path):
    saved = (platform_settings._SOURCE, platform_settings._SOURCE_KEY)  # other tests keep their own settings source
    platform_settings.set_source(lambda: [])  # the built-in numbers
    platform_settings.invalidate()
    now = [THURSDAY]
    clock = lambda: now[0].astimezone(timezone.utc)  # noqa: E731
    db = str(tmp_path / "a.db")
    store = PosStore(db, clock=clock)
    PosFrontDesk(store, PosRestaurant(store), notify=lambda *a: None, pay_to=lambda *a: [])
    pur = PosPurchases(store)
    biz = store.create_business(OWNER, {"name": "Murali Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9300001002", "cashier")
    yield Automations(db, clock=clock), store, pur, biz, now
    platform_settings._SOURCE, platform_settings._SOURCE_KEY = saved
    platform_settings.invalidate()


def _order(store, biz, at, *, user=BUYER, stage="done", items=None):
    with store._connect() as conn:
        conn.execute("INSERT INTO pos_desk_orders(id, business_id, source, kind, items_json, stage, client_txn_id, placed_at,"
                     " updated_at, customer_user) VALUES(?,?,?,?,?,?,?,?,?,?)",
                     ("o-" + uuid.uuid4().hex[:8], biz, "app", "takeaway",
                      json.dumps(items or [{"product_id": "p1", "name": "Milk", "qty": 2, "price_paise": 3000}]), stage,
                      uuid.uuid4().hex, at.astimezone(timezone.utc).isoformat(), at.astimezone(timezone.utc).isoformat(), user))
        conn.commit()


def test_habit_needs_the_same_weekday_three_times_and_never_orders(env):
    auto, store, _, biz, now = env
    _order(store, biz, THURSDAY - timedelta(days=7))
    _order(store, biz, THURSDAY - timedelta(days=14))
    _order(store, biz, THURSDAY - timedelta(days=20))  # a Friday: not this weekday
    _order(store, biz, THURSDAY - timedelta(days=21), stage="cancelled")  # not a finished order
    assert auto.habit(BUYER) == [], "two Thursdays are not a habit yet"
    _order(store, biz, THURSDAY - timedelta(days=28), items=[{"product_id": "p9", "name": "Old", "qty": 1}])
    card = auto.habit(BUYER)[0]
    assert card["kind"] == "habit" and card["ref"] == biz and card["times"] == 3
    assert card["order"]["business_name"] == "Murali Kirana" and card["order"]["items"][0]["name"] == "Milk", "the newest"
    assert auto.habit("app-phone-9300009999") == [], "only the person's own orders"
    now[0] = THURSDAY + timedelta(days=1)
    assert auto.habit(BUYER) == [], "Friday is not the habit day"
    now[0] = THURSDAY
    with store._connect() as conn:
        orders = conn.execute("SELECT COUNT(*) FROM pos_desk_orders").fetchone()[0]
    assert orders == 5, "the card never places an order"


def test_habit_goes_quiet_after_todays_order_and_when_put_away(env):
    auto, store, _, biz, now = env
    for weeks in (1, 2, 3):
        _order(store, biz, THURSDAY - timedelta(days=7 * weeks))
    assert len(auto.habit(BUYER)) == 1
    auto.dismiss(BUYER, "habit", biz, forever=False)  # వద్దు: today only
    assert auto.habit(BUYER) == []
    now[0] = THURSDAY + timedelta(days=7)
    assert len(auto.habit(BUYER)) == 1, "back next week"
    auto.dismiss(BUYER, "habit", biz, forever=True)  # ఇక చూపించకు
    now[0] = THURSDAY + timedelta(days=14)
    assert auto.habit(BUYER) == []
    with pytest.raises(AutomationError):
        auto.dismiss(BUYER, "teleport", biz, forever=True)


def test_habit_not_shown_once_ordered_today(env):
    auto, store, _, biz, _ = env
    for weeks in (1, 2, 3):
        _order(store, biz, THURSDAY - timedelta(days=7 * weeks))
    _order(store, biz, THURSDAY - timedelta(hours=2), stage="placed")
    assert auto.habit(BUYER) == []


def _stocked(store, pur, biz):
    rice = store.add_product(biz, OWNER, {"name": "Rice 25kg", "unit": "pcs", "price_paise": 140000, "track_stock": True,
                                          "low_stock_milli": 5000})["id"]
    oil = store.add_product(biz, OWNER, {"name": "Oil 1L", "unit": "pcs", "price_paise": 15000, "track_stock": True,
                                         "low_stock_milli": 10000})["id"]
    salt = store.add_product(biz, OWNER, {"name": "Salt", "unit": "pcs", "price_paise": 2000, "track_stock": True,
                                          "low_stock_milli": 4000})["id"]
    sup = pur.add_supplier(biz, OWNER, {"name": "Sri Lakshmi Traders"})["id"]
    pur.record_purchase(biz, OWNER, {"client_txn_id": "bill-" + uuid.uuid4().hex, "supplier_id": sup, "supplier_bill_no": "1",
                                     "lines": [{"product_id": rice, "qty_milli": 4000, "cost_paise": 120000},
                                               {"product_id": oil, "qty_milli": 60000, "cost_paise": 12000}]})
    return rice, oil, salt, sup


def test_low_stock_groups_by_last_supplier_and_makes_only_a_draft(env):
    auto, store, pur, biz, _ = env
    rice, oil, salt, sup = _stocked(store, pur, biz)
    out = auto.low_stock(store, biz, OWNER)
    assert out["draft_only"] is True and [g["supplier"] for g in out["suppliers"]] == ["Sri Lakshmi Traders"]
    lines = out["suppliers"][0]["lines"]
    assert [l["name"] for l in lines] == ["Rice 25kg"], "oil is above its mark"
    assert lines[0]["stock_milli"] == 4000 and lines[0]["qty_milli"] == 6000 and lines[0]["cost_paise"] == 120000
    assert [l["name"] for l in out["no_supplier"]] == ["Salt"], "never bought: no supplier to draft for"
    made = auto.low_stock_draft(store, pur, biz, OWNER, sup)
    assert made["sent"] is False and made["order"]["status"] == "draft" and len(made["order"]["lines"]) == 1
    assert auto.low_stock(store, biz, OWNER)["suppliers"] == [], "already on an open order: not offered twice"
    with pytest.raises(AutomationError) as err:
        auto.low_stock_draft(store, pur, biz, OWNER, sup)
    assert err.value.code == "nothing_low"
    with pytest.raises(PosError):
        auto.low_stock(store, biz, CASHIER)  # a cashier may not buy for the shop
    with pytest.raises(PosError):
        auto.low_stock(store, biz, BUYER)  # not a member


def test_low_stock_supplier_can_be_put_away_for_ever(env):
    auto, store, pur, biz, _ = env
    _, _, _, sup = _stocked(store, pur, biz)
    auto.dismiss(OWNER, "low_stock", f"{biz}:{sup}", forever=True)
    assert auto.low_stock(store, biz, OWNER)["suppliers"] == []


def _bill(store, biz, customer, now, when):
    now[0] = when
    item = getattr(_bill, "item", None) or store.add_product(biz, OWNER, {"name": "Sugar", "unit": "pcs", "price_paise": 5000})["id"]
    _bill.item = item
    store.create_invoice(biz, OWNER, {"client_txn_id": "t-" + uuid.uuid4().hex, "customer_id": customer,
                                      "lines": [{"product_id": item, "qty_milli": 1000}],
                                      "payments": [{"method": "cash", "amount_paise": 5000}]})


def test_regulars_not_seen_for_fifteen_days_get_a_draft_never_a_sent_message(env):
    auto, store, _, biz, now = env
    _bill.item = None
    regular = store.add_customer(biz, OWNER, {"name": "Lakshmi", "phone": "9300002001"})["id"]
    recent = store.add_customer(biz, OWNER, {"name": "Ravi", "phone": "9300002002"})["id"]
    once = store.add_customer(biz, OWNER, {"name": "Once", "phone": "9300002003"})["id"]
    no_phone = store.add_customer(biz, OWNER, {"name": "No phone"})["id"]
    for days in (40, 30, 20):
        _bill(store, biz, regular, now, THURSDAY - timedelta(days=days))
        _bill(store, biz, no_phone, now, THURSDAY - timedelta(days=days))
    for days in (30, 20, 5):
        _bill(store, biz, recent, now, THURSDAY - timedelta(days=days))
    _bill(store, biz, once, now, THURSDAY - timedelta(days=25))
    now[0] = THURSDAY
    out = auto.winback(store, biz, OWNER)
    assert out["days"] == 15 and out["draft_only"] is True
    assert [(p["name"], p["days"], p["bills"]) for p in out["people"]] == [("Lakshmi", 20, 3)]
    assert "Murali Kirana" in out["draft"]["te"] and "Murali Kirana" in out["draft"]["en"]
    auto.dismiss(OWNER, "winback", f"{biz}:{regular}", forever=True)
    assert auto.winback(store, biz, OWNER)["people"] == []
    with pytest.raises(PosError):
        auto.winback(store, biz, BUYER)


def test_winback_days_is_a_command_center_number(env):
    auto, store, _, biz, now = env
    _bill.item = None
    regular = store.add_customer(biz, OWNER, {"name": "Lakshmi", "phone": "9300002001"})["id"]
    for days in (30, 20, 10):
        _bill(store, biz, regular, now, THURSDAY - timedelta(days=days))
    now[0] = THURSDAY
    assert auto.winback(store, biz, OWNER)["people"] == [], "10 days: not yet with the default 15"
    platform_settings.set_source(lambda: [{"status": "ACTIVE", "data": {"key": "automation.winback_days", "value": 7}}],
                                 key=uuid.uuid4().hex)
    platform_settings.invalidate()
    out = auto.winback(store, biz, OWNER)
    assert out["days"] == 7 and [p["name"] for p in out["people"]] == ["Lakshmi"]


def test_stopped_shop_help_push_once_a_week_per_shop(env):
    auto, _, _, biz, now = env
    sent = []
    notify = lambda user, **kw: sent.append((user, kw["route"], kw["event_key"])) or 1  # noqa: E731
    out = auto.nudge_stopped([{"id": biz, "owner": OWNER}, {"id": "", "owner": OWNER}], actor="staff:1", notify=notify)
    assert out == {"sent": 1, "skipped_recent": 0, "gap_days": 7} and sent[0][0] == OWNER and sent[0][1] == "/"
    again = auto.nudge_stopped([{"id": biz, "owner": OWNER}], actor="staff:1", notify=notify)
    assert again["sent"] == 0 and again["skipped_recent"] == 1 and len(sent) == 1
    assert biz in auto.nudges([biz])
    now[0] = THURSDAY + timedelta(days=8)
    assert auto.nudge_stopped([{"id": biz, "owner": OWNER}], actor="staff:1", notify=notify)["sent"] == 1


def test_ai_cost_guard_only_warns_and_alerts_once_per_day_and_level(env):
    auto, _, _, _, now = env
    assert auto.cost_guard(today_cost_inr=900)["state"] == "off", "no budget set: the guard is off"
    platform_settings.set_source(lambda: [
        {"status": "ACTIVE", "data": {"key": "automation.ai_cost_daily_inr", "value": 1000}},
        {"status": "ACTIVE", "data": {"key": "automation.ai_cost_user_daily_inr", "value": 50}}], key=uuid.uuid4().hex)
    platform_settings.invalidate()
    assert auto.cost_guard(today_cost_inr=500)["state"] == "ok"
    warn = auto.cost_guard(today_cost_inr=850, users=[{"user": "••••1001", "cost_inr": 80, "uses": 40},
                                                       {"user": "••••1002", "cost_inr": 5, "uses": 3}])
    assert warn["state"] == "warn" and warn["percent"] == 85 and [u["user"] for u in warn["heavy_users"]] == ["••••1001"]
    assert auto.cost_alert_due(warn) is True and auto.cost_alert_due(warn) is False
    over = auto.cost_guard(today_cost_inr=1200)
    assert over["state"] == "over" and auto.cost_alert_due(over) is True and auto.cost_alert_due(over) is False
    assert auto.cost_alert_due(auto.cost_guard(today_cost_inr=10)) is False
    now[0] = THURSDAY + timedelta(days=1)
    assert auto.cost_alert_due(warn) is True, "a new day"


def test_http_buyer_cards_dismiss_and_staff_pages_need_staff():
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    user = "app-phone-9411100901"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    assert client.get("/api/automations/buyer").status_code == 401
    assert client.get("/api/automations/buyer", headers=auth).json() == {"cards": []}
    done = client.post("/api/automations/dismiss", headers=auth, json={"kind": "habit", "ref": "biz_x", "forever": True})
    assert done.status_code == 200 and done.json()["forever"] is True
    assert client.post("/api/automations/dismiss", headers=auth, json={"kind": "x", "ref": "y"}).status_code == 400
    assert client.get("/api/pos/businesses/biz_missing/automations", headers=auth).status_code == 404
    assert client.get("/admin/cc/automations").status_code in (401, 403)
    assert client.post("/admin/cc/automations/stopped-shops/push", json={}).status_code in (401, 403)
    assert client.get("/admin/cc/phone-reports").status_code in (401, 403)


def test_cost_guard_job_is_registered():
    from app.services.periodic_jobs import default_jobs

    jobs = {name: every for name, every, _ in default_jobs()}
    assert jobs.get("ai_cost_guard", 0) >= 600
