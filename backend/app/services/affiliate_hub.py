"""Affiliate Product Hub: paste -> detect -> extract -> preview -> edit ->
validate -> draft / publish -> enable, one link or many.

Composes what already exists -- ``affiliate_catalog`` (the ONE item store,
review states, eligibility, duplicate keys, history) and
``affiliate_providers`` (provider detection + truthful extraction). Smart
Links stay routing infrastructure; nothing here stores products elsewhere.

Every item succeeds or fails on its own (partial success), carries its own
status and reason, and can be retried alone.
"""

from __future__ import annotations

import re
from typing import Any, Callable, Iterable

from app.services import affiliate_catalog as ac
from app.services import affiliate_providers as providers

MAX_LINKS = 50
_URL = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)

# Per-item preview statuses.
READY, NEEDS_REVIEW, MANUAL, DUPLICATE, INVALID = "READY", "NEEDS_REVIEW", "MANUAL_ENTRY", "DUPLICATE", "INVALID"


def split_links(text: str = "", urls: Iterable[str] = ()) -> list[str]:
    """Every link pasted (one per line, comma / space separated or inside
    other text), in order, without repeats."""
    found = [u.rstrip(").,;") for u in _URL.findall(text or "")] + [str(u).strip() for u in urls if str(u).strip()]
    return list(dict.fromkeys(found))[:MAX_LINKS]


def _status(result: dict[str, Any]) -> str:
    fields = result.get("fields") or {}
    if not fields.get("title"):
        return MANUAL if result.get("status") != "ok" else NEEDS_REVIEW
    if result.get("missing"):
        return NEEDS_REVIEW
    return READY


def preview(store: ac.AffiliateCatalog, links: list[str], *,
            fetch: Callable[[str], str] | None = None) -> dict[str, Any]:
    """Read every link and say, per item, what it is and what is missing.
    Writes nothing."""
    items: list[dict[str, Any]] = []
    seen: dict[str, int] = {}
    for index, url in enumerate(links):
        try:
            clean = ac.https_url(url)
        except ValueError as error:
            items.append({"index": index, "url": url, "status": INVALID, "error": str(error)})
            continue
        key = ac.canonical_key(clean)
        if key in seen:
            items.append({"index": index, "url": clean, "status": DUPLICATE, "duplicate_of_item": seen[key],
                          "error": "Pasted twice in this batch"})
            continue
        seen[key] = index
        existing = store.duplicates(clean)
        try:
            result = providers.extract(clean, fetch=fetch)
        except ValueError as error:
            items.append({"index": index, "url": clean, "status": INVALID, "error": str(error)})
            continue
        item = {
            "index": index, "url": clean, "provider": result.get("provider"),
            "provider_name": result.get("provider_name"), "link_kind": result.get("link_kind"),
            "extraction_status": result.get("status"), "note": result.get("note"),
            "fields": result.get("fields") or {}, "provenance": result.get("provenance") or {},
            "missing": result.get("missing") or [], "commission": result.get("commission"),
            "checked_at": result.get("checked_at"), "status": _status(result),
        }
        if existing:
            item["status"] = DUPLICATE
            item["duplicate_of"] = [{"id": d.get("id"), "title": d.get("title"),
                                     "review_status": d.get("review_status")} for d in existing[:3]]
            item["error"] = f"Already in the catalog as #{existing[0].get('id')}"
        items.append(item)
    counts: dict[str, int] = {}
    for item in items:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
    return {"items": items, "counts": counts, "total": len(items)}


IMPORT_FIELDS = ("title", "original_product_url", "affiliate_url", "image_url", "images", "price", "mrp",
                 "category", "subcategory", "description", "variants", "seller", "brand", "product_id",
                 "canonical_url", "availability", "item_type")


