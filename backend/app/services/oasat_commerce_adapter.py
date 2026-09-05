"""Live commerce adapter for ASKODOX OASAT.

Combines structured purchase memory, repeat-quantity reasoning, and fresh offer
comparison. Current offers remain caller supplied: historical prices are never
presented as live prices.
"""
from __future__ import annotations
from typing import Any
from app.services.oasat_repeat_purchase_advisor import OASATRepeatPurchaseAdvisor
from app.services.oasat_offer_recommendation_service import OASATOfferRecommendationService


class OASATCommerceAdapter:
    def __init__(self, repeat: OASATRepeatPurchaseAdvisor, offers: OASATOfferRecommendationService) -> None:
        self.repeat = repeat
        self.offers = offers

    def solve(self, user_id: str, item_name: str, *, target_days: int | None = None,
              local_offers: list[dict[str, Any]] | None = None,
              online_offers: list[dict[str, Any]] | None = None,
              urgency: str = "NORMAL") -> dict[str, Any]:
        fresh_local = local_offers or []
        fresh_online = online_offers or []
        current_prices = [x.get("price") for x in fresh_local + fresh_online if x.get("price") is not None]
        current_unit_price = min(current_prices) if current_prices else None
        repeat = self.repeat.recommend(user_id, item_name, target_days=target_days,
                                       current_unit_price=current_unit_price)
        offer = self.offers.recommend(user_id, item_name, local_offers=fresh_local,
                                      online_offers=fresh_online, urgency=urgency)
        return {
            "domain": "COMMERCE", "item_name": item_name,
            "repeat_purchase": repeat, "offer_recommendation": offer,
            "needs_fresh_offers": not bool(fresh_local or fresh_online),
            "approval_required_before_action": True,
            "rule": "Use memory for context and quantity reasoning; use only fresh supplied offers for current seller/price claims.",
        }
