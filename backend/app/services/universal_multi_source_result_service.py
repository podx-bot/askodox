"""Aggregate every relevant source for one requirement into chat results.

Finding one ASKODOX-registered seller must not stop discovery: registered
listings, nearby offline shops, used/individual/surplus/deal options, online
and affiliate destinations, and related videos are all collected, labelled
with a ``segment`` and ranked. Only genuinely relevant rows are returned --
no section is filled just to look complete.

Sources reused (no parallel pipelines):
- ``ProductCatalogRepository.search_active`` + ``ProductMatchRankingService``
  (registered listings; relevance, location, budget, availability, trust)
- ``SellerProfileRepository`` seller tier (``casual`` = individual seller)
- ``GoogleMapsService.search_places`` (nearby external/offline shops)
- the Brave web provider already used by Live Research (used / surplus /
  deals pages), plus ``UniversalOnlineFallbackService`` for online + videos.
"""
from __future__ import annotations

import math
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable

from app.services.universal_external_result_service import (
    UniversalExternalResultService,
    UniversalOnlineFallbackService,
    _host,
    _is_video_host,
)

SEGMENT_REGISTERED = "registered"
SEGMENT_INDIVIDUAL = "individual"
SEGMENT_USED = "used"
SEGMENT_SURPLUS = "surplus"
SEGMENT_DEALS = "deals"
SEGMENT_NEARBY_EXTERNAL = "nearby_external"
SEGMENT_WIDER_LOCAL = "wider_local"

_USED_WORDS = ("used", "second hand", "second-hand", "secondhand", "pre-owned", "preowned", "refurbished")
_SURPLUS_WORDS = ("open box", "open-box", "openbox", "surplus", "clearance", "excess stock", "stock clearance", "display piece")
_DEAL_WORDS = ("offer", "discount", "deal", "% off", "sale", "combo", "cashback")
_NEW_WORDS = ("brand new", "new piece", "sealed", "new ")


def _mentions(text: str, words: tuple[str, ...]) -> bool:
    lower = f" {text.casefold()} "
    return any(word in lower for word in words)


def listing_segment(row: dict[str, Any], seller_tier: str | None = None) -> str:
    """Condition/offer class of a registered listing, inferred from its text."""
    text = " ".join(
        str(row.get(key) or "")
        for key in ("subject", "brand", "variant", "category_tag", "features_json")
    )
    if _mentions(text, _SURPLUS_WORDS):
        return SEGMENT_SURPLUS
    if _mentions(text, _USED_WORDS):
        return SEGMENT_USED
    if _mentions(text, _DEAL_WORDS):
        return SEGMENT_DEALS
    if str(seller_tier or "").lower() == "casual":
        return SEGMENT_INDIVIDUAL
    return SEGMENT_REGISTERED


def wanted_condition(text: str) -> str | None:
    if _mentions(text, _USED_WORDS):
        return "used"
    if _mentions(text, _NEW_WORDS):
        return "new"
    return None


def distance_km(lat1, lon1, lat2, lon2) -> float | None:
    try:
        p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
        dp = p2 - p1
        dl = math.radians(float(lon2) - float(lon1))
    except (TypeError, ValueError):
        return None
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return round(6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)), 1)


def _tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", str(text or "").casefold()) if len(token) > 1}


def _relevant(subject: str, *texts: Any) -> bool:
    """A web row is relevant only if it mentions the requirement's key words."""
    wanted = {token for token in _tokens(subject) if not token.isdigit()} or _tokens(subject)
    if not wanted:
        return False
    hay = _tokens(" ".join(str(text or "") for text in texts))
    return len(wanted & hay) >= max(1, math.ceil(len(wanted) / 2))


