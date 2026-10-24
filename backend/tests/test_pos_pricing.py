"""Rates by quantity (pav kilo / kg / 10 kg / 100 kg), least quantity, item photos."""
import base64
import uuid
from datetime import datetime, timezone

import pytest

from app.services.pos_catalogue import PosCatalogue
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000401"
CASHIER = "app-phone-9400000402"
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")


def _txn():
    return "t-" + uuid.uuid4().hex


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    cat = PosCatalogue(store)
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37", "template": "kirana"})["id"]
    store.set_member(biz, OWNER, "9400000402", "cashier")
    dal = store.add_product(biz, OWNER, {"name": "Toor dal", "unit": "kg", "price_paise": 16000})
    return store, cat, biz, dal


def test_rates_by_quantity_pick_the_highest_reached_tier(env):
    store, cat, biz, dal = env
    with pytest.raises(PosError):
        cat.set_pricing(biz, CASHIER, dal["id"], {"tiers": [{"min_qty_milli": 10000, "price_paise": 15000}]})
    with pytest.raises(PosError):
        cat.set_pricing(biz, OWNER, dal["id"], {"tiers": [{"min_qty_milli": 1000, "price_paise": 1},
                                                           {"min_qty_milli": 1000, "price_paise": 2}]})
    out = cat.set_pricing(biz, OWNER, dal["id"], {"tiers": [
        {"min_qty_milli": 250, "price_paise": 17000},     # pav kilo: Rs 42.50 for 250 g = Rs 170 / kg
        {"min_qty_milli": 10000, "price_paise": 15000},   # 10 kg and above: Rs 150 / kg
        {"min_qty_milli": 100000, "price_paise": 14000},  # 100 kg and above
    ]})
    assert [t["min_qty_milli"] for t in out["tiers"]] == [250, 10000, 100000]
    assert store.tier_price(out["tiers"], 500) == 17000 and store.tier_price(out["tiers"], 100) is None
    for qty, unit_price in ((250, 17000), (5000, 17000), (10000, 15000), (120000, 14000)):
        cust = store.add_customer(biz, OWNER, {"name": f"C{qty}"})["id"]
        inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust,
                                                  "lines": [{"product_id": dal["id"], "qty_milli": qty}], "payments": []})
        line = inv["lines"][0]
        assert line["unit_price_paise"] == unit_price, qty
    # a cashier sending the tier price (offline bill) is NOT a price override
    cust = store.add_customer(biz, OWNER, {"name": "Offline"})["id"]
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust, "lines": [
        {"product_id": dal["id"], "qty_milli": 10000, "unit_price_paise": 15000}], "payments": []})
    assert inv["lines"][0]["unit_price_paise"] == 15000
    assert cat.set_pricing(biz, OWNER, dal["id"], {"tiers": []})["tiers"] == [], "back to one rate"


def test_least_quantity_is_enforced(env):
    store, cat, biz, dal = env
    cat.set_pricing(biz, OWNER, dal["id"], {"tiers": [], "min_qty_milli": 10000})
    cust = store.add_customer(biz, OWNER, {"name": "A"})["id"]
    with pytest.raises(PosError) as e:
        store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust,
                                            "lines": [{"product_id": dal["id"], "qty_milli": 2000}], "payments": []})
    assert e.value.code == "min_qty"
    assert store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust,
                                               "lines": [{"product_id": dal["id"], "qty_milli": 10000}], "payments": []})


def test_item_photo(env):
    store, cat, biz, dal = env
    with pytest.raises(PosError):
        cat.set_photo(biz, OWNER, dal["id"], b"not an image at all")
    with pytest.raises(PosError):
        cat.set_photo(biz, OWNER, dal["id"], b"\x89PNG\r\n\x1a\n" + b"0" * (301 * 1024))
    at = cat.set_photo(biz, OWNER, dal["id"], PNG)["photo_at"]
    assert store.product(biz, OWNER, dal["id"])["photo_at"] == at
    image, mime = cat.photo(biz, CASHIER, dal["id"])
    assert image == PNG and mime == "image/png"
    with pytest.raises(PosError) as e:
        cat.photo(biz, "app-phone-9000000001", dal["id"])
    assert e.value.status == 404
