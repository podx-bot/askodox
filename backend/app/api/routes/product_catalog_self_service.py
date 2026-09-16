"""Real self-service listing creation -- an ordinary app user, not just the
admin-key-gated bootstrap form, can make their own item real and searchable.

Added 2026-09-15 (round 5). Before this, the ONLY way a listing reached the
real `seller_products` table (the one `/api/products/search` actually reads
from) was the `/admin/products/new` web form, which only this project's
developer has the key for -- an ordinary person saying "I want to sell
mango pickle" in the app's own chat never reached this table at all (see
docs/ASKODOX_EXECUTION_TRACKER.md, round 4 finding). This endpoint writes
into the exact same `seller_products` table via the exact same
`ProductCatalogRepository.upsert_product()` used by the admin form, so
search/matching code needs no changes -- only the entry point (a JSON API
gated by a real "app-" user id, per the same convention already used for
/deals and /api/orders) is new.

This intentionally does not add any new moderation/review step -- same
bootstrap-stage tradeoff already accepted for the real /deals endpoints
elsewhere in this codebase. A spam/abuse review pass is future work, not
part of this round.

Identity: 2026-09-16 (round 12) -- this endpoint used to trust whatever
seller_user_id the client sent with zero proof: exactly the same
identity-spoofing gap that the 2026-09-16 full repository audit found and
round 10 fixed in orders.py. It is fixed here the same way -- every
request now re-derives who is really calling from the signed session
token issued at OTP-verify time (see session_tokens.py, onboarding_auth.py),
and a client-supplied seller_user_id is only ever checked against that
proven identity, never trusted alone. in_app_deal.py and universal_deals.py
still have the same `_app_user` pattern and are intentionally not fixed in
this round -- see the round-12 tracker entry in
docs/ASKODOX_EXECUTION_TRACKER.md for why.

Seller tiers: 2026-09-16 (round 12) -- roadmap Phase 2 ("Seller tiers &
verification foundation": https://claude.ai/artifact/TWUnjbA2TTubwczT9Lxg4n).
Every successful listing now updates a per-seller profile (see
seller_profile_repository.py) tracking how many listings this seller has
created and whether any of them carries a GSTIN, and classifies the seller
into a tier (see seller_tiers.py) from those two facts. This is a
foundation only -- nothing yet reads or acts on the tier (no different
treatment in search/matching, no dedicated seller-facing UI for it); that
is future work tracked in the roadmap.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services.session_tokens import verify_token

router = APIRouter(prefix="/api/products", tags=["product-self-service"])


def _authenticated_app_user(request: Request) -> str:
    """Return the app_user_id proven by this request's bearer token.

    Added 2026-09-16 (round 12), mirroring orders.py's helper of the same
    name (round 10). Raises 401 if no token was sent, or if the token is
    missing/malformed/expired/forged -- see session_tokens.py for exactly
    what "forged" catches (wrong secret, tampered payload, wrong
    signature). This is now the only source of truth for identity on every
    route below; a client-supplied seller_user_id field is only ever
    checked against this, never trusted on its own.
    """
    container: Any = request.app.state.container
    header = request.headers.get("authorization") or request.headers.get("Authorization") or ""
    token = header[7:].strip() if header.lower().startswith("bearer ") else ""
    if not token:
        raise HTTPException(status_code=401, detail="Sign in required -- no session token was sent")
    user_id = verify_token(token, container.settings.session_token_secret)
    if not user_id:
        raise HTTPException(status_code=401, detail="Session expired or invalid -- please sign in again")
    return user_id


def _matching_app_user(claimed_value: str, authenticated_user_id: str) -> str:
    """Reconcile a client-supplied identity field with the token-proven one.

    Mirrors orders.py's helper of the same name (round 10). The
    client-supplied field is kept (rather than dropped) so an
    already-deployed app build's request body shape keeps working
    unchanged -- it is simply no longer trusted by itself. A blank claimed
    value (an older or simplified client that stops sending it) is fine
    and just uses the authenticated identity outright. A non-blank value
    that disagrees with the token is rejected outright.
    """
    claimed = str(claimed_value or "").strip()
    if claimed and claimed != authenticated_user_id:
        raise HTTPException(status_code=403, detail="This session is not signed in as that user")
    return authenticated_user_id


class CreateMyListingRequest(BaseModel):
    seller_user_id: str = Field(min_length=1)
    subject: str = Field(min_length=1, max_length=200)
    seller_name: str | None = None
    variant: str | None = None
    price: float | None = None
    unit: str | None = None
    stock_status: str = "UNKNOWN"
    location_label: str | None = None
    contact_phone: str | None = None
    category_tag: str | None = None
    service_area: str | None = None
    working_hours: str | None = None
    precise_location: str | None = None
    cancellation_policy: str | None = None
    payout_reference: str | None = None
    # Added 2026-09-16 (round 12) for seller-tier classification -- see
    # seller_tiers.py. Optional and never required: most sellers will not
    # have one, and that is fine, they just stay "casual"/"regular"
    # instead of "business".
    gstin: str | None = None


class MyListingResponse(BaseModel):
    id: int
    seller_tier: str


class MyListingsResponse(BaseModel):
    items: list[dict]
    seller_tier: str | None = None


@router.post("/mine", response_model=MyListingResponse)
def create_my_listing(payload: CreateMyListingRequest, request: Request) -> MyListingResponse:
    container: Any = request.app.state.container
    seller_user_id = _matching_app_user(payload.seller_user_id, _authenticated_app_user(request))

    subject = payload.subject.strip()
    if not subject:
        raise HTTPException(status_code=422, detail="subject required")

    gstin = (payload.gstin or "").strip() or None

    product_id = container.product_catalog_repository.upsert_product(
        seller_user_id=seller_user_id,
        subject=subject,
        seller_name=(payload.seller_name or "").strip() or None,
        variant=(payload.variant or "").strip() or None,
        price=payload.price,
        unit=(payload.unit or "").strip() or None,
        stock_status=payload.stock_status,
        location_label=(payload.location_label or "").strip() or None,
        contact_phone=(payload.contact_phone or "").strip() or None,
        category_tag=(payload.category_tag or "").strip() or None,
        service_area=(payload.service_area or "").strip() or None,
        working_hours=(payload.working_hours or "").strip() or None,
        precise_location=(payload.precise_location or "").strip() or None,
        cancellation_policy=(payload.cancellation_policy or "").strip() or None,
        payout_reference=(payload.payout_reference or "").strip() or None,
        gstin=gstin,
    )
    profile = container.seller_profile_repository.record_listing_created(
        seller_user_id, has_gstin=bool(gstin)
    )
    return MyListingResponse(id=product_id, seller_tier=profile["tier"])


@router.get("/mine", response_model=MyListingsResponse)
def my_listings(request: Request, seller_user_id: str = "") -> MyListingsResponse:
    container: Any = request.app.state.container
    user_id = _matching_app_user(seller_user_id, _authenticated_app_user(request))
    rows = container.product_catalog_repository.list_active_for_seller(user_id)
    profile = container.seller_profile_repository.get(user_id)
    return MyListingsResponse(items=rows, seller_tier=(profile["tier"] if profile else None))
