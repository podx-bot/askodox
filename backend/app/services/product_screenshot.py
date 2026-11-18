"""Product SCREENSHOT -> the item's details (owner 2026-11-18: a Meesho link would not open on the staff phone, so the
item could not be added at all). Staff take a screenshot of the product in the store's own app and the details fill
from it. Only what is clearly visible is returned; a price that is not clearly shown stays empty (never guessed).
Nothing is saved here -- staff check the boxes and save as usual."""
from __future__ import annotations

import re
from typing import Any, Dict, Sequence, Tuple

MAX_PHOTOS = 3

PROMPT = (
    "You read a screenshot of ONE product page in a shopping app or website (Meesho, Amazon, Flipkart, any store; any "
    "language). Return ONLY JSON: {\"title\": string or null, \"price\": number or null, \"mrp\": number or null, "
    "\"seller\": string or null, \"brand\": string or null, \"category\": string or null, \"sizes\": [string], "
    "\"description\": string or null, \"rating\": number or null}. Rules: copy the product name as shown; price = the "
    "selling price in rupees shown for this product (plain number), mrp = the struck-out / original price; null when "
    "not clearly visible -- NEVER guess. Skip offers, coupons, delivery dates, other products, ads and the app's own "
    "buttons. description = the product details text shown (material, size, colour ...), max 600 characters."
)


def _rupees(value: Any) -> float | None:
    try:
        if value is None or isinstance(value, bool):
            return None
        n = float(str(value).replace(",", "").replace("₹", "").replace("Rs.", "").strip())
    except (TypeError, ValueError):
        return None
    return n if 0 < n <= 10_000_000 else None


def _text(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit] if isinstance(value, (str, int, float)) else ""


def read_product(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    """[(bytes, mime)] -> {"fields": {...}, "read": bool}. Never raises for a provider failure (read False)."""
    photos = [(d, m) for d, m in list(images)[:MAX_PHOTOS] if d]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return {"fields": {}, "read": False}
    try:
        try:
            payload, _calls = image_service.analyze_with_prompt(photos, PROMPT, max_models=2,
                                                                allow_second_provider=True, fast=True)
        except TypeError:  # an older / fake service without ``fast``
            payload, _calls = image_service.analyze_with_prompt(photos, PROMPT, max_models=2, allow_second_provider=True)
    except Exception:
        return {"fields": {}, "read": False}
    if not isinstance(payload, dict):
        return {"fields": {}, "read": False}
    fields: Dict[str, Any] = {}
    for key, limit in (("title", 300), ("seller", 200), ("brand", 120), ("category", 160), ("description", 600)):
        value = _text(payload.get(key), limit)
        if value and value.lower() not in ("null", "none", "n/a"):
            fields[key] = value
    price, mrp = _rupees(payload.get("price")), _rupees(payload.get("mrp"))
    if price is not None:
        fields["price"] = price
    if mrp is not None and (price is None or mrp >= price):
        fields["mrp"] = mrp
    sizes = payload.get("sizes")
    if isinstance(sizes, list):
        clean = [s for s in (_text(x, 40) for x in sizes[:30]) if s]
        if clean:
            fields["variants"] = list(dict.fromkeys(clean))
    return {"fields": fields, "read": bool(fields.get("title") or "price" in fields)}
