"""Bulk items from a pasted TABLE (owner 2026-11-19: bulk upload for any shop) -- rows copied from Excel / Google Sheets
(tabs) or a CSV file (commas): name, price and optionally unit and category / group, in any column order when the first
row names the columns, else name first and the first number as the price.

Returns preview items in the same shape as the spoken / typed menu parser (nothing is saved; the owner reviews and
imports). None when the text is not a table (the normal parser then reads it).
"""

from __future__ import annotations

import csv
import io
import re
from typing import Any, Dict, List, Optional

from app.services.pos_store import UNITS

_HEAD = {
    "name": ("name", "item", "item name", "product", "product name", "పేరు", "ఐటమ్", "नाम"),
    "price": ("price", "rate", "mrp", "selling price", "sp", "amount", "ధర", "రేటు", "कीमत", "दाम"),
    "unit": ("unit", "uom", "units", "యూనిట్", "इकाई"),
    "group": ("category", "group", "section", "type", "కేటగిరీ", "విభాగం", "श्रेणी"),
}
_UNIT_WORDS = {
    "pc": "pcs", "piece": "pcs", "pieces": "pcs", "nos": "pcs", "no": "pcs", "kgs": "kg", "kilo": "kg", "gm": "g",
    "gms": "g", "gram": "g", "grams": "g", "ltr": "l", "litre": "l", "liter": "l", "litres": "l", "mtr": "m",
    "meter": "m", "metre": "m", "doz": "dozen", "plates": "plate", "packet": "pack", "pkt": "pack", "packs": "pack",
    "boxes": "box", "hr": "hour", "hours": "hour",
}


def _unit(raw: str, default: str) -> str:
    w = raw.strip().lower().rstrip(".")
    w = _UNIT_WORDS.get(w, w)
    return w if w in UNITS else default


def _paise(raw: str) -> int:
    m = re.search(r"[0-9][0-9,]*(?:\.[0-9]{1,2})?", raw.replace("₹", "").replace("Rs", "").replace("rs", ""))
    if not m:
        return 0
    try:
        return int(round(float(m.group(0).replace(",", "")) * 100))
    except ValueError:
        return 0


def parse(text: str, default_unit: str = "pcs", limit: int = 200) -> Optional[List[Dict[str, Any]]]:
    lines = [l for l in str(text or "").replace("\r", "").split("\n") if l.strip()]
    if len(lines) < 1:
        return None
    sep = "\t" if sum("\t" in l for l in lines) >= max(1, len(lines) // 2) else (
        "," if sum("," in l for l in lines) >= max(1, (len(lines) + 1) // 2) else None)
    if sep is None:
        return None
    rows = [[c.strip() for c in r] for r in csv.reader(io.StringIO("\n".join(lines)), delimiter=sep)]
    rows = [r for r in rows if any(r)]
    if not rows:
        return None
    cols: Dict[str, int] = {}
    head = [c.lower() for c in rows[0]]
    for key, names in _HEAD.items():
        for i, c in enumerate(head):
            if c in names and key not in cols:
                cols[key] = i
    if "name" in cols and "price" in cols:
        rows = rows[1:]
    else:
        cols = {}
    items: List[Dict[str, Any]] = []
    for r in rows:
        if cols:
            name = r[cols["name"]] if cols["name"] < len(r) else ""
            price = _paise(r[cols["price"]]) if cols["price"] < len(r) else 0
            unit = _unit(r[cols["unit"]], default_unit) if "unit" in cols and cols["unit"] < len(r) else default_unit
            group = r[cols["group"]] if "group" in cols and cols["group"] < len(r) else ""
        else:
            # no header: name = the first cell with letters, price = the first cell that is a number, unit = a unit word
            name = next((c for c in r if re.search(r"[^\W\d_]", c)), "")
            price = next((_paise(c) for c in r if c is not name and re.fullmatch(r"[₹Rs.\s]*[0-9][0-9,]*(?:\.[0-9]{1,2})?", c)), 0)
            unit = next((_unit(c, "") for c in r if c is not name and _unit(c, "")), default_unit) or default_unit
            group = ""
        name = re.sub(r"\s+", " ", name).strip()[:80]
        if not name or price <= 0:
            continue
        item: Dict[str, Any] = {"name": name, "price_paise": price, "unit": unit, "today_only": False}
        if group:
            item["menu_group"] = group[:40]
        items.append(item)
        if len(items) >= limit:
            break
    return items or None
