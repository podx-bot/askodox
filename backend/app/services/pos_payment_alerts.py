"""ASKODOX POS -- UPI payment voice alerts ("soundbox on the phone").

What this is
* The shop's own phone reads the incoming-payment notification of the shop's
  OWN payment app (PhonePe Business, Google Pay, Paytm, BHIM ...) through the
  Android notification-access permission the owner turns on, speaks it
  (Telugu by default) and reports a minimal event here.
* This server normalises, de-duplicates, keeps a short history, and fans the
  event out to the shop's other authorised devices (owner / staff).

What this is NOT
* ASKODOX never takes, initiates, collects, redirects or settles a payment.
* A notification is NOT a bank confirmation. Every event reported by a phone
  is stored as ``notification_unverified`` -- the client cannot set any other
  verification. ``provider_verified`` comes only from the shop's OWN connected
  payment provider (``pos_payment_providers``: signed webhook + the provider's
  API re-check), never from a phone.
* Unverified events are never revenue, never a payment against a bill and
  never touch ``pos_payments`` / the customer ledger.

Privacy / retention
* No notification text is ever sent or stored: only amount, source app,
  times, the last 4 characters of a transaction reference and a salted hash of
  the full reference (for de-duplication). No payer name, no phone, no OTP.
* Events older than ``RETENTION_DAYS`` are deleted.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import uuid
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import ROLES, PosError, PosStore

RETENTION_DAYS = 90
MAX_AMOUNT_PAISE = 10_000_000_00  # ₹1 crore: anything above is not a counter UPI alert
MAX_DELAY = timedelta(days=3)  # an event detected earlier than this (phone offline long) is refused
LANGUAGES = ("te", "hi", "en")
VOICES = ("female", "male")
# Package ids of payment apps whose incoming-payment notifications may be read. The owner can
# narrow this per shop; anything not listed is never read on the phone.
DEFAULT_APPS: Dict[str, str] = {
    "com.phonepe.app.business": "PhonePe Business",
    "com.phonepe.app": "PhonePe",
    "com.google.android.apps.nbu.paisa.merchant": "Google Pay for Business",
    "com.google.android.apps.nbu.paisa.user": "Google Pay",
    "com.paytm.business": "Paytm for Business",
    "net.one97.paytm": "Paytm",
    "in.org.npci.upiapp": "BHIM",
}
DEFAULT_ROLES = ("owner", "manager", "cashier")
# Bank / provider confirmation comes ONLY through pos_payment_providers (signed webhook + API re-check),
# which calls record_verified(). A phone can never mark an event verified.
VERIFIED_PROVIDERS: Dict[str, str] = {"razorpay": "Razorpay"}
EVENT_STATUSES = ("notification_unverified", "provider_verified", "ambiguous", "failed")
ACK_STATES = ("announced", "delivered", "quiet_hours", "muted", "tts_failed", "seen")
_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
_REF = re.compile(r"^[A-Za-z0-9]{4,40}$")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_alert_settings (business_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0,"
    " language TEXT NOT NULL DEFAULT 'te', voice TEXT NOT NULL DEFAULT 'female', rate_pct INTEGER NOT NULL DEFAULT 100,"
    " volume_pct INTEGER NOT NULL DEFAULT 100, quiet_start TEXT NOT NULL DEFAULT '', quiet_end TEXT NOT NULL DEFAULT '',"
    " roles TEXT NOT NULL, apps TEXT NOT NULL, updated_by TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_alert_devices (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, user_id TEXT NOT NULL,"
    " device_key TEXT NOT NULL, label TEXT NOT NULL DEFAULT '', listener_on INTEGER NOT NULL DEFAULT 0,"
    " speaks_remote INTEGER NOT NULL DEFAULT 1, alerts_on INTEGER NOT NULL DEFAULT 1, revoked INTEGER NOT NULL DEFAULT 0,"
    " last_seen_at TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE (business_id, user_id, device_key))",
    "CREATE TABLE IF NOT EXISTS pos_payment_events (id TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " fingerprint TEXT NOT NULL, amount_paise INTEGER, source_app TEXT NOT NULL, source_label TEXT NOT NULL,"
    " ref_tail TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, verification TEXT NOT NULL, reason TEXT NOT NULL DEFAULT '',"
    " detected_at TEXT NOT NULL, received_at TEXT NOT NULL, device_id TEXT, reported_by TEXT NOT NULL,"
    " test INTEGER NOT NULL DEFAULT 0, duplicates INTEGER NOT NULL DEFAULT 0, expires_at TEXT NOT NULL,"
    " UNIQUE (business_id, fingerprint))",
    "CREATE INDEX IF NOT EXISTS idx_pos_payment_events_biz ON pos_payment_events(business_id, received_at)",
    "CREATE TABLE IF NOT EXISTS pos_payment_acks (event_id TEXT NOT NULL, device_id TEXT NOT NULL, user_id TEXT NOT NULL,"
    " state TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY (event_id, device_id))",
]


def _hash(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:40]


def _parse_time(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        at = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return at if at.tzinfo else None


def announcement(amount_paise: Optional[int], language: str, verified: bool = False, test: bool = False) -> str:
    """The sentence a phone speaks. Unverified wording always asks the shop to check the bank."""
    if amount_paise is None:
        return {"te": "పేమెంట్ నోటిఫికేషన్ వచ్చింది, కానీ మొత్తం స్పష్టంగా లేదు. యాప్‌లో చూడండి.",
                "hi": "पेमेंट नोटिफिकेशन आया, पर रकम साफ़ नहीं है। ऐप में देखें।",
                "en": "A payment notification arrived but the amount is not clear. Please check the app."}.get(language, "")
    rupees, paise = divmod(int(amount_paise), 100)
    if language == "te":
        amount = f"{rupees} రూపాయల" + (f" {paise} పైసల" if paise else "")
        text = f"మీకు {amount.replace('రూపాయల', 'రూపాయలు')} అందాయి." if verified else \
            f"{amount} పేమెంట్ నోటిఫికేషన్ వచ్చింది. బ్యాంకులో నిర్ధారించుకోండి."
        return ("టెస్ట్. " + text) if test else text
    if language == "hi":
        amount = f"{rupees} रुपये" + (f" {paise} पैसे" if paise else "")
        text = f"आपको {amount} मिले।" if verified else f"{amount} का पेमेंट नोटिफिकेशन आया है। बैंक में पक्का कर लें।"
        return ("टेस्ट। " + text) if test else text
    amount = f"{rupees} rupees" + (f" {paise} paise" if paise else "")
    text = f"You received {amount}." if verified else f"Payment notification of {amount} received. Please confirm in your bank."
    return ("Test. " + text) if test else text


class PosPaymentAlerts:
    def __init__(self, store: PosStore,
                 notify: Optional[Callable[[str, str, str, str, str], None]] = None,
                 feature_on: Optional[Callable[[], bool]] = None) -> None:
        self.store = store
        # notify(user_id, title, body, route, event_key) -- best effort, never raises into the caller.
        self.notify = notify or (lambda *args: None)
        self.feature_on = feature_on or (lambda: True)
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------- helpers
    def _now(self) -> datetime:
        return self.store.clock()

    def _settings_row(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_alert_settings WHERE business_id = ?", (business_id,)).fetchone()
        if row is None:
            return {"enabled": False, "language": "te", "voice": "female", "rate_pct": 100, "volume_pct": 100,
                    "quiet_start": "", "quiet_end": "", "roles": list(DEFAULT_ROLES), "apps": dict(DEFAULT_APPS),
                    "updated_at": None}
        return {"enabled": bool(row["enabled"]), "language": row["language"], "voice": row["voice"],
                "rate_pct": row["rate_pct"], "volume_pct": row["volume_pct"], "quiet_start": row["quiet_start"],
                "quiet_end": row["quiet_end"], "roles": json.loads(row["roles"]), "apps": json.loads(row["apps"]),
                "updated_at": row["updated_at"]}

    def _member(self, conn: sqlite3.Connection, business_id: str, user: str) -> str:
        """The caller's role, or 404 (not a member) / 403 (role not allowed to see payment alerts)."""
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        settings = self._settings_row(conn, business_id)
        if role != "owner" and role not in settings["roles"]:
            raise PosError(403, "payment_alerts", "The owner has not allowed your role to see payment alerts.")
        return role

    def _require_feature(self) -> None:
        if not self.feature_on():
            raise PosError(503, "feature_disabled", "Payment voice alerts are switched off by ASKODOX for now.")

    def _purge(self, conn: sqlite3.Connection) -> None:
        conn.execute("DELETE FROM pos_payment_acks WHERE event_id IN (SELECT id FROM pos_payment_events WHERE expires_at < ?)",
                     (self._now().isoformat(),))
        conn.execute("DELETE FROM pos_payment_events WHERE expires_at < ?", (self._now().isoformat(),))

    # ------------------------------------------------------------ settings
    def settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            role = self._member(conn, business_id, user)
            out = self._settings_row(conn, business_id)
        out.update({"my_role": role, "feature_on": self.feature_on(), "can_edit": role == "owner",
                    "all_roles": [r for r in ROLES if r != "owner"],
                    "verified_provider": self._provider_connected(business_id)})
        return out

    def update_settings(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            if self.store.role_of(conn, business_id, user) != "owner":
                raise PosError(403, "owner_only", "Only the shop owner can change payment alert settings.")
            cur = self._settings_row(conn, business_id)
            if "enabled" in data and data["enabled"] is not None:
                cur["enabled"] = bool(data["enabled"])
            if data.get("language") is not None:
                if data["language"] not in LANGUAGES:
                    raise PosError(400, "language", "language must be te, hi or en.")
                cur["language"] = data["language"]
            if data.get("voice") is not None:
                if data["voice"] not in VOICES:
                    raise PosError(400, "voice", "voice must be female or male.")
                cur["voice"] = data["voice"]
            for key, low, high in (("rate_pct", 50, 200), ("volume_pct", 10, 100)):
                if data.get(key) is not None:
                    value = int(data[key])
                    if not low <= value <= high:
                        raise PosError(400, key, f"{key} must be between {low} and {high}.")
                    cur[key] = value
            for key in ("quiet_start", "quiet_end"):
                if data.get(key) is not None:
                    value = str(data[key]).strip()
                    if value and not _TIME.match(value):
                        raise PosError(400, key, f"{key} must look like 22:00 (or be empty).")
                    cur[key] = value
            if bool(cur["quiet_start"]) != bool(cur["quiet_end"]):
                raise PosError(400, "quiet_hours", "Give both a quiet-hours start and end, or neither.")
            if data.get("roles") is not None:
                roles = [r for r in dict.fromkeys(str(x) for x in data["roles"]) if r in ROLES and r != "owner"]
                cur["roles"] = roles
            if data.get("apps") is not None:
                apps = data["apps"]
                if not isinstance(apps, dict) or not apps or len(apps) > 20:
                    raise PosError(400, "apps", "Choose 1-20 payment apps.")
                clean: Dict[str, str] = {}
                for pkg, label in apps.items():
                    pkg = str(pkg).strip()
                    if not re.match(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$", pkg) or len(pkg) > 120:
                        raise PosError(400, "apps", f"'{pkg}' is not an Android package id.")
                    clean[pkg] = str(label or pkg).strip()[:40]
                cur["apps"] = clean
            now = self._now().isoformat()
            conn.execute(
                "INSERT INTO pos_alert_settings (business_id, enabled, language, voice, rate_pct, volume_pct, quiet_start,"
                " quiet_end, roles, apps, updated_by, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"
                " ON CONFLICT(business_id) DO UPDATE SET enabled=excluded.enabled, language=excluded.language,"
                " voice=excluded.voice, rate_pct=excluded.rate_pct, volume_pct=excluded.volume_pct,"
                " quiet_start=excluded.quiet_start, quiet_end=excluded.quiet_end, roles=excluded.roles,"
                " apps=excluded.apps, updated_by=excluded.updated_by, updated_at=excluded.updated_at",
                (business_id, int(cur["enabled"]), cur["language"], cur["voice"], cur["rate_pct"], cur["volume_pct"],
                 cur["quiet_start"], cur["quiet_end"], json.dumps(cur["roles"]), json.dumps(cur["apps"]), user, now))
            self.store._audit(conn, business_id, user, "payment_alerts.settings", business_id,
                              {k: cur[k] for k in ("enabled", "language", "roles")}, now)
        return self.settings(business_id, user)

    def _provider_connected(self, business_id: str) -> bool:
        try:
            with self.store._connect() as conn:
                return conn.execute("SELECT 1 FROM pos_provider_accounts WHERE business_id = ? AND active = 1",
                                    (business_id,)).fetchone() is not None
        except sqlite3.OperationalError:
            return False

    def record_verified(self, business_id: str, *, provider: str, label: str, amount_paise: int, payment_id: str,
                        reference: str, detected_at: Optional[datetime] = None, test: bool = False) -> Dict[str, Any]:
        """Called ONLY by pos_payment_providers after a signed webhook + the provider's own API confirmed it."""
        if provider not in VERIFIED_PROVIDERS:
            raise PosError(400, "provider", "Unknown provider.")
        now = self._now()
        detected = detected_at or now
        with self.store._tx() as conn:
            settings = self._settings_row(conn, business_id)
            self._purge(conn)
            fingerprint = _hash(business_id, "provider", provider, payment_id)
            existing = conn.execute("SELECT * FROM pos_payment_events WHERE business_id = ? AND fingerprint = ?",
                                    (business_id, fingerprint)).fetchone()
            if existing is not None:
                conn.execute("UPDATE pos_payment_events SET duplicates = duplicates + 1 WHERE id = ?", (existing["id"],))
                event = self._event_out(conn, existing, "")
                event["duplicate"] = True
                return event
            event_id = f"ppe_{uuid.uuid4().hex[:20]}"
            ref = re.sub(r"[^A-Za-z0-9]", "", reference or "")
            conn.execute(
                "INSERT INTO pos_payment_events (id, business_id, fingerprint, amount_paise, source_app, source_label,"
                " ref_tail, status, verification, reason, detected_at, received_at, device_id, reported_by, test,"
                " expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (event_id, business_id, fingerprint, int(amount_paise), f"provider.{provider}", label, ref[-4:],
                 "provider_verified", f"provider:{provider}", "", detected.isoformat(), now.isoformat(), None,
                 f"provider:{provider}", int(test), (now + timedelta(days=RETENTION_DAYS)).isoformat()))
            row = conn.execute("SELECT * FROM pos_payment_events WHERE id = ?", (event_id,)).fetchone()
            event = self._event_out(conn, row, "")
            receivers = self._receivers(conn, business_id, settings, exclude="")
            shop = self.store._business_row(conn, business_id)["name"]
        event["duplicate"] = False
        if self.feature_on() and (settings["enabled"] or test):
            title = f"{shop}: payment received ({label})" + (" (test)" if test else "")
            body = announcement(int(amount_paise), settings["language"], verified=True, test=test)
            for receiver in receivers:
                try:
                    self.notify(receiver, title, body, f"/pos/{business_id}/payment-alerts", f"payalert:{event_id}")
                except Exception:
                    pass
        return event

    # ------------------------------------------------------------- devices
    def register_device(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        device_key = str(data.get("device_key") or "").strip()
        if not re.match(r"^[A-Za-z0-9_.:-]{8,80}$", device_key):
            raise PosError(400, "device_key", "device_key must be 8-80 letters / digits.")
        now = self._now().isoformat()
        with self.store._tx() as conn:
            self._member(conn, business_id, user)
            row = conn.execute("SELECT id FROM pos_alert_devices WHERE business_id = ? AND user_id = ? AND device_key = ?",
                               (business_id, user, device_key)).fetchone()
            fields = (str(data.get("label") or "")[:60], int(bool(data.get("listener_on"))),
                      int(data.get("speaks_remote", True) is not False), int(data.get("alerts_on", True) is not False))
            if row is None:
                device_id = f"pad_{uuid.uuid4().hex[:20]}"
                conn.execute("INSERT INTO pos_alert_devices (id, business_id, user_id, device_key, label, listener_on,"
                             " speaks_remote, alerts_on, last_seen_at, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                             (device_id, business_id, user, device_key, *fields, now, now))
                self.store._audit(conn, business_id, user, "payment_alerts.device", device_id, {"label": fields[0]}, now)
            else:
                device_id = row["id"]
                conn.execute("UPDATE pos_alert_devices SET label = ?, listener_on = ?, speaks_remote = ?, alerts_on = ?,"
                             " last_seen_at = ?, revoked = 0 WHERE id = ?", (*fields, now, device_id))
        return {"device_id": device_id, "devices": self.devices(business_id, user)}

    def devices(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            role = self._member(conn, business_id, user)
            rows = conn.execute("SELECT * FROM pos_alert_devices WHERE business_id = ? ORDER BY created_at",
                                (business_id,)).fetchall()
            roles = {r["user_id"]: r["role"] for r in conn.execute(
                "SELECT app_user_id AS user_id, role FROM pos_members WHERE business_id = ? AND active = 1",
                (business_id,)) if r["user_id"]}
            owner = self.store._business_row(conn, business_id)["owner_user_id"]
        out = []
        for r in rows:
            if role not in ("owner", "manager") and r["user_id"] != user:
                continue  # staff see only their own devices
            out.append({"id": r["id"], "label": r["label"], "mine": r["user_id"] == user,
                        "role": "owner" if r["user_id"] == owner else roles.get(r["user_id"], "removed"),
                        "listener_on": bool(r["listener_on"]), "speaks_remote": bool(r["speaks_remote"]),
                        "alerts_on": bool(r["alerts_on"]), "revoked": bool(r["revoked"]),
                        "last_seen_at": r["last_seen_at"]})
        return out

    def revoke_device(self, business_id: str, user: str, device_id: str) -> List[Dict[str, Any]]:
        with self.store._tx() as conn:
            role = self._member(conn, business_id, user)
            row = conn.execute("SELECT user_id FROM pos_alert_devices WHERE id = ? AND business_id = ?",
                               (device_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "device", "Device not found.")
            if role != "owner" and row["user_id"] != user:
                raise PosError(403, "owner_only", "Only the owner can remove another person's device.")
            now = self._now().isoformat()
            conn.execute("UPDATE pos_alert_devices SET revoked = 1, alerts_on = 0 WHERE id = ?", (device_id,))
            self.store._audit(conn, business_id, user, "payment_alerts.revoke", device_id, {}, now)
        return self.devices(business_id, user)

    def _device(self, conn: sqlite3.Connection, business_id: str, user: str, device_id: Optional[str]) -> Optional[str]:
        if not device_id:
            return None
        row = conn.execute("SELECT user_id, revoked FROM pos_alert_devices WHERE id = ? AND business_id = ?",
                           (device_id, business_id)).fetchone()
        if row is None or row["user_id"] != user:
            raise PosError(403, "device", "This device is not registered to you for this shop.")
        if row["revoked"]:
            raise PosError(403, "device_revoked", "This device was removed from the shop's payment alerts.")
        conn.execute("UPDATE pos_alert_devices SET last_seen_at = ? WHERE id = ?", (self._now().isoformat(), device_id))
        return device_id

    # -------------------------------------------------------------- events
    def report(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A phone reports one detected notification. Idempotent: the same payment twice -> duplicate."""
        self._require_feature()
        if data.get("verification") not in (None, "", "notification_only") or data.get("status") == "provider_verified":
            raise PosError(400, "verification", "A phone can only report a notification. Bank / provider verification "
                                                "comes only from a connected provider (none is connected).")
        test = bool(data.get("test"))
        source = str(data.get("source_app") or "").strip()
        client_event_id = str(data.get("client_event_id") or "").strip()
        if not re.match(r"^[A-Za-z0-9_.:|-]{8,120}$", client_event_id):
            raise PosError(400, "client_event_id", "client_event_id must be 8-120 characters.")
        amount = data.get("amount_paise")
        if amount is not None:
            amount = int(amount)
            if amount <= 0 or amount > MAX_AMOUNT_PAISE:
                raise PosError(400, "amount", "Amount is out of range.")
        ref = str(data.get("reference") or "").strip()
        if ref and not _REF.match(ref):
            ref = ""  # malformed reference: ignored, never stored
        now = self._now()
        detected = _parse_time(data.get("detected_at")) or now
        if detected > now + timedelta(minutes=10):
            raise PosError(400, "detected_at", "detected_at is in the future.")
        if now - detected > MAX_DELAY:
            raise PosError(400, "too_old", "This notification is too old to announce.")
        with self.store._tx() as conn:
            self._member(conn, business_id, user)
            settings = self._settings_row(conn, business_id)
            if not settings["enabled"] and not test:
                raise PosError(409, "not_enabled", "Payment alerts are not turned on for this shop.")
            if test:
                source, label = "askodox.test", "ASKODOX test"
            else:
                if source not in settings["apps"]:
                    raise PosError(400, "unsupported_app", "This payment app is not in the shop's allowed list.")
                label = settings["apps"][source]
            device_id = self._device(conn, business_id, user, data.get("device_id"))
            self._purge(conn)
            # Same payment = same reference in the same app; without a reference, the phone's own event id.
            fingerprint = _hash(business_id, source, "ref", ref) if ref else _hash(business_id, source, "evt", client_event_id)
            existing = conn.execute("SELECT * FROM pos_payment_events WHERE business_id = ? AND fingerprint = ?",
                                    (business_id, fingerprint)).fetchone()
            if existing is not None:
                conn.execute("UPDATE pos_payment_events SET duplicates = duplicates + 1 WHERE id = ?", (existing["id"],))
                event = self._event_out(conn, existing, user)
                event["duplicate"] = True
                return event
            status = "notification_unverified" if amount is not None else "ambiguous"
            reason = "" if amount is not None else str(data.get("reason") or "amount_missing")[:40]
            event_id = f"ppe_{uuid.uuid4().hex[:20]}"
            conn.execute(
                "INSERT INTO pos_payment_events (id, business_id, fingerprint, amount_paise, source_app, source_label,"
                " ref_tail, status, verification, reason, detected_at, received_at, device_id, reported_by, test,"
                " expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (event_id, business_id, fingerprint, amount, source, label, ref[-4:] if ref else "", status,
                 "notification_only", reason, detected.isoformat(), now.isoformat(), device_id, user, int(test),
                 (now + timedelta(days=RETENTION_DAYS)).isoformat()))
            if device_id and data.get("spoken"):
                spoken = str(data["spoken"])
                if spoken in ACK_STATES:
                    conn.execute("INSERT OR REPLACE INTO pos_payment_acks (event_id, device_id, user_id, state, at)"
                                 " VALUES (?,?,?,?,?)", (event_id, device_id, user, spoken, now.isoformat()))
            row = conn.execute("SELECT * FROM pos_payment_events WHERE id = ?", (event_id,)).fetchone()
            event = self._event_out(conn, row, user)
            receivers = self._receivers(conn, business_id, settings, exclude=user)
            shop = self.store._business_row(conn, business_id)["name"]
        event["duplicate"] = False
        title = f"{shop}: payment notification" + (" (test)" if test else "")
        body = announcement(amount, settings["language"], test=test)
        for receiver in receivers:
            try:
                self.notify(receiver, title, body, f"/pos/{business_id}/payment-alerts", f"payalert:{event_id}")
            except Exception:
                pass  # a push failure never fails the report; the feed still has it
        return event

    def _receivers(self, conn: sqlite3.Connection, business_id: str, settings: Dict[str, Any], exclude: str) -> List[str]:
        owner = self.store._business_row(conn, business_id)["owner_user_id"]
        allowed = {owner}
        for r in conn.execute("SELECT app_user_id, role FROM pos_members WHERE business_id = ? AND active = 1",
                              (business_id,)):
            if r["app_user_id"] and r["role"] in settings["roles"]:
                allowed.add(r["app_user_id"])
        with_devices = {r["user_id"] for r in conn.execute(
            "SELECT DISTINCT user_id FROM pos_alert_devices WHERE business_id = ? AND revoked = 0 AND alerts_on = 1",
            (business_id,))}
        return sorted(u for u in allowed & with_devices if u != exclude)

    def _event_out(self, conn: sqlite3.Connection, row: sqlite3.Row, user: str) -> Dict[str, Any]:
        acks = conn.execute("SELECT a.device_id, a.state, a.at, d.label, d.user_id FROM pos_payment_acks a"
                            " LEFT JOIN pos_alert_devices d ON d.id = a.device_id WHERE a.event_id = ?",
                            (row["id"],)).fetchall()
        reporter = conn.execute("SELECT label FROM pos_alert_devices WHERE id = ?", (row["device_id"],)).fetchone() \
            if row["device_id"] else None
        active = {r["id"] for r in conn.execute(
            "SELECT id FROM pos_alert_devices WHERE business_id = ? AND revoked = 0 AND alerts_on = 1",
            (row["business_id"],))}
        acked = {a["device_id"] for a in acks}
        expired = _parse_time(row["expires_at"]) is not None and _parse_time(row["expires_at"]) < self._now()
        return {
            "id": row["id"], "amount_paise": row["amount_paise"], "source_app": row["source_app"],
            "source_label": row["source_label"], "reference_tail": row["ref_tail"], "status": row["status"],
            "verification": row["verification"], "verified": row["status"] == "provider_verified",
            "reason": row["reason"], "detected_at": row["detected_at"], "received_at": row["received_at"],
            "receiving_device": reporter["label"] if reporter else "", "reported_by_me": row["reported_by"] == user,
            "test": bool(row["test"]), "duplicates": row["duplicates"], "expired": expired,
            "acks": [{"device": a["label"] or "", "mine": a["user_id"] == user, "state": a["state"], "at": a["at"]}
                     for a in acks],
            "delivery_pending": len(active - acked),
            "announcement": {lang: announcement(row["amount_paise"], lang, verified=row["status"] == "provider_verified",
                                                test=bool(row["test"])) for lang in LANGUAGES},
        }

    def events(self, business_id: str, user: str, *, status: str = "", q: str = "", since: str = "",
               include_test: bool = True, limit: int = 100) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._member(conn, business_id, user)
            self._purge(conn)
            sql, args = "SELECT * FROM pos_payment_events WHERE business_id = ?", [business_id]
            if status:
                if status not in EVENT_STATUSES + ("duplicate",):
                    raise PosError(400, "status", "Unknown status.")
                if status == "duplicate":
                    sql += " AND duplicates > 0"
                else:
                    sql += " AND status = ?"
                    args.append(status)
            if since:
                sql += " AND received_at > ?"
                args.append(since)
            if not include_test:
                sql += " AND test = 0"
            q = q.strip()
            if q:
                digits = re.sub(r"[^0-9.]", "", q)
                clauses, extra = ["source_label LIKE ?", "ref_tail LIKE ?"], [f"%{q}%", f"%{q}%"]
                if digits:
                    try:
                        clauses.append("amount_paise = ?")
                        extra.append(int(round(float(digits) * 100)))
                    except ValueError:
                        pass
                sql += " AND (" + " OR ".join(clauses) + ")"
                args.extend(extra)
            sql += " ORDER BY received_at DESC LIMIT ?"
            args.append(max(1, min(int(limit), 500)))
            rows = conn.execute(sql, args).fetchall()
            items = [self._event_out(conn, r, user) for r in rows]
            today = self.store._local(self._now())
            verified = conn.execute(
                "SELECT COUNT(*) AS n, COALESCE(SUM(amount_paise), 0) AS total FROM pos_payment_events"
                " WHERE business_id = ? AND test = 0 AND status = 'provider_verified' AND received_at >= ?",
                (business_id, (self._now() - timedelta(hours=24)).isoformat())).fetchone()
            counts = conn.execute(
                "SELECT COUNT(*) AS n, COALESCE(SUM(amount_paise), 0) AS total FROM pos_payment_events"
                " WHERE business_id = ? AND test = 0 AND status = 'notification_unverified' AND received_at >= ?",
                (business_id, (self._now() - timedelta(hours=24)).isoformat())).fetchone()
        return {"events": items, "today": today,
                "last_24h": {"count": counts["n"], "notified_total_paise": counts["total"],
                             "verified_count": verified["n"], "verified_total_paise": verified["total"],
                             "note": "Notification totals are not bank-verified and not revenue; verified totals come "
                                     "from the shop's connected payment provider."}}

    def ack(self, business_id: str, user: str, event_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        state = str(data.get("state") or "")
        if state not in ACK_STATES:
            raise PosError(400, "state", "Unknown acknowledgement state.")
        with self.store._tx() as conn:
            self._member(conn, business_id, user)
            device_id = self._device(conn, business_id, user, data.get("device_id"))
            if device_id is None:
                raise PosError(400, "device_id", "device_id is required.")
            row = conn.execute("SELECT * FROM pos_payment_events WHERE id = ? AND business_id = ?",
                               (event_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "event", "Event not found.")
            conn.execute("INSERT OR REPLACE INTO pos_payment_acks (event_id, device_id, user_id, state, at)"
                         " VALUES (?,?,?,?,?)", (event_id, device_id, user, state, self._now().isoformat()))
            return self._event_out(conn, row, user)

    def export_csv(self, business_id: str, user: str) -> str:
        data = self.events(business_id, user, limit=500)
        lines = ["detected_at,amount_rupees,source,reference_last4,status,verification,test,duplicates"]
        for e in data["events"]:
            amount = "" if e["amount_paise"] is None else f"{e['amount_paise'] / 100:.2f}"
            lines.append(",".join([e["detected_at"], amount, e["source_label"].replace(",", " "), e["reference_tail"],
                                   e["status"], e["verification"], str(int(e["test"])), str(e["duplicates"])]))
        lines.append("# Notifications only. Not bank-verified. Not revenue or settled collections.")
        return "\n".join(lines) + "\n"

    # --------------------------------------------------------------- admin
    def admin_summary(self) -> Dict[str, Any]:
        since = (self._now() - timedelta(hours=24)).isoformat()
        with self.store._connect() as conn:
            def one(sql: str, *args: Any) -> int:
                return int(conn.execute(sql, args).fetchone()[0] or 0)

            return {
                "feature_on": self.feature_on(),
                "shops_enabled": one("SELECT COUNT(*) FROM pos_alert_settings WHERE enabled = 1"),
                "devices_active": one("SELECT COUNT(*) FROM pos_alert_devices WHERE revoked = 0"),
                "devices_listening": one("SELECT COUNT(*) FROM pos_alert_devices WHERE revoked = 0 AND listener_on = 1"),
                "events_24h": one("SELECT COUNT(*) FROM pos_payment_events WHERE received_at >= ? AND test = 0", since),
                "test_events_24h": one("SELECT COUNT(*) FROM pos_payment_events WHERE received_at >= ? AND test = 1", since),
                "ambiguous_24h": one("SELECT COUNT(*) FROM pos_payment_events WHERE received_at >= ? AND status = 'ambiguous'",
                                     since),
                "duplicates_24h": one("SELECT COALESCE(SUM(duplicates), 0) FROM pos_payment_events WHERE received_at >= ?",
                                      since),
                "acks_24h": one("SELECT COUNT(*) FROM pos_payment_acks WHERE at >= ?", since),
                "verified_providers": list(VERIFIED_PROVIDERS),
                "supported_apps": DEFAULT_APPS,
            }
