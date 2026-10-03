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
    BUYABLE_PAGES,
    JOB_HOSTS,
    PAGE_JOB,
    STATUS_ERROR,
    STATUS_NO_RESULTS,
    STATUS_OK,
    STATUS_UNAVAILABLE,
    UniversalExternalResultService,
    UniversalOnlineFallbackService,
    _host,
    _is_video_host,
    _price_fields,
    _host_matches,
    _tokens,
    category_conflict,
    intent_conflict,
    classify_page,
    place_region_mismatch,
    region_mismatch,
    relevant_to,
)

SEGMENT_REGISTERED = "registered"
SEGMENT_INDIVIDUAL = "individual"
SEGMENT_USED = "used"
SEGMENT_SURPLUS = "surplus"
SEGMENT_DEALS = "deals"
SEGMENT_NEARBY_EXTERNAL = "nearby_external"
SEGMENT_WIDER_LOCAL = "wider_local"
SEGMENT_JOBS = "jobs"

STATUS_NOT_APPLICABLE = "not_applicable"
# Nearby search needs a place: without one it is never run as a generic
# "in India" query (that is how US stores / Delhi results appeared).
STATUS_NEEDS_LOCATION = "needs_location"

# One universal engine, category-aware source selection (never a per-category
# flow): which discovery sources make sense for the KIND of need.
NEED_PRODUCT, NEED_SERVICE, NEED_PARTY, NEED_JOB = "product", "service", "party", "job"
_SERVICE_DOMAINS = {"SERVICES", "SERVICE", "APPOINTMENT", "EVENT", "REPAIR", "STAFFING", "RENTAL"}
_PARTY_DOMAINS = {"JOB", "JOBS", "WORK", "WORKERS", "JOB_SEEKER", "RIDE", "MOBILITY", "PARCEL",
                  "DELIVERY", "COURIER"}
_JOB_DOMAINS = {"JOB", "JOBS", "WORK", "JOB_SEEKER"}
SOURCE_PLAN = {
    NEED_PRODUCT: {"askodox", "nearby", "used_deals", "online", "videos"},
    NEED_SERVICE: {"askodox", "nearby", "online", "videos"},  # videos only when asked
    NEED_PARTY: {"askodox"},
    # A job seeker: ASKODOX employers first, then real job openings online.
    NEED_JOB: {"askodox", "jobs"},
}


# Geographic expansion (only when the nearer scope found nothing): each step
# is one more Places call, so it stops at the first scope with options.
GEO_LADDER = (
    ("nearby", None),        # the customer's own radius
    ("city", 25.0),
    ("region", 80.0),        # district / nearby region
    ("state", 250.0),
)


def _public_image(value: Any) -> str | None:
    text = str(value or "").strip()
    # A seller's own catalogue photo is served by ASKODOX (the app resolves
    # the relative path against its API base).
    if text.startswith("catalog-photo:") and text.split(":", 1)[1].isdigit():
        return f"/api/catalog/photos/{text.split(':', 1)[1]}"
    return text if text.startswith("https://") else None


# Service wording: "AC installation", "fridge repair", "bike servicing" ask
# for a PROVIDER, even when the object named is a product the AI may have
# tagged as PRODUCT. Explicit buying wording keeps it a product search.
_SERVICE_WORDS = re.compile(
    r"\b(install(ation|ing|er)?|uninstall(ation)?|repair(s|ing|er)?|servic(e|es|ing)|fix(ing)?|mechanic|"
    r"plumb(er|ing)|electrician|carpenter|technician|cleaning|painting|painter|maintenance|fitting|wiring|"
    r"pest control|gas (refill|filling)|tutor(ing)?|tuition|driver|mason|welder|shifting|packers?)\b",
    re.IGNORECASE,
)
_BUY_WORDS = re.compile(r"\b(buy|purchase|price of|for sale|order|shop for|new [a-z]+ with|warranty)\b", re.IGNORECASE)


def is_service_wording(text: str) -> bool:
    text = str(text or "")
    return bool(_SERVICE_WORDS.search(text)) and not _BUY_WORDS.search(text)


def need_kind(demand: dict[str, Any]) -> str:
    domain = str(demand.get("domain") or "").strip().upper()
    if domain in _JOB_DOMAINS and str(demand.get("side") or "").upper() == "OFFER":
        return NEED_JOB
    if domain in _PARTY_DOMAINS:
        return NEED_PARTY
    if domain in _SERVICE_DOMAINS:
        return NEED_SERVICE
    if domain in {"", "PRODUCT", "PRODUCTS", "GENERAL", "OTHER"} and is_service_wording(
        f"{demand.get('subject') or ''} {demand.get('raw_text') or ''}"
    ):
        return NEED_SERVICE
    return NEED_PRODUCT


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


