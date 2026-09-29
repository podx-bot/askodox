"""Growth engines over the ONE universal marketplace (no separate apps):

Customers / sellers / participants (token-proven identity):
  offers ........ POST /api/offers, GET /api/offers/mine, PATCH /api/offers/{id},
                  GET /api/offers/listing/{product_id} (public)
  referrals ..... POST /api/referrals, GET /api/referrals/mine,
                  POST /api/referrals/{code}/redeem
  rewards ....... GET /api/rewards/mine
  plans ......... GET /api/plans (public), POST /api/subscriptions,
                  GET /api/subscriptions/me
  catalog AI .... POST /api/catalog/drafts, GET /api/catalog/drafts/mine,
                  POST /api/catalog/drafts/{id}/publish | /discard

Admin (Command Center permissions growth:view / growth:manage):
  /admin/cc/growth/{offers,reward-rules,rewards,referrals,plans,
  subscriptions,credits,catalog-drafts}
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.repositories.command_center_repository import mask_user_id
from app.repositories.growth_repository import (
    PARTICIPANT_ROLES,
    REWARD_STATES,
    GrowthRepository,
)
from app.services import offers_engine
from app.services.catalog_drafter import build_draft

router = APIRouter(tags=["growth"])
admin_router = APIRouter(prefix="/admin/cc/growth", tags=["command-center"])


def growth(container: Any) -> GrowthRepository:
    repo = getattr(container, "growth_repository", None)
    if repo is None:
        repo = GrowthRepository(container.settings.database_path)
        container.growth_repository = repo
    return repo


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    try:
        from app.api.routes.command_center import command_center

        entity_type, _, entity_id = target.partition(":")
        command_center(request.app.state.container).audit(principal["id"], action, entity_type, entity_id,
                                                          after=detail or {})
    except Exception:
        pass


# ------------------------------------------------------------------ offers --

class OfferRequest(BaseModel):
    rule_type: str
    params: dict[str, Any] = Field(default_factory=dict)
    title: str = Field(default="", max_length=120)
    scope: str = "all"  # all | listing | category
    scope_value: str | None = Field(default=None, max_length=120)
    starts_at: str | None = None
    ends_at: str | None = None


def _checked_offer(payload: OfferRequest) -> dict[str, Any]:
    try:
        params = offers_engine.validate(payload.rule_type, payload.params)
    except offers_engine.OfferError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    if payload.scope not in {"all", "listing", "category"}:
        raise HTTPException(status_code=422, detail="scope must be all, listing or category")
    if payload.scope != "all" and not (payload.scope_value or "").strip():
        raise HTTPException(status_code=422, detail="scope_value required for a listing/category offer")
    return params


@router.post("/api/offers")
def create_offer(payload: OfferRequest, request: Request) -> dict:
    """A seller/provider offer on their own shop, listing or category."""
    container = request.app.state.container
    seller = _authenticated_app_user(request)
    params = _checked_offer(payload)
    if payload.scope == "listing":
        listing = container.product_catalog_repository.get(int(payload.scope_value or 0)) \
            if str(payload.scope_value or "").isdigit() else None
        if not listing or str(listing.get("seller_user_id")) != seller:
            raise HTTPException(status_code=403, detail="You can only create offers on your own listings")
    return growth(container).create_offer(
        owner_type="seller", owner_id=seller, rule_type=payload.rule_type.lower(), params=params,
        title=payload.title.strip(), scope=payload.scope, scope_value=payload.scope_value,
        starts_at=payload.starts_at, ends_at=payload.ends_at,
    )


@router.get("/api/offers/mine")
def my_offers(request: Request) -> dict:
    seller = _authenticated_app_user(request)
    return {"items": growth(request.app.state.container).offers(owner_type="seller", owner_id=seller)}


class OfferToggle(BaseModel):
    active: bool


@router.patch("/api/offers/{offer_id}")
def toggle_my_offer(offer_id: int, payload: OfferToggle, request: Request) -> dict:
    seller = _authenticated_app_user(request)
    repo = growth(request.app.state.container)
    offer = repo.get_offer(offer_id)
    if not offer or offer["owner_type"] != "seller" or offer["owner_id"] != seller:
        raise HTTPException(status_code=404, detail="Offer not found")
    repo.set_offer_active(offer_id, payload.active)
    return repo.get_offer(offer_id) or {}


@router.get("/api/offers/listing/{product_id}")
def listing_offers(product_id: int, request: Request, quantity: float = 1) -> dict:
    """Public: offers that apply to a listing, with the best one computed
    for this quantity from the listing's real price."""
    container = request.app.state.container
    listing = container.product_catalog_repository.get(product_id)
    if not listing:
        raise HTTPException(status_code=404, detail="Listing not found")
    offers = growth(container).offers_for_listing(listing)
    best = offers_engine.best_offer(offers, {"unit_price": listing.get("price") or 0, "quantity": quantity})
    return {"offers": [{"id": o["id"], "title": o["title"], "rule_type": o["rule_type"]} for o in offers],
            "best": best}


