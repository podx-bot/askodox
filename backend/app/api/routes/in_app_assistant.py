from __future__ import annotations

from typing import Any

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from pydantic import BaseModel, Field

from app.services.buyer_guide_gate import wants_buying_guide
from app.services.dynamic_role_profile_attachment_service import DynamicRoleProfileAttachmentService

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
    # Active Role = current conversation/request intent, re-derived fresh on
    # every message (never persisted here, never locking the user into one
    # role). Reuses the same UniversalCategoryFlowBrain classification and
    # ROLE_MAP already used by DynamicRoleProfileAttachmentService for the
    # durable capability it attaches once a deal actually completes -- this
    # is purely a same-message UI hint so the chat can show/switch an
    # "X mode activated" chip without waiting for that deeper pipeline.
    active_role: str = ""
    active_role_confidence: float = 0.0


def _suggest_active_role(container: Any, message: str) -> tuple[str, float]:
    try:
        decision = container.universal_category_flow_brain.classify(message)
    except Exception:
        return "", 0.0
    confidence = float(getattr(decision, "confidence", 0.0) or 0.0)
    if confidence < DynamicRoleProfileAttachmentService.MIN_CONFIDENCE:
        return "", confidence
    category = str(getattr(decision, "category", "") or "").upper()
    side = str(getattr(decision, "side", "") or "").upper()
    role = DynamicRoleProfileAttachmentService.ROLE_MAP.get((category, side), "")
    return role, confidence


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
    active_role, active_role_confidence = _suggest_active_role(container, payload.message)

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
            active_role=active_role,
            active_role_confidence=active_role_confidence,
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

    return AssistantDecision(
        **decision,
        source="universal_ai",
        buying_guide=buying_guide,
        active_role=active_role,
        active_role_confidence=active_role_confidence,
    )


@router.post("/voice/transcribe")
async def transcribe_in_app_voice(
    request: Request,
    audio: UploadFile = File(...),
    locale: str = Form(default=""),
) -> dict[str, Any]:
    """Transcribe Main Chat microphone audio through the production Sarvam-first voice service."""
    container: Any = request.app.state.container
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio upload")
    result = container.voice_assistant_service.transcribe(
        audio_bytes=audio_bytes,
        mime_type=audio.content_type or "audio/m4a",
    )
    transcript = str((result or {}).get("transcript") or (result or {}).get("text") or "").strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="Voice transcription failed")
    return {
        "transcript": transcript,
        "locale": locale,
        "provider": str((result or {}).get("provider") or "sarvam_first"),
    }


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    locale: str = ""


@router.post("/voice/speak")
async def speak_in_app_reply(payload: SpeakRequest, request: Request) -> Response:
    """Synthesize a Main Chat assistant reply through the same production
    Sarvam-first voice service (Bulbul v3) already used for WhatsApp voice
    replies, instead of leaving Sarvam TTS reachable only from that channel."""
    container: Any = request.app.state.container
    result = container.voice_assistant_service.synthesize(payload.text)
    content = (result or {}).get("content")
    if not result or not result.get("success") or not content:
        raise HTTPException(status_code=502, detail="Voice synthesis failed")
    return Response(
        content=content,
        media_type=str(result.get("mime_type") or "audio/ogg"),
    )
