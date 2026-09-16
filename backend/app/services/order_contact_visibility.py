from __future__ import annotations

from typing import Any

CONTACT_VISIBLE_STATUSES = {"ACCEPTED", "FULFILLED"}


def mask_contact_for_viewer(row: dict[str, Any] | None, viewer_user_id: str | None) -> dict[str, Any]:
    """Return a copy of the order row with only the viewer's own contact visible.

    Before the seller has explicitly accepted the order, the counterpart's
    identity must be hidden. Once the order status is ACCEPTED or FULFILLED,
    the counterpart's app-phone ID becomes visible to the matching viewer.
    Untrusted or unrelated viewers see neither side.
    """
    if not row:
        return {}

    masked = dict(row)
    buyer_user_id = str(row.get("buyer_user_id") or "").strip()
    seller_user_id = str(row.get("seller_user_id") or "").strip()
    viewer = str(viewer_user_id or "").strip()
    status = str(row.get("status") or "").strip().upper()

    if viewer in {buyer_user_id, seller_user_id} and status in CONTACT_VISIBLE_STATUSES:
        return masked

    if viewer not in {buyer_user_id, seller_user_id}:
        masked["buyer_user_id"] = ""
        masked["seller_user_id"] = ""
        return masked

    if viewer == buyer_user_id:
        masked["seller_user_id"] = ""
    elif viewer == seller_user_id:
        masked["buyer_user_id"] = ""
    else:
        masked["buyer_user_id"] = ""
        masked["seller_user_id"] = ""

    return masked
