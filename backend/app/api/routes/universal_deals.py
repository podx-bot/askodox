from __future__ import annotations

import json

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
from app.services.universal_external_result_service import (
    UniversalExternalResultService,
    UniversalOnlineFallbackService,
)

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


class AcceptMatchRequest(BaseModel):
    match_id: str = Field(min_length=1)


class ReviewRequest(BaseModel):
    reviewed_user_id: str = Field(min_length=1)
    rating: int = Field(ge=1, le=5)
    review_text: str = Field(default="", max_length=2000)


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

    affiliate_config = getattr(container, "affiliate_provider_config", None)
    if affiliate_config is not None:
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
        external = UniversalExternalResultService.resolve(
            category=category,
            subject=subject,
            providers=providers,
        )
        matches.extend(
            item for item in external
            if item.get("id") not in existing_ids
        )

    # 2026-09-25: unified chat results. When no genuine (non-demo) local
    # party has responded and no configured online partner covers this
    # request, fall back to real online results instead of an empty chat.
    # Relevant videos ride along for categories where they make sense.
    # Fallback rows never count as matches for the consent/waiting state.
    category = str(demand.get("domain") or "").strip()
    subject = str(demand.get("subject") or "").strip()
    local_match_count = sum(
        1 for item in matches if item.get("match_source") in {"interest", "demo_discovery"}
    )
    genuine_local = any(item.get("match_source") == "interest" for item in matches)
    has_online = any(item.get("match_source") == "online" for item in matches)
    fallback_service = UniversalOnlineFallbackService(
        getattr(container, "brave_web_search_provider", None)
    )
    fallback: list[dict] = []
    if not genuine_local and not has_online:
        fallback.extend(fallback_service.online(category=category, subject=subject))
    fallback.extend(fallback_service.videos(category=category, subject=subject))
    primary_count = len(matches)
    matches.extend(fallback)

    return {
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "status": demand.get("status"),
        "match_count": primary_count,
        "local_match_count": local_match_count,
        "online_fallback_used": any(item.get("match_source") == "online" for item in fallback),
        "matches": matches,
        "waiting_for_interest": primary_count == 0,
        "action_result": build_action_result(
            raw_status="MATCHES_AVAILABLE" if primary_count else "WAITING_FOR_INTEREST",
            request_id=deal_id,
            category=demand.get("domain"),
            side=demand.get("side"),
            channel="in_app",
            result={"match_count": primary_count},
        ).to_dict(),
    }


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
