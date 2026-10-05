"""Universal Smart Entry: paste -> detect -> fetch -> extract -> prepared form
(value + confidence + provenance), batches isolated + de-duplicated, nothing
saved, permissions per target form."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import smart_entry as se

PRODUCT = "https://www.meesho.com/women-cotton-kurti/p/4xyz"
HTML = """<html><head><title>Kurti | Meesho</title>
  <meta property="og:title" content="Women Cotton Kurti">
  <script type="application/ld+json">{"@type":"Product","name":"Women Cotton Kurti Blue",
    "image":["https://images.meesho.com/1.jpg"],"brand":{"name":"Sri Fashions"},
    "offers":{"@type":"Offer","price":"399","availability":"https://schema.org/InStock"}}</script>
  </head></html>"""
OFFER_TEXT = ("Festive Bonanza\n10% instant discount on HDFC Bank credit cards, minimum purchase of ₹5,000, "
              "maximum discount up to ₹1,500. Use code SAVE10. Valid till 31 Oct 2026.")


def _fetch(url):
    if "broken" in url:
        raise PermissionError("403")
    return HTML


def test_detect_kinds():
    assert se.detect("hello")["kind"] == "text"
    assert se.detect("https://youtu.be/abcdef123")["kind"] == "video"
    assert se.detect("https://www.youtube.com/shorts/abcdef123")["kind"] == "video"
    assert se.detect("https://amzn.to/3xYz")["kind"] == "affiliate"
    assert se.detect("https://shop.example.in/catalog.pdf")["kind"] == "pdf"
    assert se.detect("https://shop.example.in/feed.xml")["kind"] == "feed"
    assert se.detect("https://shop.example.in/offers/diwali")["kind"] == "offer"
    assert se.detect(PRODUCT)["kind"] == "product"


def test_offer_text_fields_need_review_and_never_prefill():
    out = se.ingest(OFFER_TEXT, "offer")
    f = out["fields"]
    assert f["discount_percent"]["value"] == 10
    assert f["min_spend"]["value"] == 5000 and f["max_benefit"]["value"] == 1500
    assert f["coupon_code"]["value"] == "SAVE10"
    assert f["payment_eligibility"]["value"] == ["HDFC credit card"]
    assert f["ends_on"]["value"].startswith("31 Oct")
    assert f["title"]["value"] == "Festive Bonanza"
    assert all(v["provenance"] for v in f.values())
    # text patterns are medium/low confidence: reviewed, never silently pre-filled
    assert out["prefill"] == {} and "discount_percent" in out["needs_review"]
    assert "merchant" in out["not_found"]


def test_product_page_and_failure_isolation_in_a_batch():
    batch = se.ingest_batch([PRODUCT, PRODUCT, "https://broken.example.in/p/1", "https://youtu.be/abcdef123",
                             "https://amzn.to/3xYz", "  "], "auto", fetch=_fetch)
    assert batch["count"] == 4 and batch["duplicates_skipped"] == 1
    product, broken, video, aff = batch["items"]
    assert product["target"] == "catalog"
    assert product["fields"]["title"]["value"] == "Women Cotton Kurti Blue"
    assert product["fields"]["price"]["value"] == 399
    assert product["prefill"]["source_url"] == PRODUCT
    assert broken["status"] == "unavailable" and "title" not in broken["fields"]
    assert video["fields"]["video_id"]["value"] == "abcdef123" and video["fields"]["platform"]["value"] == "youtube"
    assert aff["target"] == "affiliate_link" and aff["fields"]["network"]["value"] == "Amazon Associates"
    assert batch["failed"] == 1


def test_batch_is_bounded():
    batch = se.ingest_batch([f"offer {i} 10% off" for i in range(se.MAX_BATCH + 5)], "offer")
    assert batch["count"] == se.MAX_BATCH and batch["truncated"] == 5


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-se-" + uuid.uuid4().hex[:6]
    db = str(tmp_path / "se.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(db), raising=False)
    monkeypatch.setattr(container, "affiliate_page_fetch", _fetch, raising=False)
    return TestClient(app), {"X-ASKODOX-Admin-Key": key}


def test_route_prepares_without_saving_and_checks_permissions(api):
    client, owner = api
    r = client.post("/admin/cc/smart-entry", headers=owner, json={"inputs": [PRODUCT, OFFER_TEXT]})
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert [i["target"] for i in items] == ["catalog", "offer"] and all(i["can_save"] for i in items)
    assert client.post("/admin/cc/smart-entry", headers=owner, json={"inputs": []}).status_code == 400
    assert client.post("/admin/cc/smart-entry", json={"inputs": [PRODUCT]}).status_code == 401
    staff = client.post("/admin/cc/staff", headers=owner, json={"name": "viewer", "role": "viewer"})
    if staff.status_code == 200:
        token = {"X-ASKODOX-Staff-Token": staff.json()["token"]}
        assert client.post("/admin/cc/smart-entry", headers=token,
                           json={"inputs": [PRODUCT], "target": "catalog"}).status_code == 403
