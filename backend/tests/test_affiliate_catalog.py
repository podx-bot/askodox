"""Affiliate Product Manager (staff Meesho / Amazon / Flipkart products),
stock + commission automation, affiliate vs organic routing, staff
permissions, audit history, bulk / feed import, source settings and the
organic marketplace search in discovery."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import affiliate_catalog as ac
from app.services.phase_6_9_assistant_service import AffiliateProviderConfig
from app.services.universal_external_result_service import classify_page

MEESHO_URL = "https://www.meesho.com/women-cotton-kurti/p/4xyz"
WISHLINK = "https://wishlink.com/share/abc123"


class _Web:
    """Brave stand-in: general queries get one normal shop, site-restricted
    marketplace queries get real-looking marketplace catalogue pages."""
    configured = True
    last_error = False

    def __init__(self):
        self.queries = []

    def __call__(self, query, limit):
        self.queries.append(query)
        if "site:" in query:
            return [
                {"title": "Amazon.in: Buy Cotton Kurti Online at Best Prices in India",
                 "url": "https://www.amazon.in/s?k=cotton+kurti", "snippet": "Cotton kurti for women ₹399"},
                {"title": "Cotton Kurti - Buy Cotton Kurtis Online at Best Prices | Flipkart",
                 "url": "https://www.flipkart.com/womens-kurtas-kurtis/cotton~fabric/pr?sid=2oq", "snippet": "Cotton kurti"},
                {"title": "Cotton Kurti for Women - Buy Online at Best Price | Meesho",
                 "url": "https://www.meesho.com/cotton-kurti-women/pl/abc", "snippet": "Cotton kurti from ₹199"},
                {"title": "Best 10 cotton kurti brands", "url": "https://www.amazon.in/blog/best-kurti/",
                 "snippet": "cotton kurti guide"},
            ]
        return [{"title": "Cotton Kurti at Fabindia", "url": "https://www.fabindia.com/cotton-kurti/p/1",
                 "snippet": "Cotton kurti ₹1,290"}]


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-af-" + uuid.uuid4().hex[:6]
    db = str(tmp_path / "af.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(db), raising=False)
    monkeypatch.setattr(container, "affiliate_catalog", ac.AffiliateCatalog(db), raising=False)
    monkeypatch.setattr(container, "affiliate_provider_config", AffiliateProviderConfig(db_path=db), raising=False)
    web = _Web()
    monkeypatch.setattr(container, "brave_web_search_provider", web)
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}, web


def _staff(client, owner, role, **extra):
    r = client.post("/admin/cc/staff", headers=owner, json={"name": f"{role} user", "role": role, **extra})
    assert r.status_code == 200, r.text
    return r.json(), {"X-ASKODOX-Staff-Token": r.json()["token"]}


def _discover(client, raw="cotton kurti for women", subject="cotton kurti"):
    body = {"user_id": "", "raw_text": raw, "intent": "buy", "subject": subject, "category": "fashion",
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6}, "dynamic_fields": {}}
    r = client.post("/deals/discover", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def _catalog_rows(data):
    return [m for m in data["matches"] if m.get("origin") == "affiliate_catalog"]


def _add(client, headers, **extra):
    body = {"title": "Women Cotton Kurti", "platform": "meesho", "original_product_url": MEESHO_URL,
            "price": 399, "mrp": 999, "category": "fashion", "images": ["https://images.meesho.com/k1.jpg"],
            "sizes": None, "variants": ["S", "M", "L"], "seller": "Sri Fashions", **extra}
    body = {k: v for k, v in body.items() if v is not None}
    return client.post("/admin/cc/affiliate-products", headers=headers, json=body)


# ------------------------------------------------------------- staff flow --

def test_catalog_staff_can_add_and_edit_but_not_links_commission_or_delete(api):
    client, container, owner, _ = api
    _, staff = _staff(client, owner, "affiliate_catalog_staff")
    assert client.get("/admin/cc/affiliate-products").status_code == 401

    denied = _add(client, staff, affiliate_url=WISHLINK)
    assert denied.status_code == 403 and "affiliate_products:links" in denied.json()["detail"]
    created = _add(client, staff, stock_status="IN_STOCK")
    assert created.status_code == 200, created.text
    item = created.json()["item"]
    assert item["platform"] == "meesho" and item["discount_percent"] == 60
    assert item["stock_status"] == "IN_STOCK" and item["commission_status"] == "UNKNOWN"
    assert item["eligibility"]["state"] == "ACTIVE" and item["eligibility"]["routing"] == "organic"
    assert item["variants"] == ["S", "M", "L"] and item["created_by"].startswith("staff-")

    edited = client.patch(f"/admin/cc/affiliate-products/{item['id']}", headers=staff,
                          json={"price": 349, "description": "Pure cotton, hand block print"})
    assert edited.status_code == 200 and edited.json()["item"]["price"] == 349
    assert client.post(f"/admin/cc/affiliate-products/{item['id']}/commission", headers=staff,
                       json={"status": "ACTIVE"}).status_code == 403
    assert client.patch(f"/admin/cc/affiliate-products/{item['id']}", headers=staff,
                        json={"affiliate_url": WISHLINK}).status_code == 403
    assert client.delete(f"/admin/cc/affiliate-products/{item['id']}?confirm=true", headers=staff).status_code == 403
    assert client.put("/admin/cc/affiliate-sources/meesho", headers=staff,
                      json={"organic_enabled": False}).status_code == 403
    # Duplicate of the same Meesho URL is refused.
    assert _add(client, staff).status_code == 400

    # A viewer-only staff member cannot add anything.
    _, viewer = _staff(client, owner, "analyst", permissions=["affiliate_products:view"])
    assert client.get("/admin/cc/affiliate-products", headers=viewer).status_code == 200
    assert _add(client, viewer).status_code == 403

    detail = client.get(f"/admin/cc/affiliate-products/{item['id']}", headers=staff).json()
    actions = [h["action"] for h in detail["history"]]
    assert actions == ["edit", "create"]
    assert detail["history"][0]["changes"]["price"] == {"from": 399.0, "to": 349.0}
    assert all(h["actor"].startswith("staff-") for h in detail["history"])
    audit = client.get("/admin/cc/audit?limit=50", headers=owner).text
    assert "affiliate_product.create" in audit and "affiliate_product.edit" in audit


def test_validation_never_accepts_invented_or_unsafe_values(api):
    client, _, owner, _ = api
    assert _add(client, owner, original_product_url="http://www.meesho.com/x").status_code == 400
    assert _add(client, owner, price=999, mrp=399).status_code == 400
    assert _add(client, owner, title="").status_code == 400
    bad_platform = _add(client, owner, platform="ebay")
    assert bad_platform.status_code == 400


# ---------------------------------------------- stock / commission / links --

def test_stock_and_commission_transitions_drive_results_and_routing(api):
    client, _, owner, _ = api
    item = _add(client, owner, affiliate_url=WISHLINK).json()["item"]
    pid = item["id"]

    # Stock UNKNOWN + commission UNKNOWN: shown, organic link (never a guess).
    rows = _catalog_rows(_discover(client))
    assert len(rows) == 1 and rows[0]["routing"] == "organic" and rows[0]["affiliate"] is False
    assert rows[0]["destination_url"] == MEESHO_URL and rows[0]["disclosure"] == ""
    assert rows[0]["original_price"] == 999 and rows[0]["discount_percent"] == 60
    assert rows[0]["source_name"] == "Meesho" and rows[0]["price_verified"] is False

    # Commission becomes ACTIVE: the same product now opens via its affiliate link.
    client.post(f"/admin/cc/affiliate-products/{pid}/commission", headers=owner, json={"status": "ACTIVE", "rate": 8})
    row = _catalog_rows(_discover(client))[0]
    assert row["routing"] == "affiliate" and row["affiliate"] is True
    assert row["destination_url"] == WISHLINK and row["disclosure"] == "Affiliate link"

    # Out of stock: not recommended at all; the record and history stay.
    client.post(f"/admin/cc/affiliate-products/{pid}/stock", headers=owner, json={"status": "OUT_OF_STOCK"})
    assert _catalog_rows(_discover(client)) == []
    record = client.get(f"/admin/cc/affiliate-products/{pid}", headers=owner).json()["item"]
    assert record["eligibility"] == {**record["eligibility"], "state": "DISABLED", "reasons": ["out_of_stock"]}

    # Back in stock: re-enabled automatically (nothing else to do).
    client.post(f"/admin/cc/affiliate-products/{pid}/stock", headers=owner, json={"status": "IN_STOCK"})
    row = _catalog_rows(_discover(client))[0]
    assert row["routing"] == "affiliate" and row["stock_status"] == "IN_STOCK"

    # Commission removed: the useful result stays, organic link, no affiliate label.
    client.post(f"/admin/cc/affiliate-products/{pid}/commission", headers=owner, json={"status": "INACTIVE"})
    row = _catalog_rows(_discover(client))[0]
    assert row["routing"] == "organic" and row["destination_url"] == MEESHO_URL and not row["affiliate"]

    # Commission restored: monetized routing comes back.
    client.post(f"/admin/cc/affiliate-products/{pid}/commission", headers=owner, json={"status": "ACTIVE"})
    assert _catalog_rows(_discover(client))[0]["routing"] == "affiliate"

    # Affiliate link removed (owner has links permission): organic again.
    client.patch(f"/admin/cc/affiliate-products/{pid}", headers=owner, json={"affiliate_url": None})
    row = _catalog_rows(_discover(client))[0]
    assert row["routing"] == "organic" and row["destination_url"] == MEESHO_URL

    # Disabled / deleted: gone from results, history kept.
    client.post(f"/admin/cc/affiliate-products/{pid}/disable", headers=owner)
    assert _catalog_rows(_discover(client)) == []
    client.post(f"/admin/cc/affiliate-products/{pid}/enable", headers=owner)
    assert len(_catalog_rows(_discover(client))) == 1
    assert client.delete(f"/admin/cc/affiliate-products/{pid}", headers=owner).status_code == 409
    assert client.delete(f"/admin/cc/affiliate-products/{pid}?confirm=true", headers=owner).status_code == 200
    assert _catalog_rows(_discover(client)) == []
    history = client.get(f"/admin/cc/affiliate-products/{pid}", headers=owner).json()["history"]
    assert [h["action"] for h in history][:3] == ["delete", "enable", "disable"]
    assert {"stock", "commission", "create"} <= {h["action"] for h in history}


def test_source_settings_switch_organic_and_monetization_without_exposing_credentials(api):
    client, container, owner, _ = api
    container.affiliate_provider_config.register("meesho", name="Meesho", category="product", active=False,
                                                 api_secret="SHOULD-NOT-LEAK")
    item = _add(client, owner, affiliate_url=WISHLINK, commission_status="ACTIVE",
                stock_status="IN_STOCK").json()["item"]
    assert item["eligibility"]["routing"] == "affiliate"

    listing = client.get("/admin/cc/affiliate-sources", headers=owner)
    assert "SHOULD-NOT-LEAK" not in listing.text
    meesho = next(s for s in listing.json()["items"] if s["platform"] == "meesho")
    assert meesho["has_credentials"] is True and meesho["catalog"]["products"] == 1
    assert {"amazon", "flipkart", "meesho", "wishlink", "other"} <= {s["platform"] for s in listing.json()["items"]}

    client.put("/admin/cc/affiliate-sources/meesho", headers=owner, json={"monetization_enabled": False})
    assert _catalog_rows(_discover(client))[0]["routing"] == "organic"
    client.put("/admin/cc/affiliate-sources/meesho", headers=owner,
               json={"monetization_enabled": True, "commission_state": "INACTIVE"})
    assert _catalog_rows(_discover(client))[0]["routing"] == "organic"
    client.put("/admin/cc/affiliate-sources/meesho", headers=owner, json={"commission_state": "ACTIVE"})
    assert _catalog_rows(_discover(client))[0]["routing"] == "affiliate"
    client.put("/admin/cc/affiliate-sources/meesho", headers=owner, json={"organic_enabled": False})
    data = _discover(client)
    assert _catalog_rows(data) == []
    assert not any(m.get("marketplace") == "meesho" for m in data["matches"])
    # The registry's other settings survived the source edits.
    assert container.affiliate_provider_config.providers["meesho"]["active"] is False
    assert "affiliate_source.save" in client.get("/admin/cc/audit?limit=50", headers=owner).text
    assert client.put("/admin/cc/affiliate-sources/meesho", headers=owner, json={"mode": "magic"}).status_code == 400


# ------------------------------------------------------------ bulk / feed --

def test_bulk_manual_entry_and_trusted_feed_status_updates(api):
    client, _, owner, _ = api
    _, staff = _staff(client, owner, "affiliate_catalog_staff")
    csv_text = (
        "platform,title,url,price,original_price,category,stock,image\n"
        "meesho,Printed Cotton Kurti,https://www.meesho.com/printed-kurti/p/1,299,699,fashion,in stock,https://images.meesho.com/a.jpg\n"
        "meesho,Rayon Kurti,https://www.meesho.com/rayon-kurti/p/2,349,,fashion,,\n"
        "meesho,Broken row,not-a-url,10,,fashion,,\n"
    )
    dry = client.post("/admin/cc/affiliate-products/bulk", headers=staff, json={"csv": csv_text, "dry_run": True}).json()
    assert dry["ok"] == 2 and dry["failed"] == 1
    assert client.get("/admin/cc/affiliate-products", headers=staff).json()["summary"]["total"] == 0
    done = client.post("/admin/cc/affiliate-products/bulk", headers=staff, json={"csv": csv_text}).json()
    assert done["ok"] == 2 and done["failed"] == 1 and "https" in done["results"][2]["error"]

    # Commission columns need the commission permission, row by row.
    denied = client.post("/admin/cc/affiliate-products/bulk", headers=staff, json={
        "mode": "status", "rows": [{"url": "https://www.meesho.com/rayon-kurti/p/2", "commission": "active"}]}).json()
    assert denied["failed"] == 1 and "commission" in denied["results"][0]["error"]

    # A trusted feed marks one item out of stock and never creates products.
    feed = client.post("/admin/cc/affiliate-products/bulk", headers=owner, json={
        "mode": "status", "check_source": "feed", "rows": [
            {"url": "https://www.meesho.com/printed-kurti/p/1", "stock": "OutOfStock"},
            {"url": "https://www.meesho.com/never-added/p/9", "stock": "in stock"},
        ]}).json()
    assert feed["ok"] == 1 and "never create" in feed["results"][1]["error"]
    items = {i["title"]: i for i in client.get("/admin/cc/affiliate-products", headers=owner).json()["items"]}
    assert items["Printed Cotton Kurti"]["stock_status"] == "OUT_OF_STOCK"
    assert items["Printed Cotton Kurti"]["stock_check_source"] == "feed"
    assert items["Rayon Kurti"]["stock_status"] == "UNKNOWN"
    titles = [r["title"] for r in _catalog_rows(_discover(client, "kurti", "kurti"))]
    assert titles == ["Rayon Kurti"]
    health = {s["platform"]: s for s in client.get("/admin/cc/affiliate-sources", headers=owner).json()["items"]}
    assert health["meesho"]["health"]["method"] in {"feed", "web_search"}


# ------------------------------------------------------- metadata extract --

def test_extract_reads_page_metadata_as_suggestions_only(api, monkeypatch):
    client, container, owner, _ = api
    html = """<html><head><title>Kurti | Meesho</title>
      <meta property="og:title" content="Women Cotton Kurti">
      <meta property="og:image" content="https://images.meesho.com/og.jpg">
      <script type="application/ld+json">{"@type":"Product","name":"Women Cotton Kurti Blue",
        "image":["https://images.meesho.com/1.jpg"],"brand":{"name":"Sri Fashions"},
        "offers":{"@type":"Offer","price":"399","availability":"https://schema.org/OutOfStock"}}</script>
      </head></html>"""
    monkeypatch.setattr(container, "affiliate_page_fetch", lambda url: html, raising=False)
    data = client.post("/admin/cc/affiliate-products/extract", headers=owner, json={"url": MEESHO_URL}).json()
    assert data["status"] == "ok" and data["fields"]["title"] == "Women Cotton Kurti Blue"
    assert data["fields"]["price"] == 399 and data["fields"]["platform"] == "meesho"
    assert data["fields"]["images"][0] == "https://images.meesho.com/og.jpg"
    assert data["suggested_stock"] == "OUT_OF_STOCK"
    assert client.get("/admin/cc/affiliate-products", headers=owner).json()["summary"]["total"] == 0

    def blocked(url):
        raise PermissionError("403")
    monkeypatch.setattr(container, "affiliate_page_fetch", blocked, raising=False)
    data = client.post("/admin/cc/affiliate-products/extract", headers=owner, json={"url": MEESHO_URL}).json()
    assert data["status"] == "unavailable" and data["found"] == []


def test_fetch_page_refuses_private_hosts():
    with pytest.raises(ValueError):
        ac.fetch_page("https://localhost/x")
    with pytest.raises(ValueError):
        ac.fetch_page("http://example.com/x")


# --------------------------------------------------- marketplace discovery --

def test_marketplace_pages_are_store_pages_not_articles():
    assert classify_page("https://www.amazon.in/s?k=phone", "Amazon.in: Buy Mobile Phones Online at Best Prices") == "store"
    assert classify_page("https://www.flipkart.com/mobiles/pr?sid=t", "Mobiles at Best Prices | Flipkart") == "store"
    assert classify_page("https://www.meesho.com/x/pl/1", "Dresses Online at Best Price | Meesho") == "store"
    assert classify_page("https://www.amazon.in/blog/best-phones/", "Best 10 phones") == "article"
    assert classify_page("https://www.gadgets.example/x", "Best phones under 15000 in 2026") == "article"


def test_discovery_shows_marketplaces_organically_after_local_and_online(api):
    client, _, owner, web = api
    data = _discover(client)
    market = [m for m in data["matches"] if m.get("marketplace")]
    assert {m["marketplace"] for m in market} == {"amazon", "flipkart", "meesho"}
    assert all(m["routing"] == "organic" and m["affiliate"] is False and m["disclosure"] == "" for m in market)
    assert {m["source_name"] for m in market} == {"Amazon", "Flipkart", "Meesho"}
    assert not any("blog" in m["destination_url"] for m in market)
    query = next(q for q in web.queries if "site:" in q)
    assert "site:amazon.in" in query and "site:flipkart.com" in query and "site:meesho.com" in query
    # Order: the normal online shop first, marketplaces after it.
    ids = [m["id"] for m in data["matches"]]
    online = next(i for i, m in enumerate(data["matches"]) if "fabindia" in str(m.get("destination_url")))
    assert online < ids.index(market[0]["id"])
    assert data["marketplaces"]["found"] == {"amazon": 1, "flipkart": 1, "meesho": 1}

    # A staff catalog product no longer suppresses the normal online search.
    _add(client, owner, title="Cotton Kurti Women", stock_status="IN_STOCK")
    data = _discover(client)
    assert any("fabindia" in str(m.get("destination_url")) for m in data["matches"])
    assert len(_catalog_rows(data)) == 1


def test_no_marketplace_search_for_services_food_or_used(api):
    client, _, _, web = api
    body = {"user_id": "", "raw_text": "AC repair near me", "intent": "needservice", "subject": "AC repair",
            "category": "services", "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6},
            "dynamic_fields": {}}
    service = client.post("/deals/discover", json=body).json()
    assert service["marketplaces"].get("searched") in (None, [])
    body.update(raw_text="1 kg chicken curry cut", subject="chicken curry cut", category="food", intent="buy")
    food = client.post("/deals/discover", json=body).json()
    assert food["marketplaces"]["status"] == "not_applicable", food["marketplaces"]
    assert not any("site:" in q for q in web.queries), web.queries


def test_external_click_route_used_by_the_app_records_a_masked_click(api):
    client, container, _, _ = api
    r = client.post("/deals/external/click", json={"provider_id": "Meesho", "result_id": "catalog-7",
                                                    "destination_url": MEESHO_URL, "user_id": "app-919876543210"})
    assert r.status_code == 200 and r.json() == {"recorded": True, "event": "click"}
    row = container.database.fetchone("SELECT * FROM external_commerce_events ORDER BY id DESC LIMIT 1")
    assert row["provider_id"] == "meesho" and "9876543210" not in str(dict(row))
    # The old app path never existed (the #123 bug the app now avoids).
    assert client.post("/external/click", json={"provider_id": "x", "result_id": "y",
                                                 "destination_url": MEESHO_URL}).status_code == 404
