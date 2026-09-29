"""ASKODOX commerce platform API (Command Center + customer endpoints).

Admin (/admin/cc/platform/..., staff permissions <area>:view / <area>:manage):
  schema, dashboard, search                     console structure + global search
  r/{resource}[/{id}[/actions/{a}|/history]]    generic CRUD + lifecycle for every
  r/{resource}/export.csv                       configurable resource
  accounts[/{type}/{ref}]                       block / unblock / verify / archive
  affiliate/conversions                         record a network-reported conversion
  merchant-offers/{id}/report                   claims / redemptions / benefit given
  payments[...], ledger[...], rewards[...]      finance state machines (idempotent)
  transactions                                  one timeline of everything money-like
  integrations[/{provider}[/check]]             LIVE / TEST / DISABLED / NEEDS CONFIGURATION / ERROR
  notifications/test                            render + dispatch through rules
  analytics, insights                           funnel, video funnel, AI-style suggestions
Public / app:
  GET  /l/{slug}                                smart link (app -> deep link -> web -> safe page)
  GET  /go/af/{click_id}                        tracked affiliate redirect (stored URLs only)
  POST /api/track                               client attribution events (whitelisted)
  GET  /api/videos/search, POST /api/videos/{id}/explain, GET /api/reviews
  merchant offers: /api/merchant/offers..., /api/merchant-offers/{id}/claim,
                   /api/merchant/claims/{code}/redeem, /api/rewards/ledger/mine
  POST /api/payments/webhook/{provider}         HMAC-verified, replay-protected
  GET  /api/notifications/inbox
"""
from __future__ import annotations

import time
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse
from pydantic import BaseModel, Field

from app.repositories.platform_repository import (
    EVENT_IDS,
    LEDGER_STATES,
    PlatformConflict,
    PlatformRepository,
    REWARD_STATES,
    REWARD_TYPES,
)
from app.services import commerce_finance as fin
from app.services import platform_schema as ps
from app.services.commerce_engines import (
    AffiliateEngine,
    MerchantOfferEngine,
    ReviewEngine,
    SmartLinkEngine,
    VideoEngine,
)
from app.services.platform_service import ResourceService

router = APIRouter(tags=["platform"])
admin_router = APIRouter(prefix="/admin/cc/platform", tags=["command-center"])

# Events an app / web client may report (the rest are server-side only).
CLIENT_EVENTS = {"impression", "result_view", "click", "deep_link", "abandon", "video_impression", "video_open",
                 "video_watch_start", "video_watch_complete", "video_ask", "video_product_click",
                 "video_service_click", "video_local_search", "video_affiliate_click", "video_contact",
                 "notification_open"}


