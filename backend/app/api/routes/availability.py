""""Tell me when it is available" (services/availability_watch.py).

  POST   /api/me/availability-watches        {subject, location?, category?} -> one watch (30 days, de-duplicated)
  GET    /api/me/availability-watches        my watches (ACTIVE / NOTIFIED / EXPIRED / CANCELLED)
  DELETE /api/me/availability-watches/{id}   stop one

Signed-in buyers only (the push goes to their own devices). The background
runner matches new listings and sends ONE push per watch.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services import availability_watch as aw

router = APIRouter(prefix="/api/me", tags=["availability"])


def store(container: Any) -> aw.AvailabilityWatches:
    existing = getattr(container, "availability_watches", None)
    if existing is None or existing.db_path != container.settings.database_path:
        existing = aw.AvailabilityWatches(container.settings.database_path)
        container.availability_watches = existing
    return existing


def _app_user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


class WatchBody(BaseModel):
    subject: str = Field(min_length=2, max_length=120)
    location: str = Field(default="", max_length=200)
    category: str = Field(default="", max_length=60)


@router.post("/availability-watches")
def create_watch(body: WatchBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "availability_watch", limit=30)
    user = _app_user(request)
    try:
        watch = store(request.app.state.container).create(user, body.subject, location=body.location,
                                                          category=body.category)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    if not watch.get("already"):
        try:
            from app.api.routes.platform import platform

            platform(request.app.state.container).repo.record_event(
                "availability_watch", detail={"subject": watch["subject"]}, category=body.category[:60],
                location=watch.get("area") or "", source="app")
        except Exception:
            pass
    return {"watch": watch}


@router.get("/availability-watches")
def my_watches(request: Request) -> dict:
    return {"items": store(request.app.state.container).mine(_app_user(request))}


@router.delete("/availability-watches/{watch_id}")
def cancel_watch(watch_id: int, request: Request) -> dict:
    if not store(request.app.state.container).cancel(_app_user(request), watch_id):
        raise HTTPException(status_code=404, detail="No active alert with that id")
    return {"ok": True}
