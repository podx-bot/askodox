import hashlib
import secrets
import threading
import time
from dataclasses import dataclass

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

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
    with _lock:
        current = _otps.get(mobile)
        if current and now - current.last_sent_at < _RESEND_SECONDS:
            wait = max(1, int(_RESEND_SECONDS - (now - current.last_sent_at)))
            raise HTTPException(status_code=429, detail=f"Please wait {wait} seconds before requesting another OTP.")

        otp = f"{secrets.randbelow(1_000_000):06d}"
        entry = _OtpEntry(
            digest=_digest(mobile, otp),
            expires_at=now + _TTL_SECONDS,
            attempts_left=_MAX_ATTEMPTS,
            last_sent_at=now,
        )
        _otps[mobile] = entry

    service = request.app.state.container.whatsapp_service
    result = service.send_text_message(
        mobile,
        f"Your ASKODOX verification code is {otp}. It expires in 5 minutes. Do not share this code.",
    )
    if not result.get("success"):
        with _lock:
            _otps.pop(mobile, None)
        raise HTTPException(status_code=503, detail=f"OTP delivery failed: {result.get('status', 'provider error')}")

    return {"status": "sent", "channel": "whatsapp", "expires_in_seconds": _TTL_SECONDS}


@router.post("/otp/verify")
def verify_otp(payload: VerifyOtpRequest) -> dict:
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

    return {"status": "verified", "mobile": mobile}
