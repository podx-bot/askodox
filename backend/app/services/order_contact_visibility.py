"""Decide when an order's counterpart contact details may be shown.

Added 2026-09-16 (round 8). ASKODOX's own Master Architecture Point 13
requires "contact details are not shared before both parties accept" -- but
buyer_user_id/seller_user_id are literally the other side's phone number
(e.g. "app-phone-919876543210", see lib/core/auth/auth_controller.dart),
and the order API was returning both, in every status, including the
instant a buyer merely requests an item nobody has agreed to yet.

Live testing of the round 5/7 order flow (a buyer requesting a used car)
is what surfaced this: a one-tap "order" with no negotiation step is the
wrong model for anything that needs a look, a question, or a price
discussion first, and freely handing out phone numbers before either side
has agreed compounds that problem. This module is the fix for the contact
side of it; app/api/routes/orders.py's Accept/Decline plumbing and the
Flutter "Send request" relabelling are the rest.

Kept dependency-free (no FastAPI/pydantic import) on purpose, so the rule
can be unit-tested directly in any environment, including one where
FastAPI/pydantic are not installable.
"""
from __future__ import annotations

from typing import Any

CONTACT_VISIBLE_STATUSES = {"ACCEPTED", "FULFILLED"}


def mask_contact_for_viewer(row: dict[str, Any], *, viewer: str) -> dict[str, Any]:
    """Return a copy of `row` with the *other* party's id withheld pre-accept.

    `viewer` is "buyer" or "seller": a buyer never needs their own id
    withheld from themselves, only the seller's contact info before
    acceptance -- and vice versa for a seller looking at incoming requests.
    Any other `viewer` value is treated as untrusted and gets both sides
    masked, rather than silently leaking contact details by default.
    """
    data = dict(row)
    visible = str(data.get("status") or "").upper() in CONTACT_VISIBLE_STATUSES
    if not visible:
        if viewer == "buyer":
            data["seller_user_id"] = ""
        elif viewer == "seller":
            data["buyer_user_id"] = ""
        else:
            data["seller_user_id"] = ""
            data["buyer_user_id"] = ""
    return data
