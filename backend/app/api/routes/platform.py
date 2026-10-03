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

import json
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


class _LazyPush:
    """Resolves the FCM sender at send time (credentials can change at runtime)."""

    def __init__(self, platform: "Platform") -> None:
        self.platform = platform

    @property
    def configured(self) -> bool:
        return bool(getattr(self.platform.push(), "configured", False))

    def notify(self, user_id: str, **kwargs: Any) -> int:
        return self.platform.push().notify(user_id, **kwargs)


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
        self.videos = VideoEngine(self.repo, self.affiliate)
        self.reviews = ReviewEngine(self.repo)
        self.registry = fin.IntegrationRegistry(settings.database_path, secret_box=box_from_settings(settings))
        self.payments = fin.PaymentService(self.repo, self.registry)
        self.ledger = fin.RevenueLedger(self.repo)
        from app.services import comms

        self.outbox = comms.Outbox(settings.database_path)
        self.messenger = comms.Messenger(self.registry, self.outbox,
                                         http=getattr(container, "comms_http", None),
                                         smtp_factory=getattr(container, "smtp_factory", None),
                                         push=_LazyPush(self), contacts=self._contact)
        self.notifications = fin.NotificationDispatcher(self.repo, self.registry, messenger=self.messenger)
        from app.services.razorpay_gateway import RazorpayGateway

        self.razorpay = RazorpayGateway(self.repo, self.registry,
                                        getattr(container, "comms_http", None) or comms.default_http)
        self._push: Any = None
        from app.services.promotion_engine import PromotionEngine

        self.promotions = PromotionEngine(settings.database_path, self.repo, messenger=self.messenger,
                                          outbox=self.outbox, user_ref=user_ref)
        self.resources = ResourceService(self.repo, effects={
            "link_test": self._link_test, "preview": self._preview,
            "promo_estimate": lambda record, params: {"result": self.promotions.estimate(record)},
            "promo_preview": lambda record, params: {"result": self.promotions.preview(record)},
            "promo_run": lambda record, params: {"result": self.promotions.run(
                record, enabled=self._flag_on("notifications.promotions"))},
        }, ref_exists=self._ref_exists)
        self._blocked_cache: tuple[float, set[str]] = (0.0, set())
        from app.services.video_content import WebVideoStore

        self.web_videos = WebVideoStore(settings.database_path)
        self._video_study: Any = None

    @property
    def video_study(self) -> Any:
        """Grounded short-video study (lazy: one cache, the media brain's client)."""
        if self._video_study is None:
            from app.services.video_study import VideoStudyService, VideoStudyStore

            brain = getattr(self.container, "universal_image_service", None)
            self._video_study = VideoStudyService(
                VideoStudyStore(self.container.settings.database_path), client=getattr(brain, "client", None),
                models=tuple(getattr(brain, "GEMINI_IMAGE_MODELS", ()) or ("gemini-3.6-flash", "gemini-3.5-flash")))
        return self._video_study

    def _flag_on(self, key: str) -> bool:
        from app.api.routes.command_center import feature_enabled

        return feature_enabled(self.container, key)

    def run_due_promotions(self) -> Dict[str, Any]:
        """Background runner + admin button: deliver every due campaign window."""
        campaigns = self.repo.list("promotion_campaigns", status="ACTIVE")
        return self.promotions.run_due(campaigns, enabled=self._flag_on("notifications.promotions"))

    # online payments -----------------------------------------------------
    def checkout_provider(self) -> Optional[str]:
        """The gateway that can take an online payment right now: one with a real
        adapter, credentials and TEST/LIVE status (Razorpay today)."""
        status = self.registry.status("razorpay")
        return "razorpay" if status["status"] in (fin.STATUS_LIVE, fin.STATUS_TEST) else None

    def start_checkout(self, payment: Dict[str, Any]) -> Dict[str, Any]:
        if payment["provider"] != "razorpay":
            raise fin.PlatformConflict("no checkout adapter for this provider")
        return self.razorpay.start(payment)

    def sync_order(self, payment: Dict[str, Any]) -> None:
        """A gateway-paid customer order becomes payment VERIFIED (by the gateway)."""
        ref = str(payment.get("order_ref") or "")
        if payment.get("status") != "PAID" or not ref.startswith("order:"):
            return
        try:
            order_id = int(ref.split(":", 1)[1])
            from datetime import datetime, timezone

            self.container.order_repository.update_fields(
                order_id, payment_state="VERIFIED", payment_verified_by="gateway",
                payment_reference=payment.get("provider_ref") or payment["id"],
                paid_at=datetime.now(timezone.utc).isoformat())
        except Exception:
            pass

    # communications ------------------------------------------------------
    def push(self) -> Any:
        """The FCM sender: the service account saved in the Command Center, else the
        existing FIREBASE_SERVICE_ACCOUNT_JSON deployment variable."""
        from app.services.push_service import PushService, push_service

        stored = self.registry._secrets(self.registry._row("fcm_push")).get("service_account_json", "")
        if not stored:
            return push_service(self.container)
        if self._push is None or getattr(self._push, "_source", None) != stored:
            self._push = PushService(self.container.settings.database_path, service_account_json=stored)
            self._push._source = stored
        return self._push

    @staticmethod
    def _contact(user_ref: str, channel: str) -> Optional[str]:
        """A user's mobile comes from their phone-based id; no e-mail is stored for
        customers, so e-mail goes only to an address given explicitly."""
        if channel in ("sms", "whatsapp"):
            from app.repositories.user_profile_repository import UserProfileRepository

            return UserProfileRepository.mobile_for(user_ref)
        return None

    def probes(self) -> Dict[str, Any]:
        from app.services import comms

        custom = getattr(self.container, "integration_probes", None)
        if custom is not None:
            return custom
        return comms.default_probes(getattr(self.container, "comms_http", None) or comms.default_http,
                                    push=self.push(), smtp_factory=getattr(self.container, "smtp_factory", None))

    # real video sources -------------------------------------------------
    def http_json(self, url: str, params: Dict[str, str]) -> tuple[int, Any]:
        """GET a JSON API (injectable as container.video_fetcher in tests)."""
        fetcher = getattr(self.container, "video_fetcher", None)
        if fetcher is not None:
            return fetcher(url, params)
        import httpx

        response = httpx.get(url, params=params, timeout=4.0, follow_redirects=True,
                             headers={"User-Agent": "ASKODOX/2.0"})
        try:
            body = response.json()
        except ValueError:
            body = None
        return response.status_code, body

    def youtube_key(self) -> str:
        # Command Center value first, then YOUTUBE_API_KEY / YOUTUBE_DATA_API_KEY.
        return self.registry.secret("youtube_data", "api_key")

    def oembed(self):
        from app.services import external_call_budget
        from app.services.video_content import YouTubeOEmbed

        def cached(url: str, params: Dict[str, str]) -> tuple[int, Any]:
            return external_call_budget.cached_call(
                "youtube_oembed", (params.get("url"),), lambda: self.http_json(url, params), ttl=24 * 3600)

        return YouTubeOEmbed(cached)

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
        try:  # editable defaults for the Universal Advisor (only into an empty resource)
            from app.services.advisor_engine import seed_defaults

            seed_defaults(existing.resources)
        except Exception:
            pass
    from app.services import platform_settings

    repo = existing.repo
    platform_settings.set_source(lambda: repo.list("platform_settings"), key=repo.db_path)
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
            event, user_ref=user_ref(user_id), values=values, language=language, contact_id=user_id,
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
        verb = (spec.perm if spec and spec.perm else None) or ("manage" if manage else "view")
        principal = _require(request, f"{res.permission}:{verb}")
        if spec and spec.confirm and not body.confirm:
            raise HTTPException(status_code=409, detail=f"Confirmation required to {spec.label.lower()}")
        if res.four_eyes and verb == "approve":
            from app.services import governance as gov

            record = _pf(request).resources.get(resource, record_id)
            if record.get("created_by") == principal["id"] and not gov.is_super(principal):
                raise HTTPException(status_code=403,
                                    detail=f"{gov.FORBIDDEN} A second person must approve what you created.")
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
    if payment["provider"] == "razorpay" and payment["status"] in ("CREATED", "PENDING"):
        try:
            payment = payment | {"checkout": _pf(request).start_checkout(payment)}
        except Exception as error:
            payment = payment | {"checkout_error": str(error)[:200]}
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
        elif action in ("simulate_paid", "simulate_failed"):
            result = pf.payments.simulate(payment_id, action.split("_", 1)[1], actor=principal["id"])
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
    return {"items": _pf(request).registry.all(), "runtime": runtime_identity()}


