from __future__ import annotations

from typing import Any

import hashlib
import hmac
import json
import os
import re

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.debug import _prepare_askodox_app_identity
from app.api.routes.in_app_deal import (
    InterestDecisionRequest,
    _app_user,
    _authenticated_app_user,
    _matching_app_user,
    interest_action,
)
from app.core.default_intent_rules import build_default_intent_router
from app.core.domain_field_requirements import FieldPolicyNotFoundError, missing_fields
from app.core.intent_domain_router import IntentRouteNotFoundError
from app.services.universal_category_schema import UniversalCategorySchemaRegistry
from app.services.universal_action_contract import build_action_result
from app.services.universal_external_result_service import UniversalExternalResultService
from app.repositories.command_center_repository import mask_user_id
from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService

router = APIRouter(prefix="/deals", tags=["Deals"])

_INTENT_ROUTER = build_default_intent_router()


class UniversalDealCreateRequest(BaseModel):
    user_id: str
    raw_text: str = Field(min_length=1, max_length=4000)
    intent: str | None = None
    opposite_intent: str | None = None
    subject: str | None = None
    category: str | None = None
    quantity: float | None = None
    unit: str | None = None
    price: float | None = None
    price_basis: str | None = None
    quality: str | None = None
    variant: str | None = None
    size: str | None = None
    weight: str | None = None
    model: str | None = None
    availability: str | None = None
    fulfilment: str | None = None
    timing: str | None = None
    location: dict | None = None
    dynamic_fields: dict = Field(default_factory=dict)
    party_a: dict | None = None
    party_b: dict | None = None
    # App-side context for the admin flow trace (query, AI intent,
    # categories, questions asked, answers remembered, auth gate). Optional.
    trace: dict | None = None


class AcceptMatchRequest(BaseModel):
    match_id: str = Field(min_length=1)


class ReviewRequest(BaseModel):
    reviewed_user_id: str = Field(min_length=1)
    rating: int = Field(ge=1, le=5)
    review_text: str = Field(default="", max_length=2000)




class ExternalClickRequest(BaseModel):
    provider_id: str = Field(min_length=1, max_length=80)
    result_id: str = Field(default="", max_length=160)
    destination_url: str = Field(default="", max_length=2000)
    user_id: str = Field(default="", max_length=160)


class ExternalConversionRequest(BaseModel):
    provider_id: str = Field(min_length=1, max_length=80)
    event: str = Field(default="conversion", max_length=80)
    external_reference: str = Field(default="", max_length=240)
    value: float | None = None
    currency: str = Field(default="INR", max_length=8)


def _ensure_external_tracking_table(container) -> None:
    container.database.execute("""CREATE TABLE IF NOT EXISTS external_commerce_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        result_id TEXT,
        destination_url TEXT,
        user_ref TEXT,
        external_reference TEXT,
        value REAL,
        currency TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )""")


@router.post("/external/click")
def record_external_click(payload: ExternalClickRequest, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "external_click", limit=60)  # public, write-only log
    container = request.app.state.container
    _ensure_external_tracking_table(container)
    user_ref = mask_user_id(payload.user_id) if payload.user_id else ""
    container.database.execute(
        """INSERT INTO external_commerce_events
        (event_type,provider_id,result_id,destination_url,user_ref,currency)
        VALUES('click',?,?,?,?,?)""",
        (payload.provider_id.strip().lower(), payload.result_id, payload.destination_url, user_ref, "INR"),
    )
    return {"recorded": True, "event": "click"}


@router.post("/external/conversion")
def record_external_conversion(payload: ExternalConversionRequest, request: Request) -> dict:
    container = request.app.state.container
    config = getattr(container, "affiliate_provider_config", None)
    provider = dict((config.providers if config else {}).get(payload.provider_id.strip().lower()) or {})
    if not provider or not provider.get("callback_enabled", False):
        raise HTTPException(status_code=404, detail="Conversion callback is not enabled for this provider")
    provider_key = re.sub(r"[^A-Z0-9]+", "_", payload.provider_id.strip().upper()).strip("_")
    secret = os.getenv(f"ASKODOX_PARTNER_{provider_key}_CALLBACK_SECRET", "").strip()
    if not secret:
        raise HTTPException(status_code=503, detail="Conversion callback secret is not configured")
    supplied = request.headers.get("x-askodox-signature", "").strip()
    canonical = json.dumps(payload.model_dump(), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    expected = hmac.new(secret.encode(), canonical, hashlib.sha256).hexdigest()
    if not supplied or not hmac.compare_digest(supplied.removeprefix("sha256="), expected):
        raise HTTPException(status_code=401, detail="Invalid conversion callback signature")
    reference = payload.external_reference.strip()
    if not reference:
        raise HTTPException(status_code=422, detail="external_reference is required for conversion callbacks")
    event = payload.event.strip().lower()
    provider_id = payload.provider_id.strip().lower()
    _ensure_external_tracking_table(container)
    existing = container.database.fetchone(
        """SELECT id FROM external_commerce_events
        WHERE provider_id=? AND event_type=? AND external_reference=? LIMIT 1""",
        (provider_id, event, reference),
    )
    if existing is not None:
        return {"recorded": False, "duplicate": True, "event": event}
    container.database.execute(
        """INSERT INTO external_commerce_events
        (event_type,provider_id,external_reference,value,currency)
        VALUES(?,?,?,?,?)""",
        (event, provider_id, reference, payload.value, payload.currency.upper()),
    )
    return {"recorded": True, "duplicate": False, "event": event}


def _latest_created_deal(container, user_id: str):
    return container.database.fetchone(
        """
        SELECT id,user_id,side,domain,subject,quantity,unit,price,currency,
             when_text,location_text,latitude,longitude,constraints_json,status,created_at
        FROM universal_need_offer_records
        WHERE user_id=?
        ORDER BY id DESC
        LIMIT 1
        """,
        (user_id,),
    )


def _deal_progressed(before, after) -> bool:
    """Treat both a new row and a meaningful in-place follow-up update as progress."""
    if after is None:
        return False
    if before is None:
        return True
    before_item = dict(before)
    after_item = dict(after)
    if int(after_item.get("id") or 0) > int(before_item.get("id") or 0):
        return True
    if int(after_item.get("id") or 0) != int(before_item.get("id") or 0):
        return False
    mutable_fields = (
        "side",
        "domain",
        "subject",
        "quantity",
        "unit",
        "price",
        "currency",
        "when_text",
        "location_text",
        "latitude",
        "longitude",
        "constraints_json",
        "status",
    )
    return any(before_item.get(field) != after_item.get(field) for field in mutable_fields)


def _present(value) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, dict):
        return any(_present(item) for item in value.values())
    if isinstance(value, (list, tuple, set)):
        return any(_present(item) for item in value)
    return True


def _extractor_context(raw_text: str, extractor) -> dict:
    """Reuse the existing UniversalRequestExtractor only to fill details already said.

    The extractor remains advisory here. It never overrides normalized app fields and
    the existing conversation/live-capture pipeline remains authoritative for saving,
    merging and matching the actual requirement.
    """
    if extractor is None:
        return {}
    try:
        extracted = extractor.extract(raw_text)
    except Exception:
        return {}
    if not extracted or not extracted.get("success"):
        return {}
    request = dict(extracted.get("request") or {})
    if not request:
        return {}
    return {
        "subject": request.get("subject"),
        "quantity": request.get("quantity"),
        "unit": request.get("unit"),
        "price": request.get("price"),
        "timing": request.get("when_text"),
        "location": request.get("location_text"),
    }


def _normalized_intent_state(payload: UniversalDealCreateRequest) -> dict:
    """Translate Flutter deal aliases into the canonical intent-policy field names."""
    dynamic = dict(payload.dynamic_fields or {})
    state = {
        "subject": payload.subject,
        "location": payload.location,
        "timing": payload.timing,
        "quantity": payload.quantity,
        "unit": payload.unit,
        "price": payload.price,
        "price_basis": payload.price_basis,
        "quality": payload.quality,
        "variant": payload.variant,
        "size": payload.size,
        "weight": payload.weight,
        "model": payload.model,
        "availability": payload.availability,
        "fulfilment": payload.fulfilment,
        **dynamic,
    }

    aliases = {
        "from": "from_location",
        "to": "to_location",
    }
    for source, target in aliases.items():
        if not _present(state.get(target)) and _present(state.get(source)):
            state[target] = state[source]
    return state


def _intent_context(payload: UniversalDealCreateRequest, extractor=None) -> dict | None:
    """Classify the request and ask only for details the user has not already stated."""
    try:
        route = _INTENT_ROUTER.route(payload.raw_text)
    except IntentRouteNotFoundError:
        return None

    state = _normalized_intent_state(payload)
    try:
        preliminary_missing = missing_fields(route.domain, route.action, state)
    except FieldPolicyNotFoundError:
        preliminary_missing = ()

    if preliminary_missing and extractor is not None:
        extracted_state = _extractor_context(payload.raw_text, extractor)
        for key, value in extracted_state.items():
            if not _present(state.get(key)) and _present(value):
                state[key] = value

    try:
        required_missing = missing_fields(route.domain, route.action, state)
    except FieldPolicyNotFoundError:
        required_missing = ()

    return {
        "domain": route.domain,
        "action": route.action,
        "score": route.score,
        "missing_fields": list(required_missing),
    }


def _readiness(created: dict | None, intent_context: dict | None) -> dict:
    """Expose one backend readiness contract without changing capture behavior."""
    item = dict(created or {})
    missing = list((intent_context or {}).get("missing_fields") or [])
    constraints = item.get("constraints") or item.get("constraints_json") or {}
    if isinstance(constraints, str):
        try:
            constraints = json.loads(constraints)
        except json.JSONDecodeError:
            constraints = {"raw": constraints}
    schema = UniversalCategorySchemaRegistry.resolve(item.get("domain"))
    action_result = build_action_result(
        raw_status=str(item.get("status") or "ACTIVE"),
        request_id=item.get("id"),
        category=item.get("domain"),
        side=item.get("side"),
        channel="in_app",
        missing_fields=tuple(missing),
        result={"subject": item.get("subject"), "location": item.get("location_text")},
    )
    return {
        "ready_to_match": bool(item) and not missing,
        "missing_fields": missing,
        "result_kind": schema.result_kind,
        "seeker_capability": schema.seeker_capability,
        "provider_capability": schema.provider_capability,
        "lifecycle": action_result.to_dict(),
        "canonical": {
            "deal_id": item.get("id"),
            "side": item.get("side"),
            "domain": item.get("domain"),
            "subject": item.get("subject"),
            "quantity": item.get("quantity"),
            "unit": item.get("unit"),
            "price": item.get("price"),
            "location": item.get("location_text"),
            "latitude": item.get("latitude"),
            "longitude": item.get("longitude"),
            "constraints": constraints,
        },
    }


