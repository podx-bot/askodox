"""ASKODOX commerce platform store (one repository, tables ``pf_*``).

- pf_records          configurable Command Center resources (affiliate
                      programs / links, smart links, merchant offers, creators,
                      video sources, videos, reviews, notification templates /
                      rules, subscription promotions, ...). Schema and
                      lifecycle live in services/platform_schema.py.
- pf_record_history   append-only change history per record (who, what,
                      before / after). There is no update / delete for it.
- pf_events           the attribution pipeline: SEARCH -> IMPRESSION -> ...
                      -> COMMISSION -> REVENUE, with stable ids for user,
                      session, search, result, merchant, partner, campaign,
                      offer, coupon, click, order, transaction, conversion,
                      video, creator.
- pf_payments         provider-agnostic payment records (idempotency key per
                      intent); pf_payment_events dedupes provider webhooks.
- pf_ledger           revenue / commission ledger (expected -> pending ->
                      confirmed -> paid, or rejected / reversed); idempotent.
- pf_rewards          customer rewards ledger (available / locked / unlocked /
                      claimed / redeemed / expired / cancelled); idempotent.
- pf_state_history    every ledger / payment state change (append-only).
- pf_account_states   moderation for users / partners / merchants: blocked,
                      verified, archived (enforced server-side).

Dependency-free sqlite3 like the other repositories; ids are stable strings
with a type prefix so they can travel through links and analytics.
"""
from __future__ import annotations

import json
import secrets
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def _loads(raw: Any, default: Any) -> Any:
    try:
        return json.loads(raw) if raw else default
    except (TypeError, ValueError):
        return default


class PlatformConflict(RuntimeError):
    """Optimistic-lock or idempotency conflict."""


PAYMENT_STATES = ("CREATED", "PENDING", "PAID", "FAILED", "CANCELLED", "REFUNDED", "PARTIALLY_REFUNDED",
                  "SETTLED", "DISPUTED")
PAYMENT_TRANSITIONS: Dict[str, tuple[str, ...]] = {
    "CREATED": ("PENDING", "PAID", "FAILED", "CANCELLED"),
    "PENDING": ("PAID", "FAILED", "CANCELLED"),
    "PAID": ("REFUNDED", "PARTIALLY_REFUNDED", "SETTLED", "DISPUTED"),
    "PARTIALLY_REFUNDED": ("REFUNDED", "PARTIALLY_REFUNDED", "SETTLED", "DISPUTED"),
    "SETTLED": ("REFUNDED", "PARTIALLY_REFUNDED", "DISPUTED"),
    "DISPUTED": ("PAID", "REFUNDED", "SETTLED"),
    "FAILED": (),
    "CANCELLED": (),
    "REFUNDED": (),
}

LEDGER_KINDS = ("affiliate_commission", "sponsored_revenue", "lead_fee", "merchant_promotion_fee",
                "subscription_revenue", "campaign_revenue", "referral_commission", "service_fee", "premium_service",
                "other")
LEDGER_STATES = ("EXPECTED", "PENDING", "CONFIRMED", "REJECTED", "PAID", "REVERSED")
LEDGER_TRANSITIONS: Dict[str, tuple[str, ...]] = {
    "EXPECTED": ("PENDING", "CONFIRMED", "REJECTED"),
    "PENDING": ("CONFIRMED", "REJECTED"),
    "CONFIRMED": ("PAID", "REVERSED"),
    "PAID": ("REVERSED",),
    "REJECTED": (),
    "REVERSED": (),
}

REWARD_TYPES = ("cashback", "coupon", "voucher", "points", "scratch", "partner", "referral", "merchant",
                "milestone", "engagement", "festival", "promotional")
REWARD_STATES = ("AVAILABLE", "LOCKED", "UNLOCKED", "CLAIMED", "REDEEMED", "EXPIRED", "CANCELLED")
REWARD_TRANSITIONS: Dict[str, tuple[str, ...]] = {
    "LOCKED": ("UNLOCKED", "EXPIRED", "CANCELLED"),
    "UNLOCKED": ("CLAIMED", "EXPIRED", "CANCELLED"),
    "AVAILABLE": ("CLAIMED", "EXPIRED", "CANCELLED"),
    "CLAIMED": ("REDEEMED", "EXPIRED", "CANCELLED"),
    "REDEEMED": (),
    "EXPIRED": (),
    "CANCELLED": (),
}

