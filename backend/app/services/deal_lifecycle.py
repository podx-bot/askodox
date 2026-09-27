"""Universal ASKODOX deal lifecycle (orders, bookings, requests).

One state machine for every category, with category-aware execution
sub-states: products move through preparation/dispatch/delivery, services
through scheduling/arrival/work. A seller/provider marking the work done
never closes the deal -- the customer confirms (or reports a problem), and
a dispute blocks closing until support resolves it.

Dependency-free on purpose (like order_contact_visibility.py) so the rules
can be unit-tested anywhere.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

PRODUCT, SERVICE = "product", "service"

PLACED, ACCEPTED, REJECTED, CANCELLED = "PLACED", "ACCEPTED", "REJECTED", "CANCELLED"
DISPUTED, RESOLVED, CLOSED = "DISPUTED", "RESOLVED", "CLOSED"
FULFILLED = "FULFILLED"  # legacy "seller says done": awaits customer confirmation

PRODUCT_STEPS = ("PREPARING", "READY", "DISPATCHED", "DELIVERED")
SERVICE_STEPS = ("SCHEDULED", "PROVIDER_ASSIGNED", "ARRIVED", "IN_PROGRESS", "SERVICE_COMPLETED")
COMPLETION_STATES = {"DELIVERED", "SERVICE_COMPLETED", FULFILLED, RESOLVED}

ALL_STATUSES = (
    PLACED, ACCEPTED, REJECTED, CANCELLED, FULFILLED, *PRODUCT_STEPS, *SERVICE_STEPS, DISPUTED, RESOLVED, CLOSED,
)
# Contact is shared only once the seller/provider has explicitly accepted
# (round-8 consent rule), and stays shared for the rest of that deal.
CONTACT_VISIBLE = {ACCEPTED, FULFILLED, *PRODUCT_STEPS, *SERVICE_STEPS, DISPUTED, RESOLVED, CLOSED}
OPEN_EXECUTION = {ACCEPTED, *PRODUCT_STEPS, *SERVICE_STEPS}

# Payment: ASKODOX does not move money. States describe the offline/UPI
# payment truthfully; VERIFIED needs the seller's or staff's confirmation.
PAYMENT_STATES = ("NOT_STARTED", "AWAITING_PAYMENT", "PROOF_SUBMITTED", "VERIFIED", "FAILED", "DISPUTED")

MESSAGE_KINDS = ("QUESTION", "ANSWER", "OFFER", "COUNTER_OFFER", "ACCEPT_OFFER", "DECLINE_OFFER", "NOTE")
SELLER_RESPONSE_HOURS = 24


class LifecycleError(ValueError):
    """An action that is not allowed in the deal's current state."""


def kind_for(listing: dict[str, Any] | None, seller_profile: dict[str, Any] | None = None) -> str:
    listing = listing or {}
    profile = seller_profile or {}
    tag = " ".join(str(listing.get(k) or "") for k in ("category_tag", "subject", "unit")).lower()
    if profile.get("is_service_provider") or profile.get("tier") == "service_provider":
        return SERVICE
    if any(word in tag for word in ("service", "repair", "install", "booking", "visit", "per hour", "hour")):
        return SERVICE
    return PRODUCT


def steps_for(kind: str) -> tuple[str, ...]:
    return SERVICE_STEPS if kind == SERVICE else PRODUCT_STEPS


def seller_next(status: str, kind: str) -> tuple[str, ...]:
    """Statuses the seller/provider may set next (forward-only)."""
    status = str(status or "").upper()
    steps = steps_for(kind)
    if status == PLACED:
        return (ACCEPTED, REJECTED)
    if status == ACCEPTED:
        return steps
    if status in steps:
        return steps[steps.index(status) + 1:]
    return ()


def check_seller_transition(status: str, target: str, kind: str) -> str:
    target = str(target or "").upper()
    if target == FULFILLED:  # legacy clients: "done" == the kind's completion step
        target = steps_for(kind)[-1]
    if target not in seller_next(status, kind):
        raise LifecycleError(f"A {kind} deal in {status} cannot move to {target}")
    return target


