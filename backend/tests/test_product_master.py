"""Items come in by themselves (owner 2026-11-24): a shelf photo -> every pack with its own photo; a list / note photo
item is filled from what shops on ASKODOX keep (barcoded packs only, never another shop's selling price); a scanned
barcode -> name / brand / pack / MRP / photo (ASKODOX first, then Open Food Facts); a price only from a printed MRP."""

import base64
import io
import json

import pytest

from app.services import pos_menu_photo
from app.services.pos_frontdesk import PosFrontDesk
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosStore
from app.services.product_master import ProductMaster

OWNER_A = "app-phone-9400000501"
OWNER_B = "app-phone-9400000502"


def _jpeg(w=400, h=300, color=(200, 30, 30)) -> bytes:
    from PIL import Image

    out = io.BytesIO()
    Image.new("RGB", (w, h), color).save(out, format="JPEG")
    return out.getvalue()


class FakeVision:
    def __init__(self, items):
        self.items = items

    def analyze_with_prompt(self, photos, prompt, **kw):
        return {"items": self.items}, 1


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    desk = PosFrontDesk(store, PosRestaurant(store), notify=lambda *a: None, pay_to=lambda *a: [])
    a = store.create_business(OWNER_A, {"name": "Lakshmi Kirana", "state_code": "37", "template": "kirana"})["id"]
    b = store.create_business(OWNER_B, {"name": "New Mart", "state_code": "37", "template": "kirana",
                                        "invoice_prefix": "NM"})["id"]
    oil = store.add_product(a, OWNER_A, {"name": "Freedom Sunflower Oil 1 L", "unit": "pcs", "price_paise": 15500,
                                         "barcode": "8901234567890"})["id"]
    loose = store.add_product(a, OWNER_A, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 16000})["id"]
    with store._connect() as conn:
        conn.execute("UPDATE pos_products SET attributes = ? WHERE id = ?",
                     (json.dumps({"brand": "Freedom", "pack": "1 L", "mrp": "165"}), oil))
        for pid in (oil, loose):
            conn.execute("INSERT INTO pos_product_photos (business_id, product_id, image, mime, updated_at)"
                         " VALUES (?, ?, ?, 'image/jpeg', 'now')", (a, pid, _jpeg()))
    return store, desk, a, b, oil, loose


def test_a_shelf_photo_gives_every_pack_with_its_own_photo_and_never_a_guessed_price():
    shelf = FakeVision([
        {"name": "Sunflower Oil", "brand": "Freedom", "pack": "1 L", "mrp": 165, "box": [100, 100, 600, 400]},
        {"name": "Sunflower Oil", "brand": "Freedom", "pack": "1 L", "mrp": 165, "box": [100, 500, 600, 800]},
        {"name": "Toor Dal", "brand": "Tata Sampann", "pack": "500 g", "mrp": None, "box": [0, 0, 5, 5]},
    ])
    out = pos_menu_photo.read_shelf(shelf, [(_jpeg(1000, 800), "image/jpeg")])
    assert out["read"] and [i["name"] for i in out["items"]] == ["Freedom Sunflower Oil 1 L", "Tata Sampann Toor Dal 500 g"]
    oil, dal = out["items"]
    assert oil["price_paise"] == 16500 and oil["price_from"] == "mrp" and not oil["needs_price"]
    assert base64.b64decode(oil["photo_b64"])[:3] == b"\xff\xd8\xff", "the pack cut out of the shelf photo"
    assert dal["needs_price"] and dal["price_paise"] == 0 and dal["photo_b64"] == "", "no MRP read -> owner types it"
    assert pos_menu_photo.read_shelf(None, [(b"x", "image/jpeg")]) == {"items": [], "read": False}


def test_list_items_are_filled_from_barcoded_packs_on_askodox_only(env):
    store, desk, a, b, oil, loose = env
    master = ProductMaster(store.db_path)
    items = master.enrich([{"name": "sunflower oil freedom", "price_paise": 0, "needs_price": True},
                           {"name": "Chicken Biryani", "price_paise": 0, "needs_price": True}], business_id=b)
    filled, dish = items
    assert filled["brand"] == "Freedom" and filled["mrp_paise"] == 16500 and filled["barcode"] == "8901234567890"
    assert filled["price_paise"] == 16500 and filled["price_from"] == "mrp" and filled["photo"] == f"p:{oil}"
    assert "photo" not in dish and dish["needs_price"], "a shop's own dish photo is never shared"
    assert master.photo(f"p:{oil}")[1] == "image/jpeg" and master.photo(f"p:{loose}") is None


