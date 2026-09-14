"""Manually curated sponsored placements shown to buyers."""
from __future__ import annotations

from typing import Any

SPONSORED_ITEMS: list[dict[str, Any]] = []


def sponsored_items_for(placement: str) -> list[dict[str, Any]]:
    clean_placement = str(placement or "").strip().lower()
    if not clean_placement:
        return []
    return [
        item
        for item in SPONSORED_ITEMS
        if isinstance(item, dict)
        and item.get("active")
        and str(item.get("placement", "")).strip().lower() == clean_placement
        and str(item.get("id", "")).strip()
        and str(item.get("title", "")).strip()
    ]
