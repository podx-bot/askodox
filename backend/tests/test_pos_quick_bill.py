"""Quick bill -> a real invoice with advance and pending; GST only when the shop has it."""
from datetime import datetime, timezone

import pytest

from app.services.pos_quick_bill import PosQuickBill
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000101"
CASHIER = "app-phone-9400000103"


def _store(tmp_path, **business):
    store = PosStore(str(tmp_path / "q.db"), clock=lambda: datetime(2026, 11, 15, 6, 0, tzinfo=timezone.utc))
    biz = store.create_business(OWNER, {"name": "Murali Shop", "invoice_prefix": "MS", "state_code": "37", **business})["id"]
    store.set_member(biz, OWNER, "9400000103", "cashier")
    return store, biz


def test_advance_and_pending_on_a_customer(tmp_path):
    store, biz = _store(tmp_path)
    quick = PosQuickBill(store)
    out = quick.make(biz, OWNER, {"lines": [{"name": "Toor dal quarter kilo", "amount_paise": 3000},
                                            {"name": "Cashew half kilo", "amount_paise": 50000},
                                            {"name": "Chicken dum biryani", "amount_paise": 16000},
                                            {"name": "Fry", "amount_paise": 30000}],
                                  "advance_paise": 90000, "method": "upi", "name": "Ramesh", "phone": "9876543210",
                                  "client_txn_id": "qb-0000001"})
    assert out["totals"]["grand_total_paise"] == 99000
    assert out["advance_paise"] == 90000 and out["pending_paise"] == 9000
    customer = store.customers(biz, OWNER)[0]
    assert customer["name"] == "Ramesh" and customer["balance_paise"] == 9000
    # the same request again is the same bill
    again = quick.make(biz, OWNER, {"lines": [{"name": "Toor dal quarter kilo", "amount_paise": 3000},
                                              {"name": "Cashew half kilo", "amount_paise": 50000},
                                              {"name": "Chicken dum biryani", "amount_paise": 16000},
                                              {"name": "Fry", "amount_paise": 30000}],
                                    "advance_paise": 90000, "method": "upi", "name": "Ramesh", "phone": "9876543210",
                                    "client_txn_id": "qb-0000001"})
    assert again["id"] == out["id"]
    # the same name again at another price: the owner may override, a cashier may not
    quick.make(biz, OWNER, {"lines": [{"name": "Fry", "amount_paise": 32000}], "advance_paise": 32000, "client_txn_id": "qb-0000002"})
    with pytest.raises(PosError) as e:
        quick.make(biz, CASHIER, {"lines": [{"name": "Fry", "amount_paise": 31000}], "advance_paise": 31000, "client_txn_id": "qb-0000003"})
    assert e.value.status == 403


def test_needs_payment_or_customer_and_advance_not_above_total(tmp_path):
    store, biz = _store(tmp_path)
    quick = PosQuickBill(store)
    with pytest.raises(PosError):
        quick.make(biz, OWNER, {"lines": [{"name": "Rice", "amount_paise": 5000}], "client_txn_id": "qb-1000001"})
    out = quick.make(biz, OWNER, {"lines": [{"name": "Rice", "amount_paise": 5000}], "advance_paise": 99999, "client_txn_id": "qb-1000002"})
    assert out["advance_paise"] == 5000 and out["pending_paise"] == 0  # cannot pay more than the bill


def test_unregistered_shop_has_no_gst_and_registered_shop_shows_it(tmp_path):
    store, biz = _store(tmp_path)
    plain = PosQuickBill(store).make(biz, OWNER, {"lines": [{"name": "Rice 1kg", "amount_paise": 10500}], "advance_paise": 10500,
                                                  "rate_bp": 500, "client_txn_id": "qb-2000001"})
    assert plain["totals"]["tax_paise"] == 0 and plain["document_type"] != "TAX_INVOICE"
    store2 = PosStore(str(tmp_path / "g.db"), clock=lambda: datetime(2026, 11, 15, 6, 0, tzinfo=timezone.utc))
    gst = store2.create_business(OWNER, {"name": "GST Shop", "invoice_prefix": "GS", "registration_type": "regular",
                                         "gstin": "29AAGCB7383J1Z4"})["id"]
    taxed = PosQuickBill(store2).make(gst, OWNER, {"lines": [{"name": "Rice 1kg", "amount_paise": 10500}], "advance_paise": 10500,
                                                   "rate_bp": 500, "client_txn_id": "qb-2000002"})
    assert taxed["totals"]["tax_paise"] == 500 and taxed["totals"]["grand_total_paise"] == 10500
