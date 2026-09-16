"""Real order placement/tracking against the real seller_products catalog.

Added 2026-09-15 (round 5) so that "place an order" in the app actually
does something: it creates a real, persisted row a seller can see and a
buyer can look back on later. This deliberately covers everything short of
actual payment -- there is still no real payment processing anywhere in
ASKODOX (Master Architecture Point 21); settling payment between buyer and
seller (cash, UPI to the seller's own payout_reference, etc.) still happens
outside the app, same as it always has.

Identity: reuses the exact same "app-" prefixed user id convention already
used by the real /deals endpoints (see universal_deals.py's `_app_user`),
which itself comes from the phone-number-OTP-verified identity already
wired up in the Flutter app (AuthController -> 'app-phone-<digits>'). No
new auth system was introduced for this.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.repositories.order_repository import VALID_STATUSES
from app.services.order_contact_visibility import mask_contact_for_viewer

router = APIRouter(prefix="/api/orders", tags=["orders"])


def _app_user(value: str) -> str:
    user_id = str(value or "").strip()
    if not user_id.lower().startswith("app-"):
        raise HTTPException(status_code=400, detail="ASKODOX app user_id required")
    return user_id


class PlaceOrderRequest(BaseModel):
    buyer_user_id: str = Field(min_length=1)
    product_id: int
    quantity: float | None = None
    buyer_note: str | None = None


class OrderResponse(BaseModel):
    id: int
    buyer_user_id: str
    seller_user_id: str
    product_id: int
    product_title: str
    quantity: float | None = None
    unit: str | None = None
    price: float | None = None
    currency: str = "INR"
    total_amount: float | None = None
    status: str
    buyer_note: str | None = None
    seller_note: str | None = None
    created_at: str
    updated_at: str


class OrderListResponse(BaseModel):
    items: list[OrderResponse]


class UpdateOrderStatusRequest(BaseModel):
    seller_user_id: str = Field(min_length=1)
    status: str = Field(min_length=1)
    seller_note: str | None = None


# Added 2026-09-16 (round 8): see order_contact_visibility.py for why this
# masking exists. Contact (phone number) is withheld from each party until
# both have agreed -- i.e. until the order is ACCEPTED (or later,
# FULFILLED).
def _to_response(row: dict[str, Any], *, viewer: str) -> OrderResponse:
    return OrderResponse(**mask_contact_for_viewer(row, viewer=viewer))


@router.post("", response_model=OrderResponse)
def place_order(payload: PlaceOrderRequest, request: Request) -> OrderResponse:
    container: Any = request.app.state.container
    buyer_user_id = _app_user(payload.buyer_user_id)

    product = container.product_catalog_repository.get(payload.product_id)
    if not product or not product.get("active", True):
        raise HTTPException(status_code=404, detail="This listing is no longer available")

    seller_user_id = str(product.get("seller_user_id") or "").strip()
    if not seller_user_id:
        raise HTTPException(status_code=409, detail="This listing has no seller on record")

    variant = str(product.get("variant") or "").strip()
    subject = str(product.get("subject") or "").strip()
    title = f"{subject} -- {variant}" if variant else subject

    order_id = container.order_repository.create_order(
        buyer_user_id=buyer_user_id,
        seller_user_id=seller_user_id,
        product_id=int(payload.product_id),
        product_title=title or f"Product #{payload.product_id}",
        quantity=payload.quantity,
        unit=(str(product.get("unit")).strip() or None) if product.get("unit") else None,
        price=(float(product["price"]) if product.get("price") is not None else None),
        currency=str(product.get("currency") or "INR"),
        buyer_note=payload.buyer_note,
    )
    order = container.order_repository.get(order_id)
    if not order:
        raise HTTPException(status_code=500, detail="Order was not saved")
    return _to_response(order, viewer="buyer")


@router.get("/mine", response_model=OrderListResponse)
def my_orders(request: Request, buyer_user_id: str = "", limit: int = 50) -> OrderListResponse:
    container: Any = request.app.state.container
    user_id = _app_user(buyer_user_id)
    rows = container.order_repository.list_for_buyer(user_id, limit=limit)
    return OrderListResponse(items=[_to_response(row, viewer="buyer") for row in rows])


@router.get("/incoming", response_model=OrderListResponse)
def incoming_orders(request: Request, seller_user_id: str = "", limit: int = 50) -> OrderListResponse:
    container: Any = request.app.state.container
    user_id = _app_user(seller_user_id)
    rows = container.order_repository.list_for_seller(user_id, limit=limit)
    return OrderListResponse(items=[_to_response(row, viewer="seller") for row in rows])


@router.post("/{order_id}/status", response_model=OrderResponse)
def update_order_status(order_id: int, payload: UpdateOrderStatusRequest, request: Request) -> OrderResponse:
    container: Any = request.app.state.container
    seller_user_id = _app_user(payload.seller_user_id)

    order = container.order_repository.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if str(order.get("seller_user_id") or "") != seller_user_id:
        # 404 rather than 403 so this endpoint doesn't confirm/deny which
        # orders exist to a user who isn't the seller on them.
        raise HTTPException(status_code=404, detail="Order not found")

    clean_status = payload.status.strip().upper()
    if clean_status not in VALID_STATUSES:
        raise HTTPException(status_code=422, detail=f"status must be one of {', '.join(VALID_STATUSES)}")

    container.order_repository.update_status(order_id, clean_status, seller_note=payload.seller_note)
    updated = container.order_repository.get(order_id)
    return _to_response(updated, viewer="seller")
