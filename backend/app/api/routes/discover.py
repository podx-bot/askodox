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


@router.get("/place")
def resolve_place(request: Request, latitude: float, longitude: float) -> dict[str, Any]:
    """Readable place for the customer's GPS point (area / city / state).

    No sign-in needed (it only names a point the device already has).
    ``resolved`` is False when Maps is not configured or fails -- the app
    then keeps "Current location" and never claims a confirmed place.
    """
    from app.services import rate_limit

    rate_limit.check(request, "place", limit=30)
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return {"resolved": False, "reason": "invalid_coordinates"}
    container: Any = request.app.state.container
    maps = getattr(container, "google_maps_service", None)
    resolver = getattr(maps, "reverse_geocode", None)
    if not callable(resolver) or not getattr(maps, "enabled", False):
        return {"resolved": False, "reason": "maps_unavailable"}
    place = resolver(latitude, longitude)
    if not place:
        return {"resolved": False, "reason": "not_found"}
    return {"resolved": True, **place}



@router.get("/places")
def search_places(request: Request, q: str, latitude: float | None = None, longitude: float | None = None) -> dict:
    """Address / place search for the location and pickup/drop pickers
    (India region). Real Places results only; empty when Maps is off."""
    from app.services import rate_limit

    rate_limit.check(request, "places", limit=30)
    query = " ".join(str(q or "").split())[:120]
    if len(query) < 2:
        return {"items": [], "status": "query_too_short"}
    maps = getattr(request.app.state.container, "google_maps_service", None)
    if maps is None or not getattr(maps, "enabled", False):
        return {"items": [], "status": "unavailable"}
    places = maps.search_places(query, latitude=latitude, longitude=longitude, radius_m=30000, limit=6)
    status = "error" if getattr(maps, "last_error", False) else ("ok" if places else "no_results")
    return {"status": status, "items": [
        {"name": p.get("name"), "address": p.get("address"), "latitude": p.get("latitude"),
         "longitude": p.get("longitude"), "place_id": p.get("place_id")}
        for p in places if p.get("latitude") is not None and p.get("longitude") is not None
    ]}


class RoutePoint(BaseModel):
    latitude: float
    longitude: float
    label: str = ""


class RouteRequest(BaseModel):
    pickup: RoutePoint
    drop: RoutePoint
    item: str = ""


@router.post("/route")
def route_quote(payload: RouteRequest, request: Request) -> dict:
    """Pickup -> drop: real road distance/time (Routes API) and quotes from
    registered ASKODOX delivery partners' own listed rates. A quote is only
    shown when a partner listed a rate -- never estimated by ASKODOX."""
    from app.services import rate_limit
    from app.services.universal_multi_source_result_service import distance_km

    rate_limit.check(request, "route", limit=20)
    container: Any = request.app.state.container
    for point in (payload.pickup, payload.drop):
        if not (-90 <= point.latitude <= 90 and -180 <= point.longitude <= 180):
            return {"status": "invalid_coordinates"}
    maps = getattr(container, "google_maps_service", None)
    route = None
    if maps is not None and getattr(maps, "enabled", False):
        route = maps.compute_route([payload.pickup.model_dump(), payload.drop.model_dump()])
    straight = distance_km(payload.pickup.latitude, payload.pickup.longitude,
                           payload.drop.latitude, payload.drop.longitude)
    km = (route or {}).get("distance_km") or None
    quotes = []
    catalog = container.product_catalog_repository
    seen = set()
    for query in ("parcel delivery", "courier", "delivery partner"):
        for row in catalog.search_active(query, limit=20) or []:
            if row["id"] in seen or row.get("price") in (None, ""):
                continue
            seen.add(row["id"])
            unit = str(row.get("unit") or "").lower()
            price = float(row["price"])
            per_km = "km" in unit
            if per_km and not km:
                continue  # a per-km rate needs the real road distance
            quotes.append({"listing_id": row["id"], "title": row.get("subject"),
                           "rate": price, "rate_unit": unit or "per trip",
                           "quote": round(price * km, 0) if per_km else price})
    quotes.sort(key=lambda q: q["quote"])
    return {
        "status": "ok" if route else ("maps_unavailable" if maps is None or not getattr(maps, "enabled", False)
                                      else "route_unavailable"),
        "distance_km": km,
        "duration_minutes": (route or {}).get("duration_minutes"),
        "straight_line_km": straight,
        "quotes": quotes[:5],
        "quote_note": "" if quotes else "No registered delivery partner has listed a rate yet.",
    }
