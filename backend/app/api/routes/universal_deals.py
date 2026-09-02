from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.debug import _prepare_askodox_app_identity
from app.api.routes.in_app_deal import InterestDecisionRequest, interest_action
from backend.app.core.default_intent_rules import build_default_intent_router
from backend.app.core.domain_field_requirements import FieldPolicyNotFoundError, missing_fields
from backend.app.core.intent_domain_router import IntentRouteNotFoundError

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


def _app_user(value: str) -> str:
    user_id = str(value or "").strip()
    if not user_id.lower().startswith("app-"):
        raise HTTPException(status_code=400, detail="ASKODOX app user_id required")
    return user_id


def _latest_created_deal(container, user_id: str):
    return container.database.fetchone(
        """
        SELECT id,user_id,side,domain,subject,quantity,unit,price,currency,
               when_text,location_text,latitude,longitude,status,created_at
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

    # Flutter's universal deal brain intentionally uses compact cross-domain keys.
    # Field policies use explicit canonical names. Preserve both without changing the
    # app model or the authoritative V2 extraction/capture pipeline.
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

    # Avoid a second AI call when Flutter already supplied every field needed by the
    # route. Only reuse the existing extractor if the preliminary policy is missing
    # something that may already be present in raw_text.
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


@router.post("")
def create_deal(payload: UniversalDealCreateRequest, request: Request) -> dict:
    """Create a universal ASKODOX requirement through the existing V2 Deal Brain.

    The app sends its normalized deal object, but V2 still runs the original natural
    request through the same conversation/extraction/capture pipeline used by other
    channels. This prevents the Flutter client from becoming a second source of
    business rules.
    """
    container = request.app.state.container
    user_id = _app_user(payload.user_id)
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
    }


@router.get("/{deal_id}/matches")
def get_matches(deal_id: int, request: Request) -> dict:
    """Return genuine opposite-party responders for a published requirement.

    Only responders who actually expressed interest are returned. Targeted users who
    have not consented are intentionally not presented as connectable matches.
    """
    container = request.app.state.container
    demand = container.universal_demand_repository.get(deal_id)
    if not demand:
        raise HTTPException(status_code=404, detail="deal not found")

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
    for row in rows:
        item = dict(row)
        responder = str(item.get("responder_user_id") or "")
        if not responder:
            continue
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
            }
        )

    return {
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "status": demand.get("status"),
        "match_count": len(matches),
        "matches": matches,
        "waiting_for_interest": len(matches) == 0,
    }


@router.post("/{deal_id}/accept-match")
def accept_match(deal_id: int, payload: AcceptMatchRequest, request: Request) -> dict:
    """Accept a responder who already opted in and open the existing in-app deal."""
    container = request.app.state.container
    demand = container.universal_demand_repository.get(deal_id)
    if not demand:
        raise HTTPException(status_code=404, detail="deal not found")
    requester = _app_user(str(demand.get("user_id") or ""))
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
    return {
        **result,
        "deal_id": deal_id,
        "request_id": deal_id,
        "contract_version": 1,
        "match_id": responder,
    }
