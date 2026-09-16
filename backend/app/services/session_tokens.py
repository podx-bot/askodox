"""Issue and verify signed session tokens proving a real OTP verification.

Added 2026-09-16 (round 10) to close the "identity spoofing" gap found by
the full repository audit: OTP verification itself has always been real
(see onboarding_auth.py -- server-side random code, SHA-256 hashed,
secrets.compare_digest checked, 5-minute expiry, 5-attempt limit) but
nothing was ever issued *after* a successful verification. Every later
request -- placing an order, seeing incoming orders, accepting/rejecting
an order -- simply trusted a client-supplied "app-phone-<digits>" string
with zero proof anyone had ever verified that number. Any client could
claim to be any other user's phone number and see or act on their orders
(including the other party's real phone number, once revealed).

This module signs the verified identity into an opaque bearer token at
the moment /onboarding/otp/verify succeeds. Every request that needs to
know "who is really making this call" (see orders.py's
`_authenticated_app_user`) verifies that token instead of trusting a
client-supplied id field.

Token shape: "<url-safe-base64 payload>.<url-safe-base64 HMAC-SHA256 sig>"
payload = "<app_user_id>:<issued_at-epoch-seconds>"

Deliberately dependency-free (no fastapi/pydantic import) so it can be
unit-tested directly in any plain Python environment and reused as-is by
both the route that issues a token and the dependency that verifies one.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import time

# 30 days -- matches the session lifetime AuthController.completeOnboarding
# already uses on the Flutter side (see auth_controller.dart).
DEFAULT_TTL_SECONDS = 30 * 24 * 60 * 60

# How far into the future an "issued_at" is still tolerated. Guards against
# verify_token rejecting a legitimately-issued token over ordinary small
# clock drift between processes, without opening any real window for a
# forged future-dated token (the signature check below still runs first).
_CLOCK_SKEW_SECONDS = 60


def _b64encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64decode(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def _sign(payload: bytes, secret: str) -> str:
    return _b64encode(hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).digest())


def issue_token(app_user_id: str, secret: str, *, issued_at: int | None = None) -> str:
    """Create a signed bearer token proving `app_user_id` just completed OTP verification.

    Raises ValueError if `app_user_id` is blank -- callers must only call
    this after a real, successful OTP verification (never speculatively).
    """
    clean_user_id = str(app_user_id or "").strip()
    if not clean_user_id:
        raise ValueError("app_user_id is required to issue a session token")
    if not str(secret or ""):
        raise ValueError("secret is required to issue a session token")
    ts = int(issued_at if issued_at is not None else time.time())
    payload = f"{clean_user_id}:{ts}".encode("utf-8")
    return f"{_b64encode(payload)}.{_sign(payload, secret)}"


def verify_token(
    token: str,
    secret: str,
    *,
    now: int | None = None,
    ttl_seconds: int = DEFAULT_TTL_SECONDS,
) -> str | None:
    """Return the app_user_id proven by `token`, or None if it does not check out.

    Returns None (never raises) for: a blank/malformed token, a bad
    signature (including one signed with a different secret), a token
    whose signature is valid but whose payload cannot be parsed, an
    expired token, or a token implausibly far in the future. Callers
    should treat None the same as "not authenticated" (401), same as a
    missing token.
    """
    clean_token = str(token or "").strip()
    if not clean_token or "." not in clean_token:
        return None
    encoded_payload, _, signature = clean_token.partition(".")
    if not encoded_payload or not signature:
        return None
    try:
        payload = _b64decode(encoded_payload)
    except Exception:
        return None
    expected_signature = _sign(payload, secret)
    if not hmac.compare_digest(signature, expected_signature):
        return None
    try:
        text = payload.decode("utf-8")
        user_id, sep, ts_text = text.rpartition(":")
        if not sep:
            return None
        issued_at = int(ts_text)
    except (ValueError, UnicodeDecodeError):
        return None
    if not user_id:
        return None
    current = int(now if now is not None else time.time())
    if current - issued_at > ttl_seconds:
        return None
    if issued_at - current > _CLOCK_SKEW_SECONDS:
        return None
    return user_id
