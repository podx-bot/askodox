from __future__ import annotations

from typing import Any

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from pydantic import BaseModel, Field

import logging
import os

from app.repositories.hybrid_support_repository import SupportEscalationRepository
from app.services.buyer_guide_gate import wants_buying_guide
from app.services.session_tokens import verify_token

logger = logging.getLogger(__name__)

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
    # What the options on screen were searched for (the brain's facts at that
    # search), so a later detail that does not change them never re-searches.
    searched_for: dict[str, Any] = Field(default_factory=dict)
    # One-time advice memory: concerns already raised in this conversation
    # (the ledger the previous answer returned), so the brain never repeats
    # a warning without new information, an explicit ask or a critical risk.
    advice_given: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
    # What this app build can render (e.g. "meaning_tags"); older builds send
    # nothing and get replies without the new markers.
    capabilities: list[str] = Field(default_factory=list, max_length=10)


class AssistantDecision(BaseModel):
    reply: str
    domain: str
    transactional: bool
    action: str = ""
    confidence: float = 0.0
    source: str = "universal_ai"
    entities: dict[str, Any] = Field(default_factory=dict)
    # Decision brain mode: advice (reasoning, no result cards), commerce
    # (search / act), follow_up (about options already shown) or chat.
    mode: str = "chat"
    # Conversation Decision Brain: accumulated state, whether a search is
    # justified now (None = the model gave no readiness; the app keeps its
    # offline rule), the ONE next question and the consolidated search subject.
    state: dict[str, Any] = Field(default_factory=dict)
    search_ready: bool | None = None
    next_question: str | None = None
    search_subject: str | None = None
    ready_reason: str = ""
    new_need: bool = False
    # APK 1305: deterministic conversation-relation layer output. The app
    # retires the active result deck when the subject changed or the turn is
    # a genuine new topic, and answers comparison/result_action turns from
    # the options on screen instead of starting a new search.
    conversation_relation: str = "unknown"
    subject_changed: bool = False
    # Added 2026-09-16 (round 9, roadmap Phase 1: "Reconnect what already
    # works"). BuyerIntelligenceService.build_buying_guide() is a real,
    # tested service that already existed but was only ever wired into the
    # WhatsApp pipeline, which ordinary users can no longer reach. See
    # buyer_guide_gate.py for exactly when this gets filled in -- it is
    # None for every non-buying message, so existing clients that ignore
    # this field see no change at all.
    buying_guide: dict[str, Any] | None = None
    # Present only for time-sensitive questions: whether live web evidence
    # verified the answer, and which sources (never claimed when unverified).
    grounding: dict[str, Any] | None = None
    # The concern raised in THIS reply (key, summary, severity, repeated,
    # allowed) and the conversation's updated advice ledger for the app to
    # send back next turn. None / [] for turns that raise no concern.
    advice: dict[str, Any] | None = None
    advice_ledger: list[dict[str, Any]] = Field(default_factory=list)


@router.post("/assistant", response_model=AssistantDecision)
def assistant_decision(payload: AssistantRequest, request: Request) -> AssistantDecision:
    container: Any = request.app.state.container
    service = container.universal_ai_assistant_service
    history = [{"role": turn.role, "text": turn.text} for turn in payload.history[-12:]]
    # Command Center switch (Phase 20): with the AI assistant disabled the
    # app keeps working through its deterministic flow (same as model-down).
    decision = None
    if _feature_enabled(container, "ai.assistant"):
        # searched_for only when the app sent it: other decide() implementations
        # (fallbacks, fakes) keep their older signature.
        extra = {"searched_for": payload.searched_for} if payload.searched_for else {}
        if payload.advice_given:
            extra["advice_given"] = payload.advice_given
        if payload.capabilities:
            extra["capabilities"] = [str(c)[:30] for c in payload.capabilities]
        decision = service.decide(
            payload.message,
            history=history,
            locale=payload.locale,
            location=payload.location,
            **extra,
        )

        from app.services import assistant_health
        assistant_health.observe("conversation_intelligence", decision is not None,
                                 "" if decision is not None else "brain_unavailable_fallback")

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


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2500)
    locale: str = ""
    voice: str = Field(default="automatic", pattern="^(automatic|male|female)$")


