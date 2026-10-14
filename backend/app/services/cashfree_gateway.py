"""Cashfree Payment Gateway, following Cashfree's documented PG API
(x-api-version 2023-08-01): Create Order -> payment_session_id for the
Cashfree checkout SDK, signed webhooks, refunds. Built and tested against
recorded request/response shapes -- it is not "live" until real keys are added,
the Command Center Check passes and the Owner approves Live mode.

* start(payment)  -> POST {base}/orders (order_id = ASKODOX payment id). Returns
                     the payment_session_id the app hands to Cashfree's SDK.
                     No card / UPI data ever touches ASKODOX.
* webhook         -> x-webhook-signature = base64(HMAC_SHA256(client_secret,
                     x-webhook-timestamp + raw body)); PAYMENT_SUCCESS -> PAID,
                     PAYMENT_FAILED / USER_DROPPED -> FAILED, REFUND (SUCCESS)
                     -> (PARTIALLY_)REFUNDED. Replays are ignored.
* refund          -> POST {base}/orders/{order_id}/refunds (idempotent refund_id).
The base URL follows the integration mode: test -> sandbox.cashfree.com.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import sqlite3
import time
from typing import Any, Callable, Dict, Optional, Tuple

from app.repositories.platform_repository import PlatformConflict, now_iso

API_VERSION = "2023-08-01"
SANDBOX = "https://sandbox.cashfree.com/pg"
PRODUCTION = "https://api.cashfree.com/pg"
MAX_WEBHOOK_AGE_S = 15 * 60
Http = Callable[..., Tuple[int, Any]]


class CashfreeGateway:
    def __init__(self, repo: Any, registry: Any, http: Http) -> None:
        self.repo = repo
        self.registry = registry
        self.http = http
        with self._connect() as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS pf_gateway_orders (provider TEXT NOT NULL, order_id TEXT NOT NULL,"
                         " payment_id TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(provider, order_id))")

    def _connect(self):
        conn = sqlite3.connect(self.repo.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def base_url(self) -> str:
        return PRODUCTION if self.registry.status("cashfree").get("mode") == "live" else SANDBOX

    def _headers(self) -> Dict[str, str]:
        return {"x-client-id": self.registry.config_value("cashfree", "client_id"),
                "x-client-secret": self.registry.secret("cashfree", "client_secret"),
                "x-api-version": API_VERSION, "Content-Type": "application/json"}

    def _payment_for_order(self, order_id: str) -> Optional[str]:
        with self._connect() as conn:
            row = conn.execute("SELECT payment_id FROM pf_gateway_orders WHERE provider='cashfree' AND order_id=?",
                               (order_id,)).fetchone()
        return row["payment_id"] if row else None

    # ---------------------------------------------------------------- start
    def start(self, payment: Dict[str, Any], *, customer_id: str = "", phone: str = "",
              notify_url: str = "") -> Dict[str, Any]:
        """Create (or reuse) the Cashfree order for this ASKODOX payment."""
        order_id = payment["id"][:45]
        known = self._payment_for_order(order_id)
        body: Dict[str, Any] = {
            "order_id": order_id, "order_amount": round(float(payment["amount"]), 2),
            "order_currency": payment.get("currency") or "INR",
            "customer_details": {"customer_id": (customer_id or "askodox")[:50],
                                 "customer_phone": phone or "9999999999"},
            "order_note": str(payment.get("order_ref") or "")[:200],
        }
        if notify_url:
            body["order_meta"] = {"notify_url": notify_url}
        path = f"{self.base_url()}/orders" + (f"/{order_id}" if known else "")
        status, data = self.http("GET" if known else "POST", path, headers=self._headers(),
                                 **({} if known else {"json": body}))
        if status not in (200, 201) or not isinstance(data, dict) or not data.get("payment_session_id"):
            message = data.get("message") if isinstance(data, dict) else ""
            raise PlatformConflict(f"Cashfree could not create the order (HTTP {status}"
                                   f"{': ' + str(message)[:120] if message else ''})")
        if not known:
            with self._connect() as conn:
                conn.execute("INSERT OR IGNORE INTO pf_gateway_orders VALUES ('cashfree', ?, ?, ?)",
                             (order_id, payment["id"], now_iso()))
            if payment["status"] == "CREATED":
                self.repo.transition_payment(payment["id"], "PENDING", actor="gateway:cashfree",
                                             note=f"Cashfree order {data.get('cf_order_id') or order_id}")
        return {"provider": "cashfree", "order_id": order_id, "payment_session_id": data["payment_session_id"],
                "environment": "production" if self.base_url() == PRODUCTION else "sandbox",
                "amount": round(float(payment["amount"]), 2), "currency": payment.get("currency") or "INR"}

    # -------------------------------------------------------------- webhook
    @staticmethod
    def signature(secret: str, timestamp: str, body: bytes) -> str:
        mac = hmac.new(secret.encode(), timestamp.encode() + body, hashlib.sha256).digest()
        return base64.b64encode(mac).decode()

    def webhook(self, body: bytes, signature: str, timestamp: str, *, now: float | None = None) -> Dict[str, Any]:
        secret = self.registry.secret("cashfree", "client_secret")
        if not secret:
            raise PermissionError("Cashfree is not configured")
        if not signature or not timestamp:
            raise PermissionError("missing signature")
        if not hmac.compare_digest(self.signature(secret, timestamp, body), signature.strip()):
            raise PermissionError("invalid signature")
        try:  # Cashfree sends epoch milliseconds; refuse stale replays
            sent = float(timestamp) / (1000 if float(timestamp) > 1e11 else 1)
            if abs((now or time.time()) - sent) > MAX_WEBHOOK_AGE_S:
                raise PermissionError("stale webhook")
        except ValueError:
            raise PermissionError("bad timestamp") from None
        try:
            event = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ValueError("body is not JSON") from None
        kind = str(event.get("type") or "")
        data = event.get("data") or {}
        order_id = str((data.get("order") or {}).get("order_id") or "")
        pay = data.get("payment") or {}
        refund = data.get("refund") or {}
        if not order_id and refund:
            order_id = str(refund.get("order_id") or "")
        payment_id = self._payment_for_order(order_id) if order_id else None
        if kind.startswith("PAYMENT_SUCCESS"):
            target = "PAID"
        elif kind.startswith(("PAYMENT_FAILED", "PAYMENT_USER_DROPPED")):
            target = "FAILED"
        elif kind.startswith("REFUND") and str(refund.get("refund_status") or "").upper() == "SUCCESS":
            target = "REFUND"
        else:
            target = ""
        if not target or not payment_id:
            return {"ignored": True, "event": kind}
        dedupe = f"{kind}:{pay.get('cf_payment_id') or refund.get('cf_refund_id') or refund.get('refund_id') or order_id}"
        if self.repo.seen_webhook("cashfree", dedupe, payment_id=payment_id, event=kind):
            return {"duplicate": True, "payment": self.repo.payment(payment_id)}
        current = self.repo.payment(payment_id)
        if target == "PAID":
            if current["status"] not in ("CREATED", "PENDING"):
                return {"duplicate": True, "payment": current}
            updated = self.repo.transition_payment(payment_id, "PAID", actor="webhook:cashfree",
                                                   provider_ref=str(pay.get("cf_payment_id") or ""), note=kind)
        elif target == "FAILED":
            if current["status"] not in ("CREATED", "PENDING"):
                return {"ignored": True, "event": kind}
            updated = self.repo.transition_payment(payment_id, "FAILED", actor="webhook:cashfree",
                                                   note=str(pay.get("payment_message") or kind)[:200])
        else:
            amount = float(refund.get("refund_amount") or 0)
            remaining = float(current["amount"]) - float(current.get("refunded_amount") or 0)
            updated = self.repo.transition_payment(
                payment_id, "REFUNDED" if abs(amount - remaining) < 1e-9 else "PARTIALLY_REFUNDED",
                actor="webhook:cashfree", refund_amount=amount, note=f"refund {refund.get('refund_id')}")
        return {"duplicate": False, "payment": updated}

    # --------------------------------------------------------------- refund
    def refund(self, payment: Dict[str, Any], amount: float, *, refund_id: str) -> Dict[str, Any]:
        """Ask Cashfree to refund; the state changes when its signed webhook
        confirms (never assumed)."""
        order_id = payment["id"][:45]
        status, data = self.http("POST", f"{self.base_url()}/orders/{order_id}/refunds", headers=self._headers(),
                                 json={"refund_amount": round(float(amount), 2), "refund_id": refund_id[:40],
                                       "refund_note": "ASKODOX refund"})
        if status not in (200, 201) or not isinstance(data, dict):
            raise PlatformConflict(f"Cashfree refused the refund (HTTP {status})")
        return {"provider": "cashfree", "refund_id": data.get("refund_id") or refund_id,
                "status": str(data.get("refund_status") or "PENDING")}
