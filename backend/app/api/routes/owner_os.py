"""Owner OS routes (see app/services/owner_os.py).

Customer: GET /api/greeting, GET /api/priority-credits/mine.
Admin:    GET /admin/cc/owner/setup, POST /admin/cc/owner/seed-staging (refused in
production), POST /admin/cc/delivery/match, GET /admin/cc/priority-credits/{user_ref}.
"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from app.services import owner_os

router = APIRouter(tags=["owner-os"])
admin_router = APIRouter(prefix="/admin/cc", tags=["command-center"])


def credits(container: Any) -> owner_os.PriorityCredits:
    c = getattr(container, "priority_credits", None)
    if c is None or c.db_path != container.settings.database_path:
        c = owner_os.PriorityCredits(container.settings.database_path)
        container.priority_credits = c
    return c


def _greeting_log(container: Any) -> owner_os.GreetingLog:
    g = getattr(container, "greeting_log", None)
    if g is None or g.db_path != container.settings.database_path:
        g = owner_os.GreetingLog(container.settings.database_path)
        container.greeting_log = g
    return g


def _resources(container: Any):
    from app.api.routes.platform import platform

    return platform(container).resources


def active_credit_rule(container: Any):
    return owner_os.PriorityCredits.active_rule(_resources(container).repo.list("referral_credit_rules"))


def award_referral_credits(container: Any, referral: Dict[str, Any]) -> Dict[str, Any]:
    """Called after a successful referral redemption. Never raises."""
    from app.api.routes.command_center import feature_enabled

    try:
        if not feature_enabled(container, "referrals.priority_credits"):
            return {"granted": 0, "reason": "flag_off"}
        from app.api.routes.growth import growth

        referrer = referral["referrer_user_id"]
        count = sum(1 for r in growth(container).referrals(referrer_user_id=referrer)
                    if r.get("status") != "INVITED")
        return credits(container).award_referral(referrer, referral_count=count, rule=active_credit_rule(container),
                                                 roles=_roles(container, referrer), ref=f"referral:{referral['id']}")
    except Exception:
        return {"granted": 0, "reason": "error"}


def _roles(container: Any, user_id: str) -> list[str]:
    try:
        import json
        import sqlite3

        with sqlite3.connect(container.settings.database_path) as conn:
            row = conn.execute("SELECT roles_json FROM user_profiles WHERE user_id=?", (user_id,)).fetchone()
        return [str(r) for r in json.loads(row[0] or "[]")] if row else []
    except Exception:
        return []


@router.get("/api/greeting")
def greeting(request: Request, language: str = Query("en", max_length=35), local_hour: int = Query(ge=0, le=23),
             returning: bool = False, name: str = Query("", max_length=40), last: str = Query("", max_length=300)
             ) -> dict:
    """Localized greeting for the user's local hour, language and context --
    at most once every few hours per signed-in user, rotated to avoid repeats."""
    from app.api.routes.in_app_assistant import _optional_app_user

    container = request.app.state.container
    user = _optional_app_user(request)
    templates = _resources(container).repo.list("greeting_templates")
    return owner_os.greet(templates, _greeting_log(container) if user != "guest" else None,
                          user_id="" if user == "guest" else user, local_hour=local_hour, language=language,
                          name=name.strip(), returning=returning, last_text=last)


@router.get("/api/priority-credits/mine")
def my_credits(request: Request) -> dict:
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.in_app_deal import _authenticated_app_user

    container = request.app.state.container
    user = _authenticated_app_user(request)
    rule = active_credit_rule(container)
    d = (rule or {}).get("data") or {}
    return {"enabled": feature_enabled(container, "referrals.priority_credits"),
            "balance": credits(container).balance(user), "history": credits(container).history(user, 20),
            "rule": None if rule is None else {
                "referrals_required": d.get("referrals_required"), "credits_awarded": d.get("credits_awarded"),
                "bonus_slabs": d.get("bonus_slabs") or {}, "expiry_days": d.get("expiry_days"),
                "max_balance": d.get("max_balance"),
                "eligible_notification_types": d.get("eligible_notification_types") or []}}


def _require(request: Request, perm: str) -> Dict[str, Any]:
    from app.api.routes.command_center import _require as require

    return require(request, perm)


@admin_router.get("/priority-credits/{user_id}")
def admin_user_credits(user_id: str, request: Request) -> dict:
    _require(request, "growth:view")
    container = request.app.state.container
    return {"balance": credits(container).balance(user_id), "history": credits(container).history(user_id)}


class MatchBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    service: str = Field(min_length=2, max_length=30)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


@admin_router.post("/delivery/match")
def delivery_match(body: MatchBody, request: Request) -> dict:
    """Preview which delivery partners (Party B) would receive a request."""
    _require(request, "delivery:view")
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.platform import platform

    container = request.app.state.container
    pf = platform(container)

    def ready(key: str) -> bool:
        try:
            return pf.registry.status(key)["status"] in ("LIVE", "TEST")
        except Exception:
            return False

    result = owner_os.match_delivery(pf.resources.repo.list("delivery_partners"), service=body.service,
                                     latitude=body.latitude, longitude=body.longitude, integration_ready=ready)
    return {**result, "matching_enabled": feature_enabled(container, "delivery.matching")}


@admin_router.get("/owner/setup")
def owner_setup(request: Request) -> dict:
    """One readiness view: e-mail roles, integrations, QA findings, Owner OS switches."""
    _require(request, "config:view")
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.platform import platform
    from app.services.commerce_finance import is_production

    container = request.app.state.container
    pf = platform(container)
    repo = pf.resources.repo
    qa: Dict[str, int] = {}
    for r in repo.list("qa_checks"):
        qa[r["status"]] = qa.get(r["status"], 0) + 1
    try:
        integrations = [{"key": i.get("provider"), "status": i.get("status")} for i in pf.registry.all()]
    except Exception:
        integrations = []
    flags = ("referrals.priority_credits", "location.proximity_alerts", "location.background_optin",
             "delivery.matching", "notifications.promotions", "companion.screen_guide")
    return {"environment": "production" if is_production(pf.registry.env) else "staging/local",
            "email_roles": [{"role": r["data"].get("role"), "address": r["data"].get("address"),
                             "mode": r["data"].get("mode"), "status": r["status"],
                             "verified_on": r["data"].get("verified_on") or ""} for r in repo.list("email_roles")],
            "integrations": integrations, "qa": qa,
            "flags": {k: feature_enabled(container, k) for k in flags},
            "credit_rule": (active_credit_rule(container) or {}).get("name")}


@admin_router.post("/owner/seed-staging")
def seed_staging(request: Request) -> dict:
    """Idempotent staging test data (open phone findings, a test credit rule,
    greeting texts, e-mail role placeholders). Refused in production."""
    principal = _require(request, "config:manage")
    from app.api.routes.platform import platform
    from app.services.commerce_finance import is_production

    pf = platform(request.app.state.container)
    if is_production(pf.registry.env):
        raise HTTPException(status_code=403, detail="Staging defaults are never loaded in production.")
    return {"created": owner_os.seed_staging_defaults(pf.resources, actor=str(principal.get("id") or "admin"))}