def _demo_discovery_matches(container, demand: dict, existing_ids: set[str]) -> list[dict]:
    """Expose matcher candidates only for isolated TEST/DEMO records.

    Production keeps the consent-first interested-responder contract unchanged.
    Demo mode can immediately show its deterministic opposite-side candidate so
    end-to-end UI tests do not depend on a second real account responding first.
    """
    repository = container.universal_demand_repository
    if not repository.is_test_record(demand):
        return []

    discovered = []
    for candidate in container.universal_matcher.find_matches(demand, limit=20):
        responder = str(candidate.get("user_id") or "").strip()
        if not responder or responder in existing_ids:
            continue
        subject = str(candidate.get("subject") or "Match").strip()
        domain = str(candidate.get("domain") or "").upper()
        if domain in {"WORK", "WORKERS"}:
            title = f"{subject.title()} job match"
            subtitle = "Demo employer available nearby" if domain == "WORKERS" else "Demo worker available nearby"
        else:
            title = subject
            subtitle = "Demo match available nearby"
        discovered.append(
            {
                "id": responder,
                "match_id": responder,
                "provider_id": responder,
                "title": title,
                "subtitle": subtitle,
                "score": candidate.get("score"),
                "distance_km": candidate.get("distance_km"),
                "price": candidate.get("price"),
                "match_source": "demo_discovery",
                "demo": True,
            }
        )
    return discovered


_SUPPLY_INTENTS = {
    "sell", "offerservice", "seekwork", "offerride", "deliverparcel",
    "offerrental", "offerappointment",
}
_DOMAIN_BY_CATEGORY = {"product": "PRODUCT", "food": "PRODUCT", "service": "SERVICES"}


_SUBJECT_FIELDS = ("skill", "role", "jobRole", "job_role", "service", "item", "product", "cargo",
                   "speciality", "specialty", "jobType", "rentalType")
_INTENT_SUBJECT = {
    "sendparcel": "parcel delivery", "deliverparcel": "parcel delivery", "needride": "ride",
    "offerride": "ride", "seekwork": "job", "needworker": "worker", "bookappointment": "appointment",
}


def _fill_subject(payload: UniversalDealCreateRequest) -> None:
    """A requirement whose "what" lives in a detail field (a job seeker's
    skill, a parcel's item) still has a subject -- never a 422 that the app
    shows as "Matching is unavailable right now"."""
    if _present(payload.subject):
        return
    fields = dict(payload.dynamic_fields or {})
    for key in _SUBJECT_FIELDS:
        if _present(fields.get(key)):
            payload.subject = str(fields[key]).strip()
            return
    intent = str(payload.intent or "").replace("_", "").lower()
    if intent in _INTENT_SUBJECT:
        payload.subject = _INTENT_SUBJECT[intent]


# Videos/reviews are shown only when the customer asks for them.
_VIDEO_ASK = re.compile(r"\b(videos?|reviews?|review|youtube|compare|comparison|vs|unboxing|demo|how to)\b",
                        re.IGNORECASE)
# The same ask in Telugu (and common Hindi): video, review, comparison, demo.
_VIDEO_ASK_LOCAL = re.compile(r"(వీడియో|విడియో|రివ్యూ|రివ్యు|సమీక్ష|పోలిక|యూట్యూబ్|డెమో|वीडियो|रिव्यू|समीक्षा)")


_VIDEO_WORDS = re.compile(r"\b(review|reviews|video|videos|youtube|unboxing|demo|clips?)\b|"
                          r"(వీడియో|విడియో|రివ్యూ|రివ్యు|సమీక్ష|यूट्यूब|वीडियो|रिव्यू|समीक्षा)", re.IGNORECASE)


def _without_video_words(subject: str) -> str:
    """"Samsung TV review videos" searches for the TV (videos are shown
    because the customer asked; the thing searched is the TV)."""
    cleaned = " ".join(_VIDEO_WORDS.sub(" ", subject).split())
    return cleaned or subject


# Words that name WHICH KIND of results the customer wants (videos, online
# links, offers, places near them) -- never what is searched. "chicken
# biryani videos, restaurants, online links and offers" searches for
# "chicken biryani" and asks for four result groups. Any language listed;
# the subject is never emptied by this.
_RESULT_GROUP_WORDS = {
    "videos": re.compile(r"\b(videos?|youtube|reels?|reviews?|unboxing|demo|clips?)\b|"
                         r"(వీడియో\S*|విడియో\S*|రివ్యూ\S*|యూట్యూబ్|रिव्यू|वीडियो|यूट्यूब)", re.IGNORECASE),
    "online": re.compile(r"\b(online( links?| stores?| shops?| sites?)?|links?|websites?|web ?sites?|sites?|"
                         r"e-?commerce)\b|(ఆన్\s*లైన్\S*|ఆన్‌లైన్\S*|లింక్\S*|वेबसाइट|ऑनलाइन|लिंक)", re.IGNORECASE),
    "deals": re.compile(r"\b(offers?|deals?|discounts?|coupons?|cashback|sale)\b|"
                        r"(ఆఫర్\S*|డీల్\S*|డిస్కౌంట్\S*|తగ్గింపు\S*|ऑफ़र|ऑफर|डील|छूट)", re.IGNORECASE),
    "local": re.compile(r"\b(restaurants?|hotels?|shops?|stores?|showrooms?|outlets?|near ?me|nearby|"
                        r"local (shops?|stores?|places?))\b|(రెస్టారెంట్\S*|హోటల్\S*|షాప్\S*|షాపు\S*|"
                        r"దుకాణ\S*|దగ్గర\S*|నా దగ్గర|రेस्टोरेंट|दुकान|पास में)", re.IGNORECASE),
}
_LIST_GLUE = re.compile(r"(\s*[,&/+]\s*|\s+(and|or|with|plus)\s+|\s+(మరియు|ఇంకా)\s+|\s+(और|या)\s+)", re.IGNORECASE)
_SHOW_WORDS = re.compile(r"\b(show( me)?|find|search|get|give( me)?|list)\b|"
                         r"(చూపించు\S*|చూపండి|చూపు|వెతుకు\S*|दिखाओ|दिखाइए)", re.IGNORECASE)


def group_counts(matches: list[dict]) -> dict[str, int]:
    """How many returned rows fall in each result group the app shows."""
    counts = {"local": 0, "deals": 0, "online": 0, "videos": 0}
    for item in matches:
        source = str(item.get("match_source") or item.get("source") or "").lower()
        segment = str(item.get("segment") or "").lower()
        if source == "video":
            counts["videos"] += 1
        elif segment in {"deals", "used", "surplus"}:
            counts["deals"] += 1
        elif source in {"online"}:
            counts["online"] += 1
        else:
            counts["local"] += 1
    return counts


def _group_hits(text: str) -> tuple[list[str], str]:
    """Groups named in the text, checked in order with each match removed
    ("online stores" is the online group, not local stores)."""
    rest, groups = f" {text or ''} ", []
    for group, rx in _RESULT_GROUP_WORDS.items():
        if rx.search(rest):
            groups.append(group)
            rest = rx.sub(" ", rest)
    return groups, rest


def _trailing_group_strip(text: str) -> tuple[list[str], str]:
    """Only group words at the END ("TV deals", "biryani videos")."""
    words, groups = str(text or "").split(), []
    while len(words) > 1:
        hit = next((g for g, rx in _RESULT_GROUP_WORDS.items() if rx.fullmatch(words[-1])), None)
        if hit is None and _SHOW_WORDS.fullmatch(words[-1]):
            words.pop()
            continue
        if hit is None:
            break
        groups.append(hit)
        words.pop()
    return list(dict.fromkeys(reversed(groups))), " ".join(words)


def requested_result_groups(text: str) -> list[str]:
    """Which result groups the customer named, e.g. ["videos", "local",
    "online", "deals"]. A list of two or more, or group words closing the
    request; "offer letter format" names no group."""
    groups, _ = _group_hits(text)
    if len(groups) >= 2:
        return groups
    return _trailing_group_strip(text)[0]


def _without_result_group_words(subject: str) -> str:
    """The thing searched, without the words that only name result groups."""
    groups, rest = _group_hits(subject)
    if len(groups) >= 2:
        cleaned = _SHOW_WORDS.sub(" ", rest)
    else:
        cleaned = _trailing_group_strip(subject)[1]
    cleaned = _LIST_GLUE.sub(" ", f" {cleaned} ")
    words = cleaned.replace(",", " ").split()
    glue = {"and", "or", "with", "plus", "మరియు", "ఇంకా", "और", "या", "&"}
    while words and words[-1].casefold() in glue:
        words.pop()
    while words and words[0].casefold() in glue:
        words.pop(0)
    cleaned = " ".join(words).strip(" ,.&/-")
    return cleaned or subject


def _subject_with_brand(subject: str, constraints: dict) -> str:
    """The brand the customer chose is part of WHAT is searched ("Tata car",
    not the earlier "Maruti 800") -- slots never sit unused beside the query."""
    brand = next((str(constraints.get(k)).strip() for k in ("brand", "make") if _present(constraints.get(k))), "")
    if not brand or brand.casefold() in {"any", "no preference", "none", "any brand"}:
        return subject
    if brand.casefold() in subject.casefold():
        return subject
    # Drop another brand's model that the new brand replaces.
    model = str(constraints.get("model") or "")
    if model and brand.casefold() not in model.casefold():
        constraints.pop("model", None)
        subject = " ".join(w for w in subject.split() if w.casefold() not in model.casefold().split()) or subject
    return f"{brand} {subject}".strip()


