"""Morning brief (owner 2026-11-27): at most three things to do today from the engines that exist, real counts only,
nothing sent from here, a part the caller may not do is absent, a non-member gets the shop's 404."""
import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.services import platform_settings
from app.services.automations import Automations
from app.services.morning_brief import MAX_TASKS, MorningBrief
from app.services.pos_bills import PosBills
from app.services.pos_dues_followup import PosDuesFollowup
from app.services.pos_frontdesk import PosFrontDesk
from app.services.pos_purchases import PosPurchases
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300002001"
CASHIER = "app-phone-9300002002"
BUYER = "app-phone-9300002003"
STRANGER = "app-phone-9300002009"
IST = timezone(timedelta(hours=5, minutes=30))
FRIDAY = datetime(2026, 11, 27, 7, 0, tzinfo=IST)


@pytest.fixture()
def env(tmp_path):
    saved = (platform_settings._SOURCE, platform_settings._SOURCE_KEY)
    platform_settings.set_source(lambda: [])
    platform_settings.invalidate()
    now = [FRIDAY]
    clock = lambda: now[0].astimezone(timezone.utc)  # noqa: E731
    db = str(tmp_path / "b.db")
    store = PosStore(db, clock=clock)
    PosFrontDesk(store, PosRestaurant(store), notify=lambda *a: None, pay_to=lambda *a: [])
    PosPurchases(store)
    bills = PosBills(store, clock=clock)
    dues = PosDuesFollowup(store, bills, clock=clock)
    biz = store.create_business(OWNER, {"name": "Sample Kirana", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9300002002", "cashier")
    yield MorningBrief(db, clock=clock), Automations(db, clock=clock), store, bills, dues, biz, now
    platform_settings._SOURCE, platform_settings._SOURCE_KEY = saved
    platform_settings.invalidate()


def _bill(store, biz, *, paid, phone="", days_ago=0, now=FRIDAY):
    product = store.add_product(biz, OWNER, {"name": "Rice " + uuid.uuid4().hex[:4], "price_paise": 10000, "unit": "pcs"})
    customer = store.add_customer(biz, OWNER, {"name": "Customer", "phone": phone})["id"] if phone else None
    invoice = store.create_invoice(biz, OWNER, {
        "client_txn_id": uuid.uuid4().hex, "customer_id": customer,
        "lines": [{"product_id": product["id"], "qty_milli": 1000}],
        "payments": [{"method": "cash", "amount_paise": 10000}] if paid else []})
    if days_ago:
        day = (now.astimezone(IST).date() - timedelta(days=days_ago)).isoformat()
        with store._connect() as conn:
            conn.execute("UPDATE pos_invoices SET local_date = ? WHERE id = ?", (day, invoice["id"]))
            conn.commit()
    return invoice


def test_an_empty_shop_has_nothing_to_do_and_no_invented_numbers(env):
    brief, autos, store, _, dues, biz, _ = env
    out = brief.shop(store, dues, autos, biz, OWNER)
    assert out["tasks"] == [] and out["more"] == 0 and out["scope"] == "shop" and out["approve_first"] is True
    assert out["handled"]["bills"] == 0 and out["day"] == "2026-11-27" and out["weekday"] == 4


def test_yesterday_and_a_due_reminder_show_with_real_counts(env):
    brief, autos, store, _, dues, biz, _ = env
    _bill(store, biz, paid=True, days_ago=1)
    _bill(store, biz, paid=True, days_ago=1)
    _bill(store, biz, paid=False, phone="9300002050", days_ago=6)  # pay date = 7 days after: tomorrow -> remind today
    out = brief.shop(store, dues, autos, biz, OWNER)
    keys = [task["key"] for task in out["tasks"]]
    assert keys == ["dues", "yesterday"], keys
    due, look = out["tasks"]
    assert due == {"key": "dues", "action": "send", "count": 1, "route": f"/pos/{biz}/dues"}
    assert look["count"] == 2 and look["amount_paise"] == 20000 and look["action"] == "view"
    assert out["handled"]["bills"] == 2 and out["handled"]["day"] == "2026-11-26"


def test_reading_the_brief_sends_and_marks_nothing(env):
    brief, autos, store, _, dues, biz, _ = env
    _bill(store, biz, paid=False, phone="9300002051", days_ago=6)
    with store._connect() as conn:
        before = (conn.execute("SELECT COUNT(*) FROM pos_bill_shares").fetchone()[0],
                  conn.execute("SELECT COUNT(*) FROM pos_due_followups").fetchone()[0])
    for _ in range(2):
        assert brief.shop(store, dues, autos, biz, OWNER)["tasks"][0]["count"] == 1
    with store._connect() as conn:
        after = (conn.execute("SELECT COUNT(*) FROM pos_bill_shares").fetchone()[0],
                 conn.execute("SELECT COUNT(*) FROM pos_due_followups").fetchone()[0])
    assert before == after


def test_a_reminder_already_sent_today_leaves_the_list(env):
    brief, autos, store, _, dues, biz, _ = env
    invoice = _bill(store, biz, paid=False, phone="9300002052", days_ago=6)
    dues.mark_sent(biz, OWNER, invoice["id"])
    assert [t["key"] for t in brief.shop(store, dues, autos, biz, OWNER)["tasks"]] == []


def test_never_more_than_three_and_the_rest_is_counted(env):
    brief, autos, store, _, dues, biz, _ = env
    found = [{"key": k} for k in ("a", "b", "c", "d", "e")]
    head = brief._head(found)
    assert len(head["tasks"]) == MAX_TASKS and head["more"] == 2


def test_staff_see_only_their_own_work_and_a_stranger_sees_no_shop(env):
    brief, autos, store, _, dues, biz, _ = env
    _bill(store, biz, paid=True, days_ago=1)
    out = brief.shop(store, dues, autos, biz, CASHIER)
    assert "yesterday" not in [t["key"] for t in out["tasks"]] and "handled" not in out
    with pytest.raises(PosError) as error:
        brief.shop(store, dues, autos, biz, STRANGER)
    assert error.value.status == 404


def test_my_side_counts_my_unpaid_bills_without_marking_them_seen(env):
    brief, autos, store, bills, _, biz, _ = env
    assert brief.me(bills, autos, BUYER)["tasks"] == []
    invoice = _bill(store, biz, paid=False, phone="9300002003")
    bills.share_to_user(biz, invoice["id"], BUYER, OWNER)
    out = brief.me(bills, autos, BUYER)
    assert out["scope"] == "me"
    assert out["tasks"] == [{"key": "my_bills", "action": "view", "count": 1, "amount_paise": 10000, "route": "/me/bills"}]
    with store._connect() as conn:
        assert conn.execute("SELECT COUNT(*) FROM pos_bill_shares WHERE seen_at IS NOT NULL").fetchone()[0] == 0
    assert json.dumps(out)  # plain data only


def test_memberships_ending_join_the_brief_after_the_dues(env):
    from app.services.pos_memberships import PosMemberships

    brief, autos, store, _, dues, biz, now = env
    terms = PosMemberships(store, clock=lambda: now[0].astimezone(timezone.utc))
    assert brief.shop(store, dues, autos, biz, OWNER, terms)["tasks"] == []
    terms.add(biz, OWNER, {"name": "Member", "phone": "9300002060", "months": 1, "fee_paise": 150000,
                           "start_date": "2026-10-29"})  # ends 29 Nov: two days from this Friday
    task = brief.shop(store, dues, autos, biz, OWNER, terms)["tasks"][0]
    assert task == {"key": "renewals", "action": "send", "count": 1, "route": f"/biz/{biz}/members"}
