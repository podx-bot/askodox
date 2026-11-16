"""Sales page: day / week / month from the shop's own bills only."""
from datetime import datetime, timezone

import pytest

from app.services.pos_quick_bill import PosQuickBill
from app.services.pos_sales import PosSales, period_range
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000101"
CASHIER = "app-phone-9400000103"
NOW = [datetime(2026, 11, 16, 6, 0, tzinfo=timezone.utc)]  # a Monday


def _setup(tmp_path):
    store = PosStore(str(tmp_path / "s.db"), clock=lambda: NOW[0])
    biz = store.create_business(OWNER, {"name": "Murali Shop", "invoice_prefix": "MS", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000103", "cashier")
    return store, biz


def test_period_ranges():
    assert [d.isoformat() for d in period_range("week", "2026-11-18")] == ["2026-11-16", "2026-11-22"]
    assert [d.isoformat() for d in period_range("month", "2026-02-10")] == ["2026-02-01", "2026-02-28"]
    assert [d.isoformat() for d in period_range("day", "2026-11-16")] == ["2026-11-16", "2026-11-16"]


def test_sales_come_from_bills_and_split_by_day_payment_and_item(tmp_path):
    store, biz = _setup(tmp_path)
    quick = PosQuickBill(store)
    quick.make(biz, OWNER, {"lines": [{"name": "Chicken dum biryani", "amount_paise": 30000}], "method": "cash",
                            "advance_paise": 30000, "name": "Ramesh", "phone": "9876543210", "client_txn_id": "sale-0001"})
    quick.make(biz, OWNER, {"lines": [{"name": "Chicken dum biryani", "amount_paise": 30000},
                                      {"name": "Fry", "amount_paise": 20000}], "method": "upi",
                            "advance_paise": 20000, "name": "Suresh", "phone": "9876500000", "client_txn_id": "sale-0002"})
    NOW[0] = datetime(2026, 11, 17, 6, 0, tzinfo=timezone.utc)
    quick.make(biz, OWNER, {"lines": [{"name": "Tea", "amount_paise": 1000}], "method": "cash", "advance_paise": 1000,
                            "name": "Ravi", "phone": "9876511111", "client_txn_id": "sale-0003"})
    sales = PosSales(store)
    day = sales.summary(biz, OWNER, "day", "2026-11-16")
    assert day["bills"] == 2 and day["sales_paise"] == 80000 and day["dues_paise"] == 30000
    assert {p["method"]: p["amount_paise"] for p in day["payments"]} == {"cash": 30000, "upi": 20000}
    assert day["top_items"][0]["name"] == "Chicken dum biryani" and day["top_items"][0]["total_paise"] == 60000
    week = sales.summary(biz, OWNER, "week", "2026-11-17")
    assert week["bills"] == 3 and week["sales_paise"] == 81000 and len(week["days"]) == 7
    assert week["days"][0]["date"] == "2026-11-16" and week["days"][0]["sales_paise"] == 80000
    assert week["days"][1]["bills"] == 1
    month = sales.summary(biz, OWNER, "month")  # default anchor = today
    assert month["bills"] == 3 and month["recent"][0]["customer"] == "Ravi"
    with pytest.raises(PosError):  # a cashier does not see the shop's totals
        sales.summary(biz, CASHIER, "day")
    with pytest.raises(PosError):
        sales.summary(biz, OWNER, "year")
    with pytest.raises(PosError):
        sales.summary(biz, OWNER, "day", "2026-13-45")
