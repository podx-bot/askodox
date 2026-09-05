"""Conversation-facing long-term memory commands for ASKODOX."""
from __future__ import annotations

import re
from typing import Any

from app.repositories.user_memory_repository import UserMemoryRepository


class UserMemoryService:
    """Handle explicit save/recall/forget commands without guessing sensitive facts."""

    _REMEMBER_PREFIXES = (
        "remember that ",
        "remember ",
        "please remember that ",
        "గుర్తుంచుకో ",
        "గుర్తు పెట్టుకో ",
    )
    _RECALL_PHRASES = (
        "what do you remember about me",
        "what do you remember",
        "show my memory",
        "my memory",
        "నా గురించి ఏమి గుర్తుంది",
        "నాకు సంబంధించినవి ఏమి గుర్తున్నాయి",
    )
    _CLEAR_PHRASES = (
        "forget everything about me",
        "clear my memory",
        "delete my memory",
        "నా మెమరీ క్లియర్ చేయి",
        "నా గురించి అన్నీ మర్చిపో",
    )

    def __init__(self, repository: UserMemoryRepository) -> None:
        self.repository = repository

    @staticmethod
    def _key_for_fact(text: str) -> str:
        normalized = re.sub(r"[^\w\s-]", "", text.casefold(), flags=re.UNICODE)
        words = [w for w in normalized.split() if w]
        return "fact:" + "-".join(words[:8])

    def process(self, user_id: str, message: str) -> str | None:
        clean = " ".join(str(message or "").strip().split())
        if not clean:
            return None
        lowered = clean.casefold()

        if lowered in self._CLEAR_PHRASES:
            count = self.repository.clear_user(user_id)
            return f"🧠 Cleared {count} saved memory item{'s' if count != 1 else ''}."

        if lowered in self._RECALL_PHRASES:
            memories = self.repository.list_active(user_id, limit=20)
            if not memories:
                return "🧠 I don't have any saved long-term memory for you yet."
            lines = [f"• {row['memory_value']}" for row in memories]
            return "🧠 I remember:\n" + "\n".join(lines)

        for prefix in self._REMEMBER_PREFIXES:
            if lowered.startswith(prefix):
                fact = clean[len(prefix):].strip(" .")
                if not fact:
                    return "Tell me the specific non-sensitive fact or preference you want me to remember."
                key = self._key_for_fact(fact)
                self.repository.remember(
                    user_id,
                    key,
                    fact,
                    memory_type="EXPLICIT_USER_MEMORY",
                    source="conversation",
                )
                return f"🧠 Remembered: {fact}"

        forget_match = re.match(r"^(?:forget|remove from memory|మర్చిపో)\s+(.+)$", clean, flags=re.IGNORECASE)
        if forget_match:
            target = forget_match.group(1).strip(" .")
            memories = self.repository.list_active(user_id, limit=100)
            for row in memories:
                if target.casefold() in str(row.get("memory_value") or "").casefold():
                    self.repository.forget(user_id, str(row["memory_key"]))
                    return f"🧠 Forgotten: {row['memory_value']}"
            return "I couldn't find a matching saved memory item."

        return None

    def context(self, user_id: str, limit: int = 10) -> list[dict[str, Any]]:
        return self.repository.list_active(user_id, limit=limit)