def _structured_demand(user_id: str, payload: UniversalDealCreateRequest) -> dict:
    """The app's already-complete deal as a universal demand record."""
    location = dict(payload.location or {})
    intent = str(payload.intent or "").replace("_", "").lower()
    category = str(payload.category or "").strip().lower()
    constraints = {
        key: value
        for key, value in {
            **dict(payload.dynamic_fields or {}),
            "fulfilment": payload.fulfilment,
            "quality": payload.quality,
            "variant": payload.variant,
            "size": payload.size,
            "weight": payload.weight,
            "model": payload.model,
            "availability": payload.availability,
        }.items()
        if _present(value)
    }
    radius = location.get("radius_km")
    if _present(radius):
        constraints.setdefault("radius_km", radius)
    # The customer's OWN words: the app sends a rewritten raw_text ("i want
    # to buy chicken biryani in Vijayawada") and keeps what they actually
    # typed/said in trace.query -- "videos / offers / online links" live only
    # there (APK 1285: no Videos group on the signed-in path).
    said = " ".join(
        part for part in (str(payload.raw_text or ""),
                          str((getattr(payload, "trace", None) or {}).get("query") or "")[:500])
        if part.strip())
    if _VIDEO_ASK.search(said) or _VIDEO_ASK_LOCAL.search(said):
        constraints["wants_videos"] = True
    # Every result group the customer named is produced -- one request can
    # ask for videos AND places AND online links AND offers.
    # Groups the app remembered for this request (asked in an earlier turn)
    # stay requested while the customer answers follow-up questions.
    remembered = constraints.get("requested_groups")
    groups: list[str] = [str(g) for g in remembered if str(g).strip()] if isinstance(remembered, list) else []
    for text in (str(payload.raw_text or ""), str((getattr(payload, "trace", None) or {}).get("query") or "")[:500],
                 str(payload.subject or "")):
        groups += [g for g in requested_result_groups(text) if g not in groups]
    if groups:
        constraints["requested_groups"] = groups
        if "videos" in groups:
            constraints["wants_videos"] = True
    # Online / local / both, from the user's own words anywhere in the
    # message (a later statement replaces an earlier one; nothing said keeps
    # what the app remembered for this request).
    from app.services.channel_preference import detect as detect_channel
    channel = detect_channel(said)
    if channel:
        constraints["channel"] = channel
    elif str(constraints.get("channel") or "") not in ("online", "local"):
        constraints.pop("channel", None)
    # The conversation language (Revenue Center breakdown only).
    language = str((getattr(payload, "trace", None) or {}).get("language") or "").strip()[:8]
    if language:
        constraints["language"] = language
    # The specific category the app/AI detected (events, analytics, insights
    # use it instead of the coarse PRODUCT / SERVICES routing domain).
    from app.services.category_signal import detect

    detected, sub = detect(constraints=constraints, category=payload.category,
                           trace=getattr(payload, "trace", None) or {}, subject=payload.subject)
    if detected:
        constraints.setdefault("category_detected", detected)
    if sub:
        constraints.setdefault("subcategory_detected", sub)
    return {
        "user_id": user_id,
        "side": "OFFER" if intent in _SUPPLY_INTENTS else "NEED",
        "domain": _DOMAIN_BY_CATEGORY.get(category, category.upper() or "PRODUCT"),
        "subject": _subject_with_brand(
            _without_video_words(_without_result_group_words(str(payload.subject).strip())), constraints),
        "quantity": payload.quantity,
        "unit": payload.unit,
        "price": payload.price,
        "when_text": payload.timing,
        "latitude": location.get("latitude"),
        "longitude": location.get("longitude"),
        "location_text": location.get("label"),
        "constraints": constraints,
        "raw_text": str(payload.raw_text or "")[:500],
        # The customer's own words (orchestration ranks videos by them).
        "said": str((getattr(payload, "trace", None) or {}).get("query") or "")[:300],
        "source": "app",
    }


def _resolve_typed_places(container, demand: dict) -> None:
    """A TYPED place gets a real map point (Geocoding) so nearby ranking,
    routes and the nearest junction work like a map pin: the request's own
    location, and a ride / parcel pickup ("from") and drop ("to"). Never
    overrides coordinates the app already sent; never invents a point."""
    maps = getattr(container, "google_maps_service", None)
    if maps is None or not getattr(maps, "enabled", False):
        return
    from app.api.routes.discover import find_junction, geocode_text

    constraints = demand.setdefault("constraints", {})
    resolved = {}
    text = str(demand.get("location_text") or "").strip()
    if text and (demand.get("latitude") is None or demand.get("longitude") is None):
        hit = geocode_text(maps, text)
        if hit.get("status") == "ok":
            demand["latitude"], demand["longitude"] = hit["point"]["latitude"], hit["point"]["longitude"]
            resolved["location"] = "geocoded"
    for end in ("from", "to"):
        place = str(constraints.get(end) or constraints.get(f"{end}_location") or "").strip()
        if not place or constraints.get(f"{end}_lat") is not None:
            continue
        hit = geocode_text(maps, place)
        if hit.get("status") != "ok":
            resolved[end] = hit.get("status")
            continue
        point = hit["point"]
        constraints[f"{end}_lat"], constraints[f"{end}_lng"] = point["latitude"], point["longitude"]
        junction = find_junction(maps, point["latitude"], point["longitude"]).get("junction")
        if junction:
            constraints[f"{end}_landmark"] = junction["name"]
        resolved[end] = "geocoded"
    if resolved:
        constraints["places_resolved"] = resolved


def _web_search(container):
    """The web-search CHAIN (Brave, then fallbacks). A test or caller that
    replaced ``brave_web_search_provider`` alone gets that provider."""
    brave = getattr(container, "brave_web_search_provider", None)
    chain = getattr(container, "web_search_chain", None)
    if chain is None or brave is None or getattr(chain, "primary", None) is not brave:
        return brave
    return chain


def _multi_source_service(container) -> UniversalMultiSourceResultService:
    maps = getattr(container, "google_maps_service", None)
    if maps is None:
        # Lazy: google_maps_service needs httpx, which lightweight route
        # imports (e.g. the demo-isolation CI check) do not install.
        from app.services.google_maps_service import GoogleMapsService

        maps = GoogleMapsService(api_key=getattr(container.settings, "google_maps_api_key", ""))
        container.google_maps_service = maps
    service = UniversalMultiSourceResultService(
        catalog=getattr(container, "product_catalog_repository", None),
        ranking=getattr(container, "product_match_ranking_service", None),
        seller_profiles=getattr(container, "seller_profile_repository", None),
        maps=maps,
        web_search=_web_search(container),
    )
    try:
        from app.services.self_healing import engine

        service.bypassed = engine(container).bypassed_sources()
    except Exception:
        pass  # self-healing never breaks discovery
    return service


def _review_summary(container, user_id: str) -> dict:
    repository = getattr(container, "universal_review_repository", None)
    summary = getattr(repository, "summary_for_user", None)
    if not callable(summary):
        return {}
    try:
        return dict(summary(user_id))
    except Exception:  # a reviews read must never break matching
        return {}


@router.post("")
def create_deal(payload: UniversalDealCreateRequest, request: Request) -> dict:
    container = request.app.state.container
    user_id = _matching_app_user(payload.user_id, _authenticated_app_user(request))
    _prepare_askodox_app_identity(container, user_id)
    intent_context = _intent_context(
        payload,
        extractor=getattr(container, "universal_request_extractor", None),
    )

    before = _latest_created_deal(container, user_id)
    _fill_subject(payload)
    if _app_structured_requirement(payload):
        # 2026-09-27 (universal engine): the app already understood the need
        # (AI + requirement state, from text, voice, photo or file) and sent
        # it structured. Persist THAT -- for every category, including
        # services and categories the keyword router has never seen -- and
        # dispatch it to matching providers. Re-parsing it through the
        # WhatsApp-era text pipeline dropped most natural requests ("I want a
        # 43 inch battery TV", "I need a plumber") and could misread a buyer
        # as a seller.
        live_capture = getattr(container, "universal_live_capture_service", None)
        persist = getattr(live_capture, "persist_app_requirement", None)
        demand = _structured_demand(user_id, payload)
        stored = persist(user_id, demand) if callable(persist) else None
        if stored is None:
            demand_id = container.universal_demand_repository.create(demand)
            stored = container.universal_demand_repository.get(demand_id) or {**demand, "id": demand_id}
        _trace_request(container, f"deal:{stored['id']}", payload, user_id, deal_id=int(stored["id"]))
        # Real in-app leads to matching registered providers (catering staff,
        # plumbers, sellers...): a saved need is also a sent need.
        from app.services.app_demand_broadcast import broadcast_need

        broadcast = broadcast_need(container, stored)
        _trace_stage(container, int(stored["id"]), broadcast=broadcast)
        from app.api.routes.platform import journey_event
        from app.services.demand_insights import budget_band

        journey_event(container, "request", category=str(stored.get("domain") or ""),
                      location=str(stored.get("location_text") or ""),
                      detail={"subject": str(stored.get("subject") or "")[:120],
                              "budget_band": budget_band(stored.get("price")),
                              "providers_notified": int((broadcast or {}).get("sent") or 0)})
        _remember(container, user_id, stored)
        response = _deal_response(stored, "", intent_context)
        response["broadcast"] = broadcast
        return response
    reply = container.conversation_service.process(
        sender_mobile=user_id,
        message=" ".join(payload.raw_text.strip().split()),
    )
    created = _latest_created_deal(container, user_id)
    if not _deal_progressed(before, created):
        # Conversation OS owns the in-app reply, while the /deals contract also
        # requires a persisted universal demand for matching and later retrieval.
        # Use the existing live-capture pipeline only when the conversational
        # path did not create or update that demand.
        live_capture = getattr(container, "universal_live_capture_service", None)
        process_text = getattr(live_capture, "process_text", None)
        if callable(process_text):
            capture_reply = process_text(user_id, payload.raw_text)
            if capture_reply:
                reply = capture_reply
            created = _latest_created_deal(container, user_id)
    if (
        not _deal_progressed(before, created)
        and intent_context is not None
        and not intent_context["missing_fields"]
        and _present(payload.subject)
    ):
        # 2026-09-25 (Build 1236): the WhatsApp-era conversation pipeline can
        # misread a complete in-app buy request (e.g. treat "I want to buy
        # 1 kg chicken in Vijayawada" as seller onboarding) and save nothing,
        # which left the app with a 422 and no result cards. The app already
        # sent the structured, complete requirement, so persist it directly.
        container.universal_demand_repository.create(_structured_demand(user_id, payload))
        created = _latest_created_deal(container, user_id)
    if not _deal_progressed(before, created):
        headers = None
        if intent_context is not None:
            headers = {
                "X-ASKODOX-Intent-Domain": str(intent_context["domain"]),
                "X-ASKODOX-Intent-Action": str(intent_context["action"]),
                "X-ASKODOX-Missing-Fields": ",".join(intent_context["missing_fields"]),
            }
        raise HTTPException(
            status_code=422,
            detail="ASKODOX understood the message but the requirement is not ready to publish yet",
            headers=headers,
        )

    _remember(container, user_id, created)
    return _deal_response(created, reply, intent_context)


