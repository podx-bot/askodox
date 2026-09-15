import pytest

from app.repositories.product_catalog_repository import ProductCatalogRepository


@pytest.fixture()
def repo(tmp_path):
    return ProductCatalogRepository(str(tmp_path / "catalog.db"))


def test_search_active_matches_subject_case_insensitively(repo):
    repo.upsert_product(
        "seller-1",
        "Chicken 5kg skinless curry cut",
        price=220,
        unit="kg",
        stock_status="in_stock",
        seller_name="Fresh Chicken Vijayawada",
        location_label="Vijayawada",
    )

    results = repo.search_active("CHICKEN")

    assert len(results) == 1
    assert results[0]["seller_name"] == "Fresh Chicken Vijayawada"
    assert results[0]["location_label"] == "Vijayawada"
    assert results[0]["price"] == 220


def test_search_active_matches_brand_and_variant_too(repo):
    repo.upsert_product("seller-1", "Rice", brand="India Gate", variant="Basmati 5kg")

    assert [row["id"] for row in repo.search_active("india gate")]
    assert [row["id"] for row in repo.search_active("basmati")]


def test_search_active_excludes_inactive_and_respects_limit(repo):
    for i in range(5):
        repo.upsert_product(f"seller-{i}", f"Health Insurance Plan {i}")

    results = repo.search_active("insurance", limit=3)

    assert len(results) == 3


def test_search_active_returns_empty_for_blank_query(repo):
    repo.upsert_product("seller-1", "Chicken")

    assert repo.search_active("") == []
    assert repo.search_active("   ") == []


def test_search_active_returns_empty_when_nothing_matches(repo):
    repo.upsert_product("seller-1", "Chicken")

    assert repo.search_active("mutual funds") == []


def test_upsert_product_reuses_row_for_same_seller_and_subject(repo):
    first_id = repo.upsert_product("seller-1", "Chicken", price=200)
    second_id = repo.upsert_product("seller-1", "Chicken", price=210)

    assert first_id == second_id
    assert repo.get(first_id)["price"] == 210


def test_upsert_product_persists_seller_operating_fields(repo):
    product_id = repo.upsert_product(
        "seller-1",
        "AC repair",
        category_tag="Home Services",
        service_area="5 km around Vuyyuru",
        working_hours="7 AM - 9 PM, all days",
    )

    product = repo.get(product_id)
    assert product["category_tag"] == "Home Services"
    assert product["service_area"] == "5 km around Vuyyuru"
    assert product["working_hours"] == "7 AM - 9 PM, all days"


def test_search_active_matches_category(repo):
    repo.upsert_product("seller-1", "Fresh produce", category_tag="Groceries & Food")

    assert len(repo.search_active("groceries")) == 1


def test_search_active_falls_back_to_token_match_for_descriptive_queries(repo):
    repo.upsert_product(
        "VMM2424",
        "CHICKEN & MUTTON",
        price=200,
        unit="kg",
        stock_status="in_stock",
        seller_name="Murali Manohar chicken & Mutton Shop",
        location_label="vuyyuru",
    )

    results = repo.search_active("curry cut skinless chicken")

    assert len(results) == 1
    assert results[0]["seller_name"] == "Murali Manohar chicken & Mutton Shop"


def test_search_active_does_not_false_positive_on_conversational_filler(repo):
    repo.upsert_product("VMM2424", "CHICKEN & MUTTON", price=200)

    assert repo.search_active("2.25 not curry cut it biryani cut 80 grmas each pices") == []
    assert repo.search_active("rate please") == []
    assert repo.search_active("first confirm price") == []
    assert repo.search_active("yes") == []
    assert repo.search_active("show nearby") == []


def test_upsert_product_persists_trust_and_compliance_fields(repo):
    """2026-09-15 (round 2): after a role-by-role (Seller/Provider/Buyer/
    Service-taker) research pass, added precise_location, cancellation_policy,
    payout_reference, gstin, pan, and id_verification_status. None of these
    ever store a raw national-ID number (e.g. Aadhaar) -- only a plain
    verification-status string.
    """
    product_id = repo.upsert_product(
        "VMM2424",
        "CHICKEN & MUTTON",
        precise_location="16.4419,80.6423 (near Vuyyuru bus stand)",
        cancellation_policy="No cancellation after order is packed.",
        payout_reference="murali@upi",
        gstin="37ABCDE1234F1Z5",
        pan="ABCDE1234F",
        id_verification_status="verified",
    )

    product = repo.get(product_id)
    assert product["precise_location"] == "16.4419,80.6423 (near Vuyyuru bus stand)"
    assert product["cancellation_policy"] == "No cancellation after order is packed."
    assert product["payout_reference"] == "murali@upi"
    assert product["gstin"] == "37ABCDE1234F1Z5"
    assert product["pan"] == "ABCDE1234F"
    assert product["id_verification_status"] == "VERIFIED"


def test_upsert_product_leaves_trust_fields_unset_by_default(repo):
    product_id = repo.upsert_product("seller-1", "Tailoring")

    product = repo.get(product_id)
    assert product["id_verification_status"] is None
    assert product["gstin"] is None
    assert product["pan"] is None


def test_list_active_for_seller_returns_only_that_sellers_active_listings(repo):
    repo.upsert_product("seller-1", "Mango Pickle", price=250, unit="kg")
    repo.upsert_product("seller-1", "Lime Pickle", price=200, unit="kg")
    repo.upsert_product("seller-2", "Chicken", price=220, unit="kg")

    listings = repo.list_active_for_seller("seller-1")

    assert len(listings) == 2
    assert {row["subject"] for row in listings} == {"Mango Pickle", "Lime Pickle"}
    assert all(row["seller_user_id"] == "seller-1" for row in listings)


def test_list_active_for_seller_orders_most_recently_updated_first(repo):
    repo.upsert_product("seller-1", "First Item")
    repo.upsert_product("seller-1", "Second Item")

    listings = repo.list_active_for_seller("seller-1")

    assert listings[0]["subject"] == "Second Item"
    assert listings[1]["subject"] == "First Item"