def runtime_identity() -> Dict[str, str]:
    """Which deployment answered (Railway's own non-secret variables), so the
    console always says whose configuration it is showing."""
    import os

    env = os.environ
    return {"environment": env.get("RAILWAY_ENVIRONMENT_NAME") or env.get("ASKODOX_ENV") or "local",
            "service": env.get("RAILWAY_SERVICE_NAME", ""),
            "branch": env.get("RAILWAY_GIT_BRANCH", ""),
            "commit": (env.get("RAILWAY_GIT_COMMIT_SHA", "") or "")[:7],
            "domain": env.get("RAILWAY_PUBLIC_DOMAIN", "")}


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
    if status["missing"] and status["status"] != fin.STATUS_MOCK:
        return pf.registry.record_check(provider, False, f"missing: {', '.join(status['missing'])}")
    if status["status"] == fin.STATUS_MOCK:
        return status | {"note": "Mock mode never contacts the provider -- switch the mode to test to run a live "
                                 "check."}
    if not status["available"]:
        raise HTTPException(status_code=409, detail="Not available in this environment")
    probe = pf.probes().get(provider)
    if probe is None:
        # No automated probe for this provider: stays TEST until verified.
        _audit(request, principal, "integration.check", f"integration:{provider}", {"result": "manual"})
        return status | {"note": "No automated live check for this provider -- verify with the partner, then "
                                 "switch mode to live."}
    try:
        ok, detail = probe(pf.registry)
    except Exception as error:  # a provider outage is a failed check, not a 500
        ok, detail = False, f"{type(error).__name__}"
    _audit(request, principal, "integration.check", f"integration:{provider}", {"ok": ok})
    return pf.registry.record_check(provider, bool(ok), str(detail))


