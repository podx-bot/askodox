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

import json

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.repositories.command_center_repository import mask_user_id
from app.repositories.order_repository import VALID_STATUSES
from app.services import deal_lifecycle as lifecycle
from app.services import payment_gateway
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
    # Structured requirement from the conversation (category, specs, budget,
    # date/time...) so the seller never asks the customer to repeat it.
    request_context: dict[str, Any] | None = None
    # Optional first question for the seller (stock, final price, delivery).
    question: str | None = Field(default=None, max_length=2000)
    # COD / CASH_ON_PICKUP / DIRECT_CASH / DIRECT_UPI (GATEWAY later).
    settlement_method: str | None = None
    # Who else added value to this deal (influencer / advisor / referrer /
    # agent / partner / distributor) -- recorded transparently; any reward
    # needs an admin rule and admin approval.
    attribution: list[dict[str, str]] = Field(default_factory=list)
    referral_code: str | None = Field(default=None, max_length=20)


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
    kind: str = "product"
    payment_state: str = "NOT_STARTED"
    payment_reference: str | None = None
    settlement_method: str = "DIRECT_UPI"
    paid_at: str | None = None
    return_reason: str | None = None
    refund_reference: str | None = None
    offer: dict[str, Any] | None = None
    discount: float | None = None
    closed_at: str | None = None
    dispute_escalation_id: int | None = None
    request_context: dict[str, Any] | None = None
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
    try:
        method = lifecycle.settlement_method(payload.settlement_method)
        instruction = payment_gateway.adapter_for(method).instruction({"settlement_method": method})
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

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
        kind=lifecycle.kind_for(product, _seller_profile(container, seller_user_id)),
        request_context=_clean_context(payload.request_context),
        settlement_method=instruction.method,
    )
    _apply_growth(container, order_id, product, buyer_user_id, seller_user_id, payload)
    if payload.question and payload.question.strip():
        container.order_repository.add_message(order_id, "buyer", "QUESTION", payload.question)
    order = container.order_repository.get(order_id)
    _trace_order(container, order, "request_sent",
                 offer=(order or {}).get("offer"), participants=len(_participants(container, order_id)))
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
    try:
        # Forward-only, category-aware; "done" never closes the deal -- the
        # customer confirms (or reports a problem) first.
        target = lifecycle.check_seller_transition(order["status"], clean_status, order.get("kind") or "product")
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    fields: dict[str, Any] = {"status": target}
    if payload.seller_note:
        fields["seller_note"] = payload.seller_note.strip()
    if target == lifecycle.ACCEPTED and order.get("payment_state") in (None, "NOT_STARTED"):
        fields["payment_state"] = lifecycle.payment_after_accept(order.get("total_amount") or order.get("price"))
    container.order_repository.update_fields(order_id, **fields)
    updated = container.order_repository.get(order_id)
    _trace_order(container, updated, f"seller_{target.lower()}")
    return _to_response(updated, viewer="seller")


# ------------------------------------------------ universal deal lifecycle --
# One lifecycle for products and services (deal_lifecycle.py): mediated
# questions and negotiation (no contact exposed), payment state that never
# claims money moved without a confirmation, customer confirmation before
# close, disputes routed to Customer Care with the full context package.


_PUSH_WORDS = {"accepted": "Accepted", "rejected": "Declined", "fulfilled": "Completed", "cancelled": "Cancelled"}


def _push_order_event(container: Any, order: dict[str, Any] | None, stage: str) -> None:
    """Background push to the OTHER party (silent channel, once per event).
    No-op until FIREBASE_SERVICE_ACCOUNT_JSON is set (push_service.py)."""
    if not order:
        return
    try:
        from app.services.push_service import push_service

        title = str(order.get("product_title") or order.get("subject") or "ASKODOX request")[:80]
        if stage == "request_sent":
            push_service(container).notify_async(
                str(order.get("seller_user_id") or ""), title=title, body="New request -- accept or decline",
                route="/orders/incoming", event_key=f"order:{order['id']}:request")
        elif stage.startswith("seller_"):
            words = _PUSH_WORDS.get(stage.removeprefix("seller_"), stage.removeprefix("seller_").replace("_", " "))
            push_service(container).notify_async(
                str(order.get("buyer_user_id") or ""), title=title, body=words,
                route="/orders/mine", event_key=f"order:{order['id']}:{stage}")
    except Exception:
        pass  # a push never breaks the deal