# ---------------------------------------------------------------- referrals --

def redeem_referral_safely(container: Any, code: str, user: str) -> dict | None:
    """Every referral redemption path: a referrer blocked in the Command
    Center earns nothing; the repository refuses self, repeat and circular
    referrals."""
    from app.api.routes.platform import is_blocked_user

    pending = growth(container).referral(code)
    if not pending or is_blocked_user(container, pending["referrer_user_id"]):
        return None
    return growth(container).redeem_referral(code, user)


class ReferralRequest(BaseModel):
    invitee_name: str = Field(default="", max_length=80)
    category: str = Field(default="", max_length=80)
    area: str = Field(default="", max_length=80)
    deal_id: str | None = Field(default=None, max_length=40)


@router.post("/api/referrals")
def create_referral(payload: ReferralRequest, request: Request) -> dict:
    """"Know someone who does this? Refer them to ASKODOX." A code the
    invitee uses when they list; the referrer is credited transparently."""
    user = _authenticated_app_user(request)
    try:
        ref = growth(request.app.state.container).create_referral(
            user, invitee_name=payload.invitee_name.strip(), category=payload.category.strip(),
            area=payload.area.strip(), deal_id=payload.deal_id,
        )
    except ValueError:
        raise HTTPException(status_code=429, detail="Daily referral limit reached. Try again tomorrow.") from None
    what = payload.category.strip() or "your service"
    where = f" in {payload.area.strip()}" if payload.area.strip() else ""
    share = (f"Customers are looking for {what}{where} on ASKODOX. Join free to get direct local leads, "
             f"your own profile and repeat customers. Use code {ref['code']} when you list.")
    return {"code": ref["code"], "status": ref["status"], "share_text": share}


@router.get("/api/referrals/mine")
def my_referrals(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"items": growth(request.app.state.container).referrals(referrer_user_id=user)}


