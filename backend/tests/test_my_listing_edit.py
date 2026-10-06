"""A seller edits their own listing (price / stock / size): owner-only,
screened like a new listing, and the edit is what buyers then see."""
import dataclasses

from fastapi.testclient import TestClient

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services.session_tokens import issue_token


def test_owner_edits_listing_and_others_cannot(monkeypatch, tmp_path):
    from server import app, container

    db = str(tmp_path / "e.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, database_path=db))
    monkeypatch.setattr(container, "product_catalog_repository", ProductCatalogRepository(db))
    client = TestClient(app)
    seller, other = "app-phone-919800000001", "app-phone-919800000002"

    def auth(u):
        return {"Authorization": f"Bearer {issue_token(u, container.settings.session_token_secret)}"}

    pid = container.product_catalog_repository.upsert_product(seller, "walking shoes", price=2200)
    r = client.patch(f"/api/products/mine/{pid}", headers=auth(seller),
                     json={"price": 1800, "stock_status": "IN_STOCK", "variant": "Size: 8, 9, 10"})
    assert r.status_code == 200, r.text
    item = r.json()["item"]
    assert (item["price"], item["stock_status"], item["variant"]) == (1800, "IN_STOCK", "Size: 8, 9, 10")
    assert client.patch(f"/api/products/mine/{pid}", headers=auth(other), json={"price": 1}).status_code == 404
    assert client.patch(f"/api/products/mine/{pid}", json={"price": 1}).status_code == 401
    bad = client.patch(f"/api/products/mine/{pid}", headers=auth(seller), json={"variant": "call 9876543210"})
    assert bad.status_code == 422 and "contact details" in str(bad.json())
    assert client.patch(f"/api/products/mine/{pid}", headers=auth(seller), json={}).status_code == 422
    rows = client.get("/api/products/mine", headers=auth(seller)).json()["items"]
    assert rows[0]["price"] == 1800