def _trace_order(container: Any, order: dict[str, Any] | None, stage: str, **fields: Any) -> None:
    """Advance the admin flow trace of the conversation request this deal
    came from (seller request status, deal stage)."""
    _push_order_event(container, order, stage)
    try:
        deal_id = ((order or {}).get("request_context") or {}).get("deal_id")
        if not deal_id:
            return
        from app.api.routes.command_center import command_center

        command_center(container).trace_stage_for_deal(
            deal_id, stage,
            seller_request={"order_id": order["id"], "status": order.get("status"), "kind": order.get("kind"),
                            "payment_state": order.get("payment_state")},
            **fields,
        )
    except Exception:
        pass


def _seller_profile(container: Any, seller_user_id: str) -> dict[str, Any]:
    repo = getattr(container, "seller_profile_repository", None)
    try:
        return dict(repo.get(seller_user_id) or {}) if repo is not None else {}
    except Exception:
        return {}


def _clean_context(context: dict[str, Any] | None) -> dict[str, Any] | None:
    if not context:
        return None
    return {str(k)[:40]: v for k, v in list(context.items())[:30] if v not in (None, "", [], {})}


def _party(container: Any, order_id: int, request: Request) -> tuple[dict[str, Any], str]:
    user_id = _authenticated_app_user(request)
    order = container.order_repository.get(order_id)
    if order and str(order.get("buyer_user_id")) == user_id:
        return order, "buyer"
    if order and str(order.get("seller_user_id")) == user_id:
        return order, "seller"
    raise HTTPException(status_code=404, detail="Order not found")


def _growth(container: Any):
    from app.api.routes.growth import growth

    return growth(container)


def _participants(container: Any, order_id: int) -> list[dict[str, Any]]:
    try:
        return _growth(container).participants("order", order_id)
    except Exception:
        return []


def _apply_growth(container: Any, order_id: int, product: dict[str, Any], buyer: str, seller: str,
                  payload: "PlaceOrderRequest") -> None:
    """Best applicable offer (seller + admin campaigns) and the transaction's
    participants. Never blocks placing the order."""
    from app.repositories.growth_repository import REWARDABLE_ROLES
    from app.services import offers_engine

    try:
        repo = _growth(container)
        order = container.order_repository.get(order_id) or {}
        referral = repo.referral(payload.referral_code) if payload.referral_code else None
        referred = bool(referral and referral["referrer_user_id"] not in {buyer, seller})
        prior = int(next(iter(dict(container.database.fetchall(
            "SELECT COUNT(*) AS n FROM orders WHERE buyer_user_id=? AND seller_user_id=? AND id<>?",
            (buyer, seller, order_id))[0]).values())) or 0)
        best = offers_engine.best_offer(repo.offers_for_listing(product), {
            "unit_price": order.get("price") or 0, "quantity": order.get("quantity") or 1,
            "prior_orders": prior, "referred": referred,
        })
        if best:
            total = float(order.get("total_amount") or 0)
            container.order_repository.update_fields(
                order_id, offer_json=json.dumps(best, ensure_ascii=False), discount=best["discount"],
                total_amount=round(max(0.0, total - best["discount"]), 2) if order.get("total_amount") else None,
            )
        kind = str(order.get("kind") or "product")
        repo.add_participant("order", order_id, buyer, "customer" if kind == "service" else "buyer", added_by=buyer)
        repo.add_participant("order", order_id, seller, "service_provider" if kind == "service" else "seller",
                             added_by=buyer)
        if referred:
            repo.add_participant("order", order_id, referral["referrer_user_id"], "referrer", added_by=buyer)
        for entry in payload.attribution[:5]:
            user, role = str(entry.get("user_id") or "").strip(), str(entry.get("role") or "").strip().lower()
            if role in REWARDABLE_ROLES and user.startswith("app-") and user not in {buyer, seller}:
                repo.add_participant("order", order_id, user, role, added_by=buyer)
    except Exception:
        pass


