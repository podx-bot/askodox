"""Travel Radio add-on routes (see ``app/services/travel_radio.py``).

Customer (signed in):  GET /api/radio/status, POST /api/radio/pass,
                       POST /api/radio/next
Staff:                 GET /admin/cc/radio (plans, passes, usage, cost model),
                       POST /admin/cc/radio/passes (PROMOTIONAL pass only)

No route here takes money or activates a plan: paid passes wait for a
payment gateway (PENDING_PAYMENT); plans are edited in Growth -> Plans.
"""
from __future__ import annotations

import base64
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.growth import growth
from app.api.routes.in_app_deal import _authenticated_app_user
from app.services.travel_radio import ADDON_AUDIENCE, TravelRadio, cost_model, setting

router = APIRouter(prefix="/api/radio", tags=["radio"])
admin_router = APIRouter(prefix="/admin/cc/radio", tags=["command-center"])


def radio(container: Any) -> TravelRadio:
    service = getattr(container, "travel_radio", None)
    if service is None:
        service = TravelRadio(container.settings.database_path)
        TravelRadio.seed_plans(growth(container))
        container.travel_radio = service
    return service


def _enabled(container: Any) -> bool:
    from app.api.routes.command_center import feature_enabled

    return feature_enabled(container, "radio.enabled")


def _plan_rows(container: Any) -> list[dict]:
    return [{"code": p["code"], "name": p["name"], "price": p["price"], "period_days": p["period_days"],
             "available": bool(p["active"])} for p in TravelRadio.plans(growth(container))]


@router.get("/status")
def radio_status(request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    service = radio(container)
    current = service.current_pass(user)
    return {
        "enabled": _enabled(container),
        "access": service.has_access(user),
        "pass": current,
        "plans": _plan_rows(container),
        "minutes_today": round(service.seconds_today(user) / 60, 1),
        "daily_minutes": setting("radio.daily_minutes"),
        "billing": "not_available",  # no payment gateway is configured
    }


class PassRequest(BaseModel):
    plan_code: str = Field(min_length=1, max_length=40)


@router.post("/pass")
def request_radio_pass(payload: PassRequest, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    plan = growth(container).plan(payload.plan_code)
    if not plan or plan.get("audience") != ADDON_AUDIENCE or not plan["active"]:
        raise HTTPException(status_code=409, detail="PLAN_NOT_AVAILABLE")
    try:
        item = radio(container).request_pass(user, plan)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from None
    return {"pass": item, "note": "Payment is not available in the app yet; the pass starts after payment is confirmed."}


class NextRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    lang: str = Field(default="en", pattern="^(en|te|hi)$")
    voice: str = Field(default="automatic", pattern="^(automatic|male|female)$")
    audio: bool = True


@router.post("/next")
def next_segment(payload: NextRequest, request: Request) -> dict:
    from app.api.routes.affiliate_catalog import catalog
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "radio", limit=30)
    container = request.app.state.container
    if not _enabled(container):
        raise HTTPException(status_code=503, detail="RADIO_DISABLED")
    service = radio(container)
    if not service.has_access(user):
        raise HTTPException(status_code=402, detail="RADIO_ADDON_REQUIRED")
    if service.seconds_today(user) >= setting("radio.daily_minutes") * 60:
        raise HTTPException(status_code=429, detail="RADIO_DAILY_LIMIT")
    facts, calls = service.area_facts(getattr(container, "google_maps_service", None),
                                      payload.latitude, payload.longitude)
    try:
        news = catalog(container).content(limit=5)
    except Exception:
        news = []
    from app.services.travel_radio import _cell

    candidates = TravelRadio.segments(facts, news, payload.lang, _cell(payload.latitude, payload.longitude))
    segment = service.next_segment(user, candidates)
    if segment is None:
        return {"status": "nothing_new", "segment": None}
    audio, mime, synthesized = (None, "", 0)
    if payload.audio:
        synthesize = getattr(getattr(container, "voice_assistant_service", None), "synthesize", None)
        audio, mime, synthesized = service.audio_for(segment["text"], synthesize, payload.voice)
    seconds = service.record(user, segment, synthesized_chars=synthesized, places_calls=calls)
    return {
        "status": "ok",
        "segment": segment,
        "audio_b64": base64.b64encode(audio).decode() if audio else None,
        "audio_mime": mime or None,
        "audio_cached": bool(audio) and synthesized == 0,
        "seconds": round(seconds, 1),
    }


# -------------------------------------------------------------- staff --

def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


@admin_router.get("")
def admin_radio(request: Request) -> dict:
    _require(request, "growth:view")
    container = request.app.state.container
    service = radio(container)
    plans = TravelRadio.plans(growth(container))
    return {"enabled": _enabled(container), "plans": plans, "passes": service.passes(100),
            "usage": service.usage_summary(30), "cost_model": cost_model(plans)}


class GrantRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=80)
    plan_code: str = Field(min_length=1, max_length=40)


@admin_router.post("/passes")
def admin_grant_pass(payload: GrantRequest, request: Request) -> dict:
    """A PROMOTIONAL pass (no money moves). Paid passes need a gateway."""
    principal = _require(request, "growth:manage")
    container = request.app.state.container
    plan = growth(container).plan(payload.plan_code)
    if not plan or plan.get("audience") != ADDON_AUDIENCE:
        raise HTTPException(status_code=404, detail="Unknown add-on plan")
    actor = str(principal.get("id") or principal.get("name") or "staff")
    return {"pass": radio(container).grant_promotional(payload.user_id, plan, granted_by=actor)}
