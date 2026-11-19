"""Supplier bill photo -> preview -> one save: supplier, new items, stock, ledger (owner 2026-11-19)."""
from datetime import datetime, timezone

import pytest

from app.services import pos_tax
from app.services.pos_bill_photo import PosBillPhoto, read_bill
from app.services.pos_purchases import PosPurchases
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300000011"


def _gstin(state, pan="AAPFU0939F"):
    head = f"{state}{pan}1Z"
    return head + pos_tax.gstin_check_char(head)


class FakeVision:
    def __init__(self, payload):
        self.payload = payload

    def analyze_with_prompt(self, photos, prompt, **_kwargs):
        assert "PURCHASE BILL" in prompt and "NEVER guess" in prompt
        return self.payload, 1


BILL = {"supplier": {"name": "Sri Lakshmi Distributors", "gstin": _gstin("37", "AAGCB7383J"), "phone": "9000000000"},
        "bill_no": "SL/204", "bill_date": "2026-10-20", "total": 2362.5,
        "lines": [{"name": "Good Day Biscuit 100g", "qty": 50, "unit": "pcs", "cost": 9, "gst_percent": 5, "mrp": 12,
                   "batch": "GD77", "expiry": "2027-03-31"},
                  {"name": "Sunflower Oil 1L", "qty": 12, "unit": "pcs", "cost": 150, "gst_percent": 5, "mrp": None},
                  {"name": "Mystery item", "qty": None, "cost": None, "gst_percent": 7}]}


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    purchases = PosPurchases(store)
    biz = store.create_business(OWNER, {"name": "Sai Kirana", "registration_type": "regular", "gstin": _gstin("37"),
                                        "template": "pharmacy", "invoice_prefix": "SK"})["id"]
    oil = store.add_product(biz, OWNER, {"name": "Sunflower Oil 1L", "unit": "pcs", "price_paise": 17500, "rate_bp": 500,
                                         "track_stock": True})
    return store, purchases, PosBillPhoto(store, purchases), biz, oil["id"]


def test_reader_never_guesses_and_drops_an_illegal_gst_rate():
    bill = read_bill(FakeVision(BILL), [(b"x", "image/jpeg")])
    assert bill["read"] and bill["bill_no"] == "SL/204" and bill["total_paise"] == 236250
    biscuit, oil, mystery = bill["lines"]
    assert biscuit["qty_milli"] == 50000 and biscuit["cost_paise"] == 900 and biscuit["rate_bp"] == 500
    assert biscuit["expiry_date"] == "2027-03-31" and biscuit["mrp_paise"] == 1200
    assert mystery["qty_milli"] is None and mystery["cost_paise"] is None and mystery["rate_bp"] is None
    assert read_bill(None, [(b"x", "image/jpeg")])["read"] is False


def test_preview_matches_own_items_and_asks_only_what_is_missing(env):
    _store, _purchases, photo, biz, oil = env
    out = photo.preview(biz, OWNER, [(b"x", "image/jpeg")], FakeVision(BILL))
    assert out["supplier_id"] is None and out["supplier_name"] == "Sri Lakshmi Distributors" and out["new_items"] == 2
    biscuit, oil_line, mystery = out["lines"]
    assert biscuit["new"] and biscuit["price_paise"] == 1200 and biscuit["ask"] == []
    assert oil_line["product_id"] == oil and not oil_line["new"] and oil_line["ask"] == []
    assert set(mystery["ask"]) == {"qty_milli", "cost_paise", "price_paise", "rate_bp"}
    assert out["ask"] == ["line:2"]


def test_one_save_creates_supplier_and_items_and_records_the_purchase(env):
    store, purchases, photo, biz, oil = env
    preview = photo.preview(biz, OWNER, [(b"x", "image/jpeg")], FakeVision(BILL))
    data = {"client_txn_id": "photo-bill-1", "supplier": preview["supplier"], "supplier_bill_no": preview["bill_no"],
            "bill_date": preview["bill_date"], "supplier_total_paise": preview["total_paise"],
            "lines": preview["lines"][:2]}
    out = photo.save(biz, OWNER, data)
    assert out["created_items"] == 1 and out["totals"]["total_paise"] == 236250
    names = {p["name"]: p for p in store.products(biz, OWNER)}
    assert names["Good Day Biscuit 100g"]["stock_milli"] == 50000 and names["Sunflower Oil 1L"]["stock_milli"] == 12000
    assert [s["name"] for s in purchases.suppliers(biz, OWNER)] == ["Sri Lakshmi Distributors"]
    again = photo.save(biz, OWNER, data)  # a second tap: same bill, nothing doubled
    assert again["replayed"] and again["created_items"] == 0 and len(store.products(biz, OWNER)) == 2
    assert len(purchases.suppliers(biz, OWNER)) == 1


def test_save_refuses_a_half_read_line_before_creating_anything(env):
    store, _purchases, photo, biz, _oil = env
    preview = photo.preview(biz, OWNER, [(b"x", "image/jpeg")], FakeVision(BILL))
    with pytest.raises(PosError) as e:
        photo.save(biz, OWNER, {"client_txn_id": "photo-bill-2", "supplier": preview["supplier"],
                                "supplier_bill_no": "SL/204", "lines": preview["lines"]})
    assert e.value.code == "line" and len(store.products(biz, OWNER)) == 1


def test_packet_photo_fills_the_new_item_form_without_guessing():
    from app.services.pos_bill_photo import read_product

    class Vision:
        def analyze_with_prompt(self, photos, prompt, **_kwargs):
            assert "ONE product" in prompt
            return {"name": "Good Day Butter Cookies 100g", "mrp": 12, "unit": "pcs", "expiry": "2027-03-31",
                    "barcode": "8901063 010215"}, 1

    out = read_product(Vision(), [(b"x", "image/jpeg")])
    assert out == {"read": True, "name": "Good Day Butter Cookies 100g", "price_paise": 1200, "unit": "pcs",
                   "expiry_date": "2027-03-31", "barcode": "8901063010215"}

    class Blank:
        def analyze_with_prompt(self, photos, prompt, **_kwargs):
            return {"name": None, "mrp": None}, 1

    blank = read_product(Blank(), [(b"x", "image/jpeg")])
    assert blank["read"] is False and blank["price_paise"] is None
