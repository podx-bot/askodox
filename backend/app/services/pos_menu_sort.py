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


_PREFIX = re.compile(r"^\s*(?:no\.?\s*)?(\d{1,4})\s*[).:\-]\s*(.+)$", re.I)


def clean_name(name: str) -> tuple:
    """"68) Haravara Chicken" -> ("Haravara Chicken", 68). A photo-read menu keeps the printed number in the name."""
    match = _PREFIX.match(str(name or ""))
    if not match or not match.group(2).strip():
        return str(name or "").strip(), None
    return match.group(2).strip(), int(match.group(1))


_PRINTED_NO = re.compile(r"^\s*(?:no\.?\s*)?(\d{1,4})\s*(?:[).:]|-(?=\s))\s*(\S.*)$", re.I)


def printed_number(name: str) -> tuple:
    """Stricter than ``clean_name`` (for automatic cleaning): "117) Fish Biryani" / "12. Tea" / "5 - Dosa" ->
    (name, number); "7-Up", "500 ml Coke", "2 Idli" are left alone."""
    match = _PRINTED_NO.match(str(name or ""))
    if not match:
        return str(name or "").strip(), None
    return match.group(2).strip(), int(match.group(1))


def _key(group: str) -> str:
    return re.sub(r"[^a-z0-9\u0c00-\u0c7f]+", "", group.lower()).rstrip("s")


def sort_menu(items: List[Dict[str, Any]], write_text: Callable[..., str], chunk: int = 50,
              workers: int = 4) -> Dict[str, Any]:
    """items: [{id, name, menu_group, food_type}] -> preview rows (the old values kept where the model is silent).

    Owner 2026-11-18: 193 items took longer than the phone waited ("no internet"). The parts are now read AT THE SAME
    TIME (``workers``) and spellings of one section are merged afterwards ("Biryani" / "Biryanis" / "biryani")."""
    from concurrent.futures import ThreadPoolExecutor

    parts = [items[i:i + chunk] for i in range(0, len(items), chunk)]

    def read(part: List[Dict[str, Any]]) -> Dict[int, Dict[str, Any]]:
        listing = "\n".join(f"{n + 1}. {clean_name(it.get('name'))[0][:80]}" for n, it in enumerate(part))
        try:
            return _parse(write_text(PROMPT + listing, max_tokens=2200) or "")
        except Exception:
            return {}

    with ThreadPoolExecutor(max_workers=max(1, min(workers, len(parts) or 1))) as pool:
        found_parts = list(pool.map(read, parts))
    out: List[Dict[str, Any]] = []
    groups: List[str] = []
    spelled: Dict[str, str] = {}
    read_any = any(found_parts)
    for part, found in zip(parts, found_parts):
        for n, it in enumerate(part):
            got = found.get(n + 1, {})
            raw_group = re.sub(r"\s+", " ", str(got.get("group") or "")).strip()[:40]
            if raw_group and raw_group not in groups:
                groups.append(raw_group)
            group = spelled.setdefault(_key(raw_group), raw_group) if raw_group else str(it.get("menu_group") or "")
            food = str(got.get("food") or "").lower().replace("-", "").replace(" ", "")
            food = food if food in ("veg", "nonveg", "egg") else str(it.get("food_type") or "")
            if group and group not in groups:
                groups.append(group)
            name, number = clean_name(it.get("name"))
            out.append({"id": it["id"], "name": name, "item_no": number,
                        "menu_group": group, "food_type": food,
                        "changed": group != (it.get("menu_group") or "") or food != (it.get("food_type") or "")
                        or name != str(it.get("name") or "").strip()})
    # One spelling per section: the title-cased one the model used most.
    best: Dict[str, str] = {}
    for g in groups:
        k = _key(g)
        if k not in best or (g[:1].isupper() and not best[k][:1].isupper()):
            best[k] = g
    for r in out:
        if r["menu_group"]:
            r["menu_group"] = best.get(_key(r["menu_group"]), r["menu_group"])
    groups = list(dict.fromkeys(best.get(_key(g), g) for g in groups))
    counts = {g: sum(1 for r in out if r["menu_group"] == g) for g in groups}
    return {"items": out, "groups": groups, "counts": counts, "read": read_any}


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