def _remember(container, user_id: str, demand: dict) -> None:
    """Conversation -> profile memory (private; the person controls it in
    Profile). Never breaks the request."""
    try:
        from app.services.profile_memory import record_from_demand

        record_from_demand(container.settings.database_path, user_id, dict(demand or {}))
    except Exception:
        pass


def _app_structured_requirement(payload: UniversalDealCreateRequest) -> bool:
    """The app sends its understood requirement with an intent and subject;
    raw-text-only callers (legacy clients) keep the text pipeline."""
    return _present(payload.subject) and _present(payload.intent)


def _deal_response(created, reply, intent_context) -> dict:
    item = dict(created)
    deal_id = int(item["id"])
    readiness = _readiness(item, intent_context)
    return {
        "id": deal_id,
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "status": item.get("status"),
        "side": item.get("side"),
        "domain": item.get("domain"),
        "subject": item.get("subject"),
        "reply": reply,
        "intent_context": intent_context,
        "readiness": readiness,
    }


@router.post("/discover")
def discover_results(payload: UniversalDealCreateRequest, request: Request) -> dict:
    """Browse real results WITHOUT signing in: the same universal discovery
    pipeline as signed-in matches, but nothing is saved to anyone's account.
    Identity is required only to act (send a request/order, contact a
    seller) -- never to view results, photos, prices or links."""
    container = request.app.state.container
    from app.services import rate_limit

    rate_limit.check(request, "discover", limit=40)
    _fill_subject(payload)
    if not _present(payload.subject):
        import uuid as _uuid

        _trace_request(container, f"browse:{_uuid.uuid4().hex[:16]}", payload, "",
                       auth_gate="rejected: no subject (422)")
        raise HTTPException(status_code=422, detail="Tell ASKODOX what you are looking for")
    try:
        viewer = _authenticated_app_user(request)
    except HTTPException:
        viewer = ""  # a guest or an expired session may still browse
    demand = _structured_demand(viewer or "guest", payload)
    import uuid as _uuid

    trace_key = f"browse:{_uuid.uuid4().hex[:16]}"
    gate = "" if viewer else "guest browsing (no sign-in needed to view results)"
    _trace_request(container, trace_key, payload, viewer, auth_gate=gate)
    discovered = _discover(container, demand, trace_key=trace_key)
    _trace_results(container, trace_key, discovered)
    matches = discovered["matches"]
    advisor = _advisor_for(container, demand, payload)
    return {
        "deal_id": None,
        "contract_version": 1,
        "local_match_count": discovered["local_match_count"],
        "segments": sorted({str(item.get("segment")) for item in matches if item.get("segment")}),
        "source_status": discovered["source_status"],
        "scope": discovered.get("scope") or {},
        "advice": discovered.get("advice") or [],
        "next_actions": discovered.get("next_actions") or [],
        "matches": matches,
        # Evidence for mixed requests: what was asked vs what came back.
        "requested_groups": list((demand.get("constraints") or {}).get("requested_groups") or []),
        # Rows removed by an explicit strict budget, with the reason.
        "rejected": discovered.get("rejected") or [],
        "group_counts": group_counts(matches),
        # Which approved marketplaces were searched and what each returned.
        "marketplaces": discovered.get("marketplaces") or {},
        # Universal Advisor: decision-relevant questions still open (each
        # field tracked separately), readiness and trade-off guidance.
        "advisor": advisor,
        "trace_key": trace_key,
        "requires_sign_in_for": ["send_request", "contact_seller"],
        # The ONE canonical result contract (sections, preserved constraints,
        # honest answer) -- every client renders from this.
        **_result_contract(container, demand, discovered, advisor, trace_key),
    }


def _advisor_for(container, demand: dict, payload) -> dict:
    from app.api.routes.demand_advisor import advisor_view, maybe_run_instant_rules, wants_results_now

    trace = dict(payload.trace or {}) if getattr(payload, "trace", None) else {}
    dynamic = dict(payload.dynamic_fields or {})
    language = str(trace.get("language") or (demand.get("constraints") or {}).get("language") or "en")
    said = f"{trace.get('query') or ''} {payload.raw_text or ''}"
    view = advisor_view(container, {**demand, "trace": trace}, language=language,
                        asked=list(dynamic.get("advisor_asked") or []), show_now=wants_results_now(said))
    maybe_run_instant_rules(container)
    return view


class TraceEventRequest(BaseModel):
    trace_key: str = Field(min_length=6, max_length=64)
    event: str = Field(min_length=2, max_length=40)
    detail: dict = Field(default_factory=dict)


_TRACE_EVENTS = {"result_selected", "action_attempted", "action_result", "location_failure", "auth_required",
                 "search_failed", "auth_resumed", "attachment_failed"}


@router.post("/trace-event")
def trace_event(payload: TraceEventRequest, request: Request) -> dict:
    """The app reports what happened AFTER results (which result the
    customer picked, the action tried and whether the request/order was
    created, a location or sign-in failure) onto the same admin trace.
    Only existing traces are updated; values are short, sanitized text."""
    container = request.app.state.container
    from app.services import rate_limit

    rate_limit.check(request, "trace_event", limit=60)
    if payload.event not in _TRACE_EVENTS or not re.fullmatch(r"(browse|deal):[A-Za-z0-9_-]+", payload.trace_key):
        raise HTTPException(status_code=422, detail="Unknown trace event")
    detail = {
        str(k)[:30]: (v if isinstance(v, (int, float, bool)) else str(v)[:160])
        for k, v in list(payload.detail.items())[:8]
        if str(k).lower() not in {"phone", "token", "password", "otp", "authorization"}
    }
    try:
        from app.api.routes.command_center import command_center

        recorded = command_center(container).trace_event(payload.trace_key, {"event": payload.event, **detail})
    except Exception:
        recorded = False
    return {"recorded": recorded}


@router.get("/leads")
def provider_leads(request: Request) -> dict:
    """Requests ASKODOX sent to this registered provider (in-app leads).

    The requester's identity/contact is never included: it is shared only
    after the requester accepts the provider's interest (consent rule).
    """
    container = request.app.state.container
    provider = _authenticated_app_user(request)
    rows = container.database.fetchall(
        """
        SELECT n.request_id, n.lead_message, n.created_at, n.status AS lead_status,
               d.subject, d.domain, d.location_text, d.when_text, d.quantity, d.unit, d.price, d.status,
               (SELECT responder_status FROM universal_interests i
                WHERE i.request_id=n.request_id AND i.responder_user_id=n.target_user_id) AS my_response
        FROM universal_notifications n
        JOIN universal_need_offer_records d ON d.id = n.request_id
        WHERE n.target_user_id=? AND UPPER(COALESCE(d.status,'ACTIVE'))='ACTIVE'
        ORDER BY n.id DESC
        LIMIT 100
        """,
        (provider,),
    )
    return {"leads": [dict(row) for row in rows], "count": len(rows)}


@router.post("/{deal_id}/interest")
def provider_interest(deal_id: int, request: Request) -> dict:
    """A targeted provider says "I can do this" -> the requester sees the
    interest in their results and decides (existing consent flow)."""
    container = request.app.state.container
    provider = _authenticated_app_user(request)
    demand = container.universal_demand_repository.get(deal_id)
    if not demand or str(demand.get("status") or "ACTIVE").upper() != "ACTIVE":
        raise HTTPException(status_code=404, detail="active request not found")
    if str(demand.get("user_id") or "") == provider:
        raise HTTPException(status_code=409, detail="this is your own request")
    notifications = container.universal_notification_repository
    if not notifications.was_targeted(deal_id, provider):
        raise HTTPException(status_code=403, detail="this request was not sent to you")
    result = container.universal_notification_service.register_interest(demand, provider)
    _trace_stage(container, deal_id, stage="provider_interested",
                 seller_request={"provider": mask_user_id(provider), "status": "INTERESTED"})
    from app.api.routes.platform import journey_event

    journey_event(container, "seller_accept", category=str(demand.get("domain") or ""),
                  location=str(demand.get("location_text") or ""),
                  detail={"kind": "lead_interest", "subject": str(demand.get("subject") or "")[:120]})
    return {"deal_id": deal_id, "status": "INTERESTED", "result": result}


def _trace_stage(container, deal_id: int, *, stage: str | None = None, **fields) -> None:
    try:
        from app.api.routes.command_center import command_center

        command_center(container).trace_upsert(f"deal:{int(deal_id)}", deal_id=int(deal_id), stage=stage, **fields)
    except Exception:
        pass  # tracing never breaks the customer flow


