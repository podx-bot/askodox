"""ASKODOX Talk routes: anonymous topic discussions (see services/anonymous_talk.py).

Customer: ``/api/talk/*`` -- every call needs sign-in (the account stays known
to ASKODOX, never to other people). Staff: ``/admin/cc/talk/*``.
"""
from __future__ import annotations

import base64
import uuid
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import talk_moderation
from app.services.anonymous_talk import AnonymousTalk, TalkError

router = APIRouter(prefix="/api/talk", tags=["talk"])
admin_router = APIRouter(prefix="/admin/cc/talk", tags=["talk-admin"])

# Shown to a person whose message spoke of hurting themselves (it is not posted).
SUPPORT = {
    "te": "మీరు ఒంటరి కాదు. మాట్లాడాలనిపిస్తే Tele-MANAS 14416 కి ఉచితంగా కాల్ చేయండి (24 గంటలు), "
          "లేదా మీకు నమ్మకమైన వ్యక్తితో మాట్లాడండి. అత్యవసరమైతే 112.",
    "en": "You are not alone. If you want to talk, call Tele-MANAS 14416 free, any time, or talk to someone you "
          "trust. In an emergency call 112.",
}


def talk(container: Any) -> AnonymousTalk:
    service = getattr(container, "anonymous_talk", None)
    path = container.settings.database_path
    if service is None or service.db_path != path:
        service = AnonymousTalk(path, getattr(container.settings, "session_token_secret", "") or "")
        container.anonymous_talk = service
    return service


def _writer(container: Any):
    service = getattr(container, "universal_ai_assistant_service", None)
    write = getattr(service, "write_text", None)
    return write if callable(write) else None


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except TalkError as error:
        raise HTTPException(status_code=error.status, detail=error.code) from None


class OpenIn(BaseModel):
    topic: str = Field(min_length=1, max_length=120)
    adult: bool = False


class PostIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    kind: str = Field(default="text", pattern="^(text|voice)$")
    lang: str = Field(default="te", pattern="^(te|en|hi)$")


class ReportIn(BaseModel):
    reason: str = Field(default="other", max_length=40)


class SpeakIn(BaseModel):
    lang: str = Field(default="te", pattern="^(te|en|hi)$")


@router.get("/rooms")
def rooms(request: Request, q: str = "") -> dict:
    from app.services import rate_limit

    _authenticated_app_user(request)
    rate_limit.check(request, "talk-read", limit=120)
    return {"rooms": talk(request.app.state.container).rooms(q[:80])}


@router.post("/rooms")
def open_room(body: OpenIn, request: Request) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    if not body.adult:
        raise HTTPException(status_code=403, detail="ADULTS_ONLY")
    rate_limit.check(request, "talk-open", limit=20)
    container = request.app.state.container
    return {"room": _call(talk(container).open_room, body.topic, user, _writer(container))}


@router.get("/rooms/{room_id}/messages")
def messages(room_id: str, request: Request, after: int = 0) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "talk-read", limit=120)
    service = talk(request.app.state.container)
    room = _call(service.room, room_id)
    te, en = service.alias(user, room_id)
    return {"room": room, "you": {"alias": te, "alias_en": en}, "muted_until": service.muted_until(user),
            "messages": _call(service.messages, room_id, user, max(0, after))}


@router.post("/rooms/{room_id}/messages")
def post(room_id: str, body: PostIn, request: Request) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "talk-post", limit=12)
    container = request.app.state.container
    out = _call(talk(container).post, room_id, user, body.text, body.kind, _writer(container))
    if out["category"] == "self_harm":
        out["support"] = SUPPORT["te" if body.lang == "te" else "en"]
    return out


@router.post("/messages/{message_id}/report")
def report(message_id: str, body: ReportIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    return _call(talk(request.app.state.container).report, message_id, user, body.reason)


@router.post("/messages/{message_id}/block")
def block(message_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    return _call(talk(request.app.state.container).block, message_id, user)


@router.post("/messages/{message_id}/speak")
def speak(message_id: str, body: SpeakIn, request: Request) -> dict:
    """Reads one message aloud in the ASKODOX voice (never the writer's own
    voice); masked words are spoken as "beep". One AI Credits ``voice`` use,
    free while charging is OFF; reading the text stays free."""
    from app.api.routes.ai_credits import ai_credits
    from app.services import rate_limit
    from app.services.ai_credits import CreditsError

    user = _authenticated_app_user(request)
    rate_limit.check(request, "talk-speak", limit=30)
    container = request.app.state.container
    text = talk_moderation.spoken(_call(talk(container).visible_text, message_id), body.lang == "te")
    ref = f"talk:{user}:{uuid.uuid4().hex}"
    try:
        credit = ai_credits(container).reserve(user, "voice", ref)
    except CreditsError as error:
        if error.code == "insufficient":
            raise HTTPException(status_code=402, detail="AI_CREDITS_LOW") from None
        raise
    synthesize = getattr(getattr(container, "voice_assistant_service", None), "synthesize", None)
    audio = None
    if callable(synthesize):
        try:
            result = synthesize(text) or {}
            if result.get("success") and result.get("content"):
                audio = result["content"]
        except Exception:
            audio = None
    if audio is None and credit.get("charged"):
        try:
            ai_credits(container).release(user, ref)
        except Exception:
            pass
        credit = {"charged": False, "paise": 0}
    return {"text": text, "audio_b64": base64.b64encode(audio).decode() if audio else None,
            "credits": {"charged": bool(credit.get("charged")), "paise": int(credit.get("paise") or 0)}}


# -------------------------------------------------------------- staff --

def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


@admin_router.get("/reports")
def admin_reports(request: Request) -> dict:
    _require(request, "growth:view")
    return {"reports": talk(request.app.state.container).open_reports()}


class DecideIn(BaseModel):
    remove: bool


@admin_router.post("/messages/{message_id}/decision")
def admin_decide(message_id: str, body: DecideIn, request: Request) -> dict:
    _require(request, "growth:manage")
    return _call(talk(request.app.state.container).decide, message_id, body.remove)
