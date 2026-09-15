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