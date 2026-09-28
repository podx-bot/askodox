"""Which verified benefits apply to a result, and what they are worth.

Only campaigns that exist as rows (admin-entered from a source, partner
feed/API or import) are ever shown. A value is computed only from the
result's real price and the campaign's own numbers; conditions (payment
method, minimum purchase, expiry, per-user limit) are always returned with
it. The engine never calls anything "best": it returns a factual list
(highest computed value first) and says when values are not comparable.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional

KIND_BY_TYPE = {
    "bank_card": "instant_discount", "upi_wallet": "instant_discount", "merchant_brand": "discount",
    "affiliate_partner": "discount", "coupon": "coupon", "cashback": "cashback", "askodox_credit": "credit",
    "referral_reward": "credit", "free_gift": "gift", "scratch_reward": "reward", "other": "benefit",
}


def _parse(value: Any) -> Optional[datetime]:
    try:
        moment = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def live(campaign: Dict[str, Any], now: datetime | None = None) -> bool:
    now = now or datetime.now(timezone.utc)
    if not campaign.get("active"):
        return False
    start, end = _parse(campaign.get("starts_at")), _parse(campaign.get("ends_at"))
    if start and now < start:
        return False
    if end and now > end:
        return False
    # External offers must be verified (a source and a verification time).
    if campaign.get("offer_type") in {"bank_card", "upi_wallet", "merchant_brand", "affiliate_partner"} and not (
            campaign.get("source_url") and campaign.get("verified_at")):
        return False
    return True


def benefit_value(campaign: Dict[str, Any], price: float | None) -> Optional[float]:
    """Money value for this price, or None when it cannot be computed."""
    def num(key: str) -> Optional[float]:
        value = campaign.get(key)
        try:
            return float(value) if value not in (None, "") else None
        except (TypeError, ValueError):
            return None

    amount, percent = num("discount_amount"), num("discount_percent")
    cash_amount, cash_percent = num("cashback_amount"), num("cashback_percent")
    credit, cap = num("credit_amount"), num("max_discount")
    if amount is not None:
        return amount
    if cash_amount is not None:
        return cash_amount
    if credit is not None:
        return credit
    rate = percent if percent is not None else cash_percent
    if rate is not None and price:
        value = round(float(price) * rate / 100, 2)
        return min(value, cap) if cap is not None else value
    return None


def applies(campaign: Dict[str, Any], *, category: str = "", subject: str = "", location: str = "",
            country: str = "IN", partner_id: int | None = None) -> bool:
    countries = [str(c).upper() for c in campaign.get("countries") or [] if str(c).strip()]
    if countries and "ALL" not in countries and country.upper() not in countries:
        return False
    locations = [str(c).casefold() for c in campaign.get("locations") or [] if str(c).strip()]
    if locations and location and not any(loc in location.casefold() for loc in locations):
        return False
    if campaign.get("partner_id") and campaign["partner_id"] != partner_id:
        return False  # a partner's own offer applies to that partner's results only
    wanted = f"{category} {subject}".casefold()
    cats = [str(c).casefold() for c in campaign.get("categories") or [] if str(c).strip()]
    words = [str(c).casefold() for c in campaign.get("keywords") or [] if str(c).strip()]
    if cats and "all" not in cats and not any(c in wanted or (category and category.casefold() in c) for c in cats):
        return False
    if words and not any(w in wanted for w in words):
        return False
    return True


def evaluate(campaigns: Iterable[Dict[str, Any]], *, price: float | None, category: str = "", subject: str = "",
             location: str = "", country: str = "IN", partner_id: int | None = None,
             now: datetime | None = None, limit: int = 3) -> Dict[str, Any]:
    offers: List[Dict[str, Any]] = []
    for campaign in campaigns:
        if campaign.get("offer_type") == "scratch_reward" or not live(campaign, now):
            continue
        if not applies(campaign, category=category, subject=subject, location=location, country=country,
                       partner_id=partner_id):
            continue
        minimum = campaign.get("min_purchase")
        if minimum not in (None, "") and price is not None and float(price) < float(minimum):
            continue  # not eligible at this price
        conditions = []
        if campaign.get("payment_methods"):
            conditions.append({"type": "payment_method", "value": list(campaign["payment_methods"])})
        if minimum not in (None, ""):
            conditions.append({"type": "min_purchase", "value": float(minimum)})
        if campaign.get("max_discount") not in (None, ""):
            conditions.append({"type": "max_discount", "value": float(campaign["max_discount"])})
        if int(campaign.get("per_user_limit") or 1) >= 1:
            conditions.append({"type": "per_user_limit", "value": int(campaign.get("per_user_limit") or 1)})
        offers.append({
            "id": campaign["id"], "name": campaign["name"], "provider": campaign.get("provider_name") or "",
            "type": campaign["offer_type"], "kind": KIND_BY_TYPE.get(campaign["offer_type"], "benefit"),
            "value": benefit_value(campaign, price), "percent": campaign.get("discount_percent")
            or campaign.get("cashback_percent"), "free_benefit": campaign.get("free_benefit"),
            "conditions": conditions, "expires_at": campaign.get("ends_at"),
            "verified_at": campaign.get("verified_at"), "source_url": campaign.get("source_url"),
            "funding": campaign.get("funding_source"), "claimable": campaign["offer_type"] in
            {"coupon", "askodox_credit", "cashback", "free_gift"},
        })
    offers.sort(key=lambda o: (o["value"] is None, -(o["value"] or 0)))
    comparable = [o for o in offers if o["value"] is not None]
    return {
        "offers": offers[:limit],
        "more": max(0, len(offers) - limit),
        # Honest comparison: never "best" -- values differ by conditions.
        "comparison_note": ("Values depend on each offer's conditions (payment method, minimum purchase, limits)."
                            if len(comparable) >= 2 else ""),
    }


def scratch_reward(campaigns: Iterable[Dict[str, Any]], *, category: str = "", country: str = "IN",
                   now: datetime | None = None) -> Optional[Dict[str, Any]]:
    """Deterministic: the highest-priority live scratch_reward campaign that
    applies (no randomness, no lottery). Its configured value is the reward."""
    for campaign in sorted(campaigns, key=lambda c: (-int(c.get("priority") or 0), c["id"])):
        if campaign.get("offer_type") != "scratch_reward" or not live(campaign, now):
            continue
        if applies(campaign, category=category, country=country):
            return campaign
    return None
