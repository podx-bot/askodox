"""Delivery jobs for the shop's own people (owner plan 2026-11-24, step 1) + the person's colour status. Identity from the
bearer token only; shop routes need the shop role; /api/me routes act only on the caller's own offers / jobs."""
from __future__ import annotations

from typing import Any, List, Optional, Union

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.api.routes.pos import _call, _payment_alerts, _store, _user
from app.services.pos_delivery_jobs import PosDeliveryJobs

router = APIRouter(tags=["POS delivery jobs"])


def _jobs(request: Request) -> PosDeliveryJobs:
    from app.services.push_service import push_service

    container: Any = request.app.state.container

    def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
        try:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)
        except Exception:
            pass

    return PosDeliveryJobs(_store(request), notify=notify, maps=getattr(container, "google_maps_service", None),
                           collect=_payment_alerts(request))


class DraftIn(BaseModel):
    text: str = Field(min_length=1, max_length=400)


class JobIn(BaseModel):
    from_: str = Field(default="", alias="from", max_length=80)
    to: str = Field(max_length=80)
    item: str = Field(default="", max_length=80)
    fee_paise: int = Field(default=0, ge=0)
    collect_paise: int = Field(default=0, ge=0)
    km: Optional[float] = None
    minutes: Optional[int] = None
    ask: Union[str, List[str]] = "free"  # "free" (all green people) | "all" | one / some person ids
    auto_first: bool = False
    note: str = Field(default="", max_length=200)

    model_config = {"populate_by_name": True}


class GiveIn(BaseModel):
    person: str = Field(min_length=1, max_length=80)


class AnswerIn(BaseModel):
    answer: str = Field(pattern="^(now|10|20|30|no)$")


class StepIn(BaseModel):
    step: str = Field(pattern="^(picked|done|cancelled)$")
    money: str = Field(default="", pattern="^(|cash|upi|prepaid)$")


class StatusIn(BaseModel):
    colour: str = Field(pattern="^(free|busy|off)$")


@router.post("/api/pos/businesses/{business_id}/delivery-jobs/draft")
def draft(business_id: str, payload: DraftIn, request: Request) -> dict:
    return _call(_jobs(request).draft, business_id, _user(request), payload.text)


@router.post("/api/pos/businesses/{business_id}/delivery-jobs")
def create(business_id: str, payload: JobIn, request: Request) -> dict:
    data = payload.model_dump(by_alias=True)
    return _call(_jobs(request).create, business_id, _user(request), data)


@router.get("/api/pos/businesses/{business_id}/delivery-jobs")
def jobs(business_id: str, request: Request) -> dict:
    return _call(_jobs(request).jobs, business_id, _user(request))


@router.get("/api/pos/businesses/{business_id}/delivery-jobs/people")
def people(business_id: str, request: Request) -> dict:
    return _call(_jobs(request).people, business_id, _user(request))


@router.get("/api/pos/businesses/{business_id}/delivery-jobs/day")
def day(business_id: str, request: Request, date: str = "") -> dict:
    return _call(_jobs(request).day, business_id, _user(request), date)


@router.post("/api/pos/businesses/{business_id}/delivery-jobs/{job_id}/give")
def give(business_id: str, job_id: str, payload: GiveIn, request: Request) -> dict:
    return _call(_jobs(request).give, business_id, _user(request), job_id, payload.person)


@router.get("/api/me/delivery-jobs")
def mine(request: Request) -> dict:
    return _call(_jobs(request).mine, _user(request))


@router.post("/api/me/delivery-jobs/{job_id}/answer")
def answer(job_id: str, payload: AnswerIn, request: Request) -> dict:
    return _call(_jobs(request).answer, _user(request), job_id, payload.answer)


@router.post("/api/me/delivery-jobs/{job_id}/step")
def step(job_id: str, payload: StepIn, request: Request) -> dict:
    return _call(_jobs(request).step, _user(request), job_id, payload.step, payload.money)


@router.post("/api/me/delivery-jobs/{job_id}/collect")
def collect(job_id: str, request: Request) -> dict:
    return _call(_jobs(request).collect_upi, _user(request), job_id)


@router.get("/api/me/work-status")
def my_status(request: Request) -> dict:
    return _call(_jobs(request).my_status, _user(request))


@router.put("/api/me/work-status")
def set_status(payload: StatusIn, request: Request) -> dict:
    return _call(_jobs(request).set_status, _user(request), payload.colour)
