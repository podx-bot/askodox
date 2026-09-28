"""Affiliate / Partner Hub + Revenue Center routes.

Public (no secrets ever returned):
  GET  /go/{click_id} ................ tracked redirect to the partner
                                       (records "partner_opened")
  POST /api/partners/event ........... in-app card_view / click for a shown
                                       partner result (click id required)
  GET|POST /api/partners/{slug}/postback  partner conversion/lead callback
                                       (token-verified)
Admin (Command Center; partners:view|manage, revenue:view|manage,
analytics:export):
  /admin/cc/partners ...................... list / create / edit / enable
  /admin/cc/partners/guide ................ what the owner needs + where
  /admin/cc/partners/{id}/secrets/{name} .. set a key (write-only)
  /admin/cc/partners/{id}/postback-token .. generate (shown once)
  /admin/cc/partners/{id}/test ............ integration test
  /admin/cc/partners/{id}/import .......... partner report CSV
  /admin/cc/partners/conversions/{id} ..... manual reconciliation
  /admin/cc/revenue[/why|/records|/export.csv|/entries]
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import PlainTextResponse, RedirectResponse
from pydantic import BaseModel, Field

from app.repositories.partner_revenue_repository import (
    CONVERSION_STATES,
    REVENUE_SOURCES,
    SECRET_NAMES,
    PartnerRevenueRepository,
)
from app.services import affiliate_partner_service as partners_service
from app.services.revenue_center_service import RevenueCenter, period_bounds

router = APIRouter(tags=["partners"])
admin_router = APIRouter(prefix="/admin/cc", tags=["command-center"])


def partner_repo(container: Any) -> PartnerRevenueRepository:
    repo = getattr(container, "partner_revenue_repository", None)
    if repo is None:
        repo = PartnerRevenueRepository(container.settings.database_path)
        container.partner_revenue_repository = repo
    return repo


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    try:
        from app.api.routes.command_center import command_center

        entity_type, _, entity_id = target.partition(":")
        command_center(request.app.state.container).audit(principal["id"], action, entity_type, entity_id,
                                                          after=detail or {})
    except Exception:
        pass


def _public_base(request: Request) -> str:
    configured = str(getattr(request.app.state.container.settings, "public_base_url", "") or "").rstrip("/")
    if configured:
        return configured
    proto = request.headers.get("x-forwarded-proto") or request.url.scheme
    host = request.headers.get("x-forwarded-host") or request.headers.get("host") or request.url.netloc
    return f"{proto}://{host}"


# ------------------------------------------------------------- public --

@router.get("/go/{click_id}", include_in_schema=False)
def partner_redirect(click_id: str, request: Request) -> RedirectResponse:
    """Only URLs ASKODOX itself generated for an impression are followed
    (never an arbitrary URL -> no open redirect)."""
    from app.services import rate_limit

    rate_limit.check(request, "partner_go", limit=60)
    repo = partner_repo(request.app.state.container)
    context = repo.impression_context(click_id[:40])
    url = str(((context or {}).get("detail") or {}).get("url") or "")
    if not context or not url.startswith("https://"):
        raise HTTPException(status_code=404, detail="Link expired or unknown")
    repo.record_event("partner_opened", partner_id=context["partner_id"], click_id=click_id,
                      trace_key=context.get("trace_key"), category=context.get("category") or "",
                      subject=context.get("subject") or "", location=context.get("location") or "",
                      language=context.get("language") or "", campaign=context.get("campaign") or "")
    return RedirectResponse(url, status_code=302)


class PartnerEvent(BaseModel):
    click_id: str = Field(min_length=6, max_length=40)
    event: str


@router.post("/api/partners/event")
def partner_event(payload: PartnerEvent, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "partner_event", limit=120)
    if payload.event not in {"card_view", "click"}:
        raise HTTPException(status_code=422, detail="event must be card_view or click")
    repo = partner_repo(request.app.state.container)
    context = repo.impression_context(payload.click_id)
    if context is None:
        raise HTTPException(status_code=404, detail="Unknown result")
    repo.record_event(payload.event, partner_id=context["partner_id"], click_id=payload.click_id,
                      trace_key=context.get("trace_key"), category=context.get("category") or "",
                      subject=context.get("subject") or "", location=context.get("location") or "",
                      language=context.get("language") or "", campaign=context.get("campaign") or "")
    return {"recorded": payload.event}


@router.api_route("/api/partners/{slug}/postback", methods=["GET", "POST"])
async def partner_postback(slug: str, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "partner_postback", limit=300)
    repo = partner_repo(request.app.state.container)
    partner = repo.partner_by_slug(slug)
    if partner is None:
        raise HTTPException(status_code=404, detail="Unknown partner")
    params: dict[str, Any] = dict(request.query_params)
    if request.method == "POST":
        try:
            body = await request.json()
            if isinstance(body, dict):
                params.update(body)
        except Exception:
            form = await request.form()
            params.update({k: v for k, v in form.items()})
    try:
        return partners_service.handle_postback(repo, partner, params)
    except PermissionError as error:
        raise HTTPException(status_code=403, detail="Invalid postback token") from error
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


# ------------------------------------------------------ admin: partners --

GUIDE = {
    "levels": [
        {"level": 1, "name": "Affiliate / deep link", "needs": "tracking ID + a deep-link template or base URL",
         "gives": "a tracked 'search on partner' result; ASKODOX measures impressions, clicks and partner opens"},
        {"level": 2, "name": "Product / feed API", "needs": "feed URL, field mapping and an API key (if the partner "
                                                            "offers one)",
         "gives": "real product rows with the partner's own titles, prices and images"},
        {"level": 3, "name": "Conversion API / postback", "needs": "paste ASKODOX's postback URL into the partner's "
                                                                   "dashboard (token generated here)",
         "gives": "leads, orders, order value and commission states"},
        {"level": 4, "name": "Report import / manual", "needs": "the partner's conversion report as CSV",
         "gives": "orders and commission when no postback exists"},
    ],
    "fields": [
        {"field": "name", "where": "Your choice -- shown to customers as the source."},
        {"field": "signup_url", "where": "The partner's affiliate / partner program page (search '<company> affiliate "
                                         "program'). Apply there with ASKODOX's business details."},
        {"field": "apply_instructions", "where": "Notes for whoever applies (documents, approval time)."},
        {"field": "tracking_id", "where": "After approval: partner dashboard -> account / tracking IDs / link tools."},
        {"field": "link_instructions", "where": "Where in the partner dashboard the link builder or deep-link tool is."},
        {"field": "deep_link_template", "where": "Build from the partner's link tool. Placeholders: {query}, {url}, "
                                                 "{tracking_id}, {sub_id}, {campaign}, {category}. Must be https."},
        {"field": "base_url", "where": "Fallback link when no template exists (may contain {query})."},
        {"field": "sub_id_param", "where": "The partner's sub-ID / click-reference parameter (e.g. 'subid'); ASKODOX "
                                           "puts its click id there so reports can be matched."},
        {"field": "campaign_params", "where": "Extra fixed URL parameters, e.g. {\"utm_source\": \"askodox\"}."},
        {"field": "feed", "where": "Only if the partner gives a product API/feed: {\"url\": \"https://...{query}\", "
                                   "\"items_path\": \"data.items\", \"title\": \"name\", \"item_url\": \"link\", \"price\": "
                                   "\"price\", \"image\": \"image\", \"auth\": \"header:X-Api-Key\"}."},
        {"field": "secrets", "where": "API key / feed token: paste here (write-only, stored on the server, never sent "
                                      "to the app)."},
        {"field": "webhook_notes", "where": "Where the partner's postback / conversion-API settings are."},
        {"field": "commission", "where": "From the partner's commission table: {\"percent\": 4} or {\"flat\": 50} or "
                                         "{\"per_category\": {\"tv\": 2.5}}. Used only for 'expected' amounts."},
        {"field": "attribution_notes", "where": "Cookie window / attribution rules from the partner's terms."},
        {"field": "categories / countries / locations", "where": "Where this partner is relevant (empty = all)."},
    ],
    "note": "An affiliate link does not give access to a partner's full product database or customer-care APIs. "
            "Only what the partner actually provides is used.",
}


class PartnerPayload(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    logo_url: str | None = Field(default=None, max_length=400)
    categories: list[str] | None = None
    countries: list[str] | None = None
    locations: list[str] | None = None
    signup_url: str | None = Field(default=None, max_length=400)
    apply_instructions: str | None = Field(default=None, max_length=2000)
    link_instructions: str | None = Field(default=None, max_length=2000)
    base_url: str | None = Field(default=None, max_length=600)
    deep_link_template: str | None = Field(default=None, max_length=800)
    tracking_id: str | None = Field(default=None, max_length=120)
    sub_id_param: str | None = Field(default=None, max_length=40)
    campaign_params: dict[str, str] | None = None
    feed: dict[str, str] | None = None
    webhook_notes: str | None = Field(default=None, max_length=2000)
    commission: dict[str, Any] | None = None
    attribution_notes: str | None = Field(default=None, max_length=2000)
    notes: str | None = Field(default=None, max_length=2000)
    active: bool | None = None


def _checked(payload: PartnerPayload) -> dict:
    data = payload.model_dump(exclude_none=True)
    for field in ("signup_url", "base_url", "deep_link_template", "logo_url"):
        value = str(data.get(field) or "").strip()
        if value and not value.startswith("https://"):
            raise HTTPException(status_code=422, detail=f"{field} must start with https://")
    feed_url = str((data.get("feed") or {}).get("url") or "")
    if feed_url and not feed_url.startswith("https://"):
        raise HTTPException(status_code=422, detail="feed url must start with https://")
    commission = data.get("commission") or {}
    for key in ("percent", "flat"):
        if commission.get(key) not in (None, ""):
            try:
                if float(commission[key]) < 0 or (key == "percent" and float(commission[key]) > 100):
                    raise ValueError
            except (TypeError, ValueError):
                raise HTTPException(status_code=422, detail=f"commission.{key} must be a valid number") from None
    return data


def _with_postback(request: Request, partner: dict) -> dict:
    partner["postback_url"] = f"{_public_base(request)}/api/partners/{partner['slug']}/postback?token=<token>" \
                              "&click_id={sub_id}&order_id={order_id}&order_value={amount}&commission={payout}" \
                              "&status={status}"
    return partner


@admin_router.get("/partners/guide")
def admin_partner_guide(request: Request) -> dict:
    _require(request, "partners:view")
    return GUIDE


@admin_router.get("/partners")
def admin_partners(request: Request) -> dict:
    _require(request, "partners:view")
    items = [_with_postback(request, p) for p in partner_repo(request.app.state.container).partners()]
    return {"items": items, "secret_names": list(SECRET_NAMES)}


@admin_router.post("/partners")
def admin_create_partner(payload: PartnerPayload, request: Request) -> dict:
    principal = _require(request, "partners:manage")
    data = _checked(payload)
    if not str(data.get("name") or "").strip():
        raise HTTPException(status_code=422, detail="name is required")
    partner = partner_repo(request.app.state.container).create_partner(data)
    _audit(request, principal, "partner.create", f"partner:{partner['id']}", {"name": partner["name"]})
    return _with_postback(request, partner)


@admin_router.patch("/partners/{partner_id}")
def admin_update_partner(partner_id: int, payload: PartnerPayload, request: Request) -> dict:
    principal = _require(request, "partners:manage")
    partner = partner_repo(request.app.state.container).update_partner(partner_id, _checked(payload))
    if partner is None:
        raise HTTPException(status_code=404, detail="Partner not found")
    _audit(request, principal, "partner.update", f"partner:{partner_id}",
           {k: v for k, v in payload.model_dump(exclude_none=True).items() if k in {"active", "name"}})
    return _with_postback(request, partner)


class SecretPayload(BaseModel):
    value: str = Field(default="", max_length=600)


@admin_router.put("/partners/{partner_id}/secrets/{name}")
def admin_set_secret(partner_id: int, name: str, payload: SecretPayload, request: Request) -> dict:
    principal = _require(request, "partners:manage")
    repo = partner_repo(request.app.state.container)
    if repo.get_partner(partner_id) is None:
        raise HTTPException(status_code=404, detail="Partner not found")
    try:
        repo.set_secret(partner_id, name, payload.value.strip())
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    _audit(request, principal, "partner.secret", f"partner:{partner_id}", {"name": name, "set": bool(payload.value)})
    return {"name": name, "set": bool(payload.value.strip())}


@admin_router.post("/partners/{partner_id}/postback-token")
def admin_postback_token(partner_id: int, request: Request) -> dict:
    """Shown ONCE to the owner to paste into the partner's dashboard."""
    principal = _require(request, "partners:manage")
    repo = partner_repo(request.app.state.container)
    partner = repo.get_partner(partner_id)
    if partner is None:
        raise HTTPException(status_code=404, detail="Partner not found")
    token = repo.generate_postback_token(partner_id)
    _audit(request, principal, "partner.postback_token", f"partner:{partner_id}", {})
    return {"postback_url": _with_postback(request, partner)["postback_url"].replace("<token>", token),
            "note": "Copy this now -- the token is not shown again (generate a new one to rotate)."}


