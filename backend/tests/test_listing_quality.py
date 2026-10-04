"""Listing spam / abuse screening: block prohibited items and flooding, hold
contact-in-text and cross-account copies for staff review, approve/reject
from Command Center."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services import listing_quality
from app.services.session_tokens import issue_token


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-lq-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    catalog = container.product_catalog_repository  # seller profiles read the same database
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}, catalog


def _seller():
    return "app-" + uuid.uuid4().hex[:10]


def _post(client, container, seller, subject, **extra):
    token = issue_token(seller, container.settings.session_token_secret)
    return client.post("/api/products/mine", headers={"Authorization": f"Bearer {token}"},
                       json={"seller_user_id": seller, "subject": subject, "price": 500, **extra})


def test_rules_are_explainable(tmp_path):
    db = str(tmp_path / "x.db")
    ProductCatalogRepository(db)
    assert listing_quality.check(db, "s", {"subject": "country made pistol"})["decision"] == "block"
    held = listing_quality.check(db, "s", {"subject": "mango pickle call 9876543210"})
    assert held["decision"] == "review" and "contact details" in held["reasons"][0]
    assert listing_quality.check(db, "s", {"subject": "shoes www.cheapdeals.xyz"})["decision"] == "review"
    assert listing_quality.check(db, "s", {"subject": "fresh mango pickle 1 kg"})["decision"] == "allow"
    # Whole-word matching: "gunny bags" is not "gun".
    assert listing_quality.check(db, "s", {"subject": "gunny bags"})["decision"] == "allow"


def test_block_hold_and_staff_review(api):
    client, container, owner, catalog = api
    seller = _seller()
    blocked = _post(client, container, seller, "ganja 50g")
    assert blocked.status_code == 422 and "prohibited" in str(blocked.json())

    held = _post(client, container, seller, "home made pickles whatsapp 9876543210")
    assert held.status_code == 200 and held.json()["held_for_review"] is True
    pid = held.json()["id"]
    assert not any(r["id"] == pid for r in catalog.list_active_for_seller(seller)), "hidden until reviewed"

    reviews = client.get("/admin/cc/platform/r/listing_reviews", headers=owner).json()["items"]
    mine = next(r for r in reviews if r["data"]["product_id"] == pid)
    assert mine["status"] == "PENDING_REVIEW" and mine["data"]["reasons"]
    r = client.post(f"/admin/cc/platform/r/listing_reviews/{mine['id']}/actions/approve", headers=owner,
                    json={"params": {}, "confirm": True})
    assert r.status_code == 200, r.text
    assert any(x["id"] == pid for x in catalog.list_active_for_seller(seller)), "approved -> searchable"
    r = client.post(f"/admin/cc/platform/r/listing_reviews/{mine['id']}/actions/reject", headers=owner,
                    json={"params": {}, "confirm": True})
    assert r.status_code == 200 and not any(x["id"] == pid for x in catalog.list_active_for_seller(seller))

    ok = _post(client, container, seller, "fresh mango pickle 1 kg")
    assert ok.status_code == 200 and ok.json()["held_for_review"] is False


def test_one_number_listing_from_several_accounts_is_held(api):
    client, container, owner, catalog = api
    phone = "98" + uuid.uuid4().hex[:8].translate(str.maketrans("abcdef", "123456"))
    results = [_post(client, container, _seller(), f"iphone 15 pro {i} {phone[-3:]}", contact_phone=phone)
               for i in range(3)]
    assert [r.json()["held_for_review"] for r in results] == [False, False, True]
    # Many shops listing the same product name is normal, never held.
    same = [_post(client, container, _seller(), "basmati rice 1 kg") for _ in range(4)]
    assert all(r.json()["held_for_review"] is False for r in same)


def test_editable_prohibited_terms(api):
    client, container, owner, catalog = api
    made = client.post("/admin/cc/platform/r/prohibited_terms", headers=owner,
                       json={"data": {"term": "zorbo tonic", "why": "test"}})
    assert made.status_code == 200, made.text
    rid = made.json().get("id") or made.json()["item"]["id"]
    try:
        assert _post(client, container, _seller(), "zorbo tonic 1 bottle").status_code == 422
    finally:
        from app.api.routes.platform import platform

        platform(container).repo.delete(rid, actor="test")
