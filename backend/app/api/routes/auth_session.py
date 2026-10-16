"""The signed-in session on THIS phone: check it, sign it out, test a push.

* ``GET  /api/me/session``  -- is the stored session still valid? (401 when
  expired / signed out / revoked). The app checks this on every start so it
  never shows an authenticated profile without a valid identity.
* ``POST /api/me/logout``   -- signs out THIS session only: the token stops
  working everywhere (``session_logouts``), this phone's push token is
  unlinked. Nothing else is touched: profile, listings, orders, roles and
  business data stay on the server for the next sign-in.
* ``POST /api/me/push-test`` -- one test notification to the caller's OWN
  registered devices only (never anybody else, never a campaign), at most
  three per ten minutes, obeying their notification switches.
"""
from __future__ import annotations

import sqlite3
import threading
import time
from contextlib import closing

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services.session_tokens import DEFAULT_TTL_SECONDS, token_issued_at

router = APIRouter(prefix="/api/me", tags=["session"])

_PUSH_TEST_WINDOW = 600
_PUSH_TEST_MAX = 3
_push_tests: dict[str, list[float]] = {}
_push_lock = threading.Lock()


def _ensure(conn) -> None:
    conn.execute("CREATE TABLE IF NOT EXISTS session_logouts (user_id TEXT NOT NULL, issued_at INTEGER NOT NULL, "
                 "logged_out_at INTEGER NOT NULL, PRIMARY KEY (user_id, issued_at))")


def logged_out(database_path: str, user_id: str, issued_at: int) -> bool:
    """Revocation hook: this exact session was signed out."""
    with closing(sqlite3.connect(database_path)) as conn:
        _ensure(conn)
        return conn.execute("SELECT 1 FROM session_logouts WHERE user_id=? AND issued_at=?",
                            (user_id, int(issued_at))).fetchone() is not None


def _bearer(request: Request) -> str:
    header = request.headers.get("authorization") or ""
    return header[7:].strip() if header.lower().startswith("bearer ") else ""


@router.get("/session")
def session_status(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    container = request.app.state.container
    proven = token_issued_at(_bearer(request), container.settings.session_token_secret)
    issued_at = proven[1] if proven else int(time.time())
    from app.api.routes.onboarding_auth import _profile_summary

    return {"valid": True, "app_user_id": user_id, "issued_at": issued_at,
            "expires_at": issued_at + DEFAULT_TTL_SECONDS, "profile": _profile_summary(container, user_id)}


class LogoutRequest(BaseModel):
    push_token: str | None = Field(default=None, max_length=4096)


@router.post("/logout")
def logout(payload: LogoutRequest, request: Request) -> dict:
    """Always succeeds for the phone (an already-invalid session is simply
    reported); never deletes any account data."""
    container = request.app.state.container
    proven = token_issued_at(_bearer(request), container.settings.session_token_secret)
    if proven is None:
        return {"signed_out": True, "server_session": "already_invalid", "push_token_removed": False}
    user_id, issued_at = proven
    with closing(sqlite3.connect(container.settings.database_path)) as conn:
        _ensure(conn)
        conn.execute("INSERT OR IGNORE INTO session_logouts(user_id, issued_at, logged_out_at) VALUES(?,?,?)",
                     (user_id, issued_at, int(time.time())))
        conn.commit()
    removed = False
    token = (payload.push_token or "").strip()
    if token:
        from app.services.push_service import push_service

        push_service(container).unregister(user_id, token)
        removed = True
    return {"signed_out": True, "server_session": "revoked", "push_token_removed": removed}


@router.post("/push-test")
def push_test_to_my_devices(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    from app.api.routes.platform import platform

    service = platform(request.app.state.container).push()
    if not service.configured:
        return {"status": "NOT_CONFIGURED", "delivered": 0,
                "detail": "Push is not configured on the server (FIREBASE_SERVICE_ACCOUNT_JSON)."}
    if not service.tokens(user_id):
        return {"status": "NO_DEVICE_TOKENS", "delivered": 0,
                "detail": "This phone has not registered for push (needs an APK built with the Firebase values)."}
    now = time.time()
    with _push_lock:
        recent = [t for t in _push_tests.get(user_id, []) if now - t < _PUSH_TEST_WINDOW]
        if len(recent) >= _PUSH_TEST_MAX:
            raise HTTPException(status_code=429, detail="Too many test notifications. Try again in a few minutes.")
        _push_tests[user_id] = recent + [now]
    delivered = service.notify(user_id, title="ASKODOX test", body="Test notification to your own phone",
                               route="/updates", event_key=f"self-test:{int(now * 1000)}")
    return {"status": "SENT" if delivered else "NOT_DELIVERED", "delivered": delivered,
            "detail": "FCM accepted the message; check the phone." if delivered else
            "FCM did not accept it, or notifications are switched off in the app."}
