"""Travel Radio add-on routes (see ``app/services/travel_radio.py``).

Customer (signed in):  GET /api/radio/status, POST /api/radio/pass,
                       POST /api/radio/next
Staff:                 GET /admin/cc/radio (plans, passes, usage, cost model),
                       POST /admin/cc/radio/passes (PROMOTIONAL pass only)

No route here takes money or activates a plan. Owner decision 2026-11-04:
Radio has NO separate package -- with the customer flag on, every signed-in
person may listen and each segment is one AI Credits use (feature "radio";
free while AI Credits charging is OFF). The older add-on passes still grant
access if one exists (no new ones are sold).
"""
from __future__ import annotations

import base64
import uuid
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


def _testing_on(container: Any) -> bool:
    from app.api.routes.command_center import feature_enabled

    return feature_enabled(container, "radio.internal_testing")


def _tester(container: Any, service: TravelRadio, user: str) -> bool:
    return _testing_on(container) and service.is_tester(user)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    try:
        from app.api.routes.command_center import command_center

        command_center(request.app.state.container).audit(principal["id"], action, "radio_tester", target,
                                                          after=detail or {})
    except Exception:
        pass


def _daily_cap(container: Any, service: TravelRadio, user: str) -> float:
    """Platform cap, tightened by the pass plan's own usage limit
    (entitlements.limits.radio_minutes_per_day) when staff set one."""
    cap = setting("radio.daily_minutes")
    current = service.current_pass(user) or {}
    if current.get("status") == "ACTIVE":
        plan = growth(container).plan(current.get("plan_code") or "") or {}
        limit = ((plan.get("entitlements") or {}).get("limits") or {}).get("radio_minutes_per_day")
        if isinstance(limit, (int, float)) and not isinstance(limit, bool) and limit >= 0:
            cap = min(cap, float(limit))
    return cap


def _plan_rows(container: Any) -> list[dict]:
    return [{"code": p["code"], "name": p["name"], "price": p["price"], "period_days": p["period_days"],
             "available": bool(p["active"])} for p in TravelRadio.plans(growth(container))]


@router.get("/status")
def radio_status(request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    service = radio(container)
    current = service.current_pass(user)
    tester = _tester(container, service, user)
    enabled = _enabled(container)
    return {
        "enabled": enabled or tester,
        "internal_testing": tester,
        # Radio runs on AI Credits: the flag alone opens it to every signed-in person.
        "access": tester or enabled or (current or {}).get("status") == "ACTIVE",
        "pass": current,
        "plans": _plan_rows(container),
        "minutes_today": round(service.seconds_today(user) / 60, 1),
        "daily_minutes": _daily_cap(container, service, user),
        "billing": "ai_credits",
        "credits": _credits_state(container),
    }


def _credits_state(container: Any) -> dict:
    """Whether a segment costs AI Credits right now (never a separate pass)."""
    try:
        from app.api.routes.ai_credits import ai_credits

        settings = ai_credits(container).settings()
        rate = settings["rates_paise"].get("radio", 0) if settings["charging"] else 0
        return {"charging": bool(settings["charging"]), "rate_paise": int(rate)}
    except Exception:
        return {"charging": False, "rate_paise": 0}


def _reserve_radio_credit(container: Any, user: str) -> dict:
    """One AI Credits use for one segment. Raises 402 AI_CREDITS_LOW when the
    balance cannot cover it; free while charging is OFF."""
    from app.api.routes.ai_credits import ai_credits
    from app.services.ai_credits import CreditsError

    ref = f"radio:{user}:{uuid.uuid4().hex}"
    try:
        result = ai_credits(container).reserve(user, "radio", ref)
    except CreditsError as error:
        if error.code == "insufficient":
            raise HTTPException(status_code=402, detail="AI_CREDITS_LOW") from None
        raise
    return {**result, "ref": ref}


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
    service = radio(container)
    # Customers need the flag; staff-chosen internal testers do not.
    tester = _tester(container, service, user)
    if not _enabled(container) and not tester:
        raise HTTPException(status_code=503, detail="RADIO_DISABLED")
    paid = (service.current_pass(user) or {}).get("status") == "ACTIVE"
    if service.seconds_today(user) >= _daily_cap(container, service, user) * 60:
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
        return {"status": "nothing_new", "segment": None}  # nothing played -> nothing charged
    # Testers and old passes listen free; everyone else uses AI Credits.
    credit = {"charged": False, "paise": 0} if (paid or tester) else _reserve_radio_credit(container, user)
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
        "credits": {"charged": bool(credit.get("charged")), "paise": int(credit.get("paise") or 0)},
    }


class TownRequest(BaseModel):
    place: str = Field(min_length=2, max_length=60)
    lang: str = Field(default="te", pattern="^(en|te|hi)$")
    voice: str = Field(default="automatic", pattern="^(automatic|male|female)$")
    audio: bool = True


# (place key, lang) -> (fetched at, headlines). Same town within 30 minutes =
# no new web search for anyone (per process).
_TOWN_CACHE: dict = {}
_TOWN_TTL = 30 * 60