def _settle_rewards(container: Any, order: dict[str, Any] | None, *, completed: bool, note: str = "") -> None:
    try:
        repo = _growth(container)
        if completed:
            repo.accrue_rewards("order", order["id"], float(order.get("total_amount") or 0))
        else:
            repo.cancel_rewards("order", order["id"], note)
    except Exception:
        pass


def _settlement(order: dict[str, Any]) -> dict[str, Any]:
    try:
        info = payment_gateway.adapter_for(order.get("settlement_method")).instruction(order)
    except lifecycle.LifecycleError:
        return {"method": order.get("settlement_method"), "available": False}
    return {"method": info.method, "payer_action": info.payer_action, "payee_action": info.payee_action,
            "needs_reference": info.needs_reference, "online": info.online, "available": True}


def _detail(container: Any, order: dict[str, Any], role: str) -> dict[str, Any]:
    messages = container.order_repository.messages(order["id"])
    body = _to_response(order, viewer=role).model_dump()
    body.update({
        "messages": messages,
        "awaiting": lifecycle.awaiting(order, messages),
        "seller_unresponsive": lifecycle.seller_unresponsive(order, messages),
        "actions": lifecycle.buyer_actions(order, messages) if role == "buyer" else lifecycle.seller_actions(order, messages),
        "viewer": role,
        "payment_note": "ASKODOX does not process payments; payment is made directly to the seller/provider.",
        "settlement": _settlement(order),
        "participants": [{"role": p["role"], "user": mask_user_id(p["user_id"])}
                         for p in _participants(container, order["id"])],
    })
    return body


@router.get("/{order_id}")
def order_detail(order_id: int, request: Request) -> dict[str, Any]:
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    return _detail(container, order, role)


class OrderMessageRequest(BaseModel):
    kind: str
    text: str | None = Field(default=None, max_length=2000)
    amount: float | None = Field(default=None, gt=0)


_ROLE_KINDS = {
    "buyer": {"QUESTION", "OFFER", "ACCEPT_OFFER", "DECLINE_OFFER", "NOTE"},
    "seller": {"ANSWER", "COUNTER_OFFER", "ACCEPT_OFFER", "DECLINE_OFFER", "NOTE"},
}