@admin_router.post("/partners/{partner_id}/test")
def admin_test_partner(partner_id: int, request: Request) -> dict:
    principal = _require(request, "partners:manage")
    repo = partner_repo(request.app.state.container)
    partner = repo.get_partner(partner_id)
    if partner is None:
        raise HTTPException(status_code=404, detail="Partner not found")
    report = partners_service.integration_test(repo, partner)
    _audit(request, principal, "partner.test", f"partner:{partner_id}", {"ok": report["ok"]})
    return report


class ImportPayload(BaseModel):
    csv: str = Field(min_length=10, max_length=2_000_000)


@admin_router.post("/partners/{partner_id}/import")
def admin_import(partner_id: int, payload: ImportPayload, request: Request) -> dict:
    principal = _require(request, "partners:manage")
    repo = partner_repo(request.app.state.container)
    partner = repo.get_partner(partner_id)
    if partner is None:
        raise HTTPException(status_code=404, detail="Partner not found")
    result = partners_service.import_report(repo, partner, payload.csv)
    _audit(request, principal, "partner.import", f"partner:{partner_id}", {"imported": result["imported"]})
    return result


class ConversionStatus(BaseModel):
    status: str


@admin_router.patch("/partners/conversions/{conversion_id}")
def admin_conversion_status(conversion_id: int, payload: ConversionStatus, request: Request) -> dict:
    principal = _require(request, "revenue:manage")
    try:
        conversion = partner_repo(request.app.state.container).set_conversion_status(conversion_id, payload.status)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    if conversion is None:
        raise HTTPException(status_code=404, detail="Conversion not found")
    _audit(request, principal, "conversion.status", f"conversion:{conversion_id}", {"status": conversion["status"]})
    return conversion


