import hashlib
import os
import secrets
import threading
import time
from dataclasses import dataclass

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from app.services.session_tokens import issue_token

router = APIRouter(prefix="/onboarding", tags=["Onboarding"])


@dataclass
class _OtpEntry:
    digest: str
    expires_at: float
    attempts_left: int
    last_sent_at: float


_lock = threading.RLock()
_otps: dict[str, _OtpEntry] = {}
_TTL_SECONDS = 5 * 60
_RESEND_SECONDS = 45
_MAX_ATTEMPTS = 5
_TEST_OTP = "123456"
# Public demo-only number. This is intentionally not a real user's mobile number.
_DEMO_MOBILE = "919999999999"


def _test_mode() -> bool:
    return os.getenv("ASKODOX_TEST_OTP_MODE", "false").strip().lower() in {"1", "true", "yes", "on"}


def _test_mobiles() -> set[str]:
    raw = os.getenv("ASKODOX_TEST_OTP_MOBILES", "")
    return {"".join(ch for ch in value if ch.isdigit()) for value in raw.split(",") if value.strip()}


def _production() -> bool:
    from app.services.commerce_finance import is_production

    return is_production(dict(os.environ))


def demo_login_allowed() -> bool:
    """The shared demo number (fixed OTP) is a test convenience, never a
    production bypass: off in production unless the Owner explicitly sets
    ASKODOX_DEMO_LOGIN=yes for a test session. Elsewhere (local / staging /
    CI) it stays available."""
    if not _production():
        return True
    return os.getenv("ASKODOX_DEMO_LOGIN", "").strip().lower() in {"1", "true", "yes", "on"}


def _is_test_mobile(mobile: str) -> bool:
    # Environment-controlled test mobiles (ASKODOX_TEST_OTP_MODE) and the isolated
    # non-user demo number -- both fixed-OTP conveniences, so neither works in
    # production without an explicit Owner switch.
    if mobile == _DEMO_MOBILE:
        return demo_login_allowed()
    allowed = _test_mobiles()
    if _production() and not demo_login_allowed():
        return False
    return _test_mode() and bool(allowed) and mobile in allowed


def _mobile(value: str) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    if len(digits) < 10 or len(digits) > 15:
        raise HTTPException(status_code=422, detail="Enter a valid mobile number with country code.")
    return digits


def _digest(mobile: str, otp: str) -> str:
    return hashlib.sha256(f"{mobile}:{otp}".encode()).hexdigest()


class SendOtpRequest(BaseModel):
    mobile: str


class VerifyOtpRequest(BaseModel):
    mobile: str
    otp: str


@router.post("/otp/send")
def send_otp(payload: SendOtpRequest, request: Request) -> dict:
    mobile = _mobile(payload.mobile)
    now = time.time()
    is_test = _is_test_mobile(mobile)
    with _lock:
        current = _otps.get(mobile)
        if current and now - current.last_sent_at < _RESEND_SECONDS:
            wait = max(1, int(_RESEND_SECONDS - (now - current.last_sent_at)))
            raise HTTPException(status_code=429, detail=f"Please wait {wait} seconds before requesting another OTP.",
                                headers={"Retry-After": str(wait)})

        otp = _TEST_OTP if is_test else f"{secrets.randbelow(1_000_000):06d}"
        entry = _OtpEntry(
            digest=_digest(mobile, otp),
            expires_at=now + _TTL_SECONDS,
            attempts_left=_MAX_ATTEMPTS,
            last_sent_at=now,
        )
        _otps[mobile] = entry

    if is_test:
        # The fixed OTP is only for explicit test/demo numbers; no message is sent.
        return {"status": "sent", "channel": "test", "expires_in_seconds": _TTL_SECONDS,
                "resend_after_seconds": _RESEND_SECONDS}

    from app.services import otp_delivery

    result = otp_delivery.deliver(
        request.app.state.container, mobile,
        f"Your ASKODOX verification code is {otp}. It expires in 5 minutes. Do not share this code.",
    )
    if not result.get("success"):
        with _lock:
            _otps.pop(mobile, None)
        failed = [a for a in result["attempts"] if a["outcome"] == "failed"]
        undelivered = [a["reason"][len("undelivered: "):] for a in failed
                       if str(a.get("reason", "")).startswith("undelivered: ")]
        if undelivered:
            detail = "The code could not be delivered: " + undelivered[0] + "."
        elif failed:
            detail = "OTP delivery failed (" + ", ".join(a["channel"] for a in failed) + "). Try again in a minute."
        else:
            detail = "OTP delivery is not configured (no WhatsApp or SMS provider is set up)"
        raise HTTPException(status_code=503, detail=detail)

    return {"status": "sent", "channel": result["channel"], "expires_in_seconds": _TTL_SECONDS,
            "resend_after_seconds": _RESEND_SECONDS}


