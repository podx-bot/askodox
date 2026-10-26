"""ASKODOX POS -- bank / provider-confirmed payment alerts (Razorpay QR + webhook).

The shop connects ITS OWN Razorpay account (key id + key secret + webhook secret). Customers pay the
shop's Razorpay UPI QR; Razorpay settles the money to the shop. ASKODOX never holds, collects or
moves money -- it only receives Razorpay's signed webhook, re-checks the payment with Razorpay's
API using the shop's keys, and then records a ``provider_verified`` alert that phones announce as
"మీకు ... రూపాయలు అందాయి".

Safety
* Secrets are stored encrypted (``secret_box``; fails closed without ASKODOX_SECRETS_KEY) and are
  never returned by any API.
* A webhook counts only with a valid ``X-Razorpay-Signature`` (HMAC-SHA256 of the raw body with the
  shop's webhook secret) AND when Razorpay's API confirms the payment is ``captured`` for that amount.
* Each Razorpay event id is processed once (replays are ignored).
* Live keys (``rzp_live_``) are refused until ASKODOX_POS_PROVIDER_LIVE_APPROVED=yes is set on the
  server (owner approval). Test-mode payments are recorded as TEST alerts, never as money.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import sqlite3
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Mapping, Optional, Tuple

from app.services.pos_store import PosError, PosStore
from app.services.secret_box import SecretBox, SecretsNotConfigured

API = "https://api.razorpay.com/v1"
Http = Callable[..., Tuple[int, Any]]
PROVIDERS = {"razorpay": "Razorpay"}
_KEY_ID = re.compile(r"^rzp_(test|live)_[A-Za-z0-9]{6,40}$")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_provider_accounts (business_id TEXT NOT NULL, provider TEXT NOT NULL,"
    " mode TEXT NOT NULL, key_id TEXT NOT NULL, key_secret TEXT NOT NULL, webhook_secret TEXT NOT NULL,"
    " qr_id TEXT NOT NULL DEFAULT '', qr_image_url TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1,"
    " last_event_at TEXT, updated_by TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (business_id, provider))",
    "CREATE TABLE IF NOT EXISTS pos_provider_webhook_events (provider TEXT NOT NULL, event_id TEXT NOT NULL,"
    " business_id TEXT NOT NULL, outcome TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY (provider, event_id))",
]


def _default_http(method: str, url: str, **kwargs: Any) -> Tuple[int, Any]:
    from app.services.comms import default_http

    return default_http(method, url, **kwargs)


class PosPaymentProviders:
    def __init__(self, store: PosStore, alerts: Any, box: SecretBox, http: Optional[Http] = None,
                 env: Optional[Mapping[str, str]] = None) -> None:
        self.store = store
        self.alerts = alerts
        self.box = box
        self.http = http or _default_http
        self.env = env if env is not None else os.environ
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _live_approved(self) -> bool:
        return str(self.env.get("ASKODOX_POS_PROVIDER_LIVE_APPROVED", "")).strip().lower() == "yes"

    def _owner(self, conn: sqlite3.Connection, business_id: str, user: str) -> None:
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        if role != "owner":
            raise PosError(403, "owner_only", "Only the shop owner can connect a payment provider.")

    def _row(self, conn: sqlite3.Connection, business_id: str, provider: str = "razorpay") -> Optional[sqlite3.Row]:
        return conn.execute("SELECT * FROM pos_provider_accounts WHERE business_id = ? AND provider = ? AND active = 1",
                            (business_id, provider)).fetchone()

    # -------------------------------------------------------------- owner
    def status(self, business_id: str, user: str, webhook_base: str = "") -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.alerts._member(conn, business_id, user)
            row = self._row(conn, business_id)
        out: Dict[str, Any] = {
            "provider": "razorpay", "label": PROVIDERS["razorpay"], "connected": row is not None,
            "secrets_ready": self.box.configured, "live_approved": self._live_approved(),
            "webhook_url": f"{webhook_base.rstrip('/')}/api/pos/payment-webhooks/razorpay/{business_id}",
            "webhook_events": ["qr_code.credited", "payment.captured"],
        }
        if row is not None:
            out.update({"mode": row["mode"], "key_id_tail": row["key_id"][-4:], "qr_id": row["qr_id"],
                        "qr_image_url": row["qr_image_url"], "last_event_at": row["last_event_at"],
                        "updated_at": row["updated_at"]})
        return out

    def connect(self, business_id: str, user: str, data: Dict[str, Any], webhook_base: str = "") -> Dict[str, Any]:
        key_id = str(data.get("key_id") or "").strip()
        key_secret = str(data.get("key_secret") or "").strip()
        webhook_secret = str(data.get("webhook_secret") or "").strip()
        match = _KEY_ID.match(key_id)
        if not match:
            raise PosError(400, "key_id", "Razorpay key id looks like rzp_test_... or rzp_live_...")
        mode = match.group(1)
        if mode == "live" and not self._live_approved():
            raise PosError(409, "live_not_approved", "Live Razorpay keys are not allowed yet. Use test keys (rzp_test_) "
                                                     "until ASKODOX approves live payments.")
        if len(key_secret) < 10 or len(webhook_secret) < 8:
            raise PosError(400, "secrets", "Enter the key secret and the webhook secret you set in Razorpay.")
        if not self.box.configured:
            raise PosError(503, "secrets_not_configured", "ASKODOX cannot store keys yet (server secret key missing).")
        with self.store._connect() as conn:
            self._owner(conn, business_id, user)
        status, _ = self.http("GET", f"{API}/payments", auth=(key_id, key_secret), params={"count": 1})
        if status != 200:
            raise PosError(400, "keys_rejected", "Razorpay did not accept these keys. Check the key id and secret.")
        now = self.store.clock().isoformat()
        try:
            enc_key, enc_hook = self.box.encrypt(key_secret), self.box.encrypt(webhook_secret)
        except SecretsNotConfigured:
            raise PosError(503, "secrets_not_configured", "ASKODOX cannot store keys yet (server secret key missing).")
        with self.store._tx() as conn:
            self._owner(conn, business_id, user)
            conn.execute(
                "INSERT INTO pos_provider_accounts (business_id, provider, mode, key_id, key_secret, webhook_secret,"
                " updated_by, updated_at) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(business_id, provider) DO UPDATE SET"
                " mode=excluded.mode, key_id=excluded.key_id, key_secret=excluded.key_secret,"
                " webhook_secret=excluded.webhook_secret, active=1, updated_by=excluded.updated_by,"
                " updated_at=excluded.updated_at",
                (business_id, "razorpay", mode, key_id, enc_key, enc_hook, user, now))
            self.store._audit(conn, business_id, user, "payment_provider.connect", "razorpay",
                              {"mode": mode, "key_id_tail": key_id[-4:]}, now)
        return self.status(business_id, user, webhook_base)

    def disconnect(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._owner(conn, business_id, user)
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_provider_accounts SET active = 0, key_secret = '', webhook_secret = '',"
                         " updated_by = ?, updated_at = ? WHERE business_id = ?", (user, now, business_id))
            self.store._audit(conn, business_id, user, "payment_provider.disconnect", "razorpay", {}, now)
        return self.status(business_id, user)

    def create_qr(self, business_id: str, user: str, webhook_base: str = "") -> Dict[str, Any]:
        with self.store._connect() as conn:
            self._owner(conn, business_id, user)
            row = self._row(conn, business_id)
            shop = self.store._business_row(conn, business_id)["name"]
        if row is None:
            raise PosError(409, "not_connected", "Connect Razorpay first.")
        auth = (row["key_id"], self.box.decrypt(row["key_secret"]))
        status, body = self.http("POST", f"{API}/payments/qr_codes", auth=auth, json={
            "type": "upi_qr", "name": str(shop)[:40], "usage": "multiple_use", "fixed_amount": False,
            "description": "Shop UPI QR (ASKODOX payment alerts)", "notes": {"askodox_business": business_id},
        })
        if status not in (200, 201) or not isinstance(body, dict) or not body.get("id"):
            raise PosError(502, "qr_failed", "Razorpay could not create the QR. Check that QR codes are enabled "
                                             "on your Razorpay account.")
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_provider_accounts SET qr_id = ?, qr_image_url = ?, updated_at = ?"
                         " WHERE business_id = ? AND provider = 'razorpay'",
                         (str(body["id"]), str(body.get("image_url") or ""), self.store.clock().isoformat(), business_id))
        return self.status(business_id, user, webhook_base)

    # ------------------------------------------------------------ webhook
    def webhook(self, provider: str, business_id: str, body: bytes, signature: str, event_id: str) -> Dict[str, Any]:
        if provider != "razorpay":
            raise PosError(404, "provider", "Unknown provider.")
        with self.store._connect() as conn:
            row = self._row(conn, business_id)
        if row is None:
            raise PosError(404, "not_connected", "No provider connected for this shop.")
        secret = self.box.decrypt(row["webhook_secret"])
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        if not secret or not signature or not hmac.compare_digest(expected, signature.strip()):
            raise PosError(401, "signature", "Invalid webhook signature.")
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise PosError(400, "payload", "Webhook body is not JSON.")
        event_id = (event_id or "").strip() or hashlib.sha256(body).hexdigest()[:40]
        now = self.store.clock().isoformat()
        with self.store._tx() as conn:
            seen = conn.execute("SELECT outcome FROM pos_provider_webhook_events WHERE provider = ? AND event_id = ?",
                                (provider, event_id)).fetchone()
            if seen is not None:
                return {"ok": True, "outcome": "replay", "first_outcome": seen["outcome"]}
            conn.execute("INSERT INTO pos_provider_webhook_events (provider, event_id, business_id, outcome, at)"
                         " VALUES (?,?,?,?,?)", (provider, event_id, business_id, "processing", now))
        outcome, event = self._handle(business_id, row, payload)
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_provider_webhook_events SET outcome = ? WHERE provider = ? AND event_id = ?",
                         (outcome, provider, event_id))
            if event is not None:
                conn.execute("UPDATE pos_provider_accounts SET last_event_at = ? WHERE business_id = ? AND provider = ?",
                             (now, business_id, provider))
        return {"ok": True, "outcome": outcome, "event_id": event["id"] if event else None}

    def _handle(self, business_id: str, row: sqlite3.Row, payload: Dict[str, Any]) -> Tuple[str, Optional[Dict[str, Any]]]:
        kind = str(payload.get("event") or "")
        if kind not in ("qr_code.credited", "payment.captured"):
            return "ignored_event", None
        entity = (((payload.get("payload") or {}).get("payment") or {}).get("entity")) or {}
        payment_id = str(entity.get("id") or "")
        if not payment_id.startswith("pay_"):
            return "no_payment", None
        # Never trust the webhook body alone: ask Razorpay with the shop's own keys.
        auth = (row["key_id"], self.box.decrypt(row["key_secret"]))
        status, live = self.http("GET", f"{API}/payments/{payment_id}", auth=auth)
        if status != 200 or not isinstance(live, dict):
            return "verify_failed", None
        if live.get("status") != "captured" or str(live.get("currency") or "INR") != "INR":
            return "not_captured", None
        amount = int(live.get("amount") or 0)
        if amount <= 0 or amount != int(entity.get("amount") or amount):
            return "amount_mismatch", None
        rrn = str(((live.get("acquirer_data") or {}).get("rrn")) or "")
        created = live.get("created_at")
        at = datetime.fromtimestamp(int(created), tz=timezone.utc) if isinstance(created, (int, float)) else None
        event = self.alerts.record_verified(business_id, provider="razorpay", label=PROVIDERS["razorpay"],
                                            amount_paise=amount, payment_id=payment_id, reference=rrn or payment_id,
                                            detected_at=at, test=row["mode"] != "live")
        return ("duplicate" if event.get("duplicate") else "recorded"), event
