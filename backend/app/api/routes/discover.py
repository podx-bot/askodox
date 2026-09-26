"""Sponsored content for Discover surfaces."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
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


class ExploreItem(BaseModel):
    id: str
    title: str
    subtitle: str = ""
    price: float | None = None
    segment: str
    source: str
    prompt: str
    destination_url: str | None = None
    distance_km: float | None = None


class ExploreResponse(BaseModel):
    items: list[ExploreItem]


@router.get("/explore", response_model=ExploreResponse)
def explore_feed(
    request: Request,
    latitude: float | None = None,
    longitude: float | None = None,
    location: str = "",
    limit: int = 20,
) -> ExploreResponse:
    """Real Explore discovery (2026-09-26): newest registered ASKODOX listings,
    classified into registered / individual / used / surplus / deals, plus
    nearby offline businesses when Maps is configured. Every item carries a
    chat ``prompt`` -- selecting it continues in the same ASKODOX chat."""
    from app.api.routes.product_search import _subtitle, _title
    from app.services.universal_multi_source_result_service import listing_segment

    container: Any = request.app.state.container
    catalog = container.product_catalog_repository
    profiles = getattr(container, "seller_profile_repository", None)
    near = f" in {location.strip()}" if location.strip() else ""
    items: list[ExploreItem] = []
    for row in catalog.list_recent_active(limit=max(1, min(limit, 50))):
        tier = None
        if profiles is not None and row.get("seller_user_id"):
            try:
                tier = (profiles.get(str(row["seller_user_id"])) or {}).get("tier")
            except Exception:
                tier = None
        title = _title(row)
        items.append(ExploreItem(
            id=str(row["id"]),
            title=title,
            subtitle=_subtitle(row),
            price=float(row["price"]) if row.get("price") is not None else None,
            segment=listing_segment(row, tier),
            source="local",
            prompt=f"I want to buy {title}{near}",
        ))
    maps = getattr(container, "google_maps_service", None)
    if maps is not None and getattr(maps, "enabled", False) and latitude is not None and longitude is not None:
        for index, place in enumerate(maps.search_places("shops", latitude=latitude, longitude=longitude, limit=6)):
            items.append(ExploreItem(
                id=f"external-{place.get('place_id') or index}",
                title=str(place.get("name")),
                subtitle=str(place.get("address") or ""),
                segment="nearby_external",
                source="external",
                prompt=f"What can I get at {place.get('name')}{near}?",
                destination_url=place.get("maps_url") or None,
            ))
    return ExploreResponse(items=items)