@admin_router.get("/readiness")
def integration_readiness(request: Request) -> dict:
    """One row per external integration, from live state (never a hand-set flag)."""
    from app.api.routes.partners import partner_repo
    from app.services.integration_readiness import readiness

    _require(request, "integrations:view")
    pf = _pf(request)
    try:
        partners = partner_repo(request.app.state.container).partners()
    except Exception:
        partners = []
    return {"items": readiness(pf.registry, outbox=pf.outbox, repo=pf.repo, partners=partners),
            "environment": pf.registry.env.get("RAILWAY_ENVIRONMENT_NAME") or "local"}


# discovered web videos -> moderation queue

@admin_router.get("/web-videos")
def web_videos(request: Request, limit: int = 100) -> dict:
    """Real videos ASKODOX found through search (last seen first) -- the source
    for curating: send one to Pending Review to feature, link or monetise it."""
    _require(request, "content:view")
    pf = _pf(request)
    curated = {v["data"].get("source_ref") for v in pf.repo.list("videos") if v["data"].get("source_ref")}
    return {"items": [v | {"in_review_queue": v["ref"] in curated}
                      for v in pf.web_videos.recent(max(1, min(limit, 200)))]}


class PromoteVideoBody(BaseModel):
    relationship: str = "creator"
    keywords: List[str] = Field(default_factory=list)
    video_type: str = "review"


@admin_router.post("/web-videos/{ref}/promote")
def promote_web_video(ref: str, body: PromoteVideoBody, request: Request) -> dict:
    """Copy a discovered video into Videos as PENDING_REVIEW (nothing is shown
    differently until an admin approves it). One curated record per video."""
    principal = _require(request, "content:manage")
    pf = _pf(request)
    item = pf.web_videos.get(ref)
    if not item:
        raise HTTPException(status_code=404, detail="Unknown web video")
    if any(v["data"].get("source_ref") == ref for v in pf.repo.list("videos")):
        raise HTTPException(status_code=409, detail="Already in the review queue")
    platform = item["platform"] if item["platform"] in ps.PLATFORMS else "other"
    keywords = body.keywords or [*item.get("products", []), *item.get("services", [])]
    try:
        record = pf.resources.create("videos", {
            "title": item["title"], "platform": platform, "url": item["url"],
            "thumbnail_url": item.get("thumbnail") if str(item.get("thumbnail") or "").startswith("https://") else None,
            "duration": item.get("duration"), "video_type": body.video_type, "description": item.get("snippet"),
            "keywords": keywords[:20], "categories": [item["category"]] if item.get("category") else [],
            "products": item.get("products") or [], "services": item.get("services") or [],
            "relationship": body.relationship, "source_ref": ref,
        }, actor=principal["id"])
    except Exception as error:
        raise _err(error) from None
    _audit(request, principal, "video.promote", f"video:{record['id']}", {"source_ref": ref})
    return record


class TestSendBody(BaseModel):
    to: str = Field(min_length=3, max_length=200)
    title: str = Field(default="ASKODOX test", max_length=120)
    body: str = Field(default="This is a test message from ASKODOX.", max_length=1000)


@admin_router.post("/integrations/{provider}/test-send")
def integration_test_send(provider: str, body: TestSendBody, request: Request) -> dict:
    """Send one message through a messaging provider. In mock mode nothing leaves
    ASKODOX; unconfigured providers are never contacted. Recipient is masked."""
    from app.services import comms

    from app.services import rate_limit

    principal = _require(request, "integrations:manage")
    if provider not in comms.PROVIDER_CHANNEL:
        raise HTTPException(status_code=404, detail="Not a messaging provider")
    rate_limit.check(request, "integration_test_send", limit=20)
    record = _pf(request).messenger.send(comms.PROVIDER_CHANNEL[provider], title=body.title, body=body.body,
                                         to=body.to, event="admin_test")
    _audit(request, principal, "integration.test_send", f"integration:{provider}",
           {"status": record["status"], "to": record["to_masked"]})
    return record


