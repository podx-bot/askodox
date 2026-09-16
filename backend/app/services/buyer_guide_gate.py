"""Decide when the in-app assistant should attach a real buying-guide payload.

Added 2026-09-16 (round 9, roadmap Phase 1: "Reconnect what already works").

BuyerIntelligenceService.build_buying_guide() is a real, already-tested
service (Master Architecture / 14-point-spec Point 6, "buyer decision
assistant") that was built for the WhatsApp chat pipeline and is never called
from the in-app assistant path (backend/app/api/routes/in_app_assistant.py)
that real users actually use today -- the WhatsApp pipeline it *was* wired
into was deliberately cut off from ordinary users by an earlier, unrelated
support-only gate. This is not a missing feature; it is a disconnected one.

This module decides *when* to attach it: only for a genuine buy-side
PRODUCT/FOOD message with a known subject. The offering/requesting phrase and
action-hint rules below are a deliberate mirror of
lib/features/home/domain/semantic_deal_input.dart's `_isOfferingSide` (kept
in sync by hand, same as round 7's regex mirroring) so a seller's own
"selling my old car" message never also gets a buyer's guide -- the backend
and the Flutter app always agree on which side of the deal a message is on.

Kept dependency-free (no FastAPI/pydantic import) on purpose, following
order_contact_visibility.py's round-8 precedent, so it can be unit-tested
directly in any environment, including one where FastAPI/pydantic are not
installable.
"""
from __future__ import annotations

BUYING_GUIDE_DOMAINS = {"PRODUCT", "FOOD"}

_OFFERING_ACTION_HINTS = (
    "sell",
    "list_product",
    "list_item",
    "list_my",
    "create_listing",
    "add_listing",
    "add_product",
    "publish_listing",
    "publish_product",
    "offer_product",
    "offer_service",
    "offer_ride",
    "provide_service",
    "become_seller",
    "register_seller",
)

_REQUESTING_ACTION_HINTS = ("buy", "purchase", "order", "need_", "find_", "search_", "request_")

_OFFERING_PHRASES = (
    "i want to sell",
    "want to sell",
    "i want sell",
    "i wanna sell",
    "looking to sell",
    "need to sell",
    "planning to sell",
    "for sale",
    "i am selling",
    "i m selling",
    "selling my",
    "sell my",
    "sell some",
    "list my",
    "listing my",
    "i have to sell",
    "i offer",
    "we offer",
    "i provide",
    "we provide",
    "offer service",
    "provide service",
    "service provider",
    "seats available",
    "ride available",
    "carpool available",
    "offer ride",
    "అమ్మాలి",
    "అమ్మకం",
    "అమ్ముతున్నాను",
    "అమ్మాలనుకుంటున్నాను",
    "నేను అమ్ముతున్నా",
)


def _is_offering_side(message: str, action: str) -> bool:
    """Mirrors semantic_deal_input.dart's `_isOfferingSide` exactly."""
    clean_action = str(action or "").strip().lower()
    if clean_action:
        if any(hint in clean_action for hint in _OFFERING_ACTION_HINTS):
            return True
        if any(hint in clean_action for hint in _REQUESTING_ACTION_HINTS):
            return False

    text = str(message or "").strip().lower()
    if not text:
        return False
    return any(phrase in text for phrase in _OFFERING_PHRASES)


def wants_buying_guide(*, domain: str, action: str, message: str, subject: str | None) -> bool:
    """True when the in-app assistant should attach a real buying guide.

    Requires a buy-side (not selling) PRODUCT/FOOD message with a known
    `subject` entity already extracted by the AI, so the guide is always
    concrete ("buying a used car") rather than a generic questionnaire with
    nothing to anchor it.
    """
    clean_domain = str(domain or "").strip().upper()
    if clean_domain not in BUYING_GUIDE_DOMAINS:
        return False
    if not subject or not str(subject).strip():
        return False
    return not _is_offering_side(message, action)
