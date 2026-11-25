"""Bulk price change (owner 2026-11-25, "ఒక్క టచ్" seller list): change many items' prices at once.

Which items: all, the shop's own menu sections (``menu_group``), or picked ids. How: up / down by a percent, up / down
by rupees, or one price for all. New prices are rounded to the shop's choice (₹1 / ₹5 / ₹10 / none) and never go
below ₹1. ``preview`` shows old -> new without writing; ``apply`` writes every item in ONE transaction with the same
product history + audit rows a single edit makes (edits apply to FUTURE bills only; issued bills keep their prices).
Rates by quantity (tiers), pack prices and a separately set online price are NOT touched -- the answer says how many
items have them so the owner can check those by hand.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List

from app.services.pos_store import PosError, PosStore

MODES = ("up_percent", "down_percent", "up_rupees", "down_rupees", "set")
ROUNDS = (0, 100, 500, 1000)  # paise: none, ₹1, ₹5, ₹10
MAX_ITEMS = 500


def new_price(old_paise: int, mode: str, value: float, round_paise: int) -> int:
    """Pure rule (the app shows the same numbers before the owner taps ✓)."""
    if mode == "up_percent":
        raw = old_paise * (100 + value) / 100
    elif mode == "down_percent":
        raw = old_paise * (100 - value) / 100
    elif mode == "up_rupees":
        raw = old_paise + value * 100
    elif mode == "down_rupees":
        raw = old_paise - value * 100
    elif mode == "set":
        raw = value * 100
    else:
        raise PosError(400, "mode", "Unknown way to change the price.")
    price = int(round(raw))
    if round_paise:
        price = int(round(price / round_paise)) * round_paise
    return max(100, price)


def _check(mode: str, value: float, round_paise: int) -> None:
    if mode not in MODES:
        raise PosError(400, "mode", "Unknown way to change the price.")
    if round_paise not in ROUNDS:
        raise PosError(400, "round", "Round to ₹1, ₹5 or ₹10 (or not at all).")
    if mode.endswith("percent") and not 0 < value <= (90 if mode == "down_percent" else 500):
        raise PosError(400, "value", "Percent must be more than 0 (down at most 90%).")
    if not mode.endswith("percent") and not 0 < value <= 1_000_000:
        raise PosError(400, "value", "Give an amount in rupees.")


def _pick(conn, business_id: str, scope: str, groups: List[str], ids: List[str]):
    rows = conn.execute("SELECT * FROM pos_products WHERE business_id = ? AND active = 1 ORDER BY name",
                        (business_id,)).fetchall()
    if scope == "groups":
        wanted = {g.strip().lower() for g in groups if g and g.strip()}
        if not wanted:
            raise PosError(400, "groups", "Choose at least one section.")
        rows = [r for r in rows if (r["menu_group"] or "").strip().lower() in wanted]
    elif scope == "items":
        wanted_ids = {i for i in ids if i}
        if not wanted_ids:
            raise PosError(400, "items", "Choose at least one item.")
        rows = [r for r in rows if r["id"] in wanted_ids]
    elif scope != "all":
        raise PosError(400, "scope", "Choose all items, sections or items.")
    if len(rows) > MAX_ITEMS:
        raise PosError(400, "items", f"At most {MAX_ITEMS} items at once.")
    return rows


def _plan(store: PosStore, conn, business_id: str, data: Dict[str, Any]):
    mode = str(data.get("mode") or "")
    value = float(data.get("value") or 0)
    round_paise = int(data.get("round_paise") if data.get("round_paise") is not None else 100)
    _check(mode, value, round_paise)
    rows = _pick(conn, business_id, str(data.get("scope") or "all"), list(data.get("groups") or []),
                 list(data.get("product_ids") or []))
    tiers = {r["product_id"] for r in conn.execute(
        "SELECT DISTINCT product_id FROM pos_price_tiers WHERE business_id = ?", (business_id,))}
    packs = {r["product_id"] for r in conn.execute(
        "SELECT DISTINCT product_id FROM pos_product_packs WHERE business_id = ? AND price_paise IS NOT NULL",
        (business_id,))}
    lines = []
    for r in rows:
        new = new_price(int(r["price_paise"]), mode, value, round_paise)
        lines.append({"id": r["id"], "name": r["name"], "group": r["menu_group"] or "", "old_paise": int(r["price_paise"]),
                      "new_paise": new, "changes": new != int(r["price_paise"])})
    keys = {r["id"] for r in rows}
    online = sum(1 for r in rows if r["online_price_paise"] is not None)
    return lines, {"tiers": len(keys & tiers), "packs": len(keys & packs), "online_price": online}


def preview(store: PosStore, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
    with store._connect() as conn:
        store._require(conn, business_id, user, "products")
        lines, untouched = _plan(store, conn, business_id, data)
    return {"items": lines, "changing": sum(1 for l in lines if l["changes"]), "not_changed": untouched}


def apply(store: PosStore, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
    with store._tx() as conn:
        store._require(conn, business_id, user, "products")
        lines, untouched = _plan(store, conn, business_id, data)
        now = store.clock().isoformat()
        done: List[str] = []
        for line in lines:
            if not line["changes"]:
                continue
            row = conn.execute("SELECT version FROM pos_products WHERE id = ?", (line["id"],)).fetchone()
            version = row["version"] + 1
            conn.execute("UPDATE pos_products SET price_paise = ?, version = ?, updated_at = ? WHERE id = ?",
                         (line["new_paise"], version, now, line["id"]))
            change = {"before": {"price_paise": line["old_paise"]}, "after": {"price_paise": line["new_paise"]},
                      "bulk": {"mode": data.get("mode"), "value": data.get("value")}}
            conn.execute("INSERT INTO pos_product_history (product_id, business_id, version, changes, changed_by, at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (line["id"], business_id, version, json.dumps(change), user, now))
            store._audit(conn, business_id, user, "product.update", line["id"], change, now)
            done.append(line["id"])
    return {"changed": len(done), "product_ids": done, "items": lines, "not_changed": untouched}
