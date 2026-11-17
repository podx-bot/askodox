"""Sort a shop's existing menu into sections + veg / non-veg / egg with ONE model reading of the item names
(owner 2026-11-17: "73 items have no section"). Nothing is saved here: the owner sees the preview, fixes any line and
then saves. The model only reads the names it is given; an item it cannot place keeps what it had."""

from __future__ import annotations

import json
import re
from typing import Any, Callable, Dict, List

PROMPT = (
    "You sort the items of ONE shop's menu. For each numbered item name (any language), give the menu section it "
    "belongs to and whether it is veg, nonveg or egg. Use at most 8 short sections that suit THIS menu, written the "
    "way Indian menus print them in English (e.g. Biryani, Starters, Curries, Rice, Rotis, Drinks, Desserts, Tiffins) "
    "-- the same spelling for every item of one section. food = veg / nonveg / egg only when the name makes it clear "
    "(chicken, mutton, fish, prawn, egg, paneer, dal ...), else \"\". Return ONLY JSON: "
    "{\"items\": [{\"i\": number, \"group\": string, \"food\": \"veg\"|\"nonveg\"|\"egg\"|\"\"}]}.\nItems:\n"
)


def sort_menu(items: List[Dict[str, Any]], write_text: Callable[..., str], chunk: int = 60) -> Dict[str, Any]:
    """items: [{id, name, menu_group, food_type}] -> preview rows (the old values kept where the model is silent)."""
    out: List[Dict[str, Any]] = []
    groups: List[str] = []
    read_any = False
    for start in range(0, len(items), chunk):
        part = items[start:start + chunk]
        listing = "\n".join(f"{n + 1}. {str(it.get('name') or '')[:80]}" for n, it in enumerate(part))
        hint = f"\nSections already used: {', '.join(groups)}" if groups else ""
        try:
            raw = write_text(PROMPT + listing + hint, max_tokens=2200) or ""
        except Exception:
            raw = ""
        found = _parse(raw)
        read_any = read_any or bool(found)
        for n, it in enumerate(part):
            got = found.get(n + 1, {})
            group = re.sub(r"\s+", " ", str(got.get("group") or "")).strip()[:40] or str(it.get("menu_group") or "")
            food = str(got.get("food") or "").lower().replace("-", "").replace(" ", "")
            food = food if food in ("veg", "nonveg", "egg") else str(it.get("food_type") or "")
            if group and group not in groups:
                groups.append(group)
            out.append({"id": it["id"], "name": it.get("name", ""), "menu_group": group, "food_type": food,
                        "changed": group != (it.get("menu_group") or "") or food != (it.get("food_type") or "")})
    return {"items": out, "groups": groups, "read": read_any}


def _parse(raw: str) -> Dict[int, Dict[str, Any]]:
    match = re.search(r"\{.*\}", raw or "", re.S)
    if not match:
        return {}
    try:
        data = json.loads(match.group(0))
    except ValueError:
        return {}
    out: Dict[int, Dict[str, Any]] = {}
    for row in data.get("items") or []:
        if isinstance(row, dict):
            try:
                out[int(row.get("i"))] = row
            except (TypeError, ValueError):
                continue
    return out
