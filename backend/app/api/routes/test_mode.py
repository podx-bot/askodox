"""Test Mode Diagnostics API (services/test_diagnostics.py).

  GET  /api/me/test-mode              is Test Mode on for me? (signed in; staff only can turn it on)
  PUT  /api/me/test-mode              {"enabled": bool} -- staff numbers only (403 otherwise), expires by itself
  POST /api/diagnostics/test-events   a batch of allow-listed, masked events (stored only while Test Mode is on)
  GET  /admin/cc/test-mode/events     recent events + a summary (qa:view; a read-only staff token works)
  GET  /admin/cc/test-mode/testers    who has Test Mode on (qa:view)
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _require, command_center
from app.services import test_diagnostics as td

router = APIRouter(tags=["test-mode"])


def store(request: Request) -> td.TestDiagnosticsStore:
    container: Any = request.app.state.container
    existing = getattr(container, "test_diagnostics_store", None)
    if existing is None:
        existing = td.TestDiagnosticsStore(container.settings.database_path)
        container.test_diagnostics_store = existing
    return existing


def _app_user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


class TestModeBody(BaseModel):
    enabled: bool


class TestEventsBody(BaseModel):
    events: list[dict[str, Any]] = Field(default_factory=list, max_length=td.MAX_EVENTS_PER_CALL)
    session: str = Field(default="", max_length=40)
    app_version: str = Field(default="", max_length=40)


@router.get("/api/me/test-mode")
def my_test_mode(request: Request) -> dict:
    user = _app_user(request)
    staff = command_center(request.app.state.container).staff_by_app_user(user)
    return {**store(request).status(user), "allowed": bool(staff)}


@router.put("/api/me/test-mode")
def set_my_test_mode(body: TestModeBody, request: Request) -> dict:
    user = _app_user(request)
    staff = command_center(request.app.state.container).staff_by_app_user(user)
    if body.enabled and not staff:
        raise HTTPException(status_code=403, detail="Test Mode is only for ASKODOX staff numbers")
    result = store(request).set_enabled(user, body.enabled, staff_name=(staff or {}).get("name", ""))
    try:
        command_center(request.app.state.container).audit(
            f"staff-{staff['id']}" if staff else "app", "test_mode_on" if body.enabled else "test_mode_off",
            "test_mode", td.user_ref(user), None, {"expires_at": result.get("expires_at")},
            role=(staff or {}).get("role", ""))
    except Exception:
        pass
    return {**result, "allowed": bool(staff)}


@router.post("/api/diagnostics/test-events")
def test_events(body: TestEventsBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "test_events", limit=120)
    user = _app_user(request)
    return store(request).record(user, body.events, session=body.session, app_version=body.app_version)


@router.get("/admin/cc/test-mode/events")
def admin_test_events(request: Request, minutes: int = 180, kind: str = "", ref: str = "", limit: int = 300) -> dict:
    _require(request, "qa:view")
    rows = store(request).events(since_minutes=minutes, kind=kind, ref=ref, limit=limit)
    return {"summary": store(request).summary(rows), "items": rows}


@router.get("/admin/cc/test-mode/testers")
def admin_testers(request: Request) -> dict:
    _require(request, "qa:view")
    return {"items": store(request).testers()}
