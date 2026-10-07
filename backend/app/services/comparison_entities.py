"""Which phrases can be compared as things (products, services, options).

A comparison is between real items. Location phrases ("in Vuyyuru, Andhra
Pradesh"), price constraints ("under ₹20k"), source / status labels
("Sponsored", "In stock", "Online") and other result metadata are never
comparison entities -- comparing "in Vuyyuru" with other options is
nonsense. Category-agnostic: no product vocabulary, only the shapes of
metadata.
"""

from __future__ import annotations

import re
from typing import Iterable

_LOCATION_LEAD = re.compile(
    r"^\s*(?:in|near|at|around|from|within|nearby|close\s+to|located\s+in|based\s+in|"
    r"lo|daggara|mein|me)\b",
    re.IGNORECASE,
)
_LOCATION_TAIL = re.compile(r"(?:లో|దగ్గర|వద్ద|में|के\s+पास)\s*$")
_PRICE_LIKE = re.compile(
    r"^\s*(?:(?:under|below|above|over|within|upto|up\s+to|around|less\s+than|more\s+than|budget)\s*)?"
    r"(?:₹|rs\.?|inr)?\s*[\d,.]+\s*(?:k|l|lakh|lakhs|thousand|rs|rupees?|/-)?\s*$",
    re.IGNORECASE,
)
_CONSTRAINT_ONLY = re.compile(
    r"^\s*(?:under|below|above|over|within|upto|up\s+to|around|less\s+than|more\s+than)\b",
    re.IGNORECASE,
)
_META_LABELS = {
    "available", "unavailable", "in stock", "out of stock", "stock", "verified", "unverified", "not verified",
    "sponsored", "ad", "online", "offline", "local", "nearby", "open now", "open", "closed", "new", "used",
    "refurbished", "deal", "deals", "offer", "offers", "result", "results", "option", "options", "item",
    "items", "the other options", "other options", "the others", "others", "price not provided",
    "not provided", "unknown", "best", "cheapest", "nearest", "top rated", "featured", "partner",
    "affiliate", "marketplace", "store", "shop", "seller", "provider", "listing",
}
_COMPARE_SPLIT = re.compile(r"\s+(?:vs\.?|versus|or|and|with|against|aur|ya|leka|mariyu|తో|లేదా)\s+", re.IGNORECASE)
_COMPARE_LEAD = re.compile(
    r"^\s*(?:please\s+)?(?:compare|comparison\s+of|difference\s+between|which\s+is\s+better[:,]?)\s+",
    re.IGNORECASE,
)


def is_entity_label(text: str, *, location_labels: Iterable[str] = (), meta_labels: Iterable[str] = ()) -> bool:
    """True only for a phrase that can stand for a comparable thing."""
    label = " ".join(str(text or "").replace('"', " ").replace("'", " ").split()).strip(" .,:;-")
    if not label or not any(ch.isalpha() for ch in label):
        return False
    low = label.casefold()
    if low in _META_LABELS or low in {str(m).strip().casefold() for m in meta_labels if str(m).strip()}:
        return False
    if _LOCATION_LEAD.search(label) or _LOCATION_TAIL.search(label):
        return False
    if _PRICE_LIKE.match(label) or _CONSTRAINT_ONLY.match(label):
        return False
    for place in location_labels:
        place_low = " ".join(str(place or "").split()).casefold()
        if not place_low:
            continue
        if low == place_low or (len(low) >= 4 and low in place_low) or place_low.startswith(low):
            return False
    return True


def comparison_candidates(text: str) -> list[str]:
    """The phrases a comparison message names ("A vs B", "compare A with B")."""
    body = _COMPARE_LEAD.sub("", " ".join(str(text or "").split()))
    body = re.sub(r"[?!.]+$", "", body)
    parts = [p.strip(" ,;:\"'") for p in _COMPARE_SPLIT.split(body)]
    return [p for p in parts if p]


def named_comparison_entities(text: str, *, location_labels: Iterable[str] = ()) -> list[str]:
    """Only the candidates that are real things; metadata is dropped."""
    places = list(location_labels)
    return [c for c in comparison_candidates(text) if is_entity_label(c, location_labels=places)]
