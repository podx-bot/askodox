"""Bills & warranty (owner 2026-11-27, phase 6): a photo of a bill or a warranty card -> the few facts a person wants
to find again (what, where, when bought, warranty till when, serial number, the service number printed on it).

The reader only READS: nothing is saved here -- the record and the photo stay on the person's own phone. Dates are
what is printed; a warranty end is worked out only from a printed purchase date + a printed warranty period, and the
app shows every value for the person to check (the maker's card is the truth, never this reading).
"""
from __future__ import annotations

from datetime import date
import re
from typing import Any, Dict, Optional, Sequence, Tuple

from app.services.pos_bill_photo import _date, _number
from app.services.pos_memberships import add_months

MAX_PHOTOS = 2
MAX_WARRANTY_MONTHS = 240

PROMPT = (
    "You read a photo of a purchase bill / invoice and / or a warranty card for ONE main item a person bought (any "
    "Indian language or English). Return ONLY JSON: {\"item\": string or null, \"shop\": string or null, "
    "\"bought_on\": \"YYYY-MM-DD\" or null, \"warranty_months\": number or null, \"warranty_until\": \"YYYY-MM-DD\" "
    "or null, \"serial\": string or null, \"service_phone\": string or null, \"amount\": number or null}. "
    "item = brand + product as printed (e.g. \"Preethi Mixer Grinder 750W\"); when the bill has many items, the "
    "costliest one. shop = the seller's name as printed. bought_on = the bill / purchase date printed. "
    "warranty_months = the warranty period printed, in months (2 years = 24). warranty_until = a warranty end date "
    "ONLY when it is printed. serial = the serial / IMEI number printed. service_phone = the customer care / service "
    "number printed. amount = the bill total in rupees (a plain number). A value that is not clearly readable is null "
    "-- NEVER guess, never work a date out yourself."
)


def _text(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def warranty_end(bought_on: str, months: int) -> str:
    """The printed purchase day + the printed period. Empty when either is missing."""
    if not bought_on or months <= 0:
        return ""
    try:
        return add_months(date.fromisoformat(bought_on), months).isoformat()
    except ValueError:
        return ""


def clean(payload: Any) -> Dict[str, Any]:
    """The reader's answer as plain, bounded data. ``read`` False = nothing usable came back."""
    empty: Dict[str, Any] = {"read": False, "item": "", "shop": "", "bought_on": "", "warranty_months": 0,
                             "warranty_until": "", "warranty_from": "", "serial": "", "service_phone": "",
                             "amount_paise": None}
    if not isinstance(payload, dict):
        return empty
    item = _text(payload.get("item"), 80)
    shop = _text(payload.get("shop"), 80)
    bought = _date(payload.get("bought_on"))
    months_raw = _number(payload.get("warranty_months"))
    months = int(months_raw) if months_raw is not None and 0 < months_raw <= MAX_WARRANTY_MONTHS else 0
    until = _date(payload.get("warranty_until"))
    source = "printed" if until else ""
    if not until:
        until = warranty_end(bought, months)
        source = "worked_out" if until else ""
    serial = re.sub(r"[^A-Za-z0-9/\-]", "", str(payload.get("serial") or ""))[:40]
    phone = re.sub(r"\D", "", str(payload.get("service_phone") or ""))
    amount = _number(payload.get("amount"))
    return {"read": bool(item or shop or bought or until), "item": item, "shop": shop, "bought_on": bought,
            "warranty_months": months, "warranty_until": until, "warranty_from": source, "serial": serial,
            "service_phone": phone if 8 <= len(phone) <= 13 else "",
            "amount_paise": int(round(amount * 100)) if amount else None}


def read_paper(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    """[(bytes, mime)] -> the paper's facts. Never raises; nothing is stored."""
    photos = [(data, mime) for data, mime in list(images)[:MAX_PHOTOS] if data]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return clean(None)
    try:
        try:
            payload, _calls = image_service.analyze_with_prompt(photos, PROMPT, max_models=2, allow_second_provider=True,
                                                                fast=True)
        except TypeError:
            payload, _calls = image_service.analyze_with_prompt(photos, PROMPT, max_models=2, allow_second_provider=True)
    except Exception:
        return clean(None)
    return clean(payload)


def days_left(until: str, today: date) -> Optional[int]:
    """Days from today to the warranty's last day (negative = over). None with no end day."""
    try:
        return (date.fromisoformat(until) - today).days
    except (TypeError, ValueError):
        return None