@router.get("/{deal_id}/matches")
def get_matches(deal_id: int, request: Request) -> dict:
    container = request.app.state.container
    demand = container.universal_demand_repository.get(deal_id)
    if not demand:
        raise HTTPException(status_code=404, detail="deal not found")

    # 2026-09-16 (round 15): before this, anyone who knew a deal_id could
    # see who was interested in it -- no identity check of any kind. Fixed
    # the same way accept_match was fixed in round 13: the caller's own
    # proven token identity must equal the deal's recorded owner. 403
    # (not a 404-masking response) to stay consistent with accept_match's
    # choice in this same file.
    demand_owner = _app_user(str(demand.get("user_id") or ""))
    authenticated_user = _authenticated_app_user(request)
    if authenticated_user != demand_owner:
        raise HTTPException(status_code=403, detail="Only this deal's owner can view its matches")

    rows = container.database.fetchall(
        """
        SELECT i.responder_user_id,i.qualification_status,i.responder_status,
               i.requester_status,i.created_at,
               n.distance_km,n.relevance_score
        FROM universal_interests i
        LEFT JOIN universal_notifications n
          ON n.request_id=i.request_id AND n.target_user_id=i.responder_user_id
        WHERE i.request_id=?
          AND i.responder_status='INTERESTED'
          AND i.requester_status='PENDING'
        ORDER BY COALESCE(n.relevance_score,0) DESC, i.id DESC
        LIMIT 100
        """,
        (deal_id,),
    )

    matches = []
    existing_ids: set[str] = set()
    for row in rows:
        item = dict(row)
        responder = str(item.get("responder_user_id") or "")
        if not responder:
            continue
        existing_ids.add(responder)
        score = item.get("relevance_score")
        if score is not None:
            score = float(score)
            if score > 1:
                score = score / 100.0
        matches.append(
            {
                "id": responder,
                "match_id": responder,
                "provider_id": responder,
                "title": "Interested match",
                "subtitle": str(item.get("qualification_status") or "Ready to connect"),
                "score": score,
                "distance_km": item.get("distance_km"),
                "price": None,
                "match_source": "interest",
                "demo": False,
                **_review_summary(container, responder),
            }
        )

    matches.extend(_demo_discovery_matches(container, demand, existing_ids))

    primary_count = len(matches)
    discovered = _discover(container, demand, matches, trace_key=f"deal:{deal_id}")
    matches = discovered["matches"]
    local_match_count = discovered["local_match_count"]
    source_status = discovered["source_status"]
    fallback = discovered["fallback_rows"]
    _record_discovery(container, discovered["flags"], demand, source_status, local_match_count)
    _trace_results(container, f"deal:{deal_id}", discovered, deal_id=deal_id)
    # Signed-in requests get the SAME advisor as browsing (APK 1292: "Any"
    # ended the questions because /matches had no advisor at all).
    advisor = _advisor_for_demand(container, demand)

    return {
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "status": demand.get("status"),
        "match_count": primary_count,
        "local_match_count": local_match_count,
        "online_fallback_used": any(item.get("match_source") == "online" for item in fallback),
        "segments": sorted({str(item.get("segment")) for item in matches if item.get("segment")}),
        # Honest per-source outcome (ok / no_results / unavailable) so the
        # chat never fills a section with placeholders.
        "source_status": source_status,
        # Where local results came from, and whether the search widened.
        "scope": discovered.get("scope") or {},
        "advice": discovered.get("advice") or [],
        "next_actions": discovered.get("next_actions") or [],
        "matches": matches,
        "requested_groups": list((demand.get("constraints") or {}).get("requested_groups") or []),
        # Rows removed by an explicit strict budget, with the reason.
        "rejected": discovered.get("rejected") or [],
        "group_counts": group_counts(matches),
        "waiting_for_interest": primary_count == 0,
        "action_result": build_action_result(
            raw_status="MATCHES_AVAILABLE" if primary_count else "WAITING_FOR_INTEREST",
            request_id=deal_id,
            category=demand.get("domain"),
            side=demand.get("side"),
            channel="in_app",
            result={"match_count": primary_count},
        ).to_dict(),
        "advisor": advisor,
        **_result_contract(container, demand, discovered, advisor, f"deal:{deal_id}"),
    }


def _advisor_for_demand(container, demand: dict) -> dict:
    """The advisor for a STORED request (no app payload at hand)."""
    try:
        from app.api.routes.demand_advisor import advisor_view, wants_results_now

        constraints = demand.get("constraints") or {}
        said = f"{demand.get('raw_text') or ''}"
        return advisor_view(container, demand, language=str(constraints.get("language") or "en"),
                            asked=list(constraints.get("advisor_asked") or []), show_now=wants_results_now(said))
    except Exception:  # the advisor never blocks results
        return {"questions": [], "ready": True, "guidance": [], "field_states": {}}


def _platform(container):
    from app.api.routes.platform import platform

    return platform(container)


def _result_contract(container, demand: dict, discovered: dict, advisor: dict | None, trace_key: str) -> dict:
    """``result_orchestrator.build`` + its diagnostics stored for staff."""
    from app.services import result_orchestrator

    try:
        settings = result_orchestrator.settings_from(_platform(container))
    except Exception:
        settings = {}
    contract = result_orchestrator.build(
        discovered["matches"], demand=demand, source_status=discovered.get("source_status"),
        errors=discovered.get("errors") or (), advisor=advisor, settings=settings)
    try:
        result_orchestrator.remember(container, trace_key, demand, discovered, contract)
    except Exception:
        pass  # diagnostics never break results
    return contract


_ONLINE_CHANNEL_SOURCES = {"online", "video", "content", "sponsored"}


