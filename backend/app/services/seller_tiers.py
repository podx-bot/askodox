"""Pure, dependency-free seller-tier classification logic.

Added 2026-09-16 (round 12) -- roadmap Phase 2 ("Seller tiers & verification
foundation": https://claude.ai/artifact/TWUnjbA2TTubwczT9Lxg4n). This is the
first slice of that phase: a real notion of a seller's tier, computed from
facts already available today (how many self-service listings they have
ever created, and whether any of those listings carries a GSTIN) rather
than a manual admin decision.

Deliberately small and dependency-free (no fastapi/pydantic import) so it
can be unit tested directly -- the same pattern already used for
session_tokens.py (round 10) and buyer_guide_gate.py (round 9/11).

Explicitly out of scope for this round (see docs/ASKODOX_EXECUTION_TRACKER.md,
round 12 entry, for the full reasoning):
  - A "service_provider" tier -- needs category-based detection, not just
    listing count/GSTIN, and ASKODOX does not yet have a reliable signal
    for "this seller is really a service provider" separate from an
    ordinary goods seller.
  - Any duplicate/spam-listing detection -- a distinct problem from tiering,
    deferred to its own future round.
  - PAN / id_verification_status are not read here -- GSTIN alone is used
    for the "business" classification, since it is the one identifier a
    real registered business is most likely to already have and supply,
    matching the seller-research summary already in this codebase (see
    product_catalog_repository.py's _ADDED_COLUMNS comment).
"""
from __future__ import annotations

TIER_CASUAL = "casual"
TIER_REGULAR = "regular"
TIER_BUSINESS = "business"

VALID_TIERS = (TIER_CASUAL, TIER_REGULAR, TIER_BUSINESS)

# A seller who has published at least this many self-service listings is no
# longer "just trying it once" -- see the round-12 tracker entry for why 5
# was chosen (small enough to reach quickly, large enough that a single
# test listing does not upgrade someone).
REGULAR_LISTING_THRESHOLD = 5


def compute_tier(total_listing_count: int, has_gstin: bool) -> str:
    """Classify a seller from facts already recorded about them.

    A GSTIN on file always means "business", regardless of listing count --
    a real registered business does not need to prove itself by volume
    first. Otherwise tier is purely a function of how many listings this
    seller has ever created via the self-service endpoint: fewer than
    REGULAR_LISTING_THRESHOLD is "casual", at or above it is "regular".

    total_listing_count is clamped at 0 (a negative value should never
    legitimately occur, but this keeps the function total rather than
    raising on bad input from a caller).
    """
    count = max(0, int(total_listing_count or 0))
    if has_gstin:
        return TIER_BUSINESS
    if count >= REGULAR_LISTING_THRESHOLD:
        return TIER_REGULAR
    return TIER_CASUAL