def test_barcode_lookup_asks_askodox_then_open_food_facts_once(env):
    store, desk, a, b, oil, loose = env
    calls = []

    def fetch(url, timeout):
        calls.append(url)
        if "9999999999999" in url:
            raise OSError("offline")
        if url.endswith(".json?fields=product_name,brands,quantity,image_front_small_url"):
            if "8906001200000" in url:
                return 200, json.dumps({"status": 1, "product": {"product_name": "Ragi Malt", "brands": "Manna,X",
                    "quantity": "200 g", "image_front_small_url": "https://images.openfoodfacts.org/x.jpg"}}).encode(), "application/json"
            return 200, json.dumps({"status": 0}).encode(), "application/json"
        return 200, _jpeg(80, 80), "image/jpeg"

    master = ProductMaster(store.db_path, fetch=fetch)
    own = master.lookup("8901234567890")
    assert own["name"] == "Freedom Sunflower Oil 1 L" and own["mrp_paise"] == 16500 and own["source"] == "askodox"
    assert "price_paise" not in own and calls == [], "a shop's selling price never leaves the shop"
    open_data = master.lookup("8906001200000")
    assert open_data["name"] == "Ragi Malt" and open_data["brand"] == "Manna" and open_data["pack"] == "200 g"
    assert open_data["credit"] == "Open Food Facts" and master.photo(open_data["photo"])[1] == "image/jpeg"
    asked = len(calls)
    assert master.lookup("8906001200000")["name"] == "Ragi Malt" and len(calls) == asked, "kept after the first time"
    assert master.lookup("8900000000017") is None
    assert master.lookup("8900000000017") is None and len(calls) == asked + 1, "a miss is remembered"
    assert master.lookup("9999999999999") is None
    assert master.lookup("9999999999999") is None and len(calls) == asked + 3, "network trouble is not remembered"
    assert master.lookup("12") is None


def test_import_keeps_barcode_details_and_photo_without_overwriting_the_owner(env):
    store, desk, a, b, oil, loose = env
    shelf_photo = pos_menu_photo._crop(_jpeg(1000, 800), [0, 0, 500, 500])
    desk.import_menu(b, OWNER_B, [
        {"name": "Freedom Sunflower Oil 1 L", "price_paise": 16500, "unit": "pcs", "barcode": "8901234567890",
         "brand": "Freedom", "pack": "1 L", "mrp_paise": 16500, "photo": f"p:{oil}"},
        {"name": "Tata Sampann Toor Dal 500 g", "price_paise": 9900, "unit": "pcs", "photo_b64": shelf_photo},
    ])
    with store._connect() as conn:
        rows = {r["name"]: r for r in conn.execute("SELECT id, name, barcode, attributes FROM pos_products"
                                                   " WHERE business_id = ?", (b,))}
        oil_b = rows["Freedom Sunflower Oil 1 L"]
        assert oil_b["barcode"] == "8901234567890"
        assert json.loads(oil_b["attributes"]) == {"brand": "Freedom", "pack": "1 L", "mrp": "165"}
        photos = {r[0] for r in conn.execute("SELECT product_id FROM pos_product_photos WHERE business_id = ?", (b,))}
        assert photos == {oil_b["id"], rows["Tata Sampann Toor Dal 500 g"]["id"]}
        conn.execute("UPDATE pos_products SET attributes = ? WHERE id = ?", (json.dumps({"brand": "Own words"}), oil_b["id"]))
    desk.import_menu(b, OWNER_B, [{"name": "Freedom Sunflower Oil 1 L", "price_paise": 16000, "brand": "Freedom"}])
    with store._connect() as conn:
        attrs = conn.execute("SELECT attributes FROM pos_products WHERE id = ?", (oil_b["id"],)).fetchone()[0]
    assert json.loads(attrs)["brand"] == "Own words", "the owner's own entry is never overwritten"


def test_shelf_preview_marks_items_the_shop_already_has(env):
    store, desk, a, b, oil, loose = env
    vision = FakeVision([{"name": "Freedom Sunflower Oil 1 L", "mrp": None, "box": [0, 0, 900, 900]}])
    out = desk.parse_shelf_photo(a, OWNER_A, [(_jpeg(), "image/jpeg")], vision)
    item = out["items"][0]
    assert item["exists"] and item["old_price_paise"] == 15500
    with pytest.raises(Exception):
        desk.parse_shelf_photo(a, OWNER_B, [(_jpeg(), "image/jpeg")], vision)