def _discover(container, demand: dict, matches: list[dict] | None = None, *, trace_key: str = "") -> dict:
    """The ONE universal discovery pipeline (any category): affiliate +
    ASKODOX registered + nearby/wider local + used/surplus/deals + online +
    videos, filtered by admin switches, de-duplicated across sources.

    Used by signed-in matches and by the public (no sign-in) discovery
    endpoint, so browsing results never depends on identity.
    """
    import time as _time

    from app.services import external_call_budget

    started = _time.perf_counter()
    usage_before = external_call_budget.usage_snapshot()
    _resolve_typed_places(container, demand)
    matches = list(matches or [])
    existing_ids = {str(item.get("id")) for item in matches}
    flags = _result_flags(container, demand)
    errors: list[str] = []
    affiliate_rows: list[dict] = []
    affiliate_config = getattr(container, "affiliate_provider_config", None)
    # A service request ("AC installation in Vuyyuru") wants local PROVIDERS:
    # product stores (affiliate / partner links) are never shown for it.
    from app.services.universal_multi_source_result_service import NEED_SERVICE, need_kind

    service_need = need_kind(demand) == NEED_SERVICE
    if (affiliate_config is not None and flags.get("results.affiliate", True)
            and str(demand.get("side") or "").upper() != "OFFER" and not service_need):
        category = str(demand.get("domain") or "").strip().lower()
        subject = str(demand.get("subject") or "").strip()
        providers = []
        provider_ids = set()
        for key in (category, subject):
            if key:
                for provider in affiliate_config.active_for_category(key):
                    provider_id = str(provider.get("provider_id") or provider.get("name") or "")
                    if provider_id and provider_id in provider_ids:
                        continue
                    if provider_id:
                        provider_ids.add(provider_id)
                    providers.append(provider)
        try:
            external = UniversalExternalResultService.resolve(category=category, subject=subject, providers=providers)
        except Exception as error:  # a provider failure never abandons the request
            external, _ = [], errors.append(f"affiliate:{type(error).__name__}")
        affiliate_rows = [item for item in external if item.get("id") not in existing_ids]
        matches.extend(affiliate_rows)

    # 2026-09-26: universal multi-source results. A registered ASKODOX
    # seller (or an interested party) no longer stops discovery: registered
    # listings, nearby offline shops, used / individual / surplus / deals,
    # online (normal + affiliate) and related videos are all aggregated and
    # ranked. Discovery rows never count as matches for the consent/waiting
    # state, which still tracks interested responders only.
    category = str(demand.get("domain") or "").strip()
    subject = str(demand.get("subject") or "").strip()
    discovery = _multi_source_service(container)
    # The channel the customer asked for decides which sources run: an
    # online-only ask never shows nearby shop cards, a local-only ask never
    # waits for web shops (channel_preference.py; any category).
    channel = str((demand.get("constraints") or {}).get("channel") or "")
    # Offers / used deals are fetched by the local collector but are not a
    # walk-in channel: an online ask that names offers still collects them.
    wants_deals = "deals" in ((demand.get("constraints") or {}).get("requested_groups") or [])
    local_sources_on = (channel != "online" or wants_deals) and any(
        flags.get(key, True)
        for key in ("results.registered", "results.nearby_external", "results.used", "results.surplus", "results.deals")
    )
    try:
        registered_and_external = discovery.collect(demand) if local_sources_on else []
    except Exception as error:
        registered_and_external = []
        errors.append(f"local:{type(error).__name__}")
    # Only ORGANIC online rows count: an affiliate registry row must never
    # stop the organic online search (sources add, they never replace).
    affiliate_ids = {str(item.get("id")) for item in affiliate_rows}
    has_online = any(item.get("match_source") == "online" and not item.get("affiliate")
                     and str(item.get("id")) not in affiliate_ids for item in matches)
    online_on, videos_on = flags.get("results.online", True), flags.get("results.videos", True)
    if channel == "local":
        online_on = False
    if channel == "online":
        # An explicit online ask always runs the web search (a catalog or
        # affiliate row alone is not "the online results").
        has_online = False
    try:
        fallback = (
            discovery.online_and_videos(
                category=category, subject=subject, include_online=online_on and not has_online,
                location_text=str(demand.get("location_text") or ""),
                include_videos=bool((demand.get("constraints") or {}).get("wants_videos")),
            )
            if online_on or videos_on
            else []
        )
    except Exception as error:
        fallback = []
        errors.append(f"online:{type(error).__name__}")
    filtered = dict(discovery.filtered_counts())
    seen = {str(item.get("id")) for item in matches}
    seen_urls = {_url_key(item.get("destination_url")) for item in matches} - {""}
    for item in registered_and_external + fallback:
        url_key = _url_key(item.get("destination_url"))
        if str(item.get("id")) in seen or (url_key and url_key in seen_urls):
            filtered["duplicate"] = filtered.get("duplicate", 0) + 1
            continue  # the same destination found by two sources is shown once
        if not _result_allowed(item, flags):
            filtered["source_switched_off"] = filtered.get("source_switched_off", 0) + 1
            continue
        seen.add(str(item.get("id")))
        if url_key:
            seen_urls.add(url_key)
        matches.append(item)
    # Approved marketplaces (Amazon.in / Flipkart / Meesho) and the staff
    # Affiliate Product Manager come after local + registered + normal
    # online. A catalog product shows only while eligible (enabled, not out
    # of stock, its source on); it opens through its affiliate link only
    # when commission is ACTIVE, else through its normal (organic) URL.
    catalog_sponsored: list[dict] = []
    marketplace_info: dict[str, Any] = {}
    if online_on and str(demand.get("side") or "").upper() != "OFFER" and not service_need \
            and not getattr(discovery, "_supply", False):
        try:
            marketplace_rows, catalog_sponsored, marketplace_info = _marketplace_and_catalog(
                container, demand, discovery, matches, flags)
        except Exception as error:  # a marketplace never breaks discovery
            marketplace_rows = []
            errors.append(f"marketplace:{type(error).__name__}")
        for item in marketplace_rows:
            url_key = _url_key(item.get("destination_url"))
            fallback_key = _url_key(item.get("web_fallback_url"))
            if str(item.get("id")) in seen or (url_key and url_key in seen_urls) or (
                    fallback_key and fallback_key in seen_urls):
                filtered["duplicate"] = filtered.get("duplicate", 0) + 1
                continue
            seen.add(str(item.get("id")))
            seen_urls.update(k for k in (url_key, fallback_key) if k)
            matches.append(item)
    # Staff-approved (LIVE) news / content relevant to the need: its own
    # "content" section, added -- never replacing products, local or videos.
    if flags.get("results.content", True) and not getattr(discovery, "_supply", False):
        try:
            from app.api.routes.affiliate_catalog import catalog

            for item in catalog(container).content(q=str(demand.get("subject") or ""), limit=3, subject_match=True):
                if str(item.get("id")) in seen:
                    continue
                seen.add(str(item.get("id")))
                matches.append(item)
        except Exception as error:  # content never breaks discovery
            errors.append(f"content:{type(error).__name__}")
    # Command Center Sources (approved JSON search endpoints) -- any sector,
    # priority order, each isolated: a failing source never breaks results.
    source_info: dict[str, Any] = {}
    if flags.get("results.sources", True) and str(demand.get("side") or "").upper() != "OFFER" \
            and not getattr(discovery, "_supply", False):
        try:
            source_rows, source_info = _universal_sources(container).search_rows(demand)
        except Exception as error:
            source_rows = []
            errors.append(f"sources:{type(error).__name__}")
        for item in source_rows:
            url_key = _url_key(item.get("destination_url"))
            fallback_key = _url_key(item.get("web_fallback_url"))
            if str(item.get("id")) in seen or (url_key and url_key in seen_urls) or (
                    fallback_key and fallback_key in seen_urls):
                filtered["duplicate"] = filtered.get("duplicate", 0) + 1
                continue
            if item.get("stock_status") == "OUT_OF_STOCK":
                filtered["out_of_stock"] = filtered.get("out_of_stock", 0) + 1
                continue
            seen.add(str(item.get("id")))
            seen_urls.update(k for k in (url_key, fallback_key) if k)
            matches.append(item)
    # Affiliate / partner results (Partner Hub) come AFTER ASKODOX
    # registered + nearby/local + normal online: ASKODOX stays local-first.
    partner_rows: list[dict] = []
    if flags.get("results.affiliate", True) and str(demand.get("side") or "").upper() != "OFFER" and not service_need:
        try:
            from app.api.routes.partners import partner_repo
            from app.services.affiliate_partner_service import partner_results

            partner_rows, partner_errors = partner_results(
                partner_repo(container), demand, trace_key=trace_key,
                country=str(getattr(container.settings, "search_country", "IN") or "IN"),
            )
            errors.extend(partner_errors)
        except Exception as error:  # a partner never breaks discovery
            errors.append(f"partner:{type(error).__name__}")
        for item in partner_rows:
            if str(item.get("id")) in seen:
                continue
            seen.add(str(item.get("id")))
            matches.append(item)
    # Real web videos (YouTube Data when configured, web video search):
    # trackable, embeddable only where YouTube allows, linked to the need.
    if videos_on:
        try:
            from app.api.routes.platform import enrich_discovery_videos

            enrich_discovery_videos(container, demand, matches,
                                    wants_videos=bool((demand.get("constraints") or {}).get("wants_videos")),
                                    trace_key=trace_key)
            seen.update(str(m.get("id")) for m in matches)
        except Exception as error:
            errors.append(f"web_videos:{type(error).__name__}")
    # Command Center affiliate links (disclosed, tracked) follow the Partner
    # Hub rows -- same local-first rule, never for a service need.
    platform_affiliate: list[dict] = []
    if flags.get("results.affiliate", True) and str(demand.get("side") or "").upper() != "OFFER" and not service_need:
        try:
            from app.api.routes.platform import discovery_affiliate_rows

            platform_affiliate = discovery_affiliate_rows(container, demand, trace_key=trace_key)
        except Exception as error:
            errors.append(f"affiliate_links:{type(error).__name__}")
        for item in platform_affiliate:
            url_key = _url_key(item.get("destination_url"))
            if str(item.get("id")) in seen or (url_key and url_key in seen_urls):
                continue
            seen.add(str(item.get("id")))
            if url_key:
                seen_urls.add(url_key)
            matches.append(item)
    # Reviewed Command Center videos, only when the customer asked for
    # videos/reviews (same rule as web videos). Sponsored ones wait below.
    sponsored_videos: list[dict] = []
    if videos_on and (demand.get("constraints") or {}).get("wants_videos"):
        try:
            from app.api.routes.platform import discovery_video_rows

            for item in discovery_video_rows(container, demand):
                # Videos keep their query (?v=...): two different videos on
                # the same host must never collapse into one.
                url_key = str(item.get("url") or item.get("destination_url") or "").strip().split("#", 1)[0]
                if str(item.get("id")) in seen or (url_key and url_key in seen_urls):
                    continue
                seen.add(str(item.get("id")))
                if url_key:
                    seen_urls.add(url_key)
                (sponsored_videos if item.get("sponsored") else matches).append(item)
        except Exception as error:
            errors.append(f"videos:{type(error).__name__}")
    # Sponsored campaigns (Command Center): paid placements are appended in
    # their own labelled section AFTER every organic row -- they never enter
    # or reorder the organic ranking, and are served only when targeted.
    sponsored_rows: list[dict] = []
    organic_count = len(matches)
    if flags.get("results.sponsored", True):
        try:
            from app.api.routes.sponsored import sponsored_results

            sponsored_rows = [row for row in sponsored_results(container, demand) if str(row.get("id")) not in seen]
        except Exception as error:  # an ad never breaks discovery
            errors.append(f"sponsored:{type(error).__name__}")
        matches.extend(sponsored_rows)
    # Sponsored videos are paid placements too: after every organic row.
    sponsored_rows = sponsored_rows + sponsored_videos + catalog_sponsored
    matches.extend(sponsored_videos)
    matches.extend(catalog_sponsored)
    try:
        from app.api.routes.sponsored import sponsored_repo

        sponsored_repo(container).tally_search(organic=organic_count, sponsored=len(sponsored_rows))
    except Exception:
        pass
    try:
        from app.api.routes.partners import partner_repo

        constraints = demand.get("constraints") or {}
        from app.services.category_signal import for_demand

        partner_repo(container).record_event(
            "search", trace_key=trace_key or None, category=for_demand(demand)[0],
            subject=str(demand.get("subject") or ""), location=str(demand.get("location_text") or ""),
            language=str(constraints.get("language") or ""),
            detail={"results": len(matches), "partner_results": len(partner_rows)},
        )
    except Exception:
        pass
    _annotate_offers(container, matches)
    if channel == "online":
        # An online-only ask: registered / nearby / walk-in rows that came in
        # with the matches are not what was asked for (APK 1312).
        kept_rows = [m for m in matches if str(m.get("match_source") or "") in _ONLINE_CHANNEL_SOURCES
                     or str(m.get("segment") or "") in ("online", "affiliate", "partner", "marketplace")]
        if len(kept_rows) != len(matches):
            filtered["channel_online_only"] = filtered.get("channel_online_only", 0) + len(matches) - len(kept_rows)
        matches = kept_rows
    price_rejected: list = []
    try:
        # Budget truth: every priced row says whether it fits the budget
        # (within / within only with an offer / over / unknown). "Only
        # 40,000 or below" removes rows over budget -- a conditional offer
        # price is labelled, never shown as the normal price.
        from app.services import price_truth
        from app.services.result_orchestrator import explicit_constraints

        wanted = explicit_constraints(demand)

        def _amount(value):
            try:
                return float(str(value).replace(",", "").replace("₹", "")) if value not in (None, "") else None
            except ValueError:
                return None

        budget_max = _amount(wanted.get("budget_max") or wanted.get("budget"))
        budget_min = _amount(wanted.get("budget_min"))
        if budget_max is not None or budget_min is not None:
            said = " ".join(str(x or "") for x in (demand.get("said"), demand.get("raw_text")))
            checked = price_truth.annotate(matches, budget_max=budget_max, budget_min=budget_min,
                                           strict=price_truth.is_strict(said))
            matches, price_rejected = checked["kept"], checked["rejected"]
            if price_rejected:
                filtered["over_budget_strict"] = filtered.get("over_budget_strict", 0) + len(price_rejected)
    except Exception as error:  # price truth never breaks discovery
        errors.append(f"price_truth:{type(error).__name__}")
    try:
        # Own supply is judged against the customer's explicit constraints
        # (size / budget / brand / distance), with "why it matched".
        from app.services import supply_fit

        catalog = getattr(container, "product_catalog_repository", None)
        if catalog is not None:
            gaps = supply_fit.annotate(matches, demand, catalog.get)
            matches = supply_fit.rank_registered(matches)
            supply_fit.record_gaps(container.settings.database_path, gaps)
    except Exception as error:  # fit annotation never breaks discovery
        errors.append(f"supply_fit:{type(error).__name__}")
    _annotate_benefits(container, matches, demand, trace_key)
    try:
        from app.api.routes.platform import annotate_merchant_offers, record_search

        if flags.get("offers.merchant", True):
            annotate_merchant_offers(container, matches)
        record_search(container, demand, matches, trace_key=trace_key)
    except Exception as error:  # the platform layer never breaks discovery
        errors.append(f"platform:{type(error).__name__}")
    local_match_count = sum(
        1 for item in matches if item.get("match_source") in {"interest", "demo_discovery", "registered"}
    )
    source_status = _flagged_source_status(discovery.source_status(), flags)
    counts = {
        "registered": sum(1 for m in matches if m.get("match_source") == "registered"),
        "interest": sum(1 for m in matches if m.get("match_source") == "interest"),
        "nearby": sum(1 for m in matches if m.get("segment") in {"nearby_external", "wider_local"}),
        "online": sum(1 for m in matches if m.get("match_source") == "online" and not m.get("affiliate")
                      and m.get("segment") not in {"used", "surplus", "deals"}),
        "used_surplus_deals": sum(1 for m in matches if m.get("segment") in {"used", "surplus", "deals"}),
        "affiliate": sum(1 for m in matches if m.get("affiliate")),
        "partner": len(partner_rows),
        "sponsored": len(sponsored_rows),
        "videos": sum(1 for m in matches if m.get("match_source") == "video"),
        "marketplace": sum(1 for m in matches if m.get("marketplace")),
        "catalog": sum(1 for m in matches if m.get("origin") == "affiliate_catalog"),
    }
    if not online_on:
        fallback_decision = "online switched off by admin"
    elif has_online:
        fallback_decision = "online search skipped: online result already present"
    elif local_match_count == 0:
        fallback_decision = "no ASKODOX local match: online and nearby shown as fallback"
    else:
        fallback_decision = "local matches found; online shown alongside"
    return {
        "matches": matches,
        "fallback_rows": fallback,
        "flags": flags,
        "source_status": source_status,
        "local_match_count": local_match_count,
        "counts": counts,
        "filtered": filtered,
        "rejected": price_rejected[:30],
        "fallback_decision": fallback_decision,
        "marketplaces": marketplace_info,
        "sources": source_info,
        "errors": errors,
        "latency_ms": round((_time.perf_counter() - started) * 1000),
        "need_kind": discovery._kind,
        "scope": dict(discovery.scope or {}),
        "api_calls": _usage_delta(usage_before, external_call_budget.usage_snapshot()),
        "advice": _advice(demand, matches, discovery._kind, discovery.scope),
        "next_actions": _next_actions(local_match_count, matches, demand),
        # What location the backend actually searched with (admin trace).
        "location": {
            "label": demand.get("location_text") or None,
            "has_point": demand.get("latitude") is not None and demand.get("longitude") is not None,
            "radius_km": (demand.get("constraints") or {}).get("radius_km"),
            "failure": "no location: nearby search not run"
            if source_status.get("nearby") == "needs_location" else None,
        },
    }


