"""Razorpay, following Razorpay's documented API (Orders, Standard Checkout,
Webhooks). Built and tested against recorded request/response shapes -- it is
not "live" until real keys are added and the Command Center Check passes.

* start(payment)   -> POST /v1/orders (amount in paise, receipt = ASKODOX payment id).
                      Returns the checkout parameters the app hands to Razorpay
                      Checkout (key_id, order_id, amount, currency). No card data
                      ever touches ASKODOX.
* verify_checkout  -> the checkout's success callback: HMAC_SHA256(key_secret,
                      "order_id|payment_id") must equal razorpay_signature.
* webhook          -> Razorpay's own signed events (X-Razorpay-Signature =
                      HMAC_SHA256(webhook_secret, raw body); X-Razorpay-Event-Id
                      for replay protection): payment.captured / order.paid -> PAID,
                      payment.failed -> FAILED, refund.processed -> (PARTIALLY_)REFUNDED.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import sqlite3
from typing import Any, Callable, Dict, Optional, Tuple

from app.repositories.platform_repository import PlatformConflict, now_iso

API = "https://api.razorpay.com/v1"
Http = Callable[..., Tuple[int, Any]]


class RazorpayGateway:
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

    def _auth(self) -> Tuple[str, str]:
        return self.registry.config_value("razorpay", "key_id"), self.registry.secret("razorpay", "key_secret")

    def _payment_for_order(self, order_id: str) -> Optional[str]:
        with self._connect() as conn:
            row = conn.execute("SELECT payment_id FROM pf_gateway_orders WHERE provider='razorpay' AND order_id=?",
                               (order_id,)).fetchone()
        return row["payment_id"] if row else None

    # ---------------------------------------------------------------- start
    def start(self, payment: Dict[str, Any]) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT order_id FROM pf_gateway_orders WHERE provider='razorpay' AND payment_id=?",
                               (payment["id"],)).fetchone()
        key_id, _ = self._auth()
        if row:  # idempotent: a retried start reuses the same Razorpay order
            order_id = row["order_id"]
        else:
            status, body = self.http("POST", f"{API}/orders", auth=self._auth(), json={
                "amount": int(round(float(payment["amount"]) * 100)), "currency": payment.get("currency") or "INR",
                "receipt": payment["id"][:40], "notes": {"askodox_payment_id": payment["id"],
                                                          "order_ref": str(payment.get("order_ref") or "")[:200]}})
            if status != 200 or not isinstance(body, dict) or not str(body.get("id", "")).startswith("order_"):
                err = body.get("error", {}).get("description") if isinstance(body, dict) else ""
                raise PlatformConflict(f"Razorpay could not create the order (HTTP {status}{': ' + err if err else ''})")
            order_id = body["id"]
            with self._connect() as conn:
                conn.execute("INSERT INTO pf_gateway_orders VALUES ('razorpay', ?, ?, ?)",
                             (order_id, payment["id"], now_iso()))
            if payment["status"] == "CREATED":
                self.repo.transition_payment(payment["id"], "PENDING", actor="gateway:razorpay",
                                             note=f"Razorpay order {order_id}")
        return {"provider": "razorpay", "key_id": key_id, "order_id": order_id,
                "amount": int(round(float(payment["amount"]) * 100)), "currency": payment.get("currency") or "INR"}

    # ------------------------------------------------------------- checkout
    def verify_checkout(self, order_id: str, razorpay_payment_id: str, signature: str) -> Dict[str, Any]:
        _, secret = self._auth()
        if not secret:
            raise PermissionError("Razorpay is not configured")
        expected = hmac.new(secret.encode(), f"{order_id}|{razorpay_payment_id}".encode(), hashlib.sha256).hexdigest()
        if not signature or not hmac.compare_digest(expected, signature.strip()):
            raise PermissionError("invalid Razorpay signature")
        payment_id = self._payment_for_order(order_id)
        if not payment_id:
            raise KeyError(order_id)
        if self.repo.seen_webhook("razorpay", f"checkout:{razorpay_payment_id}", payment_id=payment_id, event="PAID"):
            return {"duplicate": True, "payment": self.repo.payment(payment_id)}
        payment = self.repo.payment(payment_id)
        if payment["status"] in ("CREATED", "PENDING"):
            payment = self.repo.transition_payment(payment_id, "PAID", actor="checkout:razorpay",
                                                   provider_ref=razorpay_payment_id, note="checkout signature verified")
        return {"duplicate": False, "payment": payment}

    # -------------------------------------------------------------- webhook
    def webhook(self, body: bytes, signature: str, event_id: str) -> Dict[str, Any]:
        secret = self.registry.secret("razorpay", "webhook_secret")
        if not secret:
            raise PermissionError("webhook secret not configured")
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        if not signature or not hmac.compare_digest(expected, signature.strip()):
            raise PermissionError("invalid signature")
        try:
            event = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ValueError("body is not JSON") from None
        name = str(event.get("event") or "")
        payload = event.get("payload") or {}
        pay = (payload.get("payment") or {}).get("entity") or {}
        refund = (payload.get("refund") or {}).get("entity") or {}
        order = (payload.get("order") or {}).get("entity") or {}
        order_id = pay.get("order_id") or order.get("id") or ""
        payment_id = self._payment_for_order(order_id) if order_id else None
        if not payment_id and refund.get("payment_id"):
            payment_id = self._payment_by_provider_ref(refund["payment_id"])
        target = {"payment.captured": "PAID", "order.paid": "PAID", "payment.failed": "FAILED",
                  "refund.processed": "REFUND"}.get(name)
        if not target or not payment_id:
            return {"ignored": True, "event": name}  # events ASKODOX does not act on are acknowledged
        dedupe = event_id or f"{name}:{pay.get('id') or refund.get('id') or order_id}"
        if self.repo.seen_webhook("razorpay", dedupe, payment_id=payment_id, event=name):
            return {"duplicate": True, "payment": self.repo.payment(payment_id)}
        current = self.repo.payment(payment_id)
        if target == "PAID":
            if current["status"] not in ("CREATED", "PENDING"):
                return {"duplicate": True, "payment": current}  # already paid via checkout verify
            updated = self.repo.transition_payment(payment_id, "PAID", actor="webhook:razorpay",
                                                   provider_ref=pay.get("id"), note=name)
        elif target == "FAILED":
            if current["status"] not in ("CREATED", "PENDING"):
                return {"ignored": True, "event": name}  # a later retry already succeeded
            updated = self.repo.transition_payment(payment_id, "FAILED", actor="webhook:razorpay",
                                                   note=str(pay.get("error_description") or name)[:200])
        else:
            updated = self.repo.transition_payment(payment_id, "PARTIALLY_REFUNDED", actor="webhook:razorpay",
                                                   refund_amount=float(refund.get("amount") or 0) / 100,
                                                   note=f"refund {refund.get('id')}")
        return {"duplicate": False, "payment": updated}

    def _payment_by_provider_ref(self, provider_ref: str) -> Optional[str]:
        for p in self.repo.payments(limit=5000):
            if p["provider"] == "razorpay" and p["provider_ref"] == provider_ref:
                return p["id"]
        return None
