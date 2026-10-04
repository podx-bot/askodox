"""Outbound communications: WhatsApp, SMS, Email, Push.

One path for every message: ``Messenger.send`` picks the channel's provider
from the integration registry and records the outcome in the delivery
outbox (``pf_outbox``). What happens depends on the provider's state:

* MOCK        -- enabled in mock mode: rendered, validated and stored as
                 MOCK_DELIVERED. Nothing leaves ASKODOX (no credentials needed).
* TEST / LIVE -- credentials present and enabled: sent through the real
                 provider API; SENT with the provider's message id, or FAILED
                 with the provider's error (never raised to the caller).
* anything else (NEEDS_CONFIGURATION / DISABLED / ERROR) -- not sent;
                 recorded as SKIPPED_<state>.

Recipients are masked in the outbox; secrets are never logged. HTTP and SMTP
are injectable so tests exercise the real request shapes without a network.
"""
from __future__ import annotations

import re
import smtplib
import sqlite3
import uuid
from email.message import EmailMessage
from typing import Any, Callable, Dict, List, Optional, Tuple

from app.repositories.platform_repository import now_iso
from app.services.commerce_finance import (
    STATUS_LIVE,
    STATUS_MOCK,
    STATUS_TEST,
    IntegrationRegistry,
)

CHANNEL_PROVIDER = {"push": "fcm_push", "email": "email", "sms": "sms", "whatsapp": "whatsapp_cloud"}
PROVIDER_CHANNEL = {v: k for k, v in CHANNEL_PROVIDER.items()}
SENT, MOCK_DELIVERED, FAILED, NO_CONTACT = "SENT", "MOCK_DELIVERED", "FAILED", "SKIPPED_NO_CONTACT"
OPTED_OUT = "SKIPPED_OPTED_OUT"
OPTABLE_CHANNELS = ("whatsapp", "sms", "email", "push")
DEFAULT_WHATSAPP_VERSION = "v21.0"
_EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[A-Za-z]{2,}$")

# (status_code, json) = http(method, url, headers=..., json=..., data=..., auth=..., params=...)
Http = Callable[..., Tuple[int, Any]]


def default_http(method: str, url: str, **kwargs: Any) -> Tuple[int, Any]:
    import httpx

    response = httpx.request(method, url, timeout=10.0, **kwargs)
    try:
        body = response.json()
    except ValueError:
        body = {"text": response.text[:300]}
    return response.status_code, body


def mask(to: str) -> str:
    to = str(to or "")
    if "@" in to:
        name, _, domain = to.partition("@")
        return f"{name[:2]}***@{domain}"
    digits = "".join(c for c in to if c.isdigit())
    return f"***{digits[-4:]}" if len(digits) >= 4 else ("***" if to else "")


def phone_digits(to: str) -> str:
    digits = "".join(c for c in str(to or "") if c.isdigit())
    if len(digits) == 10:
        digits = "91" + digits  # Indian mobile without the country code
    return digits


def valid_recipient(channel: str, to: str) -> bool:
    if channel == "email":
        return bool(_EMAIL.match(str(to or "")))
    if channel in ("sms", "whatsapp"):
        return 11 <= len(phone_digits(to)) <= 15
    return bool(str(to or "").strip())  # push: a user id


def transient(error: str) -> bool:
    error = str(error or "")
    return error.startswith(("HTTP 5", "HTTP 429")) or any(
        e in error for e in ("Timeout", "ConnectError", "ReadError", "RemoteProtocolError"))


def _error_text(body: Any) -> str:
    if isinstance(body, dict):
        err = body.get("error") or body.get("message") or body.get("errors") or body
        if isinstance(err, dict):
            err = err.get("message") or err.get("error_user_msg") or err
        return str(err)[:200]
    return str(body)[:200]