@admin_router.get("/outbox")
def outbox(request: Request, channel: str = "", limit: int = 100) -> dict:
    _require(request, "integrations:view")
    pf = _pf(request)
    return {"items": pf.outbox.list(channel=channel or None, limit=limit), "summary": pf.outbox.summary(),
            "opt_outs": pf.outbox.optout_counts()}


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


@admin_router.get("/analytics/outcomes")
def outcome_analytics(request: Request, days: int = 30, category: str = "", location: str = "",
                      source: str = "", role: str = "") -> dict:
    """Demand -> results -> action -> fulfilment, with supply gaps, source
    performance, organic vs affiliate, advisor, video, offers, seller
    response, opportunities, escalations and integration health."""
    from app.services import outcome_analytics as oa

    _require(request, "analytics:view")
    container = request.app.state.container
    return oa.outcomes(_pf(request), container, days=max(1, min(days, 365)), category=category,
                       location=location, source=source, role=role)


@admin_router.get("/insights")
def platform_insights(request: Request, days: int = 7) -> dict:
    _require(request, "insights:view")
    pf = _pf(request)
    broken = [r["data"].get("slug") for r in pf.repo.list("smart_links")
              if (r["data"].get("health") or {}).get("state") == "ERROR"]
    try:
        from app.services.self_healing import engine

        fixes = engine(request.app.state.container).repeated_conversation_fixes(days=max(1, min(days, 90)))
    except Exception:
        fixes = []
    return {"items": fin.insights(pf.repo, days=max(1, min(days, 90)),
                                  extra={"broken_links": broken, "conversation_fixes": fixes}),
            "note": "Suggestions only -- nothing is changed automatically."}


@admin_router.get("/revenue-command")
def revenue_command(request: Request, period: str = "30d", start: str = "", end: str = "") -> dict:
    """One reconciled revenue view (sources, states, breakdowns, no double counting)."""
    from app.services import revenue_command as rc
    from app.services.revenue_center_service import period_bounds

    _require(request, "revenue:view")
    try:
        bounds = period_bounds(period, start=start, end=end)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None
    pf = _pf(request)
    try:
        from app.api.routes.partners import partner_repo

        prepo = partner_repo(request.app.state.container)
    except Exception:
        prepo = None
    reward_cost = sum(float(r.get("amount") or 0) for r in pf.repo.rewards()
                      if r["state"] == "REDEEMED" and bounds["start"] <= r["created_at"] < bounds["end"])
    gmv = sum(float(p["amount"]) for p in pf.repo.payments(limit=5000)
              if p["status"] in ("PAID", "SETTLED") and bounds["start"] <= p["created_at"] < bounds["end"])
    out = rc.summary(pf.repo, prepo, bounds, reward_cost=reward_cost, gmv_payments=gmv)
    out["reconciliation"] = pf.ledger.reconcile()
    return out


@admin_router.get("/events")
def platform_events(request: Request, event: str = "", limit: int = 200, category: str = "", q: str = "",
                    days: int = 0) -> dict:
    """The Event Stream: one vocabulary for the whole journey, each row with
    the specific detected category (domain / subcategory / intent in detail)."""
    from datetime import datetime, timedelta, timezone

    from app.repositories.platform_repository import EVENTS

    _require(request, "analytics:view")
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat() if days > 0 else None
    wanted = max(1, min(limit, 1000))
    rows = _pf(request).repo.events(event=event or None, since=since, limit=5000 if (category or q) else wanted)
    needle, cat = q.strip().lower(), category.strip().lower()
    items = []
    for r in rows:
        d = r.get("detail") or {}
        if cat and cat not in str(r.get("category") or "").lower():
            continue
        if needle and needle not in json.dumps(d, default=str).lower() and needle not in str(r.get("category") or "").lower():
            continue
        items.append({**r, "domain": d.get("domain"), "subcategory": d.get("subcategory"), "intent": d.get("intent")})
        if len(items) >= wanted:
            break
    return {"items": items, "events": list(EVENTS)}


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
        # A real web video ASKODOX showed (YouTube / web search).
        from app.services.video_content import explain_web

        web = pf.web_videos.get(video_id)
        if not web:
            raise HTTPException(status_code=404, detail="Video not found") from None
        result = explain_web(web, body.question, language=body.language)
        # Studied on request: the chat discusses the video from its grounded
        # study (facts with basis + timestamps), never from the title alone.
        study = pf.video_study.cached(video_id)
        if study and study.get("status") == "ready":
            said = {"te": "విక్రేత చెప్పినది", "hi": "विक्रेता का दावा"}.get(body.language[:2], "seller claim")
            shown = {"te": "వీడియోలో కనిపించింది", "hi": "वीडियो में दिखा"}.get(body.language[:2], "shown in the video")
            result = {**result, "analyzed": True, "answer": study.get("summary") or result["answer"],
                      "from_source": [f"{f['label']}: {f['value']} ({shown if f['basis'] == 'confirmed_from_video' else said})"
                                      + (f" [{f['timestamp']}]" if f.get("timestamp") else "")
                                      for f in study.get("facts") or []][:12]}
    user = _optional_user(request)
    pf.repo.record_event("video_ask", video_id=video_id, user_ref=user_ref(user) if user else None,
                         language=body.language, detail={"analyzed": result["analyzed"]})
    return result