# The attribution pipeline (plus the video funnel). Events outside this list
# are refused, so analytics never fills with free-form noise.
EVENTS = (
    "search", "impression", "result_view", "click", "deep_link", "redirect", "claim", "lead", "order", "payment",
    "redemption", "conversion", "commission", "revenue", "no_match", "abandon", "signup", "join", "referral_invite",
    "referral_signup", "coupon_claim", "coupon_redeem", "reward_claim", "reward_redeem",
    "video_impression", "video_open", "video_watch_start", "video_watch_complete", "video_ask",
    "video_product_click", "video_service_click", "video_local_search", "video_affiliate_click", "video_contact",
    "support_ticket", "notification_sent", "notification_open",
)
EVENT_IDS = ("user_ref", "session_id", "search_id", "result_id", "merchant_id", "partner_id", "campaign_id",
             "offer_id", "coupon_id", "click_id", "order_id", "transaction_id", "conversion_id", "video_id",
             "creator_id", "link_id")


class PlatformRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        id_cols = ", ".join(f"{c} TEXT" for c in EVENT_IDS)
        with self._connect() as conn:
            conn.executescript(
                f"""
                CREATE TABLE IF NOT EXISTS pf_records (
                    id TEXT PRIMARY KEY, resource TEXT NOT NULL, name TEXT NOT NULL,
                    status TEXT NOT NULL, data_json TEXT NOT NULL DEFAULT '{{}}',
                    owner_ref TEXT, archived INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL DEFAULT 1,
                    created_by TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_pf_records_resource ON pf_records(resource, archived, status);
                CREATE TABLE IF NOT EXISTS pf_record_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, record_id TEXT NOT NULL, resource TEXT NOT NULL,
                    action TEXT NOT NULL, actor TEXT, before_json TEXT, after_json TEXT, at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_pf_history_record ON pf_record_history(record_id);
                CREATE TABLE IF NOT EXISTS pf_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, event TEXT NOT NULL, at TEXT NOT NULL,
                    {id_cols},
                    category TEXT, location TEXT, language TEXT, source TEXT,
                    value REAL, currency TEXT, detail_json TEXT NOT NULL DEFAULT '{{}}', dedupe_key TEXT UNIQUE
                );
                CREATE INDEX IF NOT EXISTS idx_pf_events_event ON pf_events(event, at);
                CREATE INDEX IF NOT EXISTS idx_pf_events_search ON pf_events(search_id);
                CREATE INDEX IF NOT EXISTS idx_pf_events_click ON pf_events(click_id);
                CREATE TABLE IF NOT EXISTS pf_payments (
                    id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE, provider TEXT NOT NULL,
                    method TEXT NOT NULL, order_ref TEXT, payer_ref TEXT, payee_ref TEXT,
                    amount REAL NOT NULL, currency TEXT NOT NULL DEFAULT 'INR', status TEXT NOT NULL,
                    provider_ref TEXT, refunded_amount REAL NOT NULL DEFAULT 0, settlement_ref TEXT,
                    detail_json TEXT NOT NULL DEFAULT '{{}}', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pf_payment_events (
                    provider TEXT NOT NULL, provider_event_id TEXT NOT NULL, payment_id TEXT,
                    event TEXT NOT NULL, received_at TEXT NOT NULL,
                    PRIMARY KEY (provider, provider_event_id)
                );
                CREATE TABLE IF NOT EXISTS pf_ledger (
                    id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,
                    amount REAL NOT NULL, currency TEXT NOT NULL DEFAULT 'INR', state TEXT NOT NULL,
                    partner_id TEXT, campaign_id TEXT, conversion_id TEXT, order_ref TEXT, source_ref TEXT,
                    note TEXT, occurred_at TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS pf_rewards (
                    id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE, user_ref TEXT NOT NULL,
                    reward_type TEXT NOT NULL, amount REAL, points INTEGER, state TEXT NOT NULL,
                    source TEXT, campaign_id TEXT, title TEXT, expires_at TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_pf_rewards_user ON pf_rewards(user_ref, state);
                CREATE TABLE IF NOT EXISTS pf_state_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, entity_id TEXT NOT NULL,
                    from_state TEXT, to_state TEXT NOT NULL, actor TEXT, note TEXT, at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_pf_state_entity ON pf_state_history(entity, entity_id);
                CREATE TABLE IF NOT EXISTS pf_account_states (
                    subject_type TEXT NOT NULL, subject_ref TEXT NOT NULL,
                    blocked INTEGER NOT NULL DEFAULT 0, verified INTEGER NOT NULL DEFAULT 0,
                    archived INTEGER NOT NULL DEFAULT 0, note TEXT, updated_by TEXT, updated_at TEXT NOT NULL,
                    PRIMARY KEY (subject_type, subject_ref)
                );
                """
            )

    # ------------------------------------------------------------- records --

    @staticmethod
    def _record(row: sqlite3.Row) -> Dict[str, Any]:
        item = dict(row)
        item["data"] = _loads(item.pop("data_json", "{}"), {})
        item["archived"] = bool(item["archived"])
        return item

    def get(self, record_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_records WHERE id=?", (record_id,)).fetchone()
        return self._record(row) if row else None

    def list(self, resource: str, *, include_archived: bool = False, status: str | None = None,
             owner_ref: str | None = None) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM pf_records WHERE resource=?"
        params: list[Any] = [resource]
        if not include_archived:
            sql += " AND archived=0"
        if status:
            sql += " AND status=?"
            params.append(status)
        if owner_ref:
            sql += " AND owner_ref=?"
            params.append(owner_ref)
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY updated_at DESC", params).fetchall()
        return [self._record(r) for r in rows]

    def _history(self, conn, record_id: str, resource: str, action: str, actor: str,
                 before: Any, after: Any) -> None:
        conn.execute(
            "INSERT INTO pf_record_history (record_id, resource, action, actor, before_json, after_json, at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (record_id, resource, action, actor, json.dumps(before, default=str) if before is not None else None,
             json.dumps(after, default=str) if after is not None else None, now_iso()),
        )

    def create(self, resource: str, prefix: str, *, name: str, status: str, data: Dict[str, Any],
               actor: str, owner_ref: str | None = None) -> Dict[str, Any]:
        record_id = new_id(prefix)
        at = now_iso()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pf_records (id, resource, name, status, data_json, owner_ref, created_by, created_at, "
                "updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (record_id, resource, name, status, json.dumps(data, default=str), owner_ref, actor, at, at),
            )
            self._history(conn, record_id, resource, "create", actor, None,
                          {"name": name, "status": status, "data": data})
        return self.get(record_id) or {}

    def update(self, record_id: str, *, actor: str, action: str, name: str | None = None,
               status: str | None = None, data: Dict[str, Any] | None = None, archived: bool | None = None,
               expected_version: int | None = None) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_records WHERE id=?", (record_id,)).fetchone()
            if not row:
                raise KeyError(record_id)
            before = self._record(row)
            if expected_version is not None and int(before["version"]) != int(expected_version):
                raise PlatformConflict("This record was changed by someone else; reload and try again.")
            after = {
                "name": name if name is not None else before["name"],
                "status": status if status is not None else before["status"],
                "data": data if data is not None else before["data"],
                "archived": archived if archived is not None else before["archived"],
            }
            conn.execute(
                "UPDATE pf_records SET name=?, status=?, data_json=?, archived=?, version=version+1, updated_at=? "
                "WHERE id=?",
                (after["name"], after["status"], json.dumps(after["data"], default=str), 1 if after["archived"] else 0,
                 now_iso(), record_id),
            )
            self._history(conn, record_id, before["resource"], action, actor,
                          {k: before[k] for k in ("name", "status", "data", "archived")}, after)
        return self.get(record_id) or {}

    def delete(self, record_id: str, *, actor: str) -> None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_records WHERE id=?", (record_id,)).fetchone()
            if not row:
                raise KeyError(record_id)
            before = self._record(row)
            conn.execute("DELETE FROM pf_records WHERE id=?", (record_id,))
            self._history(conn, record_id, before["resource"], "delete", actor,
                          {k: before[k] for k in ("name", "status", "data", "archived")}, None)

    def history(self, record_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM pf_record_history WHERE record_id=? ORDER BY id", (record_id,)).fetchall()
        return [dict(r) | {"before": _loads(r["before_json"], None), "after": _loads(r["after_json"], None)}
                for r in rows]

    # -------------------------------------------------------------- events --

    def record_event(self, event: str, *, detail: Dict[str, Any] | None = None, value: float | None = None,
                     currency: str | None = None, category: str = "", location: str = "", language: str = "",
                     source: str = "", dedupe_key: str | None = None, **ids: Any) -> Optional[int]:
        if event not in EVENTS:
            raise ValueError(f"unknown event {event}")
        unknown = set(ids) - set(EVENT_IDS)
        if unknown:
            raise ValueError(f"unknown id fields {sorted(unknown)}")
        cols = ["event", "at", "category", "location", "language", "source", "value", "currency", "detail_json",
                "dedupe_key"] + [c for c in EVENT_IDS if ids.get(c)]
        vals = [event, now_iso(), category[:80], location[:120], language[:12], source[:40], value, currency,
                json.dumps(detail or {}, default=str)[:4000], dedupe_key] + [str(ids[c])[:80] for c in EVENT_IDS
                                                                            if ids.get(c)]
        with self._connect() as conn:
            try:
                cur = conn.execute(f"INSERT INTO pf_events ({', '.join(cols)}) VALUES ({', '.join('?' for _ in cols)})",
                                   vals)
            except sqlite3.IntegrityError:
                return None  # already counted (dedupe_key)
        return int(cur.lastrowid)

    def events(self, *, event: str | None = None, since: str | None = None, until: str | None = None,
               limit: int = 500, **ids: Any) -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM pf_events WHERE 1=1", []
        if event:
            sql += " AND event=?"
            params.append(event)
        if since:
            sql += " AND at>=?"
            params.append(since)
        if until:
            sql += " AND at<?"
            params.append(until)
        for key, value in ids.items():
            if key in EVENT_IDS and value:
                sql += f" AND {key}=?"
                params.append(str(value))
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY id DESC LIMIT ?", [*params, int(limit)]).fetchall()
        return [dict(r) | {"detail": _loads(r["detail_json"], {})} for r in rows]

    def event_counts(self, *, since: str | None = None, until: str | None = None,
                     group: str | None = None, where: Dict[str, Any] | None = None) -> List[Dict[str, Any]]:
        allowed = {"event", "category", "location", "language", "source", *EVENT_IDS}
        cols = "event" + (f", {group}" if group in allowed and group != "event" else "")
        sql, params = f"SELECT {cols}, COUNT(*) AS n, COALESCE(SUM(value), 0) AS value FROM pf_events WHERE 1=1", []
        if since:
            sql += " AND at>=?"
            params.append(since)
        if until:
            sql += " AND at<?"
            params.append(until)
        for key, value in (where or {}).items():
            if key in allowed and value:
                sql += f" AND {key}=?"
                params.append(str(value))
        with self._connect() as conn:
            rows = conn.execute(sql + f" GROUP BY {cols} ORDER BY n DESC", params).fetchall()
        return [dict(r) for r in rows]

    # ------------------------------------------------------ state machines --

    def _state_change(self, conn, entity: str, entity_id: str, from_state: str | None, to_state: str,
                      actor: str, note: str = "") -> None:
        conn.execute(
            "INSERT INTO pf_state_history (entity, entity_id, from_state, to_state, actor, note, at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (entity, entity_id, from_state, to_state, actor, note[:300], now_iso()),
        )

    def state_history(self, entity: str, entity_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM pf_state_history WHERE entity=? AND entity_id=? ORDER BY id",
                                (entity, entity_id)).fetchall()
        return [dict(r) for r in rows]

    # payments
    def create_payment(self, *, idempotency_key: str, provider: str, method: str, amount: float,
                       currency: str = "INR", order_ref: str | None = None, payer_ref: str | None = None,
                       payee_ref: str | None = None, detail: Dict[str, Any] | None = None,
                       actor: str = "system") -> tuple[Dict[str, Any], bool]:
        """(payment, created). The same idempotency key returns the same
        payment -- a retried request never creates a second charge."""
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_payments WHERE idempotency_key=?", (idempotency_key,)).fetchone()
            if row:
                existing = dict(row)
                if abs(float(existing["amount"]) - float(amount)) > 1e-9 or existing["order_ref"] != order_ref:
                    raise PlatformConflict("idempotency key reused for a different payment")
                return self._payment(existing), False
            pay_id = new_id("pay")
            at = now_iso()
            conn.execute(
                "INSERT INTO pf_payments (id, idempotency_key, provider, method, order_ref, payer_ref, payee_ref, "
                "amount, currency, status, detail_json, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'CREATED', ?, ?, ?)",
                (pay_id, idempotency_key, provider, method, order_ref, payer_ref, payee_ref, float(amount), currency,
                 json.dumps(detail or {}), at, at),
            )
            self._state_change(conn, "payment", pay_id, None, "CREATED", actor)
        return self.payment(pay_id) or {}, True

    @staticmethod
    def _payment(row: Dict[str, Any]) -> Dict[str, Any]:
        item = dict(row)
        item["detail"] = _loads(item.pop("detail_json", "{}"), {})
        return item

    def payment(self, payment_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_payments WHERE id=?", (payment_id,)).fetchone()
        return self._payment(dict(row)) if row else None

    def payments(self, *, status: str | None = None, limit: int = 200) -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM pf_payments", []
        if status:
            sql += " WHERE status=?"
            params.append(status)
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY created_at DESC LIMIT ?", [*params, limit]).fetchall()
        return [self._payment(dict(r)) for r in rows]

    def transition_payment(self, payment_id: str, to_state: str, *, actor: str, note: str = "",
                           provider_ref: str | None = None, refund_amount: float | None = None,
                           settlement_ref: str | None = None) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_payments WHERE id=?", (payment_id,)).fetchone()
            if not row:
                raise KeyError(payment_id)
            current = row["status"]
            if to_state not in PAYMENT_TRANSITIONS.get(current, ()):
                raise PlatformConflict(f"payment {current} cannot become {to_state}")
            refunded = float(row["refunded_amount"] or 0)
            if to_state in ("REFUNDED", "PARTIALLY_REFUNDED"):
                amount = float(row["amount"])
                add = amount - refunded if to_state == "REFUNDED" and refund_amount is None else float(refund_amount or 0)
                if add <= 0 or refunded + add > amount + 1e-9:
                    raise PlatformConflict("refund must be positive and not exceed the amount paid")
                refunded += add
                to_state = "REFUNDED" if abs(refunded - amount) < 1e-9 else "PARTIALLY_REFUNDED"
            conn.execute(
                "UPDATE pf_payments SET status=?, provider_ref=COALESCE(?, provider_ref), refunded_amount=?, "
                "settlement_ref=COALESCE(?, settlement_ref), updated_at=? WHERE id=?",
                (to_state, provider_ref, refunded, settlement_ref, now_iso(), payment_id),
            )
            self._state_change(conn, "payment", payment_id, current, to_state, actor, note)
        return self.payment(payment_id) or {}

    def seen_webhook(self, provider: str, provider_event_id: str, *, payment_id: str | None, event: str) -> bool:
        """True when this provider event was already processed (replay)."""
        with self._connect() as conn:
            try:
                conn.execute("INSERT INTO pf_payment_events (provider, provider_event_id, payment_id, event, "
                             "received_at) VALUES (?, ?, ?, ?, ?)",
                             (provider, provider_event_id, payment_id, event, now_iso()))
            except sqlite3.IntegrityError:
                return True
        return False

    # ledger
    def ledger_add(self, *, idempotency_key: str, kind: str, amount: float, state: str = "EXPECTED",
                   currency: str = "INR", partner_id: str | None = None, campaign_id: str | None = None,
                   conversion_id: str | None = None, order_ref: str | None = None, source_ref: str | None = None,
                   note: str = "", occurred_at: str | None = None, actor: str = "system") -> tuple[Dict[str, Any], bool]:
        if kind not in LEDGER_KINDS:
            raise ValueError(f"kind must be one of {', '.join(LEDGER_KINDS)}")
        if state not in LEDGER_STATES:
            raise ValueError("unknown ledger state")
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_ledger WHERE idempotency_key=?", (idempotency_key,)).fetchone()
            if row:
                return dict(row), False
            entry_id = new_id("led")
            at = now_iso()
            conn.execute(
                "INSERT INTO pf_ledger (id, idempotency_key, kind, amount, currency, state, partner_id, campaign_id, "
                "conversion_id, order_ref, source_ref, note, occurred_at, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (entry_id, idempotency_key, kind, float(amount), currency, state, partner_id, campaign_id,
                 conversion_id, order_ref, source_ref, note[:300], occurred_at or at, at, at),
            )
            self._state_change(conn, "ledger", entry_id, None, state, actor, note)
            row = conn.execute("SELECT * FROM pf_ledger WHERE id=?", (entry_id,)).fetchone()
        return dict(row), True

    def ledger(self, *, state: str | None = None, kind: str | None = None, since: str | None = None,
               until: str | None = None) -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM pf_ledger WHERE 1=1", []
        for col, value in (("state", state), ("kind", kind)):
            if value:
                sql += f" AND {col}=?"
                params.append(value)
        if since:
            sql += " AND occurred_at>=?"
            params.append(since)
        if until:
            sql += " AND occurred_at<?"
            params.append(until)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY occurred_at DESC", params).fetchall()]

    def transition_ledger(self, entry_id: str, to_state: str, *, actor: str, note: str = "") -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_ledger WHERE id=?", (entry_id,)).fetchone()
            if not row:
                raise KeyError(entry_id)
            if to_state not in LEDGER_TRANSITIONS.get(row["state"], ()):
                raise PlatformConflict(f"ledger entry {row['state']} cannot become {to_state}")
            conn.execute("UPDATE pf_ledger SET state=?, updated_at=? WHERE id=?", (to_state, now_iso(), entry_id))
            self._state_change(conn, "ledger", entry_id, row["state"], to_state, actor, note)
            row = conn.execute("SELECT * FROM pf_ledger WHERE id=?", (entry_id,)).fetchone()
        return dict(row)

    # rewards
    def reward_add(self, *, idempotency_key: str, user_ref: str, reward_type: str, state: str = "AVAILABLE",
                   amount: float | None = None, points: int | None = None, source: str = "",
                   campaign_id: str | None = None, title: str = "", expires_at: str | None = None,
                   actor: str = "system") -> tuple[Dict[str, Any], bool]:
        if reward_type not in REWARD_TYPES:
            raise ValueError(f"reward_type must be one of {', '.join(REWARD_TYPES)}")
        if state not in ("AVAILABLE", "LOCKED"):
            raise ValueError("a new reward starts AVAILABLE or LOCKED")
        if (amount is None or amount <= 0) and (points is None or points <= 0):
            raise ValueError("a reward needs a positive amount or points")
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_rewards WHERE idempotency_key=?", (idempotency_key,)).fetchone()
            if row:
                return dict(row), False
            reward_id = new_id("rwd")
            at = now_iso()
            conn.execute(
                "INSERT INTO pf_rewards (id, idempotency_key, user_ref, reward_type, amount, points, state, source, "
                "campaign_id, title, expires_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (reward_id, idempotency_key, user_ref, reward_type, amount, points, state, source[:80], campaign_id,
                 title[:120], expires_at, at, at),
            )
            self._state_change(conn, "reward", reward_id, None, state, actor)
            row = conn.execute("SELECT * FROM pf_rewards WHERE id=?", (reward_id,)).fetchone()
        return dict(row), True

    def rewards(self, *, user_ref: str | None = None, state: str | None = None) -> List[Dict[str, Any]]:
        self.expire_rewards()
        sql, params = "SELECT * FROM pf_rewards WHERE 1=1", []
        for col, value in (("user_ref", user_ref), ("state", state)):
            if value:
                sql += f" AND {col}=?"
                params.append(value)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY created_at DESC", params).fetchall()]

    def reward(self, reward_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_rewards WHERE id=?", (reward_id,)).fetchone()
        return dict(row) if row else None

    def transition_reward(self, reward_id: str, to_state: str, *, actor: str, note: str = "",
                          user_ref: str | None = None) -> Dict[str, Any]:
        self.expire_rewards()
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_rewards WHERE id=?", (reward_id,)).fetchone()
            if not row:
                raise KeyError(reward_id)
            if user_ref is not None and row["user_ref"] != user_ref:
                raise KeyError(reward_id)  # never reveal someone else's reward
            if to_state not in REWARD_TRANSITIONS.get(row["state"], ()):
                raise PlatformConflict(f"reward {row['state']} cannot become {to_state}")
            # Compare-and-set: a concurrent second claim / redeem fails.
            cur = conn.execute("UPDATE pf_rewards SET state=?, updated_at=? WHERE id=? AND state=?",
                               (to_state, now_iso(), reward_id, row["state"]))
            if cur.rowcount != 1:
                raise PlatformConflict("reward changed concurrently")
            self._state_change(conn, "reward", reward_id, row["state"], to_state, actor, note)
            row = conn.execute("SELECT * FROM pf_rewards WHERE id=?", (reward_id,)).fetchone()
        return dict(row)

    def expire_rewards(self) -> int:
        at = now_iso()
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT id, state FROM pf_rewards WHERE expires_at IS NOT NULL AND expires_at<? "
                "AND state IN ('AVAILABLE','LOCKED','UNLOCKED','CLAIMED')", (at,)).fetchall()
            for row in rows:
                conn.execute("UPDATE pf_rewards SET state='EXPIRED', updated_at=? WHERE id=?", (at, row["id"]))
                self._state_change(conn, "reward", row["id"], row["state"], "EXPIRED", "system", "expired")
        return len(rows)

    # ------------------------------------------------------- account states --

    def account_state(self, subject_type: str, subject_ref: str) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_account_states WHERE subject_type=? AND subject_ref=?",
                               (subject_type, subject_ref)).fetchone()
        if not row:
            return {"subject_type": subject_type, "subject_ref": subject_ref, "blocked": False, "verified": False,
                    "archived": False}
        item = dict(row)
        for key in ("blocked", "verified", "archived"):
            item[key] = bool(item[key])
        return item

    def set_account_state(self, subject_type: str, subject_ref: str, *, actor: str, note: str = "",
                          **flags: bool) -> Dict[str, Any]:
        current = self.account_state(subject_type, subject_ref)
        values = {k: bool(flags[k]) if k in flags else current[k] for k in ("blocked", "verified", "archived")}
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pf_account_states (subject_type, subject_ref, blocked, verified, archived, note, "
                "updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(subject_type, subject_ref) DO UPDATE SET blocked=excluded.blocked, "
                "verified=excluded.verified, archived=excluded.archived, note=excluded.note, "
                "updated_by=excluded.updated_by, updated_at=excluded.updated_at",
                (subject_type, subject_ref, int(values["blocked"]), int(values["verified"]), int(values["archived"]),
                 note[:300], actor, now_iso()),
            )
            for key, value in values.items():
                if value != current[key]:
                    self._state_change(conn, f"account:{subject_type}", subject_ref, f"{key}={current[key]}",
                                       f"{key}={value}", actor, note)
        return self.account_state(subject_type, subject_ref)

    def blocked_refs(self, subject_type: str) -> set[str]:
        with self._connect() as conn:
            rows = conn.execute("SELECT subject_ref FROM pf_account_states WHERE subject_type=? AND blocked=1",
                                (subject_type,)).fetchall()
        return {r["subject_ref"] for r in rows}

    def account_states(self, subject_type: str) -> Dict[str, Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM pf_account_states WHERE subject_type=?", (subject_type,)).fetchall()
        return {r["subject_ref"]: {k: bool(r[k]) for k in ("blocked", "verified", "archived")} for r in rows}

    def all_records(self, resources: Iterable[str]) -> List[Dict[str, Any]]:
        names = list(resources)
        if not names:
            return []
        with self._connect() as conn:
            rows = conn.execute(
                f"SELECT * FROM pf_records WHERE resource IN ({', '.join('?' for _ in names)}) AND archived=0",
                names).fetchall()
        return [self._record(r) for r in rows]
