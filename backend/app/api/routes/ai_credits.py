"""AI Credits routes (see ``app/services/ai_credits.py``).

Customer (signed in): GET /api/me/ai-credits -- balance (live + TEST), today's use, rates, packs (buy through
POST /api/billing/checkout with the pack's plan_code), history.
Staff: GET|PUT /admin/cc/ai-credits/settings (growth:view / growth:manage, audited), GET /admin/cc/ai-credits/summary.
There is deliberately NO route that adds credits by hand or from the app: only a gateway-confirmed payment does.
"""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services.ai_credits import AUDIENCE, AiCredits, CreditsError, pack_credits_paise, seed_packs

router = APIRouter(prefix="/api/me/ai-credits", tags=["ai-credits"])
admin_router = APIRouter(prefix="/admin/cc/ai-credits", tags=["command-center"])


def ai_credits(container: Any) -> AiCredits:
    service = getattr(container, "ai_credits", None)
    if service is None:
        from app.api.routes.growth import growth

        service = AiCredits(container.settings.database_path)
        seed_packs(growth(container))
        container.ai_credits = service
    return service


def _error(error: CreditsError) -> HTTPException:
    return HTTPException(status_code=error.status, detail={"code": error.code, **error.detail})


@router.get("")
def my_credits(request: Request) -> Dict[str, Any]:
    from app.api.routes.growth import growth
    from app.services import billing

    user = _authenticated_app_user(request)
    container = request.app.state.container
    service = ai_credits(container)
    settings = service.settings()
    payable = {i["plan_code"]: i for i in billing.options(container, user)["items"] if i.get("kind") == "credits"}
    packs = [{"plan_code": p["code"], "name": p["name"], "price": p["price"], "credits_paise": pack_credits_paise(p),
              "payable": bool(payable.get(p["code"], {}).get("payable")),
              "reason": payable.get(p["code"], {}).get("reason")}
             for p in growth(container).plans() if p.get("audience") == AUDIENCE]
    return {"balance_paise": service.balance(user), "charging": settings["charging"],
            "rates_paise": settings["rates_paise"], "free_per_day": settings["free_per_day"],
            "used_today": service.usage_today(user), "packs": packs, "history": service.history(user, limit=50),
            "note": "AI Credits are only for ASKODOX AI features: not transferable, not cash, never used to pay a seller."}


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


class SettingsBody(BaseModel):
    charging: Optional[bool] = None
    rates_paise: Optional[Dict[str, int]] = None
    free_per_day: Optional[Dict[str, int]] = None


@admin_router.get("/settings")
def get_settings(request: Request) -> Dict[str, Any]:
    _require(request, "growth:view")
    return ai_credits(request.app.state.container).settings()


@admin_router.put("/settings")
def put_settings(body: SettingsBody, request: Request) -> Dict[str, Any]:
    principal = _require(request, "growth:manage")
    container = request.app.state.container
    service = ai_credits(container)
    before = service.settings()
    try:
        after = service.update_settings(body.model_dump(exclude_none=True), actor=str(principal["id"]))
    except CreditsError as error:
        raise _error(error) from None
    try:
        from app.api.routes.command_center import command_center

        command_center(container).audit(principal["id"], "ai_credits.settings", "ai_credits", "settings",
                                        before=before, after=after)
    except Exception:
        pass
    return after


@admin_router.get("/summary")
def summary(request: Request) -> Dict[str, Any]:
    _require(request, "growth:view")
    return ai_credits(request.app.state.container).summary()