@router.post("/voice/speak")
def speak_in_app_reply(payload: SpeakRequest, request: Request) -> Response:
    """Main Chat reply voice through the existing Sarvam Bulbul v3 pipeline
    (SarvamTTSVoiceAssistantService.synthesize, until now used only by the
    WhatsApp webhook). Returns audio only when Sarvam actually produced it;
    any other path is a 503 so the app can fall back to device TTS and say
    so honestly."""
    container: Any = request.app.state.container
    if not _feature_enabled(container, "voice.sarvam_tts"):
        raise HTTPException(status_code=503, detail="TTS_DISABLED")
    synthesize = getattr(container.voice_assistant_service, "synthesize", None)
    if not callable(synthesize):
        raise HTTPException(status_code=503, detail="TTS_UNAVAILABLE")
    try:
        result = synthesize(payload.text, voice=payload.voice) or {}
    except TypeError:  # an engine without voice choice: only valid for "automatic"
        if payload.voice != "automatic":
            raise HTTPException(status_code=503, detail="TTS_VOICE_UNSUPPORTED") from None
        result = synthesize(payload.text) or {}
    path = str(result.get("tts_path") or "")
    audio = result.get("content")
    if not result.get("success") or not path.startswith("sarvam") or not audio:
        raise HTTPException(status_code=503, detail=str(result.get("status") or "SARVAM_TTS_UNAVAILABLE"))
    return Response(
        content=bytes(audio),
        media_type=str(result.get("mime_type") or "audio/ogg"),
        headers={
            "X-ASKODOX-TTS-Path": path,
            "X-ASKODOX-TTS-Model": str(result.get("model") or ""),
            "X-ASKODOX-TTS-Language": str(result.get("language_code") or ""),
            "X-ASKODOX-TTS-Voice": payload.voice,
        },
    )


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
    # Safe diagnostics only: sizes and counts, never audio or transcript text.
    diagnostics = {
        "upload_bytes": len(audio_bytes),
        "audio_seconds": (result or {}).get("audio_seconds"),
        "segments": (result or {}).get("segments"),
        "path": (result or {}).get("transcription_path"),
        "transcript_chars": len(transcript),
        "transcript_words": len(transcript.split()),
    }
    logger.info("in_app_voice_transcribe %s", " ".join(f"{k}={v}" for k, v in diagnostics.items()))
    return {
        "transcript": transcript,
        "locale": locale,
        "provider": str((result or {}).get("provider") or "sarvam_first"),
        "diagnostics": diagnostics,
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


def _feature_enabled(container: Any, key: str) -> bool:
    # Lazy import keeps this module importable on its own; never raises.
    try:
        from app.api.routes.command_center import feature_enabled

        return feature_enabled(container, key)
    except Exception:
        return True


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


def support_channels(case_id: Any = None) -> dict[str, Any]:
    whatsapp = "".join(ch for ch in os.getenv("SUPPORT_WHATSAPP_NUMBER", "") if ch.isdigit())
    phone = os.getenv("SUPPORT_PHONE_NUMBER", "").strip()
    # The case reference travels with the WhatsApp message so the agent opens
    # the full context in the Command Center (one-way: WhatsApp replies are
    # not synced back into the app; staff respond via the case).
    text = f"?text=ASKODOX%20support%20case%20%23{case_id}" if whatsapp and case_id else ""
    return {
        "chat": True,
        "whatsapp_url": f"https://wa.me/{whatsapp}{text}" if whatsapp else None,
        "call_uri": f"tel:{phone}" if phone else None,
    }


@router.post("/support/escalate")
def escalate_to_support(payload: SupportEscalationRequest, request: Request) -> dict[str, Any]:
    container: Any = request.app.state.container
    if not _feature_enabled(container, "support.escalation"):
        raise HTTPException(status_code=503, detail="SUPPORT_ESCALATION_DISABLED")
    context = {
        "conversation": [turn.model_dump() for turn in payload.conversation[-30:]],
        "requirement": payload.requirement,
        "deal_id": payload.deal_id,
        "counterpart": payload.counterpart,
        "actions_tried": payload.actions_tried[-20:],
        "status": payload.status,
        "active_role": payload.active_role,
        "locale": payload.locale,
        # The in-app AI answered first; the ticket records that it tried.
        "ai_attempted": any(turn.role != "user" for turn in payload.conversation),
    }
    from app.services import support_handoff

    context["handoff"] = support_handoff.build(issue=payload.issue, category=payload.category, context=context)
    case = _support_repository(container).create(
        _optional_app_user(request), payload.issue, payload.category, payload.critical, context
    )
    if case.get("id") and _feature_enabled(container, "notifications.admin"):
        # One Command Center notification per case (event_key is unique), so a
        # retried escalation never double-notifies staff.
        try:
            from app.api.routes.command_center import command_center

            command_center(container).notify_once(
                f"escalation:{case['id']}",
                "escalation_critical" if payload.critical else "escalation",
                f"{payload.category or 'Support'}: {payload.issue[:80]}",
                str(case["id"]),
            )
        except Exception:
            pass
    return {"case_id": case.get("id"), "status": case.get("status"), "channels": support_channels(case.get("id")),
            "summary": context["handoff"]["summary"]}


@router.get("/support/cases")
def my_support_cases(request: Request) -> dict[str, Any]:
    """The signed-in customer's own tickets (token-proven, never by id guess)."""
    container: Any = request.app.state.container
    user = _optional_app_user(request)
    if not user or user == "guest":
        raise HTTPException(status_code=401, detail="Sign in to see your support requests")
    return {"items": [{"case_id": c["id"], "issue": c["issue"][:160], "status": c["status"],
                       "category": c["category"], "updated_at": c["updated_at"]}
                      for c in _support_repository(container).list_for_user(user)]}


def _own_case(request: Request, case_id: int) -> tuple[str, dict[str, Any]]:
    container: Any = request.app.state.container
    user = _optional_app_user(request)
    case = _support_repository(container).get(case_id)
    # "guest" is shared by every signed-out caller: never an owner proof.
    if not user or user == "guest" or not case or str(case.get("requester_user_id") or "") != user:
        raise HTTPException(status_code=404, detail="Support case not found")
    return user, case


@router.get("/support/cases/{case_id}")
def support_case_status(case_id: int, request: Request) -> dict[str, Any]:
    """Customer Care's reply comes back into the same ASKODOX conversation:
    the requester (token-proven) sees status, resolution and the public
    messages -- never internal notes or which staff member replied."""
    _, case = _own_case(request, case_id)
    return {
        "case_id": case["id"],
        "status": case.get("status"),
        "assigned": bool(case.get("assigned_to")),
        "resolution_note": case.get("resolution_note"),
        "updated_at": case.get("updated_at"),
        "messages": _support_repository(request.app.state.container).thread(case_id, public_only=True),
        "can_reply": case.get("status") != "CLOSED",
    }


class SupportReply(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    attachments: list[str] = Field(default_factory=list, max_length=5)


_ATTACHMENT_REF = __import__("re").compile(r"^[A-Za-z0-9_\-:.]{1,120}$")


@router.post("/support/cases/{case_id}/reply")
def reply_to_support_case(case_id: int, payload: SupportReply, request: Request) -> dict[str, Any]:
    """The customer answers staff in the app. A resolved ticket reopens; a
    CLOSED one does not (start a new request)."""
    from app.services import rate_limit

    rate_limit.check(request, "support_reply", limit=30)
    container: Any = request.app.state.container
    user, case = _own_case(request, case_id)
    if case.get("status") == "CLOSED":
        raise HTTPException(status_code=409, detail="This request is closed. Please start a new one.")
    refs = [a for a in payload.attachments if _ATTACHMENT_REF.match(a)]  # references only, never raw content
    repo = _support_repository(container)
    repo.add_message(case_id, author_kind="customer", author="customer", body=payload.message, attachments=refs)
    if case.get("status") == "RESOLVED":
        repo.set_status(case_id, "OPEN", actor="customer", action="reopened")
    elif case.get("status") == "WAITING_FOR_USER":
        repo.set_status(case_id, "IN_PROGRESS", actor="customer")
    try:
        from app.api.routes.command_center import command_center

        count = len([m for m in repo.thread(case_id, public_only=True) if m.get("from") == "customer"])
        command_center(container).notify_once(f"support_reply:{case_id}:{count}", "support_reply",
                                              f"Customer replied on ticket #{case_id}", str(case_id))
    except Exception:
        pass
    return support_case_status(case_id, request)


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


# ------------------------------------------------- question localization --
# Deal questions are written once (English) in the category schema; the
# conversation can be in any language the model supports. Translated once
# per (text, language) and cached; the app keeps its own fallback.
_LOCALIZED: dict[tuple[str, str], str] = {}
_LOCALIZED_MAX = 2000


class LocalizeRequest(BaseModel):
    text: str = Field(min_length=1, max_length=300)
    language: str = Field(min_length=2, max_length=35)


def _localizer(container: Any):
    custom = getattr(container, "question_localizer", None)
    if custom is not None:
        return custom
    ai = getattr(container, "universal_ai_assistant_service", None)
    client = getattr(ai, "client", None)
    if client is None:
        return None

    def call(prompt: str) -> dict[str, Any]:
        response = ai._generate_with_retry(client, prompt, None)
        return ai._parse_json(getattr(response, "text", "") or "")

    return call


@router.post("/assistant/localize")
def localize_question(payload: LocalizeRequest, request: Request) -> dict:
    """One short customer-facing question in the conversation language."""
    from app.services import rate_limit

    rate_limit.check(request, "localize", limit=60)
    language = payload.language.strip()
    text = " ".join(payload.text.split())
    if language.lower().split("-")[0] == "en":
        return {"text": text, "language": language, "localized": False}
    key = (text, language.lower())
    if key in _LOCALIZED:
        return {"text": _LOCALIZED[key], "language": language, "localized": True}
    call = _localizer(request.app.state.container)
    if call is None:
        raise HTTPException(status_code=503, detail="LOCALIZE_UNAVAILABLE")
    prompt = (
        "Translate this short question for a shopping assistant into the language with BCP-47 tag "
        f"'{language}'. Keep product words customers normally say in that language (English loanwords "
        "are fine when that is how people speak). Reply ONLY with JSON {\"text\": \"...\"}.\n"
        f"Question: {text}"
    )
    try:
        out = str((call(prompt) or {}).get("text") or "").strip()
    except Exception:
        out = ""
    if not out or len(out) > 400:
        raise HTTPException(status_code=503, detail="LOCALIZE_FAILED")
    if len(_LOCALIZED) >= _LOCALIZED_MAX:
        _LOCALIZED.clear()
    _LOCALIZED[key] = out
    return {"text": out, "language": language, "localized": True}
