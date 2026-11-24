"""Workers under an authority (owner plan 2026-11-24 steps 3-6). Identity from the bearer token only; shop routes need
the shop role (``PosStore._require``); /api/me routes act only on the caller's own card, links, orders and documents."""
from __future__ import annotations

import base64
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.pos import _call, _store, _user
from app.services.workforce import Workforce

router = APIRouter(tags=["Workforce"])


def _wf(request: Request) -> Workforce:
    from app.services.push_service import push_service

    container: Any = request.app.state.container

    def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
        try:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)
        except Exception:
            pass

    return Workforce(_store(request), notify=notify)


class WorkerIn(BaseModel):
    name: str = Field(max_length=60)
    work_types: List[str] = Field(default_factory=list, max_length=20)
    town: str = Field(default="", max_length=60)
    lat: Optional[float] = None
    lon: Optional[float] = None
    km: int = Field(default=10, ge=1, le=100)
    free_when: List[str] = Field(default_factory=list, max_length=3)
    adult: bool = False
    udyam: str = Field(default="", max_length=25)
    upi: str = Field(default="", max_length=60)


class AuthorityIn(BaseModel):
    gstin: str = Field(default="", max_length=15)
    udyam: str = Field(default="", max_length=25)
    address: str = Field(default="", max_length=200)
    agency: bool = False
    assigned_money: str = Field(default="cash", pattern="^(cash|upi|both)$")
    lat: Optional[float] = None
    lon: Optional[float] = None
    prices: Dict[str, int] = Field(default_factory=dict)


class InviteIn(BaseModel):
    worker: str = Field(min_length=1, max_length=80)
    asks: str = Field(default="", max_length=300)


class YesNoIn(BaseModel):
    accept: bool


class ChecksIn(BaseModel):
    checks: Dict[str, bool] = Field(default_factory=dict)


class DocIn(BaseModel):
    kind: str = Field(max_length=30)
    image_base64: str = Field(max_length=900_000)
    mime: str = Field(default="image/jpeg", pattern="^image/(jpeg|png)$")


class CodeIn(BaseModel):
    code: str = Field(min_length=6, max_length=6)


class OrderIn(BaseModel):
    work_type: str = Field(max_length=40)
    business_id: str = Field(default="", max_length=80)
    worker: str = Field(default="", max_length=80)
    details: str = Field(default="", max_length=300)
    place: str = Field(default="", max_length=120)
    at: str = Field(default="", max_length=60)
    price_paise: int = Field(default=0, ge=0)


class AssignIn(BaseModel):
    worker: str = Field(min_length=1, max_length=80)
    money: str = Field(default="", pattern="^(|cash|upi|confirm_home)$")


class ShareIn(BaseModel):
    paise: int = Field(ge=0)


class TextIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class ReplyIn(BaseModel):
    reply: str = Field(default="", max_length=500)
    close: bool = False


class RateIn(BaseModel):
    stars: int = Field(ge=1, le=5)


class PostIn(BaseModel):
    worker: str = Field(max_length=80)
    site: str = Field(max_length=80)
    shift: str = Field(default="day", pattern="^(day|night)$")
    month: str = Field(default="", max_length=7)
    lat: Optional[float] = None
    lon: Optional[float] = None


class SiteIn(BaseModel):
    method: str = Field(default="face_live", pattern="^(face_live|kiosk_live)$")
    lat: Optional[float] = None
    lon: Optional[float] = None


B = "/api/pos/businesses/{business_id}/workforce"


@router.get("/api/me/work")
def me(request: Request) -> dict:
    return _call(_wf(request).me, _user(request))


@router.put("/api/me/work")
def save_me(payload: WorkerIn, request: Request) -> dict:
    return _call(_wf(request).save_worker, _user(request), payload.model_dump())


@router.post("/api/me/work/links/{business_id}")
def answer_invite(business_id: str, payload: YesNoIn, request: Request) -> dict:
    return _call(_wf(request).answer_invite, _user(request), business_id, payload.accept)


@router.post("/api/me/work/links/{business_id}/leave")
def leave(business_id: str, request: Request) -> dict:
    return _call(_wf(request).leave, _user(request), business_id)


@router.post("/api/me/work/links/{business_id}/doc-code")
def doc_code(business_id: str, request: Request) -> dict:
    return _call(_wf(request).doc_code, _user(request), business_id)


@router.post("/api/me/work/docs")
def add_doc(payload: DocIn, request: Request) -> dict:
    try:
        image = base64.b64decode(payload.image_base64, validate=True)
    except Exception:
        image = b""
    return _call(_wf(request).add_doc, _user(request), payload.kind, image, payload.mime)


@router.get("/api/me/work/orders")
def worker_orders(request: Request) -> dict:
    return _call(_wf(request).worker_orders, _user(request))


@router.post("/api/me/work/orders/{order_id}/answer")
def worker_answer(order_id: str, payload: YesNoIn, request: Request) -> dict:
    return _call(_wf(request).worker_answer, _user(request), order_id, payload.accept)