@router.post("/{order_id}/messages")
def order_message(order_id: int, payload: OrderMessageRequest, request: Request) -> dict[str, Any]:
    """ASKODOX-mediated buyer <-> seller/provider questions and negotiation."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    kind = payload.kind.strip().upper()
    if kind not in _ROLE_KINDS[role]:
        raise HTTPException(status_code=422, detail=f"A {role} cannot send {kind}")
    if order["status"] in {lifecycle.REJECTED, lifecycle.CANCELLED, lifecycle.CLOSED}:
        raise HTTPException(status_code=409, detail="This deal is no longer open")
    if kind in {"OFFER", "COUNTER_OFFER"} and not payload.amount:
        raise HTTPException(status_code=422, detail="An offer needs an amount")
    if kind in {"QUESTION", "ANSWER", "NOTE"} and not (payload.text or "").strip():
        raise HTTPException(status_code=422, detail="Message text is required")
    messages = container.order_repository.messages(order_id)
    if kind in {"ACCEPT_OFFER", "DECLINE_OFFER"}:
        pending = next((m for m in reversed(messages) if m["kind"] in {"OFFER", "COUNTER_OFFER"}), None)
        if not pending or pending["from_role"] == role or any(
                m["kind"] in {"ACCEPT_OFFER", "DECLINE_OFFER"} and m["id"] > pending["id"] for m in messages):
            raise HTTPException(status_code=409, detail="There is no open offer from the other party")
        if kind == "ACCEPT_OFFER":
            amount = float(pending["amount"])
            total = amount * float(order["quantity"]) if order.get("quantity") else amount
            container.order_repository.update_fields(order_id, price=amount, total_amount=total)
            payload.amount = amount
    container.order_repository.add_message(order_id, role, kind, payload.text or "", payload.amount)
    return _detail(container, container.order_repository.get(order_id), role)


@router.post("/{order_id}/cancel")
def cancel_order(order_id: int, request: Request) -> dict[str, Any]:
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "buyer":
        raise HTTPException(status_code=403, detail="Only the customer can cancel their request")
    try:
        lifecycle.check_buyer_cancel(order["status"])
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    container.order_repository.update_fields(order_id, status=lifecycle.CANCELLED)
    _settle_rewards(container, order, completed=False, note="order cancelled")
    return _detail(container, container.order_repository.get(order_id), role)


class PaymentAction(BaseModel):
    action: str
    reference: str | None = Field(default=None, max_length=120)


@router.post("/{order_id}/payment")
def order_payment(order_id: int, payload: PaymentAction, request: Request) -> dict[str, Any]:
    """Truthful payment state: the customer submits a UPI/UTR reference; only
    the seller/provider (money received) or staff can mark it VERIFIED."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    action = payload.action.strip().lower()
    state = order.get("payment_state") or "NOT_STARTED"
    if role == "buyer" and action == "submit_reference":
        if order["status"] not in lifecycle.OPEN_EXECUTION | lifecycle.COMPLETION_STATES:
            raise HTTPException(status_code=409, detail="Payment is made after the seller/provider accepts")
        reference = (payload.reference or "").strip()
        if len(reference) < 6:
            raise HTTPException(status_code=422, detail="Enter the payment reference (UTR) from your UPI app")
        container.order_repository.update_fields(order_id, payment_state="PROOF_SUBMITTED", payment_reference=reference)
        _notify_admin(container, f"payment_proof:{order_id}", "payment_proof",
                      f"Payment reference submitted for order #{order_id}", order_id)
    elif role == "buyer" and action == "cash_paid":
        # Cash handed over: recorded as the customer's claim until the
        # seller/provider confirms it (never VERIFIED on the payer's word).
        if order.get("settlement_method") not in lifecycle.CASH_METHODS:
            raise HTTPException(status_code=409, detail="This order is not a cash order")
        if order["status"] not in lifecycle.OPEN_EXECUTION | lifecycle.COMPLETION_STATES:
            raise HTTPException(status_code=409, detail="Payment is made after the seller/provider accepts")
        container.order_repository.update_fields(order_id, payment_state="PROOF_SUBMITTED",
                                                 payment_reference="CASH")
    elif role == "seller" and action == "confirm_cash_received":
        if order.get("settlement_method") not in lifecycle.CASH_METHODS:
            raise HTTPException(status_code=409, detail="This order is not a cash order")
        if state not in {"AWAITING_PAYMENT", "PROOF_SUBMITTED"}:
            raise HTTPException(status_code=409, detail="No cash payment is pending for this order")
        from datetime import datetime, timezone

        container.order_repository.update_fields(order_id, payment_state="VERIFIED", payment_verified_by="seller",
                                                 payment_reference=order.get("payment_reference") or "CASH",
                                                 paid_at=datetime.now(timezone.utc).isoformat())
        _trace_order(container, container.order_repository.get(order_id), "payment_confirmed",
                     payment={"method": order.get("settlement_method"), "state": "VERIFIED"})
    elif role == "seller" and action in {"confirm_received", "not_received"}:
        if state != "PROOF_SUBMITTED":
            raise HTTPException(status_code=409, detail="No payment reference is waiting for confirmation")
        container.order_repository.update_fields(
            order_id,
            payment_state="VERIFIED" if action == "confirm_received" else "FAILED",
            payment_verified_by="seller" if action == "confirm_received" else None,
        )
    else:
        raise HTTPException(status_code=422, detail="Unsupported payment action")
    return _detail(container, container.order_repository.get(order_id), role)


class ReturnRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=1000)


