"""Universal AI understanding layer for ASKODOX conversations.

The model is responsible for natural-language understanding and emits a small,
structured decision. Deterministic business modules still execute the action and
remain the source of truth for payments, bookings, matching and safety checks.
"""
from __future__ import annotations

import json
from typing import Any

from google import genai
from google.genai import types


class UniversalAIAssistantService:
    GENERAL_MARKER = "OASAT domain=GENERAL;"
    ALLOWED_DOMAINS = {
        "GENERAL", "JOB_SEEKER", "STAFFING", "SERVICE", "PARCEL", "RIDE",
        "PRODUCT", "FOOD", "EVENT", "APPOINTMENT", "LEDGER", "UNKNOWN",
    }

    def __init__(self, delegate, *, api_key: str, model: str, client: Any | None = None) -> None:
        self.delegate = delegate
        self.api_key = str(api_key or "").strip()
        self.model = str(model or "gemini-3.6-flash").strip()
        self.client = client or (genai.Client(api_key=self.api_key) if self.api_key else None)

    @property
    def configured(self) -> bool:
        return bool(self.client or self.api_key)

    def decide(self, message: str, *, history: list[dict[str, str]] | None = None, locale: str = "") -> dict[str, Any] | None:
        """Return a semantic decision for the in-app conversation.

        This deliberately distinguishes a person seeking a delivery job, an employer
        seeking delivery workers, and a parcel/courier request. New user wording should
        be handled by the model rather than by adding phrase-specific app rules.
        """
        clean = str(message or "").strip()
        if not clean or not self.configured:
            return None

        compact_history = []
        for turn in (history or [])[-12:]:
            role = str(turn.get("role", "") or "").strip().lower()
            text = str(turn.get("text", "") or "").strip()
            if role in {"user", "assistant"} and text:
                compact_history.append({"role": role, "text": text[:1200]})

        prompt = (
            "You are the semantic routing brain for ASKODOX, a natural AI assistant with optional local business actions. "
            "Understand meaning from the full conversation, not keyword matching. Return ONLY one JSON object with keys: "
            "reply, domain, transactional, action, confidence. domain must be one of GENERAL, JOB_SEEKER, STAFFING, SERVICE, "
            "PARCEL, RIDE, PRODUCT, FOOD, EVENT, APPOINTMENT, LEDGER, UNKNOWN. transactional is boolean. action is a short snake_case string. "
            "reply must answer naturally in the user's language or language mix. Do not claim a booking, payment, message, search or match happened. "
            "Important distinction: 'delivery job kavali' is JOB_SEEKER; 'delivery boys/staff kavali na shop ki' is STAFFING; "
            "'parcel/courier pampali' is PARCEL; temporary catering/function workers are STAFFING. General planning/chat is GENERAL. "
            "Use previous turns when the current message is a follow-up.\n"
            f"Locale hint: {locale or 'auto'}\n"
            f"Conversation history JSON: {json.dumps(compact_history, ensure_ascii=False)}\n"
            f"Current user message: {clean}"
        )
        try:
            client = self.client or genai.Client(api_key=self.api_key)
            response = client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.15,
                    max_output_tokens=700,
                    response_mime_type="application/json",
                ),
            )
            raw = str(getattr(response, "text", "") or "").strip()
            data = json.loads(raw)
            if not isinstance(data, dict):
                return None
            domain = str(data.get("domain", "UNKNOWN") or "UNKNOWN").upper().strip()
            if domain not in self.ALLOWED_DOMAINS:
                domain = "UNKNOWN"
            reply = str(data.get("reply", "") or "").strip()
            action = str(data.get("action", "") or "").strip().lower()[:80]
            confidence = float(data.get("confidence", 0.0) or 0.0)
            confidence = max(0.0, min(1.0, confidence))
            transactional = bool(data.get("transactional", domain not in {"GENERAL", "UNKNOWN"}))
            if not reply:
                return None
            return {
                "reply": reply,
                "domain": domain,
                "transactional": transactional,
                "action": action,
                "confidence": confidence,
            }
        except Exception:
            return None

    def process(self, sender_mobile: str, message: str) -> str:
        clean = str(message or "").strip()
        if self.GENERAL_MARKER not in clean:
            return self._delegate(sender_mobile, clean)
        decision = self.decide(clean)
        if decision is not None and not decision["transactional"]:
            return str(decision["reply"])
        return self._delegate(sender_mobile, clean)

    def _delegate(self, sender_mobile: str, message: str) -> str:
        try:
            return self.delegate.process(sender_mobile=sender_mobile, message=message)
        except TypeError:
            return self.delegate.process(sender_mobile, message)