@router.post("/api/me/work/orders/{order_id}/done")
def worker_done(order_id: str, request: Request) -> dict:
    return _call(_wf(request).done, _user(request), order_id)


@router.post("/api/me/work/orders/{order_id}/share-received")
def share_received(order_id: str, request: Request) -> dict:
    return _call(_wf(request).ack_share, _user(request), order_id)


@router.post("/api/me/work/postings/{posting_id}/attendance")
def site_attendance(posting_id: str, payload: SiteIn, request: Request) -> dict:
    return _call(_wf(request).mark_site, _user(request), posting_id, payload.method, payload.lat, payload.lon)


@router.get("/api/me/work/badge")
def badge(request: Request) -> dict:
    return _call(_wf(request).badge, _user(request))


# ---- customers
@router.get("/api/hire/options")
def options(request: Request, work_type: str, lat: Optional[float] = None, lon: Optional[float] = None) -> dict:
    _user(request)
    return _call(_wf(request).authorities_for, work_type, lat, lon)


@router.get("/api/hire/work-types")
def hire_types(request: Request) -> dict:
    from app.services.workforce import work_types

    return {"work_types": work_types()}


@router.post("/api/hire/orders")
def place(payload: OrderIn, request: Request) -> dict:
    return _call(_wf(request).place, _user(request), payload.model_dump())


@router.get("/api/hire/orders")
def my_orders(request: Request) -> dict:
    return _call(_wf(request).my_orders, _user(request))


@router.post("/api/hire/orders/{order_id}/complaint")
def complain(order_id: str, payload: TextIn, request: Request) -> dict:
    return _call(_wf(request).complain, _user(request), order_id, payload.text)


@router.post("/api/hire/orders/{order_id}/rating")
def rate(order_id: str, payload: RateIn, request: Request) -> dict:
    return _call(_wf(request).rate, _user(request), order_id, payload.stars)


# ---- the authority
@router.get(B)
def authority(business_id: str, request: Request) -> dict:
    return _call(_wf(request).authority, business_id, _user(request))


@router.put(B)
def set_authority(business_id: str, payload: AuthorityIn, request: Request) -> dict:
    return _call(_wf(request).set_authority, business_id, _user(request), payload.model_dump())


@router.get(B + "/cards")
def cards(business_id: str, request: Request, work_type: str = "") -> dict:
    return _call(_wf(request).cards, business_id, _user(request), work_type)


@router.post(B + "/invite")
def invite(business_id: str, payload: InviteIn, request: Request) -> dict:
    return _call(_wf(request).invite, business_id, _user(request), payload.worker, payload.asks)


@router.post(B + "/team/{worker}/remove")
def remove(business_id: str, worker: str, request: Request) -> dict:
    return _call(_wf(request).leave, worker, business_id, by_authority=_user(request))


@router.put(B + "/team/{worker}/checks")
def checks(business_id: str, worker: str, payload: ChecksIn, request: Request) -> dict:
    return _call(_wf(request).set_checks, business_id, _user(request), worker, payload.checks)


@router.post(B + "/team/{worker}/docs")
def open_docs(business_id: str, worker: str, payload: CodeIn, request: Request) -> dict:
    return _call(_wf(request).open_docs, business_id, _user(request), worker, payload.code)


@router.get(B + "/team/{worker}/docs/{doc_id}")
def doc_image(business_id: str, worker: str, doc_id: str, request: Request, response: Response) -> dict:
    image, mime = _call(_wf(request).doc_image, business_id, _user(request), worker, doc_id)
    # View only: never cached; the app draws it on screen with no save / share button.
    response.headers["Cache-Control"] = "no-store"
    return {"mime": mime, "image_base64": base64.b64encode(image).decode(), "view_only": True}


@router.get(B + "/orders")
def authority_orders(business_id: str, request: Request) -> dict:
    return _call(_wf(request).authority_orders, business_id, _user(request))


@router.post(B + "/orders/{order_id}/assign")
def assign(business_id: str, order_id: str, payload: AssignIn, request: Request) -> dict:
    return _call(_wf(request).assign, business_id, _user(request), order_id, payload.worker, payload.money)


@router.post(B + "/orders/{order_id}/share")
def share(business_id: str, order_id: str, payload: ShareIn, request: Request) -> dict:
    return _call(_wf(request).record_share, business_id, _user(request), order_id, payload.paise)


@router.post(B + "/complaints/{complaint_id}")
def complaint_reply(business_id: str, complaint_id: str, payload: ReplyIn, request: Request) -> dict:
    return _call(_wf(request).answer_complaint, business_id, _user(request), complaint_id, payload.reply, payload.close)


@router.get(B + "/postings")
def postings(business_id: str, request: Request, month: str = "") -> dict:
    return _call(_wf(request).postings, business_id, _user(request), month)


@router.post(B + "/postings")
def post(business_id: str, payload: PostIn, request: Request) -> dict:
    return _call(_wf(request).post, business_id, _user(request), payload.model_dump())