@router.post("/{order_id}/return")
def request_return(order_id: int, payload: ReturnRequest, request: Request) -> dict[str, Any]:
    """Customer asks to return a delivered product (before closing)."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "buyer":
        raise HTTPException(status_code=403, detail="Only the customer can request a return")
    try:
        lifecycle.check_return_request(order["status"], order.get("kind"))
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    container.order_repository.update_fields(order_id, status=lifecycle.RETURN_REQUESTED,
                                             return_reason=payload.reason.strip(),
                                             return_from_status=order["status"])
    _trace_order(container, container.order_repository.get(order_id), "return_requested")
    return _detail(container, container.order_repository.get(order_id), role)


class ReturnDecision(BaseModel):
    action: str  # item_received | decline
    note: str | None = Field(default=None, max_length=1000)


@router.post("/{order_id}/return/decision")
def return_decision(order_id: int, payload: ReturnDecision, request: Request) -> dict[str, Any]:
    """Seller records the item came back (-> refund due if paid) or declines
    (the order goes back to delivered; the customer can report a problem)."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "seller":
        raise HTTPException(status_code=403, detail="Only the seller decides a return")
    if order["status"] != lifecycle.RETURN_REQUESTED:
        raise HTTPException(status_code=409, detail="No return is waiting for a decision")
    action = payload.action.strip().lower()
    if action == "item_received":
        target = lifecycle.after_return_received(order.get("payment_state"))
        container.order_repository.update_fields(order_id, status=target)
        _trace_order(container, container.order_repository.get(order_id), target.lower())
    elif action == "decline":
        container.order_repository.update_fields(order_id, status=order.get("return_from_status") or "DELIVERED",
                                                 seller_note=(payload.note or "Return declined").strip())
        _trace_order(container, container.order_repository.get(order_id), "return_declined")
    else:
        raise HTTPException(status_code=422, detail="action must be item_received or decline")
    return _detail(container, container.order_repository.get(order_id), role)


class RefundRecord(BaseModel):
    reference: str = Field(min_length=2, max_length=120)


@router.post("/{order_id}/refund")
def record_refund(order_id: int, payload: RefundRecord, request: Request) -> dict[str, Any]:
    """Seller records the refund they paid (UPI reference or "CASH")."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "seller":
        raise HTTPException(status_code=403, detail="Only the seller records a refund")
    if order["status"] != lifecycle.REFUND_DUE:
        raise HTTPException(status_code=409, detail="No refund is due on this order")
    container.order_repository.update_fields(order_id, status=lifecycle.REFUNDED, payment_state="REFUNDED",
                                             refund_reference=payload.reference.strip())
    _trace_order(container, container.order_repository.get(order_id), "refunded")
    return _detail(container, container.order_repository.get(order_id), role)


@router.post("/{order_id}/confirm")
def confirm_completion(order_id: int, request: Request) -> dict[str, Any]:
    """Customer confirms they received the product / the service was done.
    Only this closes the deal."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "buyer":
        raise HTTPException(status_code=403, detail="Only the customer can confirm completion")
    try:
        lifecycle.check_customer_confirm(order["status"])
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    from datetime import datetime, timezone

    container.order_repository.update_fields(order_id, status=lifecycle.CLOSED,
                                             closed_at=datetime.now(timezone.utc).isoformat())
    closed = container.order_repository.get(order_id)
    # A refunded/returned order earns no reward; a completed one accrues
    # PENDING rewards for value-adding participants (admin approves/pays).
    _settle_rewards(container, closed, completed=order["status"] not in {lifecycle.REFUNDED, lifecycle.RETURNED},
                    note="order returned/refunded")
    _trace_order(container, closed, "deal_closed")
    return _detail(container, container.order_repository.get(order_id), role)


class ProblemRequest(BaseModel):
    issue: str = Field(min_length=3, max_length=2000)
    category: str = "DELIVERY"
    ai_attempts: list[str] = Field(default_factory=list)