@router.post("/api/referrals/{code}/redeem")
def redeem_referral(code: str, request: Request) -> dict:
    """The invitee registered on ASKODOX with the code."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    ref = redeem_referral_safely(container, code, user)
    if not ref:
        raise HTTPException(status_code=404, detail="Invalid or already-used referral code")
    growth(container).add_participant("referral", ref["id"], ref["referrer_user_id"], "referrer", added_by=user)
    return {"code": ref["code"], "status": ref["status"]}


@router.get("/api/rewards/mine")
def my_rewards(request: Request) -> dict:
    user = _authenticated_app_user(request)
    items = growth(request.app.state.container).rewards(user_id=user)
    return {"items": items, "pending_total": round(sum(r["amount"] for r in items if r["status"] == "PENDING"), 2),
            "paid_total": round(sum(r["amount"] for r in items if r["status"] == "PAID"), 2)}


# ---------------------------------------------------- plans / subscriptions --

@router.get("/api/plans")
def list_plans(request: Request, audience: str = "") -> dict:
    return {"items": growth(request.app.state.container).plans(active_only=True, audience=audience or None)}


class SubscribeRequest(BaseModel):
    plan_code: str = Field(min_length=1, max_length=40)


@router.post("/api/subscriptions")
def subscribe(payload: SubscribeRequest, request: Request) -> dict:
    user = _authenticated_app_user(request)
    repo = growth(request.app.state.container)
    plan = repo.plan(payload.plan_code)
    if not plan or not plan["active"]:
        raise HTTPException(status_code=404, detail="Plan not available")
    sub = repo.subscribe(user, plan)
    note = ("Payment is not available in the app yet; this plan starts after payment is confirmed."
            if sub["status"] == "PENDING_PAYMENT" else "")
    return {"subscription": sub, "entitlements": repo.entitlements(user), "note": note}


@router.get("/api/subscriptions/me")
def my_subscription(request: Request) -> dict:
    user = _authenticated_app_user(request)
    repo = growth(request.app.state.container)
    return {"subscription": repo.current_subscription(user), **repo.entitlements(user)}


# --------------------------------------------------------------- catalog AI --

class DraftRequest(BaseModel):
    text: str = Field(default="", max_length=4000)
    image_analysis: dict[str, Any] | None = None
    video_analysis: dict[str, Any] | None = None
    media_refs: list[str] = Field(default_factory=list)


@router.post("/api/catalog/drafts")
def create_draft(payload: DraftRequest, request: Request) -> dict:
    seller = _authenticated_app_user(request)
    if not (payload.text.strip() or payload.image_analysis or payload.video_analysis):
        raise HTTPException(status_code=422, detail="Describe the item or add a photo/video")
    container = request.app.state.container
    draft, missing, source = build_draft(
        text=payload.text, image_analysis=payload.image_analysis, video_analysis=payload.video_analysis,
        assistant=getattr(container, "seller_listing_assistant", None), media_refs=payload.media_refs[:10],
    )
    if not draft.get("subject"):
        raise HTTPException(status_code=422, detail="Could not identify the product or service; add a short description")
    return growth(container).save_draft(seller, draft, missing, source)


@router.get("/api/catalog/drafts/mine")
def my_drafts(request: Request) -> dict:
    seller = _authenticated_app_user(request)
    return {"items": growth(request.app.state.container).drafts(seller_user_id=seller)}


class PublishRequest(BaseModel):
    """The seller's reviewed values; anything not given stays as drafted."""
    subject: str | None = Field(default=None, max_length=200)
    price: float | None = Field(default=None, gt=0)
    unit: str | None = None
    stock_status: str | None = None
    location_label: str | None = None
    variant: str | None = None
    category_tag: str | None = None
    referral_code: str | None = Field(default=None, max_length=20)


def _own_draft(request: Request, draft_id: int) -> tuple[str, dict]:
    seller = _authenticated_app_user(request)
    draft = growth(request.app.state.container).draft(draft_id)
    if not draft or draft["seller_user_id"] != seller:
        raise HTTPException(status_code=404, detail="Draft not found")
    if draft["status"] != "DRAFT":
        raise HTTPException(status_code=409, detail=f"Draft already {draft['status'].lower()}")
    return seller, draft


@router.post("/api/catalog/drafts/{draft_id}/publish")
def publish_draft(draft_id: int, payload: PublishRequest, request: Request) -> dict:
    """Seller reviewed -> the SAME listing creation as "list my product"."""
    from app.api.routes.product_catalog_self_service import CreateMyListingRequest, create_my_listing

    seller, draft = _own_draft(request, draft_id)
    d = draft["draft"]
    attrs = d.get("attributes") or {}
    variant = payload.variant or ", ".join(f"{k} {v}" for k, v in attrs.items() if k in {"brand", "model", "color", "size"})
    listing = create_my_listing(CreateMyListingRequest(
        seller_user_id=seller,
        subject=(payload.subject or d.get("title") or d.get("subject") or "").strip(),
        variant=variant or None,
        price=payload.price or d.get("price"),
        unit=payload.unit or d.get("unit"),
        stock_status=(payload.stock_status or "UNKNOWN"),
        location_label=payload.location_label,
        category_tag=payload.category_tag or d.get("category_tag"),
    ), request)
    container = request.app.state.container
    growth(container).mark_draft(draft_id, "PUBLISHED", product_id=listing.id)
    if payload.referral_code:
        ref = redeem_referral_safely(container, payload.referral_code, seller)
        if ref:
            growth(container).add_participant("referral", ref["id"], ref["referrer_user_id"], "referrer",
                                              added_by=seller)
    return {"draft_id": draft_id, "status": "PUBLISHED", "listing_id": listing.id, "seller_tier": listing.seller_tier}


