"""Billing routes (see ``app/services/billing.py``).

Customer (signed in): GET /api/billing/options, POST /api/billing/checkout,
POST /api/billing/razorpay/verify, GET /api/billing/purchases/mine,
GET /api/billing/purchases/{id} (reconciles an open purchase with the gateway),
POST /api/billing/purchases/{id}/cancel
Hosted checkout (browser, purchase-bound short-lived link token):
GET /billing/pay/{id}?t=..., POST /api/billing/pay/{id}/verify|cancel,
GET /api/billing/pay/{id}/status
Staff: GET /admin/cc/billing/status, POST|DELETE /admin/cc/billing/testers,
POST /admin/cc/billing/purchases/{id}/refund, POST /admin/cc/billing/purchases/{id}/reconcile
"""
from __future__ import annotations

import os
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import billing

router = APIRouter(prefix="/api/billing", tags=["billing"])
admin_router = APIRouter(prefix="/admin/cc/billing", tags=["command-center"])
page_router = APIRouter(tags=["billing"])


def _public_base(request: Request) -> str:
    from app.api.routes.partners import _public_base as base

    return base(request)


def _pay_url(request: Request, purchase_id: str) -> str:
    container = request.app.state.container
    return f"{_public_base(request)}/billing/pay/{purchase_id}?t={billing.pay_token(container, purchase_id)}"


@router.get("/options")
def billing_options(request: Request) -> dict:
    """Which plans this user may pay for now (server rules; TEST mode = testers only)."""
    user = _authenticated_app_user(request)
    return billing.options(request.app.state.container, user)


class CheckoutBody(BaseModel):
    plan_code: str = Field(min_length=1, max_length=40)


@router.post("/checkout")
def start_checkout(body: CheckoutBody, request: Request) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "billing_checkout", limit=10)
    try:
        out = billing.checkout(request.app.state.container, user, body.plan_code.strip())
    except billing.BillingError as error:
        raise HTTPException(status_code=error.status, detail=error.code) from None
    if out["checkout"].get("provider") == "razorpay":
        out["pay_url"] = _pay_url(request, out["purchase_id"])  # hosted Razorpay Checkout page
    return out


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
    return {"purchase": _public(_verify(container, purchase, body.razorpay_order_id, body.razorpay_payment_id,
                                        body.razorpay_signature, actor=f"user:{user}"))}


def _verify(container: Any, purchase: dict, order_id: str, rzp_payment_id: str, signature: str, *, actor: str) -> dict:
    from app.api.routes.platform import platform

    pf = platform(container)
    if purchase.get("provider") != "razorpay" or pf.razorpay.order_for(purchase.get("payment_id") or "") != order_id:
        billing.store(container).log(purchase["id"], "verify_rejected", actor, {"reason": "order_mismatch"})
        raise HTTPException(status_code=409, detail="ORDER_MISMATCH")  # checked BEFORE any state change
    try:
        result = pf.razorpay.verify_checkout(order_id, rzp_payment_id, signature)
    except PermissionError:
        billing.store(container).log(purchase["id"], "verify_rejected", actor, {"reason": "invalid_signature"})
        raise HTTPException(status_code=401, detail="INVALID_SIGNATURE") from None
    except KeyError:
        raise HTTPException(status_code=404, detail="Unknown order") from None
    billing.store(container).log(purchase["id"], "checkout_verified", actor,
                                 {"duplicate": bool(result.get("duplicate")), "razorpay_payment_id": rzp_payment_id})
    pf.sync_order(result["payment"])
    return billing.store(container).get(purchase["id"])  # type: ignore[return-value]


def _public(p: dict | None) -> dict | None:
    if not p:
        return None
    return {k: p[k] for k in ("id", "plan_code", "kind", "amount", "mode", "status", "created_at", "updated_at")}


@router.get("/purchases/mine")
def my_purchases(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"items": [_public(p) for p in billing.store(request.app.state.container).list(user_id=user, limit=50)]}


