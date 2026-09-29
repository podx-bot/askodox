"""Sponsored listings / advertisers / campaigns.

Public:
  GET /go/sp/{click_id} ........... tracked redirect for a shown sponsored
                                    result (only the campaign's stored https
                                    URL, first open counted once)
Admin (Command Center; sponsored:view | sponsored:manage):
  GET   /admin/cc/sponsored ........................ advertisers + campaigns + stats
  POST  /admin/cc/sponsored/advertisers ............ create advertiser
  PATCH /admin/cc/sponsored/advertisers/{id} ....... edit / enable / disable
  POST  /admin/cc/sponsored/campaigns .............. create campaign (DRAFT)
  PATCH /admin/cc/sponsored/campaigns/{id} ......... edit (content change -> DRAFT)
  POST  /admin/cc/sponsored/campaigns/{id}/status .. approve / pause / disable
  POST  /admin/cc/sponsored/campaigns/{id}/conversions  record a real conversion
  GET   /admin/cc/sponsored/analytics?days=30 ...... totals, per campaign,
                                                   organic vs sponsored
Nothing here is pre-filled: with no advertiser / campaign configured, no
sponsored result is ever served.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import BaseModel

from app.repositories.sponsored_repository import (
    ADVERTISER_KINDS,
    CAMPAIGN_KINDS,
    LABELS,
    PLACEMENTS,
    STATUSES,
    SponsoredError,
    SponsoredRepository,
)

router = APIRouter(tags=["sponsored"])
admin_router = APIRouter(prefix="/admin/cc/sponsored", tags=["command-center"])


def sponsored_repo(container: Any) -> SponsoredRepository:
    repo = getattr(container, "sponsored_repository", None)
    if repo is None:
        repo = SponsoredRepository(container.settings.database_path)
        container.sponsored_repository = repo
    return repo


def sponsored_results(container: Any, demand: dict, *, limit: int = 2) -> list[dict]:
    """Result rows for the discovery pipeline: approved, targeted, in window,
    under budget; each row carries sponsored=true and its disclosure label and
    opens through the tracked /go/sp/ redirect."""
    if str(demand.get("side") or "").upper() == "OFFER":
        return []  # a seller / provider listing their own supply sees no ads
    repo = sponsored_repo(container)
    category = str(demand.get("domain") or "").strip().lower()
    location = str(demand.get("location_text") or "")
    rows: list[dict] = []
    for campaign in repo.eligible(category=category, subject=str(demand.get("subject") or ""),
                                  location=location, limit=limit):
        click_id = repo.record_impression(int(campaign["id"]), category=category, location=location)
        rows.append({
            "id": f"sponsored-{campaign['id']}",
            "title": campaign["title"],
            "subtitle": campaign.get("subtitle") or "",
            "image_url": campaign.get("image_url") or None,
            "destination_url": campaign["destination_url"],
            "redirect_path": f"/go/sp/{click_id}",
            "click_id": click_id,
            "source": "sponsored",
            "match_source": "sponsored",
            "segment": "sponsored",
            "sponsored": True,
            "sponsored_label": campaign.get("label") or "Sponsored",
            "sponsored_kind": campaign.get("kind"),
            "disclosure": f"{campaign.get('label') or 'Sponsored'} -- a paid placement, shown separately "
                          f"from ASKODOX's own ranking.",
            "price_verified": False,
        })
    return rows


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict | None = None) -> None:
    from app.api.routes.partners import _audit as audit

    audit(request, principal, action, target, detail)


# ------------------------------------------------------------- public --

@router.get("/go/sp/{click_id}", include_in_schema=False)
def sponsored_redirect(click_id: str, request: Request) -> RedirectResponse:
    from app.services import rate_limit

    rate_limit.check(request, "sponsored_go", limit=60)
    url = sponsored_repo(request.app.state.container).open_click(click_id)
    if not url:
        raise HTTPException(status_code=404, detail="Link expired or unknown")
    return RedirectResponse(url, status_code=302)


# -------------------------------------------------------------- admin --

class StatusBody(BaseModel):
    status: str


class ConversionBody(BaseModel):
    amount: float | None = None
    note: str = ""


@admin_router.get("")
def overview(request: Request) -> dict:
    _require(request, "sponsored:view")
    repo = sponsored_repo(request.app.state.container)
    return {
        "advertisers": repo.advertisers(),
        "campaigns": repo.campaigns(),
        "advertiser_kinds": list(ADVERTISER_KINDS),
        "campaign_kinds": list(CAMPAIGN_KINDS),
        "statuses": list(STATUSES),
        "labels": list(LABELS),
        "placements": list(PLACEMENTS),
    }


@admin_router.post("/advertisers")
def create_advertiser(body: dict, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        item = sponsored_repo(request.app.state.container).save_advertiser(body)
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, "sponsored.advertiser.create", f"sponsored_advertiser:{item['id']}", {"name": item["name"]})
    return item


@admin_router.patch("/advertisers/{advertiser_id}")
def update_advertiser(advertiser_id: int, body: dict, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        item = sponsored_repo(request.app.state.container).save_advertiser(body, advertiser_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Advertiser not found") from None
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, "sponsored.advertiser.update", f"sponsored_advertiser:{advertiser_id}", body)
    return item


@admin_router.post("/campaigns")
def create_campaign(body: dict, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        item = sponsored_repo(request.app.state.container).save_campaign(body)
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, "sponsored.campaign.create", f"sponsored_campaign:{item['id']}", {"name": item["name"]})
    return item


@admin_router.patch("/campaigns/{campaign_id}")
def update_campaign(campaign_id: int, body: dict, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        item = sponsored_repo(request.app.state.container).save_campaign(body, campaign_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="Campaign not found") from None
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, "sponsored.campaign.update", f"sponsored_campaign:{campaign_id}", body)
    return item


@admin_router.post("/campaigns/{campaign_id}/status")
def campaign_status(campaign_id: int, body: StatusBody, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        item = sponsored_repo(request.app.state.container).set_status(
            campaign_id, body.status, actor=str(principal.get("id") or ""))
    except KeyError:
        raise HTTPException(status_code=404, detail="Campaign not found") from None
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, f"sponsored.campaign.{item.get('status', '').lower()}",
           f"sponsored_campaign:{campaign_id}", {"status": item.get("status")})
    return item


@admin_router.post("/campaigns/{campaign_id}/conversions")
def campaign_conversion(campaign_id: int, body: ConversionBody, request: Request) -> dict:
    principal = _require(request, "sponsored:manage")
    try:
        stats = sponsored_repo(request.app.state.container).record_conversion(
            campaign_id, amount=body.amount, note=body.note)
    except KeyError:
        raise HTTPException(status_code=404, detail="Campaign not found") from None
    except SponsoredError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None
    _audit(request, principal, "sponsored.conversion.record", f"sponsored_campaign:{campaign_id}",
           {"amount": body.amount, "note": body.note})
    return stats


@admin_router.get("/analytics")
def analytics(request: Request, days: int = 30) -> dict:
    _require(request, "sponsored:view")
    return sponsored_repo(request.app.state.container).analytics(days)