class Platform:
    """Everything the routes need, built once per container."""

    def __init__(self, container: Any) -> None:
        settings = container.settings
        from app.services.secret_box import box_from_settings

        self.container = container
        self.repo = PlatformRepository(settings.database_path)
        self.links = SmartLinkEngine(self.repo)
        self.affiliate = AffiliateEngine(self.repo)
        self.offers = MerchantOfferEngine(self.repo, is_new_customer=self._is_new_customer)
        self.videos = VideoEngine(self.repo)
        self.reviews = ReviewEngine(self.repo)
        self.registry = fin.IntegrationRegistry(settings.database_path, secret_box=box_from_settings(settings))
        self.payments = fin.PaymentService(self.repo, self.registry)
        self.ledger = fin.RevenueLedger(self.repo)
        self.notifications = fin.NotificationDispatcher(self.repo, self.registry)
        self.resources = ResourceService(self.repo, effects={
            "link_test": self._link_test, "preview": self._preview}, ref_exists=self._ref_exists)
        self._blocked_cache: tuple[float, set[str]] = (0.0, set())

    # effects / helpers -------------------------------------------------
    def _is_new_customer(self, user_id: str) -> bool:
        try:
            rows = self.container.database.fetchall(
                "SELECT COUNT(*) AS n FROM orders WHERE buyer_user_id=? AND status IN ('FULFILLED','COMPLETED')",
                (user_id,))
            return int(dict(rows[0])["n"] or 0) == 0
        except Exception:
            return True

    def _ref_exists(self, kind: str, value: str) -> bool:
        if kind == "partners":
            try:
                from app.api.routes.partners import partner_repo

                return any(str(p["id"]) == value for p in partner_repo(self.container).partners())
            except Exception:
                return False
        return True

    def _fetch_status(self, url: str) -> int:
        fetcher = getattr(self.container, "link_fetcher", None)
        if fetcher is not None:
            return int(fetcher(url))
        import httpx

        response = httpx.head(url, follow_redirects=True, timeout=6.0)
        return response.status_code

    def _link_test(self, record: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
        health = self.links.health(record, self._fetch_status)
        return {"data": {**record["data"], "health": health}, "result": health}

    def _preview(self, record: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
        values = params.get("values") or {}
        d = record["data"]
        return {"data": None, "result": {"title": self.notifications.render(d.get("title") or "", values),
                                         "body": self.notifications.render(d.get("body") or "", values)}}

    def blocked(self, user_ref: str) -> bool:
        at, refs = self._blocked_cache
        if time.monotonic() - at > 5:
            refs = self.repo.blocked_refs("user")
            self._blocked_cache = (time.monotonic(), refs)
        return user_ref in refs

    def invalidate(self) -> None:
        self._blocked_cache = (0.0, set())


def platform(container: Any) -> Platform:
    existing = getattr(container, "platform", None)
    if existing is None or existing.repo.db_path != container.settings.database_path:
        existing = Platform(container)
        container.platform = existing
    return existing


def is_blocked_user(container: Any, user_id: str) -> bool:
    """Session-token revocation hook: a user blocked in the Command Center
    (by their opaque reference) loses every session at once."""
    try:
        return platform(container).blocked(user_ref(user_id))
    except Exception:
        return False


def revocation_check(container: Any, deleted_before: Any):
    """The one session-token revocation hook: deleted OR blocked accounts."""
    return lambda user_id, issued_at: bool(
        deleted_before(container.settings.database_path, user_id, issued_at)
        or is_blocked_user(container, user_id))


def notify(container: Any, event: str, user_id: str, values: Dict[str, Any], *, language: str = "en") -> List[Dict]:
    """Fire an event through the admin's notification rules (nothing is
    sent unless a rule + template exist; channels switched off by flag or
    without credentials are skipped and recorded). Never raises."""
    try:
        from app.api.routes.command_center import command_center

        flags = command_center(container).flags_map()
        return platform(container).notifications.dispatch(
            event, user_ref=user_ref(user_id), values=values, language=language,
            channel_on=lambda channel: flags.get(f"notifications.{channel}", True) if channel != "in_app" else True)
    except Exception:
        return []


def user_ref(user_id: str) -> str:
    from app.api.routes.command_center import _ref

    return _ref(user_id)


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    from app.api.routes.partners import _audit as audit

    audit(request, principal, action, target, detail)


def _pf(request: Request) -> Platform:
    return platform(request.app.state.container)


def _user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


def _optional_user(request: Request) -> Optional[str]:
    try:
        return _user(request)
    except HTTPException:
        return None


def _flag(request: Request, key: str) -> bool:
    try:
        from app.api.routes.command_center import command_center

        return bool(command_center(request.app.state.container).flags_map().get(key, True))
    except Exception:
        return True


def _err(error: Exception) -> HTTPException:
    if isinstance(error, KeyError):
        return HTTPException(status_code=404, detail="Not found")
    if isinstance(error, PlatformConflict):
        return HTTPException(status_code=409, detail=str(error))
    if isinstance(error, PermissionError):
        return HTTPException(status_code=403, detail=str(error))
    return HTTPException(status_code=400, detail=str(error))


def _mask(item: Dict[str, Any]) -> Dict[str, Any]:
    """Owner references are app user ids -- staff see an opaque reference."""
    if item.get("owner_ref"):
        item = dict(item, owner_ref=user_ref(item["owner_ref"]))
    return item


# =============================================================== admin ===

@admin_router.get("/schema")
def schema(request: Request) -> dict:
    _require(request, "overview:view")
    return {"resources": ps.public_schema(), "groups": sorted({r.group for r in ps.RESOURCES.values()}),
            "reward_states": list(REWARD_STATES), "reward_types": list(REWARD_TYPES),
            "ledger_states": list(LEDGER_STATES), "ledger_kinds": list(fin.LEDGER_KINDS),
            "payment_methods": list(fin.PaymentService.INTERNAL_METHODS + fin.PaymentService.GATEWAY_METHODS)}


@admin_router.get("/search")
def global_search(request: Request, q: str = "") -> dict:
    _require(request, "overview:view")
    pf = _pf(request)
    hits = pf.resources.search_all(q)
    needle = q.strip().lower()
    if len(needle) >= 2:
        hits += [{"id": p["id"], "resource": "payments", "resource_label": "Payments", "name": p["order_ref"] or p["id"],
                  "status": p["status"]} for p in pf.repo.payments(limit=2000) if needle in p["id"].lower()
                 or needle in str(p["order_ref"] or "").lower()][:10]
    return {"items": hits}


@admin_router.get("/dashboard")
def dashboard(request: Request) -> dict:
    principal = _require(request, "overview:view")
    perms = principal.get("permissions") or set()
    pf = _pf(request)
    counts: Dict[str, Dict[str, int]] = {}
    for record in pf.repo.all_records(ps.RESOURCES):
        counts.setdefault(record["resource"], {})
        counts[record["resource"]][record["status"]] = counts[record["resource"]].get(record["status"], 0) + 1
    integrations = pf.registry.all()
    summary = {s: sum(1 for i in integrations if i["status"] == s)
               for s in (fin.STATUS_LIVE, fin.STATUS_TEST, fin.STATUS_DISABLED, fin.STATUS_NEEDS, fin.STATUS_ERROR)}
    alerts = [i for i in fin.insights(pf.repo, days=7) if i["severity"] in ("warning", "critical")]
    pending_review = sum(n for per in counts.values() for s, n in per.items() if s == "PENDING_REVIEW")
    stats = fin.analytics(pf.repo, days=30)
    # Money figures only for people allowed to see money.
    return {"resources": counts, "pending_review": pending_review, "integrations": summary,
            "alerts": alerts[:8], "funnel": stats["funnel"],
            "revenue": pf.ledger.summary() if "finance:view" in perms else None,
            "payments": pf.payments.reconcile()["totals_by_state"] if "payments:view" in perms else None}


@admin_router.get("/r/{resource}")
def list_records(resource: str, request: Request, q: str = "", status: str = "", archived: bool = False,
                 sort: str = "-updated_at") -> dict:
    try:
        res = ps.resource(resource)
    except ps.SchemaError as error:
        raise _err(error) from None
    _require(request, f"{res.permission}:view")
    filters = {k[2:]: v for k, v in request.query_params.items() if k.startswith("f_")}
    items = _pf(request).resources.list(resource, q=q, status=status, archived=archived, filters=filters,
                                        sort=sort)
    return {"items": [_mask(i) for i in items], "count": len(items)}


@admin_router.get("/r/{resource}/export.csv", response_class=PlainTextResponse)
def export_records(resource: str, request: Request, q: str = "", status: str = "", archived: bool = False) -> str:
    try:
        res = ps.resource(resource)
    except ps.SchemaError as error:
        raise _err(error) from None
    principal = _require(request, f"{res.permission}:view")
    _require(request, "analytics:export")
    _audit(request, principal, "platform.export", f"{resource}:*", {"q": q, "status": status})
    return PlainTextResponse(_pf(request).resources.export_csv(resource, q=q, status=status, archived=archived),
                             media_type="text/csv")


class RecordBody(BaseModel):
    data: Dict[str, Any] = Field(default_factory=dict)
    version: int | None = None


@admin_router.post("/r/{resource}")
def create_record(resource: str, body: RecordBody, request: Request) -> dict:
    try:
        res = ps.resource(resource)
        principal = _require(request, f"{res.permission}:manage")
        item = _pf(request).resources.create(resource, body.data, actor=principal["id"])
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "platform.create", f"{resource}:{item['id']}", {"name": item["name"]})
    return _mask(item)


@admin_router.get("/r/{resource}/{record_id}")
def get_record(resource: str, record_id: str, request: Request) -> dict:
    try:
        res = ps.resource(resource)
        _require(request, f"{res.permission}:view")
        return _mask(_pf(request).resources.get(resource, record_id))
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None


@admin_router.patch("/r/{resource}/{record_id}")
def update_record(resource: str, record_id: str, body: RecordBody, request: Request) -> dict:
    try:
        res = ps.resource(resource)
        principal = _require(request, f"{res.permission}:manage")
        item = _pf(request).resources.update(resource, record_id, body.data, actor=principal["id"],
                                             expected_version=body.version)
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "platform.edit", f"{resource}:{record_id}", {"fields": sorted(body.data)})
    return _mask(item)


