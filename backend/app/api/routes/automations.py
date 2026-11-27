"""Automations + phone health routes (see ``app/services/automations.py`` and ``app/services/phone_health.py``).

Customer (signed in):
  GET  /api/automations/buyer .................. the "same again?" habit cards
  POST /api/automations/dismiss ................ "వద్దు" / "ఇక చూపించకు" for one card
  POST /api/me/phone-health/report ............. one phone report; ``consent`` true in THIS request, every time
Shop (members, by the shop's own permissions):
  GET  /api/pos/businesses/{id}/automations .... low-stock supplier groups + regulars who stopped coming
  POST /api/pos/businesses/{id}/automations/low-stock/draft -> a DRAFT purchase order (never sent)
Staff:
  GET  /admin/cc/automations ................... stopped / quiet shops with their last help push + the AI cost guard
  POST /admin/cc/automations/stopped-shops/push  one help push to those shops' owners (once a week a shop)
  GET  /admin/cc/phone-reports ................. what breaks on which maker's phones (numbers masked)
Nothing here orders, pays or messages a customer by itself.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import rate_limit
from app.services.automations import AutomationError, Automations
from app.services.morning_brief import MorningBrief
from app.services.phone_health import PhoneHealth, PhoneHealthError
from app.services.pos_store import PosError

router = APIRouter(tags=["automations"])
admin_router = APIRouter(prefix="/admin/cc", tags=["command-center"])


def automations(container: Any) -> Automations:
    service = getattr(container, "automations", None)
    if service is None:
        service = Automations(container.settings.database_path)
        container.automations = service
    return service


def phone_health(container: Any) -> PhoneHealth:
    service = getattr(container, "phone_health", None)
    if service is None:
        service = PhoneHealth(container.settings.database_path)
        container.phone_health = service
    return service


def _user(request: Request, bucket: str, limit: int = 120) -> str:
    user = _authenticated_app_user(request)
    rate_limit.check(request, f"{bucket}:{user}", limit=limit)
    return user


def _fail(error: Exception) -> HTTPException:
    if isinstance(error, PosError):
        return HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message})
    return HTTPException(status_code=getattr(error, "status", 400), detail={"code": getattr(error, "code", "error")})


def _pos(request: Request):
    from app.api.routes.pos import _store
    from app.services.pos_purchases import PosPurchases

    store = _store(request)
    return store, PosPurchases(store)


# ------------------------------------------------------------------ customer --
@router.get("/api/automations/buyer")
def buyer_cards(request: Request) -> Dict[str, Any]:
    user = _user(request, "automations")
    return {"cards": automations(request.app.state.container).habit(user)}


class DismissBody(BaseModel):
    kind: str = Field(max_length=20)
    ref: str = Field(min_length=1, max_length=120)
    forever: bool = False


@router.post("/api/automations/dismiss")
def dismiss(body: DismissBody, request: Request) -> Dict[str, Any]:
    user = _user(request, "automations")
    try:
        return automations(request.app.state.container).dismiss(user, body.kind, body.ref, forever=body.forever)
    except AutomationError as error:
        raise _fail(error) from None


class PhoneReportBody(BaseModel):
    consent: bool = False
    maker: str = Field(default="", max_length=40)
    android: str = Field(default="", max_length=12)
    app_build: str = Field(default="", max_length=16)
    why: str = Field(default="", max_length=30)
    checks: Dict[str, str] = Field(default_factory=dict)


@router.post("/api/me/phone-health/report")
def phone_report(body: PhoneReportBody, request: Request) -> Dict[str, Any]:
    user = _user(request, "phone-health", limit=20)
    try:
        return phone_health(request.app.state.container).report(user, body.model_dump())
    except PhoneHealthError as error:
        raise _fail(error) from None


# -------------------------------------------------------------- morning brief --
def morning_brief(container: Any) -> MorningBrief:
    service = getattr(container, "morning_brief", None)
    if service is None:
        service = MorningBrief(container.settings.database_path)
        container.morning_brief = service
    return service


@router.get("/api/me/morning-brief")
def my_brief(request: Request) -> Dict[str, Any]:
    """The person's own three things for today (own bills, family list, "same again"). Read only."""
    from app.api.routes.pos_frontdesk import _bills

    user = _user(request, "brief")
    container = request.app.state.container
    return morning_brief(container).me(_bills(request), automations(container), user)


@router.get("/api/pos/businesses/{business_id}/morning-brief")
def shop_brief(business_id: str, request: Request) -> Dict[str, Any]:
    """The shop's three things for today + what was done yesterday. Free for ever: it only reads the shop's own
    tools; nothing is sent from here."""
    from app.api.routes.pos_frontdesk import _bills, dues_followup

    user = _user(request, "brief")
    container = request.app.state.container
    store, _ = _pos(request)
    try:
        from app.services.pos_memberships import PosMemberships

        return morning_brief(container).shop(store, dues_followup(container, store, _bills(request)),
                                             automations(container), business_id, user, PosMemberships(store))
    except PosError as error:
        raise _fail(error) from None


