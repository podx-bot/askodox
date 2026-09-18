"""Real order placement/tracking against the real seller_products catalog.

Added 2026-09-15 (round 5) so that "place an order" in the app actually
does something: it creates a real, persisted row a seller can see and a
buyer can look back on later. This deliberately covers everything short of
actual payment -- there is still no real payment processing anywhere in
ASKODOX (Master Architecture Point 21); settling payment between buyer and
seller (cash, UPI to the seller's own payout_reference, etc.) still happens
outside the app, same as it always has.

Identity: 2026-09-16 (round 10) -- the "app-phone-<digits>" convention
described below is now only ever *proposed* by the client; every endpoint
here re-derives who is really calling from a signed session token (see
session_tokens.py) issued at OTP-verify time (onboarding_auth.py), and
rejects the request if the client's proposed id does not match it. Before
this round, every endpoint below simply trusted whatever buyer_user_id/
seller_user_id the client sent with zero proof -- the full repository audit
(2026-09-16) flagged this as a critical identity-spoofing gap, since these
ids are literally the other party's phone number once an order is accepted
(see order_contact_visibility.py) and this endpoint also gates who can
accept/reject someone else's order. universal_deals.py's own `_app_user`
still has the same gap and is intentionally not fixed in this round -- see
the round-10 tracker entry in docs/ASKODOX_EXECUTION_TRACKER.md for why.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.repositories.order_repository import VALID_STATUSES
from app.services.order_contact_visibility import mask_contact_for_viewer
from app.services.session_tokens import verify_token

router = APIRouter(prefix="/api/orders", tags=["orders"])


def _authenticated_app_user(request: Request) -> str:
    """Return the app_user_id proven by this request's bearer token.

    Added 2026-09-16 (round 10). Raises 401 if no token was sent, or if the
    token is missing/malformed/expired/forged -- see session_tokens.py for
    exactly what "forged" catches (wrong secret, tampered payload, wrong
    signature). This is now the *only* source of truth for identity on
    every route below; a client-supplied buyer_user_id/seller_user_id field
    is only ever checked against this, never trusted on its own.
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

    The client-supplied field is kept (rather than dropped) so an already
    -deployed app build's request body shape keeps working unchanged -- it
    is simply no longer trusted by itself. A blank claimed value (an older
    or simplified client that stops sending it) is fine and just uses the
    authenticated identity outright. A non-blank value that disagrees with
    the token is rejected outright: that only happens if a client is
    confused about who is signed in, or is actively trying to act as
    someone else, and either way the token-proven identity is what should
    be trusted, not the claim.
    """
    claimed = str(claimed_value or "").strip()
    if claimed and claimed != authenticated_user_id:
        raise HTTPException(status_code=403, detail="This session is not signed in as that user")
    return authenticated_user_id


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
    buyer_user_id = _matching_app_user(payload.buyer_user_id, _authenticated_app_user(request))

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
    user_id = _matching_app_user(buyer_user_id, _authenticated_app_user(request))
    rows = container.order_repository.list_for_buyer(user_id, limit=limit)
    return OrderListResponse(items=[_to_response(row, viewer="buyer") for row in rows])


@router.get("/incoming", response_model=OrderListResponse)
def incoming_orders(request: Request, seller_user_id: str = "", limit: int = 50) -> OrderListResponse:
    container: Any = request.app.state.container
    user_id = _matching_app_user(seller_user_id, _authenticated_app_user(request))
    rows = container.order_repository.list_for_seller(user_id, limit=limit)
    return OrderListResponse(items=[_to_response(row, viewer="seller") for row in rows])


@router.post("/{order_id}/status", response_model=OrderResponse)
def update_order_status(order_id: int, payload: UpdateOrderStatusRequest, request: Request) -> OrderResponse:
    container: Any = request.app.state.container
    seller_user_id = _matching_app_user(payload.seller_user_id, _authenticated_app_user(request))

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