@admin_router.delete("/r/{resource}/{record_id}")
def delete_record(resource: str, record_id: str, request: Request, confirm: bool = False) -> dict:
    try:
        res = ps.resource(resource)
        principal = _require(request, f"{res.permission}:manage")
        if not confirm:
            raise HTTPException(status_code=409, detail="Confirmation required to delete (archive keeps history)")
        _pf(request).resources.delete(resource, record_id, actor=principal["id"])
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "platform.delete", f"{resource}:{record_id}")
    return {"deleted": record_id}


class ActionBody(BaseModel):
    params: Dict[str, Any] = Field(default_factory=dict)
    confirm: bool = False


@admin_router.post("/r/{resource}/{record_id}/actions/{action}")
def record_action(resource: str, record_id: str, action: str, body: ActionBody, request: Request) -> dict:
    try:
        res = ps.resource(resource)
        spec = next((a for a in res.actions if a.name == action), None)
        manage = spec.manage if spec else True
        principal = _require(request, f"{res.permission}:{'manage' if manage else 'view'}")
        if spec and spec.confirm and not body.confirm:
            raise HTTPException(status_code=409, detail=f"Confirmation required to {spec.label.lower()}")
        item = _pf(request).resources.action(resource, record_id, action, actor=principal["id"],
                                             params=body.params)
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, f"platform.{action}", f"{resource}:{record_id}", {"status": item.get("status")})
    return _mask(item)


@admin_router.get("/r/{resource}/{record_id}/history")
def record_history(resource: str, record_id: str, request: Request) -> dict:
    try:
        res = ps.resource(resource)
        _require(request, f"{res.permission}:view")
        return {"items": _pf(request).resources.history(resource, record_id)}
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None


# accounts (users / partners / merchants / creators / advertisers)

ACCOUNT_TYPES = ("user", "partner", "advertiser", "creator", "merchant")


class AccountBody(BaseModel):
    blocked: bool | None = None
    verified: bool | None = None
    archived: bool | None = None
    note: str = Field(default="", max_length=300)
    confirm: bool = False


@admin_router.get("/accounts/{subject_type}")
def account_states(subject_type: str, request: Request) -> dict:
    _require(request, "users:view")
    if subject_type not in ACCOUNT_TYPES:
        raise HTTPException(status_code=404, detail="Unknown account type")
    states = _pf(request).repo.account_states(subject_type)
    return {"items": [{"subject_ref": ref, **flags} for ref, flags in sorted(states.items())]}


