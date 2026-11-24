"""Business Kit ways of working 3-5 (owner 2026-11-24): bookings, job cards, monthly members. Identity from the bearer
token only; shop routes need the shop role (``PosStore._require``); customer routes act only on the caller's own rows."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.api.routes.pos import _call, _store, _user
from app.services.pos_work import PosBookings, PosJobs, PosMonthly

router = APIRouter(prefix="/api/pos", tags=["POS bookings, jobs, monthly"])


def _notify(request: Request):
    from app.services.push_service import push_service

    container: Any = request.app.state.container

    def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
        try:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)
        except Exception:
            pass

    return notify


def _bookings(request: Request) -> PosBookings:
    return PosBookings(_store(request), notify=_notify(request))


def _jobs(request: Request) -> PosJobs:
    return PosJobs(_store(request), notify=_notify(request))


def _monthly(request: Request) -> PosMonthly:
    return PosMonthly(_store(request), notify=_notify(request))


class BookItemIn(BaseModel):
    id: str = Field(default="", max_length=40)
    name: str = Field(max_length=60)
    mode: str = Field(default="slot", pattern="^(slot|day)$")
    slot_minutes: int = Field(default=30, ge=5, le=1440)
    capacity: int = Field(default=1, ge=1, le=5000)
    price_paise: int = Field(default=0, ge=0)
    deposit_paise: int = Field(default=0, ge=0)
    note: str = Field(default="", max_length=200)
    active: bool = True


class BookingIn(BaseModel):
    item_id: str = Field(default="", max_length=40)
    at: str = Field(default="", max_length=40)  # slot things: the start (IST when no zone)
    from_date: str = Field(default="", max_length=10)  # day things: coming day
    to_date: str = Field(default="", max_length=10)  # day things: leaving day
    people: int = Field(default=1, ge=1, le=5000)
    name: str = Field(default="", max_length=60)
    phone: str = Field(default="", max_length=20)
    note: str = Field(default="", max_length=200)


class StatusIn(BaseModel):
    status: str = Field(max_length=20)


class JobIn(BaseModel):
    item: str = Field(max_length=80)
    details: str = Field(default="", max_length=600)
    name: str = Field(default="", max_length=60)
    phone: str = Field(default="", max_length=20)
    estimate_paise: int = Field(default=0, ge=0)
    advance_paise: int = Field(default=0, ge=0)
    ready_by: str = Field(default="", max_length=10)
    client_txn_id: str = Field(default="", max_length=64)


class JobUpdateIn(BaseModel):
    status: str = Field(default="", max_length=20)
    details: Optional[str] = Field(default=None, max_length=600)
    estimate_paise: Optional[int] = Field(default=None, ge=0)
    advance_paise: Optional[int] = Field(default=None, ge=0)
    ready_by: Optional[str] = Field(default=None, max_length=10)


class PlanIn(BaseModel):
    id: str = Field(default="", max_length=40)
    name: str = Field(max_length=60)
    amount_paise: int = Field(ge=1)
    note: str = Field(default="", max_length=200)
    active: bool = True


class MemberIn(BaseModel):
    plan_id: str = Field(max_length=40)
    name: str = Field(max_length=60)
    phone: str = Field(default="", max_length=20)
    due_day: int = Field(default=5, ge=1, le=28)
    start_month: str = Field(default="", max_length=7)
    note: str = Field(default="", max_length=200)


class PayIn(BaseModel):
    month: str = Field(default="", max_length=7)
    amount_paise: int = Field(default=0, ge=0)
    waive: bool = False


# ---- bookings: the shop
@router.get("/businesses/{business_id}/book-items")
def book_items(business_id: str, request: Request) -> Dict[str, Any]:
    return {"items": _call(_bookings(request).items, business_id, _user(request, "bookings", 240))}


@router.post("/businesses/{business_id}/book-items")
def save_book_item(business_id: str, body: BookItemIn, request: Request) -> Dict[str, Any]:
    return _call(_bookings(request).save_item, business_id, _user(request, "bookings", 120), body.model_dump())


@router.get("/businesses/{business_id}/bookings")
def shop_bookings(business_id: str, request: Request, day: str = "") -> Dict[str, Any]:
    return _call(_bookings(request).for_business, business_id, _user(request, "bookings", 240), day)


@router.post("/businesses/{business_id}/bookings")
def add_booking(business_id: str, body: BookingIn, request: Request) -> Dict[str, Any]:
    return _call(_bookings(request).add, business_id, _user(request, "bookings", 120), body.model_dump())


@router.post("/businesses/{business_id}/bookings/{booking_id}/status")
def booking_status(business_id: str, booking_id: str, body: StatusIn, request: Request) -> Dict[str, Any]:
    return _call(_bookings(request).set_status, business_id, _user(request, "bookings", 120), booking_id, body.status)


# ---- bookings: a customer
@router.get("/book/{business_id}/free")
def free_to_book(business_id: str, request: Request, at: str = "", from_date: str = "", to_date: str = "",
                 people: int = 1, mode: str = "") -> Dict[str, Any]:
    _user(request, "book-free", 120)
    return _call(_bookings(request).free, business_id, {"at": at, "from_date": from_date, "to_date": to_date,
                                                        "people": people, "mode": mode})


@router.post("/book/{business_id}")
def book(business_id: str, body: BookingIn, request: Request) -> Dict[str, Any]:
    return _call(_bookings(request).book, _user(request, "book", 20), business_id, body.model_dump())


@router.get("/me/bookings")
def my_bookings(request: Request) -> Dict[str, Any]:
    return {"bookings": _call(_bookings(request).mine, _user(request, "bookings-me", 120))}


@router.post("/me/bookings/{booking_id}/cancel")
def cancel_my_booking(booking_id: str, request: Request) -> Dict[str, Any]:
    return _call(_bookings(request).cancel_mine, _user(request, "bookings-me", 30), booking_id)


# ---- job cards
@router.get("/businesses/{business_id}/jobs")
def shop_jobs(business_id: str, request: Request, status: str = "open") -> Dict[str, Any]:
    return _call(_jobs(request).for_business, business_id, _user(request, "jobs", 240), status)


@router.post("/businesses/{business_id}/jobs")
def add_job(business_id: str, body: JobIn, request: Request) -> Dict[str, Any]:
    return _call(_jobs(request).create, business_id, _user(request, "jobs", 120), body.model_dump())


@router.patch("/businesses/{business_id}/jobs/{job_id}")
def update_job(business_id: str, job_id: str, body: JobUpdateIn, request: Request) -> Dict[str, Any]:
    data = {k: v for k, v in body.model_dump().items() if v is not None and v != ""}
    return _call(_jobs(request).update, business_id, _user(request, "jobs", 120), job_id, data)


@router.get("/me/jobs")
def my_jobs(request: Request) -> Dict[str, Any]:
    return {"jobs": _call(_jobs(request).mine, _user(request, "jobs-me", 120))}


# ---- monthly
@router.get("/businesses/{business_id}/monthly/plans")
def monthly_plans(business_id: str, request: Request) -> Dict[str, Any]:
    return {"plans": _call(_monthly(request).plans, business_id, _user(request, "monthly", 240))}


@router.post("/businesses/{business_id}/monthly/plans")
def save_monthly_plan(business_id: str, body: PlanIn, request: Request) -> Dict[str, Any]:
    return _call(_monthly(request).save_plan, business_id, _user(request, "monthly", 60), body.model_dump())


@router.get("/businesses/{business_id}/monthly")
def monthly(business_id: str, request: Request, month: str = "") -> Dict[str, Any]:
    return _call(_monthly(request).month, business_id, _user(request, "monthly", 240), month)


@router.post("/businesses/{business_id}/monthly/members")
def add_monthly_member(business_id: str, body: MemberIn, request: Request) -> Dict[str, Any]:
    return _call(_monthly(request).add_member, business_id, _user(request, "monthly", 120), body.model_dump())


@router.post("/businesses/{business_id}/monthly/members/{member_id}/pay")
def pay_monthly(business_id: str, member_id: str, body: PayIn, request: Request) -> Dict[str, Any]:
    return _call(_monthly(request).pay, business_id, _user(request, "monthly", 120), member_id, body.model_dump())


@router.post("/businesses/{business_id}/monthly/members/{member_id}/status")
def monthly_member_status(business_id: str, member_id: str, body: StatusIn, request: Request) -> Dict[str, Any]:
    return _call(_monthly(request).set_member, business_id, _user(request, "monthly", 120), member_id, body.status)


@router.get("/me/monthly")
def my_monthly(request: Request) -> Dict[str, Any]:
    return {"plans": _call(_monthly(request).mine, _user(request, "monthly-me", 120))}


class CollectForIn(BaseModel):
    kind: str = Field(pattern="^(job|booking|member)$")
    ref_id: str = Field(max_length=60)
    month: str = Field(default="", max_length=7)


@router.post("/businesses/{business_id}/collect/for")
def collect_for(business_id: str, body: CollectForIn, request: Request) -> dict:
    """The OWNER's own UPI QR for a job card balance / booking price / monthly due; both sides hear when the money's
    notice arrives, and the owner's confirmation records it on the card (money never touches ASKODOX)."""
    from app.api.routes.pos import _payment_alerts, _with_share
    from app.services import pos_collect_refs

    return _with_share(request, _call(pos_collect_refs.ask, _store(request), _payment_alerts(request), business_id,
                                      _user(request), body.kind, body.ref_id, body.month))


class BranchesIn(BaseModel):
    name: str = Field(default="", max_length=60)
    business_ids: list = Field(min_length=2, max_length=30)


def _branches(request: Request):
    from app.services.pos_branches import PosBranches

    return PosBranches(_store(request))


@router.get("/me/branches")
def my_branches(request: Request) -> dict:
    """The owner's own shops + the groups he linked (shared delivery pool + all-branches view)."""
    return _call(_branches(request).mine, _user(request))


@router.put("/me/branches")
def save_branches(body: BranchesIn, request: Request) -> dict:
    return _call(_branches(request).save, _user(request), body.name, [str(b) for b in body.business_ids])


@router.delete("/me/branches/{business_id}")
def leave_branches(business_id: str, request: Request) -> dict:
    return _call(_branches(request).leave, _user(request), business_id)


@router.get("/me/branches/{group_id}/overview")
def branches_overview(group_id: str, request: Request, local_date: str = "") -> dict:
    from datetime import datetime, timedelta, timezone

    day = local_date or (datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d")
    return _call(_branches(request).overview, _user(request), group_id, day)
