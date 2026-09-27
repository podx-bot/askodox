"""Broadcast an app need to relevant registered ASKODOX providers (in-app).

Catering staff, a plumber, a TV, a parcel run -- any NEED saved from the app
is offered as an in-app lead to registered app sellers/providers whose own
listing is about that need (and, when both sides say where, in that area).

Reuses the existing lead table (``universal_notifications``, one row per
request+provider, so a re-send never duplicates) and the existing interest
-> requester consent -> deal thread flow. Nothing here messages WhatsApp and
no contact details are exposed: the provider sees the need, never the
requester's phone.

The result is real: ``sent`` is the number of lead rows actually created.
"""
from __future__ import annotations

from typing import Any

from app.services.universal_external_result_service import _tokens, relevant_to

MAX_TARGETS = 25


def _is_app_user(user_id: Any) -> bool:
    return str(user_id or "").strip().casefold().startswith("app-")


def _area_ok(demand_place: str, listing: dict[str, Any]) -> bool:
    """True unless both sides name a place and the places do not overlap."""
    wanted = _tokens(demand_place)
    served = _tokens(" ".join(str(listing.get(k) or "") for k in ("location_label", "service_area")))
    return not wanted or not served or bool(wanted & served)


def candidate_providers(catalog, demand: dict[str, Any], limit: int = MAX_TARGETS) -> list[dict[str, Any]]:
    subject = str(demand.get("subject") or "").strip()
    search = getattr(catalog, "search_active", None)
    if not subject or not callable(search):
        return []
    try:
        rows = search(subject, limit=100) or []
    except Exception:
        return []
    requester = str(demand.get("user_id") or "")
    place = str(demand.get("location_text") or "")
    picked: dict[str, dict[str, Any]] = {}
    for row in rows:
        seller = str(row.get("seller_user_id") or "")
        if not _is_app_user(seller) or seller == requester or seller in picked:
            continue
        listing_text = " ".join(str(row.get(k) or "") for k in ("subject", "brand", "variant", "category_tag"))
        if not relevant_to(subject, listing_text) or not _area_ok(place, row):
            continue
        picked[seller] = {"user_id": seller, "listing_id": row.get("id"), "listing": row.get("subject")}
        if len(picked) >= limit:
            break
    return list(picked.values())


def _lead_message(demand: dict[str, Any]) -> str:
    parts = [str(demand.get("subject") or "a request")]
    if demand.get("quantity"):
        parts.append(f"qty {demand.get('quantity')} {demand.get('unit') or ''}".strip())
    if demand.get("location_text"):
        parts.append(f"in {demand['location_text']}")
    if demand.get("when_text"):
        parts.append(str(demand["when_text"]))
    if demand.get("price"):
        parts.append(f"budget ₹{int(float(demand['price']))}")
    return "New ASKODOX request: " + ", ".join(parts)


def broadcast_need(container, demand: dict[str, Any]) -> dict[str, Any]:
    """Create in-app leads for matching registered providers. Never raises."""
    if str(demand.get("side") or "NEED").upper() != "NEED" or not demand.get("id"):
        return {"status": "NOT_APPLICABLE", "sent": 0}
    repository = getattr(container, "universal_notification_repository", None)
    catalog = getattr(container, "product_catalog_repository", None)
    if repository is None or catalog is None:
        return {"status": "UNAVAILABLE", "sent": 0}
    try:
        targets = candidate_providers(catalog, demand)
        sent = skipped = 0
        message = _lead_message(demand)
        for target in targets:
            lead_id = repository.reserve_notification(
                int(demand["id"]), str(demand.get("user_id") or ""), target["user_id"], 1, None, None, message,
            )
            if lead_id is None:
                skipped += 1
                continue
            repository.mark_sent(lead_id, f"in-app:{demand['id']}:{target['user_id']}")
            sent += 1
        status = "SENT" if sent else ("ALREADY_SENT" if skipped else "NO_PROVIDERS")
        return {"status": status, "sent": sent, "already_sent": skipped, "channel": "in_app"}
    except Exception as error:  # a broadcast failure never breaks saving the need
        return {"status": "ERROR", "sent": 0, "error": type(error).__name__}