def _own(request: Request, purchase_id: str) -> tuple[str, dict]:
    user = _authenticated_app_user(request)
    purchase = billing.store(request.app.state.container).get(purchase_id)
    if not purchase or purchase["user_id"] != user:
        raise HTTPException(status_code=404, detail="Purchase not found")
    return user, purchase


def _refreshed(request: Request, purchase: dict, actor: str) -> dict:
    """An open purchase is read back from the gateway (rate-limited, GET only)."""
    from app.services import rate_limit

    if purchase["status"] in billing.OPEN_STATES:
        rate_limit.check(request, "billing_refresh", limit=30)
        purchase = billing.refresh(request.app.state.container, purchase["id"], actor=actor)["purchase"]
    return purchase


@router.get("/purchases/{purchase_id}")
def my_purchase(purchase_id: str, request: Request) -> dict:
    user, purchase = _own(request, purchase_id)
    return {"purchase": _public(_refreshed(request, purchase, f"user:{user}"))}


@router.post("/purchases/{purchase_id}/cancel")
def cancel_my_purchase(purchase_id: str, request: Request) -> dict:
    user, _ = _own(request, purchase_id)
    return {"purchase": _public(billing.cancel(request.app.state.container, purchase_id, f"user:{user}"))}


# ------------------------------------------------- hosted checkout page --

def _linked(request: Request, purchase_id: str, token: str) -> dict:
    container = request.app.state.container
    purchase = billing.store(container).get(purchase_id)
    if not purchase or not billing.check_pay_token(container, purchase_id, token):
        raise HTTPException(status_code=404, detail="This payment link is invalid or has expired")
    return purchase


class PayVerifyBody(BaseModel):
    t: str = Field(min_length=10, max_length=80)
    razorpay_order_id: str = Field(min_length=3, max_length=64)
    razorpay_payment_id: str = Field(min_length=3, max_length=64)
    razorpay_signature: str = Field(min_length=10, max_length=128)


class PayTokenBody(BaseModel):
    t: str = Field(min_length=10, max_length=80)


@router.post("/pay/{purchase_id}/verify")
def pay_verify(purchase_id: str, body: PayVerifyBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "billing_pay_verify", limit=20)
    purchase = _linked(request, purchase_id, body.t)
    done = _verify(request.app.state.container, purchase, body.razorpay_order_id, body.razorpay_payment_id,
                   body.razorpay_signature, actor="checkout_page")
    return {"purchase": _public(done)}


@router.post("/pay/{purchase_id}/cancel")
def pay_cancel(purchase_id: str, body: PayTokenBody, request: Request) -> dict:
    _linked(request, purchase_id, body.t)
    return {"purchase": _public(billing.cancel(request.app.state.container, purchase_id, "checkout_page"))}


@router.get("/pay/{purchase_id}/status")
def pay_status(purchase_id: str, t: str, request: Request) -> dict:
    purchase = _linked(request, purchase_id, t)
    return {"purchase": _public(_refreshed(request, purchase, "checkout_page"))}


_PAY_CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline' https://checkout.razorpay.com https://*.razorpay.com; "
            "frame-src https://api.razorpay.com https://*.razorpay.com; connect-src 'self' https://*.razorpay.com; "
            "img-src 'self' data: https:; style-src 'self' 'unsafe-inline' https://*.razorpay.com; "
            "base-uri 'none'; form-action 'self'")


