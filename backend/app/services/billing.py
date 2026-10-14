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
"""
from __future__ import annotations

import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.services.travel_radio import ADDON_AUDIENCE

STATES = ("PENDING", "ACTIVE", "FAILED", "REFUNDED", "CANCELLED")


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
    purchase = store(container).create(user_id=user_id, plan_code=plan["code"], kind=kind,
                                       amount=float(plan["price"]), provider=provider, mode=mode, status="PENDING")
    payment = pf.payments.create(idempotency_key=f"billing:{purchase['id']}", method="upi", amount=float(plan["price"]),
                                 order_ref=f"billing:{purchase['id']}", payer_ref=user_id, payee_ref="askodox",
                                 provider=provider, actor=f"user:{user_id}")
    store(container).update(purchase["id"], payment_id=payment["id"])
    digits = "".join(ch for ch in user_id if ch.isdigit())[-10:]
    params = pf.start_checkout(payment, **({"customer_id": purchase["id"], "phone": digits} if provider == "cashfree"
                                           else {}))
    return {"purchase_id": purchase["id"], "plan_code": plan["code"], "kind": kind, "amount": plan["price"],
            "mode": mode, "checkout": params}


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
    if status == "PAID" and purchase["status"] == "PENDING":
        if purchase["kind"] == "radio":
            target = radio(container).activate_paid(purchase["user_id"], plan, payment_id=payment["id"])
        else:
            target = growth(container).activate_paid(purchase["user_id"], plan, payment_id=payment["id"])
        purchase = store(container).update(purchase["id"], status="ACTIVE", target_id=str(target["id"]))
        _notify(container, purchase, "activated")
    elif status == "FAILED" and purchase["status"] == "PENDING":
        purchase = store(container).update(purchase["id"], status="FAILED")
    elif status == "REFUNDED" and purchase["status"] == "ACTIVE":
        if purchase.get("target_id"):
            if purchase["kind"] == "radio":
                radio(container).cancel_pass(int(purchase["target_id"]))
            else:
                growth(container).cancel_subscription(int(purchase["target_id"]))
        purchase = store(container).update(purchase["id"], status="REFUNDED")
        _notify(container, purchase, "refunded")
    return purchase


def _notify(container: Any, purchase: Dict[str, Any], what: str) -> None:
    try:
        from app.api.routes.platform import platform

        name = "Travel Radio pass" if purchase["kind"] == "radio" else "plan"
        body = (f"Your {name} is active." if what == "activated" else f"Your {name} payment was refunded.")
        platform(container).push().notify_async(purchase["user_id"], title="ASKODOX", body=body,
                                                route="/radio" if purchase["kind"] == "radio" else "/plans",
                                                event_key=f"billing:{purchase['id']}:{what}")
    except Exception:
        pass
