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
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/products", tags=["product-self-service"])


def _app_user(value: str) -> str:
    user_id = str(value or "").strip()
    if not user_id.lower().startswith("app-"):
        raise HTTPException(status_code=400, detail="ASKODOX app user_id required")
    return user_id


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


class MyListingResponse(BaseModel):
    id: int


class MyListingsResponse(BaseModel):
    items: list[dict]


@router.post("/mine", response_model=MyListingResponse)
def create_my_listing(payload: CreateMyListingRequest, request: Request) -> MyListingResponse:
    container: Any = request.app.state.container
    seller_user_id = _app_user(payload.seller_user_id)

    subject = payload.subject.strip()
    if not subject:
        raise HTTPException(status_code=422, detail="subject required")

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
    )
    return MyListingResponse(id=product_id)


@router.get("/mine", response_model=MyListingsResponse)
def my_listings(request: Request, seller_user_id: str = "") -> MyListingsResponse:
    container: Any = request.app.state.container
    user_id = _app_user(seller_user_id)
    rows = container.product_catalog_repository.list_active_for_seller(user_id)
    return MyListingsResponse(items=rows)