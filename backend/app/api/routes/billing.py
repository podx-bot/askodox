"""Billing routes (see ``app/services/billing.py``).

Customer (signed in): POST /api/billing/checkout, POST /api/billing/razorpay/verify,
GET /api/billing/purchases/mine, GET /api/billing/purchases/{id}
Staff: GET /admin/cc/billing/status, POST|DELETE /admin/cc/billing/testers,
POST /admin/cc/billing/purchases/{id}/refund
"""
from __future__ import annotations

import os
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import billing

router = APIRouter(prefix="/api/billing", tags=["billing"])
admin_router = APIRouter(prefix="/admin/cc/billing", tags=["command-center"])


class CheckoutBody(BaseModel):
    plan_code: str = Field(min_length=1, max_length=40)


@router.post("/checkout")
def start_checkout(body: CheckoutBody, request: Request) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "billing_checkout", limit=10)
    try:
        return billing.checkout(request.app.state.container, user, body.plan_code.strip())
    except billing.BillingError as error:
        raise HTTPException(status_code=error.status, detail=error.code) from None


class RazorpayVerifyBody(BaseModel):
    purchase_id: str = Field(min_length=3, max_length=40)
    razorpay_order_id: str = Field(min_length=3, max_length=64)
    razorpay_payment_id: str = Field(min_length=3, max_length=64)
    razorpay_signature: str = Field(min_length=10, max_length=128)


@router.post("/razorpay/verify")
def razorpay_verify(body: RazorpayVerifyBody, request: Request) -> dict:
    """Razorpay Checkout's success callback: activates only on a valid
    HMAC signature (key_secret, "order_id|payment_id")."""
    from app.api.routes.platform import platform

    user = _authenticated_app_user(request)
    container = request.app.state.container
    purchase = billing.store(container).get(body.purchase_id)
    if not purchase or purchase["user_id"] != user:
        raise HTTPException(status_code=404, detail="Purchase not found")
    pf = platform(container)
    try:
        result = pf.razorpay.verify_checkout(body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature)
    except PermissionError:
        raise HTTPException(status_code=401, detail="INVALID_SIGNATURE") from None
    except KeyError:
        raise HTTPException(status_code=404, detail="Unknown order") from None
    if result["payment"]["id"] != purchase["payment_id"]:
        raise HTTPException(status_code=409, detail="ORDER_MISMATCH")
    pf.sync_order(result["payment"])
    return {"purchase": _public(billing.store(container).get(purchase["id"]))}


def _public(p: dict | None) -> dict | None:
    if not p:
        return None
    return {k: p[k] for k in ("id", "plan_code", "kind", "amount", "mode", "status", "created_at", "updated_at")}


@router.get("/purchases/mine")
def my_purchases(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"items": [_public(p) for p in billing.store(request.app.state.container).list(user_id=user, limit=50)]}


@router.get("/purchases/{purchase_id}")
def my_purchase(purchase_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    purchase = billing.store(request.app.state.container).get(purchase_id)
    if not purchase or purchase["user_id"] != user:
        raise HTTPException(status_code=404, detail="Purchase not found")
    return {"purchase": _public(purchase)}


# -------------------------------------------------------------- staff --

def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict) -> None:
    try:
        from app.api.routes.command_center import command_center

        command_center(request.app.state.container).audit(principal["id"], action, "billing", target, after=detail)
    except Exception:
        pass


@admin_router.get("/status")
def billing_status(request: Request) -> dict:
    """One honest page: gateways (TEST / LIVE / locked / missing), Firebase,
    switches, plans, testers and recent purchases. Secrets are never shown."""
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.growth import growth
    from app.api.routes.platform import platform
    from app.api.routes.push_admin import readiness_for
    from app.services import commerce_finance as fin

    _require(request, "growth:view")
    container = request.app.state.container
    pf = platform(container)
    gateways = []
    for provider in pf.CHECKOUT_PROVIDERS:
        st = pf.registry.status(provider)
        gateways.append({"provider": provider, "label": st["label"], "status": st["status"], "mode": st["mode"],
                         "readiness": st["readiness"], "missing": st["missing"], "live_locked": st.get("live_locked"),
                         "warnings": st.get("warnings") or []})
    plans = growth(container).plans()
    return {
        "checkout_provider": pf.checkout_provider(),
        "live_payments_approved": fin.live_payments_approved(dict(os.environ)),
        "live_approval_variable": fin.LIVE_APPROVAL_ENV,
        "flags": {"billing.live_pricing": feature_enabled(container, "billing.live_pricing"),
                  "payments.online": feature_enabled(container, "payments.online")},
        "gateways": gateways,
        "firebase": readiness_for(pf.push()),
        "plans": [{"code": p["code"], "audience": p["audience"], "price": p["price"], "period_days": p["period_days"],
                   "trial_days": p["trial_days"], "on_sale": p["active"]} for p in plans
                  if p.get("audience") in ("base", "addon_radio")],
        "testers": billing.store(container).testers(),
        "purchases": billing.store(container).list(limit=50),
    }


class TesterBody(BaseModel):
    user_id: str = Field(min_length=3, max_length=80)


@admin_router.post("/testers")
def add_tester(body: TesterBody, request: Request) -> dict:
    """A billing tester may pay in TEST (sandbox) mode only -- no real money."""
    principal = _require(request, "growth:manage")
    billing.store(request.app.state.container).add_tester(body.user_id.strip(), str(principal.get("id")))
    _audit(request, principal, "billing.tester.add", body.user_id.strip(), {})
    return {"user_id": body.user_id.strip(), "tester": True}


@admin_router.delete("/testers/{user_id}")
def remove_tester(user_id: str, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    removed = billing.store(request.app.state.container).remove_tester(user_id)
    _audit(request, principal, "billing.tester.remove", user_id, {"removed": removed})
    return {"user_id": user_id, "removed": removed}


class RefundBody(BaseModel):
    confirm: bool = False
    amount: float | None = Field(default=None, gt=0)


@admin_router.post("/purchases/{purchase_id}/refund")
def refund_purchase(purchase_id: str, body: RefundBody, request: Request) -> dict:
    """Asks the gateway to refund; the plan / pass is cancelled only when the
    gateway's signed webhook confirms the refund."""
    from app.api.routes.platform import platform

    principal = _require(request, "payments:manage")
    if not body.confirm:
        raise HTTPException(status_code=409, detail="Confirmation required to refund")
    container = request.app.state.container
    purchase = billing.store(container).get(purchase_id)
    if not purchase or purchase["status"] != "ACTIVE":
        raise HTTPException(status_code=409, detail="Only an active, paid purchase can be refunded")
    pf = platform(container)
    payment = pf.repo.payment(purchase["payment_id"])
    amount = body.amount or float(payment["amount"]) - float(payment.get("refunded_amount") or 0)
    try:
        result = pf.gateway_refund(payment, amount, refund_id=f"rf_{purchase_id}")
    except Exception as error:
        raise HTTPException(status_code=409, detail=str(error)[:200]) from None
    _audit(request, principal, "billing.refund.requested", purchase_id, {"amount": amount})
    return {"requested": result, "note": "The plan is cancelled when the gateway confirms the refund."}