@page_router.get("/billing/pay/{purchase_id}", response_class=HTMLResponse)
def pay_page(purchase_id: str, request: Request, t: str = "") -> HTMLResponse:
    """Razorpay Standard Checkout for ONE purchase. Amount, order and key come
    from the server; the page only reports what Razorpay returns, and the
    server verifies it (signature / read-back) before anything activates."""
    import html as h
    import json as js

    from app.api.routes.growth import growth
    from app.api.routes.platform import platform

    container = request.app.state.container
    try:
        purchase = _linked(request, purchase_id, t)
    except HTTPException:
        return HTMLResponse(_PAGE.replace("__BODY__", "<h1>Link expired</h1><p>This payment link is invalid or has "
                                          "expired. Go back to the ASKODOX app and start again.</p>")
                            .replace("__CONFIG__", "null"), status_code=404, headers={"Content-Security-Policy": _PAY_CSP})
    pf = platform(container)
    payment = pf.repo.payment(purchase.get("payment_id") or "") or {}
    plan = growth(container).plan(purchase["plan_code"]) or {}
    config = None
    if purchase["status"] == "PENDING" and purchase.get("provider") == "razorpay" and payment:
        config = {"key": pf.registry.config_value("razorpay", "key_id"),
                  "order_id": pf.razorpay.order_for(payment["id"]),
                  "amount": int(round(float(payment["amount"]) * 100)), "currency": payment.get("currency") or "INR",
                  "name": "ASKODOX", "description": str(plan.get("name") or purchase["plan_code"])[:80],
                  "purchase_id": purchase["id"], "t": t}
    test = purchase.get("mode") == "test"
    body = (('<div class="test">TEST MODE &middot; no real money. Use Razorpay test card / test UPI only.</div>'
             if test else "") +
            f'<h1>{h.escape(str(plan.get("name") or purchase["plan_code"]))}</h1>'
            f'<p class="amt">&#8377;{float(purchase["amount"]):,.2f}</p>'
            f'<p id="status">Status: <b>{h.escape(purchase["status"])}</b></p>'
            + ('<button id="pay">Pay now</button>' if config else '')
            + '<button id="check" class="sec">Check status</button>'
            '<p class="note">Card / UPI details are entered on Razorpay\'s own checkout; ASKODOX never sees them. '
            'When done, go back to the ASKODOX app.</p>')
    page = _PAGE.replace("__BODY__", body).replace("__CONFIG__", js.dumps(config).replace("</", "<\\/"))
    page = page.replace("__ID__", js.dumps(purchase["id"])).replace("__T__", js.dumps(t))
    return HTMLResponse(page, headers={"Content-Security-Policy": _PAY_CSP, "X-Frame-Options": "DENY",
                                       "Referrer-Policy": "no-referrer", "Cache-Control": "no-store"})


