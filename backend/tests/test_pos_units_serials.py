"""POS selling units (box <-> pieces), serial / IMEI tracking, purchase orders."""
import uuid
from datetime import datetime, timezone

import pytest

from app.services import pos_tax
from app.services.pos_purchases import PosPurchases
from app.services.pos_store import PosError, PosStore, imei_valid

OWNER = "app-phone-9400000001"
CASHIER = "app-phone-9400000002"


def _gstin(state, pan="AAPFU0939F"):
    head = f"{state}{pan}1Z"
    return head + pos_tax.gstin_check_char(head)


def _txn():
    return "t-" + uuid.uuid4().hex


def _imei(fourteen):
    total = 0
    for i, ch in enumerate(fourteen):
        d = int(ch) * (2 if i % 2 else 1)
        total += d - 9 if d > 9 else d
    return fourteen + str((10 - total % 10) % 10)


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    pur = PosPurchases(store)
    biz = store.create_business(OWNER, {"name": "Ravi Mobiles & General", "registration_type": "regular",
                                        "gstin": _gstin("36"), "template": "electronics", "invoice_prefix": "RM"})["id"]
    store.set_member(biz, OWNER, "9400000002", "cashier")
    sup = pur.add_supplier(biz, OWNER, {"name": "Distributor", "gstin": _gstin("36", "AAGCB7383J")})["id"]
    return store, pur, biz, sup


def test_imei_check_digit():
    assert imei_valid("490154203237518")  # commonly published sample IMEI
    assert not imei_valid("490154203237519")
    assert not imei_valid("49015420323751")


def test_box_and_pieces(env):
    store, pur, biz, sup = env
    soap = store.add_product(biz, OWNER, {"name": "Soap", "unit": "pcs", "price_paise": 4000, "rate_bp": 1800,
                                          "hsn_sac": "3401", "track_stock": True})
    with pytest.raises(PosError):
        store.set_pack(biz, CASHIER, soap["id"], {"name": "box", "factor_milli": 12000})
    with pytest.raises(PosError):
        store.set_pack(biz, OWNER, soap["id"], {"name": "pcs", "factor_milli": 1000})
    p = store.set_pack(biz, OWNER, soap["id"], {"name": "box", "factor_milli": 12000, "price_paise": 45000,
                                                 "barcode": "8901111111111"})
    assert p["packs"] == [{"name": "box", "factor_milli": 12000, "price_paise": 45000, "barcode": "8901111111111"}]
    assert [x["id"] for x in store.products(biz, OWNER, "8901111111111")] == [soap["id"]], "box barcode finds the item"
    pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "D1",
                                     "lines": [{"product_id": soap["id"], "pack": "box", "qty_milli": 10000,
                                                "cost_paise": 36000}]})
    assert store.product(biz, OWNER, soap["id"])["stock_milli"] == 120000, "10 boxes = 120 pcs"
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
        {"product_id": soap["id"], "pack": "box", "qty_milli": 2000},
        {"product_id": soap["id"], "qty_milli": 5000}],
        "payments": [{"method": "cash", "amount_paise": 110000}]})
    box_line, pcs_line = inv["lines"]
    assert (box_line["unit"], box_line["qty_milli"], box_line["base_qty_milli"], box_line["unit_price_paise"]) == \
        ("box", 2000, 24000, 45000)
    assert pcs_line["unit"] == "pcs" and inv["totals"]["grand_total_paise"] == 90000 + 20000
    assert store.product(biz, OWNER, soap["id"])["stock_milli"] == 120000 - 24000 - 5000
    store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "1 box back",
                                                     "lines": [{"line_no": 1, "qty_milli": 1000}],
                                                     "refund": {"method": "cash", "amount_paise": 45000}})
    assert store.product(biz, OWNER, soap["id"])["stock_milli"] == 120000 - 12000 - 5000
    val = pur.valuation(biz, OWNER)["items"][0]
    assert val["avg_cost_paise"] == 3000, "cost per piece = Rs 360 a box / 12"


