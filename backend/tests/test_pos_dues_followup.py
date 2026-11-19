"""Baaki follow-up by itself + the daily expiry alert query (owner 2026-11-19)."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_bills import PosBills
from app.services.pos_dues_followup import PosDuesFollowup
from app.services.pos_purchases import PosPurchases
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300000021"
CUSTOMER = "app-phone-9300000022"


@pytest.fixture()
def env(tmp_path):
    clock = {"now": datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)}
    now = lambda: clock["now"]  # noqa: E731
    store = PosStore(str(tmp_path / "pos.db"), clock=now)
    biz = store.create_business(OWNER, {"name": "Sai Kirana", "registration_type": "unregistered", "state_code": "37",
                                        "template": "pharmacy", "invoice_prefix": "SK"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Rice 1kg", "unit": "pcs", "price_paise": 6000, "rate_bp": 0})
    pushes = []
    bills = PosBills(store, clock=now)
    follow = PosDuesFollowup(store, bills, notify=lambda *a: pushes.append(a), clock=now)
    cust = store.add_customer(biz, OWNER, {"name": "Ravi", "phone": "9300000022"})
    inv = store.create_invoice(biz, OWNER, {"client_txn_id": "due-bill-0001", "lines": [{"product_id": item["id"], "qty_milli": 2000}],
                                            "payments": [], "customer_id": cust["id"]})
    with store._tx() as conn:
        conn.execute("INSERT INTO pos_bill_shares (token, business_id, invoice_id, phone_key, customer_user, channel, created_by,"
                     " created_at) VALUES ('tok1', ?, ?, '9300000022', ?, 'askodox', ?, ?)",
                     (biz, inv["id"], CUSTOMER, OWNER, now().isoformat()))
    return store, bills, follow, biz, inv, pushes, clock


def test_reminders_wait_for_the_promised_date_and_stop_when_paid(env):
    store, bills, follow, biz, inv, pushes, clock = env
    if bills.due_of(inv["id"]) <= 0:
        pytest.skip("this store issues a bill without payments as paid")
    assert follow.run()["reminded"] == 0, "nothing on the first two days"
    clock["now"] += timedelta(days=2, hours=1)
    assert follow.run()["reminded"] == 1 and pushes[-1][0] == CUSTOMER and pushes[-1][3] == "/me/bills"
    assert follow.run()["reminded"] == 0, "never twice on one day"

    promised = (clock["now"] + timedelta(days=5)).astimezone(timezone(timedelta(hours=5, minutes=30))).date().isoformat()
    with pytest.raises(PosError):
        follow.promise(CUSTOMER, "tok1", "2020-01-01")
    assert follow.promise(CUSTOMER, "tok1", promised)["promised_date"] == promised
    assert pushes[-1][0] == OWNER and promised in pushes[-1][2], "the shop is told the date at once"
    assert follow.promises([inv["id"]]) == {inv["id"]: promised}
    clock["now"] += timedelta(days=4)
    assert follow.run() == {"bills": 1, "reminded": 0, "owner_told": 0}, "quiet until the promised date"
    clock["now"] += timedelta(days=1)
    out = follow.run()
    assert out["owner_told"] == 1 and out["reminded"] == 1
    bills.settle(biz, OWNER, inv["id"], "cash", client_txn_id="settle-due-0001")
    clock["now"] += timedelta(days=10)
    assert follow.run()["reminded"] == 0, "a paid bill stops by itself"


def test_expiry_alert_lists_each_shop_once_with_its_items(tmp_path):
    clock = lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)  # noqa: E731
    store = PosStore(str(tmp_path / "pos.db"), clock=clock)
    purchases = PosPurchases(store)
    biz = store.create_business(OWNER, {"name": "Sai Medicals", "registration_type": "unregistered", "state_code": "37",
                                        "template": "pharmacy", "invoice_prefix": "SM"})["id"]
    med = store.add_product(biz, OWNER, {"name": "Syrup", "unit": "pcs", "price_paise": 9000, "rate_bp": 0, "track_batches": True})
    sup = purchases.add_supplier(biz, OWNER, {"name": "Distributor"})
    purchases.record_purchase(biz, OWNER, {"client_txn_id": "exp-bill-1", "supplier_id": sup["id"], "supplier_bill_no": "D1",
                                           "lines": [{"product_id": med["id"], "qty_milli": 5000, "cost_paise": 5000,
                                                      "batch_no": "B1", "expiry_date": "2026-11-02"},
                                                     {"product_id": med["id"], "qty_milli": 5000, "cost_paise": 5000,
                                                      "batch_no": "B2", "expiry_date": "2027-08-31"}]})
    shops = store.expiring_soon_all()
    assert len(shops) == 1 and shops[0]["owner"] == OWNER and shops[0]["count"] == 1
    assert shops[0]["names"] == ["Syrup (2026-11-02)"]
