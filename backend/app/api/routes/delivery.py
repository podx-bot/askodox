"""Delivery jobs API (see app/services/delivery_jobs.py).

Customer: POST /api/delivery/jobs, GET /api/delivery/jobs/{id},
          POST /api/delivery/jobs/{id}/confirm|cancel
Partner:  GET /api/delivery/offers, POST /api/delivery/jobs/{id}/accept,
          POST /api/delivery/jobs/{id}/status
Identity always comes from the session token. A partner is an ACTIVE
(approved) delivery_partners record whose user_ref is the caller.
"""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services.delivery_jobs import KINDS, DeliveryError, DeliveryJobs

router = APIRouter(prefix="/api/delivery", tags=["delivery"])
_STATUS = {"not_found": 404, "not_offered": 403, "not_assigned": 403, "not_requester": 403}


def jobs(container: Any) -> DeliveryJobs:
    j = getattr(container, "delivery_jobs", None)
    if j is None or j.db_path != container.settings.database_path:
        j = DeliveryJobs(container.settings.database_path)
        container.delivery_jobs = j
    return j


def _error(error: DeliveryError) -> HTTPException:
    return HTTPException(status_code=_STATUS.get(error.code, 409), detail={"code": error.code, "message": str(error)})


def _partners(container: Any) -> List[Dict[str, Any]]:
    from app.api.routes.platform import platform

    return platform(container).resources.repo.list("delivery_partners")


def _my_partner_ids(container: Any, user_id: str) -> List[str]:
    from app.api.routes.platform import user_ref

    ref = user_ref(user_id)
    return [p["id"] for p in _partners(container)
            if p.get("status") == "ACTIVE" and (p.get("data") or {}).get("user_ref") in (ref, user_id)]


def _view(job: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """The requester sees everything about their job; a partner sees the
    route and status, never the requester id."""
    out = dict(job)
    if job.get("requester") != user_id:
        out.pop("requester", None)
        out["history"] = [{k: v for k, v in h.items() if k != "by"} for h in job.get("history") or []]
    out.pop("partner_user", None)
    return out


class Point(BaseModel):
    model_config = ConfigDict(extra="forbid")
    label: str = Field(default="", max_length=160)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class JobBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: str = Field(pattern="^(" + "|".join(KINDS) + ")$")
    pickup: Point
    drop: Point
    order_id: str = Field(default="", max_length=60)


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

    try:
        job = jobs(container).create(requester=user, kind=body.kind, pickup=body.pickup.model_dump(),
                                     drop=body.drop.model_dump(), partners=_partners(container),
                                     matching_enabled=feature_enabled(container, "delivery.matching"),
                                     integration_ready=ready, order_id=body.order_id)
    except DeliveryError as error:
        raise _error(error) from None
    return _view(job, user)


@router.get("/jobs/{job_id}")
def get_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    job = jobs(container).get(job_id)
    mine = set(_my_partner_ids(container, user))
    if job is None or not (job["requester"] == user or job.get("partner_user") == user
                           or mine & {o["partner_id"] for o in job.get("offered") or []}):
        raise HTTPException(status_code=404, detail="Delivery not found")
    return _view(job, user)


@router.get("/offers")
def my_offers(request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    ids = _my_partner_ids(container, user)
    return {"partner": bool(ids), "items": [_view(j, user) for j in jobs(container).offers_for(ids)]}


@router.post("/jobs/{job_id}/accept")
def accept_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    container = request.app.state.container
    job = jobs(container).get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Delivery not found")
    offered = {o["partner_id"] for o in job.get("offered") or []}
    mine = [p for p in _my_partner_ids(container, user) if p in offered]
    if not mine:
        raise HTTPException(status_code=403, detail="This delivery was not offered to you")
    try:
        return _view(jobs(container).accept(job_id, partner_id=mine[0], partner_user=user), user)
    except DeliveryError as error:
        raise _error(error) from None


class StatusBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str = Field(pattern="^(PICKED_UP|IN_TRANSIT|DELIVERED)$")


@router.post("/jobs/{job_id}/status")
def advance_job(job_id: str, body: StatusBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        return _view(jobs(request.app.state.container).advance(job_id, partner_user=user, to=body.status), user)
    except DeliveryError as error:
        raise _error(error) from None


@router.post("/jobs/{job_id}/confirm")
def confirm_job(job_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        return _view(jobs(request.app.state.container).confirm(job_id, requester=user), user)
    except DeliveryError as error:
        raise _error(error) from None


class CancelBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str = Field(default="", max_length=200)


@router.post("/jobs/{job_id}/cancel")
def cancel_job(job_id: str, body: CancelBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    try:
        return _view(jobs(request.app.state.container).cancel(job_id, requester=user, reason=body.reason), user)
    except DeliveryError as error:
        raise _error(error) from None
