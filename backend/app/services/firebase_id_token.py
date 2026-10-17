"""Verify a Firebase Authentication ID token (phone sign-in) on the server.

The app may prove a phone number with Firebase Phone Auth; the server never
trusts the app's word for it. It checks the ID token exactly as Firebase
documents (RS256 signature against Google's published securetoken
certificates, ``aud`` = the Firebase project id, ``iss`` =
``https://securetoken.google.com/<project>``, ``exp`` / ``iat`` /
``auth_time``, non-empty ``sub``) and only then reads ``phone_number``.

No service-account secret is needed for this: the certificates are public.
Configuration = the Firebase project id (``FIREBASE_PROJECT_ID``, or the
project of the FCM service account). With it, Firebase phone sign-in is the
primary sign-in (``phone_auth_enabled``); ``ASKODOX_FIREBASE_PHONE_AUTH=no``
turns it off. Google bills phone sign-in SMS beyond the free tier.

Never logs the token or the phone number.
"""
from __future__ import annotations

import base64
import json
import os
import re
import threading
import time
import urllib.request
from typing import Any, Callable, Dict, Optional, Tuple

CERTS_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
_CLOCK_SKEW = 60
_E164 = re.compile(r"^\+[1-9]\d{7,14}$")

_lock = threading.Lock()
_cache: Dict[str, Any] = {"certs": None, "until": 0.0}


class InvalidIdToken(ValueError):
    """The token does not prove a Firebase phone sign-in (reason is safe to show)."""


def _b64(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def project_id(env: Optional[Dict[str, str]] = None) -> str:
    """The Firebase project id: FIREBASE_PROJECT_ID, else the FCM service
    account's project (same Firebase project). Empty = not configured."""
    env = dict(os.environ) if env is None else env
    from app.services.commerce_finance import env_value

    value = env_value(env, "firebase_auth", "project_id")
    if value:
        return value
    raw = str(env.get("FIREBASE_SERVICE_ACCOUNT_JSON") or "").strip()
    if raw:
        try:
            return str(json.loads(raw).get("project_id") or "").strip()
        except (ValueError, AttributeError):
            return ""
    return ""


def phone_auth_enabled(env: Optional[Dict[str, str]] = None) -> bool:
    """Firebase phone sign-in (Google sends the SMS) is the PRIMARY way to
    sign in whenever the server can verify its ID tokens (project id known).
    ASKODOX_FIREBASE_PHONE_AUTH=no switches it off (the server OTP -- WhatsApp
    / SMS -- is then the only way in)."""
    env = dict(os.environ) if env is None else env
    off = str(env.get("ASKODOX_FIREBASE_PHONE_AUTH") or "").strip().lower() in {"0", "false", "no", "off"}
    return not off and bool(project_id(env))


def _fetch_certs() -> Tuple[Dict[str, str], float]:
    with urllib.request.urlopen(CERTS_URL, timeout=8) as response:  # noqa: S310 (fixed https URL)
        body = json.loads(response.read().decode("utf-8"))
        control = response.headers.get("Cache-Control", "")
    match = re.search(r"max-age=(\d+)", control or "")
    return {str(k): str(v) for k, v in body.items()}, float(match.group(1)) if match else 3600.0


def _certs(fetch: Callable[[], Tuple[Dict[str, str], float]], now: float) -> Dict[str, str]:
    with _lock:
        if _cache["certs"] and now < _cache["until"]:
            return _cache["certs"]
    certs, max_age = fetch()
    with _lock:
        _cache["certs"], _cache["until"] = certs, now + max(60.0, min(max_age, 24 * 3600.0))
    return certs


def verify(id_token: str, project: str, *, fetch: Callable[[], Tuple[Dict[str, str], float]] | None = None,
           now: float | None = None) -> Dict[str, Any]:
    """Claims of a valid Firebase phone sign-in token, else InvalidIdToken."""
    if not project:
        raise InvalidIdToken("Firebase sign-in is not configured on the server")
    parts = str(id_token or "").strip().split(".")
    if len(parts) != 3 or not all(parts):
        raise InvalidIdToken("malformed token")
    try:
        header = json.loads(_b64(parts[0]))
        claims = json.loads(_b64(parts[1]))
        signature = _b64(parts[2])
    except (ValueError, json.JSONDecodeError):
        raise InvalidIdToken("malformed token") from None
    if header.get("alg") != "RS256" or not header.get("kid"):
        raise InvalidIdToken("unexpected token algorithm")
    current = float(now if now is not None else time.time())
    certs = _certs(fetch or _fetch_certs, current)
    pem = certs.get(str(header["kid"]))
    if not pem:
        raise InvalidIdToken("unknown signing key")
    from cryptography import x509
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import padding

    try:
        x509.load_pem_x509_certificate(pem.encode()).public_key().verify(
            signature, f"{parts[0]}.{parts[1]}".encode(), padding.PKCS1v15(), hashes.SHA256())
    except (InvalidSignature, ValueError):
        raise InvalidIdToken("bad signature") from None
    if claims.get("aud") != project or claims.get("iss") != f"https://securetoken.google.com/{project}":
        raise InvalidIdToken("token is for another Firebase project")
    try:
        exp, iat = float(claims["exp"]), float(claims["iat"])
        auth_time = float(claims.get("auth_time", iat))
    except (KeyError, TypeError, ValueError):
        raise InvalidIdToken("token times are missing") from None
    if exp <= current:
        raise InvalidIdToken("token expired")
    if iat > current + _CLOCK_SKEW or auth_time > current + _CLOCK_SKEW:
        raise InvalidIdToken("token issued in the future")
    if not str(claims.get("sub") or "").strip():
        raise InvalidIdToken("token has no subject")
    phone = str(claims.get("phone_number") or "").strip()
    if not _E164.match(phone):
        raise InvalidIdToken("token is not a phone sign-in")
    return {"uid": str(claims["sub"]), "phone_number": phone, "auth_time": int(auth_time)}


def clear_cache() -> None:
    with _lock:
        _cache["certs"], _cache["until"] = None, 0.0