_FRESH_FOOD_WORDS = {
    "chicken", "mutton", "meat", "fish", "prawn", "prawns", "egg", "eggs", "curry", "cut", "boneless", "skinless",
    "biryani", "vegetable", "vegetables", "fruit", "fruits", "milk", "fresh", "kg", "g", "gm", "grams", "litre",
    "liter", "dozen", "whole", "leg", "legs", "breast", "wings", "pieces", "piece", "country", "natu", "kodi",
    "half", "one", "two", "and", "with", "skin", "small", "medium", "large", "of", "chicken65", "tiffin", "meals",
}


def _universal_sources(container):
    from app.api.routes.affiliate_catalog import catalog
    from app.api.routes.platform import platform
    from app.services.universal_sources import UniversalSources

    pf = platform(container)
    engine = getattr(container, "universal_sources", None)
    if engine is None or engine.pf is not pf:
        engine = UniversalSources(pf, catalog(container), fetch=getattr(container, "sources_fetch", None))
        container.universal_sources = engine
    return engine


def _marketplace_and_catalog(container, demand: dict, discovery, matches: list[dict],
                             flags: dict) -> tuple[list[dict], list[dict], dict]:
    """Staff catalog products + organic marketplace rows for a product need.

    Returns (rows in display order, sponsored catalog rows, info for the trace)."""
    from app.api.routes.affiliate_catalog import catalog, sources as catalog_sources
    from app.services import affiliate_catalog as ac
    from app.services.universal_multi_source_result_service import NEED_PRODUCT

    subject = str(demand.get("subject") or "").strip()
    info: dict[str, Any] = {"catalog": 0, "searched": [], "found": {}, "status": None}
    domain = str(demand.get("domain") or "").lower()
    # Fresh food / meals / property are never marketplace-catalog needs
    # ("1 kg chicken curry cut"); "egg boiler" or "fish tank" still are.
    words = set(re.findall(r"[a-z]+", subject.lower()))
    fresh_food = bool(words) and words <= _FRESH_FOOD_WORDS
    if not subject or discovery._kind != NEED_PRODUCT or fresh_food or any(
            word in domain for word in ("food", "meat", "fish", "restaurant", "property", "real_estate")):
        info["status"] = "not_applicable"
        return [], [], info
    settings = catalog_sources(container)
    store = catalog(container)
    organic, sponsored = [], []
    for item in store.search(subject, sources=settings, limit=6):
        row = ac.result_row(item)
        if not flags.get("results.affiliate", True) and row["affiliate"]:
            # Affiliate routing switched off: the product stays, organically.
            row.update({"affiliate": False, "routing": "organic", "disclosure": "",
                        "destination_url": row["web_fallback_url"]})
        (sponsored if row["sponsored"] else organic).append(row)
    info["catalog"] = len(organic) + len(sponsored)
    constraints = demand.get("constraints") or {}
    if str(constraints.get("condition") or "").lower() == "used":
        info["status"] = "not_applicable"
        return organic, sponsored, info
    present = {str(m.get("marketplace") or "") for m in matches}
    for m in matches:
        host = ac._host(str(m.get("destination_url") or ""))
        present.add(ac.detect_platform(f"https://{host}/") if host else "")
    sites = {pid: (ac.PLATFORMS[pid]["search_host"], ac.PLATFORMS[pid]["name"])
             for pid, row in settings.items()
             if ac.PLATFORMS[pid]["search_host"] and row.get("organic_enabled") and pid not in present}
    try:  # Command Center Sources with a site_search connector join the same query
        for key, site in _universal_sources(container).site_hosts(demand).items():
            if key not in present:
                sites[key] = site
    except Exception:
        pass
    info["searched"] = sorted(sites)
    rows = discovery.fallback.marketplaces(
        category=str(demand.get("domain") or ""), subject=subject, sites=sites,
        location_text=str(demand.get("location_text") or "")) if sites else []
    info["status"] = discovery.fallback.status.get("marketplaces") if sites else "already_present"
    for pid in sites:
        found = sum(1 for r in rows if r.get("marketplace") == pid)
        info["found"][pid] = found
        try:
            if pid.startswith("src-"):
                _universal_sources(container).health.record(
                    pid[4:], ok=info["status"] not in ("error", "unavailable"), results=found,
                    error=str(info["status"] or ""))
            else:
                store.record_health(pid, status=str(info["status"] or ""), results=found, method="web_search")
        except Exception:
            pass
    return organic + rows, sponsored, info


def _annotate_benefits(container, matches: list[dict], demand: dict, trace_key: str) -> None:
    """Verified offers / coupons / cashback that apply to each result,
    computed from its real price (compact list; terms on request). Nothing
    is shown unless a campaign row exists for it."""
    try:
        from app.api.routes.benefits import benefits_repo
        from app.api.routes.partners import partner_repo
        from app.services import benefits_engine

        campaigns = benefits_repo(container).campaigns(active_only=True)
        if not campaigns:
            return
        partners = {p["slug"]: p["id"] for p in partner_repo(container).partners(active_only=True)}
        shown: set[int] = set()
        country = str(getattr(container.settings, "search_country", "IN") or "IN")
        for item in matches:
            if item.get("match_source") == "video":
                continue
            price = item.get("price")
            result = benefits_engine.evaluate(
                campaigns, price=float(price) if isinstance(price, (int, float)) else None,
                category=str(demand.get("domain") or ""),
                subject=f"{demand.get('subject') or ''} {item.get('title') or ''}",
                location=str(demand.get("location_text") or ""), country=country,
                partner_id=partners.get(str(item.get("partner_slug") or "")),
            )
            if result["offers"]:
                item["benefits"] = result
                shown.update(o["id"] for o in result["offers"])
        repo = partner_repo(container)
        for campaign_id in shown:  # one impression per campaign per search
            from app.services.category_signal import for_demand

            repo.record_event("offer_impression", trace_key=trace_key or None, campaign=f"benefit:{campaign_id}",
                              category=for_demand(demand)[0])
    except Exception:
        pass  # offers never break discovery


def _annotate_offers(container, matches: list[dict]) -> None:
    """Registered listings carry their best live offer (seller or admin
    campaign), computed from the listing's real price."""
    try:
        from app.api.routes.growth import growth
        from app.services import offers_engine

        repo = growth(container)
        catalog = container.product_catalog_repository
        for item in matches:
            if item.get("match_source") != "registered" or not str(item.get("id") or "").isdigit():
                continue
            listing = catalog.get(int(item["id"]))
            if not listing:
                continue
            best = offers_engine.best_offer(repo.offers_for_listing(listing),
                                            {"unit_price": listing.get("price") or 0, "quantity": 1})
            if best:
                item["offer"] = {"title": best["title"], "note": best["note"], "discount": best["discount"]}
    except Exception:
        pass


def _next_actions(local_match_count: int, matches: list[dict], demand: dict) -> list[str]:
    """No ASKODOX provider yet is not a dead end: contact the external
    options found, refer someone to ASKODOX, or search wider."""
    if local_match_count:
        return []
    actions = []
    if any(m.get("match_source") in {"external", "online"} for m in matches):
        actions.append("contact_external")
    actions += ["refer_provider", "find_more"]
    return actions


def _advice(demand: dict, matches: list[dict], need_kind: str, scope: dict | None) -> list[dict]:
    try:
        from app.services.advisory_service import advise

        return advise(demand, matches, need_kind=need_kind, scope=scope)
    except Exception:
        return []  # advice is optional; it never breaks results


def _usage_delta(before: dict, after: dict) -> dict:
    """Real external calls made (and cache hits) while serving this request."""
    delta: dict[str, dict[str, int]] = {}
    for provider, stats in after.items():
        prior = before.get(provider, {})
        changed = {k: v - prior.get(k, 0) for k, v in stats.items() if v - prior.get(k, 0)}
        if changed:
            delta[provider] = changed
    return delta


_NOT_RUN = (None, "not_applicable", "disabled", "unavailable")


