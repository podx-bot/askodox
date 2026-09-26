from __future__ import annotations

from typing import Any

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

import os

from app.repositories.hybrid_support_repository import SupportEscalationRepository
from app.services.buyer_guide_gate import wants_buying_guide
from app.services.session_tokens import verify_token

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


_AUDIO_MIME_BY_SUFFIX = {
    ".m4a": "audio/mp4",
    ".mp4": "audio/mp4",
    ".aac": "audio/aac",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".opus": "audio/opus",
    ".mp3": "audio/mpeg",
    ".webm": "audio/webm",
}


def _audio_mime_type(content_type: str | None, filename: str | None) -> str:
    """Multipart clients often send application/octet-stream; Sarvam needs
    the real audio type, so fall back to the file extension."""
    declared = str(content_type or "").split(";", 1)[0].strip().lower()
    if declared.startswith("audio/"):
        return declared
    name = str(filename or "").lower()
    for suffix, mime in _AUDIO_MIME_BY_SUFFIX.items():
        if name.endswith(suffix):
            return mime
    return "audio/mp4"


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
        mime_type=_audio_mime_type(audio.content_type, audio.filename),
    )
    transcript = str((result or {}).get("transcript") or (result or {}).get("text") or "").strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="Voice transcription failed")
    return {
        "transcript": transcript,
        "locale": locale,
        "provider": str((result or {}).get("provider") or "sarvam_first"),
    }


# ------------------------------------------------------------------ support --
# 2026-09-26: ASKODOX AI is first-line support. The app escalates only when
# the AI could not resolve an issue (or earlier for critical issues such as
# payments, disputes or safety). The case carries the full context so the
# Support/Admin Command Center never asks the user to repeat themselves.


class SupportTurn(BaseModel):
    role: str
    text: str = Field(max_length=4000)


class SupportEscalationRequest(BaseModel):
    issue: str = Field(min_length=1, max_length=2000)
    category: str = "GENERAL"
    critical: bool = False
    conversation: list[SupportTurn] = Field(default_factory=list)
    requirement: dict[str, Any] = Field(default_factory=dict)
    deal_id: str | None = None
    counterpart: str | None = None
    actions_tried: list[str] = Field(default_factory=list)
    status: str = ""
    active_role: str = ""
    locale: str = ""


def _support_repository(container: Any) -> SupportEscalationRepository:
    repository = getattr(container, "support_escalation_repository", None)
    if repository is None:
        repository = SupportEscalationRepository(container.settings.database_path)
        container.support_escalation_repository = repository
    return repository


def _optional_app_user(request: Request) -> str:
    """Signed-in user when a valid token is sent; guests can still escalate."""
    container: Any = request.app.state.container
    header = request.headers.get("authorization") or ""
    token = header[7:].strip() if header.lower().startswith("bearer ") else ""
    if token:
        user = verify_token(token, container.settings.session_token_secret)
        if user:
            return user
    return "guest"


def support_channels() -> dict[str, Any]:
    whatsapp = "".join(ch for ch in os.getenv("SUPPORT_WHATSAPP_NUMBER", "") if ch.isdigit())
    phone = os.getenv("SUPPORT_PHONE_NUMBER", "").strip()
    return {
        "chat": True,
        "whatsapp_url": f"https://wa.me/{whatsapp}" if whatsapp else None,
        "call_uri": f"tel:{phone}" if phone else None,
    }


@router.post("/support/escalate")
def escalate_to_support(payload: SupportEscalationRequest, request: Request) -> dict[str, Any]:
    container: Any = request.app.state.container
    context = {
        "conversation": [turn.model_dump() for turn in payload.conversation[-30:]],
        "requirement": payload.requirement,
        "deal_id": payload.deal_id,
        "counterpart": payload.counterpart,
        "actions_tried": payload.actions_tried[-20:],
        "status": payload.status,
        "active_role": payload.active_role,
        "locale": payload.locale,
    }
    case = _support_repository(container).create(
        _optional_app_user(request), payload.issue, payload.category, payload.critical, context
    )
    return {"case_id": case.get("id"), "status": case.get("status"), "channels": support_channels()}


support_admin_router = APIRouter(prefix="/admin/support", tags=["admin-support"])


@support_admin_router.get("/escalations")
def list_support_escalations(request: Request, key: str = "", limit: int = 50) -> dict[str, Any]:
    """Support/Admin Command Center feed (same ADMIN_SEED_KEY gate as
    /admin/products; 404 when the key is wrong so the path isn't advertised)."""
    container: Any = request.app.state.container
    expected = str(getattr(container.settings, "admin_seed_key", "") or "").strip()
    if not expected or key != expected:
        raise HTTPException(status_code=404)
    return {"items": _support_repository(container).list_open(limit=limit)}
