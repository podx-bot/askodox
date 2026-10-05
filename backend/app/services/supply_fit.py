"""How well ONE registered ASKODOX listing fits the customer's explicit
constraints -- not a keyword match.

For each constraint the customer actually gave (size, budget, brand, colour,
distance / radius, quantity) a listing is:

  matched   -- the listing's own data satisfies it
  unmatched -- the listing's own data contradicts it (e.g. price over budget)
  unknown   -- the listing does not say (a missing-data opportunity for the
               seller -- never assumed to match)

Out-of-stock is always "unmatched". The result is explainable ("why it
matched") and drives ranking among registered listings only; it never
removes a row or invents a value.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, Iterable, List, Optional

from app.services.result_orchestrator import explicit_constraints


def _num(value: Any) -> Optional[float]:
    try:
        if value in (None, ""):
            return None
        return float(str(value).replace(",", "").replace("₹", "").strip())
    except (TypeError, ValueError):
        return None


def _features(listing: Dict[str, Any]) -> List[str]:
    raw = listing.get("features_json") if "features_json" in listing else listing.get("features")
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except ValueError:
            raw = [raw]
    return [str(x) for x in (raw or []) if x not in (None, "")]


def _listing_text(listing: Dict[str, Any]) -> str:
    return " ".join([str(listing.get(k) or "") for k in ("subject", "variant", "brand", "title")] +
                    _features(listing)).lower()


_SIZE_FIELD = re.compile(r"\bsizes?\b\s*[:\-]?\s*([0-9a-z ,/&-]+)", re.IGNORECASE)


def _sizes(listing: Dict[str, Any]) -> Optional[List[str]]:
    """Sizes the listing itself declares (variant / features "Size: 7, 8, 9");
    None when it says nothing about size."""
    found: List[str] = []
    for text in [str(listing.get("variant") or "")] + _features(listing):
        for m in _SIZE_FIELD.finditer(text):
            found += [s.strip().lower() for s in re.split(r"[,/&]|\band\b", m.group(1)) if s.strip()]
    if not found and str(listing.get("variant") or "").strip():
        variant = str(listing["variant"]).strip().lower()
        if re.fullmatch(r"(uk|us|eu)?\s*\d{1,2}(\.\d)?|xs|s|m|l|xl|xxl|xxxl", variant):
            found = [variant]
    return found or None


def evaluate(listing: Dict[str, Any], demand: Dict[str, Any], *, distance_km: Optional[float] = None) -> Dict[str, Any]:
    constraints = explicit_constraints(demand)
    matched: List[str] = []
    unmatched: List[str] = []
    unknown: List[str] = []

    stock = str(listing.get("stock_status") or "UNKNOWN").upper()
    if stock in ("OUT_OF_STOCK", "UNAVAILABLE"):
        unmatched.append("in stock")

    size = constraints.get("size")
    if size not in (None, ""):
        sizes = _sizes(listing)
        want = str(size).strip().lower()
        if sizes is None:
            unknown.append(f"size {size}")
        elif any(want == s or re.sub(r"^(uk|us|eu)\s*", "", s) == want for s in sizes):
            matched.append(f"size {size}")
        else:
            unmatched.append(f"size {size}")

    budget_max = _num(constraints.get("budget_max") or constraints.get("budget"))
    budget_min = _num(constraints.get("budget_min"))
    price = _num(listing.get("price"))
    if budget_max is not None or budget_min is not None:
        label = (f"under ₹{budget_max:,.0f}" if budget_max is not None else f"over ₹{budget_min:,.0f}")
        if price is None:
            unknown.append(f"price ({label})")
        elif (budget_max is not None and price > budget_max) or (budget_min is not None and price < budget_min):
            unmatched.append(f"price ₹{price:,.0f} ({label})")
        else:
            matched.append(f"price ₹{price:,.0f} ({label})")

    for key in ("brand", "color"):
        want = constraints.get(key)
        if want in (None, ""):
            continue
        text = _listing_text(listing)
        own = str(listing.get(key) or "").strip().lower()
        if str(want).strip().lower() in text:
            matched.append(f"{key} {want}")
        elif own:
            unmatched.append(f"{key} {want}")
        else:
            unknown.append(f"{key} {want}")

    radius = _num(constraints.get("radius_km"))
    if radius is not None:
        if distance_km is None:
            unknown.append(f"within {radius:g} km")
        elif distance_km <= radius:
            matched.append(f"within {radius:g} km")
        else:
            unmatched.append(f"{distance_km:.1f} km away (asked within {radius:g} km)")

    total = len(matched) + len(unmatched) + len(unknown)
    score = 1.0 if total == 0 else (len(matched) + 0.4 * len(unknown)) / total
    if unmatched:
        score = min(score, 0.49)
    return {"matched": matched, "unmatched": unmatched, "unknown": unknown, "score": round(score, 3),
            "status": "fits" if not unmatched and not unknown else ("mismatch" if unmatched else "missing_data")}


def why_text(fit: Dict[str, Any]) -> str:
    """One honest line for the card ("Matches size 9, price ₹1,800 (under ₹2,000);
    not stated: colour")."""
    parts = []
    if fit["matched"]:
        parts.append("Matches " + ", ".join(fit["matched"]))
    if fit["unmatched"]:
        parts.append("Does not match " + ", ".join(fit["unmatched"]))
    if fit["unknown"]:
        parts.append("Not stated by the seller: " + ", ".join(fit["unknown"]))
    return "; ".join(parts)


def annotate(matches: Iterable[Dict[str, Any]], demand: Dict[str, Any], lookup) -> List[Dict[str, Any]]:
    """Adds ``fit`` + ``why`` to registered rows (``lookup(id)`` -> listing)
    and returns the missing-data gaps (listing id, seller, unknown fields)."""
    gaps: List[Dict[str, Any]] = []
    for item in matches:
        if item.get("match_source") != "registered" or not str(item.get("id") or "").isdigit():
            continue
        listing = lookup(int(item["id"]))
        if not listing:
            continue
        fit = evaluate(listing, demand, distance_km=_num(item.get("distance_km")))
        item["fit"] = fit
        item["why"] = why_text(fit)
        if fit["unknown"]:
            gaps.append({"listing_id": int(item["id"]), "seller_user_id": listing.get("seller_user_id"),
                         "missing": fit["unknown"], "subject": listing.get("subject")})
    return gaps


def rank_registered(matches: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Registered rows ordered by fit (fits > missing data > mismatch), keeping
    every other row exactly where it was."""
    slots = [i for i, m in enumerate(matches) if m.get("fit")]
    ordered = sorted((matches[i] for i in slots), key=lambda m: -m["fit"]["score"])
    out = list(matches)
    for i, m in zip(slots, ordered):
        out[i] = m
    return out


def record_gaps(database_path: str, gaps: List[Dict[str, Any]]) -> None:
    """Counts how often a listing could not answer a customer's constraint
    (aggregated -- no customer identity), so the seller sees "38 searches
    needed Size 9; your listing does not say"."""
    if not gaps:
        return
    import sqlite3
    import time
    from contextlib import closing

    with closing(sqlite3.connect(database_path)) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS supply_gaps (listing_id INTEGER NOT NULL, seller_user_id TEXT, "
                     "field TEXT NOT NULL, subject TEXT, hits INTEGER NOT NULL DEFAULT 0, last_seen INTEGER NOT NULL, "
                     "PRIMARY KEY(listing_id, field))")
        now = int(time.time())
        for gap in gaps:
            for field in gap["missing"]:
                conn.execute(
                    "INSERT INTO supply_gaps(listing_id, seller_user_id, field, subject, hits, last_seen) "
                    "VALUES(?,?,?,?,1,?) ON CONFLICT(listing_id, field) DO UPDATE SET hits=hits+1, last_seen=?",
                    (gap["listing_id"], gap.get("seller_user_id"), field[:80], (gap.get("subject") or "")[:120],
                     now, now))
        conn.commit()


def gaps_for_seller(database_path: str, seller_user_id: str) -> List[Dict[str, Any]]:
    import sqlite3
    from contextlib import closing

    with closing(sqlite3.connect(database_path)) as conn:
        if not conn.execute("SELECT 1 FROM sqlite_master WHERE name='supply_gaps'").fetchone():
            return []
        rows = conn.execute("SELECT listing_id, field, subject, hits, last_seen FROM supply_gaps "
                            "WHERE seller_user_id=? ORDER BY hits DESC LIMIT 50", (seller_user_id,)).fetchall()
    return [{"listing_id": r[0], "field": r[1], "subject": r[2], "hits": r[3], "last_seen": r[4]} for r in rows]