def check_buyer_cancel(status: str) -> None:
    if str(status).upper() != PLACED:
        raise LifecycleError("Only a request the seller has not accepted yet can be cancelled")


def check_customer_confirm(status: str) -> None:
    status = str(status).upper()
    if status == DISPUTED:
        raise LifecycleError("This deal has an open problem; it closes after support resolves it")
    if status not in COMPLETION_STATES:
        raise LifecycleError("The seller/provider has not marked this as delivered/completed yet")


def check_problem(status: str) -> None:
    status = str(status).upper()
    if status not in OPEN_EXECUTION | COMPLETION_STATES:
        raise LifecycleError("A problem can be reported once the request is accepted and before it is closed")


def payment_after_accept(price: Any) -> str:
    return "AWAITING_PAYMENT" if price not in (None, "", 0) else "NOT_STARTED"


def awaiting(order: dict[str, Any], messages: list[dict[str, Any]] | None = None) -> str:
    """Who must act next: seller | buyer | support | none."""
    status = str(order.get("status") or "").upper()
    last = (messages or [])[-1] if messages else None
    if status == DISPUTED:
        return "support"
    if status in {REJECTED, CANCELLED, CLOSED}:
        return "none"
    if last and last.get("kind") in {"QUESTION", "OFFER"} and last.get("from_role") == "buyer":
        return "seller"
    if last and last.get("kind") == "COUNTER_OFFER" and last.get("from_role") == "seller":
        return "buyer"
    if status in COMPLETION_STATES:
        return "buyer"
    if status == PLACED or status in OPEN_EXECUTION:
        return "seller"
    return "none"


def seller_unresponsive(order: dict[str, Any], messages: list[dict[str, Any]] | None = None,
                        now: datetime | None = None) -> bool:
    """True when the seller has owed a response for SELLER_RESPONSE_HOURS."""
    if awaiting(order, messages) != "seller":
        return False
    last = (messages or [])[-1] if messages else None
    since = str((last or {}).get("created_at") or order.get("updated_at") or order.get("created_at") or "")
    try:
        started = datetime.fromisoformat(since)
    except ValueError:
        return False
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    return (now or datetime.now(timezone.utc)) - started > timedelta(hours=SELLER_RESPONSE_HOURS)


def buyer_actions(order: dict[str, Any], messages: list[dict[str, Any]] | None = None) -> list[str]:
    status = str(order.get("status") or "").upper()
    actions = []
    if status == PLACED:
        actions += ["ask_seller", "offer_price", "cancel"]
    if status in OPEN_EXECUTION:
        actions += ["ask_seller", "report_problem"]
    if status in OPEN_EXECUTION and order.get("payment_state") in {"AWAITING_PAYMENT", "FAILED"}:
        actions.append("submit_payment_reference")
    if status in COMPLETION_STATES:
        actions += ["confirm_completion", "report_problem"]
    if messages and messages[-1].get("kind") == "COUNTER_OFFER" and status in {PLACED, ACCEPTED}:
        actions += ["accept_offer", "decline_offer"]
    if status == CLOSED:
        actions.append("review")
    if status == REJECTED:
        actions.append("see_alternatives")
    if seller_unresponsive(order, messages):
        actions.append("contact_support")
    return list(dict.fromkeys(actions))


def seller_actions(order: dict[str, Any], messages: list[dict[str, Any]] | None = None) -> list[str]:
    status = str(order.get("status") or "").upper()
    kind = str(order.get("kind") or PRODUCT)
    actions = [f"status:{s}" for s in seller_next(status, kind)]
    if status in {PLACED} | OPEN_EXECUTION:
        actions += ["answer", "counter_offer"]
    if messages and messages[-1].get("kind") == "OFFER" and status in {PLACED, ACCEPTED}:
        actions += ["accept_offer", "decline_offer"]
    if order.get("payment_state") == "PROOF_SUBMITTED":
        actions += ["confirm_payment_received", "payment_not_received"]
    return actions
