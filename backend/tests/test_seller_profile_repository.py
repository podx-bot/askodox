import pytest

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.repositories.seller_profile_repository import SellerProfileRepository
from app.services.seller_tiers import REGULAR_LISTING_THRESHOLD, TIER_BUSINESS, TIER_CASUAL, TIER_REGULAR, TIER_SERVICE_PROVIDER


def test_unknown_seller_has_no_profile(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    assert repo.get("app-phone-919876543210") is None


def test_first_listing_creates_a_casual_profile(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    profile = repo.record_listing_created("app-phone-919876543210", has_gstin=False)
    assert profile["tier"] == TIER_CASUAL
    assert profile["total_listing_count"] == 1
    assert profile["has_gstin"] is False
    stored = repo.get("app-phone-919876543210")
    assert stored["tier"] == TIER_CASUAL
    assert stored["total_listing_count"] == 1


def test_seller_upgrades_to_regular_once_the_threshold_is_reached(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    seller = "app-phone-919876543210"
    profile = None
    for _ in range(REGULAR_LISTING_THRESHOLD):
        profile = repo.record_listing_created(seller, has_gstin=False)
    assert profile["total_listing_count"] == REGULAR_LISTING_THRESHOLD
    assert profile["tier"] == TIER_REGULAR


def test_a_single_gstin_listing_makes_a_brand_new_seller_a_business(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    profile = repo.record_listing_created("app-phone-919876543210", has_gstin=True)
    assert profile["tier"] == TIER_BUSINESS
    assert profile["total_listing_count"] == 1


def test_gstin_status_is_sticky_across_later_listings_without_one(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    seller = "app-phone-919876543210"
    repo.record_listing_created(seller, has_gstin=False)
    with_gstin = repo.record_listing_created(seller, has_gstin=True)
    assert with_gstin["tier"] == TIER_BUSINESS
    still_business = repo.record_listing_created(seller, has_gstin=False)
    assert still_business["tier"] == TIER_BUSINESS
    assert still_business["has_gstin"] is True
    assert still_business["total_listing_count"] == 3


def test_two_different_sellers_are_tracked_independently(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    repo.record_listing_created("app-phone-911111111111", has_gstin=True)
    other = repo.record_listing_created("app-phone-922222222222", has_gstin=False)
    assert other["tier"] == TIER_CASUAL
    assert other["total_listing_count"] == 1


def test_blank_seller_user_id_raises(tmp_path):
    repo = SellerProfileRepository(str(tmp_path / "test.db"))
    with pytest.raises(ValueError):
        repo.record_listing_created("   ", has_gstin=False)


def test_backfill_creates_profile_for_preexisting_seller(tmp_path):
    db = str(tmp_path / "test.db")
    catalog = ProductCatalogRepository(db)
    catalog.upsert_product(
        seller_user_id="app-phone-933333333333",
        subject="AC repair",
        category_tag="home service",
        service_area="Vijayawada",
    )
    repo = SellerProfileRepository(db)
    profile = repo.get("app-phone-933333333333")
    assert profile["total_listing_count"] == 1
    assert profile["is_service_provider"] == 1
    assert profile["tier"] == TIER_SERVICE_PROVIDER


def test_backfill_does_not_double_count_exact_listing_updates(tmp_path):
    db = str(tmp_path / "test.db")
    catalog = ProductCatalogRepository(db)
    catalog.upsert_product(
        seller_user_id="app-phone-944444444444",
        subject="Mango pickle",
        price=100,
    )
    repo = SellerProfileRepository(db)
    assert repo.get("app-phone-944444444444")["total_listing_count"] == 1
    catalog.upsert_product(
        seller_user_id="app-phone-944444444444",
        subject="Mango pickle",
        price=120,
    )
    repo.backfill_from_catalog()
    assert repo.get("app-phone-944444444444")["total_listing_count"] == 1