@admin_router.post("/accounts/{subject_type}/{subject_ref}")
def set_account_state(subject_type: str, subject_ref: str, body: AccountBody, request: Request) -> dict:
    principal = _require(request, "users:manage")
    if subject_type not in ACCOUNT_TYPES:
        raise HTTPException(status_code=404, detail="Unknown account type")
    if body.blocked and not body.confirm:
        raise HTTPException(status_code=409, detail="Confirmation required to block")
    flags = {k: v for k, v in (("blocked", body.blocked), ("verified", body.verified), ("archived", body.archived))
             if v is not None}
    pf = _pf(request)
    state = pf.repo.set_account_state(subject_type, subject_ref[:64], actor=principal["id"], note=body.note, **flags)
    pf.invalidate()
    _audit(request, principal, "account.state", f"{subject_type}:{subject_ref}", flags | {"note": body.note})
    return state


# affiliate conversions / merchant offer reports

class ConversionBody(BaseModel):
    click_id: str = Field(min_length=6, max_length=60)
    external_ref: str = Field(min_length=1, max_length=60)
    order_value: float | None = Field(default=None, ge=0)
    status: str = "pending"


@admin_router.post("/affiliate/conversions")
def affiliate_conversion(body: ConversionBody, request: Request) -> dict:
    principal = _require(request, "affiliate:manage")
    try:
        result = _pf(request).affiliate.record_conversion(click_id=body.click_id, order_value=body.order_value,
                                                          external_ref=body.external_ref, status=body.status,
                                                          actor=principal["id"])
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "affiliate.conversion", f"conversion:{result['conversion_id']}",
           {"order_value": body.order_value, "status": body.status})
    return result


@admin_router.get("/merchant-offers/{offer_id}/report")
def merchant_offer_report(offer_id: str, request: Request) -> dict:
    _require(request, "offers:view")
    return _pf(request).offers.report(offer_id)


# payments

class PaymentBody(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=80)
    method: str
    amount: float = Field(gt=0)
    order_ref: str | None = None
    provider: str | None = None


@admin_router.get("/payments")
def payments(request: Request, status: str = "") -> dict:
    _require(request, "payments:view")
    pf = _pf(request)
    return {"items": pf.repo.payments(status=status or None), "reconciliation": pf.payments.reconcile()}


@admin_router.post("/payments")
def create_payment(body: PaymentBody, request: Request) -> dict:
    principal = _require(request, "payments:manage")
    if not _flag(request, "payments.online") and body.method in fin.PaymentService.GATEWAY_METHODS:
        raise HTTPException(status_code=409, detail="Online payments are switched off (feature flag payments.online)")
    try:
        payment = _pf(request).payments.create(idempotency_key=body.idempotency_key, method=body.method,
                                               amount=body.amount, order_ref=body.order_ref, payer_ref=None,
                                               payee_ref=None, provider=body.provider, actor=principal["id"])
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "payment.create", f"payment:{payment['id']}", {"amount": body.amount})
    return payment


class PaymentActionBody(BaseModel):
    reference: str = Field(default="", max_length=80)
    amount: float | None = Field(default=None, gt=0)
    note: str = Field(default="", max_length=300)
    confirm: bool = False


@admin_router.post("/payments/{payment_id}/{action}")
def payment_action(payment_id: str, action: str, body: PaymentActionBody, request: Request) -> dict:
    principal = _require(request, "payments:manage")
    pf = _pf(request)
    try:
        if action == "confirm":
            result = pf.payments.confirm_direct(payment_id, reference=body.reference, actor=principal["id"])
        elif action == "refund":
            if not body.confirm:
                raise HTTPException(status_code=409, detail="Confirmation required to refund")
            result = pf.payments.refund(payment_id, body.amount, actor=principal["id"], note=body.note)
        elif action == "settle":
            if not body.reference:
                raise HTTPException(status_code=400, detail="settlement reference required")
            result = pf.payments.settle(payment_id, body.reference, actor=principal["id"])
        elif action in ("cancel", "fail", "dispute"):
            result = pf.repo.transition_payment(payment_id, {"cancel": "CANCELLED", "fail": "FAILED",
                                                             "dispute": "DISPUTED"}[action], actor=principal["id"],
                                                note=body.note)
        else:
            raise HTTPException(status_code=404, detail="Unknown payment action")
    except HTTPException:
        raise
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, f"payment.{action}", f"payment:{payment_id}", {"amount": body.amount})
    return result | {"history": pf.repo.state_history("payment", payment_id)}


# revenue / commission ledger

class LedgerBody(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=80)
    kind: str
    amount: float = Field(ge=0)
    state: str = "EXPECTED"
    partner_id: str | None = None
    campaign_id: str | None = None
    order_ref: str | None = None
    note: str = Field(default="", max_length=300)


@admin_router.get("/ledger")
def ledger(request: Request, state: str = "", kind: str = "") -> dict:
    _require(request, "finance:view")
    pf = _pf(request)
    return {"items": pf.repo.ledger(state=state or None, kind=kind or None), "summary": pf.ledger.summary(),
            "reconciliation": pf.ledger.reconcile()}


