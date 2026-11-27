"""Guide session routes (see ``app/services/guide_session.py``).

Customer (signed in):
  GET    /api/me/guide-session ............... where the person is: status, done / left topics
  POST   /api/me/guide-session/start ......... {minutes} -- any time is accepted
  POST   /api/me/guide-session/consent ....... {consent} -- nothing is kept without it; false also deletes what was kept
  POST   /api/me/guide-session/turn .......... {answer, language, asked_why, not_understood, skip} -> the next question
  POST   /api/me/guide-session/pause ......... time is up: what is done, what is left
  GET    /api/me/guide-session/arrangement ... page ids to bring to the front from the kept answers (move only)
  GET    /api/me/guide-session/facts ......... what was kept (the person's own words)
  DELETE /api/me/guide-session/facts ......... one topic (?topic=) or everything
  GET    /api/me/guide-reminders ............. unfinished setup + one feature that fits what they said
  POST   /api/me/guide-reminders/dismiss ..... "వద్దు" / "ఇక చూపించకు"
  POST   /api/me/feature-requests ............ a need the app cannot meet yet; ``consent`` true, name-less
Staff:
  GET    /admin/cc/feature-requests .......... the inbox (no names), most asked first
  POST   /admin/cc/feature-requests/{id} ..... {status, note, push_similar}; ``done`` tells the people who asked to be told
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import rate_limit
from app.services.guide_session import FeatureRequests, GuideError, GuideSessions

router = APIRouter(tags=["guide-session"])
admin_router = APIRouter(prefix="/admin/cc", tags=["command-center"])


def sessions(container: Any) -> GuideSessions:
    service = getattr(container, "guide_sessions", None)
    if service is None:
        def write_text(prompt: str) -> str:
            ai = getattr(container, "universal_ai_assistant_service", None)
            if ai is None or not hasattr(ai, "write_text"):
                raise RuntimeError("no model")
            return ai.write_text(prompt, max_tokens=700) or ""

        def tell(user: str, title: str, body: str, route: str, event_key: str) -> None:
            push = getattr(container, "push_service", None)
            if push is not None:
                push.notify_async(user, title=title, body=body, route=route, event_key=event_key)

        service = GuideSessions(container.settings.database_path, write_text=write_text, tell=tell)
        container.guide_sessions = service
    return service


def requests_inbox(container: Any) -> FeatureRequests:
    service = getattr(container, "feature_requests", None)
    if service is None:
        def notify(user: str, text: str) -> None:
            push = getattr(container, "push_service", None)
            if push is not None:
                push.notify(user, title="మీరు అడిగింది సిద్ధం", body="మీరు కోరినది ఇప్పుడు ASKODOX లో ఉంది. చూడండి.",
                            route="/", event_key="feature_ready")

        service = FeatureRequests(container.settings.database_path, notify=notify)
        container.feature_requests = service
    return service


def _user(request: Request, bucket: str, limit: int = 120) -> str:
    user = _authenticated_app_user(request)
    rate_limit.check(request, f"{bucket}:{user}", limit=limit)
    return user


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except GuideError as error:
        raise HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message}) from None


class StartBody(BaseModel):
    minutes: int = Field(default=10, ge=1, le=240)


class ConsentBody(BaseModel):
    consent: bool


class TurnBody(BaseModel):
    answer: str = Field(default="", max_length=1200)
    language: str = Field(default="te", max_length=10)
    asked_why: bool = False
    not_understood: bool = False
    skip: bool = False


class DismissBody(BaseModel):
    ref: str = Field(min_length=1, max_length=80)
    forever: bool = False


class FeatureBody(BaseModel):
    text: str = Field(min_length=1, max_length=600)
    consent: bool = False
    tell_me: bool = False


@router.get("/api/me/guide-session")
def status(request: Request, language: str = "te") -> Dict[str, Any]:
    return sessions(request.app.state.container).status(_user(request, "guide"), language)


@router.post("/api/me/guide-session/start")
def start(body: StartBody, request: Request) -> Dict[str, Any]:
    return sessions(request.app.state.container).start(_user(request, "guide", 40), body.minutes)


@router.post("/api/me/guide-session/consent")
def consent(body: ConsentBody, request: Request) -> Dict[str, Any]:
    return sessions(request.app.state.container).set_consent(_user(request, "guide", 40), body.consent)


@router.post("/api/me/guide-session/turn")
def turn(body: TurnBody, request: Request) -> Dict[str, Any]:
    user = _user(request, "guide-turn", 200)
    return _call(sessions(request.app.state.container).turn, user, body.answer, body.language,
                 asked_why=body.asked_why, not_understood=body.not_understood, skip=body.skip)


@router.post("/api/me/guide-session/pause")
def pause(request: Request) -> Dict[str, Any]:
    return sessions(request.app.state.container).pause(_user(request, "guide", 60))


@router.get("/api/me/guide-session/arrangement")
def arrangement(request: Request) -> Dict[str, Any]:
    return sessions(request.app.state.container).arrangement(_user(request, "guide"))


@router.get("/api/me/guide-session/facts")
def facts(request: Request) -> Dict[str, Any]:
    return {"facts": sessions(request.app.state.container).facts(_user(request, "guide"))}


@router.delete("/api/me/guide-session/facts")
def delete_facts(request: Request, topic: Optional[str] = None) -> Dict[str, Any]:
    svc = sessions(request.app.state.container)
    user = _user(request, "guide", 40)
    return {"deleted": svc.delete_facts(user, topic)}


@router.get("/api/me/guide-reminders")
def reminders(request: Request, language: str = "te", tried: str = "") -> Dict[str, Any]:
    user = _user(request, "guide")
    keys: List[str] = [t for t in tried.split(",") if t][:40]
    return {"reminders": sessions(request.app.state.container).reminders(user, language, tried=keys)}


@router.post("/api/me/guide-reminders/dismiss")
def dismiss(body: DismissBody, request: Request) -> Dict[str, Any]:
    sessions(request.app.state.container).dismiss(_user(request, "guide", 60), body.ref, body.forever)
    return {"ok": True}


@router.post("/api/me/feature-requests")
def feature_request(body: FeatureBody, request: Request) -> Dict[str, Any]:
    user = _user(request, "feature-requests", 20)
    return _call(requests_inbox(request.app.state.container).submit, user, body.text, consent=body.consent, tell_me=body.tell_me)


# --------------------------------------------------------------------- staff --
def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


class StatusBody(BaseModel):
    status: str = Field(max_length=20)
    note: str = Field(default="", max_length=300)
    push_similar: Optional[bool] = None


@admin_router.get("/feature-requests")
def staff_list(request: Request) -> Dict[str, Any]:
    _require(request, "analytics:view")
    return {"requests": requests_inbox(request.app.state.container).list()}


@admin_router.post("/feature-requests/{request_id}")
def staff_set(request_id: int, body: StatusBody, request: Request) -> Dict[str, Any]:
    _require(request, "analytics:view")
    return _call(requests_inbox(request.app.state.container).set_status, request_id, body.status, note=body.note,
                 push_similar=body.push_similar)
