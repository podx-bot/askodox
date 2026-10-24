"""POS ready-made catalogue (on catalogue_templates), item details, online price."""
import sqlite3
from datetime import datetime, timezone

import pytest

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services.pos_catalogue import PosCatalogue
from app.services.pos_online import PosOnline
from app.services.pos_store import PosError, PosStore
from app.services import pos_tax

OWNER = "app-phone-9400000301"
CASHIER = "app-phone-9400000302"


def _gstin(state, pan="AAPFU0939F"):
    head = f"{state}{pan}1Z"
    return head + pos_tax.gstin_check_char(head)


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    cat = PosCatalogue(store)
    kirana = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37", "template": "kirana"})["id"]
    shirts = store.create_business(OWNER, {"name": "Ravi Fashions", "registration_type": "regular",
                                           "gstin": _gstin("36"), "template": "clothing"})["id"]
    store.set_member(kirana, OWNER, "9400000302", "cashier")
    return store, cat, kirana, shirts


def test_default_template_follows_the_business_type_and_owner_can_change_it(env):
    store, cat, kirana, shirts = env
    c = cat.catalogue(kirana, OWNER)
    assert c["template_key"] == "grocery" and c["categories"] and c["attributes"]
    item = c["categories"][0]["items"][0]
    assert item["pos_unit"] in ("kg", "g", "l", "ml", "pcs", "dozen", "pack") and "price" not in item
    assert cat.catalogue(shirts, OWNER)["template_key"] == "fashion"
    assert cat.set_template(kirana, OWNER, "fruits_vegetables")["template_key"] == "fruits_vegetables"
    with pytest.raises(PosError):
        cat.set_template(kirana, CASHIER, "grocery")
    with pytest.raises(PosError):
        cat.set_template(kirana, OWNER, "no_such")


def test_import_needs_the_owners_price_and_gst_rate_never_invents_them(env):
    store, cat, kirana, shirts = env
    out = cat.import_items(kirana, OWNER, {"items": [
        {"item_key": "rice_grains.sona_masoori", "size": "25 kg", "price_paise": 145000, "track_stock": True},
        {"item_key": "dals.toor", "size": "1 kg"},
        {"item_key": "dals.moong", "size": "999 kg", "price_paise": 14000},
        {"item_key": "nope.nothing", "price_paise": 100},
    ]})
    assert [a["name"] for a in out["added"]] == ["Sona Masoori rice 25 kg", "Moong dal"], "an unknown size is dropped"
    reasons = {s.get("item_key"): s["reason"] for s in out["skipped"]}
    assert reasons["dals.toor"] == "price_missing" and reasons["nope.nothing"] == "not_in_catalogue"
    rice = store.product(kirana, OWNER, out["added"][0]["id"])
    assert rice["name_te"].startswith("సోనా మసూరి") and rice["unit"] == "kg" and rice["track_stock"]
    again = cat.import_items(kirana, OWNER, {"items": [{"item_key": "rice_grains.sona_masoori", "size": "25 kg",
                                                        "price_paise": 150000}]})
    assert again["added"] == [] and again["skipped"][0]["reason"] == "already_in_shop"
    gst = cat.import_items(shirts, OWNER, {"items": [
        {"item_key": cat.catalogue(shirts, OWNER)["categories"][0]["items"][0]["key"], "price_paise": 49900}]})
    assert gst["added"] == [] and gst["skipped"][0]["reason"] == "gst_rate_missing", "registered shop: rate is the owner's"


def test_details_are_cleaned_and_missing_required_reported(env):
    store, cat, kirana, shirts = env
    specs = cat.catalogue(shirts, OWNER)["attributes"]
    choice = next(s for s in specs if s["kind"] == "choice" and s["options"])
    shirt = store.add_product(shirts, OWNER, {"name": "Cotton shirt", "unit": "pcs", "price_paise": 49900, "rate_bp": 500})
    out = cat.set_attributes(shirts, OWNER, shirt["id"], {choice["key"]: choice["options"][0], "made_up": "x",
                                                         "mrp": "call 9876543210"})
    assert out["attributes"].get(choice["key"]) == choice["options"][0] and "made_up" not in out["attributes"]
    assert "mrp" not in out["attributes"]
    required = [s["key"] for s in specs if s.get("required") and not s.get("depends_on")]
    assert set(required) <= set(out["missing"]) | set(out["attributes"])
    assert store.product(shirts, OWNER, shirt["id"])["attributes"] == out["attributes"]


def test_online_price_reaches_the_listing_with_its_details(env):
    store, cat, kirana, shirts = env
    online = PosOnline(store)
    item = store.add_product(kirana, OWNER, {"name": "Unique Ghee 1 L", "unit": "l", "price_paise": 65000})
    specs = cat.catalogue(kirana, OWNER)["attributes"]
    choice = next(s for s in specs if s["kind"] == "choice" and s["options"])
    cat.set_attributes(kirana, OWNER, item["id"], {choice["key"]: choice["options"][0]})
    with pytest.raises(PosError):
        cat.set_online_price(kirana, CASHIER, item["id"], 60000)
    assert cat.set_online_price(kirana, OWNER, item["id"], 62000)["online_price_paise"] == 62000
    online.set_channel(kirana, OWNER, item["id"], "both")
    with sqlite3.connect(store.db_path) as conn:
        listing_id = conn.execute("SELECT listing_id FROM pos_online_links WHERE product_id = ?", (item["id"],)).fetchone()[0]
    repo = ProductCatalogRepository(store.db_path)
    assert repo.get(listing_id)["price"] == 620.0, "ASKODOX shows the online price"
    assert repo.attributes_for([listing_id])[listing_id] == {choice["key"]: [choice["options"][0]]}
    cat.set_online_price(kirana, OWNER, item["id"], None)
    online.sync(kirana, [item["id"]])
    assert repo.get(listing_id)["price"] == 650.0, "back to the shop price"


def test_http_catalogue_routes(monkeypatch):
    import uuid  # noqa: F401
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_online", None, raising=False)
    h = {"Authorization": f"Bearer {issue_token('app-phone-9411100021', container.settings.session_token_secret)}"}
    client = TestClient(app)
    biz = client.post("/api/pos/businesses", headers=h, json={"name": "S", "state_code": "36", "template": "kirana"}).json()["id"]
    cat = client.get(f"/api/pos/businesses/{biz}/catalogue", headers=h).json()
    assert cat["template_key"] == "grocery"
    first = cat["categories"][0]["items"][0]
    out = client.post(f"/api/pos/businesses/{biz}/catalogue/import", headers=h,
                      json={"items": [{"item_key": first["key"], "price_paise": 5000}]}).json()
    pid = out["added"][0]["id"]
    r = client.put(f"/api/pos/businesses/{biz}/products/{pid}/attributes", headers=h, json={"values": {"x": "y"}})
    assert r.status_code == 200 and r.json()["attributes"] == {}
    r = client.put(f"/api/pos/businesses/{biz}/products/{pid}/online-price", headers=h, json={"online_price_paise": 4500})
    assert r.status_code == 200 and r.json()["online_price_paise"] == 4500
    r = client.put(f"/api/pos/businesses/{biz}/products/{pid}/online-price", headers=h, json={"online_price_paise": None})
    assert r.json()["online_price_paise"] is None
