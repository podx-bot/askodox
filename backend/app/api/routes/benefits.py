"""Offers, coupons & rewards routes (Partner / Revenue architecture).

Customer:
  GET  /api/benefits/{id} ........... terms + conditions (records "offer_open")
  POST /api/benefits/{id}/claim ..... sign-in; issues a coupon / credit / cashback claim
  GET  /api/benefits/mine ........... my claims (codes only for my own claims)
  POST /api/rewards/scratch ......... sign-in; Scratch & Reveal after a REAL
                                      completed order of this customer; the
                                      reward is decided here (deterministic)
Admin (growth:view / growth:manage):
  /admin/cc/benefits[ /{id} | /import | /{id}/coupons | /claims/{id}/redeem | /analytics ]
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.repositories.benefits_repository import (
    FUNDING,
    OFFER_TYPES,
    SOURCE_KINDS,
    BenefitError,
    BenefitsRepository,
)
from app.services import benefits_engine

router = APIRouter(tags=["benefits"])
admin_router = APIRouter(prefix="/admin/cc/benefits", tags=["command-center"])

_EXTERNAL = {"bank_card", "upi_wallet", "merchant_brand", "affiliate_partner"}
_CREDIT_TYPES = {"askodox_credit", "referral_reward"}


def benefits_repo(container: Any) -> BenefitsRepository:
    repo = getattr(container, "benefits_repository", None)
    if repo is None:
        from app.services.secret_box import box_from_settings

        repo = BenefitsRepository(container.settings.database_path, secret_box=box_from_settings(container.settings))
        container.benefits_repository = repo
    return repo


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    from app.api.routes.partners import _audit as audit

    audit(request, principal, action, target, detail)


def _event(request: Request, event: str, campaign_id: int, **attrs: Any) -> None:
    try:
        from app.api.routes.partners import partner_repo

        partner_repo(request.app.state.container).record_event(event, campaign=f"benefit:{campaign_id}", **attrs)
    except Exception:
        pass


def _public(campaign: dict) -> dict:
    """What a customer may see (no budgets, no coupon codes, no internals)."""
    keys = ("id", "name", "provider_name", "offer_type", "description", "payment_methods", "min_purchase",
            "max_discount", "discount_amount", "discount_percent", "cashback_amount", "cashback_percent",
            "credit_amount", "free_benefit", "starts_at", "ends_at", "per_user_limit", "terms", "source_url",
            "verified_at", "funding_source")
    return {k: campaign.get(k) for k in keys}


def _user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


# ------------------------------------------------------------ customer --

@router.get("/api/benefits/mine")
def my_benefits(request: Request) -> dict:
    user = _user(request)
    repo = benefits_repo(request.app.state.container)
    items = []
    for claim in repo.claims_for(user):
        campaign = repo.campaign(claim["campaign_id"]) or {}
        items.append({"id": claim["id"], "status": claim["status"], "kind": claim["kind"], "value": claim["value"],
                      "code": claim["code"], "created_at": claim["created_at"], "campaign": _public(campaign)})
    return {"items": items}


@router.get("/api/benefits/{campaign_id}")
def benefit_detail(campaign_id: int, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "benefit_open", limit=60)
    campaign = benefits_repo(request.app.state.container).campaign(campaign_id)
    if campaign is None or not benefits_engine.live(campaign):
        raise HTTPException(status_code=404, detail="Offer not available")
    _event(request, "offer_open", campaign_id)
    return _public(campaign)


class ClaimRequest(BaseModel):
    order_value: float | None = Field(default=None, ge=0)


def _issue(request: Request, campaign: dict, user: str, *, trigger_ref: str, kind: str,
           price: float | None = None) -> dict:
    repo = benefits_repo(request.app.state.container)
    value = benefits_engine.benefit_value(campaign, price)
    try:
        claim = repo.issue(campaign, user, trigger_ref=trigger_ref, kind=kind, value=value)
    except BenefitError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    if not claim["duplicate"]:
        _event(request, "offer_claim", campaign["id"])
        credit = campaign["offer_type"] in _CREDIT_TYPES or (
            campaign["offer_type"] == "scratch_reward" and campaign.get("credit_amount") not in (None, ""))
        if credit and value:
            # ASKODOX credit is applied at once (it is ASKODOX's own ledger).
            from app.api.routes.growth import growth

            growth(request.app.state.container).add_credits(user, float(value), f"benefit:{campaign['id']}")
            repo.redeem(claim["id"], redemption_ref=f"credit:{claim['id']}", order_value=None,
                        benefit_value=float(value), funding_source=campaign.get("funding_source") or "askodox",
                        partner_share_percent=campaign.get("partner_share_percent"))
    code = next((c["code"] for c in repo.claims_for(user, campaign["id"]) if c["id"] == claim["id"]), None)
    fresh = repo.claim(claim["id"]) or claim
    return {"claim_id": claim["id"], "status": fresh["status"], "duplicate": claim["duplicate"], "code": code,
            "reward": {"name": campaign["name"], "type": campaign["offer_type"],
                       "kind": benefits_engine.KIND_BY_TYPE.get(campaign["offer_type"], "benefit"),
                       "value": value, "free_benefit": campaign.get("free_benefit"),
                       "expires_at": campaign.get("ends_at"), "terms": campaign.get("terms")}}


@router.post("/api/benefits/{campaign_id}/claim")
def claim_benefit(campaign_id: int, payload: ClaimRequest, request: Request) -> dict:
    user = _user(request)
    campaign = benefits_repo(request.app.state.container).campaign(campaign_id)
    if campaign is None or not benefits_engine.live(campaign) or campaign["offer_type"] == "scratch_reward":
        raise HTTPException(status_code=404, detail="Offer not available")
    if campaign["offer_type"] in _EXTERNAL:
        raise HTTPException(status_code=409, detail="This offer is applied by the bank/partner at payment")
    return _issue(request, campaign, user, trigger_ref="", kind="claim", price=payload.order_value)


class ScratchRequest(BaseModel):
    trigger: str = Field(min_length=3, max_length=80)


@router.post("/api/rewards/scratch")
def scratch(payload: ScratchRequest, request: Request) -> dict:
    """Scratch & Reveal. The trigger must be a real event of THIS customer
    (a completed order where they are the buyer). One reward per trigger;
    the reward is chosen here (highest-priority live scratch campaign) --
    nothing random, nothing the app can influence."""
    from app.services.deal_lifecycle import CLOSED, COMPLETION_STATES

    user = _user(request)
    container = request.app.state.container
    kind, _, ref = payload.trigger.partition(":")
    if kind != "order" or not ref.isdigit():
        raise HTTPException(status_code=422, detail="Unsupported reward trigger")
    order = container.order_repository.get(int(ref))
    if not order or str(order.get("buyer_user_id")) != user:
        raise HTTPException(status_code=404, detail="Order not found")
    if str(order.get("status")) not in {*COMPLETION_STATES, CLOSED}:
        raise HTTPException(status_code=409, detail="Rewards unlock after the order is completed")
    campaign = benefits_engine.scratch_reward(benefits_repo(container).campaigns(active_only=True),
                                              category=str(order.get("product_title") or ""))
    if campaign is None:
        return {"reward": None}
    return _issue(request, campaign, user, trigger_ref=payload.trigger, kind="scratch",
                  price=order.get("total_amount"))


# --------------------------------------------------------------- admin --

class CampaignPayload(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    partner_id: int | None = None
    provider_name: str | None = Field(default=None, max_length=120)
    offer_type: str | None = None
    description: str | None = Field(default=None, max_length=1000)
    categories: list[str] | None = None
    keywords: list[str] | None = None
    locations: list[str] | None = None
    countries: list[str] | None = None
    payment_methods: list[str] | None = None
    min_purchase: float | None = Field(default=None, ge=0)
    max_discount: float | None = Field(default=None, ge=0)
    discount_amount: float | None = Field(default=None, ge=0)
    discount_percent: float | None = Field(default=None, gt=0, le=100)
    cashback_amount: float | None = Field(default=None, ge=0)
    cashback_percent: float | None = Field(default=None, gt=0, le=100)
    credit_amount: float | None = Field(default=None, ge=0)
    free_benefit: str | None = Field(default=None, max_length=200)
    starts_at: str | None = None
    ends_at: str | None = None
    per_user_limit: int | None = Field(default=None, ge=1, le=1000)
    total_budget: float | None = Field(default=None, ge=0)
    total_cap: int | None = Field(default=None, ge=1)
    funding_source: str | None = None
    partner_share_percent: float | None = Field(default=None, ge=0, le=100)
    terms: str | None = Field(default=None, max_length=4000)
    source_url: str | None = Field(default=None, max_length=600)
    source_kind: str | None = None
    verified: bool | None = None
    active: bool | None = None
    priority: int | None = Field(default=None, ge=-100, le=100)
    tracking_params: dict[str, str] | None = None


def _checked(payload: CampaignPayload, *, creating: bool) -> dict:
    from datetime import datetime, timezone

    data = payload.model_dump(exclude_none=True)
    verified = data.pop("verified", None)
    if creating and not str(data.get("name") or "").strip():
        raise HTTPException(status_code=422, detail="name is required")
    if creating and data.get("offer_type") not in OFFER_TYPES:
        raise HTTPException(status_code=422, detail=f"offer_type must be one of {', '.join(OFFER_TYPES)}")
    if "offer_type" in data and data["offer_type"] not in OFFER_TYPES:
        raise HTTPException(status_code=422, detail="unknown offer_type")
    if "funding_source" in data and data["funding_source"] not in FUNDING:
        raise HTTPException(status_code=422, detail=f"funding_source must be one of {', '.join(FUNDING)}")
    if "source_kind" in data and data["source_kind"] not in SOURCE_KINDS:
        raise HTTPException(status_code=422, detail=f"source_kind must be one of {', '.join(SOURCE_KINDS)}")
    url = str(data.get("source_url") or "")
    if url and not url.startswith("https://"):
        raise HTTPException(status_code=422, detail="source_url must start with https://")
    if creating and data.get("offer_type") in _EXTERNAL and not url:
        raise HTTPException(status_code=422, detail="bank / UPI / merchant / partner offers need the source URL "
                                                    "where the offer is published")
    for key in ("starts_at", "ends_at"):
        if data.get(key):
            try:
                datetime.fromisoformat(str(data[key]).replace("Z", "+00:00"))
            except ValueError:
                raise HTTPException(status_code=422, detail=f"{key} must be an ISO date/time") from None
    if verified:
        data["verified_at"] = datetime.now(timezone.utc).isoformat()
    return data


@admin_router.get("")
def admin_campaigns(request: Request) -> dict:
    _require(request, "growth:view")
    return {"items": benefits_repo(request.app.state.container).campaigns(), "offer_types": list(OFFER_TYPES),
            "funding_sources": list(FUNDING), "source_kinds": list(SOURCE_KINDS)}


@admin_router.post("")
def admin_create_campaign(payload: CampaignPayload, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    campaign = benefits_repo(request.app.state.container).create_campaign(_checked(payload, creating=True))
    _audit(request, principal, "benefit.create", f"benefit:{campaign['id']}",
           {"name": campaign["name"], "type": campaign["offer_type"]})
    return campaign


class ImportPayload(BaseModel):
    campaigns: list[CampaignPayload] = Field(min_length=1, max_length=500)


@admin_router.post("/import")
def admin_import_campaigns(payload: ImportPayload, request: Request) -> dict:
    """Bulk import (e.g. from a partner's offer feed export). Each row is
    validated like a manual entry; invalid rows are reported, not guessed."""
    principal = _require(request, "growth:manage")
    repo = benefits_repo(request.app.state.container)
    created, errors = [], []
    for index, row in enumerate(payload.campaigns):
        try:
            created.append(repo.create_campaign(_checked(row, creating=True))["id"])
        except HTTPException as error:
            errors.append({"row": index + 1, "error": error.detail})
    _audit(request, principal, "benefit.import", "benefit:bulk", {"created": len(created), "errors": len(errors)})
    return {"created": created, "errors": errors}


@admin_router.patch("/{campaign_id}")
def admin_update_campaign(campaign_id: int, payload: CampaignPayload, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    repo = benefits_repo(request.app.state.container)
    if repo.campaign(campaign_id) is None:
        raise HTTPException(status_code=404, detail="Campaign not found")
    data = _checked(payload, creating=False)
    campaign = repo.update_campaign(campaign_id, data)
    _audit(request, principal, "benefit.update", f"benefit:{campaign_id}", {"changed_fields": sorted(data)})
    return campaign


class CouponsPayload(BaseModel):
    codes: list[str] = Field(min_length=1, max_length=10000)


@admin_router.post("/{campaign_id}/coupons")
def admin_add_coupons(campaign_id: int, payload: CouponsPayload, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    repo = benefits_repo(request.app.state.container)
    if repo.campaign(campaign_id) is None:
        raise HTTPException(status_code=404, detail="Campaign not found")
    result = repo.add_coupons(campaign_id, payload.codes)
    _audit(request, principal, "benefit.coupons", f"benefit:{campaign_id}", result)
    return result


class RedeemPayload(BaseModel):
    redemption_ref: str = Field(min_length=2, max_length=120)
    order_value: float | None = Field(default=None, ge=0)


@admin_router.post("/claims/{claim_id}/redeem")
def admin_redeem(claim_id: int, payload: RedeemPayload, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    result = redeem_claim(request.app.state.container, claim_id, payload.redemption_ref, payload.order_value)
    _audit(request, principal, "benefit.redeem", f"benefit_claim:{claim_id}", {"ref": payload.redemption_ref})
    return result


def redeem_claim(container: Any, claim_id: int, redemption_ref: str, order_value: float | None) -> dict:
    repo = benefits_repo(container)
    claim = repo.claim(claim_id)
    if claim is None:
        raise HTTPException(status_code=404, detail="Claim not found")
    campaign = repo.campaign(claim["campaign_id"]) or {}
    value = benefits_engine.benefit_value(campaign, order_value)
    if value is None:
        value = float(claim.get("value") or 0)
    try:
        return repo.redeem(claim_id, redemption_ref=redemption_ref, order_value=order_value, benefit_value=value,
                           funding_source=campaign.get("funding_source") or "askodox",
                           partner_share_percent=campaign.get("partner_share_percent"))
    except BenefitError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error


@admin_router.get("/analytics")
def admin_benefit_analytics(request: Request, period: str = "30d", start: str = "", end: str = "",
                            tz: str = "Asia/Kolkata") -> dict:
    _require(request, "growth:view")
    from app.api.routes.partners import _bounds, partner_repo

    bounds = _bounds(period, start, end, tz)
    container = request.app.state.container
    return benefit_analytics(benefits_repo(container), partner_repo(container), bounds)


def benefit_analytics(repo: BenefitsRepository, partners: Any, bounds: dict) -> dict:
    """Per campaign: impressions, opens, claims, redemptions, reward cost
    (ASKODOX / partner), order value of redemptions, ROI where measurable."""
    campaigns = {c["id"]: c for c in repo.campaigns()}
    rows: dict[int, dict] = {cid: {"campaign_id": cid, "name": c["name"], "type": c["offer_type"],
                                   "funding": c["funding_source"], "impressions": 0, "opens": 0, "claims": 0,
                                   "redemptions": 0, "askodox_cost": 0.0, "partner_cost": 0.0, "order_value": 0.0}
                             for cid, c in campaigns.items()}
    for event in partners.events_between(bounds["start"], bounds["end"]):
        campaign = str(event.get("campaign") or "")
        if not campaign.startswith("benefit:") or not campaign[8:].isdigit():
            continue
        row = rows.get(int(campaign[8:]))
        if row is None:
            continue
        key = {"offer_impression": "impressions", "offer_open": "opens"}.get(event["event"])
        if key:
            row[key] += event.get("count", 1)
    for claim in repo.claims_between(bounds["start"], bounds["end"]):
        row = rows.get(claim["campaign_id"])
        if row is None:
            continue
        if bounds["start"] <= claim["created_at"] < bounds["end"]:
            row["claims"] += 1
        if claim["status"] == "REDEEMED" and claim["redeemed_at"] and bounds["start"] <= claim["redeemed_at"] < bounds["end"]:
            row["redemptions"] += 1
            row["askodox_cost"] += float(claim["askodox_cost"] or 0)
            row["partner_cost"] += float(claim["partner_cost"] or 0)
            row["order_value"] += float(claim["order_value"] or 0)
    items = []
    for row in rows.values():
        # ROI only where ASKODOX paid something and revenue can be tied to it
        # (redeemed order value is GMV, not ASKODOX revenue -> not ROI).
        row["roi"] = None
        row["roi_note"] = "not measurable: no revenue is attributed to this campaign yet" if row["askodox_cost"] else ""
        items.append({k: (round(v, 2) if isinstance(v, float) else v) for k, v in row.items()})
    totals = {k: round(sum(r[k] for r in items), 2) for k in
              ("impressions", "opens", "claims", "redemptions", "askodox_cost", "partner_cost", "order_value")}
    return {"period": bounds, "items": sorted(items, key=lambda r: -r["claims"]), "totals": totals}