@router.post("/otp/verify")
def verify_otp(payload: VerifyOtpRequest, request: Request) -> dict:
    mobile = _mobile(payload.mobile)
    otp = "".join(ch for ch in str(payload.otp or "") if ch.isdigit())
    if len(otp) != 6:
        raise HTTPException(status_code=422, detail="Enter the 6-digit OTP.")

    now = time.time()
    with _lock:
        entry = _otps.get(mobile)
        if entry is None:
            raise HTTPException(status_code=400, detail="Request a new OTP first.")
        if now > entry.expires_at:
            _otps.pop(mobile, None)
            raise HTTPException(status_code=400, detail="OTP expired. Request a new OTP.")
        if entry.attempts_left <= 0:
            _otps.pop(mobile, None)
            raise HTTPException(status_code=429, detail="Too many attempts. Request a new OTP.")
        if not secrets.compare_digest(entry.digest, _digest(mobile, otp)):
            entry.attempts_left -= 1
            raise HTTPException(status_code=400, detail="Incorrect OTP.")
        _otps.pop(mobile, None)

    # Added 2026-09-16 (round 10): this is the fix for the "identity
    # spoofing" gap the full audit found. Until now, verifying an OTP
    # proved the mobile number was real but nothing was ever issued to
    # carry that proof forward -- every later request (placing an order,
    # seeing someone else's phone number once an order is accepted, etc.)
    # just trusted a client-supplied "app-phone-<digits>" string. This
    # signs the verified identity into an opaque bearer token (see
    # session_tokens.py) that the Flutter app now stores and sends as
    # `Authorization: Bearer <token>` on every request that needs to know
    # who is really acting -- see orders.py's `_authenticated_app_user`.
    return signed_in(request.app.state.container, mobile)


def signed_in(container, mobile_digits: str) -> dict:
    """The ONE place a verified number becomes a session (server OTP and
    Firebase phone sign-in alike): one account per number, a signed session
    token, and -- for a returning person -- the profile they already have, so
    the app restores it instead of asking again (nothing is created twice)."""
    from app.services import account_identity

    settings = container.settings
    # ONE account per number however it was typed (phase 5): the first id
    # issued for this number is reused; older profiles are adopted.
    resolved = account_identity.resolve(settings.database_path, mobile_digits)
    app_user_id = resolved["user_id"]
    token = issue_token(app_user_id, settings.session_token_secret)
    profile = _profile_summary(container, app_user_id)
    returning = resolved["source"] != "new_account" or bool(profile.get("name"))
    return {"status": "verified", "mobile": mobile_digits, "app_user_id": app_user_id, "token": token,
            "returning": returning, "profile": profile}


def _profile_summary(container, user_id: str) -> dict:
    try:
        from app.api.routes.profile import profiles

        data = profiles(container).get(user_id)
    except Exception:
        return {}
    return {"name": (data.get("name") or "").strip(), "language": data.get("language") or "",
            "roles": list(data.get("roles") or [])}


@router.get("/methods")
def sign_in_methods(request: Request) -> dict:
    """How this server can prove a phone number right now (no secrets): the
    app uses Firebase phone sign-in only when the Owner switched it on, else
    the server's own code delivery (WhatsApp / SMS)."""
    from app.services import firebase_id_token, otp_delivery

    try:
        server_channels = [c["channel"] for c in otp_delivery.channels(request.app.state.container) if c["ready"]]
    except Exception:
        server_channels = []
    return {"firebase_phone_auth": firebase_id_token.phone_auth_enabled(),
            "server_otp": bool(server_channels), "server_channels": server_channels,
            "resend_seconds": _RESEND_SECONDS, "code_ttl_seconds": _TTL_SECONDS}


class FirebaseVerifyRequest(BaseModel):
    id_token: str


@router.post("/firebase/verify")
def verify_firebase(payload: FirebaseVerifyRequest, request: Request) -> dict:
    """Firebase phone sign-in -> ASKODOX session. The ID token is verified
    here (signature, project, times); the app's claim alone is never trusted."""
    from app.services import firebase_id_token

    project = firebase_id_token.project_id()
    if not project:
        raise HTTPException(status_code=503, detail="Firebase sign-in is not configured on the server")
    try:
        claims = firebase_id_token.verify(payload.id_token, project)
    except firebase_id_token.InvalidIdToken as error:
        raise HTTPException(status_code=401, detail=f"Sign-in could not be verified ({error})") from None
    except Exception:
        raise HTTPException(status_code=503, detail="Sign-in could not be checked right now. Try again.") from None
    return signed_in(request.app.state.container, _mobile(claims["phone_number"]))
