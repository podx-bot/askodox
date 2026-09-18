"""Seller AI assistant: turn one natural-language seller message into a listing draft."""
from __future__ import annotations

import re
from typing import Any


class SellerListingAssistant:
    # A price must be explicitly signalled. Bare product/model numbers such as
    # "iPhone 15" are not prices.
    _PRICE = re.compile(
        r"(?:₹\s*|rs\.?\s*|inr\s*|(?:price|for|at)\s+)(\d+(?:\.\d+)?)"
        r"\s*(?:/\s*([a-zA-Z]+))?",
        re.I,
    )
    _PREFIX_MARKERS = ("i sell", "i am selling", "sell ", "for sale")
    _TELUGU_MARKERS = ("అమ్ముతాను", "అమ్మాలి", "అమ్మకం")

    def __init__(self, category_repository=None):
        self.category_repository = category_repository

    def draft(self, message: str) -> dict[str, Any]:
        raw = " ".join(str(message or "").strip().split())
        if not raw:
            raise ValueError("message required")

        subject = raw
        folded = raw.casefold()
        for marker in self._PREFIX_MARKERS:
            index = folded.find(marker)
            if index >= 0:
                subject = raw[index + len(marker):].strip(" :-,")
                break
        else:
            # Telugu sell verbs normally follow the product, so keep the text
            # before the verb rather than the text after it.
            for marker in self._TELUGU_MARKERS:
                index = raw.find(marker)
                if index >= 0:
                    subject = raw[:index].strip(" :-,")
                    subject = re.sub(r"^నేను\s+", "", subject).strip()
                    break
            else:
                # "నా దగ్గర rice ₹60/kg" is a prefix-style availability phrase.
                marker = "నా దగ్గర"
                index = raw.find(marker)
                if index >= 0:
                    subject = raw[index + len(marker):].strip(" :-,")

        price = None
        unit = None
        match = self._PRICE.search(subject)
        remove_price_from_subject = match is not None
        if match is None:
            # Telugu seller phrasing keeps the price after the sell verb, while
            # subject extraction intentionally keeps only the product text.
            match = self._PRICE.search(raw)
        if match:
            price = float(match.group(1))
            unit = (match.group(2) or "").lower() or None
            if remove_price_from_subject:
                subject = (subject[:match.start()] + subject[match.end():]).strip(" ,-₹")

        subject = re.sub(r"\b(?:at|for|price)\s*$", "", subject, flags=re.I).strip(" ,-")
        category = self.category_repository.match(raw) if self.category_repository else None
        missing = []
        if not subject:
            missing.append("subject")
        if price is None:
            missing.append("price")

        return {
            "subject": subject or None,
            "price": price,
            "unit": unit,
            "category_tag": category["category_key"] if category else "COMMERCE",
            "missing_fields": missing,
            "ready_to_confirm": bool(subject),
            "source": "seller_ai_assistant",
        }

    @staticmethod
    def confirmation(draft: dict[str, Any]) -> str:
        subject = draft.get("subject") or "—"
        price = draft.get("price")
        unit = draft.get("unit")
        price_text = (
            "Price later"
            if price is None
            else f"₹{price:g}" + (f"/{unit}" if unit else "")
        )
        return f"Product: {subject}\nPrice: {price_text}\n\nSave this listing? Yes / Edit"