_JOB_SITE_SUFFIX = re.compile(r"\s*[-|–:]\s*(naukri(\.com)?|indeed|shine(\.com)?|apna|workindia|foundit|"
                              r"timesjobs|glassdoor|linkedin|freshersworld|quikr|olx)[^\n]*$", re.IGNORECASE)


def job_card_title(title: str) -> tuple[str, str | None]:
    """'369 Latest Delivery Vacancies in Hyderabad 2026 - Naukri.com' ->
    ('Delivery jobs', 'Hyderabad'): short and scannable, nothing invented
    (the full page title stays in Details)."""
    text = _JOB_SITE_SUFFIX.sub("", " ".join(title.split()))
    place_match = re.search(r"\bin ([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)?)", text)
    place = place_match.group(1) if place_match else None
    text = re.sub(r"\bin [A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)?", " ", text)
    text = re.sub(r"^\s*[\d,]+\+?\s*", "", text)
    text = re.sub(r"\b(latest|new|urgent|top|best|jobs? openings?|openings?|vacanc(?:y|ies)|jobs?|hiring|"
                  r"recruitment|20\d\d|near me|apply now|today)\b", " ", text, flags=re.IGNORECASE)
    core = " ".join(text.replace("&", " ").split()).strip(" -,:|")
    return ((f"{core} jobs" if core else title.strip()[:80]), place)


