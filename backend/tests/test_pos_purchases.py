"""POS suppliers / purchase bills / supplier ledger / batch + expiry (FEFO, expired never
sold) / valuation / input tax as recorded."""
import uuid
from datetime import datetime, timezone

import pytest

from app.services import pos_tax
from app.services.pos_purchases import PosPurchases
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300000001"
CASHIER = "app-phone-9300000002"


def _gstin(state, pan="AAPFU0939F"):
    head = f"{state}{pan}1Z"
    return head + pos_tax.gstin_check_char(head)


def _txn():
    return "t-" + uuid.uuid4().hex


@pytest.fixture()
def env(tmp_path):
    clock = {"now": datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)}
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: clock["now"])
    pur = PosPurchases(store)
    biz = store.create_business(OWNER, {"name": "Sri Sai Medicals", "registration_type": "regular",
                                        "gstin": _gstin("37"), "template": "pharmacy", "invoice_prefix": "SS"})["id"]
    store.set_member(biz, OWNER, "9300000002", "cashier")
    med = store.add_product(biz, OWNER, {"name": "Paracetamol 500 strip", "unit": "pcs", "price_paise": 3000,
                                         "rate_bp": 500, "hsn_sac": "3004", "track_batches": True})
    sup = pur.add_supplier(biz, OWNER, {"name": "Vijaya Pharma Distributors", "gstin": _gstin("37", "AAGCB7383J")})
    return store, pur, biz, med["id"], sup["id"], clock


def test_purchase_bill_stock_ledger_and_duplicates(env):
    store, pur, biz, med, sup, _ = env
    bill = pur.record_purchase(biz, OWNER, {"client_txn_id": "bill-0001", "supplier_id": sup, "supplier_bill_no": "VP/889",
                                            "lines": [{"product_id": med, "qty_milli": 100000, "cost_paise": 2000,
                                                       "batch_no": "B1", "expiry_date": "2026-11-30"},
                                                      {"product_id": med, "qty_milli": 50000, "cost_paise": 2100,
                                                       "batch_no": "B2", "expiry_date": "2027-06-30"}],
                                            "supplier_total_paise": 320250})
    # 100 x 20 + 50 x 21 = 3050 taxable; 5% intra = 76.25 + 76.25 -> 3202.50
    assert bill["totals"]["taxable_paise"] == 305000 and bill["totals"]["cgst_paise"] == 7625
    assert bill["totals"]["total_paise"] == 320250 and bill["totals"]["round_off_paise"] == 0
    assert "accountant" in bill["totals"]["input_tax_note"]
    assert pur.record_purchase(biz, OWNER, {"client_txn_id": "bill-0001", "supplier_id": sup, "supplier_bill_no": "VP/889",
                                            "lines": [{"product_id": med, "qty_milli": 100000, "cost_paise": 2000,
                                                                "batch_no": "B1", "expiry_date": "2026-11-30"},
                                                               {"product_id": med, "qty_milli": 50000, "cost_paise": 2100,
                                                                "batch_no": "B2", "expiry_date": "2027-06-30"}],
                                            "supplier_total_paise": 320250})["replayed"]
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "VP/889",
                                         "lines": [{"product_id": med, "qty_milli": 1000, "cost_paise": 100, "batch_no": "B9"}]})
    assert e.value.code == "duplicate_bill"
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "VP/890",
                                         "lines": [{"product_id": med, "qty_milli": 1000, "cost_paise": 100, "batch_no": "B9"}],
                                         "supplier_total_paise": 99999})
    assert e.value.code == "total_mismatch"
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "VP/891",
                                         "lines": [{"product_id": med, "qty_milli": 1000, "cost_paise": 100}]})
    assert e.value.code == "batch_no"
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, CASHIER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "X",
                                           "lines": [{"product_id": med, "qty_milli": 1, "cost_paise": 1, "batch_no": "B"}]})
    assert e.value.status == 403, "a cashier cannot record purchases"
    assert store.product(biz, OWNER, med)["stock_milli"] == 150000
    assert pur.supplier(biz, OWNER, sup)["owed_paise"] == 320250
    pur.pay_supplier(biz, OWNER, sup, {"client_txn_id": "pay-00001", "method": "bank_transfer", "amount_paise": 200000})
    assert pur.pay_supplier(biz, OWNER, sup, {"client_txn_id": "pay-00001", "method": "bank_transfer",
                                              "amount_paise": 200000})["replayed"]
    st = pur.supplier_statement(biz, OWNER, sup, "2026-10")
    assert [e["balance_paise"] for e in st["entries"]] == [320250, 120250]
    val = pur.valuation(biz, OWNER)
    item = val["items"][0]
    assert item["avg_cost_paise"] == 2033 and item["value_paise"] == 150000 * 2033 // 1000
    tax = pur.input_tax(biz, OWNER, "2026-10-01", "2026-10-31")
    assert tax["totals"]["cgst_paise"] == 7625 and "not by ASKODOX" in tax["disclaimer"]
    cancelled = pur.cancel_purchase(biz, OWNER, bill["id"], "wrong supplier")
    assert cancelled["status"] == "cancelled" and store.product(biz, OWNER, med)["stock_milli"] == 0
    assert pur.supplier(biz, OWNER, sup)["owed_paise"] == -200000, "the payment stays; the bill is reversed"


