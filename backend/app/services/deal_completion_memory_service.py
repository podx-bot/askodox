"""Write completed commerce deals into structured ASKODOX purchase memory.

This is the bridge between deal completion and OASAT history. It is deliberately
strict: only a completed/closed commerce purchase with concrete quantity and
price becomes purchase memory. Other domains keep their own history adapters.
"""
from __future__ import annotations

from typing import Any

from app.repositories.purchase_history_repository import PurchaseHistoryRepository


class DealCompletionMemoryService:
    COMPLETE = {"COMPLETED", "COMPLETE", "CLOSED", "FINISHED"}
    COMMERCE = {"COMMERCE", "FOOD", "GROCERY", "PRODUCT", "SHOPPING"}

    def __init__(self, purchases: PurchaseHistoryRepository) -> None:
        self.purchases = purchases

    def _existing_source_reference(self, source_reference: str) -> int | None:
        """Return the existing purchase id for a completed deal callback.

        Deal status callbacks can be retried by the app/network. Purchase memory
        must therefore be idempotent by the stable deal id rather than creating
        another history row on every retry.
        """
        with self.purchases._connect() as conn:
            row = conn.execute(
                f"SELECT id FROM {self.purchases.TABLE} WHERE source_reference=? ORDER BY id ASC LIMIT 1",
                (source_reference,),
            ).fetchone()
        return int(row["id"]) if row else None

    def record(self, deal: dict[str, Any]) -> dict[str, Any]:
        status = str(deal.get("status") or "").strip().upper()
        domain = str(deal.get("domain") or deal.get("category") or "").strip().upper()
        intent = str(deal.get("intent") or "BUY").strip().upper()
        if status not in self.COMPLETE:
            return {"recorded": False, "reason": "deal_not_completed"}
        if domain not in self.COMMERCE or intent not in {"BUY", "PURCHASE"}:
            return {"recorded": False, "reason": "not_purchase_memory_domain"}

        source_reference = str(deal.get("deal_id")) if deal.get("deal_id") is not None else None
        if source_reference:
            existing_id = self._existing_source_reference(source_reference)
            if existing_id is not None:
                return {
                    "recorded": False,
                    "purchase_id": existing_id,
                    "reason": "purchase_memory_already_recorded",
                }

        user_id = deal.get("buyer_id") or deal.get("user_id")
        item = deal.get("item_name") or deal.get("subject")
        quantity = deal.get("quantity")
        unit_price = deal.get("unit_price")
        if unit_price is None and deal.get("agreed_price") is not None and quantity:
            unit_price = float(deal["agreed_price"]) / float(quantity)
        if not user_id or not item or quantity is None or unit_price is None:
            return {"recorded": False, "reason": "missing_purchase_facts"}

        purchase_id = self.purchases.add_purchase(
            str(user_id), item_name=str(item), quantity=float(quantity), unit_price=float(unit_price),
            seller_id=deal.get("seller_id"), seller_name=deal.get("seller_name"), unit=deal.get("unit"),
            purchased_at=deal.get("completed_at") or deal.get("purchased_at"),
            preference_note=deal.get("preference_note"),
            conversation_rationale=deal.get("conversation_rationale"),
            source_reference=source_reference,
        )
        return {"recorded": True, "purchase_id": purchase_id, "reason": "completed_purchase_recorded"}
