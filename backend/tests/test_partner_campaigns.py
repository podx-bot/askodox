"""Partner campaigns in the ONE item store: app installs, referral programmes
and financial-services partner offers. Always labelled (never passed off as
organic), relevance-first (never shown because they pay), financial offers
only for a need about their own category, no reward promised."""
from app.services import affiliate_catalog as ac


def _store(tmp_path):
    return ac.AffiliateCatalog(str(tmp_path / "items.db"))


def _add(store, title, item_type, category, url):
    return store.create({"title": title, "item_type": item_type, "category": category,
                         "original_product_url": url, "description": title}, actor="test", review_status="LIVE")


def test_campaign_types_are_labelled_and_relevance_first(tmp_path):
    store = _store(tmp_path)
    assert {"app_install", "referral", "financial_offer"} <= set(ac.ITEM_TYPES)
    _add(store, "Example Budget Planner app", "app_install", "finance apps", "https://apps.example.test/budget")
    _add(store, "Example Demat account opening", "financial_offer", "demat account trading",
         "https://broker.example.test/open")
    _add(store, "Example Refer a friend grocery", "referral", "grocery", "https://grocery.example.test/refer")
    app_rows = [ac.result_row(i) for i in store.search("budget planner app")]
    assert app_rows and app_rows[0]["item_type"] == "app_install" and app_rows[0]["partner_offer"] is True
    assert "may earn a commission" in app_rows[0]["disclosure"] and "No reward is promised" in app_rows[0]["disclosure"]
    fin = [ac.result_row(i) for i in store.search("demat account")]
    assert fin and "does not give financial advice" in fin[0]["disclosure"]
    # A financial offer never appears for an unrelated need, even if a title word matches.
    assert not [i for i in store.search("example opening hours") if i.get("item_type") == "financial_offer"]
    ref = [ac.result_row(i) for i in store.search("grocery refer")]
    assert ref and ref[0]["item_type"] == "referral" and ref[0]["disclosure"].startswith("Referral programme")
    # Ordinary products keep their old disclosure rules.
    _add(store, "Cotton kurti", "product", "fashion", "https://www.meesho.com/cotton-kurti/p/1")
    plain = ac.result_row(store.search("cotton kurti")[0])
    assert plain["partner_offer"] is False


def test_staff_need_the_offers_grant_for_campaigns():
    from app.api.routes.staff_workspace import TYPE_PERMISSION

    for t in ("app_install", "referral", "financial_offer"):
        assert TYPE_PERMISSION[t] == "offers:create"