def distance_km(lat1, lon1, lat2, lon2) -> float | None:
    try:
        p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
        dp = p2 - p1
        dl = math.radians(float(lon2) - float(lon1))
    except (TypeError, ValueError):
        return None
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return round(6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)), 1)


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
        self._status: dict[str, str] = {}
        # Sources the Self-Healing Engine is bypassing right now (GREEN,
        # temporary): skipped instead of waiting on a failing provider.
        self.bypassed: set[str] = set()
        self._kind = NEED_PRODUCT
        self._filtered: dict[str, int] = {}
        # Geographic scope actually used for local results (admin trace +
        # the one-line "expanding to ..." message in chat).
        self.scope: dict[str, Any] = {}

    def _filter(self, reason: str) -> None:
        self._filtered[reason] = self._filtered.get(reason, 0) + 1

    def filtered_counts(self) -> dict[str, int]:
        """Rows dropped and why (admin flow trace), across all sources."""
        merged = dict(self._filtered)
        for reason, count in getattr(self.fallback, "filtered", {}).items():
            merged[reason] = merged.get(reason, 0) + count
        return merged

    def source_status(self) -> dict[str, str]:
        """Per source: ok / no_results / unavailable / not_applicable (never faked)."""
        status = {**self._status, **self.fallback.status}
        for source in ("askodox", "nearby", "used_deals", "online", "videos", "jobs"):
            if source not in self._source_plan():
                status[source] = STATUS_NOT_APPLICABLE
        return status

    def _source_plan(self) -> set[str]:
        """The kind's sources plus every group the customer explicitly asked
        for (offers on a service request still search deals)."""
        plan = set(SOURCE_PLAN[self._kind])
        requested = set(getattr(self, "_requested", ()) or ())
        if self._kind in (NEED_PRODUCT, NEED_SERVICE):
            if "deals" in requested:
                plan.add("used_deals")
            if "videos" in requested:
                plan.add("videos")
        return plan

    # ------------------------------------------------------------ public --

    def collect(self, demand: dict[str, Any]) -> list[dict[str, Any]]:
        subject = " ".join(str(demand.get("subject") or "").split())
        self._kind = need_kind(demand)
        self._requested = tuple((demand.get("constraints") or {}).get("requested_groups") or ())
        if not subject:
            return []
        plan = self._source_plan()
        category = str(demand.get("domain") or "").strip()
        constraints = demand.get("constraints") or {}
        context_text = f"{subject} {constraints}"
        # The AI's category ("grocery", "fashion" ...) travels with the demand:
        # every web row must belong to it (category_conflict).
        self._category = f"{category} {constraints.get('aiCategory') or ''}".strip()
        setattr(self.fallback, "category_hint", self._category)
        # A seller / provider (OFFER side) is not shopping: buyer-side web
        # searches (used, open box, deals, online shops) are not their results.
        self._supply = str(demand.get("side") or "").upper() == "OFFER" and self._kind == NEED_PRODUCT
        budget = self._number(demand.get("price"))
        lat, lon = demand.get("latitude"), demand.get("longitude")
        location_text = str(demand.get("location_text") or "").strip()
        radius_km = self._number((constraints or {}).get("radius_km")) or 5.0
        condition = wanted_condition(context_text)
        # Words naming a place/route ("to Hyderabad", "in Vijayawada") are not
        # the thing wanted: they must never match an unrelated listing.
        place_words = _tokens(" ".join(
            str(v) for v in (location_text, (constraints or {}).get("from"), (constraints or {}).get("to"),
                             (constraints or {}).get("pickup"), (constraints or {}).get("drop")) if v
        ))

        skip = self.bypassed
        with ThreadPoolExecutor(max_workers=4) as pool:
            external = (pool.submit(self._external, subject, location_text, lat, lon, radius_km)
                        if "nearby" in plan and "nearby" not in skip else None)
            web = (pool.submit(self._web_segments, subject, location_text)
                   if "used_deals" in plan and "used_deals" not in skip else None)
            jobs = (pool.submit(self._jobs, subject, location_text, constraints)
                    if "jobs" in plan and "jobs" not in skip else None)
            registered = self._registered(subject, location_text, budget, lat, lon, condition, place_words)
            external_rows = external.result() if external else []
            web_rows = web.result() if web else []
            job_rows = jobs.result() if jobs else []
            rows = registered + external_rows + web_rows + job_rows
        self._status["askodox"] = STATUS_OK if registered else STATUS_NO_RESULTS
        maps_ready = callable(getattr(self.maps, "search_places", None)) and getattr(self.maps, "enabled", False)
        if "nearby" in plan and self._needs_location:
            self._status["nearby"] = STATUS_NEEDS_LOCATION
        elif not maps_ready:
            self._status["nearby"] = STATUS_UNAVAILABLE
        elif external_rows:
            self._status["nearby"] = STATUS_OK
        else:
            self._status["nearby"] = STATUS_ERROR if self._maps_failed else STATUS_NO_RESULTS
        web_ready = callable(self.web_search) and getattr(self.web_search, "configured", True)
        self._status["used_deals"] = (STATUS_OK if web_rows else STATUS_NO_RESULTS) if web_ready else STATUS_UNAVAILABLE
        if "jobs" in plan:
            self._status["jobs"] = (STATUS_OK if job_rows else STATUS_NO_RESULTS) if web_ready else STATUS_UNAVAILABLE
        for source in skip:
            if source in plan and self._status.get(source) != STATUS_NEEDS_LOCATION:
                self._status[source] = "bypassed_unhealthy"
        return sorted(rows, key=lambda item: -float(item.get("rank_score") or 0))

    def online_and_videos(self, *, category: str, subject: str, include_online: bool,
                          location_text: str = "", include_videos: bool = True) -> list[dict[str, Any]]:
        plan = self._source_plan()
        query = None
        where = location_text or "India"
        if self._kind == NEED_SERVICE:
            query = f"{subject} service in {where} book"
        rows = (self.fallback.online(category=category, subject=subject, query=query, location_text=location_text,
                                     allow_directories=self._kind == NEED_SERVICE)
                if include_online and "online" in plan and not getattr(self, "_supply", False) else [])
        if "videos" in plan and not include_videos:
            # Reviews/videos only when the customer asked for them (never
            # mixed into "buy a TV" results just because search found some).
            self.fallback.status["videos"] = STATUS_NOT_APPLICABLE
            return rows
        return rows + (self.fallback.videos(category=category, subject=subject, service=self._kind == NEED_SERVICE)
                       if "videos" in plan else [])

    # ----------------------------------------------------------- sources --

    def _registered(self, subject, location_text, budget, lat, lon, condition,
                    place_words: set[str] | None = None) -> list[dict[str, Any]]:
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

        core = " ".join(t for t in _tokens(subject) if t not in (place_words or set())) or subject
        items = []
        for row in rows:
            # The listing must be about what is wanted -- a place name alone
            # ("Hyderabad" in a parcel request) is never a match.
            listing_text = " ".join(str(row.get(k) or "") for k in
                                    ("subject", "brand", "variant", "category_tag", "features_json"))
            if not relevant_to(core, listing_text):
                self._filter("not_relevant")
                continue
            price = self._number(row.get("price"))
            # Far over budget is not a relevant option, it is noise.
            if budget and price and price > budget * 1.3:
                self._filter("over_budget")
                continue
            segment = listing_segment(row, self._tier(row.get("seller_user_id")))
            if condition == "new" and segment in {SEGMENT_USED, SEGMENT_SURPLUS}:
                self._filter("condition_mismatch")
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
                # Only a real, publicly loadable photo URL -- never a guess.
                "image_url": _public_image(row.get("image_media_id")),
                "source": "local",
                "match_source": "registered",
                "segment": segment,
                "rank_score": score,
                "demo": False,
            })
        return items

    _maps_failed = False
    _needs_location = False

    def _external(self, subject, location_text, lat, lon, radius_km) -> list[dict[str, Any]]:
        search = getattr(self.maps, "search_places", None)
        if not callable(search) or not getattr(self.maps, "enabled", False):
            return []
        has_point = lat is not None and lon is not None
        if not has_point and not location_text:
            # "Nearby" without a place is meaningless: never a country-wide
            # guess. The app asks for / uses the customer's location instead.
            self._needs_location = True
            return []
        # "used car shop" finds nothing; the need itself ("used car near X")
        # lets Places return dealers, garages, stores -- whatever sells it.
        # A domain adapter names the right kind of business (a toothache ->
        # "dentist", rooms -> "hotel"); otherwise the need itself.
        from app.services import domain_adapters

        adapted = domain_adapters.search_query(subject)
        noun = " service" if self._kind == NEED_SERVICE and adapted == subject else ""
        query = f"{adapted}{noun}" + (f" near {location_text}" if location_text else "")
        ladder = GEO_LADDER if has_point else GEO_LADDER[:1]
        for level, level_km in ladder:
            scope_km = max(radius_km, level_km or radius_km)
            if level_km is not None and level_km <= radius_km:
                continue
            try:
                places = search(query, latitude=lat, longitude=lon, radius_m=scope_km * 1000, limit=10)
            except Exception:
                places = []
            if getattr(self.maps, "last_error", False):
                self._maps_failed = True
                return []
            items = self._places_to_rows(places, lat, lon, radius_km, scope_km)
            if items:
                expanded = level != "nearby"
                self.scope = {
                    "level": level,
                    "radius_km": scope_km,
                    "expanded": expanded,
                    "place": location_text or None,
                    "message": (f"No suitable option near {location_text or 'you'}, "
                                f"expanding to the wider {level} (~{int(scope_km)} km).") if expanded else "",
                }
                return items
        self.scope = {"level": ladder[-1][0], "radius_km": max(radius_km, ladder[-1][1] or radius_km),
                      "expanded": len(ladder) > 1, "place": location_text or None, "message": ""}
        return []

    def _places_to_rows(self, places, lat, lon, radius_km, scope_km) -> list[dict[str, Any]]:
        items = []
        for index, place in enumerate(places or []):
            if place_region_mismatch(place.get("address")):
                self._filter("wrong_region")
                continue
            km = distance_km(lat, lon, place.get("latitude"), place.get("longitude"))
            if km is not None and km > max(scope_km * 1.5, radius_km * 3):
                self._filter("too_far")
                continue  # beyond the current search scope: not a local option
            segment = SEGMENT_WIDER_LOCAL if km is not None and km > radius_km else SEGMENT_NEARBY_EXTERNAL
            rating = self._number(place.get("rating"))
            score = 40.0 - min(km or radius_km, 200) * 0.2 + (rating or 0) * 2
            items.append({
                "id": f"external-{place.get('place_id') or index}",
                "match_id": f"external-{place.get('place_id') or index}",
                "provider_id": "",
                "title": place.get("name"),
                "subtitle": place.get("address") or "Local business (not on ASKODOX yet)",
                "distance_km": km,
                "rating_average": rating,
                # Unknown stays unknown (never "0 reviews" for a place Google
                # simply did not report on).
                "review_count": int(place["rating_count"]) if place.get("rating_count") not in (None, "") else None,
                "availability": ("Open now" if place.get("open_now") is True else None),
                "destination_url": place.get("maps_url") or None,
                # Real coordinates for Directions (never a guessed point).
                "latitude": place.get("latitude"),
                "longitude": place.get("longitude"),
                "source": "external",
                "match_source": "external",
                "segment": segment,
                "page_type": "business",
                # Places gives no price: never shown as if it did.
                "price": None,
                "price_verified": False,
                "rank_score": score,
                "demo": False,
            })
        return items

    def _web_segments(self, subject, location_text) -> list[dict[str, Any]]:
        if not callable(self.web_search) or not getattr(self.web_search, "configured", True):
            return []
        if getattr(self, "_supply", False):
            return []
        near = f" {location_text}" if location_text else " India"
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
                if not relevant_to(subject, title, snippet) or not _mentions(f"{title} {snippet}", words):
                    self._filter("not_relevant")
                    continue
                if category_conflict(subject, getattr(self, "_category", ""), url, title, snippet):
                    self._filter("other_category")
                    continue
                if intent_conflict(subject, getattr(self, "_category", ""), url, title, snippet):
                    self._filter("other_intent")
                    continue
                if region_mismatch(url, title, snippet, wanted_place=location_text):
                    self._filter("wrong_region")
                    continue
                page_type = classify_page(url, title, snippet)
                if page_type not in BUYABLE_PAGES:
                    self._filter("not_purchasable")
                    continue
                host = _host(url).removeprefix("www.")
                items.append({
                    "id": f"{segment}-{kept}-{host}",
                    "match_id": f"{segment}-{kept}-{host}",
                    "provider_id": host,
                    "title": str(title or host)[:160],
                    "subtitle": str(snippet or "")[:280],
                    "destination_url": url,
                    "image_url": (row or {}).get("thumbnail") or None,
                    "source_name": (row or {}).get("host") or host,
                    **_price_fields(title, snippet),
                    "page_type": page_type,
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

    _SALARY = re.compile(
        r"(?:₹|rs\.?|inr)\s?[0-9][0-9,.]*\s*(?:k|lpa|lakh|lakhs)?(?:\s*(?:-|to|–)\s*(?:₹|rs\.?|inr)?\s?[0-9][0-9,.]*"
        r"\s*(?:k|lpa|lakh|lakhs)?)?(?:\s*(?:per|/|a)\s*(?:month|annum|year|pm|pa))?"
        r"|[0-9][0-9,.]*\s*(?:-|to|–)\s*[0-9][0-9,.]*\s*(?:lpa|lakhs? p\.?a\.?)",
        re.IGNORECASE,
    )

    def _jobs(self, subject, location_text, constraints) -> list[dict[str, Any]]:
        """Real job openings from job sites (Brave, India-first). Salary only
        when the page text states one -- never estimated."""
        if not callable(self.web_search) or not getattr(self.web_search, "configured", True):
            return []
        core = re.sub(r"\b(jobs?|work|vacanc(y|ies)|openings?|near me|nearby)\b", " ", subject, flags=re.I)
        core = " ".join(core.split()) or subject
        where = location_text or "India"
        try:
            rows = self.web_search(f"{core} jobs in {where}", 12) or []
        except Exception:
            rows = []
        items: list[dict[str, Any]] = []
        for row in rows:
            url = UniversalExternalResultService._http_url((row or {}).get("url"))
            title, snippet = (row or {}).get("title"), (row or {}).get("snippet")
            if not url or _is_video_host(url):
                continue
            if classify_page(url, title, snippet) != PAGE_JOB and not _host_matches(url, JOB_HOSTS):
                self._filter("not_a_job_listing")
                continue
            if not relevant_to(core, title, snippet, url):
                self._filter("not_relevant")
                continue
            if region_mismatch(url, title, snippet, wanted_place=location_text):
                self._filter("wrong_region")
                continue
            host = _host(url).removeprefix("www.")
            salary = self._SALARY.search(f"{title or ''} {snippet or ''}")
            short_title, place = job_card_title(str(title or host))
            items.append({
                "id": f"job-{len(items)}-{host}",
                "match_id": f"job-{len(items)}-{host}",
                "provider_id": host,
                "title": short_title[:80],
                "full_title": str(title or host)[:160],
                "subtitle": str(snippet or "")[:280],
                "destination_url": url,
                "source_name": (row or {}).get("host") or host,
                # Salary is text from the page itself, or absent.
                "salary_text": salary.group(0).strip() if salary else None,
                "price": None,
                "price_verified": False,
                "location_label": place or location_text or None,
                "page_type": PAGE_JOB,
                "source": "online",
                "match_source": "online",
                "segment": SEGMENT_JOBS,
                "rank_score": 30.0 - len(items),
                "affiliate": False,
                "disclosure": "",
                "demo": False,
            })
            if len(items) >= 6:
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
