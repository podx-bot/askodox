"""Mobility + delivery API (see app/services/delivery_jobs.py) -- ONE
canonical system for rides, parcels, local / seller-order deliveries and
carpool. Not a clone of any ride app: requests are offered to APPROVED
ASKODOX partners (or a configured logistics integration) and nothing is
"confirmed" until a partner accepts.

Customer: POST /api/delivery/jobs, GET /api/delivery/jobs/mine|{id},
          POST /api/delivery/jobs/{id}/confirm|cancel, GET /api/delivery/services
Partner:  POST /api/delivery/partners/apply, GET|PATCH /api/delivery/partners/me,
          POST /api/delivery/partners/me/availability, GET /api/delivery/offers,
          GET /api/delivery/jobs/assigned,
          POST /api/delivery/jobs/{id}/accept|decline|release|status
Carpool:  POST /api/delivery/carpool/rides, GET /api/delivery/carpool/search,
          POST /api/delivery/carpool/rides/{id}/request|close,
          GET /api/delivery/carpool/mine, POST /api/delivery/carpool/requests/{id}/decide
Orders:   GET|POST /api/delivery/orders/{id}/fulfillment (responsibility +
          delivery state, separate from the order's commerce state)
Reports:  POST /api/delivery/reports
Admin:    GET /admin/cc/mobility/overview, POST /admin/cc/mobility/reports/{id},
          POST /admin/cc/mobility/carpool/{id}

Identity always comes from the session token. A partner is an ACTIVE
(approved) delivery_partners record whose user_ref is the caller. Contact
details (phones, recipient) are shown only after acceptance (Round-8 rule).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import delivery_jobs as dj
from app.services.delivery_jobs import KINDS, DeliveryError, DeliveryJobs

router = APIRouter(prefix="/api/delivery", tags=["delivery"])
admin_router = APIRouter(tags=["delivery-admin"])
_STATUS = {"not_found": 404, "not_offered": 403, "not_assigned": 403, "not_requester": 403, "not_host": 403,
           "needs_location": 422, "bad_seats": 422, "own_ride": 422}

STAGE_TEXT = {
    dj.REQUESTED: "Request saved -- not confirmed yet",
    dj.NEEDS_CONFIGURATION: "This service is switched off right now",
    dj.NEEDS_PARTNER: "No driver / partner found yet -- request saved",
    dj.PARTNER_SEARCH: "Request sent to nearby partners -- waiting for one to accept",
    dj.PARTNER_ACCEPTED: "Partner accepted",
    dj.EN_ROUTE_PICKUP: "Partner is on the way to pickup",
    dj.ARRIVED_PICKUP: "Partner arrived at pickup",
    dj.PICKED_UP: "Picked up",
    dj.IN_TRANSIT: "On the way",
    dj.ARRIVED_DROP: "Arrived at drop",
    dj.DELIVERED: "Delivered / trip finished -- please confirm",
    dj.CONFIRMED: "Completed",
    dj.CANCELLED: "Cancelled",
}


def jobs(container: Any) -> DeliveryJobs:
    j = getattr(container, "delivery_jobs", None)
    if j is None or j.db_path != container.settings.database_path:
        j = DeliveryJobs(container.settings.database_path)
        container.delivery_jobs = j
    return j


def _error(error: DeliveryError) -> HTTPException:
    return HTTPException(status_code=_STATUS.get(error.code, 409), detail={"code": error.code, "message": str(error)})


def _resources(container: Any):
    from app.api.routes.platform import platform

    return platform(container).resources


def _partners(container: Any) -> List[Dict[str, Any]]:
    return _resources(container).repo.list("delivery_partners")


def _owns(partner: Dict[str, Any], user_id: str) -> bool:
    from app.api.routes.platform import user_ref

    return (partner.get("data") or {}).get("user_ref") in (user_ref(user_id), user_id)


def _my_partner_records(container: Any, user_id: str) -> List[Dict[str, Any]]:
    return [p for p in _partners(container) if _owns(p, user_id) and not p.get("archived")]


def _my_partner_ids(container: Any, user_id: str) -> List[str]:
    return [p["id"] for p in _my_partner_records(container, user_id) if p.get("status") == "ACTIVE"]


def _phone_of(user_id: str) -> str:
    """App user ids carry the signed-in number (app-phone-91...)."""
    digits = "".join(ch for ch in str(user_id or "") if ch.isdigit())
    return "+" + digits if str(user_id or "").startswith("app-phone-") and len(digits) >= 10 else ""


def _view(container: Any, job: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """Requester: everything about their job, plus the partner's name /
    vehicle / phone once accepted. Assigned partner: the route, the job's
    details and the customer's phone once accepted. An offered (not yet
    accepted) partner: route, kind, quote and non-private details only."""
    out = dict(job)
    accepted = job.get("status") in dj.ACCEPTED_STATES
    is_requester = job.get("requester") == user_id
    is_assigned = bool(job.get("partner_user")) and job.get("partner_user") == user_id
    details = dict(job.get("details") or {})
    if not (is_requester or (is_assigned and accepted)):
        for key in dj.PRIVATE_DETAIL_KEYS:
            details.pop(key, None)
    out["details"] = details
    out["stage"] = STAGE_TEXT.get(job.get("status") or "", job.get("status") or "")
    out["confirmed_by_partner"] = accepted
    if is_requester and accepted and job.get("partner_id"):
        partner = next((p for p in _partners(container) if p["id"] == job["partner_id"]), None)
        d = (partner or {}).get("data") or {}
        out["partner"] = {"name": (partner or {}).get("name") or "", "vehicle": d.get("vehicle") or "",
                          "vehicle_number": d.get("vehicle_number") or "", "verified": bool(d.get("verified")),
                          "phone": _phone_of(job.get("partner_user") or "")}
    if is_assigned and accepted:
        out["customer_phone"] = details.get("contact_phone") or _phone_of(job.get("requester") or "")
    if not is_requester:
        out.pop("requester", None)
        out["history"] = [{k: v for k, v in h.items() if k != "by"} for h in job.get("history") or []]
    out.pop("partner_user", None)
    out.pop("declined", None)
    return out


class Point(BaseModel):
    model_config = ConfigDict(extra="forbid")
    label: str = Field(default="", max_length=160)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class Details(BaseModel):
    """What the customer tells the partner. Private keys (phones, recipient,
    private notes) reach the partner only after acceptance."""
    model_config = ConfigDict(extra="forbid")
    passengers: Optional[int] = Field(default=None, ge=1, le=60)
    vehicle_preference: str = Field(default="", max_length=40)
    item_description: str = Field(default="", max_length=200)
    parcel_size: str = Field(default="", pattern="^(|small|medium|large|xl)$")
    weight_kg: Optional[float] = Field(default=None, ge=0, le=5000)
    fragile: bool = False
    notes: str = Field(default="", max_length=300)
    return_trip: bool = False
    contact_phone: str = Field(default="", max_length=20)
    recipient_name: str = Field(default="", max_length=80)
    recipient_phone: str = Field(default="", max_length=20)
    notes_private: str = Field(default="", max_length=300)


class JobBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: str = Field(pattern="^(" + "|".join(KINDS) + ")$")
    pickup: Point
    drop: Point
    order_id: str = Field(default="", max_length=60)
    details: Details = Field(default_factory=Details)
    schedule_at: str = Field(default="", max_length=25)


def _resolve_point(container: Any, point: Point, which: str) -> Dict[str, Any]:
    """A typed place ("Benz Circle") becomes a map point through the same
    geocoder the chat uses; never a guessed coordinate."""
    data = point.model_dump()
    if data.get("latitude") is not None and data.get("longitude") is not None:
        return data
    from app.api.routes.discover import geocode_text

    hit = geocode_text(getattr(container, "google_maps_service", None), data.get("label") or "")
    if hit.get("status") != "ok" or not hit.get("point"):
        raise HTTPException(status_code=422, detail={"code": "needs_location", "message":
                            f"Could not place the {which} '{data.get('label') or ''}' on the map "
                            f"({hit.get('status')}). Pick it on the map instead."})
    p = hit["point"]
    return {"label": data.get("label") or p.get("label") or "", "latitude": p["latitude"],
            "longitude": p["longitude"]}


def _service_rule(container: Any, kind: str, label: str) -> Optional[Dict[str, Any]]:
    """The Command Center mobility_services row for this kind. Rows exist but
    none ACTIVE -> the service is switched off (409)."""
    rows = [r for r in _resources(container).repo.list("mobility_services")
            if (r.get("data") or {}).get("kind") == kind and not r.get("archived")]
    if not rows:
        return None
    live = [r for r in rows if r.get("status") == "ACTIVE"]
    if not live:
        raise HTTPException(status_code=409, detail={"code": "service_off",
                                                     "message": "This service is not offered right now."})
    place = (label or "").lower()
    town = [r for r in live if (r["data"].get("town") or "").lower() and r["data"]["town"].lower() in place]
    return (town or [r for r in live if not (r["data"].get("town") or "")] or live)[0]["data"]


@router.get("/services")
def services(request: Request) -> dict:
    """Which services are offered, and whether an estimate can be shown."""
    container = request.app.state.container
    rows = [r for r in _resources(container).repo.list("mobility_services") if not r.get("archived")]
    out = []
    for kind in KINDS:
        mine = [r for r in rows if (r.get("data") or {}).get("kind") == kind]
        off = bool(mine) and not any(r.get("status") == "ACTIVE" for r in mine)
        out.append({"kind": kind, "offered": not off, "has_rate": any(r.get("status") == "ACTIVE" for r in mine),
                    "ride": kind in dj.RIDE_KINDS})
    from app.api.routes.command_center import feature_enabled

    return {"matching_enabled": feature_enabled(container, "delivery.matching"), "items": out}


@router.post("/jobs")
def create_job(body: JobBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.platform import platform

    registry = platform(container).registry

    def ready(key: str) -> bool:
        try:
            return registry.status(key)["status"] in ("LIVE", "TEST")
        except Exception:
            return False

    pickup = _resolve_point(container, body.pickup, "pickup")
    drop = _resolve_point(container, body.drop, "drop")
    rule = _service_rule(container, body.kind, pickup.get("label") or "")
    details = {k: v for k, v in body.details.model_dump().items() if v not in ("", None, False)}
    try:
        job = jobs(container).create(requester=user, kind=body.kind, pickup=pickup, drop=drop,
                                     partners=_partners(container),
                                     matching_enabled=feature_enabled(container, "delivery.matching"),
                                     integration_ready=ready, order_id=body.order_id, details=details,
                                     schedule_at=body.schedule_at, fare_rule=rule)
    except DeliveryError as error:
        raise _error(error) from None
    return _view(container, job, user)


@router.get("/jobs/mine")
def my_jobs(request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    return {"items": [_view(container, j, user) for j in jobs(container).for_requester(user)]}


@router.get("/jobs/assigned")
def assigned_jobs(request: Request) -> dict:
    """The partner's trips (current first, then history)."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    items = [_view(container, j, user) for j in jobs(container).for_partner(user)]
    active = [j for j in items if j["status"] in dj.TRIP_PATH and j["status"] != dj.DELIVERED]
    return {"active": active, "history": [j for j in items if j not in active]}