# ---------------------------------------------------------------------- shop --
@router.get("/api/pos/businesses/{business_id}/automations")
def shop_cards(business_id: str, request: Request) -> Dict[str, Any]:
    """Each part only for a member who may do that work; a part the caller may not see is simply absent."""
    user = _user(request, "automations")
    store, _ = _pos(request)
    service = automations(request.app.state.container)
    out: Dict[str, Any] = {}
    seen = False
    for key, read in (("low_stock", service.low_stock), ("winback", service.winback)):
        try:
            out[key] = read(store, business_id, user)
            seen = True
        except PosError as error:
            if error.status == 404:  # not a member: the shop does not exist for this person
                raise _fail(error) from None
    if not seen:
        raise HTTPException(status_code=403, detail={"code": "forbidden"})
    return out


class DraftBody(BaseModel):
    supplier_id: str = Field(min_length=1, max_length=60)


@router.post("/api/pos/businesses/{business_id}/automations/low-stock/draft")
def low_stock_draft(business_id: str, body: DraftBody, request: Request) -> Dict[str, Any]:
    user = _user(request, "automations", limit=30)
    store, purchases = _pos(request)
    try:
        return automations(request.app.state.container).low_stock_draft(store, purchases, business_id, user,
                                                                        body.supplier_id)
    except (PosError, AutomationError) as error:
        raise _fail(error) from None


# --------------------------------------------------------------------- staff --
def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def cost_guard_now(container: Any) -> Dict[str, Any]:
    from app.services import ai_usage_meter

    db = container.settings.database_path
    today = ai_usage_meter.report(db, days=1)
    people = ai_usage_meter.users_report(db, days=1)["users"]
    for row in people:  # a sign-in number is never shown in full
        digits = "".join(ch for ch in str(row["user"]) if ch.isdigit())
        row["user"] = ("••••" + digits[-4:]) if len(digits) >= 4 else "user"
    return automations(container).cost_guard(today_cost_inr=sum(f["cost_inr"] for f in today["features"]), users=people)


@admin_router.get("/automations")
def staff_view(request: Request) -> Dict[str, Any]:
    from app.api.routes.command_center import _can
    from app.services.shop_retention import shop_retention

    principal = _require(request, "analytics:view")
    container = request.app.state.container
    names = _can(principal, "users:view")
    report = shop_retention(container).report(lists=names)
    lists = report.get("lists") or {}
    shops: List[Dict[str, Any]] = [{**s, "list": key} for key in ("quiet", "stopped") for s in lists.get(key) or []]
    pushed = automations(container).nudges([s["id"] for s in shops])
    for shop in shops:
        shop["help_push_at"] = pushed.get(shop["id"], "")
    try:
        guard: Optional[Dict[str, Any]] = cost_guard_now(container)
    except Exception:
        guard = None
    return {"totals": report.get("totals"), "can_see_shops": names, "shops": shops, "cost_guard": guard,
            "can_push": _can(principal, "growth:manage")}


class PushBody(BaseModel):
    shop_ids: List[str] = Field(default_factory=list, max_length=200)


@admin_router.post("/automations/stopped-shops/push")
def push_stopped(body: PushBody, request: Request) -> Dict[str, Any]:
    """Only to shops that ARE on the quiet / stopped lists right now; the owner's id never leaves the server."""
    import sqlite3
    from contextlib import closing

    from app.services.push_service import push_service
    from app.services.shop_retention import shop_retention

    principal = _require(request, "growth:manage")
    container = request.app.state.container
    lists = shop_retention(container).report(lists=True).get("lists") or {}
    allowed = {s["id"] for key in ("quiet", "stopped") for s in lists.get(key) or []}
    wanted = [i for i in body.shop_ids if i in allowed] if body.shop_ids else sorted(allowed)
    if not wanted:
        return {"sent": 0, "skipped_recent": 0, "gap_days": 0}
    with closing(sqlite3.connect(container.settings.database_path)) as conn:
        marks = ",".join("?" * len(wanted))
        shops = [{"id": r[0], "owner": r[1]} for r in conn.execute(
            f"SELECT id, owner_user_id FROM pos_businesses WHERE id IN ({marks})", wanted)]
    out = automations(container).nudge_stopped(shops, actor=str(principal["id"]), notify=push_service(container).notify)
    try:
        from app.api.routes.command_center import command_center

        command_center(container).audit(principal["id"], "automations.stopped_push", "automations", "stopped_shops",
                                        after={"shops": len(wanted), **out})
    except Exception:
        pass
    return out


@admin_router.get("/phone-reports")
def phone_reports(request: Request, days: int = 30) -> Dict[str, Any]:
    _require(request, "analytics:view")
    return phone_health(request.app.state.container).overview(days=days)
