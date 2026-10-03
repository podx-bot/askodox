"""AI Companion Screen Guide API (see app/services/screen_guide.py).

Customer: /api/companion/guide/* (signed in; feature flag companion.screen_guide,
OFF by default). Admin: /admin/cc/companion/screen-guide (companion:view) --
aggregate counts only, never screen content.
"""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from app.services.screen_guide import ScreenGuide

router = APIRouter(prefix="/api/companion/guide", tags=["screen-guide"])
admin_router = APIRouter(prefix="/admin/cc/companion", tags=["command-center"])


def _llm(container: Any):
    custom = getattr(container, "screen_guide_llm", None)
    if custom is not None:
        return custom
    ai = getattr(container, "universal_ai_assistant_service", None)
    client = getattr(ai, "client", None)
    if client is None:
        return None

    def call(prompt: str) -> Dict[str, Any]:
        response = ai._generate_with_retry(client, prompt, None)
        return ai._parse_json(getattr(response, "text", "") or "")

    return call


def guide(container: Any) -> ScreenGuide:
    g = getattr(container, "screen_guide", None)
    if g is None or g.db_path != container.settings.database_path:
        g = ScreenGuide(container.settings.database_path, llm=_llm(container))
        container.screen_guide = g
    return g


CONSENT_VERSION = "sg-disclosure-v1"
CAPABILITY_FLAGS = ("companion.enabled", "companion.floating_bubble", "companion.screen_guide",
                    "companion.accessibility", "companion.privacy_shield")
POLICY_NOTICE = ("Screen Guide is not available right now. ASKODOX works normally -- you can still ask in chat "
                 "and get step-by-step written help.")


def capabilities(container: Any) -> Dict[str, bool]:
    from app.api.routes.command_center import feature_enabled

    return {key.split(".", 1)[1]: feature_enabled(container, key) for key in CAPABILITY_FLAGS}


def _enabled(container: Any) -> bool:
    """Every switch must be on. Privacy Shield is fail-closed: turning it off
    stops the guide instead of running it unprotected."""
    c = capabilities(container)
    return c["enabled"] and c["screen_guide"] and c["accessibility"] and c["privacy_shield"]


def _user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


def _live(request: Request) -> ScreenGuide:
    container = request.app.state.container
    if not _enabled(container):
        raise HTTPException(status_code=503, detail="SCREEN_GUIDE_DISABLED")
    return guide(container)


class StartBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    goal: str = Field(min_length=2, max_length=200)
    language: str = Field(default="en", max_length=12)
    permissions: Dict[str, bool] = Field(default_factory=dict)
    consent_version: str = Field(default="", max_length=40)


class Element(BaseModel):
    model_config = ConfigDict(extra="ignore")
    label: str = Field(default="", max_length=300)
    role: str = Field(default="", max_length=40)
    hint: str = Field(default="", max_length=200)
    id: str = Field(default="", max_length=120)
    clickable: bool = False
    password: bool = False
    input: str = Field(default="", max_length=30)


class Screen(BaseModel):
    model_config = ConfigDict(extra="ignore")
    package: str = Field(default="", max_length=200)
    app_label: str = Field(default="", max_length=120)
    title: str = Field(default="", max_length=200)
    secure_window: bool = False
    sensitive_hint: bool = False
    elements: List[Element] = Field(default_factory=list, max_length=200)


class StepBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=4, max_length=80)
    screen: Screen


class SessionBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: str = Field(min_length=4, max_length=80)
    outcome: str = "abandoned"
    failure: str = ""


@router.get("/status")
def status(request: Request) -> dict:
    """Public switches for the app (no user data): each companion capability
    can be turned off on its own; ASKODOX itself keeps working."""
    container = request.app.state.container
    enabled = _enabled(container)
    return {"enabled": enabled, "model": _llm(container) is not None, "capabilities": capabilities(container),
            "consent_version": CONSENT_VERSION, "notice": None if enabled else POLICY_NOTICE}


@router.post("/start")
def start(body: StartBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "guide_start", limit=10)
    g = _live(request)
    if body.consent_version != CONSENT_VERSION:
        # The prominent disclosure must have been shown and accepted first.
        raise HTTPException(status_code=428, detail="SCREEN_GUIDE_CONSENT_REQUIRED")
    return g.start(_user(request), body.goal, body.language, body.permissions)


@router.post("/step")
def step(body: StepBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "guide_step", limit=40)
    container = request.app.state.container
    if not _enabled(container):
        # Kill switch mid-guide: the phone shows the notice and ends the guide;
        # the screen sent with this request is not processed at all.
        user = _user(request)
        try:
            guide(container).end(user, body.session_id, "abandoned", "")
        except KeyError:
            pass
        return {"state": "DISABLED", "message": POLICY_NOTICE}
    g = guide(container)
    try:
        return g.step(_user(request), body.session_id, body.screen.model_dump())
    except KeyError:
        raise HTTPException(status_code=404, detail="Guide session ended") from None


@router.post("/resume")
def resume(body: SessionBody, request: Request) -> dict:
    g = _live(request)
    try:
        return g.resume(_user(request), body.session_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Guide session ended") from None


@router.post("/end")
def end(body: SessionBody, request: Request) -> dict:
    # Ending always works (even if the flag was switched off meanwhile).
    g = guide(request.app.state.container)
    try:
        return g.end(_user(request), body.session_id, body.outcome, body.failure)
    except KeyError:
        return {"state": "ENDED", "retained": "nothing from the screens; only anonymous counts"}


@admin_router.get("/screen-guide")
def admin_screen_guide(request: Request, days: int = 30) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "companion:view")
    container = request.app.state.container
    return {"enabled": _enabled(container), "flag": "companion.screen_guide",
            "capabilities": capabilities(container), "consent_version": CONSENT_VERSION,
            "model_configured": _llm(container) is not None,
            "stats": guide(container).stats(max(1, min(days, 365))),
            "privacy": ["No screenshots are taken or stored.",
                        "Screen text is used only for the current step and never stored or logged.",
                        "OTP / password / PIN / UPI PIN / CVV / bank / Aadhaar screens and payment apps pause the "
                        "guide on the phone before anything is sent.",
                        "Resume needs the user's double-tap or Continue.",
                        "End Guide clears the session; only anonymous counts remain."]}