@admin_router.post("/ledger")
def ledger_add(body: LedgerBody, request: Request) -> dict:
    principal = _require(request, "finance:manage")
    try:
        entry, created = _pf(request).repo.ledger_add(
            idempotency_key=body.idempotency_key, kind=body.kind, amount=body.amount, state=body.state,
            partner_id=body.partner_id, campaign_id=body.campaign_id, order_ref=body.order_ref, note=body.note,
            actor=principal["id"])
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "ledger.add", f"ledger:{entry['id']}", {"amount": body.amount, "kind": body.kind})
    return entry | {"created": created}


class StateBody(BaseModel):
    state: str
    note: str = Field(default="", max_length=300)
    confirm: bool = False


@admin_router.post("/ledger/{entry_id}/state")
def ledger_state(entry_id: str, body: StateBody, request: Request) -> dict:
    principal = _require(request, "finance:manage")
    if body.state in ("PAID", "REVERSED") and not body.confirm:
        raise HTTPException(status_code=409, detail=f"Confirmation required to mark {body.state.lower()}")
    try:
        entry = _pf(request).repo.transition_ledger(entry_id, body.state.upper(), actor=principal["id"],
                                                    note=body.note)
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "ledger.state", f"ledger:{entry_id}", {"state": body.state})
    return entry


# rewards

class RewardBody(BaseModel):
    idempotency_key: str = Field(min_length=1, max_length=80)
    user_ref: str = Field(min_length=4, max_length=80)
    reward_type: str
    amount: float | None = Field(default=None, gt=0)
    points: int | None = Field(default=None, gt=0)
    state: str = "AVAILABLE"
    title: str = Field(default="", max_length=120)
    campaign_id: str | None = None
    expires_at: str | None = None


@admin_router.get("/rewards")
def rewards(request: Request, state: str = "", user: str = "") -> dict:
    _require(request, "rewards:view")
    items = _pf(request).repo.rewards(state=state or None, user_ref=user or None)
    by_state: Dict[str, int] = {}
    for r in items:
        by_state[r["state"]] = by_state.get(r["state"], 0) + 1
    return {"items": items[:500], "by_state": by_state}


@admin_router.post("/rewards")
def grant_reward(body: RewardBody, request: Request) -> dict:
    principal = _require(request, "rewards:manage")
    if not _flag(request, "rewards"):
        raise HTTPException(status_code=409, detail="Rewards are switched off (feature flag rewards)")
    try:
        reward, created = _pf(request).repo.reward_add(
            idempotency_key=body.idempotency_key, user_ref=body.user_ref, reward_type=body.reward_type,
            state=body.state, amount=body.amount, points=body.points, source="admin", campaign_id=body.campaign_id,
            title=body.title, expires_at=body.expires_at, actor=principal["id"])
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "reward.grant", f"reward:{reward['id']}", {"type": body.reward_type})
    if created and reward["state"] == "AVAILABLE":
        # Admin grants address users by their opaque reference already.
        try:
            _pf(request).notifications.dispatch("reward_available", user_ref=body.user_ref,
                                                values={"reward": body.title or body.reward_type})
        except Exception:
            pass
    return reward | {"created": created}


@admin_router.post("/rewards/{reward_id}/state")
def reward_state(reward_id: str, body: StateBody, request: Request) -> dict:
    principal = _require(request, "rewards:manage")
    try:
        reward = _pf(request).repo.transition_reward(reward_id, body.state.upper(), actor=principal["id"],
                                                     note=body.note)
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "reward.state", f"reward:{reward_id}", {"state": body.state})
    return reward


@admin_router.get("/transactions")
def transactions(request: Request, kind: str = "", status: str = "", q: str = "") -> dict:
    _require(request, "finance:view")
    from app.api.routes.command_center import _rows

    pf = _pf(request)
    items = fin.transaction_center(pf.repo, lambda sql: _rows(request, sql), kind=kind, status=status, q=q)
    return {"items": items, "kinds": sorted({i["kind"] for i in items})}


# integrations

class IntegrationBody(BaseModel):
    enabled: bool | None = None
    mode: str | None = None
    config: Dict[str, Any] = Field(default_factory=dict)
    secrets: Dict[str, str] = Field(default_factory=dict)


@admin_router.get("/integrations")
def integrations(request: Request) -> dict:
    _require(request, "integrations:view")
    return {"items": _pf(request).registry.all()}


@admin_router.put("/integrations/{provider}")
def configure_integration(provider: str, body: IntegrationBody, request: Request) -> dict:
    principal = _require(request, "integrations:manage")
    try:
        status = _pf(request).registry.configure(provider, actor=principal["id"], enabled=body.enabled,
                                                 mode=body.mode, config=body.config, secrets=body.secrets)
    except PermissionError as error:
        raise HTTPException(status_code=503, detail=str(error)) from None
    except Exception as error:
        raise _err(error) from None
    # Names only -- secret values never reach the audit log.
    _audit(request, principal, "integration.configure", f"integration:{provider}",
           {"enabled": body.enabled, "mode": body.mode, "config": sorted(body.config), "secrets": sorted(body.secrets)})
    return status