# ------------------------------------------------------- admin: revenue --

def _center(request: Request) -> RevenueCenter:
    container = request.app.state.container
    from app.api.routes.growth import growth

    return RevenueCenter(partner_repo(container), growth(container))


def _bounds(period: str, start: str, end: str, tz: str) -> dict:
    try:
        return period_bounds(period, tz=tz or "Asia/Kolkata", start=start, end=end)
    except (ValueError, KeyError) as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


def _filters(partner: str, category: str, location: str, campaign: str, language: str) -> dict:
    return {"partner": partner, "category": category, "location": location, "campaign": campaign,
            "language": language}


@admin_router.get("/revenue")
def admin_revenue(request: Request, period: str = "7d", start: str = "", end: str = "", tz: str = "Asia/Kolkata",
                  partner: str = "", category: str = "", location: str = "", campaign: str = "",
                  language: str = "") -> dict:
    _require(request, "revenue:view")
    return _center(request).summary(_bounds(period, start, end, tz),
                                    _filters(partner, category, location, campaign, language))


@admin_router.get("/revenue/why")
def admin_revenue_why(request: Request, period: str = "7d", start: str = "", end: str = "",
                      tz: str = "Asia/Kolkata", partner: str = "", category: str = "", location: str = "",
                      campaign: str = "", language: str = "") -> dict:
    _require(request, "revenue:view")
    return _center(request).explain(_bounds(period, start, end, tz),
                                    _filters(partner, category, location, campaign, language))


