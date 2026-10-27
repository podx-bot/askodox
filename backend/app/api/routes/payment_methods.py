"""``/api/me/payment-methods`` -- the signed-in person's OWN ways to be paid (UPI / QR, bank). ASKODOX never
holds money: these are only shown to a counter-party who is entitled to pay them (see orders / POS collect)."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import rate_limit
from app.services.payment_methods import PaymentMethodError, PaymentMethods, parse_upi_qr

router = APIRouter(prefix="/api/me/payment-methods", tags=["Payment methods"])


def payment_methods(container: Any) -> PaymentMethods:
    from app.services.secret_box import box_from_settings

    existing = getattr(container, "payment_methods", None)
    if existing is None or existing.db_path != container.settings.database_path:
        existing = PaymentMethods(container.settings.database_path, box_from_settings(container.settings))
        try:
            container.payment_methods = existing
        except Exception:
            pass
    return existing


def _call(fn, *args):
    try:
        return fn(*args)
    except PaymentMethodError as error:
        raise HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message})


def _user(request: Request) -> str:
    user = _authenticated_app_user(request)
    rate_limit.check(request, f"paymethods:{user}", limit=60)
    return user


class MethodIn(BaseModel):
    kind: str = Field(pattern="^(upi|bank)$")
    label: str = Field(default="", max_length=40)
    app: str = Field(default="", max_length=30)
    upi_id: Optional[str] = Field(default=None, max_length=120)
    qr_text: Optional[str] = Field(default=None, max_length=1000)
    payee_name: Optional[str] = Field(default=None, max_length=60)
    bank_name: Optional[str] = Field(default=None, max_length=40)
    account_holder: Optional[str] = Field(default=None, max_length=60)
    account_number: Optional[str] = Field(default=None, max_length=30)
    ifsc: Optional[str] = Field(default=None, max_length=11)
    is_default: bool = False


class QrIn(BaseModel):
    qr_text: str = Field(min_length=3, max_length=1000)


@router.get("")
def list_methods(request: Request) -> dict:
    return {"methods": payment_methods(request.app.state.container).list(_user(request)),
            "note": "Payers pay you directly. ASKODOX never holds or moves money."}


@router.post("")
def add_method(body: MethodIn, request: Request) -> dict:
    return {"methods": _call(payment_methods(request.app.state.container).add, _user(request), body.model_dump())}


@router.post("/read-qr")
def read_qr(body: QrIn, request: Request) -> dict:
    """Preview what a scanned QR contains before saving (UPI ID + name)."""
    _user(request)
    return _call(parse_upi_qr, body.qr_text)


@router.post("/{method_id}/default")
def make_default(method_id: str, request: Request) -> dict:
    return {"methods": _call(payment_methods(request.app.state.container).set_default, _user(request), method_id)}


@router.delete("/{method_id}")
def delete_method(method_id: str, request: Request) -> dict:
    return {"methods": _call(payment_methods(request.app.state.container).remove, _user(request), method_id)}
