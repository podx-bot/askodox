"""Universal AI understanding layer for ASKODOX conversations.

The model is responsible for natural-language understanding and emits a small,
structured decision. Deterministic business modules still execute the action and
remain the source of truth for payments, bookings, matching and safety checks.
"""
from __future__ import annotations

import json
import logging
import re
import time
from typing import Any

import httpx
from google import genai
from google.genai import errors as genai_errors
from google.genai import types

from app.services.runtime_time_context import grounded_search_query, needs_live_verification, runtime_context_block

logger = logging.getLogger(__name__)


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

    def __init__(
        self,
        delegate,
        *,
        api_key: str,
        model: str,
        client: Any | None = None,
        openai_api_key: str = "",
        openai_model: str = "gpt-5",
        http_client: Any | None = None,
        research_service: Any | None = None,
        clock: Any | None = None,
    ) -> None:
        self.delegate = delegate
        # Live evidence for time-sensitive facts (OASATLiveResearchService) and
        # the runtime clock used for "today / this year / now" grounding.
        self.research_service = research_service
        self.clock = clock
        self.api_key = str(api_key or "").strip()
        self.model = str(model or "gemini-3.6-flash").strip()
        self.client = client or (genai.Client(api_key=self.api_key) if self.api_key else None)
        self.openai_api_key = str(openai_api_key or "").strip()
        self.openai_model = str(openai_model or "gpt-5").strip()
        self.http = http_client or httpx.Client(timeout=20.0)

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

    def _generate_with_retry(
        self, client: Any, prompt: str, config: Any, *, attempts: int = 3, base_delay: float = 0.6
    ) -> Any:
        """Call generate_content with a short retry for transient server overload.

        Production logs showed Gemini occasionally answering with a 503
        ServerError ("This model is currently experiencing high demand ...
        usually temporary") that clears within a second or two -- the very
        next identical request often succeeds. The SDK's own internal retry
        already exhausts before raising, so this adds one more short,
        ASKODOX-side retry for that specific transient case instead of
        immediately giving up and showing the user a generic fallback reply.
        Any other exception type is not retried here; it propagates to the
        caller's exception handler as before.
        """
        last_error: Exception | None = None
        for attempt in range(attempts):
            try:
                return client.models.generate_content(model=self.model, contents=prompt, config=config)
            except genai_errors.ServerError as exc:
                last_error = exc
                if attempt < attempts - 1:
                    time.sleep(base_delay * (attempt + 1))
                    continue
        raise last_error

    def _call_openai(self, prompt: str) -> dict[str, Any]:
        response = self.http.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {self.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": self.openai_model,
                "input": [{"role": "user", "content": [{"type": "input_text", "text": prompt}]}],
            },
        )
        response.raise_for_status()
        return self._parse_json(self._openai_output_text(response.json()))

    @staticmethod
    def _openai_output_text(data: dict[str, Any]) -> str:
        direct = data.get("output_text")
        if isinstance(direct, str) and direct.strip():
            return direct.strip()
        chunks: list[str] = []
        for item in data.get("output") or []:
            if not isinstance(item, dict):
                continue
            for content in item.get("content") or []:
                if isinstance(content, dict) and content.get("type") == "output_text" and content.get("text"):
                    chunks.append(str(content["text"]))
        return "\n".join(chunks).strip()

    @staticmethod
    def _parse_json(raw: str) -> dict[str, Any]:
        text = str(raw or "").strip()
        if text.startswith("```"):
            text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.I)
            text = re.sub(r"\s*```$", "", text)
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            start, end = text.find("{"), text.rfind("}")
            if start < 0 or end <= start:
                raise ValueError("no json object found in model reply")
            data = json.loads(text[start : end + 1])
        if not isinstance(data, dict):
            raise ValueError("model reply JSON was not an object")
        return data

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
        if not clean or not (self.configured or self.openai_api_key):
            return None
        clean_location = str(location or "").strip()[:300]

        compact_history = []
        for turn in (history or [])[-12:]:
            role = str(turn.get("role", "") or "").strip().lower()
            text = str(turn.get("text", "") or "").strip()
            if role in {"user", "assistant"} and text:
                compact_history.append({"role": role, "text": text[:1200]})

        runtime_block = runtime_context_block(clean, self.clock)
        grounding, grounding_block = self._live_grounding(clean)
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
            + runtime_block + "\n"
            + grounding_block
            + f"Current user message: {clean}"
        )
        data: dict[str, Any] | None = None
        if self.configured:
            try:
                client = self.client or genai.Client(api_key=self.api_key)
                config = types.GenerateContentConfig(
                    temperature=0.15,
                    max_output_tokens=2048,
                    response_mime_type="application/json",
                    # Structured extraction does not need deep reasoning. Keep
                    # thinking from consuming the visible JSON response budget.
                    thinking_config=types.ThinkingConfig(thinking_budget=0),
                )
                response = self._generate_with_retry(client, prompt, config)
                data = self._parse_json(str(getattr(response, "text", "") or "").strip())
            except Exception:
                logger.exception(
                    "universal_ai_assistant.decide: gemini call failed%s (message_len=%d, has_known_location=%s)",
                    "; trying openai fallback" if self.openai_api_key else "; no openai fallback configured",
                    len(clean),
                    bool(clean_location),
                )
        if data is None and self.openai_api_key:
            try:
                data = self._call_openai(prompt)
            except Exception:
                logger.exception(
                    "universal_ai_assistant.decide: openai fallback also failed "
                    "(message_len=%d, has_known_location=%s)",
                    len(clean),
                    bool(clean_location),
                )
        if not isinstance(data, dict):
            return None
        try:
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
            if grounding is not None and not grounding["verified"]:
                # Deterministic honesty: never let an unverified current fact look checked.
                reply = f"{reply}\n\n{self._unverified_note(clean, locale)}"
            return {
                "reply": reply,
                "domain": domain,
                "transactional": transactional,
                "action": action,
                "confidence": confidence,
                "entities": entities,
                **({"grounding": grounding} if grounding is not None else {}),
            }
        except Exception:
            # Previously silent -- this made every AI-call failure (bad API
            # response, quota, malformed JSON, network hiccup) indistinguishable
            # from "model unavailable" in production, with no way to diagnose
            # why a given request fell back to the app's generic reply.
            logger.exception(
                "universal_ai_assistant.decide failed; falling back to deterministic reply "
                "(message_len=%d, has_known_location=%s)",
                len(clean),
                bool(clean_location),
            )
            return None

    _UNVERIFIED_NOTE = {
        "te": "(గమనిక: ప్రస్తుతం దీన్ని లైవ్ సోర్సులతో ధృవీకరించలేకపోయాను — దయచేసి అధికారిక క్యాలెండర్/సోర్స్‌తో సరిచూసుకోండి.)",
        "en": "(Note: I couldn't verify this with live sources right now — please confirm with an official source.)",
    }

    def _unverified_note(self, message: str, locale: str) -> str:
        telugu = str(locale or "").lower().startswith("te") or bool(re.search(r"[\u0C00-\u0C7F]", message))
        return self._UNVERIFIED_NOTE["te" if telugu else "en"]

    def _live_grounding(self, message: str) -> tuple[dict[str, Any] | None, str]:
        """Live evidence for time-sensitive/changeable facts. Returns
        (grounding summary or None when not needed, prompt block)."""
        if message.startswith("OASAT ") or not needs_live_verification(message):
            return None, ""
        query = grounded_search_query(message, self.clock)
        evidence: dict[str, Any] = {}
        if self.research_service is not None:
            try:
                evidence = self.research_service.research(query, limit=5) or {}
            except Exception:
                logger.exception("universal_ai_assistant: live research failed (query_len=%d)", len(query))
                evidence = {}
        sources = list(evidence.get("sources") or [])[:5]
        if not sources:
            grounding = {"required": True, "verified": False, "query": query, "sources": []}
            block = (
                "LIVE VERIFICATION REQUIRED BUT UNAVAILABLE: this question depends on current or date-specific facts and no "
                "live web evidence could be retrieved. Do NOT claim the answer was checked or is verified, do NOT present a "
                "specific current date/price/policy as confirmed, and say plainly that it could not be verified right now.\n"
            )
            return grounding, block
        lines = [
            f"[S{i}] {src.get('title')} | {src.get('url')} | published={src.get('published_at')} | {src.get('snippet')}"
            for i, src in enumerate(sources, start=1)
        ]
        grounding = {
            "required": True,
            "verified": True,
            "query": query,
            "sources": [{"id": f"S{i}", "title": src.get("title"), "url": src.get("url")} for i, src in enumerate(sources, start=1)],
        }
        block = (
            "LIVE WEB EVIDENCE (retrieved now for this question). Answer current/date-specific facts ONLY from this evidence, "
            "for the runtime year above; cite source ids like [S1]; if the evidence does not settle it, say so instead of guessing.\n"
            + "\n".join(lines) + "\n"
        )
        return grounding, block

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