def test_fefo_never_sells_expired_and_returns_go_back_to_batch(env):
    store, pur, biz, med, sup, clock = env
    pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "A1",
                                     "lines": [{"product_id": med, "qty_milli": 5000, "cost_paise": 2000, "batch_no": "OLD",
                                                "expiry_date": "2026-10-23"},
                                               {"product_id": med, "qty_milli": 3000, "cost_paise": 2000, "batch_no": "SOON",
                                                "expiry_date": "2026-11-15"},
                                               {"product_id": med, "qty_milli": 10000, "cost_paise": 2000, "batch_no": "LATER",
                                                "expiry_date": "2027-12-31"}]})
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [{"product_id": med, "qty_milli": 5000}],
                                              "payments": [{"method": "cash", "amount_paise": 15000}]})
    assert inv["lines"][0]["batches"] == [
        {"batch_no": "SOON", "expiry_date": "2026-11-15", "qty_milli": 3000},
        {"batch_no": "LATER", "expiry_date": "2027-12-31", "qty_milli": 2000},
    ], "first-expiry-first-out, the expired OLD batch is skipped"
    batches = {b["batch_no"]: b for b in store.batches(biz, OWNER, med)}
    assert batches["OLD"]["expired"] and batches["OLD"]["qty_milli"] == 5000 and "SOON" not in batches
    report = store.expiry_report(biz, OWNER, 30)
    assert [(i["batch_no"], i["expired"]) for i in report["items"]] == [("OLD", True)]
    note = store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "returned",
                                                            "lines": [{"line_no": 1, "qty_milli": 4000}],
                                                            "refund": {"method": "cash", "amount_paise": 12000}})
    assert note["totals"]["grand_total_paise"] == 12000
    batches = {b["batch_no"]: b["qty_milli"] for b in store.batches(biz, OWNER, med)}
    assert batches["SOON"] == 3000 and batches["LATER"] == 9000
    # sell everything that is not expired, then only expired stock is left -> refused
    store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [{"product_id": med, "qty_milli": 12000}],
                                        "payments": [{"method": "cash", "amount_paise": 36000}]})
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [{"product_id": med, "qty_milli": 1000}],
                                            "payments": [{"method": "cash", "amount_paise": 3000}]})
    assert e.value.code == "expired_stock" and "OLD" in e.value.message
    store.stock_move(biz, OWNER, {"product_id": med, "kind": "wastage", "qty_milli": 5000, "batch_no": "OLD",
                                  "reason": "expired, returned to distributor"})
    assert store.batches(biz, OWNER, med) == []


def test_http_purchase_routes(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_purchases", None, raising=False)
    owner = f"app-phone-97{uuid.uuid4().int % 10**8:08d}"
    h = {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}
    c = TestClient(app)
    biz = c.post("/api/pos/businesses", headers=h, json={"name": "Kirana", "state_code": "36"}).json()
    item = c.post(f"/api/pos/businesses/{biz['id']}/products", headers=h,
                  json={"name": "Rice", "unit": "kg", "price_paise": 6000, "track_stock": True}).json()
    sup = c.post(f"/api/pos/businesses/{biz['id']}/suppliers", headers=h, json={"name": "Local mill"}).json()
    bill = c.post(f"/api/pos/businesses/{biz['id']}/purchases", headers=h,
                  json={"client_txn_id": _txn(), "supplier_id": sup["id"], "supplier_bill_no": "12",
                        "lines": [{"product_id": item["id"], "qty_milli": 25000, "cost_paise": 4800}]})
    assert bill.status_code == 200 and bill.json()["totals"]["tax_paise"] == 0, "unregistered supplier: no GST"
    assert c.get(f"/api/pos/businesses/{biz['id']}/reports/valuation", headers=h).json()["total_value_paise"] == 120000
    assert c.get(f"/api/pos/businesses/{biz['id']}/suppliers").status_code == 401
