"""Menu PHOTO -> a PREVIEW list of items with the prices printed on it (owner 2026-11-16).

Nothing is saved here: the shop owner sees the list, edits any name / price, and only then imports it with the same
``import_menu`` the spoken menu uses. A price that is not clearly on the photo stays EMPTY (needs_price) -- the model
never guesses one. Works for a printed list, a hand-written board, any language; several photos make one list.
"""
from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Sequence, Tuple

MAX_ITEMS = 200
MAX_PHOTOS = 4
MAX_RUPEES = 100000

PROMPT = (
    "You read a photo of a menu / price list of a shop, hotel, tiffin centre or any business (printed or hand-written, "
    "any Indian language or English). Return ONLY JSON: {\"items\": [{\"name\": string, \"price\": number or null, "
    "\"unit\": string or null, \"group\": string or null, \"food_type\": \"veg\" | \"nonveg\" | \"egg\" | null}]}. "
    "group = the menu section heading the item is printed under (as printed, e.g. Biryani / Starters / Drinks), else "
    "null; food_type only when the menu marks it (green / red dot, a Veg / Non-Veg heading) or the item name itself "
    "says it (chicken, mutton, fish, egg ...), else null. Rules: one entry per sellable item; copy the item name as printed (keep its "
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
    # One call PER photo, all at once, thinking off (owner 2026-11-16: three photos in one call took 44-75 s and the
    # phone gave up). The answer waits only for the slowest single photo.
    def one(photo: Tuple[bytes, str]) -> Any:
        try:
            try:
                payload, _calls = image_service.analyze_with_prompt([photo], PROMPT, max_models=2,
                                                                    allow_second_provider=True, fast=True)
            except TypeError:  # an older / fake service without ``fast``
                payload, _calls = image_service.analyze_with_prompt([photo], PROMPT, max_models=2,
                                                                    allow_second_provider=True)
        except Exception:
            return None
        raw_items = payload.get("items") if isinstance(payload, dict) else None
        return raw_items if isinstance(raw_items, list) else None

    if len(photos) == 1:
        answers = [one(photos[0])]
    else:
        with ThreadPoolExecutor(max_workers=len(photos)) as pool:
            answers = list(pool.map(one, photos))
    if all(a is None for a in answers):
        return {"items": [], "read": False}
    raw = [entry for a in answers if a for entry in a]
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
        food = str(entry.get("food_type") or "").strip().lower().replace("-", "").replace(" ", "")
        items.append({"name": name, "price_paise": price or 0, "unit": unit, "today_only": False,
                      "needs_price": price is None,
                      "menu_group": re.sub(r"\s+", " ", str(entry.get("group") or "")).strip()[:40],
                      "food_type": food if food in ("veg", "nonveg", "egg") else ""})
        if len(items) >= MAX_ITEMS:
            break
    return {"items": items, "read": True}


# ---- shelf photo (owner 2026-11-24): one photo of a shelf / counter -> every pack on it, each with its own photo.
SHELF_PROMPT = (
    "You see a photo of a shop shelf, rack or counter with packaged products (any language on the packs). Return ONLY "
    "JSON: {\"items\": [{\"name\": string, \"brand\": string or null, \"pack\": string or null, \"mrp\": number or null, "
    "\"box\": [ymin, xmin, ymax, xmax]}]}. One entry per DIFFERENT product (the same product repeated on the shelf = one "
    "entry). name = the product name as printed (with the variant, e.g. 'Sunflower oil'); brand = the brand printed; "
    "pack = the size printed (e.g. '1 L', '500 g'), else null; mrp = the MRP rupees ONLY when you can clearly read it on "
    "the pack, else null -- NEVER guess a price; box = where ONE pack of it is, as numbers 0-1000 of the photo height / "
    "width. Skip anything you cannot read."
)
MAX_SHELF_ITEMS = 60
THUMB_PX = 360


def _crop(image: bytes, box: Any) -> str:
    """One pack cut out of the shelf photo as a small JPEG (base64), or '' when the box is unusable."""
    try:
        import base64
        import io

        from PIL import Image

        ymin, xmin, ymax, xmax = [max(0.0, min(1000.0, float(v))) for v in list(box)[:4]]
        if ymax - ymin < 20 or xmax - xmin < 20:
            return ""
        with Image.open(io.BytesIO(image)) as photo:
            photo = photo.convert("RGB")
            w, h = photo.size
            part = photo.crop((int(xmin / 1000 * w), int(ymin / 1000 * h), int(xmax / 1000 * w), int(ymax / 1000 * h)))
            part.thumbnail((THUMB_PX, THUMB_PX))
            out = io.BytesIO()
            part.save(out, format="JPEG", quality=80)
        data = out.getvalue()
        return base64.b64encode(data).decode("ascii") if len(data) <= 120_000 else ""
    except Exception:
        return ""


def read_shelf(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    """[(bytes, mime)] shelf photos -> {"items": [{name, brand, pack, mrp_paise, price_paise, needs_price, photo_b64}],
    "read": bool}. Nothing saved; a price only when the MRP is printed and read."""
    photos = [(data, mime) for data, mime in list(images)[:MAX_PHOTOS] if data]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return {"items": [], "read": False}

    def one(photo: Tuple[bytes, str]) -> Any:
        try:
            try:
                payload, _calls = image_service.analyze_with_prompt([photo], SHELF_PROMPT, max_models=2,
                                                                    allow_second_provider=True, fast=True)
            except TypeError:
                payload, _calls = image_service.analyze_with_prompt([photo], SHELF_PROMPT, max_models=2,
                                                                    allow_second_provider=True)
        except Exception:
            return None
        found = payload.get("items") if isinstance(payload, dict) else None
        return [(photo[0], e) for e in found] if isinstance(found, list) else None

    with ThreadPoolExecutor(max_workers=len(photos)) as pool:
        answers = list(pool.map(one, photos))
    if all(a is None for a in answers):
        return {"items": [], "read": False}
    items: List[Dict[str, Any]] = []
    seen = set()
    for image, entry in [pair for a in answers if a for pair in a]:
        if not isinstance(entry, dict):
            continue
        name = re.sub(r"\s+", " ", str(entry.get("name") or "")).strip()[:60]
        brand = re.sub(r"\s+", " ", str(entry.get("brand") or "")).strip()[:40]
        pack = re.sub(r"\s+", " ", str(entry.get("pack") or "")).strip()[:20]
        full = " ".join(x for x in (brand if brand.lower() not in name.lower() else "", name, pack) if x)[:80]
        key = _norm(full)
        if len(key) < 2 or key in seen:
            continue
        seen.add(key)
        mrp = _price_paise(entry.get("mrp"))
        box = entry.get("box")
        items.append({"name": full, "brand": brand, "pack": pack, "mrp_paise": mrp, "price_paise": mrp or 0,
                      "needs_price": mrp is None, "price_from": "mrp" if mrp else "", "unit": "pcs", "today_only": False,
                      "menu_group": "", "food_type": "",
                      "photo_b64": _crop(image, box) if isinstance(box, (list, tuple)) and len(box) >= 4 else ""})
        if len(items) >= MAX_SHELF_ITEMS:
            break
    return {"items": items, "read": True}
