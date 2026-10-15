"""Subscription + Travel Radio billing through the ONE payment layer
(``commerce_finance.PaymentService`` + the Razorpay / Cashfree adapters).

A purchase is a ``pf_payments`` row (order_ref ``billing:<purchase id>``) plus a
``billing_purchases`` row saying what it buys. Nothing is activated by the app:
only a gateway-confirmed PAID (signed webhook, or Razorpay's verified checkout
signature) activates the plan / pass, through ``on_payment``; a REFUNDED payment
cancels it. Card / UPI details never reach ASKODOX (the gateway's checkout owns
them). Base plans and Radio passes stay separate.

Who may buy:
- TEST gateway (sandbox keys, no real money): only staff-chosen billing testers,
  any configured plan, so the whole flow can be rehearsed before approval;
- LIVE gateway: only after the Owner's approvals -- live mode unlocked
  (ASKODOX_PAYMENTS_LIVE_APPROVED), flag billing.live_pricing, plan on sale.
- Travel Radio passes additionally need flag billing.radio_checkout (default
  OFF), so Radio billing stays off even for testers until the Owner approves.

TEST-mode purchases never create a real entitlement: a gateway-confirmed PAID
on a TEST purchase becomes TEST_PAID (proves the payment flow) and no plan or
pass is activated. Only a LIVE purchase (after every Owner approval) activates.

Purchase states: PENDING (order created) -> ACTIVE (LIVE: gateway-confirmed PAID) /
TEST_PAID (TEST: confirmed, nothing activated) /
FAILED / CANCELLED (customer closed the checkout) / EXPIRED (no payment after
PENDING_TTL_HOURS) -> REFUNDED. A capture that Razorpay reports later still
activates a CANCELLED / EXPIRED purchase (the money was taken). Every step is
logged in billing_events (who, what, when; never card / UPI data).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from app.services.travel_radio import ADDON_AUDIENCE

STATES = ("PENDING", "ACTIVE", "TEST_PAID", "FAILED", "REFUNDED", "CANCELLED", "EXPIRED")
PAID_STATES = ("ACTIVE", "TEST_PAID")  # refundable
OPEN_STATES = ("PENDING", "CANCELLED", "EXPIRED")  # a later gateway capture still activates these
PENDING_TTL_HOURS = 24
PAY_LINK_TTL_SECONDS = 30 * 60
RADIO_FLAG = "billing.radio_checkout"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class BillingStore:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS billing_purchases (
                    id TEXT PRIMARY KEY, user_id TEXT NOT NULL, plan_code TEXT NOT NULL, kind TEXT NOT NULL,
                    amount REAL NOT NULL, payment_id TEXT, provider TEXT, mode TEXT NOT NULL,
                    status TEXT NOT NULL, target_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS ix_billing_user ON billing_purchases(user_id);
                CREATE TABLE IF NOT EXISTS billing_testers (
                    user_id TEXT PRIMARY KEY, added_by TEXT NOT NULL, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS billing_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id TEXT NOT NULL, event TEXT NOT NULL,
                    actor TEXT NOT NULL, detail_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS ix_billing_events ON billing_events(purchase_id);
                """
            )

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def create(self, **row: Any) -> Dict[str, Any]:
        row = {"id": "bp_" + uuid.uuid4().hex[:16], "created_at": _now(), "updated_at": _now(), **row}
        with self._connect() as conn:
            conn.execute(f"INSERT INTO billing_purchases({','.join(row)}) VALUES({','.join('?' * len(row))})",
                         list(row.values()))
        return self.get(row["id"])  # type: ignore[return-value]

    def get(self, purchase_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM billing_purchases WHERE id=?", (purchase_id,)).fetchone()
        return dict(row) if row else None

    def update(self, purchase_id: str, **fields: Any) -> Dict[str, Any]:
        fields["updated_at"] = _now()
        with self._connect() as conn:
            conn.execute(f"UPDATE billing_purchases SET {', '.join(f'{k}=?' for k in fields)} WHERE id=?",
                         [*fields.values(), purchase_id])
        return self.get(purchase_id)  # type: ignore[return-value]

    def list(self, *, user_id: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM billing_purchases", []
        if user_id:
            sql += " WHERE user_id=?"
            args.append(user_id)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY created_at DESC LIMIT ?", [*args, int(limit)])]

    # audit trail -------------------------------------------------------
    def log(self, purchase_id: str, event: str, actor: str, detail: Optional[Dict[str, Any]] = None) -> None:
        with self._connect() as conn:
            conn.execute("INSERT INTO billing_events(purchase_id, event, actor, detail_json, created_at) "
                         "VALUES(?,?,?,?,?)", (purchase_id, event, actor, json.dumps(detail or {})[:2000], _now()))

    def events(self, purchase_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT event, actor, detail_json, created_at FROM billing_events WHERE purchase_id=?"
                                " ORDER BY id", (purchase_id,)).fetchall()
        return [{"event": r["event"], "actor": r["actor"], "detail": json.loads(r["detail_json"] or "{}"),
                 "at": r["created_at"]} for r in rows]

    # testers -----------------------------------------------------------
    def is_tester(self, user_id: str) -> bool:
        with self._connect() as conn:
            return conn.execute("SELECT 1 FROM billing_testers WHERE user_id=?", (user_id,)).fetchone() is not None

    def add_tester(self, user_id: str, added_by: str) -> None:
        with self._connect() as conn:
            conn.execute("INSERT OR IGNORE INTO billing_testers VALUES(?,?,?)", (user_id, added_by, _now()))

    def remove_tester(self, user_id: str) -> bool:
        with self._connect() as conn:
            return conn.execute("DELETE FROM billing_testers WHERE user_id=?", (user_id,)).rowcount > 0

    def testers(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM billing_testers ORDER BY created_at DESC")]


def tester_user_id(raw: str) -> str:
    """Staff may type the tester's phone number: 10 digits / +91... -> the app
    user id "app-phone-91XXXXXXXXXX" (see lib/core/auth/auth_controller.dart).
    Anything else is kept as typed."""
    text = str(raw or "").strip()
    if text.lower().startswith("app-"):
        return text
    digits = "".join(ch for ch in text if ch.isdigit())
    if len(digits) == 10:
        return "app-phone-91" + digits
    if len(digits) == 12 and digits.startswith("91"):
        return "app-phone-" + digits
    return text


def store(container: Any) -> BillingStore:
    found = getattr(container, "billing_store", None)
    if found is None or found.db_path != container.settings.database_path:
        found = BillingStore(container.settings.database_path)
        container.billing_store = found
    return found


class BillingError(Exception):
    def __init__(self, code: str, status: int = 409) -> None:
        super().__init__(code)
        self.code, self.status = code, status


def eligibility(container: Any, user_id: str, plan: Dict[str, Any], gateway_mode: str) -> Optional[str]:
    """None when this user may pay for this plan now, else the reason code."""
    from app.api.routes.command_center import feature_enabled
    from app.services import commerce_finance as fin
    import os

    if float(plan.get("price") or 0) <= 0:
        return "FREE_PLAN_NO_PAYMENT"
    if gateway_mode == "test":
        return None if store(container).is_tester(user_id) else "TEST_MODE_TESTERS_ONLY"
    if not fin.live_payments_approved(dict(os.environ)):
        return "LIVE_MODE_LOCKED"
    if not feature_enabled(container, "billing.live_pricing"):
        return "LIVE_PRICING_OFF"
    if not plan.get("active"):
        return "PLAN_NOT_ON_SALE"
    return None


def checkout(container: Any, user_id: str, plan_code: str) -> Dict[str, Any]:
    from app.api.routes.growth import growth
    from app.api.routes.platform import platform

    from app.api.routes.command_center import feature_enabled

    pf = platform(container)
    if not feature_enabled(container, "payments.online"):
        raise BillingError("PAYMENTS_OFF")
    plan = growth(container).plan(plan_code)
    if not plan or str(plan.get("audience") or "") not in ("base", ADDON_AUDIENCE):
        raise BillingError("UNKNOWN_PLAN", 404)
    provider = pf.checkout_provider()
    if not provider:
        raise BillingError("NO_PAYMENT_GATEWAY")
    mode = pf.registry.status(provider).get("mode") or "test"
    reason = eligibility(container, user_id, plan, mode)
    if reason:
        raise BillingError(reason)
    kind = "radio" if plan["audience"] == ADDON_AUDIENCE else "base"
    if kind == "radio" and not feature_enabled(container, RADIO_FLAG):
        raise BillingError("RADIO_BILLING_OFF")
    purchase = store(container).create(user_id=user_id, plan_code=plan["code"], kind=kind,
                                       amount=float(plan["price"]), provider=provider, mode=mode, status="PENDING")
    payment = pf.payments.create(idempotency_key=f"billing:{purchase['id']}", method="upi", amount=float(plan["price"]),
                                 order_ref=f"billing:{purchase['id']}", payer_ref=user_id, payee_ref="askodox",
                                 provider=provider, actor=f"user:{user_id}")
    store(container).update(purchase["id"], payment_id=payment["id"])
    digits = "".join(ch for ch in user_id if ch.isdigit())[-10:]
    try:
        params = pf.start_checkout(payment, **({"customer_id": purchase["id"], "phone": digits}
                                               if provider == "cashfree" else {}))
    except Exception as error:
        store(container).update(purchase["id"], status="FAILED")
        store(container).log(purchase["id"], "gateway_order_failed", "system", {"error": str(error)[:200]})
        raise BillingError("GATEWAY_UNAVAILABLE", 502) from None
    store(container).log(purchase["id"], "checkout_started", f"user:{user_id}",
                         {"plan_code": plan["code"], "amount": float(plan["price"]), "provider": provider,
                          "mode": mode, "order_id": params.get("order_id")})
    return {"purchase_id": purchase["id"], "plan_code": plan["code"], "kind": kind, "amount": plan["price"],
            "mode": mode, "checkout": params}


def options(container: Any, user_id: str) -> Dict[str, Any]:
    """What this signed-in user can buy right now (the app shows Pay only for
    these). Server-side rules only; the app never decides."""
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.growth import growth
    from app.api.routes.platform import platform

    pf = platform(container)
    provider = pf.checkout_provider() if feature_enabled(container, "payments.online") else None
    mode = (pf.registry.status(provider).get("mode") or "test") if provider else None
    items = []
    for plan in growth(container).plans():
        if str(plan.get("audience") or "") not in ("base", ADDON_AUDIENCE):
            continue
        reason = "NO_PAYMENT_GATEWAY" if not provider else eligibility(container, user_id, plan, mode or "test")
        if not reason and plan["audience"] == ADDON_AUDIENCE and not feature_enabled(container, RADIO_FLAG):
            reason = "RADIO_BILLING_OFF"
        items.append({"plan_code": plan["code"], "price": plan["price"], "payable": reason is None,
                      "reason": reason})
    return {"provider": provider, "mode": mode, "items": items}


# ------------------------------------------------------------ pay link --
# The hosted checkout page (/billing/pay/{id}) is opened in a browser, outside
# the app's session, so it carries a short-lived token bound to ONE purchase.
def _link_key(container: Any) -> bytes:
    return ("billing-pay-link:" + str(container.settings.session_token_secret)).encode()


def pay_token(container: Any, purchase_id: str, *, ttl: int = PAY_LINK_TTL_SECONDS) -> str:
    expires = int(time.time()) + int(ttl)
    sig = hmac.new(_link_key(container), f"{purchase_id}.{expires}".encode(), hashlib.sha256).hexdigest()[:40]
    return f"{expires}.{sig}"


def check_pay_token(container: Any, purchase_id: str, token: str) -> bool:
    try:
        expires_s, sig = str(token or "").split(".", 1)
        expires = int(expires_s)
    except ValueError:
        return False
    if expires < time.time():
        return False
    expected = hmac.new(_link_key(container), f"{purchase_id}.{expires}".encode(), hashlib.sha256).hexdigest()[:40]
    return hmac.compare_digest(expected, sig)


# ------------------------------------------------- customer / gateway --
def cancel(container: Any, purchase_id: str, actor: str) -> Dict[str, Any]:
    """The customer closed the checkout. Client-reported, so it can only STOP a
    pending purchase -- a capture Razorpay reports later still activates it."""
    purchase = store(container).get(purchase_id)
    if purchase and purchase["status"] == "PENDING":
        purchase = store(container).update(purchase_id, status="CANCELLED")
        store(container).log(purchase_id, "checkout_closed", actor)
    return purchase  # type: ignore[return-value]


def note_gateway_event(container: Any, payment: Dict[str, Any], event: str, *, actor: str,
                       detail: Optional[Dict[str, Any]] = None) -> None:
    ref = str(payment.get("order_ref") or "")
    if ref.startswith("billing:") and store(container).get(ref.split(":", 1)[1]):
        store(container).log(ref.split(":", 1)[1], event, actor, detail)


def refresh(container: Any, purchase_id: str, *, actor: str = "system") -> Dict[str, Any]:
    """Reconcile one purchase with the gateway (read-only) and expire a stale
    PENDING one. Safe to call any number of times."""
    from app.api.routes.platform import platform

    purchase = store(container).get(purchase_id)
    if not purchase or not purchase.get("payment_id"):
        return {"purchase": purchase, "gateway": None}
    pf = platform(container)
    gateway = None
    payment = pf.repo.payment(purchase["payment_id"])
    if payment and purchase["provider"] == "razorpay" and purchase["status"] in (*OPEN_STATES, *PAID_STATES):
        try:
            gateway = pf.razorpay.reconcile(payment)
        except Exception as error:  # a gateway outage leaves the state as it is
            gateway = {"checked": False, "reason": type(error).__name__}
        if gateway.get("checked"):
            before = payment["status"]
            payment = gateway["payment"]
            if payment["status"] != before:
                store(container).log(purchase_id, "reconciled", actor, {"payment": f"{before}->{payment['status']}"})
            pf.sync_order(payment)
    purchase = store(container).get(purchase_id) or purchase
    if purchase["status"] == "PENDING":
        created = datetime.fromisoformat(purchase["created_at"])
        if datetime.now(timezone.utc) - created > timedelta(hours=PENDING_TTL_HOURS):
            purchase = store(container).update(purchase_id, status="EXPIRED")
            store(container).log(purchase_id, "expired", actor, {"after_hours": PENDING_TTL_HOURS})
    return {"purchase": purchase, "gateway": {k: v for k, v in (gateway or {}).items() if k != "payment"} or None}


def on_payment(container: Any, payment: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Gateway-confirmed state -> plan / pass state (idempotent)."""
    from app.api.routes.growth import growth
    from app.api.routes.radio import radio

    ref = str(payment.get("order_ref") or "")
    if not ref.startswith("billing:"):
        return None
    purchase = store(container).get(ref.split(":", 1)[1])
    if not purchase:
        return None
    status = payment.get("status")
    plan = growth(container).plan(purchase["plan_code"]) or {"code": purchase["plan_code"]}
    if status == "PAID" and purchase["status"] in OPEN_STATES and purchase.get("mode") != "live":
        # TEST (sandbox) money: the flow is proven, but no real entitlement is created.
        purchase = store(container).update(purchase["id"], status="TEST_PAID")
        store(container).log(purchase["id"], "test_paid_no_entitlement", "gateway", {"payment_id": payment["id"]})
        _notify(container, purchase, "test_paid")
    elif status == "PAID" and purchase["status"] in OPEN_STATES:
        if purchase["kind"] == "radio":
            target = radio(container).activate_paid(purchase["user_id"], plan, payment_id=payment["id"])
        else:
            target = growth(container).activate_paid(purchase["user_id"], plan, payment_id=payment["id"])
        purchase = store(container).update(purchase["id"], status="ACTIVE", target_id=str(target["id"]))
        store(container).log(purchase["id"], "activated", "gateway", {"payment_id": payment["id"]})
        _notify(container, purchase, "activated")
    elif status == "FAILED" and purchase["status"] == "PENDING":
        purchase = store(container).update(purchase["id"], status="FAILED")
        store(container).log(purchase["id"], "payment_failed", "gateway")
    elif status == "REFUNDED" and purchase["status"] in PAID_STATES:
        if purchase.get("target_id") and purchase["status"] == "ACTIVE":
            if purchase["kind"] == "radio":
                radio(container).cancel_pass(int(purchase["target_id"]))
            else:
                growth(container).cancel_subscription(int(purchase["target_id"]))
        purchase = store(container).update(purchase["id"], status="REFUNDED")
        store(container).log(purchase["id"], "refunded", "gateway", {"payment_id": payment["id"]})
        _notify(container, purchase, "refunded")
    return purchase


def _notify(container: Any, purchase: Dict[str, Any], what: str) -> None:
    try:
        from app.api.routes.platform import platform

        name = "Travel Radio pass" if purchase["kind"] == "radio" else "plan"
        body = (f"Your {name} is active." if what == "activated"
                else f"Test payment for the {name} confirmed (TEST mode: nothing was activated)."
                if what == "test_paid" else f"Your {name} payment was refunded.")
        platform(container).push().notify_async(purchase["user_id"], title="ASKODOX", body=body,
                                                route="/radio" if purchase["kind"] == "radio" else "/plans",
                                                event_key=f"billing:{purchase['id']}:{what}")
    except Exception:
        pass
