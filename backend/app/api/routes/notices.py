"""Paid notifications routes (owner 2026-11-24): any signed-in person sends one; receivers open it in the app."""
from __future__ import annotations

import base64
import binascii
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.pos import _store, _user
from app.services import platform_settings
from app.services.notice_broadcast import NoticeBroadcast, NoticeError

router = APIRouter(tags=["Notices"])


def _service(request: Request) -> NoticeBroadcast:
    container: Any = request.app.state.container
    existing = getattr(container, "notice_broadcast", None)
    if existing is None:
        existing = NoticeBroadcast(_store(request).db_path, setting=platform_settings.get)
        try:
            container.notice_broadcast = existing
        except Exception:
            pass
    return existing


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except NoticeError as error:
        raise HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message,
                                                              **error.extra})


class Audience(BaseModel):
    audience: str = Field(default="followers", max_length=12)
    business_id: str = Field(default="", max_length=64)
    radius_km: float = Field(default=3, ge=0, le=20)
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lon: Optional[float] = Field(default=None, ge=-180, le=180)


class NoticeIn(Audience):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(default="", max_length=400)
    image_base64: str = Field(default="", max_length=4_100_000)
    image_mime: str = Field(default="", max_length=20)
    client_txn_id: str = Field(min_length=1, max_length=64)


@router.post("/api/notices/preview")
def preview(body: Audience, request: Request) -> Dict[str, Any]:
    """How many people it would reach today and what it costs (nothing is sent)."""
    user = _user(request, bucket="notices", limit=60)
    from app.api.routes.ai_credits import ai_credits

    out = _call(_service(request).preview, user, audience=body.audience, business_id=body.business_id,
                radius_km=body.radius_km, lat=body.lat, lon=body.lon)
    credits = ai_credits(request.app.state.container)
    out["charging"] = bool(credits.settings()["charging"])
    out["balance_paise"] = credits.balance(user).get("live", 0)
    return out


@router.post("/api/notices")
def send(body: NoticeIn, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="notices_send", limit=10)
    container: Any = request.app.state.container
    from app.api.routes.ai_credits import ai_credits
    from app.services.ai_credits import CreditsError

    image = b""
    if body.image_base64:
        try:
            image = base64.b64decode(body.image_base64, validate=True)
        except (binascii.Error, ValueError):
            raise HTTPException(status_code=400, detail={"code": "image", "message": "The picture could not be read."})
    credits = ai_credits(container)

    def charge(ref: str, paise: int) -> Dict[str, Any]:
        try:
            return credits.spend(user, paise, f"notice:{ref}", feature="notice", note="notification")
        except CreditsError as error:
            raise NoticeError(402, "AI_CREDITS_LOW", "Not enough AI Credits for this many people. Recharge a little "
                                                     "or choose fewer people.", **(error.detail or {}))

    service = _service(request)
    out = _call(service.create, user, title=body.title, body=body.body, image=image, image_mime=body.image_mime,
                audience=body.audience, business_id=body.business_id, radius_km=body.radius_km, lat=body.lat,
                lon=body.lon, client_txn_id=body.client_txn_id, charge=charge)
    people = out.pop("people", None)
    if people is not None:  # a new notification (a repeat of the same tap returns the stored one)
        def unused(paise: int) -> None:
            credits.refund_unused(user, f"notice:{out['id']}", paise, feature="notice")

        from app.services.push_service import push_service

        service.deliver_async(out["id"], push_service(container), on_unused=unused)
        out["people"] = len(people)
    return out


@router.get("/api/notices/mine")
def mine(request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="notices", limit=120)
    return {"notices": _service(request).mine(user)}


@router.get("/api/notices/{notice_id}")
def open_notice(notice_id: str, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="notices", limit=240)
    return _call(_service(request).open, notice_id, user)


@router.get("/api/notices/{notice_id}/image")
def notice_image(notice_id: str, request: Request) -> Response:
    user = _user(request, bucket="notices", limit=240)
    data, mime = _call(_service(request).image, notice_id, user)
    return Response(content=data, media_type=mime or "image/png", headers={"Cache-Control": "private, max-age=86400"})
