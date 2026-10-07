"""Affiliate Product Hub + Meesho provider: paste -> detect -> extract
(truthful, with provenance) -> preview -> edit -> draft / publish -> enable
-> eligible for customer results; bulk partial failure, retry, duplicates
and least-privilege permissions."""
import dataclasses
import json
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import affiliate_catalog as ac
from app.services import affiliate_hub as hub
from app.services import affiliate_providers as providers
from app.services.phase_6_9_assistant_service import AffiliateProviderConfig

MEESHO_PAGE_URL = "https://www.meesho.com/women-rayon-kurti/p/5abcde"
MEESHO_SHORT = "https://msho.in/k2Ab9"

NEXT_DATA = {
    "props": {"pageProps": {"initialState": {"product": {"details": {"data": {
        "name": "Women Rayon Printed Kurti",
        "min_product_price": 349,
        "original_price": 899,
        "images": ["https://images.meesho.com/images/products/1/a.jpg",
                   "https://images.meesho.com/images/products/1/b.jpg"],
        "supplier_name": "Sri Lakshmi Fashions",
        "category_name": "Kurtis",
        "description": "Rayon kurti with print",
        "variations": [{"name": "S"}, {"name": "M"}, {"name": "L"}],
    }}}}}},
}
MEESHO_HTML = (
    '<html><head><title>Women Rayon Printed Kurti | Meesho</title>'
    f'<link rel="canonical" href="{MEESHO_PAGE_URL}">'
    '<meta property="og:url" content="' + MEESHO_PAGE_URL + '">'
    '<meta name="keywords" content="kurti, rayon kurti, women kurti">'
    '<meta property="al:android:url" content="meesho://product/5abcde">'
    '</head><body><script id="__NEXT_DATA__" type="application/json">' + json.dumps(NEXT_DATA) +
    '</script></body></html>'
)
SCHEMA_HTML = (
    '<html><head><meta property="og:title" content="Steel Water Bottle 1L">'
    '<meta property="og:image" content="https://cdn.example.com/bottle.jpg">'
    '<script type="application/ld+json">{"@type":"Product","name":"Steel Water Bottle 1L",'
    '"offers":{"@type":"Offer","price":"499","priceSpecification":[{"@type":"UnitPriceSpecification",'
    '"priceType":"https://schema.org/ListPrice","price":"799"}]},'
    '"hasVariant":[{"@type":"Product","color":"Blue"},{"@type":"Product","color":"Black"}]}</script>'
    '</head></html>'
)


def fetcher(pages):
    def fetch(url):
        if url not in pages:
            raise TimeoutError("blocked by provider")
        return pages[url]
    return fetch


# --------------------------------------------------------- provider layer --

def test_meesho_detection_and_link_kinds_are_generic_adapters():
    assert providers.adapter_for(MEESHO_PAGE_URL).id == "meesho"
    assert providers.adapter_for(MEESHO_SHORT).id == "meesho"
    assert providers.adapter_for(MEESHO_SHORT).link_kind(MEESHO_SHORT) == "affiliate"
    assert providers.adapter_for(MEESHO_PAGE_URL).link_kind(MEESHO_PAGE_URL) == "product"
    assert providers.adapter_for("https://www.amazon.in/dp/B0ABCDEFGH?tag=askodox-21").link_kind(
        "https://www.amazon.in/dp/B0ABCDEFGH?tag=askodox-21") == "affiliate"
    assert providers.adapter_for("https://example.com/x") is None
    assert {"meesho", "amazon", "flipkart", "wishlink"} <= set(providers.ADAPTERS)


