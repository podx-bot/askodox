"""Universal AI understanding layer for ASKODOX conversations.

The model is responsible for natural-language understanding and emits a small,
structured decision. Deterministic business modules still execute the action and
remain the source of truth for payments, bookings, matching and safety checks.
"""
from __future__ import annotations

import json
import re
from typing import Any

from google import genai
from google.genai import types


class UniversalAIAssistantService:
    GENERAL_MARKER = "OASAT domain=GENERAL;"
    ALLOWED_DOMAINS = {
        "GENERAL", "JOB_SEEKER", "STAFFING", "SERVICE", "PARCEL", "RIDE",
        "PRODUCT", "FOOD", "EVENT", "APPOINTMENT", "LEDGER", "UNKNOWN",
    }
    ALLOWED_ENTITY_KEYS = {
        "subject", "category", "role", "skill", "quantity", "unit", "headcount",
        "date", "time", "timing", "location", "from", "to", "budget", "price",
        "salary", "pay", "pay_basis", "duration", "shift", "context", "variant",
        "quality", "size", "model", "fulfilment", "availability", "specialist",
        "service_type", "job_type", "seats", "notes",
    }
    # Phrases that indicate the model's reply is asking the user for their
    # location/address, in the language mixes ASKODOX users actually type in.
    _LOCATION_ASK_KEYWORDS = (
        "location", "your address", "delivery address", "delivery location",
        "which area", "which place",
        "లొకేషన్", "లొకేషన", "చిరునామా", "ఎక్కడ ఉన్నారు", "ఎక్కడ నుండి",
        "ఎక్కడ తెలియ", "ఎక్కడ చెప్ప", "ఎక్కడో", "పిన్ కోడ్", "పిన్‌కోడ్",
    )
    _LOCATION_FALLBACK_REPLY = {
        "te": "సరే, మీ సేవ్ చేసిన లొకేషన్ ఉపయోగించి కొనసాగిస్తున్నాను.",
        "en": "Got it — continuing with your saved location.",
    }

    def __init__(self, delegate, *, api_key: str, model: str, client: Any | None = None) -> None:
        self.delegate = delegate
        self.api_key = str(api_key or "").strip()
        self.model = str(model or "gemini-3.6-flash").strip()
        self.client = client or (genai.Client(api_key=self.api_key) if self.api_key else None)

    @property
    def configured(self) -> bool:
        return bool(self.client or self.api_key)

    @classmethod
    def _clean_entities(cls, raw: Any) -> dict[str, Any]:
        """Keep only portable semantic values safe for deterministic app logic."""
        if not isinstance(raw, dict):
            return {}
        result: dict[str, Any] = {}
        for key, value in raw.items():
            clean_key = str(key or "").strip().lower()
            if clean_key not in cls.ALLOWED_ENTITY_KEYS or value is None:
                continue
            if isinstance(value, bool):
                result[clean_key] = value
            elif isinstance(value, (int, float)):
                result[clean_key] = value
            elif isinstance(value, str):
                clean_value = value.strip()
                if clean_value:
                    result[clean_key] = clean_value[:500]
            elif isinstance(value, list):
                items = [str(item).strip()[:200] for item in value if str(item).strip()]
                if items:
                    result[clean_key] = items[:20]
        return result

    @classmethod
    def _reply_asks_for_location(cls, sentence: str) -> bool:
        """True if a sentence looks like it is asking the user for a location.

        Only a sentence that both mentions a location-ish keyword AND reads
        as a question is treated as an ask -- this avoids stripping a
        sentence that merely mentions "location" in passing.
        """
        if "?" not in sentence and "గలరా" not in sentence and "చెప్పగలరా" not in sentence:
            return False
        lowered = sentence.lower()
        return any(keyword.lower() in lowered for keyword in cls._LOCATION_ASK_KEYWORDS)

    @classmethod
    def _strip_location_question(cls, reply: str, locale: str) -> str:
        """Deterministically remove any location question from a reply.

        The prompt instructs the model never to re-ask for a known location,
        but LLM instruction-following is probabilistic, not guaranteed --
        live testing showed the same known-location input sometimes still
        produced a location question. This code-level guard makes the
        behaviour deterministic regardless of what the model does.
        """
        sentences = re.split(r"(?<=[.?!])\s+", reply.strip())
        kept = [s for s in sentences if s.strip() and not cls._reply_asks_for_location(s)]
        if kept:
            return " ".join(kept).strip()
        # The whole reply was a location question -- fall back to a short,
        # honest continuation rather than showing the user an empty bubble.
        return cls._LOCATION_FALLBACK_REPLY["te" if locale == "te" else "en"]

    def decide(
        self,
        message: str,
        *,
        history: list[dict[str, str]] | None = None,
        locale: str = "",
        location: str = "",
    ) -> dict[str, Any] | None:
        """Return a semantic decision for the in-app conversation.

        The AI extracts reusable semantic entities so downstream business logic does
        not need to re-infer the primary intent from keyword-prefixed text.

        ``location`` is the user's saved/default location, when the app already
        knows one. When supplied, the model must treat location as already
        satisfied and must not ask the user for it again.
        """
        clean = str(message or "").strip()
        if not clean or not self.configured:
            return None
        clean_location = str(location or "").strip()[:300]

        compact_history = []
        for turn in (history or [])[-12:]:
            role = str(turn.get("role", "") or "").strip().lower()
            text = str(turn.get("text", "") or "").strip()
            if role in {"user", "assistant"} and text:
                compact_history.append({"role": role, "text": text[:1200]})

        prompt = (
            "You are the semantic routing brain for ASKODOX, a natural AI assistant with optional local business actions. "
            "Understand meaning from the full conversation, not keyword matching. Return ONLY one JSON object with keys: "
            "reply, domain, transactional, action, confidence, entities. domain must be one of GENERAL, JOB_SEEKER, STAFFING, SERVICE, "
            "PARCEL, RIDE, PRODUCT, FOOD, EVENT, APPOINTMENT, LEDGER, UNKNOWN. transactional is boolean. action is a short snake_case string. "
            "entities must be a JSON object containing only facts actually supplied or unambiguously inherited from the conversation. "
            "Useful entity keys include subject, category, role, skill, quantity, unit, headcount, date, time, timing, location, from, to, budget, price, salary, pay, pay_basis, duration, shift, context, variant, quality, size, model, fulfilment, availability, specialist, service_type, job_type, seats, notes. "
            "Never invent a missing entity. Keep values concise. reply must answer naturally in the user's language or language mix. "
            "Do not claim a booking, payment, message, search or match happened. "
            "Important distinction: 'delivery job kavali' is JOB_SEEKER; 'delivery boys/staff kavali na shop ki' is STAFFING; "
            "'parcel/courier pampali' is PARCEL; temporary catering/function workers are STAFFING. General planning/chat is GENERAL. "
            "Conversation continuity rule: if the current message supplies a missing detail, correction, quantity, date, time, location, budget, salary, "
            "price or other parameter for the immediately preceding transactional request, KEEP the same transactional domain and action family and return the new entity in entities. "
            "Do not downgrade a short follow-up such as 'salary 800 estha', '10 members', 'repu 11 am', 'Vijayawada', or 'one person' to GENERAL when the prior context is staffing or another transaction. "
            "If a new request clearly changes intent, switch domains. Example: staffing follow-up -> parcel request must switch from STAFFING to PARCEL. "
            "Use previous turns as authoritative context for ellipsis and follow-ups. "
            "Known user location rule: if a known location is given below, treat the location "
            "requirement as already satisfied for this request. Do NOT ask the user for their "
            "location again, and do not include a location question in reply. Only ask about "
            "location if the user is explicitly asking to use a different/new location than the "
            "known one. You may still copy the known location into entities.location when relevant.\n"
            f"Locale hint: {locale or 'auto'}\n"
            f"Known user location: {clean_location or 'none (ask if the request needs it)'}\n"
            f"Conversation history JSON: {json.dumps(compact_history, ensure_ascii=False)}\n"
            + (
                f"FINAL REMINDER (highest priority, overrides anything above if in conflict): the "
                f"user's location is already known as '{clean_location}'. Your reply text must NOT "
                f"contain any question asking for location, address, or delivery place. Skip that "
                f"topic entirely and move to the next missing detail (such as product variant, "
                f"quantity, date or budget) instead.\n"
                if clean_location else ""
            )
            + f"Current user message: {clean}"
        )
        try:
            client = self.client or genai.Client(api_key=self.api_key)
            response = client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.15,
                    max_output_tokens=900,
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
            entities = self._clean_entities(data.get("entities"))
            # Defensive fallback: guarantee the known location survives even if the
            # model's JSON omits it, so downstream capture never re-asks for it.
            if clean_location and not entities.get("location"):
                entities["location"] = clean_location
            # Deterministic safety net: the prompt instructs the model to never
            # re-ask for a known location, but that instruction is probabilistic.
            # Strip any location question the model asked anyway so the user
            # never sees the re-ask regardless of the model's behaviour.
            if clean_location:
                reply = self._strip_location_question(reply, locale)
            if not reply:
                return None
            return {
                "reply": reply,
                "domain": domain,
                "transactional": transactional,
                "action": action,
                "confidence": confidence,
                "entities": entities,
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
