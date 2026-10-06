"""Price provenance and budget truth.

A web snippet / page can mention several rupee amounts: an MRP, the selling
price, an offer price, a price that applies only with a bank card / coupon /
exchange, a "starting from" price for the cheapest variant, or just an
amount somewhere on the page. ASKODOX must never present a conditional or
starting price as THE price of the matched product.

``classify(*texts)`` returns:
  price            the amount to show as the row's price (selling / page
                   level / starting-from), or None
  price_kind       list | selling | offer | starting_from | page_level |
                   variant_verified (set by verified sources, never here)
  list_price       MRP / list price when stated
  offer_price      a price that needs a condition (bank / coupon / exchange)
  offer_condition  short text of that condition ("HDFC card", "exchange")
``budget_fit(row, budget_max, budget_min)`` -> within | within_with_offer |
over | unknown (unknown = no usable price; never assumed to fit).
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional

_AMOUNT = r"(?:₹|rs\.?|inr)\s*([0-9][0-9,]{2,})(?:\.\d+)?"
_MRP = re.compile(r"\b(?:m\.?r\.?p\.?|list price|maximum retail price)\s*[:\-]?\s*(?:of\s*)?" + _AMOUNT, re.I)
_STARTING = re.compile(r"\b(?:starting|starts)\s*(?:at|from|@)?\s*" + _AMOUNT + r"|\bfrom\s*" + _AMOUNT
                       + r"(?!\s*(?:with|using))|" + _AMOUNT + r"\s*(?:onwards|and above|\+)", re.I)
_CONDITIONAL = re.compile(
    r"(?:effective price|net effective price|price after (?:bank )?(?:offer|discount)|with (?:bank )?offers?)\s*"
    r"(?:of|:|-|is)?\s*" + _AMOUNT
    + r"|" + _AMOUNT + r"\s*(?:\*\s*)?(?:with|using|on)\s+((?:[a-z]+\s){0,3}(?:bank|credit|debit|card|cards|coupon|exchange|emi|upi)[a-z ]{0,25})",
    re.I)
_CONDITION_WORDS = re.compile(
    r"\b((?:hdfc|icici|sbi|axis|kotak|idfc|bob|rbl|yes bank|amex|onecard|au)\s+(?:bank\s+)?(?:credit|debit)?\s*cards?"
    r"|bank offer|coupon|exchange|no[- ]cost emi|upi offer)\b", re.I)
_OFFER = re.compile(r"\b(?:deal price|offer price|special price|sale price|discounted price|now)\s*[:\-]?\s*" + _AMOUNT, re.I)
_ANY = re.compile(_AMOUNT, re.I)


def _num(match_group: Optional[str]) -> Optional[float]:
    if not match_group:
        return None
    try:
        return float(match_group.replace(",", ""))
    except ValueError:
        return None


def _first_group(m: re.Match) -> Optional[float]:
    for g in m.groups():
        if g and re.fullmatch(r"[0-9][0-9,]*", g):
            return _num(g)
    return None


def classify(*texts: Any) -> Dict[str, Any]:
    text = " ".join(str(t or "") for t in texts)
    out: Dict[str, Any] = {"price": None, "price_kind": None, "list_price": None, "offer_price": None,
                           "offer_condition": None}
    if not _ANY.search(text):
        return out
    used: List[tuple] = []

    m = _MRP.search(text)
    if m:
        out["list_price"] = _first_group(m)
        used.append(m.span())
    cond = _CONDITIONAL.search(text)
    if cond:
        out["offer_price"] = _first_group(cond)
        words = _CONDITION_WORDS.search(text)
        trailing = next((g for g in cond.groups()[1:] if g and not re.fullmatch(r"[0-9][0-9,]*", g)), None)
        out["offer_condition"] = (words.group(1) if words else (trailing or "eligible offer")).strip().lower()
        used.append(cond.span())
    offer = _OFFER.search(text)
    start = _STARTING.search(text)

    def unused(m2: re.Match) -> bool:
        return all(not (a <= m2.start() < b) for a, b in used)

    if offer and unused(offer):
        out["price"], out["price_kind"] = _first_group(offer), "offer"
    elif start and unused(start):
        out["price"], out["price_kind"] = _first_group(start), "starting_from"
    else:
        rest = [x for x in _ANY.finditer(text) if unused(x)]
        if rest:
            out["price"], out["price_kind"] = _num(rest[0].group(1)), "page_level"
        elif out["list_price"] is not None and out["offer_price"] is None:
            out["price"], out["price_kind"] = out["list_price"], "list"
    if out["list_price"] and out["price"] and out["list_price"] < out["price"]:
        out["list_price"] = None  # an "MRP" lower than the price is a mis-parse
    return out


def budget_fit(row: Dict[str, Any], budget_max: Optional[float], budget_min: Optional[float] = None) -> str:
    if budget_max is None and budget_min is None:
        return "unknown"
    price = row.get("price")
    try:
        price = float(price) if price is not None else None
    except (TypeError, ValueError):
        price = None
    kind = row.get("price_kind")
    offer = row.get("offer_price")
    if price is None and offer is None:
        return "unknown"
    if budget_min is not None and price is not None and price < budget_min:
        return "over"  # outside the asked range (below it)
    if budget_max is None:
        return "within"
    if price is not None and price <= budget_max:
        # A "starting from" price fits only the cheapest variant -- never
        # shown as the matched product's price.
        return "unknown" if kind == "starting_from" else "within"
    if offer is not None and float(offer) <= budget_max:
        return "within_with_offer"
    return "over"


_STRICT = re.compile(r"\b(only|strictly|max(?:imum)?|not more than|no more than|or (?:below|less) only|at most)\b"
                     r"|మాత్రమే|ఎక్కువ కాదు|से ज़्यादा नहीं|सिर्फ", re.I)


def is_strict(said: str) -> bool:
    return bool(_STRICT.search(said or ""))


def annotate(matches: Iterable[Dict[str, Any]], *, budget_max: Optional[float], budget_min: Optional[float] = None,
             strict: bool = False) -> Dict[str, Any]:
    """Adds ``budget_fit`` to priced rows; with ``strict`` removes rows that
    are over budget (and rows whose only price is conditional stay, labelled).
    Returns {"kept": [...], "rejected": [{id, title, reason}]}."""
    kept: List[Dict[str, Any]] = []
    rejected: List[Dict[str, Any]] = []
    for row in matches:
        if budget_max is not None or budget_min is not None:
            fit = budget_fit(row, budget_max, budget_min)
            row["budget_fit"] = fit
            if strict and fit == "over" and row.get("source") not in ("video", "content"):
                rejected.append({"id": row.get("id"), "title": row.get("title"), "reason": "over_budget_strict",
                                 "price": row.get("price"), "price_kind": row.get("price_kind")})
                continue
        kept.append(row)
    # Within budget first, then within-with-offer, then unknown, then over
    # (stable: the source order is kept inside each group).
    rank = {"within": 0, "within_with_offer": 1, "unknown": 2, "over": 3}
    if budget_max is not None or budget_min is not None:
        kept.sort(key=lambda r: rank.get(r.get("budget_fit") or "unknown", 2)
                  if r.get("source") not in ("video", "content") else 0)
    return {"kept": kept, "rejected": rejected}