def test_meesho_extraction_reads_only_what_the_page_states_with_provenance():
    out = providers.extract(MEESHO_PAGE_URL, fetch=fetcher({MEESHO_PAGE_URL: MEESHO_HTML}))
    f = out["fields"]
    assert out["provider"] == "meesho" and out["link_kind"] == "product"
    assert f["title"] == "Women Rayon Printed Kurti"
    assert f["price"] == 349 and f["mrp"] == 899
    assert f["discount_percent"] == round((899 - 349) / 899 * 100)
    assert f["images"][0].startswith("https://images.meesho.com/") and f["image_url"] == f["images"][0]
    assert f["seller"] == "Sri Lakshmi Fashions" and f["category"] == "Kurtis"
    assert f["variants"] == ["S", "M", "L"]
    assert f["keywords"][:2] == ["kurti", "rayon kurti"]
    assert f["deep_link"] == "meesho://product/5abcde"
    assert f["product_id"] == "5abcde"
    prov = out["provenance"]
    assert prov["price"]["source"] == "page_embedded_data" and prov["price"]["verified"] is False
    assert prov["discount_percent"]["source"] == "derived" and prov["discount_percent"]["from"] == ["price", "mrp"]
    assert all("checked_at" in p for p in prov.values())
    # Commission is never read from a page.
    assert out["commission"] == {"status": "UNKNOWN", "label": "Needs verification", "source": None}
    for invented in ("stock_status", "rating", "review_count", "commission_status", "delivery"):
        assert invented not in f


def test_generic_schema_org_mrp_and_variants_for_any_provider():
    url = "https://shop.example.com/p/bottle"
    out = providers.extract(url, fetch=fetcher({url: SCHEMA_HTML}))
    f = out["fields"]
    assert f["price"] == 499 and f["mrp"] == 799 and f["variants"] == ["Blue", "Black"]
    assert out["provider"] == "other"


def test_an_mrp_below_the_price_is_dropped_never_shown():
    html = SCHEMA_HTML.replace('"price":"799"', '"price":"99"')
    url = "https://shop.example.com/p/bottle2"
    out = providers.extract(url, fetch=fetcher({url: html}))
    assert "mrp" not in out["fields"] and "discount_percent" not in out["fields"]


def test_blocked_page_keeps_the_url_and_marks_everything_missing():
    out = providers.extract(MEESHO_SHORT, fetch=fetcher({}))
    f = out["fields"]
    assert out["status"] == "unavailable"
    assert f["affiliate_url"] == MEESHO_SHORT and out["link_kind"] == "affiliate"
    assert out["provenance"]["affiliate_url"]["source"] == "pasted_link"
    assert {"title", "price", "images"} <= set(out["missing"])
    assert "price" not in f and "title" not in f


# --------------------------------------------------------------- the hub --

def test_preview_reports_each_link_on_its_own(tmp_path):
    store = ac.AffiliateCatalog(str(tmp_path / "hub.db"))
    text = f"""Here are the links:
    {MEESHO_PAGE_URL}
    {MEESHO_SHORT}, http://insecure.example.com/x
    {MEESHO_PAGE_URL}"""
    links = hub.split_links(text)
    assert links == [MEESHO_PAGE_URL, MEESHO_SHORT, "http://insecure.example.com/x"]
    out = hub.preview(store, links + [MEESHO_PAGE_URL + "?utm_source=wa"], fetch=fetcher({MEESHO_PAGE_URL: MEESHO_HTML}))
    by = {i["index"]: i for i in out["items"]}
    assert by[0]["status"] == "READY"
    assert by[1]["status"] == "MANUAL_ENTRY" and by[1]["fields"]["affiliate_url"] == MEESHO_SHORT
    assert by[2]["status"] == "INVALID"
    assert by[3]["status"] == "DUPLICATE" and by[3]["duplicate_of_item"] == 0
    assert out["counts"]["READY"] == 1


def _allow(*verbs):
    return lambda verb: verb in verbs


