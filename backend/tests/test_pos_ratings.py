"""Ratings (stars only, real buyers), reviews (shop only, masked), shop page, welcome, menu sort, split / revised bills."""
from datetime import timedelta

import pytest

from app.services.pos_frontdesk import QR_PREFIX
from app.services.pos_menu_sort import sort_menu
from app.services.pos_quick_bill import PosQuickBill
from app.services.pos_store import PosError
from tests.test_pos_frontdesk import CUSTOMER, OWNER, env  # noqa: F401  (fixture)


def _finished_order(desk, store, biz, item, txn="rate0001"):
    order = desk.place(CUSTOMER, f"{QR_PREFIX}{biz}", {"items": [{"product_id": item, "qty": 1}], "kind": "takeaway",
                                                       "client_txn_id": "txn-" + txn})
    desk.confirm(biz, OWNER, order["id"])
    for stage in ("preparing", "ready", "packed", "handed"):
        desk.advance(biz, OWNER, order["id"], stage)
    return order["id"]


def test_only_a_real_buyer_rates_once_and_the_menu_shows_it(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    oid = _finished_order(desk, store, biz, biryani)
    ask = desk.ratings.ask(CUSTOMER, oid)
    assert ask and [i["product_id"] for i in ask["items"]] == [biryani]
    assert desk.ratings.ask("app-phone-9000000009", oid) is None  # not their order
    desk.ratings.rate(CUSTOMER, oid, 4, {biryani: 5, "not-in-order": 1})
    assert desk.ratings.ask(CUSTOMER, oid) is None  # rated: never asked again
    seen = desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)
    assert seen["business"]["rating"]["average"] == 4.0 and seen["business"]["rating"]["count"] == 1
    assert next(m for m in seen["menu"] if m["id"] == biryani)["rating"] == {"average": 5.0, "count": 1}
    with pytest.raises(PosError):
        desk.ratings.rate(CUSTOMER, oid, 9, {})


def test_later_asks_once_more_the_next_day_then_never(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    oid = _finished_order(desk, store, biz, biryani, "rate0002")
    desk.ratings.rate(CUSTOMER, oid, None, {}, later=True)
    assert desk.ratings.ask(CUSTOMER, oid) is None
    now[0] = now[0] + timedelta(days=1)
    assert desk.ratings.ask(CUSTOMER, oid) is not None
    desk.ratings.rate(CUSTOMER, oid, None, {}, later=True)
    now[0] = now[0] + timedelta(days=2)
    assert desk.ratings.ask(CUSTOMER, oid) is None


def test_reviews_are_for_buyers_masked_replied_and_hidden_after_reports(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    with pytest.raises(PosError) as e:
        desk.ratings.write_review(CUSTOMER, biz, 5, "super", [])
    assert e.value.code == "not_customer"
    _finished_order(desk, store, biz, biryani, "rate0003")
    with pytest.raises(PosError):
        desk.ratings.write_review(OWNER, biz, 5, "my own shop", [])
    rev = desk.ratings.write_review(CUSTOMER, biz, 5, "biryani super, call 9876543210", [])
    assert "9876543210" not in rev["text"]
    desk.ratings.write_review(CUSTOMER, biz, 4, "changed my mind", [])  # one review per person, edited
    page = desk.ratings.shop_page(biz, CUSTOMER)
    assert len(page["reviews"]) == 1 and page["reviews"][0]["stars"] == 4 and page["reviews"][0]["mine"]
    assert page["rating"]["count"] == 1 and page["can_review"]
    desk.ratings.reply(biz, OWNER, rev["id"], "thank you!")
    assert desk.ratings.shop_page(biz, "app-phone-9000000001")["reviews"][0]["reply"] == "thank you!"
    for who in ("app-phone-9000000001", "app-phone-9000000002", "app-phone-9000000003"):
        desk.ratings.report(who, rev["id"])
    assert desk.ratings.shop_page(biz, "app-phone-9000000004")["reviews"] == []  # held for staff after 3 reports


def test_welcome_uses_the_persons_own_name_and_the_shops_words(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    with store._tx() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS user_profiles (user_id TEXT PRIMARY KEY, name TEXT)")
        conn.execute("INSERT OR REPLACE INTO user_profiles (user_id, name) VALUES (?, ?)", (CUSTOMER, "Rajesh"))
    first = desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["welcome"]
    assert first["returning"] is False and "Rajesh" in first["text"] and "స్వాగతం" in first["text"]
    _finished_order(desk, store, biz, biryani, "rate0004")
    again = desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["welcome"]
    assert again["returning"] and again["favourite"] == "Chicken Biryani" and "మళ్ళీ" in again["text"]
    assert desk.resolve(f"{QR_PREFIX}{biz}", OWNER)["welcome"] is None  # never greets the owner in his own shop
    desk.ratings.set_welcome(biz, OWNER, {"enabled": False})
    assert desk.resolve(f"{QR_PREFIX}{biz}", CUSTOMER)["welcome"] is None


def test_menu_sort_reads_names_and_keeps_old_values_when_silent():
    calls = []

    def model(prompt, max_tokens=0):
        calls.append(prompt)
        return '{"items": [{"i": 1, "group": "Biryani", "food": "nonveg"}, {"i": 2, "group": "Curries", "food": "veg"}]}'

    out = sort_menu([{"id": "a", "name": "Chicken Biryani"}, {"id": "b", "name": "Paneer Butter Masala"},
                     {"id": "c", "name": "Thums Up", "menu_group": "Drinks", "food_type": ""}], model)
    assert out["read"] and [(r["menu_group"], r["food_type"]) for r in out["items"]] == [
        ("Biryani", "nonveg"), ("Curries", "veg"), ("Drinks", "")]
    assert sort_menu([{"id": "a", "name": "x"}], lambda p, max_tokens=0: "no json")["read"] is False


def test_cash_plus_online_bill_leaves_the_rest_due_and_a_revised_bill_replaces_the_old(env):
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    quick = PosQuickBill(store)
    bill = quick.make(biz, OWNER, {"lines": [{"name": "Chicken", "amount_paise": 180000}], "cash_paise": 100000,
                                   "online_paise": 60000, "method": "phonepe", "name": "Ravi", "phone": "9876543210",
                                   "client_txn_id": "split-0001"})
    assert bill["pending_paise"] == 20000
    paper = desk.bills.paper_for(biz, OWNER, bill["id"])
    assert (paper["cash_paise"], paper["online_paise"], paper["due_paise"], paper["bill_kind"]) == (100000, 60000, 20000, "part")
    assert paper["online_apps"] == ["PhonePe"] and paper["gst"] is False and paper["customer_name"] == "Ravi"
    with pytest.raises(PosError):
        quick.make(biz, OWNER, {"lines": [{"name": "Tea", "amount_paise": 1000}], "cash_paise": 900, "online_paise": 900,
                                "client_txn_id": "split-0002"})
    new = quick.make(biz, OWNER, {"lines": [{"name": "Chicken", "amount_paise": 180000}, {"name": "Egg", "amount_paise": 1000}],
                                  "cash_paise": 181000, "name": "Ravi", "revise_of": bill["id"], "client_txn_id": "split-0003"})
    assert new["revised_from"] == bill["number"]
    assert desk.bills.paper_for(biz, OWNER, bill["id"])["status"] == "cancelled"
    assert desk.bills.paper_for(biz, OWNER, new["id"])["bill_kind"] == "cash"
