"""Sponsored content for Discover surfaces."""
from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from app.core.sponsored_items import sponsored_items_for

router = APIRouter(prefix="/api/discover", tags=["discover"])


class SponsoredItem(BaseModel):
    id: str
    title: str
    subtitle: str = ""
    image_url: str = ""
    cta_type: str = "shop"
    cta_target: str = ""


class SponsoredResponse(BaseModel):
    items: list[SponsoredItem]


@router.get("/sponsored", response_model=SponsoredResponse)
def get_sponsored(placement: str = "explore_top") -> SponsoredResponse:
    return SponsoredResponse(
        items=[
            SponsoredItem(
                id=str(item["id"]),
                title=str(item["title"]),
                subtitle=str(item.get("subtitle", "") or ""),
                image_url=str(item.get("image_url", "") or ""),
                cta_type=str(item.get("cta_type", "shop") or "shop"),
                cta_target=str(item.get("cta_target", "") or ""),
            )
            for item in sponsored_items_for(placement)
        ]
    )