def test_import_drafts_by_default_publish_needs_permission_and_partial_failure(tmp_path):
    store = ac.AffiliateCatalog(str(tmp_path / "hub2.db"))
    preview = hub.preview(store, [MEESHO_PAGE_URL, MEESHO_SHORT], fetch=fetcher({MEESHO_PAGE_URL: MEESHO_HTML}))
    good, blocked = preview["items"]
    staff = _allow("create", "edit")
    result = hub.import_items(store, [{**good, "publish": True}, blocked], actor="staff-1", allowed=staff)
    first, second = result["results"]
    assert first["ok"] and first["review_status"] == "NEEDS_REVIEW", "no publish grant -> submitted for review"
    assert "submitted for review" in " ".join(first["warnings"])
    assert not second["ok"] and second["retry"] is True and "name is required" in second["error"]
    assert result == {**result, "ok": 1, "failed": 1}
    # Retry the failed item alone after staff typed the missing name.
    retried = hub.import_items(store, [{**blocked, "edited": {"title": "Kurti (Meesho share link)"}}],
                               actor="staff-1", allowed=_allow("create", "edit", "links"))
    assert retried["ok"] == 1
    item = store.get(retried["results"][0]["id"])
    assert item["review_status"] == "DRAFT" and item["commission_status"] == "UNKNOWN"
    assert item["commission_label"].startswith("Unknown")
    assert item["provenance"]["title"]["source"] == "staff" and item["provenance"]["title"]["verified"] is True
    assert item["affiliate_url"] == MEESHO_SHORT
    # The saved product keeps where each fetched value came from.
    saved = store.get(first["id"])
    assert saved["provenance"]["price"]["source"] == "page_embedded_data"
    assert saved["extraction"]["provider"] == "meesho" and saved["keywords"][0] == "kurti"
    assert saved["deep_link"] == "meesho://product/5abcde"
    # Import again: the catalog's own duplicate rule refuses it.
    again = hub.import_items(store, [good], actor="staff-1", allowed=staff)
    assert not again["results"][0]["ok"] and again["results"][0]["retry"] is False


def test_publish_enable_disable_archive_restore_and_customer_eligibility(tmp_path):
    store = ac.AffiliateCatalog(str(tmp_path / "hub3.db"))
    item = hub.preview(store, [MEESHO_PAGE_URL], fetch=fetcher({MEESHO_PAGE_URL: MEESHO_HTML}))["items"][0]
    pid = hub.import_items(store, [item], actor="staff-1", allowed=_allow("create"))["results"][0]["id"]
    assert not store.get(pid)["eligibility"]["eligible"], "a draft never reaches customers"
    assert store.search("rayon kurti") == [] or all(r.get("id") != pid for r in store.search("rayon kurti"))
    denied = hub.bulk_action(store, [pid], "publish", actor="staff-1", allowed=_allow("create", "edit"))
    assert denied["failed"] == 1 and "publish" in denied["results"][0]["error"]
    owner = _allow("create", "edit", "publish", "delete", "links")
    published = hub.bulk_action(store, [pid], "publish", actor="owner", allowed=owner)
    assert published["results"][0]["eligible"] is True
    found = store.search("rayon kurti")
    assert any(r.get("id") == pid for r in found), "a LIVE + enabled product is eligible for customer results"
    row = next(r for r in found if r.get("id") == pid)
    assert row["eligibility"]["routing"] == "organic", "commission UNKNOWN -> never affiliate routing"
    assert hub.bulk_action(store, [pid], "disable", actor="owner", allowed=owner)["results"][0]["eligible"] is False
    assert hub.bulk_action(store, [pid], "enable", actor="owner", allowed=owner)["results"][0]["eligible"] is True
    archived = hub.bulk_action(store, [pid], "archive", actor="owner", allowed=owner)
    assert archived["results"][0]["archived"] is True and not any(r.get("id") == pid for r in store.search("rayon kurti"))
    restored = hub.bulk_action(store, [pid, 999999], "restore", actor="owner", allowed=owner)
    assert restored["ok"] == 1 and restored["failed"] == 1, "bulk = per-item partial success"
    back = store.get(pid)
    assert back["review_status"] == "NEEDS_REVIEW" and not back["active"], "restored items are re-checked first"
    with pytest.raises(ValueError):
        hub.bulk_action(store, [pid], "explode", actor="owner", allowed=owner)


