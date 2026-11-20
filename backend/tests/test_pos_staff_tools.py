"""Per-staff tools the owner ticks (owner 2026-11-20): staff get only what the owner gave, never more than the role."""
import sqlite3

import pytest

from app.services.pos_store import PosError, PosStore, start_tools

OWNER = "app-phone-9400000001"
CASHIER = "app-phone-9400000002"


@pytest.fixture()
def shop(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    biz = store.create_business(OWNER, {"name": "Murali Chicken", "registration_type": "unregistered", "state_code": "37",
                                        "template": "meat_fish", "invoice_prefix": "MC"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Chicken", "unit": "kg", "price_paise": 25000, "rate_bp": 0})
    return store, biz, item


def test_ticks_limit_staff_and_only_the_owner_sets_them(shop):
    store, biz, item = shop
    # a new staff member from the app: only payment alerts ticked
    out = store.set_member(biz, OWNER, "9400000002", "cashier", tools=start_tools("cashier"))
    assert out["tools"] == ["payalerts"]
    me = store.business(biz, CASHIER)
    assert me["tools"] == ["payalerts"] and me["permissions"] == ["view"]
    with pytest.raises(PosError) as err:
        store.create_invoice(biz, CASHIER, {"client_txn_id": "staff-bill-0001",
                                            "lines": [{"product_id": item["id"], "qty_milli": 1000}],
                                            "payments": [{"method": "cash", "amount_paise": 25000}]})
    assert err.value.status == 403
    # the owner ticks billing: now the cashier can bill
    store.member_by_ref(biz, OWNER, "0002", "cashier", tools=["payalerts", "sale"])
    assert "sell" in store.business(biz, CASHIER)["permissions"]
    store.create_invoice(biz, CASHIER, {"client_txn_id": "staff-bill-0002",
                                        "lines": [{"product_id": item["id"], "qty_milli": 1000}],
                                        "payments": [{"method": "cash", "amount_paise": 25000}]})
    # a tick never gives more than the role: a cashier ticked "gst" still cannot read reports
    store.member_by_ref(biz, OWNER, "0002", "cashier", tools=["gst"])
    assert "reports" not in store.business(biz, CASHIER)["permissions"]
    with pytest.raises(PosError):
        store.member_by_ref(biz, OWNER, "0002", "cashier", tools=["everything"])
    listed = [m for m in store.members(biz, OWNER) if m["role"] == "cashier"][0]
    assert listed["tools"] == ["gst"] and "sale" in listed["role_tools"] and "gst" not in listed["role_tools"]


def test_members_from_before_get_payment_alerts_only(tmp_path):
    path = str(tmp_path / "old.db")
    store = PosStore(path)
    biz = store.create_business(OWNER, {"name": "Old Shop", "registration_type": "unregistered", "state_code": "37",
                                        "template": "general", "invoice_prefix": "OS"})["id"]
    store.set_member(biz, OWNER, "9400000002", "cashier")
    store.set_member(biz, OWNER, "9400000003", "manager")
    store.set_member(biz, OWNER, "9400000004", "kitchen")
    assert store.business(biz, CASHIER)["tools"] is None, "an API caller without ticks keeps the role's set"
    with sqlite3.connect(path) as conn:  # an older database: the column did not exist yet
        conn.execute("ALTER TABLE pos_members DROP COLUMN tools")
    store = PosStore(path)
    assert store.business(biz, CASHIER)["tools"] == ["payalerts"]
    assert store.business(biz, "app-phone-9400000003")["tools"] is None, "managers keep everything"
    assert store.business(biz, "app-phone-9400000004")["tools"] == ["kitchen"]
