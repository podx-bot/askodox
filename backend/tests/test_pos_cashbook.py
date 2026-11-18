import pytest

from app.services.pos_cashbook import PosCashbook
from app.services.pos_store import PosError
from tests.test_pos_frontdesk import OWNER, env  # noqa: F401  (fixture)


def test_entries_month_totals_remove_undo_and_repeat(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    book = PosCashbook(store)
    a = book.add(biz, OWNER, {"kind": "expense", "amount_paise": 120000, "category": "stock", "note": "vegetables",
                             "client_txn_id": "t1"})
    assert book.add(biz, OWNER, {"kind": "expense", "amount_paise": 120000, "client_txn_id": "t1"})["repeat"]
    book.add(biz, OWNER, {"kind": "income", "amount_paise": 500000, "category": "catering", "client_txn_id": "t2"})
    month = book.month(biz, OWNER)
    assert month["expense_paise"] == 120000 and month["income_paise"] >= 500000
    assert month["expense_by_category"] == {"stock": 120000}
    book.remove(biz, OWNER, a["id"])
    assert book.month(biz, OWNER)["expense_paise"] == 0
    book.remove(biz, OWNER, a["id"], undo=True)
    assert book.month(biz, OWNER)["expense_paise"] == 120000
    with pytest.raises(PosError):
        book.add(biz, OWNER, {"kind": "expense", "amount_paise": 0})
    with pytest.raises(PosError):
        book.month(biz, "app-phone-9000000009")  # not a member


def test_dues_group_by_person_biggest_first(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, pushes = env
    book = PosCashbook(store)
    bills = [{"customer_name": "Rajesh", "customer_phone_last4": "1111", "due_paise": 30000, "local_date": "2026-11-10"},
             {"customer_name": "Rajesh", "customer_phone_last4": "1111", "due_paise": 50000, "local_date": "2026-11-12"},
             {"customer_name": "Suresh", "customer_phone_last4": "2222", "due_paise": 60000, "local_date": "2026-11-15"},
             {"customer_name": "Paid", "customer_phone_last4": "3333", "due_paise": 0, "local_date": "2026-11-15"}]
    out = book.dues(biz, OWNER, bills)
    assert [p["name"] for p in out["people"]] == ["Rajesh", "Suresh"]
    assert out["people"][0]["due_paise"] == 80000 and out["people"][0]["oldest"] == "2026-11-10"
    assert out["total_paise"] == 140000
