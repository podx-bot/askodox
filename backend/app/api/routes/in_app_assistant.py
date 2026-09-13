from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/in-app", tags=["in-app-assistant"])


class AssistantTurn(BaseModel):
    role: str
    text: str


class AssistantRequest(BaseModel):
    message: str = Field(min_length=1, max_length=6000)
    locale: str = ""
    history: list[AssistantTurn] = Field(default_factory=list)


class AssistantDecision(BaseModel):
    reply: str
    domain: str
    transactional: bool
    action: str = ""
    confidence: float = 0.0
    source: str = "universal_ai"


@router.post("/assistant", response_model=AssistantDecision)
def assistant_decision(payload: AssistantRequest, request: Request) -> AssistantDecision:
    container: Any = request.app.state.container
    service = container.universal_ai_assistant_service
    history = [{"role": turn.role, "text": turn.text} for turn in payload.history[-12:]]
    decision = service.decide(payload.message, history=history, locale=payload.locale)

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

    return AssistantDecision(**decision, source="universal_ai")