@router.get("/jobs/{job_id}")
def get_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    job = jobs(container).get(job_id)
    mine = set(_my_partner_ids(container, user))
    if job is None or not (job["requester"] == user or job.get("partner_user") == user
                           or mine & {o["partner_id"] for o in job.get("offered") or []}):
        raise HTTPException(status_code=404, detail="Delivery not found")
    return _view(container, job, user)


@router.get("/offers")
def my_offers(request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    ids = _my_partner_ids(container, user)
    items = [j for j in jobs(container).offers_for(ids) if not set(ids) & set(j.get("declined") or [])]
    return {"partner": bool(ids), "items": [_view(container, j, user) for j in items]}


def _offered_partner(container: Any, job_id: str, user: str) -> tuple[Dict[str, Any], str]:
    job = jobs(container).get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Delivery not found")
    offered = {o["partner_id"] for o in job.get("offered") or []}
    mine = [p for p in _my_partner_ids(container, user) if p in offered]
    if not mine:
        raise HTTPException(status_code=403, detail="This delivery was not offered to you")
    return job, mine[0]


@router.post("/jobs/{job_id}/accept")
def accept_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    _, partner_id = _offered_partner(container, job_id, user)
    try:
        return _view(container, jobs(container).accept(job_id, partner_id=partner_id, partner_user=user), user)
    except DeliveryError as error:
        raise _error(error) from None


class ReasonBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str = Field(default="", max_length=200)


@router.post("/jobs/{job_id}/decline")
def decline_job(job_id: str, body: ReasonBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    _, partner_id = _offered_partner(container, job_id, user)
    try:
        jobs(container).decline(job_id, partner_id=partner_id, partner_user=user, reason=body.reason)
    except DeliveryError as error:
        raise _error(error) from None
    return {"declined": True, "id": job_id}


@router.post("/jobs/{job_id}/release")
def release_job(job_id: str, body: ReasonBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    try:
        jobs(container).release(job_id, partner_user=user, reason=body.reason)
    except DeliveryError as error:
        raise _error(error) from None
    return {"released": True, "id": job_id}


class StatusBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str = Field(pattern="^(EN_ROUTE_PICKUP|ARRIVED_PICKUP|PICKED_UP|IN_TRANSIT|ARRIVED_DROP|DELIVERED)$")


@router.post("/jobs/{job_id}/status")
def advance_job(job_id: str, body: StatusBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    try:
        return _view(container, jobs(container).advance(job_id, partner_user=user, to=body.status), user)
    except DeliveryError as error:
        raise _error(error) from None


@router.post("/jobs/{job_id}/confirm")
def confirm_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    try:
        return _view(container, jobs(container).confirm(job_id, requester=user), user)
    except DeliveryError as error:
        raise _error(error) from None


@router.post("/jobs/{job_id}/cancel")
def cancel_job(job_id: str, body: ReasonBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    try:
        return _view(container, jobs(container).cancel(job_id, requester=user, reason=body.reason), user)
    except DeliveryError as error:
        raise _error(error) from None


# ------------------------------------------------------------- partners --
PARTNER_SERVICES = ("food", "grocery", "parcel", "product", "pickup_drop", "documents", "other") + dj.RIDE_KINDS


class PartnerBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=2, max_length=80)
    services: List[str] = Field(min_length=1, max_length=len(PARTNER_SERVICES))
    vehicle: str = Field(pattern="^(walk|bicycle|two_wheeler|three_wheeler|car|van|truck|any)$")
    vehicle_number: str = Field(default="", max_length=20)
    licence_last4: str = Field(default="", pattern=r"^(|\d{4})$")
    town: str = Field(default="", max_length=80)
    radius_km: float = Field(default=5, ge=0.5, le=200)


def _partner_view(p: Dict[str, Any]) -> Dict[str, Any]:
    d = p.get("data") or {}
    return {"id": p["id"], "status": p["status"], "name": p.get("name") or d.get("name"),
            "services": d.get("services") or [], "vehicle": d.get("vehicle") or "",
            "vehicle_number": d.get("vehicle_number") or "", "town": d.get("town") or "",
            "radius_km": d.get("radius_km"), "available": bool(d.get("available")),
            "verified": bool(d.get("verified")), "review_note": d.get("review_note") or ""}


def _partner_data(body: PartnerBody, user: str) -> Dict[str, Any]:
    from app.api.routes.platform import user_ref

    bad = [s for s in body.services if s not in PARTNER_SERVICES]
    if bad:
        raise HTTPException(status_code=422, detail=f"Unknown service: {bad[0]}")
    return {"name": body.name, "kind": "independent", "user_ref": user_ref(user), "services": body.services,
            "vehicle": body.vehicle, "vehicle_number": body.vehicle_number.upper(),
            "licence_last4": body.licence_last4, "town": body.town, "country": "IN", "radius_km": body.radius_km,
            "available": False, "verified": False}


@router.post("/partners/apply")
def apply_partner(body: PartnerBody, request: Request) -> dict:
    """Driver / delivery-partner join. Lands PENDING_REVIEW; staff approve,
    reject, ask for a correction, pause or disable it. Only the licence's
    last 4 digits are stored -- documents are checked in person."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    if _my_partner_records(container, user):
        raise HTTPException(status_code=409, detail="You already applied -- see your partner status")
    record = _resources(container).create("delivery_partners", _partner_data(body, user), actor=user,
                                          status="PENDING_REVIEW")
    return _partner_view(record)


@router.get("/partners/me")
def my_partner(request: Request) -> dict:
    user = _authenticated_app_user(request)
    records = _my_partner_records(request.app.state.container, user)
    return {"partner": _partner_view(records[0]) if records else None}


@router.patch("/partners/me")
def update_partner(body: PartnerBody, request: Request) -> dict:
    """Correct and resubmit an application staff sent back (DRAFT) or
    rejected; an approved partner's edits go back to review."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    records = _my_partner_records(container, user)
    if not records:
        raise HTTPException(status_code=404, detail="No partner application")
    record = records[0]
    if record["status"] == "DISABLED":
        raise HTTPException(status_code=403, detail="This partner account is disabled")
    data = _partner_data(body, user)
    data["available"] = False
    data["review_note"] = ""
    res = _resources(container)
    res.repo.update(record["id"], actor=user, action="edit", name=body.name,
                    data={**(record.get("data") or {}), **data},
                    status="PENDING_REVIEW" if record["status"] in ("DRAFT", "REJECTED", "ACTIVE") else None)
    return _partner_view(res.get("delivery_partners", record["id"]))


class AvailabilityBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    available: bool
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


@router.post("/partners/me/availability")
def set_availability(body: AvailabilityBody, request: Request) -> dict:
    """Online / offline. Going online needs approval and a current point."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    records = _my_partner_records(container, user)
    if not records:
        raise HTTPException(status_code=404, detail="No partner application")
    record = records[0]
    if body.available and record["status"] != "ACTIVE":
        raise HTTPException(status_code=409, detail={"code": "not_approved",
                                                     "message": "You can go online once staff approve you."})
    data = dict(record.get("data") or {})
    if body.available and (body.latitude is None or body.longitude is None) and data.get("latitude") is None:
        raise HTTPException(status_code=422, detail={"code": "needs_location",
                                                     "message": "Share your location to go online."})
    data["available"] = body.available
    if body.latitude is not None and body.longitude is not None:
        data["latitude"], data["longitude"] = round(body.latitude, 5), round(body.longitude, 5)
    _resources(container).repo.update(record["id"], actor=user, action="availability", data=data)
    return _partner_view(_resources(container).get("delivery_partners", record["id"]))


# -------------------------------------------------------------- carpool --
class CarpoolBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    origin: Point
    dest: Point
    depart_at: str = Field(min_length=10, max_length=25)
    seats: int = Field(ge=1, le=8)
    contribution: Optional[float] = Field(default=None, ge=0, le=100000)
    preferences: str = Field(default="", max_length=300)


def _ride_view(ride: Dict[str, Any], user: str, accepted: bool = False) -> Dict[str, Any]:
    out = {k: v for k, v in ride.items() if k not in ("host", "contact_phone")}
    out["mine"] = ride.get("host") == user
    if accepted:
        out["host_phone"] = ride.get("contact_phone") or _phone_of(ride.get("host") or "")
    return out


@router.post("/carpool/rides")
def offer_ride(body: CarpoolBody, request: Request) -> dict:
    """A host offers seats on a trip they are making anyway (cost sharing,
    not a commercial taxi). Contact is shared only after the host accepts."""
    user = _authenticated_app_user(request)
    container = request.app.state.container
    from app.api.routes.command_center import feature_enabled

    if not feature_enabled(container, "carpool.enabled"):
        raise HTTPException(status_code=409, detail={"code": "service_off", "message": "Carpool is switched off."})
    origin = _resolve_point(container, body.origin, "start")
    dest = _resolve_point(container, body.dest, "destination")
    try:
        ride = jobs(container).carpool_offer(host=user, origin=origin, dest=dest, depart_at=body.depart_at,
                                             seats=body.seats, contribution=body.contribution,
                                             preferences=body.preferences)
    except DeliveryError as error:
        raise _error(error) from None
    return _ride_view(ride, user)


@router.get("/carpool/search")
def search_rides(request: Request, from_lat: float, from_lng: float, to_lat: float, to_lng: float,
                 date: str = "", within_km: float = 5.0) -> dict:
    user = _authenticated_app_user(request)
    rides = jobs(request.app.state.container).carpool_search(
        origin={"latitude": from_lat, "longitude": from_lng}, dest={"latitude": to_lat, "longitude": to_lng},
        date=date[:10], within_km=max(0.5, min(within_km, 50)))
    return {"items": [_ride_view(r, user) for r in rides if r.get("host") != user]}


class SeatBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    seats: int = Field(default=1, ge=1, le=8)


@router.post("/carpool/rides/{ride_id}/request")
def request_seat(ride_id: str, body: SeatBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        req = jobs(request.app.state.container).carpool_request(ride_id, passenger=user, seats=body.seats)
    except DeliveryError as error:
        raise _error(error) from None
    return {k: v for k, v in req.items() if k not in ("passenger", "contact_phone")}


@router.post("/carpool/rides/{ride_id}/close")
def close_ride(ride_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        return _ride_view(jobs(request.app.state.container).carpool_close(ride_id, host=user), user)
    except DeliveryError as error:
        raise _error(error) from None


@router.get("/carpool/mine")
def my_carpool(request: Request) -> dict:
    """Host: my rides with their seat requests (a passenger's phone only
    after I accept). Passenger: my requests (the host's phone only after
    acceptance)."""
    user = _authenticated_app_user(request)
    store = jobs(request.app.state.container)
    hosting = []
    for ride in store.carpool_for_host(user):
        reqs = []
        for r in store.carpool_requests_for(ride["id"]):
            item = {k: v for k, v in r.items() if k not in ("passenger", "contact_phone")}
            if r["status"] == "ACCEPTED":
                item["passenger_phone"] = r.get("contact_phone") or _phone_of(r["passenger"])
            reqs.append(item)
        hosting.append({**_ride_view(ride, user), "requests": reqs})
    riding = []
    for r in store.carpool_requests_by(user):
        ride = store.carpool_get(r["ride_id"]) or {}
        riding.append({**{k: v for k, v in r.items() if k not in ("passenger", "contact_phone")},
                       "ride": _ride_view(ride, user, accepted=r["status"] == "ACCEPTED") if ride else None})
    return {"hosting": hosting, "riding": riding}


class DecideBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    accept: bool


@router.post("/carpool/requests/{req_id}/decide")
def decide_seat(req_id: str, body: DecideBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        req = jobs(request.app.state.container).carpool_decide(req_id, host=user, accept=body.accept)
    except DeliveryError as error:
        raise _error(error) from None
    out = {k: v for k, v in req.items() if k not in ("passenger", "contact_phone")}
    if req["status"] == "ACCEPTED":
        out["passenger_phone"] = req.get("contact_phone") or _phone_of(req["passenger"])
    return out


# ---------------------------------------------------- order fulfilment --
def _fulfillment(container: Any):
    from app.services.fulfillment import FulfillmentStore

    store = getattr(container, "fulfillment_store", None)
    if store is None or store.db_path != container.settings.database_path:
        store = FulfillmentStore(container.settings.database_path)
        container.fulfillment_store = store
    return store


def _fulfillment_view(container: Any, order: Dict[str, Any], user: str) -> Dict[str, Any]:
    from app.services.fulfillment import delivery_state

    row = _fulfillment(container).get(order["id"])
    job = jobs(container).get(row["delivery_job_id"]) if row.get("delivery_job_id") else None
    return {"order_id": order["id"], "responsibility": row["mode"], "commerce_status": order.get("status"),
            "delivery_status": delivery_state(row["mode"], order.get("status") or "", job),
            "provider_name": row.get("provider_name"), "tracking_ref": row.get("tracking_ref"),
            "delivery_job": _view(container, job, user) if job and job.get("requester") == user else (
                {"id": job["id"], "status": job["status"], "stage": STAGE_TEXT.get(job["status"])} if job else None)}


@router.get("/orders/{order_id}/fulfillment")
def order_fulfillment(order_id: int, request: Request) -> dict:
    from app.api.routes.orders import _party

    container = request.app.state.container
    order, _ = _party(container, order_id, request)
    return _fulfillment_view(container, order, _authenticated_app_user(request))


class FulfillmentBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: str = Field(pattern="^(SELLER_DELIVERY|CUSTOMER_PICKUP|ASKODOX_NETWORK_DRIVER|THIRD_PARTY_PROVIDER|"
                              "CUSTOMER_ARRANGED_DRIVER|SELLER_ARRANGED_DRIVER|COURIER_PARCEL_PROVIDER|"
                              "NOT_REQUIRED|TO_BE_DECIDED)$")
    provider_name: str = Field(default="", max_length=80)
    tracking_ref: str = Field(default="", max_length=80)
    pickup: Optional[Point] = None
    drop: Optional[Point] = None
    details: Details = Field(default_factory=Details)


@router.post("/orders/{order_id}/fulfillment")
def set_order_fulfillment(order_id: int, body: FulfillmentBody, request: Request) -> dict:
    """Buyer or seller records who moves the order. ASKODOX_NETWORK_DRIVER
    also opens a delivery request (once the seller has accepted the order),
    which is only 'driver accepted' when a partner really accepts."""
    from app.api.routes.orders import _party
    from app.services import deal_lifecycle

    container = request.app.state.container
    order, _ = _party(container, order_id, request)
    user = _authenticated_app_user(request)
    if str(order.get("status") or "").upper() in ("CANCELLED", "REJECTED", "CLOSED"):
        raise HTTPException(status_code=409, detail="This order is closed")
    job_id = None
    if body.mode == "ASKODOX_NETWORK_DRIVER":
        if str(order.get("status") or "").upper() not in deal_lifecycle.OPEN_EXECUTION:
            raise HTTPException(status_code=409, detail={"code": "not_accepted", "message":
                                "A driver can be requested once the seller has accepted the order."})
        if body.pickup is None or body.drop is None:
            raise HTTPException(status_code=422, detail={"code": "needs_location",
                                                         "message": "Pickup and drop are needed for a driver."})
        current = _fulfillment(container).get(order_id)
        existing = jobs(container).get(current["delivery_job_id"]) if current.get("delivery_job_id") else None
        if existing and existing["status"] not in ("CANCELLED", "NEEDS_PARTNER", "NEEDS_CONFIGURATION"):
            raise HTTPException(status_code=409, detail="A driver request is already open for this order")
        job = create_job(JobBody(kind="local_delivery", pickup=body.pickup, drop=body.drop,
                                 order_id=str(order_id), details=body.details), request)
        job_id = job["id"]
    _fulfillment(container).set(order_id, mode=body.mode, by=user, delivery_job_id=job_id,
                                provider_name=body.provider_name, tracking_ref=body.tracking_ref)
    return _fulfillment_view(container, order, user)


# -------------------------------------------------------------- reports --
class ReportBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    subject_type: str = Field(pattern="^(job|carpool_ride|partner)$")
    subject_id: str = Field(min_length=3, max_length=40)
    reason: str = Field(min_length=3, max_length=500)


@router.post("/reports")
def report(body: ReportBody, request: Request) -> dict:
    """Safety / misconduct report on a trip, carpool ride or partner. Staff
    see it in the Mobility Command Center."""
    user = _authenticated_app_user(request)
    from app.services import pii_mask, rate_limit

    rate_limit.check(request, "mobility_report", limit=10)
    return jobs(request.app.state.container).report(subject_type=body.subject_type, subject_id=body.subject_id,
                                                    reporter=user, reason=pii_mask.mask_sensitive(body.reason))


# ---------------------------------------------------------------- admin --
@admin_router.get("/admin/cc/mobility/overview")
def mobility_overview(request: Request, limit: int = 50) -> dict:
    """Mobility Command Center: privacy-safe analytics, recent requests
    (no customer ids / phones), partners by status, open reports."""
    from app.api.routes.command_center import _require

    _require(request, "delivery:view")
    container = request.app.state.container
    store = jobs(container)
    partners = _partners(container)
    by_status: Dict[str, int] = {}
    for p in partners:
        by_status[p["status"]] = by_status.get(p["status"], 0) + 1
    online = sum(1 for p in partners if p["status"] == "ACTIVE" and (p.get("data") or {}).get("available"))
    recent = []
    for j in store.all_jobs(limit=max(1, min(limit, 200))):
        recent.append({"id": j["id"], "kind": j["kind"], "status": j["status"], "stage": STAGE_TEXT.get(j["status"]),
                       "distance_km": j.get("distance_km"), "pickup": (j.get("pickup") or {}).get("label") or "",
                       "drop": (j.get("drop") or {}).get("label") or "", "offered": len(j.get("offered") or []),
                       "declined": len(j.get("declined") or []), "partner_id": j.get("partner_id"),
                       "quote": j.get("quote"), "order_id": j.get("order_id"), "created_at": j["created_at"],
                       "updated_at": j["updated_at"]})
    return {"analytics": store.analytics(), "partners": {"by_status": by_status, "online": online},
            "requests": recent, "reports": store.reports()}


class ModerationBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str = Field(pattern="^(OPEN|REVIEWING|RESOLVED|DISMISSED)$")


@admin_router.post("/admin/cc/mobility/reports/{report_id}")
def moderate_report(report_id: str, body: ModerationBody, request: Request) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "delivery:manage")
    try:
        return jobs(request.app.state.container).set_report_status(report_id, body.status)
    except DeliveryError as error:
        raise _error(error) from None


class RideModerationBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str = Field(pattern="^(OPEN|HIDDEN|CLOSED)$")


@admin_router.post("/admin/cc/mobility/carpool/{ride_id}")
def moderate_ride(ride_id: str, body: RideModerationBody, request: Request) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "delivery:manage")
    store = jobs(request.app.state.container)
    if not store.carpool_get(ride_id):
        raise HTTPException(status_code=404, detail="Ride not found")
    store.set_carpool_status(ride_id, body.status)
    return {"id": ride_id, "status": body.status}
