"""Pure, dependency-free seller-tier classification logic."""
from __future__ import annotations

TIER_CASUAL = "casual"
TIER_REGULAR = "regular"
TIER_BUSINESS = "business"
TIER_SERVICE_PROVIDER = "service_provider"

VALID_TIERS = (
    TIER_CASUAL,
    TIER_REGULAR,
    TIER_BUSINESS,
    TIER_SERVICE_PROVIDER,
)

REGULAR_LISTING_THRESHOLD = 5


def compute_tier(
    total_listing_count: int,
    has_gstin: bool,
    is_service_provider: bool = False,
) -> str:
    """Classify a seller from durable facts recorded about the account.

    Registered businesses take precedence. A seller with a real service
    signal is classified as a service provider; otherwise listing volume
    separates regular from casual sellers.
    """
    count = max(0, int(total_listing_count or 0))
    if has_gstin:
        return TIER_BUSINESS
    if is_service_provider:
        return TIER_SERVICE_PROVIDER
    if count >= REGULAR_LISTING_THRESHOLD:
        return TIER_REGULAR
    return TIER_CASUAL