def import_items(store: ac.AffiliateCatalog, items: list[dict[str, Any]], *, actor: str,
                 allowed: Callable[[str], bool]) -> dict[str, Any]:
    """Save previewed (and staff-edited) items. Default = DRAFT. ``publish``
    goes LIVE only for a holder of ``affiliate_products:publish``; anyone
    else's publish request is submitted for review instead."""
    results: list[dict[str, Any]] = []
    for index, raw in enumerate(items):
        warnings: list[str] = []
        try:
            if not allowed("create"):
                raise PermissionError("needs affiliate_products:create")
            fields = {k: v for k, v in (raw.get("fields") or {}).items()
                      if k in IMPORT_FIELDS and v not in (None, "", [])}
            if not fields.get("original_product_url"):
                fields["original_product_url"] = raw.get("url")
            provenance = dict(raw.get("provenance") or {})
            # Staff corrections win and are recorded as staff-verified.
            for key, value in (raw.get("edited") or {}).items():
                if key in IMPORT_FIELDS:
                    fields[key] = value
                    provenance[key] = {"source": "staff", "verified": True, "by": actor,
                                       "checked_at": ac.now_iso()}
            if fields.get("affiliate_url") and not allowed("links"):
                fields.pop("affiliate_url")
                warnings.append("affiliate link not saved: needs affiliate_products:links")
            if not fields.get("title"):
                raise ValueError("A product name is required (enter it by hand if the page did not give one)")
            publish = bool(raw.get("publish"))
            review = "DRAFT"
            if publish and allowed("publish"):
                review = "LIVE"
            elif publish:
                review = "NEEDS_REVIEW"
                warnings.append("submitted for review: publishing needs affiliate_products:publish")
            metadata = {
                "provenance": provenance,
                "extraction": {"status": raw.get("extraction_status"), "provider": raw.get("provider"),
                               "link_kind": raw.get("link_kind"), "checked_at": raw.get("checked_at")},
                "keywords": list((raw.get("fields") or {}).get("keywords") or [])[:20],
                "tags": [str(t)[:40] for t in (raw.get("tags") or [])][:20],
            }
            deep = (raw.get("fields") or {}).get("deep_link")
            if deep:
                metadata["deep_link"] = deep
            # Commission is NEVER taken from a page: UNKNOWN until verified.
            item = store.create(fields, actor=actor, check_source="page_metadata", review_status=review,
                                commission_status=None, metadata=metadata)
            if raw.get("enable") is False:
                item = store.set_active(item["id"], False, actor=actor, note="imported disabled")
            results.append({"index": index, "ok": True, "action": "created", "id": item["id"],
                            "review_status": item.get("review_status"), "active": item.get("active"),
                            "eligible": (item.get("eligibility") or {}).get("eligible"), "warnings": warnings})
        except (ValueError, LookupError, PermissionError) as error:
            results.append({"index": index, "ok": False, "action": "failed", "error": str(error),
                            "retry": isinstance(error, ValueError) and "already" not in str(error).lower(),
                            "warnings": warnings})
    return {"results": results, "ok": sum(1 for r in results if r["ok"]),
            "failed": sum(1 for r in results if not r["ok"])}


# Bulk actions and the permission each needs (least privilege).
BULK_ACTIONS: dict[str, str] = {
    "publish": "publish", "approve": "publish", "reject": "publish",
    "draft": "edit", "submit": "edit", "enable": "edit", "disable": "edit",
    "archive": "delete", "restore": "delete",
}


def bulk_action(store: ac.AffiliateCatalog, ids: list[int], action: str, *, actor: str,
                allowed: Callable[[str], bool], note: str = "") -> dict[str, Any]:
    if action not in BULK_ACTIONS:
        raise ValueError("action must be one of " + ", ".join(sorted(BULK_ACTIONS)))
    verb = BULK_ACTIONS[action]
    results: list[dict[str, Any]] = []
    for pid in list(dict.fromkeys(int(i) for i in ids))[:500]:
        try:
            if not allowed(verb):
                raise PermissionError(f"needs affiliate_products:{verb}")
            if action in {"publish", "approve"}:
                item = store.set_review(pid, "LIVE", actor=actor, note=note or action)
                if not item.get("active"):
                    item = store.set_active(pid, True, actor=actor, note="published")
            elif action == "reject":
                item = store.set_review(pid, "DRAFT", actor=actor, note=note or "rejected")
            elif action == "draft":
                item = store.set_review(pid, "DRAFT", actor=actor, note=note)
            elif action == "submit":
                item = store.set_review(pid, "NEEDS_REVIEW", actor=actor, note=note)
            elif action in {"enable", "disable"}:
                item = store.set_active(pid, action == "enable", actor=actor, note=note)
            elif action == "archive":
                item = store.delete(pid, actor=actor, note=note or "archived")
            else:  # restore
                item = store.restore(pid, actor=actor, note=note)
            results.append({"id": pid, "ok": True, "review_status": item.get("review_status"),
                            "active": item.get("active"), "archived": bool(item.get("deleted_at")),
                            "eligible": (item.get("eligibility") or {}).get("eligible")})
        except (ValueError, LookupError, PermissionError) as error:
            results.append({"id": pid, "ok": False, "error": str(error)})
    return {"action": action, "results": results, "ok": sum(1 for r in results if r["ok"]),
            "failed": sum(1 for r in results if not r["ok"])}