@router.post("/api/catalog/drafts/{draft_id}/discard")
def discard_draft(draft_id: int, request: Request) -> dict:
    _own_draft(request, draft_id)
    growth(request.app.state.container).mark_draft(draft_id, "DISCARDED")
    return {"draft_id": draft_id, "status": "DISCARDED"}


# ==================================================================== admin --

def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


@admin_router.get("/offers")
def admin_offers(request: Request) -> dict:
    _require(request, "growth:view")
    items = growth(request.app.state.container).offers()
    for item in items:
        if item["owner_type"] == "seller":
            item["owner_id"] = mask_user_id(item["owner_id"])
    return {"items": items, "rule_types": list(offers_engine.RULE_TYPES)}


@admin_router.post("/offers")
def admin_create_offer(payload: OfferRequest, request: Request) -> dict:
    """Admin campaigns: festival, joining bonus, free delivery, coupons..."""
    principal = _require(request, "growth:manage")
    params = _checked_offer(payload)
    offer = growth(request.app.state.container).create_offer(
        owner_type="admin", owner_id=principal["id"], rule_type=payload.rule_type.lower(), params=params,
        title=payload.title.strip(), scope=payload.scope, scope_value=payload.scope_value,
        starts_at=payload.starts_at, ends_at=payload.ends_at,
    )
    _audit(request, principal, "offer.create", f"offer:{offer['id']}", {"rule_type": offer["rule_type"]})
    return offer


