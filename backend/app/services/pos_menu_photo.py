"""Menu PHOTO -> a PREVIEW list of items with the prices printed on it (owner 2026-11-16).

Nothing is saved here: the shop owner sees the list, edits any name / price, and only then imports it with the same
``import_menu`` the spoken menu uses. A price that is not clearly on the photo stays EMPTY (needs_price) -- the model
never guesses one. Works for a printed list, a hand-written board, any language; several photos make one list.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Sequence, Tuple

MAX_ITEMS = 200
MAX_PHOTOS = 4
MAX_RUPEES = 100000

PROMPT = (
    "You read a photo of a menu / price list of a shop, hotel, tiffin centre or any business (printed or hand-written, "
    "any Indian language or English). Return ONLY JSON: {\"items\": [{\"name\": string, \"price\": number or null, "
    "\"unit\": string or null}]}. Rules: one entry per sellable item; copy the item name as printed (keep its "
    "language); price = the rupee amount printed beside that item as a plain number, or null when it is not clearly "
    "visible -- NEVER guess a price; unit = plate / kg / piece / glass / cup / etc. only if printed, else null; "
    "skip headings, phone numbers, addresses, offers, GST lines and totals. If a name has two prices (half / full), "
    "make two entries named 'Name (half)' and 'Name (full)'."
)

_UNITS = {"plate": "plate", "plates": "plate", "kg": "kg", "kgs": "kg", "piece": "pcs", "pieces": "pcs", "pcs": "pcs",
          "glass": "glass", "cup": "cup", "litre": "litre", "ltr": "litre", "l": "litre", "gm": "g", "gram": "g"}


def _norm(name: str) -> str:
    return re.sub(r"[^\w]+", " ", str(name or "").lower(), flags=re.UNICODE).strip()


def _price_paise(value: Any) -> int | None:
    try:
        if value is None or isinstance(value, bool):
            return None
        rupees = float(str(value).replace(",", "").replace("₹", "").replace("Rs.", "").strip())
    except (TypeError, ValueError):
        return None
    if rupees <= 0 or rupees > MAX_RUPEES:
        return None
    return int(round(rupees * 100))


def read_menu(image_service: Any, images: Sequence[Tuple[bytes, str]], default_unit: str = "plate") -> Dict[str, Any]:
    """[(bytes, mime)] -> {"items": [...], "read": bool}. Never raises for a provider failure (read False)."""
    photos = [(data, mime) for data, mime in list(images)[:MAX_PHOTOS] if data]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return {"items": [], "read": False}
    try:
        payload, _calls = image_service.analyze_with_prompt(photos, PROMPT, max_models=2, allow_second_provider=True)
    except Exception:
        return {"items": [], "read": False}
    raw = payload.get("items") if isinstance(payload, dict) else None
    if not isinstance(raw, list):
        return {"items": [], "read": False}
    items: List[Dict[str, Any]] = []
    seen = set()
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        name = re.sub(r"\s+", " ", str(entry.get("name") or "")).strip()[:80]
        key = _norm(name)
        if len(key) < 2 or key in seen:
            continue
        seen.add(key)
        unit = _UNITS.get(str(entry.get("unit") or "").strip().lower(), default_unit)
        price = _price_paise(entry.get("price"))
        items.append({"name": name, "price_paise": price or 0, "unit": unit, "today_only": False,
                      "needs_price": price is None})
        if len(items) >= MAX_ITEMS:
            break
    return {"items": items, "read": True}