def _trace_results(container, trace_key: str, discovered: dict, *, deal_id=None) -> None:
    """Admin flow trace: what the pipeline actually did for this request."""
    try:
        from app.api.routes.command_center import command_center

        top = [
            {"title": str(m.get("title") or "")[:80], "source": m.get("match_source"),
             "segment": m.get("segment"), "price": m.get("price"), "has_image": bool(m.get("image_url")),
             "has_link": bool(m.get("destination_url")),
             # Why it ranked here: score + the facts ranking could use.
             "rank": i + 1, "rank_score": m.get("rank_score"), "distance_km": m.get("distance_km"),
             "price_verified": m.get("price_verified")}
            for i, m in enumerate(discovered["matches"][:12])
        ]
        command_center(container).trace_upsert(
            trace_key,
            deal_id=deal_id,
            stage="results_sent" if discovered["matches"] else "no_results",
            sources=discovered["source_status"],
            source_counts=discovered["counts"],
            filtered=discovered["filtered"],
            fallback=discovered["fallback_decision"],
            # "ran" = the source was actually called; unconfigured/switched
            # off/not relevant for this kind of need are reported as not run.
            master_web=discovered["source_status"].get("online") not in _NOT_RUN,
            local_search=discovered["source_status"].get("nearby") not in _NOT_RUN,
            need_kind=discovered["need_kind"],
            geographic_scope=discovered.get("scope") or None,
            location_searched=discovered.get("location") or None,
            api_calls=discovered.get("api_calls") or {},
            advisory_decision=[a["code"] for a in discovered.get("advice") or []] or ["none_needed"],
            results_count=len(discovered["matches"]),
            results=top,
            errors=discovered["errors"],
            latency_ms=discovered["latency_ms"],
        )
    except Exception:
        pass  # tracing never breaks the customer response


_PHONE = re.compile(r"(?<!\d)(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def _redact_pii(text: str) -> str:
    """Admin traces keep what was asked, not who to call: phone numbers and
    e-mail addresses typed into the chat are masked."""
    return _EMAIL.sub("[email]", _PHONE.sub("[phone]", text))


def _query_language(text: str) -> str:
    """Script of what the customer actually said (te / hi / en / mixed)."""
    telugu = bool(re.search(r"[ఀ-౿]", text))
    hindi = bool(re.search(r"[ऀ-ॿ]", text))
    latin = bool(re.search(r"[A-Za-z]", text))
    scripts = [name for name, hit in (("te", telugu), ("hi", hindi), ("en", latin)) if hit]
    return "+".join(scripts) or "unknown"


def _trace_request(container, trace_key: str, payload, user_id: str, *, deal_id=None, auth_gate: str = "") -> None:
    """The app-side context of the request (query, AI intent, slots, the
    questions asked and answers remembered) -- sanitized, ids masked."""
    try:
        from app.api.routes.command_center import command_center
        from app.repositories.command_center_repository import mask_user_id

        client = dict(payload.trace or {}) if getattr(payload, "trace", None) else {}
        slots = {k: v for k, v in {
            "subject": payload.subject, "category": payload.category, "intent": payload.intent,
            "quantity": payload.quantity, "unit": payload.unit, "budget": payload.price, "size": payload.size,
            "model": payload.model, "variant": payload.variant, "timing": payload.timing,
            "location": (payload.location or {}).get("label") if isinstance(payload.location, dict) else None,
            **dict(payload.dynamic_fields or {}),
        }.items() if _present(v)}
        command_center(container).trace_upsert(
            trace_key,
            deal_id=deal_id,
            user=mask_user_id(user_id) if user_id else "guest",
            query=_redact_pii(str(client.get("query") or payload.raw_text or ""))[:500],
            reply_language=str(client.get("language") or "")[:8] or None,
            attachments=[{"kind": str(a.get("kind") or "")[:12], "id": str(a.get("id") or "")[:40]}
                         for a in (client.get("attachments") or []) if isinstance(a, dict)][:4] or None,
            language=_query_language(str(client.get("query") or payload.raw_text or "")),
            ui_language=str(client.get("ui_language") or "")[:8] or None,
            intent=str(client.get("intent") or payload.intent or "")[:80],
            domain=str(client.get("domain") or payload.category or "")[:40],
            categories=[str(c)[:60] for c in (client.get("categories") or [payload.subject])][:10],
            slots=slots,
            questions=[_redact_pii(str(q))[:200] for q in (client.get("questions") or [])][:20],
            answers=[_redact_pii(str(a))[:200] for a in (client.get("answers") or [])][:20],
            auth_gate=auth_gate or str(client.get("auth_gate") or "")[:120],
            active_role=str(client.get("active_role") or "")[:40],
            missing_slots=[str(m)[:40] for m in (client.get("missing_slots") or [])][:20],
            location_used=str(client.get("location_used") or "")[:160],
            stage="request_received",
        )
    except Exception:
        pass


# ---- Command Center hooks (Phases 20 / 22 / 23) ---------------------------
# Admin switches decide which result sources run; a switched-off source is
# reported as "disabled" (the chat shows nothing for it, never a fake row).

_SEGMENT_FLAGS = {
    "used": "results.used",
    "surplus": "results.surplus",
    "deals": "results.deals",
    "nearby_external": "results.nearby_external",
    "wider_local": "results.nearby_external",
}
_SOURCE_STATUS_FLAGS = {
    "askodox": ("results.registered",),
    "nearby": ("results.nearby_external",),
    "used_deals": ("results.used", "results.surplus", "results.deals"),
    "online": ("results.online",),
    "videos": ("results.videos",),
}


def _url_key(url) -> str:
    """Normalized destination for cross-source de-duplication."""
    text = str(url or "").strip().lower()
    if not text.startswith(("http://", "https://")):
        return ""
    text = text.split("#", 1)[0].split("?", 1)[0].rstrip("/")
    return text.replace("https://", "").replace("http://", "").removeprefix("www.")


def _result_flags(container, demand: dict | None = None) -> dict[str, bool]:
    """Global flags with Command Center targeting (category / role / platform /
    location / %) applied for this request."""
    try:
        from app.services import flag_targeting

        ctx = flag_targeting.context_for_demand(demand or {})
        return flag_targeting.effective(container, ctx)
    except Exception:
        try:
            from app.api.routes.command_center import command_center

            return command_center(container).flags_map()
        except Exception:
            return {}


def _result_allowed(item: dict, flags: dict[str, bool]) -> bool:
    segment = str(item.get("segment") or "")
    if segment in _SEGMENT_FLAGS:
        return flags.get(_SEGMENT_FLAGS[segment], True)
    source = str(item.get("match_source") or "")
    if source == "registered":
        return flags.get("results.registered", True)
    if source == "video":
        return flags.get("results.videos", True)
    if source == "online":
        return flags.get("results.online", True)
    return True


def _flagged_source_status(status: dict[str, str], flags: dict[str, bool]) -> dict[str, str]:
    result = dict(status)
    for source, keys in _SOURCE_STATUS_FLAGS.items():
        if not any(flags.get(key, True) for key in keys):
            result[source] = "disabled"
    return result


def _record_discovery(container, flags, demand, source_status, local_match_count) -> None:
    """Analytics + no-match queue. Never breaks the customer response."""
    try:
        from app.api.routes.command_center import command_center

        cc = command_center(container)
        cc.record_discovery(str(demand.get("id")), source_status)
        # With registered results switched off by an admin, "no local match"
        # reflects configuration, not a supply gap -- don't queue it.
        supply_gap = local_match_count == 0 and flags.get("results.registered", True)
        if supply_gap and cc.record_no_match(demand, source_status):
            if flags.get("notifications.admin", True):
                cc.notify_once(
                    f"no_match:{demand.get('id')}",
                    "no_match",
                    f"No local match: {str(demand.get('subject') or demand.get('domain') or '')[:80]}",
                    str(demand.get("id")),
                )
    except Exception:
        pass


@router.post("/{deal_id}/review")
def submit_review(deal_id: int, payload: ReviewRequest, request: Request) -> dict:
    container = request.app.state.container
    authenticated = _authenticated_app_user(request)
    demand = container.universal_demand_repository.get(deal_id)
    if not demand:
        raise HTTPException(status_code=404, detail="deal not found")
    if authenticated != _app_user(str(demand.get("user_id") or "")):
        raise HTTPException(status_code=403, detail="Only the deal owner can review it")
    interest = container.universal_notification_repository.get_interest(deal_id, payload.reviewed_user_id)
    if not interest or interest.get("qualification_status") != "CONVERTED":
        raise HTTPException(status_code=409, detail="Review is available after deal completion")
    result = container.universal_review_repository.create(
        deal_id,
        authenticated,
        payload.reviewed_user_id,
        demand.get("domain"),
        payload.rating,
        payload.review_text,
    )
    return {"request_id": deal_id, **result}


@router.post("/{deal_id}/accept-match")
def accept_match(deal_id: int, payload: AcceptMatchRequest, request: Request) -> dict:
    container = request.app.state.container
    demand = container.universal_demand_repository.get(deal_id)
    if not demand:
        raise HTTPException(status_code=404, detail="deal not found")

    # 2026-09-16 (round 13): before this, `requester` was read straight from
    # the stored deal record with no check at all on who was actually
    # calling -- anyone who knew a deal_id and a match_id could accept a
    # match *on behalf of the deal's real owner*. This is a more serious
    # bug than ordinary identity spoofing (there was no claim to check in
    # the first place); it is fixed by requiring the caller's own proven
    # token identity to match the deal's real owner before proceeding.
    demand_owner = _app_user(str(demand.get("user_id") or ""))
    authenticated_user = _authenticated_app_user(request)
    if authenticated_user != demand_owner:
        raise HTTPException(status_code=403, detail="Only this deal's owner can accept a match for it")
    requester = demand_owner
    responder = _app_user(payload.match_id)

    result = interest_action(
        InterestDecisionRequest(
            user_id=requester,
            request_id=deal_id,
            responder_user_id=responder,
            action="ACCEPT",
        ),
        request,
    )
    result = {
        **result,
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "match_id": responder,
    }
    result["action_result"] = build_action_result(
        raw_status=str(result.get("status") or "MATCH_ACCEPTED"),
        request_id=deal_id,
        category=demand.get("domain"),
        side=demand.get("side"),
        channel="in_app",
        consent={"required": True, "state": "PENDING"},
        result={"match_id": responder},
    ).to_dict()
    return result
