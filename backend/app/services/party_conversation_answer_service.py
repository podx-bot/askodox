from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


@dataclass(frozen=True)
class PartyConversationAnswer:
    status: str
    answer: str | None = None
    field: str | None = None
    requires_party_b_confirmation: bool = False

    def as_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "answer": self.answer,
            "field": self.field,
            "requires_party_b_confirmation": self.requires_party_b_confirmation,
        }


class PartyConversationAnswerService:
    """Answer Party A questions only from trusted deal/Party B data.

    Party A / Party B are transaction sides, not fixed Buyer/Seller roles.
    The service deliberately does not generate guesses. If a relevant fact is
    not present in trusted data, the result explicitly requires Party B
    confirmation so the conversation can continue without inventing an answer.
    """

    _FIELD_ALIASES: tuple[tuple[str, tuple[str, ...]], ...] = (
        ("price", ("price", "rate", "cost", "ధర", "రేట్")),
        ("availability", ("available", "availability", "stock", "ఉందా", "దొరుక")),
        ("size", ("size", "dimension", "సైజ్")),
        ("quantity", ("quantity", "qty", "how many", "ఎన్ని", "పరిమాణం")),
        ("fulfilment", ("delivery", "pickup", "fulfilment", "fulfillment", "డెలివరీ", "పికప్")),
        ("warranty", ("warranty", "guarantee", "వారంటీ", "గ్యారంటీ")),
        ("location", ("location", "where", "address", "లొకేషన్", "ఎక్కడ")),
        ("timing", ("timing", "time", "when", "ఎప్పుడు", "టైమ్")),
        ("customization", ("custom", "customization", "customise", "customize", "కస్టమ్")),
    )

    def answer(
        self,
        question: str,
        *,
        trusted_party_b_data: Mapping[str, Any] | None = None,
        trusted_deal_data: Mapping[str, Any] | None = None,
    ) -> PartyConversationAnswer:
        text = " ".join(str(question or "").strip().lower().split())
        if not text:
            return PartyConversationAnswer(
                status="INVALID_QUESTION",
                requires_party_b_confirmation=False,
            )

        field = self._detect_field(text)
        if field is None:
            return PartyConversationAnswer(
                status="PARTY_B_CONFIRMATION_REQUIRED",
                requires_party_b_confirmation=True,
            )

        for source in (trusted_party_b_data or {}, trusted_deal_data or {}):
            value = self._trusted_value(source, field)
            if value is not None:
                return PartyConversationAnswer(
                    status="ANSWERED_FROM_TRUSTED_DATA",
                    answer=str(value),
                    field=field,
                    requires_party_b_confirmation=False,
                )

        return PartyConversationAnswer(
            status="PARTY_B_CONFIRMATION_REQUIRED",
            field=field,
            requires_party_b_confirmation=True,
        )

    def _detect_field(self, text: str) -> str | None:
        for field, aliases in self._FIELD_ALIASES:
            if any(alias in text for alias in aliases):
                return field
        return None

    @staticmethod
    def _trusted_value(source: Mapping[str, Any], field: str) -> Any | None:
        direct = source.get(field)
        if PartyConversationAnswerService._present(direct):
            return direct

        # Dynamic/category fields are allowed when they were supplied by the
        # verified Party B/catalog/deal record. This keeps the architecture
        # reusable across products, services, jobs, rides and future domains.
        dynamic = source.get("dynamic_fields")
        if isinstance(dynamic, Mapping):
            value = dynamic.get(field)
            if PartyConversationAnswerService._present(value):
                return value
        return None

    @staticmethod
    def _present(value: Any) -> bool:
        if value is None:
            return False
        if isinstance(value, str):
            return bool(value.strip())
        return True
