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


# ------------------------------------------------ Z6: quick add, templates, bulk --

def test_builtin_templates_hold_structure_only():
    from app.services.platform_schema import TEMPLATE_FACT_FIELDS

    labels = {t["label"] for t in se.TEMPLATES}
    for want in ("Amazon product", "Flipkart product", "Meesho product", "Generic online product",
                 "Local seller product", "Used product", "Service provider", "Restaurant", "Hotel", "AC service",
                 "Car listing", "Insurance lead program", "Loan lead program", "Credit-card offer",
                 "Affiliate link", "Coupon", "Bank offer (debit / UPI)", "Sponsored campaign", "YouTube video",
                 "Creator video", "News source"):
        assert want in labels, want
    for t in se.TEMPLATES:
        assert t["target"] in se.TARGET_FIELDS
        assert not set(t["defaults"]) & TEMPLATE_FACT_FIELDS, t["id"]  # never a price / stock / title ...


def test_csv_rows_are_validated_and_classified():
    csv_text = ("url,title,price,colour\n"
                f"{PRODUCT},Kurti,399,blue\n"
                "http://insecure.example.in/p/1,Shirt,abc,\n"
                ",No link,10,\n")
    rows = se.parse_csv(csv_text, "catalog")
    assert len(rows) == 3
    assert rows[0]["fields"]["source_url"]["provenance"] == "CSV column 'url'"
    assert rows[0]["fields"]["price"]["value"] == 399 and "colour" in rows[0]["note"]
    good, bad, nolink = (se.verdict(r, None) for r in rows)
    assert good["verdict"] == "NEW"
    assert bad["verdict"] == "INVALID" and "price is not a number" in bad["errors"] \
        and "source_url must be an https link" in bad["errors"]
    assert nolink["verdict"] == "INVALID" and "source_url missing" in nolink["errors"]


def test_verdict_update_vs_duplicate_vs_review():
    item = se.ingest(PRODUCT, "catalog", fetch=_fetch)
    assert se.verdict(dict(item), None)["verdict"] in ("NEW", "NEEDS_REVIEW")
    same = {"id": 7, "title": "Women Cotton Kurti Blue", "price": 399, "original_product_url": PRODUCT}
    assert se.verdict(dict(item), same)["verdict"] == "DUPLICATE"
    cheaper = dict(same, price=449)
    upd = se.verdict(dict(item), cheaper)
    assert upd["verdict"] == "UPDATE" and upd["changes"]["price"] == {"from": 449, "to": 399}


def test_route_bulk_preview_import_and_templates(api):
    client, owner = api
    csv_text = f"url,title,price\n{PRODUCT},Women Cotton Kurti Blue,399\n{PRODUCT},Again,399\nhttp://x.in/p,Bad,1\n"
    r = client.post("/admin/cc/smart-entry", headers=owner, json={"csv": csv_text, "target": "catalog"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert [i["verdict"] for i in body["items"]] == ["NEW", "DUPLICATE", "INVALID"]
    assert body["verdicts"]["NEW"] == 1 and body["verdicts"]["INVALID"] == 1
    # import needs an explicit confirmation, saves as a review item (never live)
    first = body["items"][0]
    payload = {"items": [{"target": "catalog", "fields": first["fields"]}], "defaults": {"platform": "meesho"}}
    assert client.post("/admin/cc/smart-entry/import", headers=owner, json=payload).status_code == 400
    done = client.post("/admin/cc/smart-entry/import", headers=owner, json={**payload, "confirm": True}).json()
    assert done["saved"] == 1 and done["results"][0]["status"] == "NEEDS_REVIEW"
    # the same link again is now a DUPLICATE of the stored record
    again = client.post("/admin/cc/smart-entry", headers=owner, json={"inputs": [PRODUCT], "target": "catalog"}).json()
    assert again["items"][0]["verdict"] == "DUPLICATE" and again["items"][0]["existing"]["id"] == done["results"][0]["id"]
    # defaults with record facts are refused
    bad = client.post("/admin/cc/smart-entry/import", headers=owner,
                      json={**payload, "confirm": True, "defaults": {"price": 10}})
    assert bad.status_code == 400
    # offers need a person: not bulk-importable
    off = client.post("/admin/cc/smart-entry/import", headers=owner,
                      json={"items": [{"target": "offer", "fields": {}}], "confirm": True}).json()
    assert off["saved"] == 0 and "form" in off["results"][0]["error"]
    # templates: built-ins + a staff-saved one; a template with a price is refused
    t = client.get("/admin/cc/smart-entry/templates?target=catalog", headers=owner).json()
    assert any(x["id"] == "amazon" for x in t["items"]) and t["groups"]["catalog"]["required"]
    saved = client.post("/admin/cc/platform/r/entry_templates", headers=owner,
                        json={"data": {"name": "Phones", "target": "catalog", "defaults": {"category": "phones"}}})
    assert saved.status_code == 200, saved.text
    assert any(x["label"] == "Phones" for x in
               client.get("/admin/cc/smart-entry/templates?target=catalog", headers=owner).json()["items"])
    priced = client.post("/admin/cc/platform/r/entry_templates", headers=owner,
                         json={"data": {"name": "X", "target": "catalog", "defaults": {"price": 999}}})
    assert priced.status_code in (400, 422) and "never price" in priced.text
    assert client.get("/admin/cc/smart-entry/templates").status_code == 401


def test_import_checks_permission_per_item(api):
    client, owner = api
    item = {"target": "catalog", "fields": {"source_url": {"value": PRODUCT}, "title": {"value": "Kurti"}}}
    support = client.post("/admin/cc/staff", headers=owner, json={"name": "sup", "role": "support_agent"})
    assert support.status_code == 200, support.text
    token = {"X-ASKODOX-Staff-Token": support.json()["token"]}
    assert client.post("/admin/cc/smart-entry/import", headers=token,
                       json={"items": [item], "confirm": True}).status_code == 403
    assert client.get("/admin/cc/smart-entry/templates", headers=token).status_code == 403
    # sources-only staff may import a source but not a catalog product
    src = client.post("/admin/cc/staff", headers=owner,
                      json={"name": "src", "role": "support_agent", "permissions": ["overview:view", "sources:create"]})
    assert src.status_code == 200, src.text
    token = {"X-ASKODOX-Staff-Token": src.json()["token"]}
    source = {"target": "source", "fields": {"name": {"value": "Shop"}, "domain": {"value": "shop.example.in"}}}
    out = client.post("/admin/cc/smart-entry/import", headers=token,
                      json={"items": [item, source], "confirm": True,
                            "defaults": {"source_type": "merchant", "connector": "manual"}}).json()
    assert out["results"][0]["ok"] is False and "affiliate_products:create" in out["results"][0]["error"]
    assert out["results"][1]["ok"] is True and out["results"][1]["status"] == "DISABLED"
