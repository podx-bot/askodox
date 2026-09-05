"""Repeat-purchase recommendation logic for ASKODOX OASAT.

Uses structured purchase/usage memory as evidence, but keeps the user in control:
recommendations are advisory and require a current target duration before scaling
quantity.
"""
from __future__ import annotations

from typing import Any

from app.services.oasat_history_context import OASATHistoryContext


class OASATRepeatPurchaseAdvisor:
    def __init__(self, history_context: OASATHistoryContext) -> None:
        self.history_context = history_context

    def recommend(
        self,
        user_id: str,
        item_name: str,
        *,
        target_days: int | None = None,
        current_unit_price: float | None = None,
    ) -> dict[str, Any]:
        context = self.history_context.for_item(user_id, item_name)
        if not context.get("has_history"):
            return {
                "has_history": False,
                "item_name": item_name,
                "recommendation_status": "NEED_CURRENT_REQUIREMENTS",
                "reason": "No previous purchase history is available for this item.",
            }

        last = context["last_purchase"]
        last_qty = float(last["last_quantity"])
        unit = last.get("unit") or "units"
        usage_days = last.get("usage_days")
        remaining = last.get("remaining_status")

        response: dict[str, Any] = {
            "has_history": True,
            "item_name": last["item_name"],
            "previous_quantity": last_qty,
            "unit": unit,
            "previous_unit_price": last.get("last_unit_price"),
            "previous_seller": last.get("seller_name"),
            "preference_note": last.get("preference_note"),
            "signals": context.get("signals", []),
        }

        if current_unit_price is not None:
            current_price = round(float(current_unit_price), 2)
            response["current_unit_price"] = current_price
            previous_price = last.get("last_unit_price")
            if previous_price is not None:
                response["unit_price_change"] = round(current_price - float(previous_price), 2)

        if target_days is None or int(target_days) <= 0:
            response.update(
                {
                    "recommendation_status": "NEED_TARGET_DURATION",
                    "reason": (
                        "History is available. Ask how long the next purchase should last "
                        "before changing quantity."
                    ),
                }
            )
            return response

        target = int(target_days)
        response["target_days"] = target

        if usage_days and int(usage_days) > 0 and remaining == "FINISHED":
            recommended = round(last_qty * target / int(usage_days), 2)
            response.update(
                {
                    "recommendation_status": "RECOMMENDED_FROM_USAGE_HISTORY",
                    "recommended_quantity": recommended,
                    "reason": (
                        f"Last {last_qty:g} {unit} lasted {int(usage_days)} days and was finished; "
                        f"scaled proportionally for {target} days."
                    ),
                }
            )
            if current_unit_price is not None:
                response["estimated_total"] = round(recommended * float(current_unit_price), 2)
            return response

        if remaining == "REMAINING":
            response.update(
                {
                    "recommendation_status": "DO_NOT_AUTO_INCREASE",
                    "recommended_quantity": last_qty,
                    "reason": (
                        "The previous purchase still had stock remaining, so ASKODOX should not "
                        "automatically increase the quantity. Confirm current stock/need first."
                    ),
                }
            )
            return response

        response.update(
            {
                "recommendation_status": "NEED_USAGE_FEEDBACK",
                "recommended_quantity": last_qty,
                "reason": (
                    "Previous quantity is known, but usage duration/remaining-stock evidence is "
                    "insufficient. Use it as a baseline and ask for current need."
                ),
            }
        )
        return response
