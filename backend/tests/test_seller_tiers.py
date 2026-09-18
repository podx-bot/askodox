from app.services.seller_tiers import (
    REGULAR_LISTING_THRESHOLD,
    TIER_BUSINESS,
    TIER_CASUAL,
    TIER_REGULAR,
    TIER_SERVICE_PROVIDER,
    compute_tier,
)


def test_new_seller_with_no_listings_is_casual():
    assert compute_tier(0, has_gstin=False) == TIER_CASUAL


def test_seller_just_below_the_regular_threshold_is_still_casual():
    assert compute_tier(REGULAR_LISTING_THRESHOLD - 1, has_gstin=False) == TIER_CASUAL


def test_seller_at_the_regular_threshold_is_regular():
    assert compute_tier(REGULAR_LISTING_THRESHOLD, has_gstin=False) == TIER_REGULAR


def test_seller_well_past_the_regular_threshold_is_still_just_regular():
    assert compute_tier(REGULAR_LISTING_THRESHOLD + 50, has_gstin=False) == TIER_REGULAR


def test_gstin_means_business_even_with_zero_listings():
    assert compute_tier(0, has_gstin=True) == TIER_BUSINESS


def test_gstin_means_business_even_past_the_regular_threshold():
    assert compute_tier(REGULAR_LISTING_THRESHOLD + 50, has_gstin=True) == TIER_BUSINESS


def test_negative_listing_count_is_clamped_to_zero_not_rejected():
    assert compute_tier(-3, has_gstin=False) == TIER_CASUAL


def test_service_signal_means_service_provider_without_gstin():
    assert compute_tier(1, has_gstin=False, is_service_provider=True) == TIER_SERVICE_PROVIDER


def test_gstin_takes_precedence_over_service_provider():
    assert compute_tier(1, has_gstin=True, is_service_provider=True) == TIER_BUSINESS
