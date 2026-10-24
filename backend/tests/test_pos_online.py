"""POS item channel: POS only / Online / Both -> the shop's ASKODOX listing (seller_products)."""
import sqlite3
import uuid
from datetime import datetime, timezone

import pytest

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services.pos_online import PosOnline, effective_channel
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000201"
CASHIER = "app-phone-9400000202"


@pytest.fixture()
def env(tmp_path):
    db = str(tmp_path / "pos.db")
    store = PosStore(db, clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    reviews = []
    online = PosOnline(store, queue_review=lambda lid, seller, subject, reasons: reviews.append((lid, subject)))
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "state_code": "37", "address": "Main Road, Uyyuru",
                                        "phone": "9400000201"})["id"]
    store.set_member(biz, OWNER, "9400000202", "cashier")
    return store, online, biz, db, reviews


def _listing(db, listing_id):
    with sqlite3.connect(db) as conn:
        conn.row_factory = sqlite3.Row
        return dict(conn.execute("SELECT * FROM seller_products WHERE id = ?", (listing_id,)).fetchone())


def _link(db, product_id):
    with sqlite3.connect(db) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM pos_online_links WHERE product_id = ?", (product_id,)).fetchone()
        return dict(row) if row else None


def test_effective_channel():
    assert effective_channel({"channel": None}, "both") == "both"
    assert effective_channel({"channel": "pos"}, "both") == "pos"
    assert effective_channel({}, None) == "pos"
    assert effective_channel({"channel": "weird"}, "online") == "pos"


def test_default_pos_publishes_nothing_then_online_publishes_and_search_finds_it(env):
    store, online, biz, db, _ = env
    rice = store.add_product(biz, OWNER, {"name": "Sona Masoori Rice 25kg", "unit": "pcs", "price_paise": 145000,
                                          "track_stock": True, "opening_stock_milli": 5000})
    online.sync(biz)
    assert _link(db, rice["id"]) is None, "POS only by default: nothing is published"
    status = online.set_channel(biz, OWNER, rice["id"], "online")
    item = next(i for i in status["items"] if i["product_id"] == rice["id"])
    assert item["effective"] == "online" and item["state"] == "live"
    link = _link(db, rice["id"])
    listing = _listing(db, link["listing_id"])
    assert listing["seller_user_id"] == OWNER and listing["active"] == 1
    assert listing["price"] == 1450.0 and listing["stock_status"] == "IN_STOCK"
    assert listing["seller_name"] == "Lakshmi Kirana" and listing["location_label"] == "Main Road, Uyyuru"
    found = ProductCatalogRepository(db).search_active("sona masoori rice", limit=10)
    assert [r["id"] for r in found] == [link["listing_id"]], "customer search reads it like any seller listing"


def test_rename_price_stock_and_hide_keep_one_listing(env):
    store, online, biz, db, _ = env
    item = store.add_product(biz, OWNER, {"name": "Toor Dal 1kg", "unit": "pcs", "price_paise": 16000,
                                          "track_stock": True, "opening_stock_milli": 1000})
    online.set_default(biz, OWNER, "both")
    first = _link(db, item["id"])["listing_id"]
    store.update_product(biz, OWNER, item["id"], {"name": "Toor Dal Premium 1kg", "price_paise": 17000})
    online.sync(biz, [item["id"]])
    store.stock_move(biz, OWNER, {"product_id": item["id"], "kind": "wastage", "qty_milli": -1000, "reason": "spilt",
                                  "client_txn_id": "t-" + uuid.uuid4().hex})
    online.sync(biz, [item["id"]])
    link = _link(db, item["id"])
    assert link["listing_id"] == first, "a rename updates the same listing, never a duplicate"
    listing = _listing(db, first)
    assert listing["subject"] == "Toor Dal Premium 1kg" and listing["price"] == 170.0
    assert listing["stock_status"] == "OUT_OF_STOCK"
    online.set_channel(biz, OWNER, item["id"], "pos")
    assert _listing(db, first)["active"] == 0 and _link(db, item["id"])["state"] == "hidden"
    online.set_channel(biz, OWNER, item["id"], None)  # back to the shop default (both)
    assert _listing(db, first)["active"] == 1
    store.update_product(biz, OWNER, item["id"], {"active": False})
    online.sync(biz, [item["id"]])
    assert _listing(db, first)["active"] == 0, "a deactivated item is hidden online"


def test_screening_blocks_or_holds_like_any_listing(env):
    store, online, biz, db, reviews = env
    bad = store.add_product(biz, OWNER, {"name": "Call 9876543210 for rice", "unit": "pcs", "price_paise": 100})
    online.set_channel(biz, OWNER, bad["id"], "online")
    link = _link(db, bad["id"])
    assert link["state"] == "needs_review" and _listing(db, link["listing_id"])["active"] == 0
    assert reviews and reviews[0][0] == link["listing_id"], "queued for staff review"
    online.sync(biz, [bad["id"]])
    assert _listing(db, link["listing_id"])["active"] == 0, "only staff can make a held listing live"
    blocked = PosOnline(store, screen=lambda seller, f: {"decision": "block", "reasons": ["prohibited item"]})
    gun = store.add_product(biz, OWNER, {"name": "Thing", "unit": "pcs", "price_paise": 100})
    blocked.set_channel(biz, OWNER, gun["id"], "online")
    assert _link(db, gun["id"])["state"] == "blocked" and _link(db, gun["id"])["listing_id"] is None


def test_permissions(env):
    store, online, biz, db, _ = env
    item = store.add_product(biz, OWNER, {"name": "Soap", "unit": "pcs", "price_paise": 4000})
    with pytest.raises(PosError):
        online.set_default(biz, CASHIER, "both")
    with pytest.raises(PosError):
        online.set_channel(biz, CASHIER, item["id"], "online")
    with pytest.raises(PosError) as e:
        online.status(biz, "app-phone-9000000000")
    assert e.value.status == 404
    with pytest.raises(PosError):
        online.set_default(biz, OWNER, "everywhere")


def test_http_channel_and_sale_updates_stock(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_online", None, raising=False)
    secret = container.settings.session_token_secret
    h = {"Authorization": f"Bearer {issue_token('app-phone-9411100011', secret)}"}
    client = TestClient(app)
    biz = client.post("/api/pos/businesses", headers=h, json={"name": "Shop", "state_code": "36"}).json()["id"]
    item = client.post(f"/api/pos/businesses/{biz}/products", headers=h,
                       json={"name": "Unique Jaggery Block", "unit": "pcs", "price_paise": 9000, "track_stock": True,
                             "opening_stock_milli": 1000}).json()
    assert item["channel"] is None
    r = client.put(f"/api/pos/businesses/{biz}/products/{item['id']}/online", headers=h, json={"channel": "both"})
    assert r.status_code == 200
    assert next(i for i in r.json()["items"] if i["product_id"] == item["id"])["state"] == "live"
    assert client.put(f"/api/pos/businesses/{biz}/online", headers=h, json={"channel": "nowhere"}).status_code == 422
    sale = client.post(f"/api/pos/businesses/{biz}/invoices", headers=h, json={
        "client_txn_id": "t-" + uuid.uuid4().hex, "lines": [{"product_id": item["id"], "qty_milli": 1000}],
        "payments": [{"method": "cash", "amount_paise": 9000}]})
    assert sale.status_code == 200, sale.text
    found = ProductCatalogRepository(container.settings.database_path).search_active("unique jaggery block", limit=5)
    assert found and found[0]["stock_status"] == "OUT_OF_STOCK", "the last piece sold -> out of stock online"
