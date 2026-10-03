"""Affiliate / Partner Hub and the Revenue Center ledger (one repository).

- partners            universal partner registry (any company, any category;
                      nothing is hard-coded per company)
- partner_secrets     API keys / postback tokens -- backend only, never
                      returned by any API (only "set / not set" + last 4)
- revenue_events      measured funnel: search, impression, card_view, click,
                      partner_opened, lead, error (one row per event)
- partner_conversions orders/commissions reported by a partner (postback),
                      a report import or a manual reconciliation; states
                      PENDING -> CONFIRMED -> PAID | REJECTED | REVERSED
- revenue_entries     every other ASKODOX revenue source (subscription
                      payments, lead/service fees, promotions, transaction
                      fees, partner revenue ...) recorded as real entries

Nothing is estimated into these tables: a commission computed from the
partner's commission rule is stored with commission_source='rule' (shown as
"expected"), never as a confirmed amount. Dependency-free (sqlite3).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional
from zoneinfo import ZoneInfo

from app.services.secret_box import SecretBox

CONVERSION_STATES = ("PENDING", "CONFIRMED", "PAID", "REJECTED", "REVERSED")
FUNNEL_EVENTS = ("search", "impression", "card_view", "click", "partner_opened", "lead")
# Offers & rewards (benefits) funnel: campaign = "benefit:<id>".
BENEFIT_EVENTS = ("offer_impression", "offer_open", "offer_claim")
EVENTS = FUNNEL_EVENTS + ("error",) + BENEFIT_EVENTS
# Counted at most once per ASKODOX click id (replay / double-tap / reload).
ONCE_PER_CLICK = ("card_view", "click", "partner_opened", "lead")
ROLLUP_TZ = "Asia/Kolkata"  # roll-up days match the Revenue Center's default time zone
REVENUE_SOURCES = (
    "affiliate_commission", "subscription", "lead_fee", "service_fee", "promotion", "advertising",
    "transaction_fee", "partner_revenue", "other",
)
SECRET_NAMES = ("api_key", "api_secret", "feed_token", "postback_token")

# Partner fields an admin edits (non-secret).
PARTNER_FIELDS = (
    "name", "logo_url", "categories", "countries", "locations", "signup_url", "apply_instructions",
    "link_instructions", "base_url", "deep_link_template", "tracking_id", "sub_id_param",
    "campaign_params", "feed", "webhook_notes", "commission", "attribution_notes", "notes", "active",
)
_JSON_FIELDS = {"categories": [], "countries": [], "locations": [], "campaign_params": {}, "feed": {}, "commission": {}}

# Status words partners use -> ASKODOX conversion state.
_STATUS_WORDS = {
    "pending": "PENDING", "open": "PENDING", "new": "PENDING", "processing": "PENDING",
    "approved": "CONFIRMED", "confirmed": "CONFIRMED", "valid": "CONFIRMED", "accepted": "CONFIRMED",
    "paid": "PAID", "settled": "PAID",
    "rejected": "REJECTED", "declined": "REJECTED", "invalid": "REJECTED", "cancelled": "REJECTED",
    "canceled": "REJECTED",
    "reversed": "REVERSED", "returned": "REVERSED", "refunded": "REVERSED", "chargeback": "REVERSED",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _loads(raw: Any, default: Any) -> Any:
    try:
        return json.loads(raw) if raw else default
    except (TypeError, ValueError):
        return default


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", str(value or "").casefold()).strip("-")
    return slug[:48] or "partner"


def normalize_status(value: Any) -> str:
    word = str(value or "").strip()
    if word.upper() in CONVERSION_STATES:
        return word.upper()
    return _STATUS_WORDS.get(word.casefold(), "PENDING")


def capabilities(partner: Dict[str, Any], secret_names: Iterable[str]) -> Dict[str, Any]:
    """What ASKODOX can actually do / measure with this partner's config.

    Level 1: affiliate / deep link only       -> impressions, clicks, opens
    Level 2: product/feed API                 -> real product rows
    Level 3: conversion API / postback        -> leads, orders, commission
    Level 4: report import / manual           -> always available fallback
    """
    names = set(secret_names)
    link = bool(partner.get("deep_link_template") or partner.get("base_url"))
    feed = bool((partner.get("feed") or {}).get("url"))
    postback = "postback_token" in names
    measurable = ["impressions", "clicks", "partner_opened"] if link else []
    if postback:
        measurable += ["leads", "orders", "order_value", "commission"]
    return {
        "level1_link": link,
        "level2_feed": feed,
        "level3_postback": postback,
        "level4_import": True,
        "highest_level": 3 if postback else 2 if feed else 1 if link else 0,
        "measurable": measurable,
        "not_measurable": [] if postback else [
            "leads", "orders", "order_value", "commission (until postback is set up or a partner report is imported)",
        ],
    }


class PartnerRevenueRepository:
    def __init__(self, db_path: str = "podx.db", *, secret_box: SecretBox | None = None, click_key: str = "",
                 click_ttl_hours: int = 48) -> None:
        self.db_path = db_path
        self.box = secret_box or SecretBox()
        # Click ids are HMAC-signed so only ids ASKODOX issued are accepted.
        self._click_key = (click_key or "askodox-click-ids").encode()
        self.click_ttl_hours = max(1, int(click_ttl_hours or 48))
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS partners (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL, logo_url TEXT,
                    categories_json TEXT NOT NULL DEFAULT '[]', countries_json TEXT NOT NULL DEFAULT '[]',
                    locations_json TEXT NOT NULL DEFAULT '[]',
                    signup_url TEXT, apply_instructions TEXT, link_instructions TEXT,
                    base_url TEXT, deep_link_template TEXT, tracking_id TEXT, sub_id_param TEXT,
                    campaign_params_json TEXT NOT NULL DEFAULT '{}', feed_json TEXT NOT NULL DEFAULT '{}',
                    webhook_notes TEXT, commission_json TEXT NOT NULL DEFAULT '{}', attribution_notes TEXT,
                    notes TEXT, active INTEGER NOT NULL DEFAULT 0,
                    last_check_at TEXT, last_check_ok INTEGER, last_check_json TEXT,
                    last_sync_at TEXT, last_error TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS partner_secrets (
                    partner_id INTEGER NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL,
                    updated_at TEXT NOT NULL, PRIMARY KEY (partner_id, name)
                );
                CREATE TABLE IF NOT EXISTS revenue_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    occurred_at TEXT NOT NULL, event TEXT NOT NULL, partner_id INTEGER,
                    click_id TEXT, trace_key TEXT, category TEXT, subject TEXT, location TEXT,
                    language TEXT, campaign TEXT, detail_json TEXT NOT NULL DEFAULT '{}'
                );
                CREATE INDEX IF NOT EXISTS idx_revenue_events_time ON revenue_events(occurred_at);
                CREATE INDEX IF NOT EXISTS idx_revenue_events_click ON revenue_events(click_id);
                CREATE TABLE IF NOT EXISTS partner_conversions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    partner_id INTEGER NOT NULL, external_id TEXT NOT NULL, click_id TEXT,
                    order_value REAL, currency TEXT NOT NULL DEFAULT 'INR',
                    commission REAL, commission_source TEXT NOT NULL DEFAULT 'partner',
                    status TEXT NOT NULL, category TEXT, location TEXT, campaign TEXT, language TEXT,
                    source TEXT NOT NULL, occurred_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    raw_json TEXT NOT NULL DEFAULT '{}',
                    UNIQUE(partner_id, external_id)
                );
                CREATE INDEX IF NOT EXISTS idx_partner_conversions_time ON partner_conversions(occurred_at);
                CREATE TABLE IF NOT EXISTS revenue_entries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL DEFAULT 'INR',
                    occurred_at TEXT NOT NULL, partner_id INTEGER, category TEXT, location TEXT,
                    campaign TEXT, reference TEXT, note TEXT, created_by TEXT, created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_revenue_entries_time ON revenue_entries(occurred_at);
                CREATE TABLE IF NOT EXISTS revenue_daily_rollup (
                    day TEXT NOT NULL, event TEXT NOT NULL, partner_id INTEGER NOT NULL DEFAULT 0,
                    category TEXT NOT NULL DEFAULT '', location TEXT NOT NULL DEFAULT '',
                    language TEXT NOT NULL DEFAULT '', campaign TEXT NOT NULL DEFAULT '',
                    count INTEGER NOT NULL,
                    PRIMARY KEY (day, event, partner_id, category, location, language, campaign)
                );
                CREATE TABLE IF NOT EXISTS revenue_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """
            )
            try:  # database-level guarantee on top of the app-level check
                conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS uq_revenue_events_once ON revenue_events(click_id, event) "
                    "WHERE click_id IS NOT NULL AND event IN ('card_view', 'click', 'partner_opened', 'lead')"
                )
            except sqlite3.Error:
                pass  # older rows with duplicates: the app-level check still applies

    # ---------------------------------------------------------- partners --

    def _partner_row(self, row: sqlite3.Row | None, conn) -> Optional[Dict[str, Any]]:
        if row is None:
            return None
        item = dict(row)
        for field, default in _JSON_FIELDS.items():
            item[field] = _loads(item.pop(f"{field}_json", None), default)
        item["active"] = bool(item["active"])
        item["last_check_ok"] = None if item["last_check_ok"] is None else bool(item["last_check_ok"])
        item["last_check"] = _loads(item.pop("last_check_json", None), {})
        secret_rows = conn.execute(
            "SELECT name, value, updated_at FROM partner_secrets WHERE partner_id = ?", (item["id"],)
        ).fetchall()
        # Secrets never leave the backend: only whether each one is set and
        # encrypted at rest (no characters of the value, not even the last 4).
        item["secrets"] = {
            r["name"]: {"set": True, "encrypted": str(r["value"]).startswith("enc:v1:"), "updated_at": r["updated_at"]}
            for r in secret_rows
        }
        item["capabilities"] = capabilities(item, item["secrets"].keys())
        return item

    def _values(self, data: Dict[str, Any]) -> Dict[str, Any]:
        values: Dict[str, Any] = {}
        for field in PARTNER_FIELDS:
            if field not in data:
                continue
            value = data[field]
            if field in _JSON_FIELDS:
                values[f"{field}_json"] = json.dumps(value if value is not None else _JSON_FIELDS[field])
            elif field == "active":
                values["active"] = 1 if value else 0
            else:
                values[field] = (str(value).strip() or None) if value is not None else None
        return values

    def create_partner(self, data: Dict[str, Any]) -> Dict[str, Any]:
        now = _now()
        values = self._values(data)
        values.setdefault("active", 0)
        base = slugify(data.get("slug") or data.get("name"))
        with self._connect() as conn:
            slug, n = base, 2
            while conn.execute("SELECT 1 FROM partners WHERE slug = ?", (slug,)).fetchone():
                slug, n = f"{base}-{n}", n + 1
            values.update(slug=slug, created_at=now, updated_at=now)
            cols = ", ".join(values)
            cursor = conn.execute(
                f"INSERT INTO partners ({cols}) VALUES ({', '.join('?' for _ in values)})", tuple(values.values())
            )
            return self._partner_row(conn.execute("SELECT * FROM partners WHERE id = ?", (cursor.lastrowid,)).fetchone(), conn)

    def update_partner(self, partner_id: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        values = self._values(data)
        with self._connect() as conn:
            if values:
                values["updated_at"] = _now()
                conn.execute(
                    f"UPDATE partners SET {', '.join(f'{k} = ?' for k in values)} WHERE id = ?",
                    (*values.values(), partner_id),
                )
            return self._partner_row(conn.execute("SELECT * FROM partners WHERE id = ?", (partner_id,)).fetchone(), conn)

    def get_partner(self, partner_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            return self._partner_row(conn.execute("SELECT * FROM partners WHERE id = ?", (partner_id,)).fetchone(), conn)

    def partner_by_slug(self, slug: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            return self._partner_row(conn.execute("SELECT * FROM partners WHERE slug = ?", (slug,)).fetchone(), conn)

    def partners(self, *, active_only: bool = False) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM partners" + (" WHERE active = 1" if active_only else "") + " ORDER BY name"
        with self._connect() as conn:
            return [self._partner_row(r, conn) for r in conn.execute(sql).fetchall()]

    def set_secret(self, partner_id: int, name: str, value: str) -> None:
        """Stores the value ENCRYPTED (fails closed without ASKODOX_SECRETS_KEY)."""
        if name not in SECRET_NAMES:
            raise ValueError(f"secret must be one of {', '.join(SECRET_NAMES)}")
        with self._connect() as conn:
            if value:
                conn.execute(
                    "INSERT INTO partner_secrets (partner_id, name, value, updated_at) VALUES (?, ?, ?, ?) "
                    "ON CONFLICT(partner_id, name) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
                    (partner_id, name, self.box.encrypt(value), _now()),
                )
            else:
                conn.execute("DELETE FROM partner_secrets WHERE partner_id = ? AND name = ?", (partner_id, name))

    def secret(self, partner_id: int, name: str) -> str:
        """Backend-internal only (link building, feed/postback auth)."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT value FROM partner_secrets WHERE partner_id = ? AND name = ?", (partner_id, name)
            ).fetchone()
        return self.box.decrypt(str(row["value"])) if row else ""

    def rotate_secrets(self) -> Dict[str, int]:
        """Re-encrypt every stored secret with the CURRENT key (after adding a
        new ASKODOX_SECRETS_KEY and moving the old one to _PREVIOUS), and
        encrypt any legacy plain rows. Rows no known key can read are
        reported, never guessed."""
        rewritten = unreadable = 0
        with self._connect() as conn:
            rows = conn.execute("SELECT partner_id, name, value FROM partner_secrets").fetchall()
            for row in rows:
                if not self.box.needs_rewrite(row["value"]):
                    continue
                plain = self.box.decrypt(row["value"])
                if not plain:
                    unreadable += 1
                    continue
                conn.execute("UPDATE partner_secrets SET value = ?, updated_at = ? WHERE partner_id = ? AND name = ?",
                             (self.box.encrypt(plain), _now(), row["partner_id"], row["name"]))
                rewritten += 1
        return {"secrets": len(rows), "rewritten": rewritten, "unreadable": unreadable}

    def generate_postback_token(self, partner_id: int) -> str:
        token = secrets.token_urlsafe(24)
        self.set_secret(partner_id, "postback_token", token)
        return token

    def record_check(self, partner_id: int, ok: bool, report: Dict[str, Any], *, synced: bool = False) -> None:
        now = _now()
        with self._connect() as conn:
            conn.execute(
                "UPDATE partners SET last_check_at = ?, last_check_ok = ?, last_check_json = ?, last_error = ?"
                + (", last_sync_at = ?" if synced and ok else "") + " WHERE id = ?",
                (now, 1 if ok else 0, json.dumps(report)[:8000], None if ok else str(report.get("error") or "")[:500],
                 *((now,) if synced and ok else ()), partner_id),
            )

    # ---------------------------------------------------------- click ids --

    def new_click_id(self) -> str:
        nonce = secrets.token_hex(8)
        return "ck" + nonce + hmac.new(self._click_key, nonce.encode(), hashlib.sha256).hexdigest()[:10]

    def valid_click_id(self, click_id: str) -> bool:
        text = str(click_id or "")
        if len(text) != 28 or not text.startswith("ck"):
            return False
        nonce, sig = text[2:18], text[18:]
        expected = hmac.new(self._click_key, nonce.encode(), hashlib.sha256).hexdigest()[:10]
        return hmac.compare_digest(sig, expected)

    # ------------------------------------------------------------ events --

    def record_event(self, event: str, *, partner_id: int | None = None, click_id: str | None = None,
                     trace_key: str | None = None, category: str = "", subject: str = "", location: str = "",
                     language: str = "", campaign: str = "", detail: Dict[str, Any] | None = None,
                     occurred_at: str | None = None) -> bool:
        """Records the event; False when it was already counted for this
        click id (card view / click / open / lead count once)."""
        if event not in EVENTS:
            raise ValueError(f"unknown event {event}")
        with self._connect() as conn:
            if click_id and event in ONCE_PER_CLICK and conn.execute(
                    "SELECT 1 FROM revenue_events WHERE click_id = ? AND event = ?", (click_id, event)).fetchone():
                return False
            conn.execute(
                "INSERT INTO revenue_events (occurred_at, event, partner_id, click_id, trace_key, category, subject, "
                "location, language, campaign, detail_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (occurred_at or _now(), event, partner_id, click_id, trace_key, (category or "")[:80],
                 (subject or "")[:120], (location or "")[:120], (language or "")[:12], (campaign or "")[:80],
                 json.dumps(detail or {})[:2000]),
            )
        return True

    def impression_context(self, click_id: str, *, max_age_hours: int | None = None) -> Optional[Dict[str, Any]]:
        """The impression a click / postback refers to (its attributes). Only
        signed ASKODOX click ids; optionally only recent impressions."""
        if not self.valid_click_id(click_id):
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM revenue_events WHERE click_id = ? AND event = 'impression' ORDER BY id LIMIT 1",
                (click_id,),
            ).fetchone()
        if row is None:
            return None
        item = dict(row)
        if max_age_hours is not None:
            try:
                seen = datetime.fromisoformat(str(item["occurred_at"]))
                if datetime.now(timezone.utc) - seen > timedelta(hours=max_age_hours):
                    return None
            except ValueError:
                return None
        item["detail"] = _loads(item.pop("detail_json", None), {})
        return item

    def events_between(self, start: str, end: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, occurred_at, event, partner_id, click_id, category, subject, location, language, campaign, "
                "detail_json FROM revenue_events WHERE occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at",
                (start, end),
            ).fetchall()
        return [{**{k: r[k] for k in r.keys() if k != "detail_json"}, "detail": _loads(r["detail_json"], {})}
                for r in rows]

    # ------------------------------------------------------- conversions --

    def upsert_conversion(self, *, partner_id: int, external_id: str, source: str, status: Any = "PENDING",
                          click_id: str | None = None, order_value: float | None = None,
                          commission: float | None = None, commission_source: str = "partner",
                          currency: str = "INR", category: str = "", location: str = "", campaign: str = "",
                          language: str = "", occurred_at: str | None = None,
                          raw: Dict[str, Any] | None = None) -> Dict[str, Any]:
        external_id = str(external_id or "").strip()[:120]
        if not external_id:
            raise ValueError("order/conversion id is required")
        state = normalize_status(status)
        now = _now()
        with self._connect() as conn:
            existing = conn.execute(
                "SELECT * FROM partner_conversions WHERE partner_id = ? AND external_id = ?", (partner_id, external_id)
            ).fetchone()
            if existing is None:
                conn.execute(
                    "INSERT INTO partner_conversions (partner_id, external_id, click_id, order_value, currency, commission, "
                    "commission_source, status, category, location, campaign, language, source, occurred_at, updated_at, "
                    "raw_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (partner_id, external_id, click_id, order_value, currency or "INR", commission, commission_source,
                     state, category, location, campaign, language, source, occurred_at or now, now,
                     json.dumps(raw or {})[:4000]),
                )
            else:
                # A later report updates status/amounts; unknown values keep the old ones.
                conn.execute(
                    "UPDATE partner_conversions SET status = ?, order_value = COALESCE(?, order_value), "
                    "commission = COALESCE(?, commission), commission_source = CASE WHEN ? IS NULL THEN commission_source "
                    "ELSE ? END, click_id = COALESCE(click_id, ?), updated_at = ?, raw_json = ? WHERE id = ?",
                    (state, order_value, commission, commission, commission_source, click_id, now,
                     json.dumps(raw or {})[:4000], existing["id"]),
                )
            row = conn.execute(
                "SELECT * FROM partner_conversions WHERE partner_id = ? AND external_id = ?", (partner_id, external_id)
            ).fetchone()
        return self._conversion(row)

    @staticmethod
    def _conversion(row: sqlite3.Row) -> Dict[str, Any]:
        item = dict(row)
        item["raw"] = _loads(item.pop("raw_json", None), {})
        return item

    def set_conversion_status(self, conversion_id: int, status: str) -> Optional[Dict[str, Any]]:
        state = str(status or "").upper()
        if state not in CONVERSION_STATES:
            raise ValueError(f"status must be one of {', '.join(CONVERSION_STATES)}")
        with self._connect() as conn:
            conn.execute("UPDATE partner_conversions SET status = ?, updated_at = ? WHERE id = ?",
                         (state, _now(), conversion_id))
            row = conn.execute("SELECT * FROM partner_conversions WHERE id = ?", (conversion_id,)).fetchone()
        return self._conversion(row) if row else None

    def conversions_between(self, start: str, end: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM partner_conversions WHERE occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at",
                (start, end),
            ).fetchall()
        return [self._conversion(r) for r in rows]

    # ----------------------------------------------------------- entries --

    def add_entry(self, *, source: str, amount: float, occurred_at: str | None = None, currency: str = "INR",
                  partner_id: int | None = None, category: str = "", location: str = "", campaign: str = "",
                  reference: str = "", note: str = "", created_by: str = "") -> Dict[str, Any]:
        if source not in REVENUE_SOURCES:
            raise ValueError(f"source must be one of {', '.join(REVENUE_SOURCES)}")
        with self._connect() as conn:
            cursor = conn.execute(
                "INSERT INTO revenue_entries (source, amount, currency, occurred_at, partner_id, category, location, "
                "campaign, reference, note, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (source, float(amount), currency or "INR", occurred_at or _now(), partner_id, category, location,
                 campaign, reference[:120], note[:300], created_by, _now()),
            )
            return dict(conn.execute("SELECT * FROM revenue_entries WHERE id = ?", (cursor.lastrowid,)).fetchone())

    def entries_between(self, start: str, end: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM revenue_entries WHERE occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at",
                (start, end),
            ).fetchall()]

    # --------------------------------------------------------- retention --

    def meta(self, key: str) -> str:
        with self._connect() as conn:
            row = conn.execute("SELECT value FROM revenue_meta WHERE key = ?", (key,)).fetchone()
        return str(row["value"]) if row else ""

    def set_meta(self, key: str, value: str) -> None:
        with self._connect() as conn:
            conn.execute("INSERT INTO revenue_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET "
                         "value = excluded.value", (key, value))

    def run_retention(self, keep_days: int, *, now: datetime | None = None) -> Dict[str, Any]:
        """Roll raw funnel events older than keep_days into per-day counts
        (by partner, category, location, language, campaign), then delete the
        raw rows. Totals, breakdowns and trends stay exact; only per-event
        detail (click ids, subjects) of old events goes away. Conversions and
        revenue entries are never deleted."""
        keep_days = max(1, int(keep_days))
        moment = now or datetime.now(timezone.utc)
        zone = ZoneInfo(ROLLUP_TZ)
        # Cut at a local-day boundary so a day is never split between raw rows and roll-ups.
        cut_day = (moment.astimezone(zone) - timedelta(days=keep_days)).date()
        cutoff = datetime.combine(cut_day, datetime.min.time(), zone).astimezone(timezone.utc).isoformat()
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT occurred_at, event, partner_id, category, location, language, campaign FROM revenue_events "
                "WHERE occurred_at < ?", (cutoff,)).fetchall()
            counts: Dict[tuple, int] = {}
            for row in rows:
                try:
                    day = datetime.fromisoformat(str(row["occurred_at"])).astimezone(zone).date().isoformat()
                except ValueError:
                    day = str(row["occurred_at"])[:10]
                key = (day, row["event"], row["partner_id"] or 0, row["category"] or "", row["location"] or "",
                       row["language"] or "", row["campaign"] or "")
                counts[key] = counts.get(key, 0) + 1
            for key, count in counts.items():
                conn.execute(
                    "INSERT INTO revenue_daily_rollup (day, event, partner_id, category, location, language, campaign, "
                    "count) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(day, event, partner_id, category, location, "
                    "language, campaign) DO UPDATE SET count = count + excluded.count", (*key, count))
            conn.execute("DELETE FROM revenue_events WHERE occurred_at < ?", (cutoff,))
            attachments = 0
            try:  # chat attachment analyses follow the same retention
                attachments = conn.execute("DELETE FROM chat_attachments WHERE created_at < ?", (cutoff,)).rowcount
            except sqlite3.Error:
                pass
        self.set_meta("retention_last_run", moment.isoformat())
        return {"cutoff": cutoff, "rolled_up_events": len(rows), "rollup_rows": len(counts),
                "deleted_attachment_records": attachments, "keep_days": keep_days}

    def maybe_run_retention(self, keep_days: int) -> Optional[Dict[str, Any]]:
        """At most once a day per database (there is no cron here)."""
        last = self.meta("retention_last_run")
        try:
            if last and datetime.now(timezone.utc) - datetime.fromisoformat(last) < timedelta(hours=24):
                return None
        except ValueError:
            pass
        return self.run_retention(keep_days)

    def rollups_between(self, first_day: str, last_day: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM revenue_daily_rollup WHERE day >= ? AND day <= ? ORDER BY day", (first_day, last_day)
            ).fetchall()]