@admin_router.get("/revenue/records")
def admin_revenue_records(request: Request, kind: str = "conversions", period: str = "7d", start: str = "",
                          end: str = "", tz: str = "Asia/Kolkata", partner: str = "", category: str = "",
                          location: str = "", campaign: str = "", language: str = "") -> dict:
    _require(request, "revenue:view")
    try:
        items = _center(request).records(kind, _bounds(period, start, end, tz),
                                         _filters(partner, category, location, campaign, language))
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {"items": items}


@admin_router.get("/revenue/export.csv")
def admin_revenue_export(request: Request, kind: str = "daily", period: str = "7d", start: str = "",
                         end: str = "", tz: str = "Asia/Kolkata", partner: str = "", category: str = "",
                         location: str = "", campaign: str = "", language: str = "") -> PlainTextResponse:
    _require(request, "analytics:export")
    try:
        text = _center(request).export_csv(kind, _bounds(period, start, end, tz),
                                           _filters(partner, category, location, campaign, language))
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return PlainTextResponse(text, media_type="text/csv", headers={
        "Content-Disposition": f'attachment; filename="askodox-{kind}-{period}.csv"'})


class EntryPayload(BaseModel):
    source: str
    amount: float = Field(ge=-10_000_000, le=100_000_000)
    occurred_at: str | None = None
    currency: str = Field(default="INR", max_length=3)
    category: str = Field(default="", max_length=80)
    location: str = Field(default="", max_length=120)
    campaign: str = Field(default="", max_length=80)
    reference: str = Field(default="", max_length=120)
    note: str = Field(default="", max_length=300)


@admin_router.post("/revenue/entries")
def admin_revenue_entry(payload: EntryPayload, request: Request) -> dict:
    """A real revenue record from any source (e.g. a subscription paid
    offline, a lead fee, an ad booking). Never auto-generated."""
    principal = _require(request, "revenue:manage")
    if payload.source not in REVENUE_SOURCES:
        raise HTTPException(status_code=422, detail=f"source must be one of {', '.join(REVENUE_SOURCES)}")
    entry = partner_repo(request.app.state.container).add_entry(
        created_by=principal["id"], **payload.model_dump())
    _audit(request, principal, "revenue.entry", f"revenue_entry:{entry['id']}",
           {"source": entry["source"], "amount": entry["amount"]})
    return entry


@admin_router.get("/revenue/meta")
def admin_revenue_meta(request: Request) -> dict:
    _require(request, "revenue:view")
    return {"sources": list(REVENUE_SOURCES), "conversion_states": list(CONVERSION_STATES),
            "periods": ["today", "7d", "30d", "month", "custom"]}
