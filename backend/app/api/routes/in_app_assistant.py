from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.services.buyer_guide_gate import wants_buying_guide

router = APIRouter(prefix="/api/in-app", tags=["in-app-assistant"])


class AssistantTurn(BaseModel):
    role: str
    text: str


class AssistantRequest(BaseModel):
    message: str = Field(min_length=1, max_length=6000)
    locale: str = ""
    history: list[AssistantTurn] = Field(default_factory=list)
    # Saved/default location the app already knows for this user, if any.
    # When present, the assistant must not ask the user for location again.
    location: str = Field(default="", max_length=300)


class AssistantDecision(BaseModel):
    reply: str
    domain: str
    transactional: bool
    action: str = ""
    confidence: float = 0.0
    source: str = "universal_ai"
    entities: dict[str, Any] = Field(default_factory=dict)
    # Added 2026-09-16 (round 9, roadmap Phase 1: "Reconnect what already
    # works"). BuyerIntelligenceService.build_buying_guide() is a real,
    # tested service that already existed but was only ever wired into the
    # WhatsApp pipeline, which ordinary users can no longer reach. See
    # buyer_guide_gate.py for exactly when this gets filled in -- it is
    # None for every non-buying message, so existing clients that ignore
    # this field see no change at all.
    buying_guide: dict[str, Any] | None = None


@router.post("/assistant", response_model=AssistantDecision)
def assistant_decision(payload: AssistantRequest, request: Request) -> AssistantDecision:
    container: Any = request.app.state.container
    service = container.universal_ai_assistant_service
    history = [{"role": turn.role, "text": turn.text} for turn in payload.history[-12:]]
    decision = service.decide(
        payload.message,
        history=history,
        locale=payload.locale,
        location=payload.location,
    )

    if decision is None:
        # Safe degradation: do not invent an AI action when the model is unavailable.
        # The app can fall back to its existing deterministic flow.
        return AssistantDecision(
            reply="",
            domain="UNKNOWN",
            transactional=False,
            action="",
            confidence=0.0,
            source="fallback",
        )

    entities = decision.get("entities") or {}
    subject = str(entities.get("subject") or "").strip() or None
    buying_guide: dict[str, Any] | None = None
    if wants_buying_guide(
        domain=decision.get("domain", ""),
        action=decision.get("action", ""),
        message=payload.message,
        subject=subject,
    ):
        guide_context = {"location": payload.location} if payload.location else None
        buying_guide = container.buyer_intelligence_service.build_buying_guide(
            subject, guide_context
        )

    return AssistantDecision(**decision, source="universal_ai", buying_guide=buying_guide)