@admin_router.post("/integrations/{provider}/check")
def check_integration(provider: str, request: Request) -> dict:
    principal = _require(request, "integrations:manage")
    pf = _pf(request)
    if provider not in fin.PROVIDERS:
        raise HTTPException(status_code=404, detail="Unknown provider")
    status = pf.registry.status(provider)
    if status["missing"]:
        return pf.registry.record_check(provider, False, f"missing: {', '.join(status['missing'])}")
    probe = getattr(request.app.state.container, "integration_probes", {}).get(provider)
    if probe is None:
        # No automated probe for this provider: stays TEST until verified.
        _audit(request, principal, "integration.check", f"integration:{provider}", {"result": "manual"})
        return status | {"note": "No automated live check for this provider -- verify with the partner, then "
                                 "switch mode to live."}
    ok, detail = probe(pf.registry)
    _audit(request, principal, "integration.check", f"integration:{provider}", {"ok": ok})
    return pf.registry.record_check(provider, bool(ok), str(detail))


class NotifyTestBody(BaseModel):
    event: str
    user_ref: str
    values: Dict[str, Any] = Field(default_factory=dict)
    language: str = "en"


@admin_router.post("/notifications/test")
def notifications_test(body: NotifyTestBody, request: Request) -> dict:
    principal = _require(request, "notifications:manage")
    results = _pf(request).notifications.dispatch(body.event, user_ref=body.user_ref, values=body.values,
                                                  language=body.language)
    _audit(request, principal, "notifications.test", f"event:{body.event}", {"results": len(results)})
    return {"results": results}


@admin_router.get("/analytics")
def platform_analytics(request: Request, days: int = 30, category: str = "", location: str = "",
                       source: str = "") -> dict:
    _require(request, "analytics:view")
    where = {k: v for k, v in (("category", category), ("location", location), ("source", source)) if v}
    return fin.analytics(_pf(request).repo, days=max(1, min(days, 365)), where=where)


@admin_router.get("/insights")
def platform_insights(request: Request, days: int = 7) -> dict:
    _require(request, "insights:view")
    pf = _pf(request)
    broken = [r["data"].get("slug") for r in pf.repo.list("smart_links")
              if (r["data"].get("health") or {}).get("state") == "ERROR"]
    return {"items": fin.insights(pf.repo, days=max(1, min(days, 90)), extra={"broken_links": broken}),
            "note": "Suggestions only -- nothing is changed automatically."}


@admin_router.get("/events")
def platform_events(request: Request, event: str = "", limit: int = 200) -> dict:
    _require(request, "analytics:view")
    return {"items": _pf(request).repo.events(event=event or None, limit=max(1, min(limit, 1000)))}


# ============================================================ public ===

@router.get("/l/{slug}", include_in_schema=False, response_class=HTMLResponse)
def smart_link(slug: str, request: Request) -> HTMLResponse:
    from app.services import rate_limit

    rate_limit.check(request, "smart_link", limit=120)
    if not _flag(request, "links.smart"):
        raise HTTPException(status_code=404, detail="Link unavailable")
    pf = _pf(request)
    record = pf.links.by_slug(slug)
    if not record or record["status"] != "ACTIVE":
        return HTMLResponse("<!doctype html><title>ASKODOX</title><p>This link is no longer available.</p>",
                            status_code=404)
    agent = (request.headers.get("user-agent") or "").lower()
    platform_hint = "android" if "android" in agent else ("ios" if "iphone" in agent or "ipad" in agent else "web")
    pf.repo.record_event("deep_link", link_id=record["id"], campaign_id=record["data"].get("campaign_id"),
                         source=platform_hint)
    return HTMLResponse(pf.links.landing_page(record, platform=platform_hint))


@router.get("/go/af/{click_id}", include_in_schema=False)
def affiliate_redirect(click_id: str, request: Request) -> RedirectResponse:
    from app.services import rate_limit

    rate_limit.check(request, "affiliate_go", limit=60)
    url = _pf(request).affiliate.open_click(click_id[:40])
    if not url:
        raise HTTPException(status_code=404, detail="Link expired or unknown")
    return RedirectResponse(url, status_code=302)


class TrackBody(BaseModel):
    event: str
    ids: Dict[str, str] = Field(default_factory=dict)
    category: str = Field(default="", max_length=80)
    location: str = Field(default="", max_length=120)
    language: str = Field(default="", max_length=12)
    source: str = Field(default="", max_length=40)
    detail: Dict[str, Any] = Field(default_factory=dict)


@router.post("/api/track")
def track(body: TrackBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "track", limit=240)
    if body.event not in CLIENT_EVENTS:
        raise HTTPException(status_code=400, detail="Unknown client event")
    ids = {k: str(v)[:80] for k, v in body.ids.items() if k in EVENT_IDS and k != "user_ref" and v}
    user = _optional_user(request)
    if user:
        ids["user_ref"] = user_ref(user)  # identity from the token only, never the body
    event_id = _pf(request).repo.record_event(body.event, category=body.category, location=body.location,
                                              language=body.language, source=body.source,
                                              detail={k: v for k, v in list(body.detail.items())[:12]}, **ids)
    return {"recorded": event_id is not None}


