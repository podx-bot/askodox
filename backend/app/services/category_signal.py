"""The most specific category ASKODOX actually detected for a request.

Events, analytics and AI insights used to store the coarse routing domain
(PRODUCT / SERVICES), so every insight read "PRODUCT". This picks, in
order: the detected category the request carries, the app's AI category,
the structured detail fields, the request's own category word and finally
the subject -- and only falls back to the domain when nothing specific
exists. The domain is kept separately.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable, Optional, Tuple

GENERIC = {"", "product", "products", "service", "services", "general", "unknown", "other", "commerce", "item",
           "items", "need", "offer", "none", "null", "misc"}
_CATEGORY_FIELDS = ("category_detected", "category", "product_category", "service_category", "product_type",
                    "service_type", "item_type", "type")
_SUB_FIELDS = ("subcategory_detected", "subcategory", "sub_category", "variant_type")
_DETAIL_FIELDS = ("service", "item", "product", "skill", "role", "jobRole", "job_role", "cargo", "speciality",
                  "specialty", "jobType", "rentalType")


def _specific(value: Any) -> Optional[str]:
    text = " ".join(str(value or "").strip().split())
    return text[:80] if text and text.casefold() not in GENERIC else None


def _first(values: Iterable[Any]) -> Optional[str]:
    for value in values:
        if isinstance(value, (list, tuple)):
            found = _first(value)
        else:
            found = _specific(value)
        if found:
            return found
    return None


def detect(*, constraints: Dict[str, Any] | None = None, category: Any = None, trace: Dict[str, Any] | None = None,
           subject: Any = None) -> Tuple[Optional[str], Optional[str]]:
    constraints = constraints or {}
    trace = trace or {}
    cat = (_first(constraints.get(k) for k in _CATEGORY_FIELDS)
           or _first([trace.get("categories")]) or _first([trace.get("category")])
           or _specific(category)
           or _first(constraints.get(k) for k in _DETAIL_FIELDS)
           or _specific(subject))
    sub = _first(constraints.get(k) for k in _SUB_FIELDS)
    if sub and cat and sub.casefold() == cat.casefold():
        sub = None
    return cat, sub


def for_demand(demand: Dict[str, Any]) -> Tuple[str, Optional[str]]:
    """(category, subcategory) for events; the domain only as a last resort."""
    constraints = demand.get("constraints") or {}
    cat, sub = detect(constraints=constraints, category=demand.get("category"), trace=demand.get("trace"),
                      subject=demand.get("subject"))
    return (cat or str(demand.get("domain") or "").strip())[:80], sub