@router.post("/{order_id}/problem")
def report_problem(order_id: int, payload: ProblemRequest, request: Request) -> dict[str, Any]:
    """Not received / wrong / damaged / provider didn't come / payment issue:
    the deal is held open (DISPUTED) and Customer Care gets the full context
    package once -- the customer never retells the story."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    try:
        lifecycle.check_problem(order["status"])
    except lifecycle.LifecycleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    category = payload.category.strip().upper() or "DELIVERY"
    messages = container.order_repository.messages(order_id)
    context = order_context_package(order, messages, reason=payload.issue, reported_by=role,
                                    ai_attempts=payload.ai_attempts)
    from app.api.routes.in_app_assistant import _support_repository

    case = _support_repository(container).create(
        _authenticated_app_user(request), payload.issue, category,
        category in {"PAYMENT", "SAFETY", "FRAUD"}, context,
    )
    fields: dict[str, Any] = {"status": lifecycle.DISPUTED, "dispute_from_status": order["status"],
                              "dispute_escalation_id": case.get("id")}
    if category == "PAYMENT":
        fields["payment_state"] = "DISPUTED"
    container.order_repository.update_fields(order_id, **fields)
    _notify_admin(container, f"dispute:order:{order_id}", "dispute", f"{category}: order #{order_id} -- {payload.issue[:60]}",
                  case.get("id"))
    _trace_order(container, container.order_repository.get(order_id), "disputed",
                 escalation={"case_id": case.get("id"), "category": category, "status": "OPEN"})
    return {**_detail(container, container.order_repository.get(order_id), role), "support_case_id": case.get("id")}


def order_context_package(order: dict[str, Any], messages: list[dict[str, Any]], *, reason: str,
                          reported_by: str, ai_attempts: list[str] | None = None) -> dict[str, Any]:
    """Everything Customer Care needs in one place (ids masked)."""
    from app.repositories.command_center_repository import mask_user_id

    return {
        "order_id": order["id"],
        "deal_id": str((order.get("request_context") or {}).get("deal_id") or ""),
        "kind": order.get("kind"),
        "selected": order.get("product_title"),
        "requirement": order.get("request_context") or {},
        "status_before_problem": order.get("status"),
        "payment_state": order.get("payment_state"),
        "price": order.get("price"),
        "quantity": order.get("quantity"),
        "buyer": mask_user_id(order.get("buyer_user_id")),
        "seller": mask_user_id(order.get("seller_user_id")),
        "conversation": [{"role": m["from_role"], "text": f"{m['kind']}: {m.get('text') or ''} {m.get('amount') or ''}".strip()}
                         for m in messages[-30:]],
        "actions_tried": list(ai_attempts or [])[-20:],
        "reported_by": reported_by,
        "problem": reason,
    }


def _notify_admin(container: Any, event_key: str, kind: str, title: str, entity_id: Any) -> None:
    try:
        from app.api.routes.command_center import command_center, feature_enabled

        if feature_enabled(container, "notifications.admin"):
            command_center(container).notify_once(event_key, kind, title, str(entity_id or ""))
    except Exception:
        pass


class OrderReview(BaseModel):
    rating: int = Field(ge=1, le=5)
    text: str = Field(default="", max_length=2000)


@router.post("/{order_id}/review")
def review_order(order_id: int, payload: OrderReview, request: Request) -> dict[str, Any]:
    """Only after a genuinely closed deal; feeds the same trust summary shown
    on match cards (universal_reviews). Keyed by -order_id so order reviews
    never collide with request-level reviews."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "buyer":
        raise HTTPException(status_code=403, detail="Only the customer reviews a deal")
    if order["status"] != lifecycle.CLOSED:
        raise HTTPException(status_code=409, detail="Reviews open after the deal is completed and closed")
    result = container.universal_review_repository.create(
        -int(order_id), order["buyer_user_id"], order["seller_user_id"],
        (order.get("kind") or "product").upper(), payload.rating, payload.text,
    )
    return {"order_id": order_id, **result}


@router.get("/{order_id}/alternatives")
def order_alternatives(order_id: int, request: Request, limit: int = 5) -> dict[str, Any]:
    """After a decline (or no response): other active listings for the same
    need, excluding that seller -- the customer never starts over."""
    container: Any = request.app.state.container
    order, role = _party(container, order_id, request)
    if role != "buyer":
        raise HTTPException(status_code=403, detail="Only the customer can request alternatives")
    subject = str((order.get("request_context") or {}).get("subject") or "").strip()
    if not subject:
        listing = container.product_catalog_repository.get(order["product_id"]) or {}
        subject = str(listing.get("subject") or order["product_title"]).strip()
    items = []
    try:
        rows = container.product_catalog_repository.search_active(subject, limit=30)
    except Exception:
        rows = []
    for row in rows:
        if str(row.get("seller_user_id")) == str(order["seller_user_id"]) or int(row["id"]) == int(order["product_id"]):
            continue
        items.append({
            "id": str(row["id"]), "match_id": str(row["id"]), "provider_id": "",
            "title": " ".join(str(x) for x in (row.get("subject"), row.get("brand"), row.get("variant")) if x),
            "subtitle": str(row.get("location_label") or ""),
            "price": row.get("price"), "source": "local", "match_source": "registered",
            "segment": "registered", "demo": False,
        })
        if len(items) >= max(1, min(limit, 10)):
            break
    return {"order_id": order_id, "subject": subject, "matches": items}