_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>ASKODOX payment</title>
<style>body{font-family:system-ui,sans-serif;max-width:420px;margin:0 auto;padding:24px 16px;color:#101828;background:#fff}
.test{background:#FEF3C7;border:1px solid #F59E0B;border-radius:8px;padding:8px 10px;font-weight:700;font-size:14px}
h1{font-size:22px;margin:18px 0 4px}.amt{font-size:28px;font-weight:800;margin:0 0 12px}
button{display:block;width:100%;padding:14px;margin:10px 0;border:0;border-radius:10px;font-size:16px;font-weight:700;
background:#2563EB;color:#fff}button.sec{background:#EEF2F6;color:#101828}.note{font-size:13px;color:#667085}</style>
</head><body>__BODY__
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
const CFG=__CONFIG__, ID=__ID__, T=__T__;
const show=(s,extra)=>{const el=document.getElementById("status");if(el)el.innerHTML="Status: <b>"+s+"</b>"+(extra?"<br>"+extra:"");
  if(s!=="PENDING"){const b=document.getElementById("pay");if(b)b.remove()}};
async function post(path,body){const r=await fetch("/api/billing/pay/"+encodeURIComponent(ID)+path,{method:"POST",
  headers:{"Content-Type":"application/json"},body:JSON.stringify(Object.assign({t:T},body||{}))});return r.json().catch(()=>({}))}
async function check(){const r=await fetch("/api/billing/pay/"+encodeURIComponent(ID)+"/status?t="+encodeURIComponent(T));
  const d=await r.json().catch(()=>({}));if(d.purchase)show(d.purchase.status,d.purchase.status==="ACTIVE"?"Paid. Go back to the ASKODOX app.":d.purchase.status==="TEST_PAID"?"Test payment confirmed. TEST mode: no plan was activated.":"")}
const c=document.getElementById("check");if(c)c.onclick=check;
const p=document.getElementById("pay");
if(p&&CFG&&window.Razorpay){p.onclick=()=>{const rzp=new Razorpay({key:CFG.key,order_id:CFG.order_id,amount:CFG.amount,
  currency:CFG.currency,name:CFG.name,description:CFG.description,notes:{purchase_id:CFG.purchase_id},
  handler:async(resp)=>{show("VERIFYING");const d=await post("/verify",resp);
    if(d.purchase)show(d.purchase.status,d.purchase.status==="ACTIVE"?"Paid. Go back to the ASKODOX app.":d.purchase.status==="TEST_PAID"?"Test payment confirmed. TEST mode: no plan was activated.":"");else show("NOT VERIFIED","Use Check status.")},
  modal:{ondismiss:async()=>{const d=await post("/cancel");if(d.purchase)show(d.purchase.status)}}});
  rzp.on("payment.failed",()=>show("PENDING","That attempt failed. You can try again."));rzp.open()}}
else if(p){p.disabled=true;show("PENDING","Razorpay checkout could not load. Check your connection and reload.")}
</script></body></html>"""


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
                         "warnings": st.get("warnings") or [], "enabled_by": st.get("enabled_by") or "",
                         "key_kind": fin.key_kind(provider, st["config"].get("key_id") or st["config"].get("client_id"))})
    plans = growth(container).plans()
    return {
        "checkout_provider": pf.checkout_provider(),
        "live_payments_approved": fin.live_payments_approved(dict(os.environ)),
        "live_approval_variable": fin.LIVE_APPROVAL_ENV,
        "flags": {"billing.live_pricing": feature_enabled(container, "billing.live_pricing"),
                  "payments.online": feature_enabled(container, "payments.online"),
                  billing.RADIO_FLAG: feature_enabled(container, billing.RADIO_FLAG)},
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
    user_id = billing.tester_user_id(body.user_id)
    from app.services import tester_identity

    if tester_identity.is_demo_account(user_id):
        raise HTTPException(status_code=409, detail="DEMO_ACCOUNT_NOT_ALLOWED: the shared demo login cannot be a "
                                                    "tester -- add the person's own number")
    billing.store(request.app.state.container).add_tester(user_id, str(principal.get("id")))
    _audit(request, principal, "billing.tester.add", user_id, {})
    return {"user_id": user_id, "tester": True}


@admin_router.delete("/testers/{user_id}")
def remove_tester(user_id: str, request: Request) -> dict:
    principal = _require(request, "growth:manage")
    user_id = billing.tester_user_id(user_id)
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
    if not purchase or purchase["status"] not in billing.PAID_STATES:
        raise HTTPException(status_code=409, detail="Only a paid purchase can be refunded")
    pf = platform(container)
    payment = pf.repo.payment(purchase["payment_id"])
    amount = body.amount or float(payment["amount"]) - float(payment.get("refunded_amount") or 0)
    try:
        result = pf.gateway_refund(payment, amount, refund_id=f"rf_{purchase_id}")
    except Exception as error:
        raise HTTPException(status_code=409, detail=str(error)[:200]) from None
    _audit(request, principal, "billing.refund.requested", purchase_id, {"amount": amount})
    return {"requested": result, "note": "The plan is cancelled when the gateway confirms the refund."}


@admin_router.post("/purchases/{purchase_id}/reconcile")
def reconcile_purchase(purchase_id: str, request: Request) -> dict:
    """Read the purchase back from the gateway (GET only: never refunds or
    captures) and show its audit trail."""
    principal = _require(request, "payments:manage")
    container = request.app.state.container
    if not billing.store(container).get(purchase_id):
        raise HTTPException(status_code=404, detail="Purchase not found")
    out = billing.refresh(container, purchase_id, actor=f"staff:{principal.get('id')}")
    _audit(request, principal, "billing.reconcile", purchase_id, {"status": out["purchase"]["status"]})
    return {**out, "events": billing.store(container).events(purchase_id)}


@admin_router.get("/purchases/{purchase_id}")
def purchase_detail(purchase_id: str, request: Request) -> dict:
    _require(request, "growth:view")
    container = request.app.state.container
    purchase = billing.store(container).get(purchase_id)
    if not purchase:
        raise HTTPException(status_code=404, detail="Purchase not found")
    return {"purchase": purchase, "events": billing.store(container).events(purchase_id)}
