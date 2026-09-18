"""Seller AI assistant: turn one natural-language seller message into a listing draft."""
from __future__ import annotations
import re
from typing import Any

class SellerListingAssistant:
    _PRICE = re.compile(r"(?:₹|rs\.?|inr)?\s*(\d+(?:\.\d+)?)\s*(?:/\s*([a-zA-Z]+))?", re.I)
    _SELL_MARKERS = ("i sell","i am selling","sell ","for sale","అమ్ముతాను","అమ్మాలి","అమ్మకం","నా దగ్గర")

    def __init__(self, category_repository=None):
        self.category_repository=category_repository

    def draft(self, message: str) -> dict[str, Any]:
        raw=" ".join(str(message or "").strip().split())
        if not raw: raise ValueError("message required")
        text=raw.casefold()
        subject=raw
        for marker in self._SELL_MARKERS:
            i=text.find(marker)
            if i >= 0:
                subject=raw[i+len(marker):].strip(" :-,")
                break
        price=None; unit=None
        match=self._PRICE.search(subject)
        if match:
            price=float(match.group(1)); unit=(match.group(2) or "").lower() or None
            subject=(subject[:match.start()]+subject[match.end():]).strip(" ,-₹")
        subject=re.sub(r"\b(?:at|for|price)\s*$","",subject,flags=re.I).strip(" ,-")
        category=self.category_repository.match(raw) if self.category_repository else None
        missing=[]
        if not subject: missing.append("subject")
        if price is None: missing.append("price")
        return {
            "subject": subject or None,
            "price": price,
            "unit": unit,
            "category_tag": (category["category_key"] if category else "COMMERCE"),
            "missing_fields": missing,
            "ready_to_confirm": bool(subject),
            "source": "seller_ai_assistant",
        }

    @staticmethod
    def confirmation(draft: dict[str, Any]) -> str:
        subject=draft.get("subject") or "—"
        price=draft.get("price")
        unit=draft.get("unit")
        price_text="Price later" if price is None else f"₹{price:g}" + (f"/{unit}" if unit else "")
        return f"Product: {subject}\nPrice: {price_text}\n\nSave this listing? Yes / Edit"
