"""Short-lived Staff Workspace sessions and one-time app->browser handoff codes.

A staff member signs in with their own OTP-verified number (the same
``/onboarding/otp`` flow as the app); if that number is linked to an ACTIVE
staff record they get a signed session (``x-askodox-staff-session``) that
expires after ``SESSION_SECONDS``. Permissions are re-read from the staff
record on every request, so revoking a grant or deactivating staff takes
effect immediately. Long-lived ``stf_`` tokens keep working for the console.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import threading
import time
from typing import Optional

SESSION_SECONDS = 12 * 3600
HANDOFF_SECONDS = 120
_DOMAIN = b"askodox-staff-session-v1"
_codes: dict[str, tuple[int, float]] = {}
_lock = threading.Lock()


def _key(secret: str) -> bytes:
    return hmac.new(str(secret or "").encode(), _DOMAIN, hashlib.sha256).digest()


def issue(staff_id: int, secret: str, *, now: float | None = None) -> str:
    expires = int((now or time.time()) + SESSION_SECONDS)
    body = f"{int(staff_id)}.{expires}"
    sig = base64.urlsafe_b64encode(hmac.new(_key(secret), body.encode(), hashlib.sha256).digest()).decode().rstrip("=")
    return f"sts.{body}.{sig}"


def verify(token: str, secret: str, *, now: float | None = None) -> Optional[int]:
    try:
        prefix, staff_id, expires, sig = str(token or "").split(".")
    except ValueError:
        return None
    if prefix != "sts" or not secret:
        return None
    body = f"{staff_id}.{expires}"
    good = base64.urlsafe_b64encode(hmac.new(_key(secret), body.encode(), hashlib.sha256).digest()).decode().rstrip("=")
    if not hmac.compare_digest(good, sig):
        return None
    try:
        if int(expires) < (now or time.time()):
            return None
        return int(staff_id)
    except ValueError:
        return None


def handoff_code(staff_id: int) -> str:
    code = secrets.token_urlsafe(18)
    with _lock:
        now = time.time()
        for key in [k for k, (_, exp) in _codes.items() if exp < now]:
            _codes.pop(key, None)
        _codes[code] = (int(staff_id), now + HANDOFF_SECONDS)
    return code


def redeem(code: str) -> Optional[int]:
    with _lock:
        found = _codes.pop(str(code or ""), None)  # single use
    if not found or found[1] < time.time():
        return None
    return found[0]
