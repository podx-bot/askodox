"""Payments, revenue, transactions, integrations, notifications, analytics.

Nothing here pretends to be live: external providers report NEEDS
CONFIGURATION until their credentials are stored (encrypted) and a check
passes. Money-moving operations are idempotent and state-machine checked;
webhooks are HMAC-verified and replay-protected.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.repositories.platform_repository import (
    LEDGER_KINDS,
    PlatformConflict,
    PlatformRepository,
    now_iso,
)

# ------------------------------------------------------------ integrations --

STATUS_LIVE, STATUS_TEST, STATUS_DISABLED, STATUS_NEEDS, STATUS_ERROR = (
    "LIVE", "TEST", "DISABLED", "NEEDS_CONFIGURATION", "ERROR")
# Enabled in mock mode: works end to end inside ASKODOX (outbox / sandbox)
# without credentials and never contacts the provider. Never "live".
STATUS_MOCK = "MOCK"
MODES = ("test", "live", "mock")

# name -> (group, label, required secret names, required public config keys, internal?)
PROVIDERS: Dict[str, tuple[str, str, tuple[str, ...], tuple[str, ...], bool]] = {
    # payments
    "direct_settlement": ("payments", "Cash / direct UPI between parties", (), (), True),
    "razorpay": ("payments", "Razorpay", ("key_secret", "webhook_secret"), ("key_id",), False),
    "cashfree": ("payments", "Cashfree", ("client_secret", "webhook_secret"), ("client_id",), False),
    "phonepe": ("payments", "PhonePe PG", ("salt_key", "webhook_secret"), ("merchant_id",), False),
    "paytm": ("payments", "Paytm PG", ("merchant_key", "webhook_secret"), ("merchant_id",), False),
    "stripe": ("payments", "Stripe", ("secret_key", "webhook_secret"), ("publishable_key",), False),
    # messaging / support
    "whatsapp_cloud": ("messaging", "WhatsApp Business (Cloud API)", ("access_token",),
                       ("phone_number_id",), False),
    "sms": ("messaging", "SMS gateway", ("api_key",), ("sender_id",), False),
    "email": ("messaging", "Email (SMTP / API)", ("password",), ("host", "from_address"), False),
    "fcm_push": ("messaging", "Push (Firebase)", ("service_account_json",), (), False),
    # video / social
    "youtube_data": ("video", "YouTube Data API", ("api_key",), (), False),
    "instagram_graph": ("video", "Instagram Graph API", ("access_token",), ("business_account_id",), False),
    "facebook_graph": ("video", "Facebook Graph API", ("access_token",), ("page_id",), False),
    # affiliate networks
    "amazon_associates": ("affiliate", "Amazon Associates", ("secret_key",), ("access_key", "partner_tag"), False),
    "flipkart_affiliate": ("affiliate", "Flipkart Affiliate", ("token",), ("affiliate_id",), False),
    "cuelinks": ("affiliate", "Cuelinks", ("api_key",), (), False),
    "admitad": ("affiliate", "Admitad", ("client_secret",), ("client_id",), False),
    # banks / card offers feed
    "bank_offers_feed": ("offers", "Bank / card / UPI offers feed", ("api_key",), ("endpoint",), False),
    # staging-only sandbox gateway: exercises the online-payment flow (create
    # -> signed webhook -> PAID / FAILED / REFUNDED) with no real money.
    "sandbox_gateway": ("payments", "Sandbox gateway (staging tests only -- no real money)", (), (), False),
}

# Optional settings per provider (not needed to be "configured").
OPTIONAL_SECRETS: Dict[str, tuple[str, ...]] = {
    "whatsapp_cloud": ("app_secret",),  # verifies inbound webhook signatures
}
OPTIONAL_CONFIG: Dict[str, tuple[str, ...]] = {
    "whatsapp_cloud": ("api_version", "template_name", "template_language"),
    "sms": ("vendor", "dlt_template_id", "account_sid"),
    "email": ("port", "username"),
    "fcm_push": ("project_id",),
}

# Keys that already exist as deployment variables are reused as-is (never
# copied into the database, never shown). A value saved in the Command
# Center takes precedence over the environment.
ENV_SOURCES: Dict[str, Dict[str, str]] = {
    "whatsapp_cloud": {"access_token": "WHATSAPP_ACCESS_TOKEN", "phone_number_id": "WHATSAPP_PHONE_NUMBER_ID",
                       "app_secret": "WHATSAPP_APP_SECRET", "api_version": "WHATSAPP_API_VERSION"},
    "fcm_push": {"service_account_json": "FIREBASE_SERVICE_ACCOUNT_JSON"},
    "youtube_data": {"api_key": "YOUTUBE_API_KEY"},
    "sms": {"api_key": "SMS_API_KEY", "sender_id": "SMS_SENDER_ID", "vendor": "SMS_VENDOR",
            "dlt_template_id": "SMS_DLT_TEMPLATE_ID", "account_sid": "SMS_ACCOUNT_SID"},
    "email": {"password": "SMTP_PASSWORD", "host": "SMTP_HOST", "from_address": "EMAIL_FROM",
              "port": "SMTP_PORT", "username": "SMTP_USERNAME"},
    "razorpay": {"key_id": "RAZORPAY_KEY_ID", "key_secret": "RAZORPAY_KEY_SECRET",
                 "webhook_secret": "RAZORPAY_WEBHOOK_SECRET"},
}

# Accepted alternative deployment-variable names (tried after ENV_SOURCES, in
# order). Railway production carries both YOUTUBE_API_KEY and
# YOUTUBE_DATA_API_KEY; either one alone must make YouTube configured.
ENV_ALIASES: Dict[str, Dict[str, tuple[str, ...]]] = {
    "youtube_data": {"api_key": ("YOUTUBE_DATA_API_KEY",)},
}


def env_names(provider: str, name: str) -> tuple[str, ...]:
    primary = ENV_SOURCES.get(provider, {}).get(name)
    return ((primary,) if primary else ()) + ENV_ALIASES.get(provider, {}).get(name, ())


def env_value(env: Dict[str, str], provider: str, name: str) -> str:
    """First deployment value for this field. When several names are set, the
    first one that passes the field's format check wins (a stale/garbled copy
    under one name never hides a good one under another). Never logged."""
    values = [str(env.get(var, "") or "").strip() for var in env_names(provider, name)]
    values = [v for v in values if v]
    for value in values:
        if validate_field(provider, name, value) is None:
            return value
    return values[0] if values else ""


def youtube_api_key(env: Dict[str, str] | None = None) -> str:
    """The one place every YouTube caller reads the deployment key from."""
    return env_value(dict(os.environ) if env is None else env, "youtube_data", "api_key")


# Providers the runtime uses the moment a key is present: their callers
# (e.g. platform.youtube_key() for video search) never consult the Command
# Center on/off switch, so their status must not claim DISABLED while they
# are in use. Configured => active, live mode; LIVE still needs a passed check.
ACTIVE_WHEN_CONFIGURED = frozenset({"youtube_data"})

# The sandbox gateway only ever exists outside production.
PRODUCTION_ENV_NAMES = ("production", "prod")


def is_production(env: Dict[str, str]) -> bool:
    name = (env.get("RAILWAY_ENVIRONMENT_NAME") or env.get("ASKODOX_ENV") or "").strip().lower()
    return name in PRODUCTION_ENV_NAMES


def _json_service_account(value: str) -> bool:
    try:
        data = json.loads(value)
    except (TypeError, ValueError):
        return False
    return isinstance(data, dict) and data.get("type") == "service_account" and all(
        data.get(k) for k in ("project_id", "client_email", "private_key"))


# Format checks run when a value is saved. They catch pasted-wrong-field mistakes;
# only a live Check proves a credential works. Messages never echo the value.
_RX = {
    "digits": r"^\d{6,20}$",
    "rzp_key_id": r"^rzp_(test|live)_[A-Za-z0-9]{8,32}$",
    "youtube_key": r"^AIza[0-9A-Za-z_\-]{35}$",
    "twilio_sid": r"^AC[0-9a-fA-F]{32}$",
    "sender_id": r"^([A-Za-z]{6}|\+?\d{8,15})$",
    "host": r"^[A-Za-z0-9.\-]{3,253}$",
    "email": r"^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,}$",
    "port": r"^(25|465|587|2525)$",
    "api_version": r"^v\d{2}\.\d$",
    "token": r"^\S{16,4096}$",
    "template": r"^[a-z0-9_]{1,512}$",
    "lang": r"^[a-z]{2,3}(_[A-Z]{2})?$",
    "vendor": r"^(msg91|twilio)$",
    "flow": r"^[A-Za-z0-9]{6,64}$",
}
VALIDATION: Dict[str, Dict[str, str]] = {
    "whatsapp_cloud": {"phone_number_id": "digits", "access_token": "token", "app_secret": "token",
                       "api_version": "api_version", "template_name": "template", "template_language": "lang"},
    "sms": {"vendor": "vendor", "sender_id": "sender_id", "dlt_template_id": "flow", "account_sid": "twilio_sid",
            "api_key": "token"},
    "email": {"host": "host", "from_address": "email", "port": "port", "username": "email"},
    "youtube_data": {"api_key": "youtube_key"},
    "razorpay": {"key_id": "rzp_key_id", "key_secret": "token", "webhook_secret": "token"},
}


def validate_field(provider: str, name: str, value: str) -> Optional[str]:
    """None when the value looks right, else a message naming the field (never the value)."""
    value = str(value or "").strip()
    if provider == "fcm_push" and name == "service_account_json":
        return None if _json_service_account(value) else (
            "service_account_json must be the Firebase service-account JSON file (type, project_id, client_email, "
            "private_key)")
    kind = VALIDATION.get(provider, {}).get(name)
    if kind and not __import__("re").match(_RX[kind], value):
        return f"{name} does not look right for {PROVIDERS[provider][1]}"
    return None


class IntegrationRegistry:
    """Provider config: public keys in the clear, secrets encrypted with the
    server-side key (secret_box). Secrets are write-only through the API."""

    def __init__(self, db_path: str, *, secret_box: Any = None, env: Dict[str, str] | None = None) -> None:
        self.db_path = db_path
        self.box = secret_box
        self.env = env if env is not None else dict(os.environ)
        with self._connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS pf_integrations (provider TEXT PRIMARY KEY, enabled INTEGER NOT NULL "
                "DEFAULT 0, mode TEXT NOT NULL DEFAULT 'test', config_json TEXT NOT NULL DEFAULT '{}', "
                "secrets_json TEXT NOT NULL DEFAULT '{}', last_check_at TEXT, last_check_ok INTEGER, "
                "last_check_detail TEXT, updated_by TEXT, updated_at TEXT)")
            conn.execute("CREATE TABLE IF NOT EXISTS pf_quota (provider TEXT NOT NULL, day TEXT NOT NULL, "
                         "units INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(provider, day))")

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _row(self, provider: str) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_integrations WHERE provider=?", (provider,)).fetchone()
        if not row:
            return {"provider": provider, "enabled": 0, "mode": "test", "config_json": "{}", "secrets_json": "{}",
                    "last_check_at": None, "last_check_ok": None, "last_check_detail": None}
        return dict(row)

    def _secrets(self, row: Dict[str, Any]) -> Dict[str, str]:
        stored = json.loads(row.get("secrets_json") or "{}")
        out = {}
        for name, token in stored.items():
            try:
                out[name] = self.box.decrypt(token) if self.box else ""
            except Exception:
                out[name] = ""
        return out

    def _env(self, provider: str, name: str) -> str:
        return env_value(self.env, provider, name)

    def secret(self, provider: str, name: str) -> str:
        return self._secrets(self._row(provider)).get(name, "") or self._env(provider, name)

    def config_value(self, provider: str, key: str) -> str:
        config = json.loads(self._row(provider).get("config_json") or "{}")
        return str(config.get(key) or "") or self._env(provider, key)

    @staticmethod
    def secret_names(provider: str) -> tuple[str, ...]:
        return PROVIDERS[provider][2] + OPTIONAL_SECRETS.get(provider, ())

    @staticmethod
    def config_keys(provider: str) -> tuple[str, ...]:
        return PROVIDERS[provider][3] + OPTIONAL_CONFIG.get(provider, ())

    def available(self, provider: str) -> bool:
        """False for the sandbox gateway in production -- it must never take a payment there."""
        return not (provider == "sandbox_gateway" and is_production(self.env))

    def status(self, provider: str) -> Dict[str, Any]:
        group, label, secret_names, config_keys, internal = PROVIDERS[provider]
        row = self._row(provider)
        config = json.loads(row.get("config_json") or "{}")
        stored = set(json.loads(row.get("secrets_json") or "{}"))
        # Where each value comes from (names only -- values are never returned).
        sources: Dict[str, str] = {}
        for name in self.secret_names(provider):
            if name in stored:
                sources[name] = "command_center"
            elif self._env(provider, name):
                sources[name] = "environment"
        for key in self.config_keys(provider):
            if config.get(key):
                sources[key] = "command_center"
            elif self._env(provider, key):
                sources[key] = "environment"
        have_secrets = {n for n in self.secret_names(provider) if n in sources}
        public_config = {k: config.get(k) or self._env(provider, k) for k in self.config_keys(provider)
                         if config.get(k) or self._env(provider, k)}
        missing = [s for s in secret_names if s not in have_secrets] + [k for k in config_keys if k not in sources]
        invalid = [n for n, src in sources.items() if src == "environment"
                   and validate_field(provider, n, self._env(provider, n))]
        mode = row.get("mode") or "test"
        enabled = bool(row.get("enabled"))
        if provider in ACTIVE_WHEN_CONFIGURED and not missing and mode != "mock":
            enabled, mode = True, "live"
        if internal:
            state = STATUS_LIVE
        elif not self.available(provider):
            state = STATUS_DISABLED
        elif enabled and mode == "mock":
            state = STATUS_MOCK  # never contacts the provider, so credentials are not needed
        elif missing:
            state = STATUS_NEEDS
        elif not enabled:
            state = STATUS_DISABLED
        elif row.get("last_check_ok") == 0:
            state = STATUS_ERROR
        else:
            state = STATUS_LIVE if mode == "live" and row.get("last_check_ok") == 1 else STATUS_TEST
        if internal:
            readiness = "OK"  # built in, no external service to check
        elif missing and state != STATUS_MOCK:
            readiness = "NOT_CONFIGURED"
        elif state == STATUS_DISABLED:
            readiness = "DISABLED"
        elif row.get("last_check_ok") == 0:
            readiness = "CHECK_FAILED"
        elif row.get("last_check_ok") == 1:
            readiness = "LIVE" if state == STATUS_LIVE else "OK"
        else:
            readiness = "CONFIGURED"  # credentials present, no passed real check yet
        return {"provider": provider, "group": group, "label": label, "status": state, "internal": internal,
                "readiness": readiness,
                "enabled": enabled or internal, "mode": mode, "available": self.available(provider),
                "config": public_config, "secrets_set": sorted(have_secrets), "missing": missing,
                "secret_names": list(self.secret_names(provider)), "config_keys": list(self.config_keys(provider)),
                "required": list(secret_names) + list(config_keys), "sources": sources, "invalid": invalid,
                "warnings": self._warnings(provider, sources, invalid),
                **({"quota": {"used_today": self.quota_used(provider), "daily_cap": self.quota_cap(provider)}}
                   if provider in self.QUOTA_CAPS else {}),
                "env_vars": dict(ENV_SOURCES.get(provider, {})),
                "env_aliases": {k: list(v) for k, v in ENV_ALIASES.get(provider, {}).items()},
                "last_check_at": row.get("last_check_at"), "last_check_ok": row.get("last_check_ok"),
                "last_check_detail": row.get("last_check_detail")}

    # daily API quota (YouTube resets at midnight Pacific time) ----------
    QUOTA_CAPS = {"youtube_data": ("ASKODOX_YOUTUBE_DAILY_UNITS", 9000)}

    @staticmethod
    def _quota_day() -> str:
        try:
            from zoneinfo import ZoneInfo

            return datetime.now(ZoneInfo("America/Los_Angeles")).date().isoformat()
        except Exception:
            return (datetime.now(timezone.utc) - timedelta(hours=8)).date().isoformat()

    def quota_cap(self, provider: str) -> int:
        var, default = self.QUOTA_CAPS.get(provider, ("", 0))
        try:
            return max(0, int(self.env.get(var) or default))
        except ValueError:
            return default

    def quota_used(self, provider: str) -> int:
        with self._connect() as conn:
            row = conn.execute("SELECT units FROM pf_quota WHERE provider=? AND day=?",
                               (provider, self._quota_day())).fetchone()
        return int(row["units"]) if row else 0

    def spend(self, provider: str, units: int) -> bool:
        """Reserve quota units for one call; False (nothing reserved) once the daily cap is reached."""
        cap, day = self.quota_cap(provider), self._quota_day()
        with self._connect() as conn:
            conn.execute("INSERT OR IGNORE INTO pf_quota (provider, day, units) VALUES (?, ?, 0)", (provider, day))
            cur = conn.execute("UPDATE pf_quota SET units = units + ? WHERE provider=? AND day=? AND units + ? <= ?",
                               (units, provider, day, units, cap))
            return cur.rowcount > 0

    @staticmethod
    def _warnings(provider: str, sources: Dict[str, str], invalid: List[str]) -> List[str]:
        out = [f"{name} (deployment variable) does not look right" for name in invalid]
        if provider == "whatsapp_cloud" and "access_token" in sources and "app_secret" not in sources:
            out.append("Inbound WhatsApp webhooks are not signature-verified until app_secret is set")
        if provider == "razorpay" and "key_id" in sources and "webhook_secret" not in sources:
            out.append("Without webhook_secret, payments are confirmed only by the checkout callback")
        return out

    def all(self) -> List[Dict[str, Any]]:
        return [self.status(p) for p in PROVIDERS]

    def configure(self, provider: str, *, actor: str, enabled: bool | None = None, mode: str | None = None,
                  config: Dict[str, Any] | None = None, secrets: Dict[str, str] | None = None) -> Dict[str, Any]:
        if provider not in PROVIDERS:
            raise KeyError(provider)
        if mode is not None and mode not in MODES:
            raise ValueError("mode must be test, live or mock")
        if not self.available(provider) and enabled:
            raise PermissionError("the sandbox gateway cannot be enabled in production")
        secret_names, config_keys = self.secret_names(provider), self.config_keys(provider)
        row = self._row(provider)
        cfg = json.loads(row.get("config_json") or "{}")
        for key, value in (config or {}).items():
            if key not in config_keys:
                raise ValueError(f"unknown config key {key}")
            if str(value).strip():
                problem = validate_field(provider, key, str(value))
                if problem:
                    raise ValueError(problem)
            cfg[key] = str(value).strip()[:300]
        stored = json.loads(row.get("secrets_json") or "{}")
        if secrets:
            if self.box is None or not self.box.configured:
                raise PermissionError("ASKODOX_SECRETS_KEY is not configured -- secrets cannot be stored")
            for name, value in secrets.items():
                if name not in secret_names:
                    raise ValueError(f"unknown secret {name}")
                if value:
                    problem = validate_field(provider, name, str(value))
                    if problem:
                        raise ValueError(problem)
                if value:
                    stored[name] = self.box.encrypt(str(value))
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pf_integrations (provider, enabled, mode, config_json, secrets_json, updated_by, "
                "updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(provider) DO UPDATE SET enabled=excluded.enabled,"
                " mode=excluded.mode, config_json=excluded.config_json, secrets_json=excluded.secrets_json, "
                "updated_by=excluded.updated_by, updated_at=excluded.updated_at, last_check_ok=NULL",
                (provider, int(enabled if enabled is not None else row.get("enabled") or 0),
                 mode or row.get("mode") or "test", json.dumps(cfg), json.dumps(stored), actor, now_iso()))
        return self.status(provider)

    def record_check(self, provider: str, ok: bool, detail: str) -> Dict[str, Any]:
        self._row(provider)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pf_integrations (provider, last_check_at, last_check_ok, last_check_detail, updated_at) "
                "VALUES (?, ?, ?, ?, ?) ON CONFLICT(provider) DO UPDATE SET last_check_at=excluded.last_check_at, "
                "last_check_ok=excluded.last_check_ok, last_check_detail=excluded.last_check_detail",
                (provider, now_iso(), int(ok), detail[:300], now_iso()))
        return self.status(provider)


# ---------------------------------------------------------------- payments --

class PaymentService:
    """Provider-agnostic. Internal methods (COD, cash at pickup, direct UPI,
    direct merchant payment) work today; gateway providers stay unavailable
    until configured. Card data is never stored -- gateways own it."""

    INTERNAL_METHODS = ("cod", "cash_on_pickup", "direct_upi", "direct_merchant")
    GATEWAY_METHODS = ("upi", "upi_qr", "payment_link", "card", "netbanking", "wallet", "escrow")

    def __init__(self, repo: PlatformRepository, registry: IntegrationRegistry) -> None:
        self.repo = repo
        self.registry = registry

    def create(self, *, idempotency_key: str, method: str, amount: float, order_ref: str | None,
               payer_ref: str | None, payee_ref: str | None, provider: str | None = None,
               actor: str = "system") -> Dict[str, Any]:
        if not idempotency_key or len(idempotency_key) > 80:
            raise ValueError("an idempotency key (1-80 chars) is required")
        if amount is None or float(amount) <= 0:
            raise ValueError("amount must be positive")
        if method in self.INTERNAL_METHODS:
            provider = "direct_settlement"
        elif method in self.GATEWAY_METHODS:
            if not provider or provider not in PROVIDERS or PROVIDERS[provider][0] != "payments":
                raise ValueError("choose a payment provider for online methods")
            if not self.registry.available(provider):
                raise PlatformConflict(f"{PROVIDERS[provider][1]} is not available in this environment")
            status = self.registry.status(provider)
            if status["status"] not in (STATUS_LIVE, STATUS_TEST):
                raise PlatformConflict(f"{status['label']} is {status['status'].replace('_', ' ').lower()}")
        else:
            raise ValueError("unknown payment method")
        payment, created = self.repo.create_payment(
            idempotency_key=idempotency_key, provider=provider, method=method, amount=float(amount),
            order_ref=order_ref, payer_ref=payer_ref, payee_ref=payee_ref, actor=actor)
        if created:
            if method in self.INTERNAL_METHODS:
                payment = self.repo.transition_payment(payment["id"], "PENDING", actor=actor,
                                                       note="awaiting direct settlement")
            self.repo.record_event("payment", order_id=order_ref, transaction_id=payment["id"], value=amount,
                                   currency="INR", dedupe_key=f"payment_created:{payment['id']}",
                                   detail={"state": payment["status"], "method": method})
        return payment | {"created": created}

    def simulate(self, payment_id: str, outcome: str, *, actor: str) -> Dict[str, Any]:
        """Sandbox gateway only (never in production): play the gateway's part --
        PAID / FAILED -- through the same state machine a real webhook uses."""
        payment = self.repo.payment(payment_id)
        if not payment:
            raise KeyError(payment_id)
        if payment["provider"] != "sandbox_gateway":
            raise PlatformConflict("only sandbox payments can be simulated")
        if not self.registry.available("sandbox_gateway"):
            raise PlatformConflict("the sandbox gateway is not available in production")
        target = {"paid": "PAID", "failed": "FAILED"}.get(outcome)
        if not target:
            raise ValueError("outcome must be paid or failed")
        return self.repo.transition_payment(payment_id, target, actor=f"sandbox:{actor}",
                                            provider_ref=f"sandbox_{payment_id}" if target == "PAID" else None,
                                            note="simulated by the sandbox gateway (no real money)")

    def confirm_direct(self, payment_id: str, *, reference: str = "", actor: str) -> Dict[str, Any]:
        payment = self.repo.payment(payment_id)
        if not payment:
            raise KeyError(payment_id)
        if payment["provider"] != "direct_settlement":
            raise PlatformConflict("gateway payments are confirmed by the gateway webhook")
        return self.repo.transition_payment(payment_id, "PAID", actor=actor, provider_ref=reference or None,
                                            note="payee confirmed receipt")

    @staticmethod
    def signature(secret: str, body: bytes) -> str:
        return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()

    def webhook(self, provider: str, body: bytes, signature: str) -> Dict[str, Any]:
        """Generic signed webhook: HMAC-SHA256 of the raw body with the
        provider's webhook secret. Replays are ignored; unknown payments and
        illegal transitions are refused."""
        if provider not in PROVIDERS or PROVIDERS[provider][0] != "payments" or PROVIDERS[provider][4]:
            raise KeyError(provider)
        secret = self.registry.secret(provider, "webhook_secret")
        if not secret:
            raise PermissionError("webhook secret not configured")
        if not signature or not hmac.compare_digest(self.signature(secret, body), signature.strip()):
            raise PermissionError("invalid signature")
        try:
            event = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise ValueError("body is not JSON") from None
        event_id = str(event.get("event_id") or "")
        payment_id = str(event.get("payment_id") or "")
        to_state = str(event.get("status") or "").upper()
        if not event_id or not payment_id or not to_state:
            raise ValueError("event_id, payment_id and status are required")
        payment = self.repo.payment(payment_id)
        if not payment or payment["provider"] != provider:
            raise KeyError(payment_id)
        if self.repo.seen_webhook(provider, event_id, payment_id=payment_id, event=to_state):
            return {"duplicate": True, "payment": payment}
        refund = event.get("refund_amount")
        updated = self.repo.transition_payment(payment_id, to_state, actor=f"webhook:{provider}",
                                               provider_ref=event.get("provider_ref"),
                                               refund_amount=float(refund) if refund is not None else None,
                                               settlement_ref=event.get("settlement_ref"), note=f"event {event_id}")
        return {"duplicate": False, "payment": updated}

    def refund(self, payment_id: str, amount: float | None, *, actor: str, note: str = "") -> Dict[str, Any]:
        payment = self.repo.payment(payment_id)
        if not payment:
            raise KeyError(payment_id)
        target = "REFUNDED" if amount is None or abs(float(amount) - (payment["amount"] - payment["refunded_amount"])) \
            < 1e-9 else "PARTIALLY_REFUNDED"
        return self.repo.transition_payment(payment_id, target, actor=actor, refund_amount=amount, note=note)

    def settle(self, payment_id: str, settlement_ref: str, *, actor: str) -> Dict[str, Any]:
        return self.repo.transition_payment(payment_id, "SETTLED", actor=actor, settlement_ref=settlement_ref)

    def reconcile(self) -> Dict[str, Any]:
        payments = self.repo.payments(limit=10000)
        issues = []
        for p in payments:
            if p["status"] == "PAID" and p["provider"] != "direct_settlement" and not p["provider_ref"]:
                issues.append({"payment_id": p["id"], "issue": "paid without a gateway reference"})
            if p["refunded_amount"] > p["amount"] + 1e-9:
                issues.append({"payment_id": p["id"], "issue": "refunded more than paid"})
            if p["status"] in ("CREATED", "PENDING"):
                try:
                    age = datetime.now(timezone.utc) - datetime.fromisoformat(p["created_at"])
                    if age > timedelta(hours=24):
                        issues.append({"payment_id": p["id"], "issue": "pending for more than 24 hours"})
                except ValueError:
                    pass
        totals: Dict[str, float] = {}
        for p in payments:
            totals[p["status"]] = round(totals.get(p["status"], 0) + p["amount"], 2)
        return {"count": len(payments), "totals_by_state": totals, "issues": issues}


# ------------------------------------------------------------------ ledger --

class RevenueLedger:
    def __init__(self, repo: PlatformRepository) -> None:
        self.repo = repo

    def summary(self, *, since: str | None = None, until: str | None = None) -> Dict[str, Any]:
        entries = self.repo.ledger(since=since, until=until)
        by_state: Dict[str, float] = {}
        by_kind: Dict[str, float] = {}
        for e in entries:
            by_state[e["state"]] = round(by_state.get(e["state"], 0) + e["amount"], 2)
            if e["state"] in ("CONFIRMED", "PAID"):
                by_kind[e["kind"]] = round(by_kind.get(e["kind"], 0) + e["amount"], 2)
        return {"entries": len(entries), "by_state": by_state, "realised_by_kind": by_kind,
                "realised": round(sum(v for k, v in by_state.items() if k in ("CONFIRMED", "PAID")), 2),
                "outstanding": round(sum(v for k, v in by_state.items() if k in ("EXPECTED", "PENDING")), 2),
                "kinds": list(LEDGER_KINDS)}

    def reconcile(self) -> Dict[str, Any]:
        """Ledger vs attribution: every commission must trace to a click /
        conversion; paid entries must have been confirmed first."""
        issues = []
        for entry in self.repo.ledger():
            if entry["kind"] == "affiliate_commission" and entry["conversion_id"]:
                if not self.repo.events(event="conversion", conversion_id=entry["conversion_id"], limit=1):
                    issues.append({"ledger_id": entry["id"], "issue": "commission without a tracked conversion"})
            history = [h["to_state"] for h in self.repo.state_history("ledger", entry["id"])]
            if entry["state"] == "PAID" and "CONFIRMED" not in history:
                issues.append({"ledger_id": entry["id"], "issue": "paid without being confirmed"})
        return {"issues": issues, "checked": len(self.repo.ledger())}


# ------------------------------------------------------------ transactions --

def transaction_center(repo: PlatformRepository, fetch_rows: Callable[[str], List[Dict[str, Any]]], *,
                       kind: str = "", status: str = "", q: str = "", limit: int = 300) -> List[Dict[str, Any]]:
    """One timeline across payments, orders, claims / redemptions, rewards,
    conversions, refunds, settlements and commissions."""
    items: List[Dict[str, Any]] = []
    for p in repo.payments(limit=2000):
        items.append({"kind": "payment", "id": p["id"], "status": p["status"], "amount": p["amount"],
                      "ref": p["order_ref"], "party": p["provider"], "at": p["updated_at"]})
        if p["refunded_amount"]:
            items.append({"kind": "refund", "id": p["id"], "status": p["status"], "amount": -p["refunded_amount"],
                          "ref": p["order_ref"], "party": p["provider"], "at": p["updated_at"]})
        if p["settlement_ref"]:
            items.append({"kind": "settlement", "id": p["settlement_ref"], "status": "SETTLED", "amount": p["amount"],
                          "ref": p["id"], "party": p["provider"], "at": p["updated_at"]})
    for e in repo.ledger():
        items.append({"kind": e["kind"], "id": e["id"], "status": e["state"], "amount": e["amount"],
                      "ref": e["conversion_id"] or e["source_ref"], "party": e["partner_id"], "at": e["updated_at"]})
    for r in repo.rewards():
        items.append({"kind": "reward" if r["source"] != "merchant_offer" else "offer_claim", "id": r["id"],
                      "status": r["state"], "amount": r["amount"], "ref": r["campaign_id"], "party": r["reward_type"],
                      "at": r["updated_at"]})
    for ev in repo.events(event="conversion", limit=2000):
        items.append({"kind": "conversion", "id": ev["conversion_id"] or str(ev["id"]), "status": "REPORTED",
                      "amount": ev["value"], "ref": ev["click_id"], "party": ev["partner_id"], "at": ev["at"]})
    for o in fetch_rows("SELECT id, status, total_amount, updated_at FROM orders ORDER BY id DESC LIMIT 500"):
        items.append({"kind": "order", "id": str(o.get("id")), "status": o.get("status"),
                      "amount": o.get("total_amount"), "ref": None, "party": None, "at": o.get("updated_at")})
    if kind:
        items = [i for i in items if i["kind"] == kind]
    if status:
        items = [i for i in items if str(i["status"]).upper() == status.upper()]
    if q:
        needle = q.lower()
        items = [i for i in items if needle in json.dumps(i, default=str).lower()]
    items.sort(key=lambda i: str(i["at"] or ""), reverse=True)
    return items[:limit]


# --------------------------------------------------------- notifications --

class NotificationDispatcher:
    """Renders templates and dispatches through enabled rules. In-app
    notifications are stored; push uses the existing FCM sender when
    configured; email / SMS / WhatsApp are skipped with NEEDS_CONFIGURATION
    until their providers are configured."""

    CHANNEL_PROVIDER = {"push": "fcm_push", "email": "email", "sms": "sms", "whatsapp": "whatsapp_cloud"}

    def __init__(self, repo: PlatformRepository, registry: IntegrationRegistry,
                 senders: Dict[str, Callable[[str, str, str], bool]] | None = None, messenger: Any = None) -> None:
        self.repo = repo
        self.registry = registry
        self.senders = senders or {}
        self.messenger = messenger  # comms.Messenger: real / mock delivery + outbox

    @staticmethod
    def render(text: str, values: Dict[str, Any]) -> str:
        out = str(text)
        for key, value in values.items():
            out = out.replace("{" + str(key) + "}", str(value))
        return out

    def template(self, key: str, channel: str, language: str = "en") -> Optional[Dict[str, Any]]:
        candidates = [t for t in self.repo.list("notification_templates", status="ACTIVE")
                      if t["data"].get("key") == key and t["data"].get("channel") == channel]
        for t in candidates:
            if (t["data"].get("language") or "en") == language:
                return t
        return candidates[0] if candidates else None

    def dispatch(self, event: str, *, user_ref: str, values: Dict[str, Any], language: str = "en",
                 channel_on: Callable[[str], bool] | None = None, contact_id: str | None = None) -> List[Dict]:
        results = []
        for rule in self.repo.list("notification_rules", status="ACTIVE"):
            d = rule["data"]
            if d.get("event") != event:
                continue
            throttle = int(d.get("throttle_minutes") or 0)
            for channel in d.get("channels") or ["in_app"]:
                template = self.template(d.get("template_key"), channel, language)
                if not template:
                    results.append({"rule": rule["id"], "channel": channel, "status": "no_template"})
                    continue
                if throttle:
                    since = (datetime.now(timezone.utc) - timedelta(minutes=throttle)).isoformat()
                    recent = [e for e in self.repo.events(event="notification_sent", user_ref=user_ref, since=since)
                              if e["detail"].get("rule") == rule["id"] and e["detail"].get("channel") == channel]
                    if recent:
                        results.append({"rule": rule["id"], "channel": channel, "status": "throttled"})
                        continue
                title = self.render(template["data"]["title"], values)
                body = self.render(template["data"]["body"], values)
                status = "sent"
                if channel_on is not None and not channel_on(channel):
                    status = "skipped_switched_off"  # feature flag notifications.<channel>
                elif channel != "in_app" and self.messenger is not None and channel not in self.senders:
                    # sent / mock_delivered / failed / skipped_needs_configuration / skipped_no_contact ...
                    status = self.messenger.send(channel, title=title, body=body, user_ref=user_ref,
                                                 event=event, contact_id=contact_id)["status"].lower()
                elif channel != "in_app":
                    provider = self.CHANNEL_PROVIDER[channel]
                    if self.registry.status(provider)["status"] not in (STATUS_LIVE, STATUS_TEST):
                        status = "skipped_needs_configuration"
                    elif channel in self.senders:
                        status = "sent" if self.senders[channel](user_ref, title, body) else "failed"
                    else:
                        status = "skipped_no_sender"
                self.repo.record_event("notification_sent", user_ref=user_ref,
                                       detail={"rule": rule["id"], "channel": channel, "status": status,
                                               "title": title, "body": body, "type": template["data"].get("type")})
                results.append({"rule": rule["id"], "channel": channel, "status": status, "title": title})
        return results

    def inbox(self, user_ref: str) -> List[Dict[str, Any]]:
        return [{"id": e["id"], "title": e["detail"].get("title"), "body": e["detail"].get("body"),
                 "type": e["detail"].get("type"), "at": e["at"]}
                for e in self.repo.events(event="notification_sent", user_ref=user_ref, limit=100)
                if e["detail"].get("channel") == "in_app" and e["detail"].get("status") == "sent"]


# ------------------------------------------------------ analytics / insights --

FUNNEL = ("search", "impression", "result_view", "click", "claim", "lead", "order", "payment", "redemption",
          "conversion", "commission")
VIDEO_FUNNEL = ("video_impression", "video_open", "video_watch_start", "video_watch_complete", "video_ask",
                "video_product_click", "video_service_click", "video_local_search", "video_affiliate_click",
                "video_contact", "lead", "order", "conversion")


def period(days: int) -> tuple[str, str, str]:
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)
    prev = start - timedelta(days=days)
    return prev.isoformat(), start.isoformat(), now.isoformat()


def analytics(repo: PlatformRepository, *, days: int = 30, where: Dict[str, Any] | None = None) -> Dict[str, Any]:
    _, since, until = period(days)
    counts = {r["event"]: r for r in repo.event_counts(since=since, until=until, where=where)}
    funnel = [{"step": s, "count": int(counts.get(s, {}).get("n", 0))} for s in FUNNEL]
    video = [{"step": s, "count": int(counts.get(s, {}).get("n", 0))} for s in VIDEO_FUNNEL]
    by_category = [r for r in repo.event_counts(since=since, until=until, group="category", where=where)
                   if r["event"] == "search" and r.get("category")]
    by_location = [r for r in repo.event_counts(since=since, until=until, group="location", where=where)
                   if r["event"] == "search" and r.get("location")]
    by_video = [r for r in repo.event_counts(since=since, until=until, group="video_id", where=where)
                if r.get("video_id")]
    video_table: Dict[str, Dict[str, int]] = {}
    for r in by_video:
        video_table.setdefault(r["video_id"], {})[r["event"]] = int(r["n"])
    users = {e["user_ref"] for e in repo.events(since=(datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
                                                limit=100000) if e["user_ref"]}
    revenue = sum(float(e["amount"]) for e in repo.ledger(since=since, until=until) if e["state"] in ("CONFIRMED",
                                                                                                         "PAID"))
    return {"days": days, "funnel": funnel, "video_funnel": video, "daily_active_users": len(users),
            "searches": int(counts.get("search", {}).get("n", 0)),
            "no_match": int(counts.get("no_match", {}).get("n", 0)),
            "coupon_claims": int(counts.get("coupon_claim", {}).get("n", 0)) + int(counts.get("claim", {}).get("n", 0)),
            "coupon_redemptions": int(counts.get("coupon_redeem", {}).get("n", 0)) + int(
                counts.get("redemption", {}).get("n", 0)),
            "revenue_realised": round(revenue, 2),
            "categories": [{"category": r["category"], "searches": r["n"]} for r in by_category[:20]],
            "locations": [{"location": r["location"], "searches": r["n"]} for r in by_location[:20]],
            "videos": [{"video_id": vid, **stats} for vid, stats in list(video_table.items())[:50]]}


def insights(repo: PlatformRepository, *, days: int = 7, extra: Dict[str, Any] | None = None) -> List[Dict[str, Any]]:
    """Actionable, rule-based insights: observation (real counts) -> possible
    reason -> recommended action -> expected impact. They never act on their
    own -- an admin decides. Categories are the specific detected ones
    (e.g. "samsung 43 inch tv", "plumber"), never just PRODUCT / SERVICES."""
    prev_start, start, now = period(days)
    cur = {r["event"]: r["n"] for r in repo.event_counts(since=start, until=now)}
    prev = {r["event"]: r["n"] for r in repo.event_counts(since=prev_start, until=start)}
    out: List[Dict[str, Any]] = []

    def add(kind: str, severity: str, observation: str, reason: str, action: str, impact: str,
            evidence: Dict[str, Any], confidence: str = "POSSIBLE") -> None:
        out.append({"kind": kind, "severity": severity, "observation": observation, "possible_reason": reason,
                    "recommended_action": action, "impact": impact, "confidence": confidence,
                    "evidence": evidence, "title": observation, "suggestion": action})

    def change(event: str) -> Optional[float]:
        a, b = cur.get(event, 0), prev.get(event, 0)
        return None if b == 0 else round((a - b) / b * 100, 1)

    by_cat = repo.event_counts(since=start, until=now, group="category")
    searches = {r["category"]: r["n"] for r in by_cat if r["event"] == "search" and r.get("category")}
    for event, label in (("search", "Searches"), ("conversion", "Conversions"), ("click", "Clicks")):
        pct = change(event)
        if pct is not None and abs(pct) >= 25:
            top = sorted(searches.items(), key=lambda kv: -kv[1])[:3]
            add("trend", "info" if pct > 0 else "warning",
                f"{label} {'up' if pct > 0 else 'down'} {abs(pct)}% vs the previous {days} days "
                f"({prev.get(event, 0)} -> {cur.get(event, 0)})",
                "Seasonal demand, a campaign starting/ending, or a source (Places / web / sellers) changing "
                "availability." + (f" Most searched now: {', '.join(c for c, _ in top)}." if top else ""),
                "Open Analytics filtered by the top categories and compare source status and campaigns.",
                f"{abs(cur.get(event, 0) - prev.get(event, 0))} {label.lower()} difference per {days} days.",
                {"current": cur.get(event, 0), "previous": prev.get(event, 0)})
    gaps = sorted(((r["category"], r["n"]) for r in by_cat if r["event"] == "no_match" and r.get("category")),
                  key=lambda kv: -kv[1])
    for category, n in gaps[:5]:
        if n >= 3:
            total = searches.get(category, n)
            add("supply_gap", "warning",
                f"'{category}': {n} of {total} searches found no match in {days} days",
                "No ASKODOX seller / provider lists this near the customers, and online / nearby sources "
                "returned nothing relevant.",
                f"Invite sellers or providers for '{category}' (Referrals, merchant onboarding) or add a source.",
                f"Up to {n} customers per {days} days could be served instead of leaving empty-handed.",
                {"no_match_searches": n, "searches": total}, "CONFIRMED")
    leads = {r["category"]: r["n"] for r in by_cat if r["event"] in ("lead", "order") and r.get("category")}
    for category, n in sorted(searches.items(), key=lambda kv: -kv[1])[:5]:
        if n >= 20 and leads.get(category, 0) == 0:
            add("conversion_gap", "warning",
                f"'{category}': {n} searches but no lead or order in {days} days",
                "Results may be irrelevant, too far, missing prices, or sellers are not responding.",
                f"Open a few traces for '{category}' (Flow traces) and check result relevance and seller replies.",
                f"Converting even 5% would mean about {max(1, n // 20)} leads per {days} days.",
                {"searches": n, "leads_orders": 0})
    locs = [r for r in repo.event_counts(since=start, until=now, group="location") if r["event"] == "search"]
    for r in locs[:3]:
        if r.get("location") and r["n"] >= 10:
            add("demand", "info", f"High demand in {r['location']} ({r['n']} searches in {days} days)",
                "An active local customer base or a local event.",
                "Prioritise merchant acquisition, local offers and a targeted promotion for this area.",
                f"{r['n']} searches per {days} days to serve with local supply.", {"searches": r["n"]},
                "CONFIRMED")
    impressions = {r["campaign_id"]: r["n"] for r in repo.event_counts(since=start, until=now, group="campaign_id")
                   if r["event"] == "impression" and r.get("campaign_id")}
    clicks = {r["campaign_id"]: r["n"] for r in repo.event_counts(since=start, until=now, group="campaign_id")
              if r["event"] == "click" and r.get("campaign_id")}
    for cid, n in impressions.items():
        ctr = clicks.get(cid, 0) / n if n else 0
        if n >= 50 and ctr < 0.002:
            add("campaign_anomaly", "warning", f"Campaign {cid}: {n} impressions but CTR {ctr:.2%}",
                "Targeting does not match the audience, or the creative is not relevant.",
                "Review targeting / creative, or pause the campaign.",
                "Stops spend on placements nobody clicks.", {"impressions": n, "clicks": clicks.get(cid, 0)})
        if n >= 20 and clicks.get(cid, 0) > n:
            add("fraud", "critical", f"Campaign {cid}: more clicks ({clicks[cid]}) than impressions ({n})",
                "Automated or repeated clicks (possible click fraud).",
                "Inspect click sources before paying out; pause the campaign if they repeat.",
                "Prevents paying for invalid clicks.", {"impressions": n, "clicks": clicks[cid]}, "CONFIRMED")
    claims_by_user: Dict[str, int] = {}
    for r in repo.rewards():
        if r["state"] in ("CLAIMED", "REDEEMED") and r["created_at"] >= start:
            claims_by_user[r["user_ref"]] = claims_by_user.get(r["user_ref"], 0) + 1
    for user, n in claims_by_user.items():
        if n >= 10:
            add("fraud", "warning", f"One customer ({user}) claimed {n} rewards in {days} days",
                "Reward abuse (multiple accounts or scripted claims) -- or a very loyal customer.",
                "Review the claims before approving payouts.", "Avoids paying invalid rewards.", {"claims": n})
    failed = sum(1 for p in repo.payments(limit=5000) if p["status"] == "FAILED" and p["created_at"] >= start)
    total = sum(1 for p in repo.payments(limit=5000) if p["created_at"] >= start)
    if total >= 5 and failed / total > 0.2:
        add("payments", "warning", f"Payment failures at {failed / total:.0%} ({failed} of {total})",
            "Gateway outage, wrong configuration, or customers abandoning checkout.",
            "Check the gateway status in Integrations and the failure reasons in Payments.",
            f"{failed} failed payments in {days} days.", {"failed": failed, "total": total})
    for item in (extra or {}).get("broken_links", []):
        add("links", "warning", f"Smart link '{item}' failed its health check",
            "The destination page moved or is down.", "Fix or disable the link.",
            "Customers stop landing on an error page.", {}, "CONFIRMED")
    for item in (extra or {}).get("conversation_fixes", []):
        add("conversation", "warning",
            f"ASKODOX corrected '{item['issue']}' {item['occurrences']} times in {days} days",
            "A repeated conversation problem (e.g. unrelated results or prompts, attachment sent to be understood, "
            "stale state) that the GREEN self-healing guard had to correct each time.",
            "Review the Self-healing log entries and fix the underlying flow so the guard is no longer needed.",
            "Fewer wrong turns before the guard steps in; cleaner first replies.",
            {"issue_key": item["issue_key"], "occurrences": item["occurrences"]}, "CONFIRMED")
    if not out:
        add("status", "info", "No notable changes in this period", "Traffic and outcomes are steady.",
            "No action needed.", "None.", {"events": sum(cur.values())}, "CONFIRMED")
    return out