class Outbox:
    """Delivery log: one row per attempt, recipient masked, body kept for audit."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS pf_outbox (id TEXT PRIMARY KEY, channel TEXT NOT NULL, provider TEXT "
                "NOT NULL, to_masked TEXT, user_ref TEXT, event TEXT, title TEXT, body TEXT, status TEXT NOT NULL, "
                "mode TEXT, provider_ref TEXT, error TEXT, created_at TEXT NOT NULL)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_pf_outbox_created ON pf_outbox(created_at)")
            columns = {r[1] for r in conn.execute("PRAGMA table_info(pf_outbox)")}
            for column in ("delivery_status", "delivery_error", "delivery_at", "attempts"):
                if column not in columns:  # provider receipts (sent / delivered / read / failed)
                    conn.execute(f"ALTER TABLE pf_outbox ADD COLUMN {column} TEXT")
            # A customer's own choice: channels they do not want messages on.
            conn.execute("CREATE TABLE IF NOT EXISTS pf_comm_optouts (user_ref TEXT NOT NULL, channel TEXT NOT NULL, "
                         "at TEXT NOT NULL, source TEXT, PRIMARY KEY(user_ref, channel))")

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def record(self, **row: Any) -> Dict[str, Any]:
        row = {"id": "out_" + uuid.uuid4().hex[:16], "created_at": now_iso(), **row}
        cols = ("id", "channel", "provider", "to_masked", "user_ref", "event", "title", "body", "status", "mode",
                "provider_ref", "error", "created_at", "attempts")
        row.setdefault("attempts", None)
        with self._connect() as conn:
            conn.execute(f"INSERT INTO pf_outbox ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})",
                         tuple(str(row.get(c))[:2000] if row.get(c) is not None else None for c in cols))
        return {c: row.get(c) for c in cols}

    def get(self, record_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_outbox WHERE id=?", (record_id,)).fetchone()
        return dict(row) if row else None

    def receipt(self, provider: str, provider_ref: str, status: str, error: str | None = None) -> bool:
        """A provider delivery receipt (e.g. WhatsApp sent / delivered / read / failed)."""
        if not provider_ref:
            return False
        with self._connect() as conn:
            cur = conn.execute("UPDATE pf_outbox SET delivery_status=?, delivery_error=?, delivery_at=? "
                               "WHERE provider=? AND provider_ref=?",
                               (str(status)[:30], (error or None) and str(error)[:300], now_iso(), provider,
                                str(provider_ref)[:200]))
        return cur.rowcount > 0

    # opt-outs -----------------------------------------------------------
    def opted_out(self, user_ref: str, channel: str) -> bool:
        if not user_ref:
            return False
        with self._connect() as conn:
            return conn.execute("SELECT 1 FROM pf_comm_optouts WHERE user_ref=? AND channel=?",
                                (user_ref, channel)).fetchone() is not None

    def set_opt_out(self, user_ref: str, channel: str, opted_out: bool, *, source: str = "user") -> None:
        if channel not in OPTABLE_CHANNELS:
            raise ValueError(f"unknown channel {channel}")
        with self._connect() as conn:
            if opted_out:
                conn.execute("INSERT OR REPLACE INTO pf_comm_optouts VALUES (?, ?, ?, ?)",
                             (user_ref, channel, now_iso(), source))
            else:
                conn.execute("DELETE FROM pf_comm_optouts WHERE user_ref=? AND channel=?", (user_ref, channel))

    def preferences(self, user_ref: str) -> Dict[str, bool]:
        return {c: not self.opted_out(user_ref, c) for c in OPTABLE_CHANNELS}

    def optout_counts(self) -> Dict[str, int]:
        with self._connect() as conn:
            rows = conn.execute("SELECT channel, COUNT(*) n FROM pf_comm_optouts GROUP BY channel").fetchall()
        return {r["channel"]: r["n"] for r in rows}

    def list(self, *, channel: str | None = None, limit: int = 100) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM pf_outbox", []
        if channel:
            sql, args = sql + " WHERE channel=?", [channel]
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY created_at DESC LIMIT ?", (*args, max(1, min(limit, 500)))).fetchall()
        return [dict(r) for r in rows]

    def summary(self) -> Dict[str, Dict[str, int]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT channel, status, COUNT(*) n FROM pf_outbox GROUP BY channel, status").fetchall()
        out: Dict[str, Dict[str, int]] = {}
        for r in rows:
            out.setdefault(r["channel"], {})[r["status"]] = r["n"]
        return out


# ---------------------------------------------------------------- senders --
# Each returns (ok, provider_message_id, error).

def send_whatsapp(reg: IntegrationRegistry, http: Http, to: str, title: str, body: str) -> Tuple[bool, str, str]:
    version = reg.config_value("whatsapp_cloud", "api_version") or DEFAULT_WHATSAPP_VERSION
    phone_id = reg.config_value("whatsapp_cloud", "phone_number_id")
    template = reg.config_value("whatsapp_cloud", "template_name")
    text = f"{title}\n{body}".strip() if title else body
    if template:
        # Business-initiated messages outside the 24h window need an approved template.
        payload = {"messaging_product": "whatsapp", "to": phone_digits(to), "type": "template",
                   "template": {"name": template,
                                "language": {"code": reg.config_value("whatsapp_cloud", "template_language") or "en"},
                                "components": [{"type": "body", "parameters": [{"type": "text", "text": text[:1000]}]}]}}
    else:
        payload = {"messaging_product": "whatsapp", "to": phone_digits(to), "type": "text",
                   "text": {"body": text[:4000]}}
    status, data = http("POST", f"https://graph.facebook.com/{version}/{phone_id}/messages",
                        headers={"Authorization": f"Bearer {reg.secret('whatsapp_cloud', 'access_token')}"},
                        json=payload)
    if status == 200 and isinstance(data, dict) and data.get("messages"):
        return True, str(data["messages"][0].get("id") or ""), ""
    return False, "", f"HTTP {status}: {_error_text(data)}"


def send_sms(reg: IntegrationRegistry, http: Http, to: str, title: str, body: str) -> Tuple[bool, str, str]:
    vendor = (reg.config_value("sms", "vendor") or "msg91").lower()
    key, sender = reg.secret("sms", "api_key"), reg.config_value("sms", "sender_id")
    text = f"{title}: {body}" if title else body
    if vendor == "twilio":
        sid = reg.config_value("sms", "account_sid")
        if not sid:
            return False, "", "Twilio needs account_sid"
        status, data = http("POST", f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
                            auth=(sid, key), data={"To": "+" + phone_digits(to), "From": sender, "Body": text[:1500]})
        if status in (200, 201) and isinstance(data, dict) and data.get("sid"):
            return True, str(data["sid"]), ""
        return False, "", f"HTTP {status}: {_error_text(data)}"
    # MSG91 Flow API (India, DLT): the approved flow/template id carries the text.
    flow = reg.config_value("sms", "dlt_template_id")
    if not flow:
        return False, "", "MSG91 needs dlt_template_id (the approved DLT flow id)"
    status, data = http("POST", "https://control.msg91.com/api/v5/flow/", headers={"authkey": key},
                        json={"template_id": flow, "sender": sender, "short_url": "0",
                              "recipients": [{"mobiles": phone_digits(to), "var": text[:300]}]})
    if status == 200 and isinstance(data, dict) and str(data.get("type", "")).lower() == "success":
        return True, str(data.get("message") or ""), ""
    return False, "", f"HTTP {status}: {_error_text(data)}"


def send_email(reg: IntegrationRegistry, smtp_factory: Callable[..., Any], to: str, title: str,
               body: str) -> Tuple[bool, str, str]:
    host, sender = reg.config_value("email", "host"), reg.config_value("email", "from_address")
    port = int(reg.config_value("email", "port") or 587)
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = sender, to, (title or "ASKODOX")[:200]
    msg.set_content(body)
    try:
        with smtp_factory(host, port, timeout=15) as smtp:
            if port != 465:
                smtp.starttls()
            smtp.login(reg.config_value("email", "username") or sender, reg.secret("email", "password"))
            smtp.send_message(msg)
        return True, str(msg.get("Message-ID") or ""), ""
    except Exception as error:  # SMTP errors are reported, never raised
        return False, "", f"{type(error).__name__}: {str(error)[:160]}"


def smtp_for(port: int) -> Callable[..., Any]:
    return smtplib.SMTP_SSL if port == 465 else smtplib.SMTP


class Messenger:
    def __init__(self, registry: IntegrationRegistry, outbox: Outbox, *, http: Http | None = None,
                 smtp_factory: Callable[..., Any] | None = None, push: Any = None,
                 contacts: Callable[[str, str], Optional[str]] | None = None) -> None:
        self.registry = registry
        self.outbox = outbox
        self.http = http or default_http
        self.smtp_factory = smtp_factory
        self.push = push
        self.contacts = contacts or (lambda user_ref, channel: None)

    def _deliver(self, channel: str, to: str, title: str, body: str, user_ref: str | None) -> Tuple[bool, str, str]:
        reg = self.registry
        if channel == "whatsapp":
            return send_whatsapp(reg, self.http, to, title, body)
        if channel == "sms":
            return send_sms(reg, self.http, to, title, body)
        if channel == "email":
            port = int(reg.config_value("email", "port") or 587)
            return send_email(reg, self.smtp_factory or smtp_for(port), to, title, body)
        if channel == "push":
            if self.push is None or not getattr(self.push, "configured", False):
                return False, "", "push sender not configured"
            sent = self.push.notify(user_ref or to, title=title, body=body, route="/notifications",
                                    event_key=f"outbox:{uuid.uuid4().hex[:12]}")
            return (sent > 0, "", "" if sent > 0 else "no registered device token for this user")
        return False, "", f"unknown channel {channel}"

    def send(self, channel: str, *, title: str, body: str, user_ref: str | None = None, to: str | None = None,
             event: str | None = None, contact_id: str | None = None) -> Dict[str, Any]:
        """``user_ref`` is the opaque reference stored in the outbox; ``contact_id`` is
        the real user id used server-side only to find the number / device."""
        if channel not in CHANNEL_PROVIDER:
            raise ValueError(f"unknown channel {channel}")
        provider = CHANNEL_PROVIDER[channel]
        state = self.registry.status(provider)
        who = contact_id or user_ref or ""
        recipient = to or (who if channel == "push" else (self.contacts(who, channel) or ""))
        base = {"channel": channel, "provider": provider, "user_ref": user_ref, "event": event, "title": title,
                "body": body, "mode": state["mode"], "to_masked": mask(recipient)}
        if user_ref and not to and self.outbox.opted_out(user_ref, channel):
            return self.outbox.record(**base, status=OPTED_OUT)  # the customer's choice always wins
        if state["status"] == STATUS_MOCK:
            if not valid_recipient(channel, recipient):
                return self.outbox.record(**base, status=NO_CONTACT if not recipient else FAILED,
                                          error=None if not recipient else "invalid recipient")
            return self.outbox.record(**base, status=MOCK_DELIVERED, provider_ref="mock-" + uuid.uuid4().hex[:10])
        if state["status"] not in (STATUS_LIVE, STATUS_TEST):
            return self.outbox.record(**base, status=f"SKIPPED_{state['status']}")
        if not recipient:
            return self.outbox.record(**base, status=NO_CONTACT)
        if not valid_recipient(channel, recipient):
            return self.outbox.record(**base, status=FAILED, error="invalid recipient")
        attempts = 0
        while True:
            attempts += 1
            try:
                ok, ref, error = self._deliver(channel, recipient, title, body, contact_id or user_ref)
            except Exception as exc:  # a provider outage never breaks the caller
                ok, ref, error = False, "", f"{type(exc).__name__}"
            # One retry for transient failures (provider 5xx / rate limit / network).
            if ok or attempts >= 2 or not transient(error):
                break
        return self.outbox.record(**base, status=SENT if ok else FAILED, provider_ref=ref or None,
                                  error=error or None, attempts=attempts)


# ----------------------------------------------------------------- probes --
# Read-only live checks. (ok, detail) -- detail never contains secrets.

def probe_whatsapp(reg: IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    version = reg.config_value("whatsapp_cloud", "api_version") or DEFAULT_WHATSAPP_VERSION
    status, data = http("GET", f"https://graph.facebook.com/{version}/{reg.config_value('whatsapp_cloud', 'phone_number_id')}",
                        headers={"Authorization": f"Bearer {reg.secret('whatsapp_cloud', 'access_token')}"},
                        params={"fields": "display_phone_number,verified_name,quality_rating"})
    if status == 200 and isinstance(data, dict) and data.get("display_phone_number"):
        return True, f"number {mask(data['display_phone_number'])} ({data.get('verified_name') or 'unverified name'})"
    return False, f"HTTP {status}: {_error_text(data)}"


def probe_youtube(reg: IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    # videos.list costs 1 quota unit.
    status, data = http("GET", "https://www.googleapis.com/youtube/v3/videos",
                        params={"part": "id", "id": "dQw4w9WgXcQ", "key": reg.secret("youtube_data", "api_key")})
    if status == 200 and isinstance(data, dict) and data.get("items") is not None:
        return True, "YouTube Data API v3 answered (1 quota unit)"
    return False, f"HTTP {status}: {_error_text(data)}"


def probe_sms(reg: IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    if (reg.config_value("sms", "vendor") or "msg91").lower() == "twilio":
        sid = reg.config_value("sms", "account_sid")
        status, data = http("GET", f"https://api.twilio.com/2010-04-01/Accounts/{sid}.json",
                            auth=(sid, reg.secret("sms", "api_key")))
        if status == 200:
            return True, f"Twilio account {str((data or {}).get('status') or 'ok')}"
        return False, f"HTTP {status}: {_error_text(data)}"
    return False, "MSG91 has no read-only check here -- send a test SMS to your own number to verify"


def probe_email(reg: IntegrationRegistry, smtp_factory: Callable[..., Any] | None = None) -> Tuple[bool, str]:
    port = int(reg.config_value("email", "port") or 587)
    factory = smtp_factory or smtp_for(port)
    try:
        with factory(reg.config_value("email", "host"), port, timeout=15) as smtp:
            if port != 465:
                smtp.starttls()
            smtp.login(reg.config_value("email", "username") or reg.config_value("email", "from_address"),
                       reg.secret("email", "password"))
        return True, "SMTP login OK (no message sent)"
    except Exception as error:
        return False, f"{type(error).__name__}: {str(error)[:160]}"


def probe_push(push: Any) -> Tuple[bool, str]:
    if push is None or not getattr(push, "configured", False):
        return False, "service account JSON is missing or incomplete"
    token = push._access_token()
    return (True, "Firebase OAuth token obtained") if token else (False, "Firebase rejected the service account")


def probe_razorpay(reg: IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    status, data = http("GET", "https://api.razorpay.com/v1/payments", params={"count": 1},
                        auth=(reg.config_value("razorpay", "key_id"), reg.secret("razorpay", "key_secret")))
    if status == 200:
        return True, "Razorpay API keys accepted (read-only)"
    return False, f"HTTP {status}: {_error_text(data)}"


def default_probes(reg_http: Http, *, push: Any = None, smtp_factory: Callable[..., Any] | None = None
                   ) -> Dict[str, Callable[[IntegrationRegistry], Tuple[bool, str]]]:
    return {
        "whatsapp_cloud": lambda reg: probe_whatsapp(reg, reg_http),
        "youtube_data": lambda reg: probe_youtube(reg, reg_http),
        "sms": lambda reg: probe_sms(reg, reg_http),
        "email": lambda reg: probe_email(reg, smtp_factory),
        "fcm_push": lambda reg: probe_push(push),
        "razorpay": lambda reg: probe_razorpay(reg, reg_http),
        "meta_messaging": lambda reg: _lazy("social_dm", "probe_meta")(reg, reg_http),
        "amazon_associates": lambda reg: _lazy("marketplace_api", "probe_amazon")(reg, reg_http),
        "flipkart_affiliate": lambda reg: _lazy("marketplace_api", "probe_flipkart")(reg, reg_http),
    }


def _lazy(module: str, name: str):
    import importlib

    return getattr(importlib.import_module(f"app.services.{module}"), name)