@admin_router.patch("/offers/{offer_id}")
def admin_toggle_offer(offer_id: int, payload: OfferToggle, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    repo = growth(request.app.state.container)
    if not repo.set_offer_active(offer_id, payload.active):
        raise HTTPException(status_code=404, detail="Offer not found")
    _audit(request, principal, "offer.toggle", f"offer:{offer_id}", {"active": payload.active})
    return repo.get_offer(offer_id) or {}


class RewardRule(BaseModel):
    percent: float | None = Field(default=None, ge=0, le=50)
    amount: float | None = Field(default=None, ge=0)
    active: bool = True


@admin_router.get("/reward-rules")
def admin_reward_rules(request: Request) -> dict:
    _require(request, "growth:view")
    from app.repositories.growth_repository import REWARDABLE_ROLES

    return {"items": growth(request.app.state.container).reward_rules(), "roles": list(REWARDABLE_ROLES)}


@admin_router.put("/reward-rules/{role}")
def admin_set_reward_rule(role: str, payload: RewardRule, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    from app.repositories.growth_repository import REWARDABLE_ROLES

    if role not in REWARDABLE_ROLES:
        raise HTTPException(status_code=422, detail=f"role must be one of {', '.join(REWARDABLE_ROLES)}")
    growth(request.app.state.container).set_reward_rule(role, percent=payload.percent, amount=payload.amount,
                                                        active=payload.active)
    _audit(request, principal, "reward_rule.set", f"role:{role}", payload.model_dump())
    return {"role": role, **payload.model_dump()}


@admin_router.get("/rewards")
def admin_rewards(request: Request, status: str = "") -> dict:
    _require(request, "growth:view")
    items = growth(request.app.state.container).rewards(status=status.upper() or None)
    for item in items:
        item["participant_user_id"] = mask_user_id(item["participant_user_id"])
    return {"items": items, "statuses": list(REWARD_STATES)}


class RewardDecision(BaseModel):
    status: str
    note: str = Field(default="", max_length=300)


@admin_router.patch("/rewards/{reward_id}")
def admin_reward_status(reward_id: int, payload: RewardDecision, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    try:
        reward = growth(request.app.state.container).set_reward_status(reward_id, payload.status, payload.note)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Reward not found") from error
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    _audit(request, principal, "reward.status", f"reward:{reward_id}", {"status": reward["status"]})
    reward["participant_user_id"] = mask_user_id(reward["participant_user_id"])
    return reward


@admin_router.get("/referrals")
def admin_referrals(request: Request) -> dict:
    _require(request, "growth:view")
    repo = growth(request.app.state.container)
    items = repo.referrals()
    flags = repo.referral_review_flags()
    for item in items:
        item["review"] = flags.get(item["referrer_user_id"])
        item["referrer_user_id"] = mask_user_id(item["referrer_user_id"])
        if item.get("registered_user_id"):
            item["registered_user_id"] = mask_user_id(item["registered_user_id"])
    return {"items": items}


class PlanRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    audience: str = "any"  # any | buyer | seller | service_provider | partner | influencer
    price: float = Field(default=0, ge=0)
    period_days: int = Field(default=30, ge=1, le=366)
    trial_days: int = Field(default=0, ge=0, le=90)
    credits: float = Field(default=0, ge=0)
    entitlements: dict[str, Any] = Field(default_factory=dict)
    active: bool = True


@admin_router.get("/plans")
def admin_plans(request: Request) -> dict:
    _require(request, "growth:view")
    return {"items": growth(request.app.state.container).plans()}


@admin_router.put("/plans/{code}")
def admin_upsert_plan(code: str, payload: PlanRequest, request: Request) -> dict:
    """Plans, trials and promotional credits are configured here -- never
    hard-coded prices in business logic."""
    principal = _require(request, "growth:manage")
    code = code.strip().lower()
    if not code.replace("_", "").replace("-", "").isalnum():
        raise HTTPException(status_code=422, detail="plan code must be letters, digits, - or _")
    plan = growth(request.app.state.container).upsert_plan(code, **payload.model_dump())
    _audit(request, principal, "plan.upsert", f"plan:{code}", {"price": plan["price"], "active": plan["active"]})
    return plan


@admin_router.get("/subscriptions")
def admin_subscriptions(request: Request) -> dict:
    _require(request, "growth:view")
    items = growth(request.app.state.container).subscriptions()
    for item in items:
        item["user_id"] = mask_user_id(item["user_id"])
    return {"items": items}


class CreditGrant(BaseModel):
    user_id: str = Field(min_length=4, max_length=80)
    amount: float
    reason: str = Field(min_length=3, max_length=120)


@admin_router.post("/credits")
def admin_grant_credits(payload: CreditGrant, request: Request) -> dict:
    """Joining bonus / promotional credits (audited)."""
    principal = _require(request, "growth:manage")
    balance = growth(request.app.state.container).add_credits(payload.user_id, payload.amount,
                                                              f"admin:{payload.reason}")
    _audit(request, principal, "credits.grant", f"user:{mask_user_id(payload.user_id)}",
           {"amount": payload.amount, "reason": payload.reason})
    return {"user": mask_user_id(payload.user_id), "balance": balance}


@admin_router.get("/catalog-drafts")
def admin_catalog_drafts(request: Request) -> dict:
    _require(request, "growth:view")
    items = growth(request.app.state.container).drafts()
    return {"items": [{"id": d["id"], "seller": mask_user_id(d["seller_user_id"]), "status": d["status"],
                       "source": d["source"], "title": d["draft"].get("title"), "missing": d["missing"],
                       "product_id": d["product_id"], "created_at": d["created_at"]} for d in items]}


@admin_router.get("/participant-roles")
def admin_participant_roles(request: Request) -> dict:
    _require(request, "growth:view")
    return {"roles": list(PARTICIPANT_ROLES)}
