"""History context builder for ASKODOX OASAT repeat-purchase reasoning."""
from __future__ import annotations

from typing import Any

from app.repositories.purchase_history_repository import PurchaseHistoryRepository


class OASATHistoryContext:
    def __init__(self, purchase_history: PurchaseHistoryRepository) -> None:
        self.purchase_history = purchase_history

    def for_item(self, user_id: str, item_name: str) -> dict[str, Any]:
        recall = self.purchase_history.repeat_context(user_id, item_name)
        if recall is None:
            return {
                "has_history": False,
                "item_name": item_name,
                "signals": [],
            }

        signals: list[str] = []
        usage_days = recall.get("usage_days")
        repeat_days = recall.get("repeat_cycle_days")
        remaining = recall.get("remaining_status")

        if usage_days:
            signals.append(f"last_quantity_lasted_{int(usage_days)}_days")
        if repeat_days:
            signals.append(f"repeat_cycle_{int(repeat_days)}_days")
        if remaining == "FINISHED":
            signals.append("last_purchase_finished")
        elif remaining == "REMAINING":
            signals.append("last_purchase_has_remaining_stock")
        if recall.get("seller_name"):
            signals.append("previous_seller_available_for_comparison")
        if recall.get("preference_note"):
            signals.append("saved_preference_available")
        if recall.get("conversation_rationale"):
            signals.append("saved_purchase_rationale_available")

        return {
            "has_history": True,
            "item_name": recall["item_name"],
            "last_purchase": recall,
            "signals": signals,
            "reasoning_hint": self._reasoning_hint(recall),
        }

    @staticmethod
    def _reasoning_hint(recall: dict[str, Any]) -> str:
        quantity = recall.get("last_quantity")
        unit = recall.get("unit") or "units"
        usage_days = recall.get("usage_days")
        remaining = recall.get("remaining_status")

        if usage_days and remaining == "FINISHED":
            return (
                f"Previous {quantity:g} {unit} was finished in {int(usage_days)} days; "
                "use that duration as a baseline before recommending the next quantity."
            )
        if remaining == "REMAINING":
            return (
                f"Previous {quantity:g} {unit} still had stock remaining; "
                "avoid automatically increasing the next quantity."
            )
        return (
            "Use the previous quantity, price, seller, preferences and purchase rationale "
            "as comparison context, but confirm current need before taking action."
        )