def test_imei_purchase_sale_return_lookup(env):
    store, pur, biz, sup = env
    phone = store.add_product(biz, OWNER, {"name": "Phone X 128GB", "unit": "pcs", "price_paise": 1500000, "rate_bp": 1800,
                                           "hsn_sac": "8517", "track_serials": True, "serial_kind": "imei"})
    a, b = _imei("35123456789012"), _imei("35123456789023")
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "P1",
                                         "lines": [{"product_id": phone["id"], "qty_milli": 2000, "cost_paise": 1200000,
                                                    "serials": [a, "351234567890125"]}]})
    assert e.value.code == "imei"
    with pytest.raises(PosError) as e:
        pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "P1",
                                         "lines": [{"product_id": phone["id"], "qty_milli": 2000, "cost_paise": 1200000,
                                                    "serials": [a]}]})
    assert e.value.code == "serials"
    bill = pur.record_purchase(biz, OWNER, {"client_txn_id": _txn(), "supplier_id": sup, "supplier_bill_no": "P1",
                                            "lines": [{"product_id": phone["id"], "qty_milli": 2000, "cost_paise": 1200000,
                                                       "serials": [a, b]}]})
    assert store.serials_in_stock(biz, OWNER, phone["id"]) == sorted([a, b])
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [{"product_id": phone["id"], "qty_milli": 1000}],
                                            "payments": [{"method": "cash", "amount_paise": 1500000}]})
    assert e.value.code == "serials", "an IMEI item cannot be sold without its IMEI"
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
        {"product_id": phone["id"], "qty_milli": 1000, "serials": [a]}],
        "payments": [{"method": "upi", "amount_paise": 1500000}]})
    assert inv["lines"][0]["serials"] == [a]
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [
            {"product_id": phone["id"], "qty_milli": 1000, "serials": [a]}],
            "payments": [{"method": "cash", "amount_paise": 1500000}]})
    assert e.value.code == "serial_not_in_stock", "the same IMEI is never sold twice"
    look = store.serial_lookup(biz, CASHIER, a)
    assert look["records"][0]["status"] == "sold" and look["records"][0]["invoice"]["number"] == inv["number"]
    with pytest.raises(PosError):
        pur.cancel_purchase(biz, OWNER, bill["id"], "wrong")  # one phone is already sold
    with pytest.raises(PosError) as e:
        store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "return",
                                                         "lines": [{"line_no": 1, "qty_milli": 1000, "serials": [b]}],
                                                         "refund": {"method": "upi", "amount_paise": 1500000}})
    assert e.value.code == "serials", "only an IMEI from this bill can come back"
    store.create_credit_note(biz, OWNER, inv["id"], {"client_txn_id": _txn(), "reason": "return",
                                                     "lines": [{"line_no": 1, "qty_milli": 1000, "serials": [a]}],
                                                     "refund": {"method": "upi", "amount_paise": 1500000}})
    assert a in store.serials_in_stock(biz, OWNER, phone["id"])
    with pytest.raises(PosError):
        store.serial_lookup(biz, OWNER, "000000000000000")


def test_purchase_order_partial_receipt(env):
    store, pur, biz, sup = env
    rice = store.add_product(biz, OWNER, {"name": "Rice", "unit": "kg", "price_paise": 6000, "category": "exempt",
                                          "track_stock": True})
    store.set_pack(biz, OWNER, rice["id"], {"name": "bag", "factor_milli": 25000})
    po = pur.create_po(biz, OWNER, {"supplier_id": sup, "lines": [{"product_id": rice["id"], "pack": "bag",
                                                                   "qty_milli": 10000, "cost_paise": 120000}],
                                    "expected_date": "2026-10-30"})
    assert po["number"] == "PO-00001" and po["status"] == "draft" and "10 bag" in po["text"]
    assert store.product(biz, OWNER, rice["id"])["stock_milli"] == 0, "an order is not stock"
    pur.set_po_status(biz, OWNER, po["id"], "sent")
    got = pur.receive_po(biz, OWNER, po["id"], {"client_txn_id": _txn(), "supplier_bill_no": "M-77",
                                                "lines": [{"line_no": 1, "qty_milli": 4000}]})
    assert got["order"]["status"] == "partially_received" and got["order"]["lines"][0]["received_milli"] == 4000
    assert store.product(biz, OWNER, rice["id"])["stock_milli"] == 100000, "4 bags x 25 kg"
    assert pur.supplier(biz, OWNER, sup)["owed_paise"] == 480000
    got = pur.receive_po(biz, OWNER, po["id"], {"client_txn_id": _txn(), "supplier_bill_no": "M-78",
                                                "lines": [{"line_no": 1, "qty_milli": 6000}]})
    assert got["order"]["status"] == "received" and len(got["order"]["bills"]) == 2
    with pytest.raises(PosError):
        pur.set_po_status(biz, OWNER, po["id"], "cancelled")