@router.get("/api/videos/search")
def videos_search(request: Request, q: str = "", category: str = "", location: str = "") -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "videos_search", limit=60)
    if not _flag(request, "results.videos"):
        return {"items": [], "reason": "videos switched off"}
    items = _pf(request).videos.rows({"subject": q, "raw_text": q, "domain": category, "location_text": location},
                                     limit=8)
    return {"items": items, "empty_reason": None if items else "No relevant videos for this search yet."}


class ExplainBody(BaseModel):
    question: str = Field(default="", max_length=500)
    language: str = Field(default="en", max_length=8)


@router.post("/api/videos/{video_id}/explain")
def video_explain(video_id: str, body: ExplainBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "video_explain", limit=30)
    pf = _pf(request)
    try:
        result = pf.videos.explain(video_id, body.question, language=body.language)
    except KeyError:
        raise HTTPException(status_code=404, detail="Video not found") from None
    user = _optional_user(request)
    pf.repo.record_event("video_ask", video_id=video_id, user_ref=user_ref(user) if user else None,
                         language=body.language, detail={"analyzed": result["analyzed"]})
    return result


@router.get("/api/reviews")
def reviews(q: str, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "reviews", limit=60)
    return _pf(request).reviews.for_query(q)


# merchant self-service

@router.get("/api/merchant/offers")
def my_offers(request: Request) -> dict:
    user = _user(request)
    pf = _pf(request)
    items = pf.resources.list("merchant_offers", owner_ref=user, archived=False)
    return {"items": [i | {"report": pf.offers.report(i["id"])} for i in items]}


@router.post("/api/merchant/offers")
def create_my_offer(body: RecordBody, request: Request) -> dict:
    user = _user(request)
    if not _flag(request, "offers.merchant"):
        raise HTTPException(status_code=409, detail="Merchant offers are not open yet")
    pf = _pf(request)
    if pf.repo.account_state("user", user_ref(user))["blocked"]:
        raise HTTPException(status_code=403, detail="Account blocked")
    try:
        # Always reviewed by ASKODOX before customers see it.
        return pf.resources.create("merchant_offers", body.data, actor=f"user:{user_ref(user)}", owner_ref=user,
                                   status="PENDING_REVIEW")
    except Exception as error:
        raise _err(error) from None


@router.post("/api/merchant/offers/{offer_id}/{action}")
def my_offer_action(offer_id: str, action: str, request: Request) -> dict:
    user = _user(request)
    if action not in ("pause", "resume", "archive"):
        raise HTTPException(status_code=403, detail="Merchants can pause, resume or archive their offers")
    try:
        return _pf(request).resources.action("merchant_offers", offer_id, action, actor=f"user:{user_ref(user)}",
                                             owner_ref=user)
    except Exception as error:
        raise _err(error) from None


@router.post("/api/merchant-offers/{offer_id}/claim")
def claim_offer(offer_id: str, request: Request) -> dict:
    user = _user(request)
    if not _flag(request, "offers.merchant"):
        raise HTTPException(status_code=409, detail="Merchant offers are switched off")
    try:
        result = _pf(request).offers.claim(offer_id, user)
    except Exception as error:
        raise _err(error) from None
    if not result.get("already"):
        offer = _pf(request).repo.get(offer_id) or {}
        if offer.get("owner_ref"):
            notify(request.app.state.container, "offer_claimed", offer["owner_ref"],
                   {"offer": result.get("offer") or "", "code": result.get("claim_code") or ""})
    return {k: v for k, v in result.items() if k not in ("user_ref", "idempotency_key")}


class RedeemBody(BaseModel):
    bill_amount: float | None = Field(default=None, ge=0)


@router.post("/api/merchant/claims/{claim_code}/redeem")
def redeem_claim(claim_code: str, body: RedeemBody, request: Request) -> dict:
    user = _user(request)
    try:
        result = _pf(request).offers.redeem(claim_code, user, bill_amount=body.bill_amount)
    except Exception as error:
        raise _err(error) from None
    return {k: v for k, v in result.items() if k not in ("user_ref", "idempotency_key")}


def _self_service_user(request: Request) -> str:
    user = _user(request)
    if _pf(request).repo.account_state("user", user_ref(user))["blocked"]:
        raise HTTPException(status_code=403, detail="Account blocked")
    return user


@router.get("/api/merchant/videos")
def my_videos(request: Request) -> dict:
    user = _user(request)
    return {"items": _pf(request).resources.list("videos", owner_ref=user, archived=False)}


@router.post("/api/merchant/videos")
def submit_my_video(body: RecordBody, request: Request) -> dict:
    """A business adds a video about its own product / service: always
    labelled "From the business" and reviewed before customers see it."""
    user = _self_service_user(request)
    data = {k: v for k, v in body.data.items() if k not in ("featured", "campaign_id", "affiliate_link_id",
                                                              "creator_id", "source_id", "transcript")}
    data.update(relationship="merchant", merchant_ref=user_ref(user))
    try:
        return _pf(request).resources.create("videos", data, actor=f"user:{user_ref(user)}", owner_ref=user,
                                             status="PENDING_REVIEW")
    except Exception as error:
        raise _err(error) from None


