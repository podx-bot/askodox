"""General-purpose AI assistant for ASKODOX OASAT GENERAL requests.

Domain-specific transactional flows remain with their deterministic/runtime handlers.
This layer only answers OASAT GENERAL prompts and falls back safely when the model is
not configured or unavailable.
"""
from __future__ import annotations

from typing import Any

from google import genai
from google.genai import types


class UniversalAIAssistantService:
    GENERAL_MARKER = "OASAT domain=GENERAL;"

    def __init__(self, delegate, *, api_key: str, model: str, client: Any | None = None) -> None:
        self.delegate = delegate
        self.api_key = str(api_key or "").strip()
        self.model = str(model or "gemini-3.6-flash").strip()
        self.client = client or (genai.Client(api_key=self.api_key) if self.api_key else None)

    @property
    def configured(self) -> bool:
        return bool(self.client or self.api_key)

    def process(self, sender_mobile: str, message: str) -> str:
        clean = str(message or "").strip()
        if self.GENERAL_MARKER not in clean:
            return self._delegate(sender_mobile, clean)
        if not self.configured:
            return self._delegate(sender_mobile, clean)

        prompt = (
            "You are ASKODOX, a universal AI assistant. Answer the user's actual request naturally and directly. "
            "Use the same language or natural language mix the user used. Respect any OASAT instructions and saved-memory context "
            "already embedded in the supplied prompt. Do not force shopping, seller matching, forms, menus, or local-commerce flows "
            "when the user is asking a general question. Do not pretend you checked live/current web information unless live research "
            "evidence is explicitly supplied. Never invent actions, bookings, messages, reminders, sources, or completed operations. "
            "Be concise by default, but explain enough to be useful.\n\n"
            f"Conversation prompt:\n{clean}"
        )
        try:
            client = self.client or genai.Client(api_key=self.api_key)
            response = client.models.generate_content(
                model=self.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.3,
                    max_output_tokens=1024,
                ),
            )
            answer = str(getattr(response, "text", "") or "").strip()
            if answer:
                return answer
        except Exception:
            pass
        return self._delegate(sender_mobile, clean)

    def _delegate(self, sender_mobile: str, message: str) -> str:
        try:
            return self.delegate.process(sender_mobile=sender_mobile, message=message)
        except TypeError:
            return self.delegate.process(sender_mobile, message)
