"""Push notification readiness + a staff test send (Firebase Cloud Messaging).

Truthful by construction:
- server credentials come only from FIREBASE_SERVICE_ACCOUNT_JSON (never
  invented); without them every answer says NOT_CONFIGURED;
- the Android app has no FCM client until a Firebase app + google-services.json
  exist, so devices cannot register tokens yet (``android_client``);
- a test send goes only to the chosen user's own registered devices, respects
  their notification switches, and reports what FCM actually accepted.
Delivery on a phone is proven only by a real-device test (QA checks)."""
from __future__ import annotations

import sqlite3
import time
from contextlib import closing
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

admin_router = APIRouter(prefix="/admin/cc/push", tags=["command-center"])

# The Android FCM client is in the app (lib/services/push_registration.dart)
# but activates only in an APK built with the Firebase repository variables.
# A registered device token is the only evidence that an APK has them.
ANDROID_CLIENT = "BUILT_NEEDS_FIREBASE_VALUES"
MISSING_WHEN_UNCONFIGURED = (
    "Railway variable FIREBASE_SERVICE_ACCOUNT_JSON (service account of the Firebase project), or the same JSON "
    "saved in Command Center -> Integrations -> Firebase push",
    "GitHub repository variables FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_SENDER_ID, FIREBASE_PROJECT_ID "
    "(Firebase Android app), then a new APK build",
)


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _service(request: Request):
    """The same sender production uses: credentials saved in the Command
    Center (fcm_push) or the FIREBASE_SERVICE_ACCOUNT_JSON variable."""
    from app.api.routes.platform import platform

    return platform(request.app.state.container).push()


def _token_counts(service: Any) -> tuple[int, int]:
    with closing(sqlite3.connect(service.database_path)) as conn:
        row = conn.execute("SELECT COUNT(*), COUNT(DISTINCT user_id) FROM push_tokens").fetchone()
    return int(row[0] or 0), int(row[1] or 0)


def readiness_for(service: Any) -> dict:
    tokens, users = _token_counts(service)
    if not service.configured:
        state = "NOT_CONFIGURED"
    elif not tokens:
        state = "SERVER_READY_NO_DEVICES"
    else:
        state = "READY_UNVERIFIED"  # only a real phone test proves delivery
    return {
        "state": state, "server_credentials": service.configured,
        "android_client": "REGISTERING" if tokens else ANDROID_CLIENT,
        "device_tokens": tokens, "users_with_devices": users,
        "missing": ([MISSING_WHEN_UNCONFIGURED[0]] if not service.configured else [])
        + ([MISSING_WHEN_UNCONFIGURED[1]] if not tokens else []),
        "test_procedure": "docs/push-test-procedure.md",
    }


@admin_router.get("/readiness")
def push_readiness(request: Request) -> dict:
    _require(request, "health:view")
    return readiness_for(_service(request))


class TestPush(BaseModel):
    user_id: str = Field(min_length=3, max_length=80)


@admin_router.post("/test")
def push_test(payload: TestPush, request: Request) -> dict:
    principal = _require(request, "integrations:manage")
    service = _service(request)
    if not service.configured:
        raise HTTPException(status_code=409, detail={"status": "NOT_CONFIGURED",
                                                     "missing": list(MISSING_WHEN_UNCONFIGURED[:1])})
    user = payload.user_id.strip()
    if not service.tokens(user):
        return {"status": "NO_DEVICE_TOKENS", "delivered": 0,
                "detail": "This user has no registered device (the app needs the FCM client)."}
    delivered = service.notify(user, title="ASKODOX test", body="Test notification from ASKODOX staff",
                               route="/updates", event_key=f"staff-test:{int(time.time() * 1000)}")
    try:
        from app.api.routes.command_center import command_center

        command_center(request.app.state.container).audit(principal["id"], "push.test", "user", user,
                                                          after={"delivered": delivered})
    except Exception:
        pass
    return {"status": "SENT" if delivered else "NOT_DELIVERED", "delivered": delivered,
            "detail": "FCM accepted the message" if delivered else
            "FCM did not accept it, or the user switched these notifications off"}