class StudyBody(BaseModel):
    language: str = Field(default="en", max_length=8)


class StudyAskBody(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    language: str = Field(default="en", max_length=8)


class MarketBody(BaseModel):
    language: str = Field(default="en", max_length=8)
    location: dict | None = None


def _study_target(request: Request, video_id: str) -> Dict[str, Any]:
    """A video ASKODOX knows: a web/YouTube result it showed, or an upload it studied."""
    pf = _pf(request)
    if video_id.startswith("up_"):
        study = pf.video_study.store.get(video_id)
        if not study:
            raise HTTPException(status_code=404, detail="Video not found")
        return {"ref": video_id, "source": "upload", "duration": study.get("duration_seconds"), "url": ""}
    web = pf.web_videos.get(video_id)
    if not web:
        raise HTTPException(status_code=404, detail="Video not found")
    from app.services.video_content import youtube_id
    from app.services.video_study import duration_seconds

    return {"ref": video_id, "source": "youtube" if youtube_id(web.get("url") or "") else "web",
            "duration": duration_seconds(web.get("duration")), "url": web.get("url") or "", "web": web,
            "registered": _registered_video(pf, video_id, web.get("url") or "")}


def _registered_video(pf: Any, ref: str, url: str) -> Optional[Dict[str, Any]]:
    """The Command Center video record of a REGISTERED ASKODOX seller /
    provider / creator for this web video, if any. Only such videos (and the
    user's own uploads) get deep Video Study; other external videos are
    normal results and playback."""
    from app.services.video_content import youtube_id

    yid = youtube_id(url) if url else None
    for record in pf.repo.list("videos"):
        if record.get("status") != "ACTIVE":
            continue
        d = record.get("data") or {}
        if not (d.get("merchant_ref") or d.get("provider_ref") or d.get("creator_id")):
            continue
        if d.get("source_ref") == ref or (yid and youtube_id(str(d.get("url") or "")) == yid):
            return {"id": record["id"], "owner": "merchant" if d.get("merchant_ref") else
                    "provider" if d.get("provider_ref") else "creator"}
    return None


_PUBLIC_DROP = ("transcript", "visible_text")


def _public_study(study: Optional[Dict[str, Any]], language: str) -> Optional[Dict[str, Any]]:
    """What the customer app receives: facts with evidence + timestamps,
    suggestions in THEIR language; never the raw transcript."""
    if not study:
        return study
    from app.services.video_study import suggested_questions

    out = {k: v for k, v in study.items() if k not in _PUBLIC_DROP}
    if study.get("status") == "ready":
        out["suggested_questions"] = suggested_questions(study, language)
    return out


def _external_not_eligible(target: Dict[str, Any], language: str) -> Optional[Dict[str, Any]]:
    if target["source"] == "upload" or target.get("registered"):
        return None
    message = {"te": "ఇది బయటి వీడియో: ఇక్కడ చూడవచ్చు. లోతైన వీడియో అధ్యయనం ASKODOX లో నమోదైన విక్రేతల / ప్రొవైడర్ల "
                     "వీడియోలకు మాత్రమే.",
               "hi": "यह बाहरी वीडियो है: इसे यहाँ देख सकते हैं। गहन वीडियो अध्ययन केवल ASKODOX पर पंजीकृत विक्रेताओं / "
                     "प्रदाताओं के वीडियो के लिए है।"}.get(language[:2],
                    "This is an external video: you can watch it here. Deep Video Study is for videos from "
                    "registered ASKODOX sellers / providers and your own uploads.")
    return {"eligible": False, "reason": "external_video", "message": message}


@router.get("/api/videos/{video_id}/study")
def video_study_status(video_id: str, request: Request, language: str = "en") -> dict:
    """Eligibility (hard length cap) + the cached study, if any. Cheap: no model call."""
    from app.services.video_study import eligibility

    target = _study_target(request, video_id)
    gate = eligibility(target["duration"], language)
    external = _external_not_eligible(target, language)
    if external:
        gate = {**gate, **external}
    elif target["source"] == "web":
        gate = {**gate, "eligible": False, "reason": "unsupported_source",
                "message": "Video Study supports YouTube videos and your own uploads."}
    study = None if external else _pf(request).video_study.cached(video_id)
    return {"ref": video_id, **gate, "studyable": bool(gate.get("eligible")) and not external,
            "status": (study or {}).get("status") or "none", "study": _public_study(study, language)}


@router.post("/api/videos/{video_id}/study")
def video_study_run(video_id: str, body: StudyBody, request: Request) -> dict:
    """Study the video now (only when eligible; cached by video)."""
    from app.services import rate_limit
    from app.services.video_study import eligibility, suggested_questions, unavailable_message

    target = _study_target(request, video_id)
    pf = _pf(request)
    external = _external_not_eligible(target, body.language)
    if external:
        return {"ref": video_id, "status": "not_eligible", **external}
    cached = pf.video_study.cached(video_id)
    if cached:
        study = {**cached, "cached": True}
    elif target["source"] != "youtube":
        gate = eligibility(target["duration"], body.language)
        return {"ref": video_id, "status": "not_eligible" if not gate["eligible"] else "unavailable",
                **gate, "message": gate["message"] or unavailable_message(body.language)}
    else:
        rate_limit.check(request, "video_study", limit=6)
        if not _flag(request, "results.videos"):
            raise HTTPException(status_code=403, detail="videos switched off")
        study = pf.video_study.study_youtube(video_id, target["url"], target["duration"], language=body.language)
    study = _public_study(study, body.language) or study
    user = _optional_user(request)
    pf.repo.record_event("video_study", video_id=video_id, user_ref=user_ref(user) if user else None,
                         language=body.language, detail={"status": study.get("status"),
                                                         "cached": bool(study.get("cached"))})
    return study


@router.post("/api/videos/{video_id}/ask")
def video_study_ask(video_id: str, body: StudyAskBody, request: Request) -> dict:
    """A grounded answer from the stored study (never re-processes the video)."""
    from app.services import rate_limit
    from app.services.video_study import unavailable_message

    rate_limit.check(request, "video_ask", limit=40)
    target = _study_target(request, video_id)
    external = _external_not_eligible(target, body.language)
    if external:
        return {"ref": video_id, "found": False, "status": "not_eligible", "answer": external["message"],
                "facts": [], "timestamps": []}
    pf = _pf(request)
    study = pf.video_study.store.get(video_id)
    if not study:
        return {"ref": video_id, "found": False, "status": "not_studied", "answer": unavailable_message(body.language),
                "facts": [], "timestamps": []}
    result = pf.video_study.answer(study, body.question, language=body.language)
    user = _optional_user(request)
    pf.repo.record_event("video_ask", video_id=video_id, user_ref=user_ref(user) if user else None,
                         language=body.language, detail={"analyzed": True, "found": result["found"]})
    return result


@router.post("/api/videos/{video_id}/market")
def video_market(video_id: str, body: MarketBody, request: Request) -> dict:
    """External market comparison for what the video offers -- through the
    existing discovery, always labelled external and kept apart from the
    video's own facts."""
    from app.api.routes.universal_deals import UniversalDealCreateRequest, discover_results
    from app.services.video_study import market_comparison, market_subject

    target = _study_target(request, video_id)
    if _external_not_eligible(target, body.language):
        raise HTTPException(status_code=409, detail="Market comparison follows a studied registered video")
    pf = _pf(request)
    study = pf.video_study.store.get(video_id)
    if not study or study.get("status") != "ready":
        raise HTTPException(status_code=409, detail="Study the video first")
    subject = market_subject(study)
    # Only a structured item (brand / model / year / product name) is looked
    # up -- never a free sentence that a search could misread (translation,
    # unrelated general search).
    if not subject or len(subject.split()) > 8:
        return {**market_comparison(study, [], body.language), "skipped": "no_structured_product"}
    service = study.get("category") == "service"
    facts = {f["key"]: f["value"] for f in study.get("facts") or []}
    structured = {k: v for k, v in facts.items()
                  if any(h in k for h in ("brand", "make", "model", "year", "variant", "size", "capacity"))}
    payload = UniversalDealCreateRequest(
        user_id="", raw_text=f"{subject} price", subject=subject,
        intent="needService" if service else "buy", category="services" if service else "product",
        dynamic_fields={k: str(v)[:60] for k, v in list(structured.items())[:6]},
        location=body.location or None, trace={"query": f"{subject} price", "source": "video_market"})
    try:
        rows = discover_results(payload, request).get("matches") or []
    except HTTPException:
        rows = []
    return market_comparison(study, rows, body.language)


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
    pf = _pf(request)
    if provider == "razorpay" and request.headers.get("x-razorpay-signature"):
        # Razorpay's own signed webhook format (Dashboard -> Webhooks -> this URL).
        try:
            result = pf.razorpay.webhook(body, request.headers.get("x-razorpay-signature") or "",
                                         request.headers.get("x-razorpay-event-id") or "")
        except PermissionError as error:
            raise HTTPException(status_code=401, detail=str(error)) from None
        except Exception as error:
            raise _err(error) from None
        if result.get("payment"):
            pf.sync_order(result["payment"])
        return {"ok": True, "duplicate": bool(result.get("duplicate")), "ignored": bool(result.get("ignored")),
                "status": (result.get("payment") or {}).get("status")}
    try:
        result = pf.payments.webhook(provider, body, request.headers.get("x-askodox-signature") or "")
    except PermissionError as error:
        raise HTTPException(status_code=401, detail=str(error)) from None
    except Exception as error:
        raise _err(error) from None
    pf.sync_order(result["payment"])
    return {"ok": True, "duplicate": result["duplicate"], "status": result["payment"]["status"]}


class ChannelPrefs(BaseModel):
    whatsapp: bool | None = None
    sms: bool | None = None
    email: bool | None = None
    push: bool | None = None


@router.get("/api/me/notification-channels")
def my_channels(request: Request) -> dict:
    """Which channels this customer accepts messages on (all on unless they opted out)."""
    user = _user(request)
    return {"channels": _pf(request).outbox.preferences(user_ref(user))}


@router.put("/api/me/notification-channels")
def set_my_channels(body: ChannelPrefs, request: Request) -> dict:
    """The customer's own opt-out -- always wins over any admin notification rule."""
    user = _user(request)
    pf = _pf(request)
    for channel, allowed in body.model_dump(exclude_none=True).items():
        pf.outbox.set_opt_out(user_ref(user), channel, not allowed, source="customer")
    return {"channels": pf.outbox.preferences(user_ref(user))}


class PromoConsent(BaseModel):
    in_app: Optional[bool] = None
    push: Optional[bool] = None
    email: Optional[bool] = None
    sms: Optional[bool] = None
    whatsapp: Optional[bool] = None


@router.get("/api/me/promotion-consent")
def my_promotion_consent(request: Request) -> dict:
    """In-app offers are on unless switched off; promotional push / SMS /
    WhatsApp / e-mail need the customer's own opt-in."""
    user = _user(request)
    return {"consent": _pf(request).promotions.consent(user_ref(user))}


@router.put("/api/me/promotion-consent")
def set_my_promotion_consent(body: PromoConsent, request: Request) -> dict:
    user = _user(request)
    pf = _pf(request)
    for channel, granted in body.model_dump(exclude_none=True).items():
        pf.promotions.set_consent(user_ref(user), channel, granted)
    return {"consent": pf.promotions.consent(user_ref(user))}


@router.get("/api/me/promotions")
def my_promotions(request: Request) -> dict:
    """At most five compact / quarter / half cards delivered to this user."""
    user = _user(request)
    pf = _pf(request)
    if not _flag(request, "notifications.promotions"):
        return {"items": []}
    campaigns = {c["id"]: c for c in pf.repo.list("promotion_campaigns")}
    return {"items": pf.promotions.feed(user_ref(user), campaigns)}


@router.post("/api/me/promotions/{delivery_id}/{action}")
def track_my_promotion(delivery_id: int, action: str, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "promo_track", limit=120)
    user = _user(request)
    try:
        ok = _pf(request).promotions.track(delivery_id, user_ref(user), action)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    if not ok:
        raise HTTPException(status_code=404, detail="Not found")
    return {"recorded": True}


@admin_router.post("/promotions/run-due")
def run_due_promotions(request: Request, confirm: bool = False) -> dict:
    principal = _require(request, "notifications:manage")
    if not confirm:
        raise HTTPException(status_code=409, detail="Confirmation required to send due promotions")
    result = _pf(request).run_due_promotions()
    _audit(request, principal, "promotions.run_due", "promotion_campaigns:*", {"campaigns": len(result)})
    return {"results": result}


@admin_router.get("/promotions/{campaign_id}/metrics")
def promotion_metrics(campaign_id: str, request: Request) -> dict:
    _require(request, "notifications:view")
    try:
        _pf(request).resources.get("promotion_campaigns", campaign_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Campaign not found") from None
    return _pf(request).promotions.metrics(campaign_id)


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


class QuotaExhausted(Exception):
    """The day's YouTube Data API budget is used up."""


def enrich_discovery_videos(container: Any, demand: Dict[str, Any], matches: List[Dict[str, Any]], *,
                            wants_videos: bool, trace_key: str = "") -> Dict[str, Any]:
    """Real web videos in the results become trackable, playable-where-allowed,
    linked to the need and honestly labelled. With a YouTube Data API key,
    YouTube's own search leads (with its paid-promotion declaration)."""
    from app.services import external_call_budget
    from app.services.video_content import enrich_rows, video_ref, youtube_rows_as_results, YouTubeDataSource

    pf = platform(container)
    info: Dict[str, Any] = {"youtube_data": "needs_configuration", "web": 0}
    subject = str(demand.get("subject") or "").strip()
    youtube_rows: List[Dict[str, Any]] = []
    key = pf.youtube_key()
    if key and wants_videos and subject:
        language = str((demand.get("constraints") or {}).get("language") or "")[:2]
        source = YouTubeDataSource(key, pf.http_json,
                                   region=str(getattr(container.settings, "search_country", "IN") or "IN"))
        def fetch():
            # search.list = 100 units + videos.list = 1 unit, reserved only on a cache miss.
            if not pf.registry.spend("youtube_data", 101):
                raise QuotaExhausted()
            return source.search(f"{subject} review", limit=6, language=language)

        try:
            raw = external_call_budget.cached_call(
                "youtube_data", ("search", subject.lower(), language), fetch, ttl=6 * 3600)
            youtube_rows = youtube_rows_as_results(raw or [], subject)
            info["youtube_data"] = "ok" if youtube_rows else "no_results"
        except QuotaExhausted:
            info["youtube_data"] = "quota_exhausted"  # web videos (Brave) still answer
        except Exception as error:
            external_call_budget.record_error("youtube_data")
            info["youtube_data"] = f"error:{type(error).__name__}"
    web_positions = [i for i, m in enumerate(matches) if m.get("match_source") == "video" and not m.get("video_id")]
    web_rows = [matches[i] for i in web_positions]
    seen = {video_ref(r["destination_url"]) for r in youtube_rows}
    web_rows = [r for r in web_rows if video_ref(str(r.get("destination_url") or "")) not in seen]
    category = str(demand.get("domain") or "")
    enriched = enrich_rows(youtube_rows[:4] + web_rows, demand, store=pf.web_videos, oembed=pf.oembed(),
                           category=category)
    info["web"] = len(enriched)
    # Replace the web rows in place (keeps their position after the local
    # results); YouTube Data rows lead the video section.
    for index in reversed(web_positions):
        matches.pop(index)
    insert_at = web_positions[0] if web_positions else len(matches)
    organic = [r for r in enriched if not r.get("sponsored")]
    paid = [r for r in enriched if r.get("sponsored")]
    matches[insert_at:insert_at] = organic
    matches.extend(paid)  # declared paid promotion: after every organic row
    for row in enriched:
        pf.repo.record_event("video_impression", video_id=row["video_id"], search_id=trace_key[:80] or None,
                             category=category[:80], source=row.get("platform") or "web",
                             detail={"kind": "web", "embeddable": row.get("embeddable")})
    return info


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


def journey_event(container: Any, event: str, *, category: str = "", location: str = "",
                  detail: Dict[str, Any] | None = None, value: float | None = None) -> None:
    """One funnel step in the shared event store (request, seller_accept,
    order ...). Aggregate-safe dimensions only -- no names, phones or ids of
    people. Never raises."""
    try:
        from app.services.demand_insights import area_key

        platform(container).repo.record_event(event, category=str(category or "")[:60],
                                              location=area_key(location)[:60], value=value,
                                              detail={k: v for k, v in (detail or {}).items() if v is not None})
    except Exception:
        pass


def record_search(container: Any, demand: Dict[str, Any], matches: List[Dict[str, Any]], *,
                  trace_key: str = "") -> None:
    """search + no_match events with stable ids for the attribution funnel."""
    from app.services.category_signal import for_demand

    pf = platform(container)
    constraints = demand.get("constraints") or {}
    category, subcategory = for_demand(demand)
    # No user reference here: the public discovery body's user id is not
    # token-proven. Signed-in funnel steps come through /api/track.
    common = {"category": category, "location": str(demand.get("location_text") or "")[:120],
              "language": str(constraints.get("language") or (demand.get("trace") or {}).get("language") or "")[:12],
              "search_id": trace_key[:80] or None}
    detail = {"results": len(matches), "domain": str(demand.get("domain") or "")[:40],
              "subject": str(demand.get("subject") or "")[:120], "intent": str(demand.get("side") or "").lower(),
              # Supply signal for Demand Intelligence: how many results were
              # local (registered / nearby), never who searched.
              "local": sum(1 for m in matches if m.get("match_source") in {"registered", "interest", "demo_discovery"}
                           or m.get("segment") in {"nearby_external", "wider_local"})}
    from app.services.demand_insights import budget_band

    dynamic = dict(constraints.get("dynamic_fields") or {})
    band = budget_band(dynamic.get("budget_max") or dynamic.get("budget") or demand.get("price"))
    if band:
        detail["budget_band"] = band
    brand = str(constraints.get("brand") or dynamic.get("brand") or "").strip()
    if brand and brand.casefold() not in {"any", "no preference", "none"}:
        detail["brand"] = brand[:40]
    if subcategory:
        detail["subcategory"] = subcategory
    # Source performance: how many results each source contributed.
    sources: Dict[str, int] = {}
    for m in matches:
        key = "affiliate" if m.get("affiliate") else str(m.get("segment") or m.get("match_source") or "other")
        sources[key[:30]] = sources.get(key[:30], 0) + 1
    if sources:
        detail["sources"] = sources
    pf.repo.record_event("search", detail=detail, **common)
    if not matches:
        pf.repo.record_event("no_match", detail=detail, **common)