# ------------------------------------------------------------ HTTP + perms --

@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-hub-" + uuid.uuid4().hex[:6]
    db = str(tmp_path / "hubapi.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(db), raising=False)
    monkeypatch.setattr(container, "affiliate_catalog", ac.AffiliateCatalog(db), raising=False)
    monkeypatch.setattr(container, "affiliate_provider_config", AffiliateProviderConfig(db_path=db), raising=False)
    monkeypatch.setattr(container, "affiliate_page_fetch", fetcher({MEESHO_PAGE_URL: MEESHO_HTML}), raising=False)
    return TestClient(app), {"X-ASKODOX-Admin-Key": key}


def _staff(client, owner, role, **extra):
    r = client.post("/admin/cc/staff", headers=owner, json={"name": f"{role} user", "role": role, **extra})
    assert r.status_code == 200, r.text
    return {"X-ASKODOX-Staff-Token": r.json()["token"]}


def test_hub_endpoints_end_to_end_with_least_privilege(api):
    client, owner = api
    staff = _staff(client, owner, "affiliate_catalog_staff")
    viewer = _staff(client, owner, "analyst", permissions=["affiliate_products:view"])
    assert client.post("/admin/cc/affiliate-hub/preview", headers=viewer,
                       json={"text": MEESHO_PAGE_URL}).status_code == 403
    preview = client.post("/admin/cc/affiliate-hub/preview", headers=staff,
                          json={"text": f"{MEESHO_PAGE_URL}\n{MEESHO_SHORT}"})
    assert preview.status_code == 200, preview.text
    items = preview.json()["items"]
    assert [i["status"] for i in items] == ["READY", "MANUAL_ENTRY"]
    imported = client.post("/admin/cc/affiliate-hub/import", headers=staff,
                           json={"items": [{**items[0], "publish": True}]}).json()
    pid = imported["results"][0]["id"]
    assert imported["results"][0]["review_status"] == "NEEDS_REVIEW"
    # Staff cannot publish or archive; the owner can.
    r = client.post("/admin/cc/affiliate-hub/bulk-action", headers=staff, json={"ids": [pid], "action": "publish"})
    assert r.status_code == 200 and r.json()["failed"] == 1
    r = client.post("/admin/cc/affiliate-hub/bulk-action", headers=owner, json={"ids": [pid], "action": "publish"})
    assert r.json()["ok"] == 1 and r.json()["results"][0]["eligible"] is True
    detail = client.get(f"/admin/cc/affiliate-products/{pid}", headers=owner).json()["item"]
    assert detail["provenance"]["price"]["source"] == "page_embedded_data"
    assert detail["commission_status"] == "UNKNOWN"
    providers_list = client.get("/admin/cc/affiliate-hub/providers", headers=staff).json()["providers"]
    assert providers_list[0]["id"] == "meesho" and providers_list[0]["embedded_page_data"] is True
    # The existing single-link extract endpoint is provider-aware too.
    single = client.post("/admin/cc/affiliate-products/extract", headers=staff, json={"url": MEESHO_PAGE_URL}).json()
    assert single["provider"] == "meesho" and single["fields"]["mrp"] == 899


def test_publish_permission_is_in_the_catalog_and_presets():
    from app.repositories.command_center_repository import PERMISSIONS, ROLE_PRESETS

    assert "affiliate_products:publish" in PERMISSIONS
    assert "affiliate_products:publish" in ROLE_PRESETS["affiliate_manager"]
    assert "affiliate_products:publish" in ROLE_PRESETS["admin"]
    assert "affiliate_products:publish" not in ROLE_PRESETS["affiliate_catalog_staff"]
