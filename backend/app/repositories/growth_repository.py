"""Growth & monetisation state for the universal engine (one repository):

- offers           seller/provider and admin promotions (rules: offers_engine)
- participants     who took part in a transaction and in what role
                   (influencer / advisor / referrer / agent / partner ...)
- reward_rules     admin-configured reward per participant role
- rewards          transparent ledger: PENDING -> APPROVED -> PAID | CANCELLED
- referrals        "refer to ASKODOX" invites with a code -> REGISTERED
- plans            admin-configured subscription plans (no hard-coded prices)
- subscriptions    TRIAL / ACTIVE / PENDING_PAYMENT / CANCELLED / EXPIRED
- credits          promotional / joining credits ledger
- catalog_drafts   AI catalog drafts awaiting the seller's review
- api_usage        external API calls per day+provider (survives deploys)

Every row is a real record; nothing here is shown to customers unless it
exists. Dependency-free (sqlite3) like the other repositories.
"""
from __future__ import annotations

import json
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

REWARD_STATES = ("PENDING", "APPROVED", "PAID", "CANCELLED")
SUBSCRIPTION_STATES = ("TRIAL", "ACTIVE", "PENDING_PAYMENT", "CANCELLED", "EXPIRED")
PARTICIPANT_ROLES = (
    "buyer", "seller", "one_time_seller", "service_provider", "customer", "worker", "job_seeker",
    "employer", "influencer", "advisor", "referrer", "agent", "partner", "distributor", "farmer",
    "delivery_partner", "driver",
)
# Roles that may earn a reward for adding value to someone else's deal.
REWARDABLE_ROLES = ("influencer", "advisor", "referrer", "agent", "partner", "distributor")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _loads(raw: Any, default: Any) -> Any:
    try:
        return json.loads(raw) if raw else default
    except (TypeError, ValueError):
        return default


class GrowthRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS growth_offers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    owner_type TEXT NOT NULL, owner_id TEXT NOT NULL,
                    scope TEXT NOT NULL DEFAULT 'all', scope_value TEXT,
                    title TEXT, rule_type TEXT NOT NULL, params_json TEXT NOT NULL DEFAULT '{}',
                    starts_at TEXT, ends_at TEXT, active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_participants (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    context_type TEXT NOT NULL, context_id TEXT NOT NULL,
                    user_id TEXT NOT NULL, role TEXT NOT NULL, added_by TEXT,
                    created_at TEXT NOT NULL,
                    UNIQUE(context_type, context_id, user_id, role)
                );
                CREATE TABLE IF NOT EXISTS growth_reward_rules (
                    role TEXT PRIMARY KEY, percent REAL, amount REAL,
                    active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_rewards (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    participant_user_id TEXT NOT NULL, role TEXT NOT NULL,
                    context_type TEXT NOT NULL, context_id TEXT NOT NULL,
                    rule TEXT, amount REAL NOT NULL, status TEXT NOT NULL DEFAULT 'PENDING',
                    note TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                    UNIQUE(participant_user_id, role, context_type, context_id)
                );
                CREATE TABLE IF NOT EXISTS growth_referrals (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    code TEXT NOT NULL UNIQUE, referrer_user_id TEXT NOT NULL,
                    invitee_name TEXT, category TEXT, area TEXT, deal_id TEXT,
                    status TEXT NOT NULL DEFAULT 'INVITED', registered_user_id TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_plans (
                    code TEXT PRIMARY KEY, name TEXT NOT NULL, audience TEXT NOT NULL DEFAULT 'any',
                    price REAL NOT NULL DEFAULT 0, period_days INTEGER NOT NULL DEFAULT 30,
                    trial_days INTEGER NOT NULL DEFAULT 0, credits REAL NOT NULL DEFAULT 0,
                    entitlements_json TEXT NOT NULL DEFAULT '{}', active INTEGER NOT NULL DEFAULT 1,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_subscriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL, plan_code TEXT NOT NULL, status TEXT NOT NULL,
                    starts_at TEXT NOT NULL, ends_at TEXT, source TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_credits (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL, delta REAL NOT NULL, reason TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_catalog_drafts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    seller_user_id TEXT NOT NULL, draft_json TEXT NOT NULL, missing_json TEXT NOT NULL,
                    source TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'DRAFT', product_id INTEGER,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS growth_api_usage (
                    day TEXT NOT NULL, provider TEXT NOT NULL,
                    calls INTEGER NOT NULL DEFAULT 0, cache_hits INTEGER NOT NULL DEFAULT 0,
                    errors INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(day, provider)
                );
                """
            )

    # ---------------------------------------------------------------- offers --

    @staticmethod
    def _offer(row) -> Dict[str, Any]:
        item = dict(row)
        item["params"] = _loads(item.pop("params_json", None), {})
        item["active"] = bool(item.get("active"))
        return item

    def create_offer(self, *, owner_type: str, owner_id: str, rule_type: str, params: Dict[str, Any],
                     title: str = "", scope: str = "all", scope_value: str | None = None,
                     starts_at: str | None = None, ends_at: str | None = None) -> Dict[str, Any]:
        now = _now()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO growth_offers(owner_type,owner_id,scope,scope_value,title,rule_type,params_json,"
                "starts_at,ends_at,active,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,1,?,?)",
                (owner_type, owner_id, scope, scope_value, title, rule_type, json.dumps(params),
                 starts_at, ends_at, now, now),
            )
            row = conn.execute("SELECT * FROM growth_offers WHERE id=?", (cur.lastrowid,)).fetchone()
        return self._offer(row)

    def get_offer(self, offer_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM growth_offers WHERE id=?", (int(offer_id),)).fetchone()
        return self._offer(row) if row else None

    def set_offer_active(self, offer_id: int, active: bool) -> bool:
        with self._connect() as conn:
            cur = conn.execute("UPDATE growth_offers SET active=?, updated_at=? WHERE id=?",
                               (1 if active else 0, _now(), int(offer_id)))
            return cur.rowcount > 0

    def offers(self, *, owner_type: str | None = None, owner_id: str | None = None,
               active_only: bool = False) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM growth_offers WHERE 1=1", []
        if owner_type:
            sql += " AND owner_type=?"
            args.append(owner_type)
        if owner_id:
            sql += " AND owner_id=?"
            args.append(owner_id)
        if active_only:
            sql += " AND active=1"
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY id DESC LIMIT 500", tuple(args)).fetchall()
        return [self._offer(r) for r in rows]

    def offers_for_listing(self, listing: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Active offers that can apply to one listing: the seller's own
        (whole shop, this listing, or its category) plus admin campaigns."""
        seller = str(listing.get("seller_user_id") or "")
        category = str(listing.get("category_tag") or "").strip().casefold()
        out = []
        for offer in self.offers(active_only=True):
            if offer["owner_type"] == "seller" and offer["owner_id"] != seller:
                continue
            scope, value = offer["scope"], str(offer.get("scope_value") or "").strip().casefold()
            if scope == "listing" and value != str(listing.get("id")):
                continue
            if scope == "category" and (not category or value != category):
                continue
            out.append(offer)
        return out

    # ------------------------------------------------- participants / rewards --

    def add_participant(self, context_type: str, context_id: Any, user_id: str, role: str,
                        added_by: str | None = None) -> bool:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT OR IGNORE INTO growth_participants(context_type,context_id,user_id,role,added_by,created_at)"
                " VALUES(?,?,?,?,?,?)",
                (context_type, str(context_id), user_id, role, added_by, _now()),
            )
            return cur.rowcount == 1

    def participants(self, context_type: str, context_id: Any) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM growth_participants WHERE context_type=? AND context_id=? ORDER BY id",
                (context_type, str(context_id)),
            ).fetchall()
        return [dict(r) for r in rows]

    def set_reward_rule(self, role: str, *, percent: float | None, amount: float | None, active: bool = True) -> None:
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO growth_reward_rules(role,percent,amount,active,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(role) DO UPDATE SET percent=excluded.percent, amount=excluded.amount, "
                "active=excluded.active, updated_at=excluded.updated_at",
                (role, percent, amount, 1 if active else 0, _now()),
            )

    def reward_rules(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM growth_reward_rules ORDER BY role").fetchall()]

    def accrue_rewards(self, context_type: str, context_id: Any, deal_value: float) -> List[Dict[str, Any]]:
        """When a deal completes: one PENDING ledger row per value-adding
        participant whose role has an active admin rule. Idempotent."""
        rules = {r["role"]: r for r in self.reward_rules() if r.get("active")}
        created = []
        now = _now()
        for participant in self.participants(context_type, context_id):
            rule = rules.get(participant["role"])
            if participant["role"] not in REWARDABLE_ROLES or not rule:
                continue
            amount = float(rule.get("amount") or 0) + float(deal_value or 0) * float(rule.get("percent") or 0) / 100
            amount = round(amount, 2)
            if amount <= 0:
                continue
            label = f"{rule.get('percent') or 0:g}% + ₹{rule.get('amount') or 0:g}"
            with self._connect() as conn:
                cur = conn.execute(
                    "INSERT OR IGNORE INTO growth_rewards(participant_user_id,role,context_type,context_id,rule,"
                    "amount,status,created_at,updated_at) VALUES(?,?,?,?,?,?,'PENDING',?,?)",
                    (participant["user_id"], participant["role"], context_type, str(context_id), label, amount, now, now),
                )
                if cur.rowcount == 1:
                    created.append({"id": cur.lastrowid, "participant_user_id": participant["user_id"],
                                    "role": participant["role"], "amount": amount, "status": "PENDING"})
        return created

    def cancel_rewards(self, context_type: str, context_id: Any, note: str) -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE growth_rewards SET status='CANCELLED', note=?, updated_at=? "
                "WHERE context_type=? AND context_id=? AND status IN ('PENDING','APPROVED')",
                (note, _now(), context_type, str(context_id)),
            )
            return cur.rowcount

    def rewards(self, *, user_id: str | None = None, status: str | None = None) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM growth_rewards WHERE 1=1", []
        if user_id:
            sql += " AND participant_user_id=?"
            args.append(user_id)
        if status:
            sql += " AND status=?"
            args.append(status)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY id DESC LIMIT 500", tuple(args)).fetchall()]

    _REWARD_NEXT = {"PENDING": {"APPROVED", "CANCELLED"}, "APPROVED": {"PAID", "CANCELLED"}}

    def set_reward_status(self, reward_id: int, status: str, note: str = "") -> Dict[str, Any]:
        status = status.upper()
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM growth_rewards WHERE id=?", (int(reward_id),)).fetchone()
            if not row:
                raise KeyError(reward_id)
            if status not in self._REWARD_NEXT.get(row["status"], set()):
                raise ValueError(f"A {row['status']} reward cannot become {status}")
            conn.execute("UPDATE growth_rewards SET status=?, note=?, updated_at=? WHERE id=?",
                         (status, note or row["note"], _now(), int(reward_id)))
            return dict(conn.execute("SELECT * FROM growth_rewards WHERE id=?", (int(reward_id),)).fetchone())

    # -------------------------------------------------------------- referrals --

    REFERRALS_PER_DAY = 20      # invites one person can create per 24 h
    REVIEW_REGISTRATIONS_PER_DAY = 5  # more registrations than this in 24 h -> admin review

    def referrals_created_since(self, referrer_user_id: str, since: str) -> int:
        with self._connect() as conn:
            return int(conn.execute("SELECT COUNT(*) FROM growth_referrals WHERE referrer_user_id=? AND "
                                    "created_at >= ?", (referrer_user_id, since)).fetchone()[0])

    def create_referral(self, referrer_user_id: str, *, invitee_name: str = "", category: str = "",
                        area: str = "", deal_id: str | None = None) -> Dict[str, Any]:
        now = _now()
        from datetime import datetime as _dt, timedelta as _td

        since = (_dt.fromisoformat(now) - _td(days=1)).isoformat()
        if self.referrals_created_since(referrer_user_id, since) >= self.REFERRALS_PER_DAY:
            raise ValueError("referral_limit")
        code = "ASK" + secrets.token_hex(3).upper()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO growth_referrals(code,referrer_user_id,invitee_name,category,area,deal_id,status,"
                "created_at,updated_at) VALUES(?,?,?,?,?,?,'INVITED',?,?)",
                (code, referrer_user_id, invitee_name[:80], category[:80], area[:80], deal_id, now, now),
            )
            return dict(conn.execute("SELECT * FROM growth_referrals WHERE code=?", (code,)).fetchone())

    def referral(self, code: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM growth_referrals WHERE code=?", (str(code).strip().upper(),)).fetchone()
        return dict(row) if row else None

    def redeem_referral(self, code: str, registered_user_id: str) -> Optional[Dict[str, Any]]:
        """The invitee registered (listed / joined) with the code."""
        ref = self.referral(code)
        if not ref or ref["status"] != "INVITED" or ref["referrer_user_id"] == registered_user_id:
            return None
        with self._connect() as conn:
            # One person is credited to ONE referrer, once.
            if conn.execute("SELECT 1 FROM growth_referrals WHERE registered_user_id=?",
                            (registered_user_id,)).fetchone():
                return None
            # No circular referrals: the referrer was not brought in by this user.
            if conn.execute("SELECT 1 FROM growth_referrals WHERE registered_user_id=? AND referrer_user_id=?",
                            (ref["referrer_user_id"], registered_user_id)).fetchone():
                return None
            conn.execute("UPDATE growth_referrals SET status='REGISTERED', registered_user_id=?, updated_at=? "
                         "WHERE id=?", (registered_user_id, _now(), ref["id"]))
        return self.referral(code)

    def referral_review_flags(self) -> Dict[str, str]:
        """Referrers whose registrations look unusual (burst in 24 h) --
        shown to admins for review; nothing is blocked automatically."""
        from datetime import datetime as _dt, timedelta as _td

        since = (_dt.fromisoformat(_now()) - _td(days=1)).isoformat()
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT referrer_user_id, COUNT(*) AS n FROM growth_referrals WHERE status='REGISTERED' AND "
                "updated_at >= ? GROUP BY referrer_user_id HAVING n > ?",
                (since, self.REVIEW_REGISTRATIONS_PER_DAY)).fetchall()
        return {r["referrer_user_id"]: f"{r['n']} registrations in 24 h" for r in rows}

    def referrals(self, *, referrer_user_id: str | None = None) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM growth_referrals", ()
        if referrer_user_id:
            sql, args = sql + " WHERE referrer_user_id=?", (referrer_user_id,)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY id DESC LIMIT 500", args).fetchall()]

    # --------------------------------------------------- plans / subscriptions --

    def upsert_plan(self, code: str, *, name: str, audience: str = "any", price: float = 0,
                    period_days: int = 30, trial_days: int = 0, credits: float = 0,
                    entitlements: Dict[str, Any] | None = None, active: bool = True) -> Dict[str, Any]:
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO growth_plans(code,name,audience,price,period_days,trial_days,credits,entitlements_json,"
                "active,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(code) DO UPDATE SET name=excluded.name,"
                " audience=excluded.audience, price=excluded.price, period_days=excluded.period_days,"
                " trial_days=excluded.trial_days, credits=excluded.credits,"
                " entitlements_json=excluded.entitlements_json, active=excluded.active,"
                " updated_at=excluded.updated_at",
                (code, name, audience, float(price), int(period_days), int(trial_days), float(credits),
                 json.dumps(entitlements or {}), 1 if active else 0, _now()),
            )
        return self.plan(code)  # type: ignore[return-value]

    @staticmethod
    def _plan(row) -> Dict[str, Any]:
        item = dict(row)
        item["entitlements"] = _loads(item.pop("entitlements_json", None), {})
        item["active"] = bool(item.get("active"))
        return item

    def plan(self, code: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM growth_plans WHERE code=?", (code,)).fetchone()
        return self._plan(row) if row else None

    def plans(self, *, active_only: bool = False, audience: str | None = None) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM growth_plans ORDER BY price, code").fetchall()
        out = [self._plan(r) for r in rows]
        if active_only:
            out = [p for p in out if p["active"]]
        if audience:
            out = [p for p in out if p["audience"] in ("any", audience)]
        return out

    def subscribe(self, user_id: str, plan: Dict[str, Any], *, source: str = "app") -> Dict[str, Any]:
        """Free / trial / promotional plans start now; a paid plan without
        a trial waits for payment (no gateway yet) -- never faked ACTIVE."""
        now = datetime.now(timezone.utc)
        if float(plan.get("price") or 0) <= 0 or source == "promotional":
            status, ends = "ACTIVE", now + timedelta(days=int(plan.get("period_days") or 30))
        elif int(plan.get("trial_days") or 0) > 0:
            status, ends = "TRIAL", now + timedelta(days=int(plan["trial_days"]))
        else:
            status, ends = "PENDING_PAYMENT", None
        with self._connect() as conn:
            conn.execute("UPDATE growth_subscriptions SET status='CANCELLED', updated_at=? "
                         "WHERE user_id=? AND status IN ('TRIAL','ACTIVE','PENDING_PAYMENT')", (_now(), user_id))
            cur = conn.execute(
                "INSERT INTO growth_subscriptions(user_id,plan_code,status,starts_at,ends_at,source,created_at,"
                "updated_at) VALUES(?,?,?,?,?,?,?,?)",
                (user_id, plan["code"], status, now.isoformat(), ends.isoformat() if ends else None, source,
                 _now(), _now()),
            )
            sub = dict(conn.execute("SELECT * FROM growth_subscriptions WHERE id=?", (cur.lastrowid,)).fetchone())
        if status in ("ACTIVE", "TRIAL") and float(plan.get("credits") or 0) > 0:
            self.add_credits(user_id, float(plan["credits"]), f"plan:{plan['code']}")
        return sub

    def current_subscription(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM growth_subscriptions WHERE user_id=? AND status IN ('TRIAL','ACTIVE','PENDING_PAYMENT')"
                " ORDER BY id DESC LIMIT 1", (user_id,),
            ).fetchone()
        if not row:
            return None
        sub = dict(row)
        if sub.get("ends_at") and datetime.fromisoformat(sub["ends_at"]) < datetime.now(timezone.utc):
            with self._connect() as conn:
                conn.execute("UPDATE growth_subscriptions SET status='EXPIRED', updated_at=? WHERE id=?",
                             (_now(), sub["id"]))
            return None
        return sub

    def entitlements(self, user_id: str) -> Dict[str, Any]:
        sub = self.current_subscription(user_id)
        plan = self.plan(sub["plan_code"]) if sub and sub["status"] in ("ACTIVE", "TRIAL") else None
        return {"plan": plan["code"] if plan else None, "status": sub["status"] if sub else None,
                "entitlements": dict(plan["entitlements"]) if plan else {},
                "credits": self.credit_balance(user_id)}

    def add_credits(self, user_id: str, delta: float, reason: str) -> float:
        with self._connect() as conn:
            conn.execute("INSERT INTO growth_credits(user_id,delta,reason,created_at) VALUES(?,?,?,?)",
                         (user_id, float(delta), reason[:120], _now()))
        return self.credit_balance(user_id)

    def credit_balance(self, user_id: str) -> float:
        with self._connect() as conn:
            row = conn.execute("SELECT COALESCE(SUM(delta),0) AS b FROM growth_credits WHERE user_id=?",
                               (user_id,)).fetchone()
        return round(float(row["b"] or 0), 2)

    def subscriptions(self, limit: int = 200) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM growth_subscriptions ORDER BY id DESC LIMIT ?", (int(limit),)).fetchall()]

    # ---------------------------------------------------------- catalog drafts --

    def save_draft(self, seller_user_id: str, draft: Dict[str, Any], missing: List[str], source: str) -> Dict[str, Any]:
        now = _now()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO growth_catalog_drafts(seller_user_id,draft_json,missing_json,source,status,created_at,"
                "updated_at) VALUES(?,?,?,?,'DRAFT',?,?)",
                (seller_user_id, json.dumps(draft, ensure_ascii=False), json.dumps(missing), source, now, now),
            )
        return self.draft(cur.lastrowid)  # type: ignore[return-value]

    def draft(self, draft_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM growth_catalog_drafts WHERE id=?", (int(draft_id),)).fetchone()
        if not row:
            return None
        item = dict(row)
        item["draft"] = _loads(item.pop("draft_json"), {})
        item["missing"] = _loads(item.pop("missing_json"), [])
        return item

    def mark_draft(self, draft_id: int, status: str, product_id: int | None = None) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE growth_catalog_drafts SET status=?, product_id=?, updated_at=? WHERE id=?",
                         (status, product_id, _now(), int(draft_id)))

    def drafts(self, *, seller_user_id: str | None = None, limit: int = 200) -> List[Dict[str, Any]]:
        sql, args = "SELECT id FROM growth_catalog_drafts", ()
        if seller_user_id:
            sql, args = sql + " WHERE seller_user_id=?", (seller_user_id,)
        with self._connect() as conn:
            ids = [r["id"] for r in conn.execute(sql + f" ORDER BY id DESC LIMIT {int(limit)}", args).fetchall()]
        return [d for d in (self.draft(i) for i in ids) if d]

    # --------------------------------------------------------------- API usage --

    def record_usage(self, provider: str, calls: int = 0, cache_hits: int = 0, errors: int = 0) -> None:
        day = datetime.now(timezone.utc).date().isoformat()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO growth_api_usage(day,provider,calls,cache_hits,errors) VALUES(?,?,?,?,?) "
                "ON CONFLICT(day,provider) DO UPDATE SET calls=calls+excluded.calls,"
                " cache_hits=cache_hits+excluded.cache_hits, errors=errors+excluded.errors",
                (day, provider, int(calls), int(cache_hits), int(errors)),
            )

    def usage(self, days: int = 30) -> List[Dict[str, Any]]:
        since = (datetime.now(timezone.utc).date() - timedelta(days=int(days))).isoformat()
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM growth_api_usage WHERE day>=? ORDER BY day DESC, provider", (since,)).fetchall()]
