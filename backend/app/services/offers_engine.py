"""Rule-based offers / promotions -- one engine for every seller, provider
and admin campaign. No promotion is hard-coded: an offer is a row with a
``rule_type`` and parameters, evaluated here against an order context.

Rule types (params):
- percent            {"percent": 10, "max_discount": 500?}
- fixed              {"amount": 200}
- buy_x_get_y        {"buy": 1, "get": 1}               (BOGO = 1+1)
- free_item          {"item": "raita"}                   (no price change)
- combo              {"items": [...], "combo_price": 499}
- quantity           {"min_qty": 5, "percent": 8}
- first_order        {"percent"|"amount"}                (buyer's first order)
- repeat_customer    {"percent"|"amount", "min_orders": 1}
- free_delivery      {}                                  (delivery fee waived)
- festival / limited_time / referral  {"percent"|"amount"} (dated campaigns)

All offers may carry ``min_order`` and a validity window. Discounts never
exceed the order total and never go negative. Dependency-free for testing.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable

RULE_TYPES = (
    "percent", "fixed", "buy_x_get_y", "free_item", "combo", "quantity", "first_order",
    "repeat_customer", "free_delivery", "festival", "limited_time", "referral",
)
_VALUE_RULES = {"first_order", "repeat_customer", "festival", "limited_time", "referral"}


class OfferError(ValueError):
    """An offer definition that cannot be evaluated."""


def validate(rule_type: str, params: dict[str, Any]) -> dict[str, Any]:
    rule = str(rule_type or "").strip().lower()
    if rule not in RULE_TYPES:
        raise OfferError(f"Unknown offer rule: {rule_type}")
    p = dict(params or {})

    def num(key: str, *, required: bool = True, positive: bool = True) -> float | None:
        value = p.get(key)
        if value in (None, ""):
            if required:
                raise OfferError(f"{rule} offer needs '{key}'")
            return None
        try:
            number = float(value)
        except (TypeError, ValueError) as error:
            raise OfferError(f"'{key}' must be a number") from error
        if positive and number <= 0:
            raise OfferError(f"'{key}' must be greater than 0")
        return number

    if rule == "percent":
        if not 0 < (num("percent") or 0) <= 90:
            raise OfferError("percent must be between 0 and 90")
        num("max_discount", required=False)
    elif rule == "fixed":
        num("amount")
    elif rule == "buy_x_get_y":
        num("buy"), num("get")
    elif rule == "free_item":
        if not str(p.get("item") or "").strip():
            raise OfferError("free_item offer needs 'item'")
    elif rule == "combo":
        num("combo_price")
    elif rule == "quantity":
        num("min_qty"), num("percent")
    elif rule in _VALUE_RULES:
        if p.get("percent") in (None, "") and p.get("amount") in (None, ""):
            raise OfferError(f"{rule} offer needs 'percent' or 'amount'")
        num("percent", required=False), num("amount", required=False)
    num("min_order", required=False)
    return p


def _active(offer: dict[str, Any], now: datetime) -> bool:
    if not offer.get("active", True):
        return False
    for key, check in (("starts_at", lambda t: now >= t), ("ends_at", lambda t: now <= t)):
        raw = offer.get(key)
        if raw:
            try:
                moment = datetime.fromisoformat(str(raw))
            except ValueError:
                return False
            if moment.tzinfo is None:
                moment = moment.replace(tzinfo=timezone.utc)
            if not check(moment):
                return False
    return True


def _value_discount(params: dict[str, Any], total: float) -> float:
    if params.get("percent") not in (None, ""):
        return total * float(params["percent"]) / 100.0
    return float(params.get("amount") or 0)


def evaluate(offer: dict[str, Any], ctx: dict[str, Any], now: datetime | None = None) -> dict[str, Any] | None:
    """The benefit of ONE offer for an order context, or None when it does
    not apply. ctx: unit_price, quantity, prior_orders, referred (bool)."""
    now = now or datetime.now(timezone.utc)
    if not _active(offer, now):
        return None
    rule = str(offer.get("rule_type") or "")
    params = offer.get("params") or {}
    unit = float(ctx.get("unit_price") or 0)
    qty = max(1.0, float(ctx.get("quantity") or 1))
    total = unit * qty
    if params.get("min_order") and total < float(params["min_order"]):
        return None
    prior = int(ctx.get("prior_orders") or 0)
    discount, note = 0.0, ""
    if rule == "percent":
        discount = total * float(params["percent"]) / 100.0
        if params.get("max_discount"):
            discount = min(discount, float(params["max_discount"]))
        note = f"{float(params['percent']):g}% off"
    elif rule == "fixed":
        discount, note = float(params["amount"]), f"₹{float(params['amount']):g} off"
    elif rule == "buy_x_get_y":
        buy, get = int(params["buy"]), int(params["get"])
        free_units = int(qty // (buy + get)) * get
        if free_units <= 0:
            return None
        discount, note = free_units * unit, f"Buy {buy} get {get} free"
    elif rule == "free_item":
        note = f"Free {params['item']}"
    elif rule == "combo":
        combo = float(params["combo_price"])
        if total <= combo:
            return None
        discount, note = total - combo, f"Combo price ₹{combo:g}"
    elif rule == "quantity":
        if qty < float(params["min_qty"]):
            return None
        discount = total * float(params["percent"]) / 100.0
        note = f"{float(params['percent']):g}% off on {int(float(params['min_qty']))}+"
    elif rule == "first_order":
        if prior > 0:
            return None
        discount, note = _value_discount(params, total), "First-order offer"
    elif rule == "repeat_customer":
        if prior < int(params.get("min_orders") or 1):
            return None
        discount, note = _value_discount(params, total), "Repeat-customer offer"
    elif rule == "referral":
        if not ctx.get("referred"):
            return None
        discount, note = _value_discount(params, total), "Referral benefit"
    elif rule in {"festival", "limited_time"}:
        discount = _value_discount(params, total)
        note = str(offer.get("title") or ("Festival offer" if rule == "festival" else "Limited-time offer"))
    elif rule == "free_delivery":
        note = "Free delivery"
    else:
        return None
    discount = round(max(0.0, min(discount, total)), 2)
    return {"offer_id": offer.get("id"), "rule_type": rule, "title": offer.get("title") or note,
            "note": note, "discount": discount, "free_delivery": rule == "free_delivery"}


def best_offer(offers: Iterable[dict[str, Any]], ctx: dict[str, Any],
               now: datetime | None = None) -> dict[str, Any] | None:
    """The single most valuable applicable offer (offers do not stack)."""
    results = [r for r in (evaluate(o, ctx, now) for o in offers) if r]
    if not results:
        return None
    return max(results, key=lambda r: (r["discount"], r["free_delivery"], r["title"] != ""))