@router.post("/api/creators/apply")
def apply_as_creator(body: RecordBody, request: Request) -> dict:
    """A creator / influencer applies; ASKODOX verifies before any badge."""
    user = _self_service_user(request)
    pf = _pf(request)
    if pf.resources.list("creators", owner_ref=user, archived=True) or pf.resources.list("creators", owner_ref=user):
        raise HTTPException(status_code=409, detail="You have already applied")
    data = {k: v for k, v in body.data.items() if k in ("name", "platform", "profile_url", "handle", "categories",
                                                          "languages", "notes")}
    try:
        return pf.resources.create("creators", data | {"relationship": "none", "verified": False},
                                   actor=f"user:{user_ref(user)}", owner_ref=user, status="PENDING_REVIEW")
    except Exception as error:
        raise _err(error) from None


@router.get("/api/rewards/ledger/mine")
def my_rewards(request: Request) -> dict:
    user = _user(request)
    pf = _pf(request)
    own = pf.repo.rewards(user_ref=user) + pf.repo.rewards(user_ref=user_ref(user))
    return {"items": [{k: v for k, v in r.items() if k != "idempotency_key"} for r in own]}


class RewardClaimBody(BaseModel):
    action: str


@router.post("/api/rewards/ledger/{reward_id}")
def my_reward_action(reward_id: str, body: RewardClaimBody, request: Request) -> dict:
    user = _user(request)
    if body.action != "claim":
        raise HTTPException(status_code=403, detail="Customers can only claim their rewards")
    pf = _pf(request)
    reward = pf.repo.reward(reward_id)
    if not reward or reward["user_ref"] not in (user, user_ref(user)):
        raise HTTPException(status_code=404, detail="Not found")
    try:
        return pf.repo.transition_reward(reward_id, "CLAIMED", actor=f"user:{user_ref(user)}",
                                         user_ref=reward["user_ref"])
    except Exception as error:
        raise _err(error) from None


@router.post("/api/payments/webhook/{provider}")
async def payment_webhook(provider: str, request: Request) -> dict:
    body = await request.body()
    try:
        result = _pf(request).payments.webhook(provider, body, request.headers.get("x-askodox-signature") or "")
    except PermissionError as error:
        raise HTTPException(status_code=401, detail=str(error)) from None
    except Exception as error:
        raise _err(error) from None
    return {"ok": True, "duplicate": result["duplicate"], "status": result["payment"]["status"]}


@router.get("/api/notifications/inbox")
def inbox(request: Request) -> dict:
    user = _user(request)
    return {"items": _pf(request).notifications.inbox(user_ref(user))}


# ---------------------------------------------------- discovery pipeline --
# universal_deals._discover calls these; every one is best-effort and never
# breaks discovery.

def discovery_affiliate_rows(container: Any, demand: Dict[str, Any], *, trace_key: str = "") -> List[Dict[str, Any]]:
    """Command Center affiliate links matching the need (disclosed, tracked
    via /go/af). Callers skip service needs and supply-side requests."""
    return platform(container).affiliate.rows(demand, trace_key=trace_key)


def discovery_video_rows(container: Any, demand: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Reviewed videos relevant to the need. Organic first; the caller puts
    sponsored ones after every organic row."""
    pf = platform(container)
    rows = pf.videos.rows(demand)
    for row in rows:
        pf.repo.record_event("video_impression", video_id=row["video_id"], creator_id=row.get("creator_id"),
                             category=str(demand.get("domain") or ""), source="discover")
    return rows


def annotate_merchant_offers(container: Any, matches: List[Dict[str, Any]]) -> None:
    """A registered seller's live, reviewed offer rides on their result."""
    catalog = getattr(container, "product_catalog_repository", None)
    owners: Dict[str, List[Dict[str, Any]]] = {}
    for item in matches:
        if item.get("match_source") != "registered" or not str(item.get("id") or "").isdigit() or catalog is None:
            continue
        listing = catalog.get(int(item["id"])) or {}
        seller = str(listing.get("seller_user_id") or "")
        if seller:
            owners.setdefault(seller, []).append(item)
    if not owners:
        return
    pf = platform(container)
    for seller, offer in pf.offers.live_for(owners).items():
        for item in owners[seller]:
            item["merchant_offer"] = {"id": offer["id"], "title": offer["data"].get("title"),
                                      "summary": pf.offers.summary(offer),
                                      "min_bill": offer["data"].get("min_bill"),
                                      "valid_to": offer["data"].get("valid_to"),
                                      "claim_path": f"/api/merchant-offers/{offer['id']}/claim"}


def record_search(container: Any, demand: Dict[str, Any], matches: List[Dict[str, Any]], *,
                  trace_key: str = "") -> None:
    """search + no_match events with stable ids for the attribution funnel."""
    pf = platform(container)
    constraints = demand.get("constraints") or {}
    # No user reference here: the public discovery body's user id is not
    # token-proven. Signed-in funnel steps come through /api/track.
    common = {"category": str(demand.get("domain") or "")[:80], "location": str(demand.get("location_text") or "")[:120],
              "language": str(constraints.get("language") or (demand.get("trace") or {}).get("language") or "")[:12],
              "search_id": trace_key[:80] or None}
    pf.repo.record_event("search", detail={"results": len(matches)}, **common)
    if not matches:
        pf.repo.record_event("no_match", detail={"subject": str(demand.get("subject") or "")[:120]}, **common)