def _town_headlines(container: Any, place: str) -> list:
    """Real headlines only: the web-search chain's answer for the town plus
    staff-approved LIVE news that names it. Never written by a model."""
    import time
    from urllib.parse import urlparse

    from app.api.routes.universal_deals import _web_search

    key = " ".join(place.lower().split())
    hit = _TOWN_CACHE.get(key)
    if hit and time.time() - hit[0] < _TOWN_TTL:
        return hit[1]
    rows: list = []
    search = _web_search(container)
    if search is not None:
        try:
            rows = list(search(f"{place} latest news", 8) or [])
        except Exception:
            rows = []
    try:
        from app.api.routes.affiliate_catalog import catalog

        live = [r for r in catalog(container).content(limit=40) if key in str(r.get("title") or "").lower()]
    except Exception:
        live = []
    out, seen = [], set()
    for row in live + rows:
        title = " ".join(str(row.get("title") or "").split())
        if len(title) < 8 or title.lower() in seen:
            continue
        seen.add(title.lower())
        url = str(row.get("url") or row.get("link") or "")
        out.append({"title": title[:160], "url": url,
                    "source": str(row.get("publisher") or "") or urlparse(url).netloc.replace("www.", ""),
                    "published_at": row.get("published_at")})
        if len(out) >= 5:
            break
    if out:
        _TOWN_CACHE[key] = (time.time(), out)
    return out


@router.post("/town")
def town_news(payload: TownRequest, request: Request) -> dict:
    """Any town's latest news, read aloud: one bulletin = one AI Credits
    ``radio`` use (free while charging is OFF). Nothing found -> nothing
    played, nothing charged."""
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "radio-town", limit=10)
    container = request.app.state.container
    service = radio(container)
    tester = _tester(container, service, user)
    if not _enabled(container) and not tester:
        raise HTTPException(status_code=503, detail="RADIO_DISABLED")
    paid = (service.current_pass(user) or {}).get("status") == "ACTIVE"
    if service.seconds_today(user) >= _daily_cap(container, service, user) * 60:
        raise HTTPException(status_code=429, detail="RADIO_DAILY_LIMIT")
    place = " ".join(payload.place.split())
    headlines = _town_headlines(container, place)
    if not headlines:
        return {"status": "nothing_found", "place": place, "headlines": []}
    te = payload.lang == "te"
    intro = f"{place} తాజా వార్తలు." if te else f"Latest news from {place}."
    text = " ".join([intro] + [f"{i + 1}. {h['title']}." for i, h in enumerate(headlines)])
    credit = {"charged": False, "paise": 0} if (paid or tester) else _reserve_radio_credit(container, user)
    audio, mime, synthesized = (None, "", 0)
    if payload.audio:
        synthesize = getattr(getattr(container, "voice_assistant_service", None), "synthesize", None)
        audio, mime, synthesized = service.audio_for(text, synthesize, payload.voice)
    segment = {"key": "town:" + place.lower() + ":" + headlines[0]["title"][:40].lower(), "text": text}
    seconds = service.record(user, segment, synthesized_chars=synthesized, places_calls=0)
    return {
        "status": "ok",
        "place": place,
        "headlines": headlines,
        "text": text,
        "audio_b64": base64.b64encode(audio).decode() if audio else None,
        "audio_mime": mime or None,
        "seconds": round(seconds, 1),
        "credits": {"charged": bool(credit.get("charged")), "paise": int(credit.get("paise") or 0)},
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
    return {"enabled": _enabled(container), "internal_testing": _testing_on(container),
            "billing": "INACTIVE", "testers": service.testers(), "plans": plans,
            "passes": service.passes(100),
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


class TesterRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=80)
    note: str = Field(default="", max_length=200)


@admin_router.post("/testers")
def admin_add_tester(payload: TesterRequest, request: Request) -> dict:
    """Internal testing: this user hears Radio while customers stay off.
    No pass, no price, no billing."""
    from app.services import tester_identity

    principal = _require(request, "growth:manage")
    actor = str(principal.get("id") or principal.get("name") or "staff")
    user_id = tester_identity.tester_user_id(payload.user_id)
    if tester_identity.is_demo_account(user_id):
        raise HTTPException(status_code=409, detail="DEMO_ACCOUNT_NOT_ALLOWED: the shared demo login cannot be a "
                                                    "tester -- add the person's own number")
    out = radio(request.app.state.container).add_tester(user_id, added_by=actor, note=payload.note)
    _audit(request, principal, "radio.tester.add", user_id, {"note": payload.note})
    return out


@admin_router.delete("/testers/{user_id}")
def admin_remove_tester(user_id: str, request: Request) -> dict:
    from app.services import tester_identity

    principal = _require(request, "growth:manage")
    user_id = tester_identity.tester_user_id(user_id)
    removed = radio(request.app.state.container).remove_tester(user_id)
    _audit(request, principal, "radio.tester.remove", user_id, {"removed": removed})
    return {"user_id": user_id, "removed": removed}