class UniversalMultiSourceResultService:
    def __init__(
        self,
        *,
        catalog=None,
        ranking=None,
        seller_profiles=None,
        maps=None,
        web_search: Callable[[str, int], list[dict[str, Any]]] | None = None,
    ) -> None:
        self.catalog = catalog
        self.ranking = ranking
        self.seller_profiles = seller_profiles
        self.maps = maps
        self.web_search = web_search
        self.fallback = UniversalOnlineFallbackService(web_search)

    # ------------------------------------------------------------ public --

    def collect(self, demand: dict[str, Any]) -> list[dict[str, Any]]:
        subject = " ".join(str(demand.get("subject") or "").split())
        if not subject:
            return []
        category = str(demand.get("domain") or "").strip()
        constraints = demand.get("constraints") or {}
        context_text = f"{subject} {constraints}"
        budget = self._number(demand.get("price"))
        lat, lon = demand.get("latitude"), demand.get("longitude")
        location_text = str(demand.get("location_text") or "").strip()
        radius_km = self._number((constraints or {}).get("radius_km")) or 5.0
        condition = wanted_condition(context_text)

        with ThreadPoolExecutor(max_workers=4) as pool:
            external = pool.submit(self._external, subject, location_text, lat, lon, radius_km)
            web = pool.submit(self._web_segments, subject, location_text)
            registered = self._registered(subject, location_text, budget, lat, lon, condition)
            rows = registered + external.result() + web.result()
        return sorted(rows, key=lambda item: -float(item.get("rank_score") or 0))

    def online_and_videos(self, *, category: str, subject: str, include_online: bool) -> list[dict[str, Any]]:
        rows = self.fallback.online(category=category, subject=subject) if include_online else []
        return rows + self.fallback.videos(category=category, subject=subject)

    # ----------------------------------------------------------- sources --

    def _registered(self, subject, location_text, budget, lat, lon, condition) -> list[dict[str, Any]]:
        search = getattr(self.catalog, "search_active", None)
        if not callable(search):
            return []
        try:
            rows = search(subject, limit=30)
            if self.ranking is not None:
                rows = self.ranking.rank(subject, rows, location=location_text or None, budget=budget)
        except Exception:
            return []
        from app.api.routes.product_search import _subtitle, _title

        items = []
        for row in rows:
            price = self._number(row.get("price"))
            # Far over budget is not a relevant option, it is noise.
            if budget and price and price > budget * 1.3:
                continue
            segment = listing_segment(row, self._tier(row.get("seller_user_id")))
            if condition == "new" and segment in {SEGMENT_USED, SEGMENT_SURPLUS}:
                continue
            score = 50.0 + float(row.get("match_score") or 0)
            if condition == "used" and segment == SEGMENT_USED:
                score += 15
            if budget and price and price <= budget:
                score += 10
            items.append({
                "id": str(row["id"]),
                "match_id": str(row["id"]),
                # Seller identity is their phone: never exposed before an
                # accepted order (order_contact_visibility.py).
                "provider_id": "",
                "title": _title(row),
                "subtitle": _subtitle(row),
                "price": price,
                "availability": str(row.get("stock_status") or "").replace("_", " ").title() or None,
                "location_label": str(row.get("location_label") or "") or None,
                "source": "local",
                "match_source": "registered",
                "segment": segment,
                "rank_score": score,
                "demo": False,
            })
        return items

    def _external(self, subject, location_text, lat, lon, radius_km) -> list[dict[str, Any]]:
        search = getattr(self.maps, "search_places", None)
        if not callable(search) or not getattr(self.maps, "enabled", False):
            return []
        query = f"{subject} shop" + (f" near {location_text}" if location_text else "")
        try:
            places = search(query, latitude=lat, longitude=lon, radius_m=radius_km * 3000, limit=10)
        except Exception:
            return []
        items = []
        for index, place in enumerate(places):
            km = distance_km(lat, lon, place.get("latitude"), place.get("longitude"))
            if km is not None and km > radius_km * 3:
                continue  # beyond the wider local area: not a local option
            segment = SEGMENT_WIDER_LOCAL if km is not None and km > radius_km else SEGMENT_NEARBY_EXTERNAL
            rating = self._number(place.get("rating"))
            score = 40.0 - (km or radius_km) * 2 + (rating or 0) * 2
            items.append({
                "id": f"external-{place.get('place_id') or index}",
                "match_id": f"external-{place.get('place_id') or index}",
                "provider_id": "",
                "title": place.get("name"),
                "subtitle": place.get("address") or "Nearby shop (not on ASKODOX yet)",
                "distance_km": km,
                "rating_average": rating,
                "review_count": int(place.get("rating_count") or 0),
                "availability": ("Open now" if place.get("open_now") is True else None),
                "destination_url": place.get("maps_url") or None,
                "source": "external",
                "match_source": "external",
                "segment": segment,
                "rank_score": score,
                "demo": False,
            })
        return items

    def _web_segments(self, subject, location_text) -> list[dict[str, Any]]:
        if not callable(self.web_search) or not getattr(self.web_search, "configured", True):
            return []
        near = f" {location_text}" if location_text else ""
        queries = {
            SEGMENT_USED: f"used second hand {subject}{near}",
            SEGMENT_SURPLUS: f"open box clearance {subject}{near}",
            SEGMENT_DEALS: f"{subject} offers deals{near}",
        }
        items: list[dict[str, Any]] = []
        for segment, query in queries.items():
            words = {SEGMENT_USED: _USED_WORDS, SEGMENT_SURPLUS: _SURPLUS_WORDS, SEGMENT_DEALS: _DEAL_WORDS}[segment]
            try:
                rows = self.web_search(query, 6) or []
            except Exception:
                rows = []
            kept = 0
            for row in rows:
                url = UniversalExternalResultService._http_url((row or {}).get("url"))
                title, snippet = (row or {}).get("title"), (row or {}).get("snippet")
                if not url or _is_video_host(url):
                    continue
                # Must be about the requirement AND genuinely this segment.
                if not _relevant(subject, title, snippet) or not _mentions(f"{title} {snippet}", words):
                    continue
                host = _host(url).removeprefix("www.")
                items.append({
                    "id": f"{segment}-{kept}-{host}",
                    "match_id": f"{segment}-{kept}-{host}",
                    "provider_id": host,
                    "title": str(title or host)[:160],
                    "subtitle": str(snippet or "")[:280],
                    "destination_url": url,
                    "source": "online",
                    "match_source": "online",
                    "segment": segment,
                    "rank_score": 20.0 - kept,
                    "affiliate": False,
                    "disclosure": "",
                    "demo": False,
                })
                kept += 1
                if kept >= 3:
                    break
        return items

    # ----------------------------------------------------------- helpers --

    def _tier(self, seller_user_id) -> str | None:
        getter = getattr(self.seller_profiles, "get", None)
        if not callable(getter) or not seller_user_id:
            return None
        try:
            profile = getter(str(seller_user_id)) or {}
        except Exception:
            return None
        return profile.get("tier") or profile.get("seller_tier")

    @staticmethod
    def _number(value) -> float | None:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return None
        return number if number > 0 else None
