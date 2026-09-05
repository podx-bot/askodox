"""OASAT seller/offer recommendation using purchase memory plus current offers."""
from __future__ import annotations

from typing import Any

from app.services.buyer_intelligence_service import BuyerIntelligenceService
from app.services.oasat_history_context import OASATHistoryContext


class OASATOfferRecommendationService:
    """Combine repeat-purchase memory with fresh comparable seller offers.

    The service never invents current prices: callers must supply current offers.
    History is used as decision context, not as a substitute for fresh facts.
    """

    def __init__(
        self,
        history: OASATHistoryContext,
        buyer_intelligence: BuyerIntelligenceService | None = None,
    ) -> None:
        self.history = history
        self.buyer_intelligence = buyer_intelligence or BuyerIntelligenceService()

    def recommend(
        self,
        user_id: str,
        item_name: str,
        *,
        local_offers: list[dict[str, Any]],
        online_offers: list[dict[str, Any]] | None = None,
        urgency: str = "NORMAL",
    ) -> dict[str, Any]:
        memory = self.history.for_item(user_id, item_name)
        comparison = self.buyer_intelligence.compare_offers(
            local_offers,
            online_offers or [],
            urgency=urgency,
        )
        best = comparison.get("best")
        previous = memory.get("last_purchase") if memory.get("has_history") else None

        reasons: list[str] = []
        if best is None:
            reasons.append("fresh_comparable_offer_required")
        else:
            reasons.append("ranked_by_current_offer_value")
            if best.get("verified_seller"):
                reasons.append("verified_seller")
            if best.get("exact_variant"):
                reasons.append("exact_variant")
            if best.get("service_available"):
                reasons.append("service_available")

        history_comparison = self._history_comparison(previous, best)
        reasons.extend(history_comparison["signals"])

        return {
            "item_name": item_name,
            "history": memory,
            "current_offer_comparison": comparison,
            "best_offer": best,
            "history_comparison": history_comparison,
            "recommendation": comparison.get("recommendation"),
            "reason_codes": reasons,
            "guardrail": (
                "Previous price/seller are historical context only; confirm current price, "
                "availability and exact item before user approval or action."
            ),
        }

    @staticmethod
    def _history_comparison(
        previous: dict[str, Any] | None,
        best: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if previous is None:
            return {"has_previous_purchase": False, "signals": []}

        signals: list[str] = ["previous_purchase_available"]
        result: dict[str, Any] = {
            "has_previous_purchase": True,
            "previous_seller": previous.get("seller_name"),
            "previous_unit_price": previous.get("last_unit_price"),
            "signals": signals,
        }
        if best is None:
            return result

        current_price = best.get("price")
        old_price = previous.get("last_unit_price")
        if current_price is not None and old_price is not None:
            try:
                delta = round(float(current_price) - float(old_price), 2)
                result["price_delta_vs_previous"] = delta
                if delta < 0:
                    signals.append("current_price_lower_than_previous")
                elif delta > 0:
                    signals.append("current_price_higher_than_previous")
                else:
                    signals.append("current_price_same_as_previous")
            except (TypeError, ValueError):
                pass

        current_seller = best.get("seller_name") or best.get("seller")
        previous_seller = previous.get("seller_name")
        if current_seller and previous_seller:
            if str(current_seller).strip().casefold() == str(previous_seller).strip().casefold():
                signals.append("previous_seller_ranked_best_again")
            else:
                signals.append("different_seller_ranked_best")
        return result
