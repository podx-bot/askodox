"""ASKODOX AI Credits -- optional pay-as-you-go for the AI assistant (owner decision 2026-10-27).

Not a wallet: credits are ASKODOX's own prepaid service units. They are spent only on ASKODOX AI features, are never
transferable to another user, never paid out as cash and never used for buyer <-> seller payments (those always go
person to person; see payment_methods.py). Rupee values are shown so the user understands the balance.

* Packs = ``growth_plans`` rows with audience ``ai_credits`` (seeded ONCE, INACTIVE; staff set price / credits /
  on-sale in Growth -> Plans). Bought through the ONE billing flow (billing.py, Razorpay / Cashfree). Credits are added
  ONLY by ``billing.on_payment`` after the gateway confirms PAID -- never because the app says so.
* TEST gateway (sandbox money, billing testers only): credits land in the separate ``test`` balance, labelled TEST, so
  the whole flow can be rehearsed. LIVE credits only after every owner approval (billing.eligibility).
* Ledger ``ai_credit_ledger`` is append-only; every row has a UNIQUE ``ref`` (idempotent: a repeated webhook / retried
  request can never add or deduct twice). Balance = SUM(delta) per user + mode.
* Charging is OFF until staff switch it on and set per-feature rates (paise per use) after checking real costs;
  ``free_per_day`` uses per feature stay free. A charge is RESERVED before the AI call (atomic: never below zero, no
  double spend under concurrency) and released if the AI call produced nothing.
* Refund of a pack (gateway REFUNDED) deducts the pack's credits again (the balance may go negative; spending then
  stops until the next recharge) -- recorded, never hidden.
* AI PLAN (owner 2026-11-26, every number a Command Center setting, ``plan``): every signed-in person gets
  ``daily_free_paise`` of AI use each INDIA day (use it or lose it at midnight IST; ``daily_free_days`` 0 = for ever,
  N = the person's first N days); a use takes the day's free part FIRST, then the pack. The account's FIRST recharge
  gets ``first_bonus_pct`` extra (100 = double, once for ever, a refund never brings it back); after that the first
  recharge of each India day gets ``daily_bonus_pct`` extra and later recharges that day are 1:1. A friend joining
  refills the day's free part once a day. People who paid have no other limit. The free part lives in the ledger as
  mode ``free`` rows (never a balance: only today's rows count).
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional

from app.services import shop_free_core

AUDIENCE = "ai_credits"
FEATURES = ("chat", "reasoning", "voice", "web_search", "image", "radio", "video_study")
# video_study (owner 2026-11-27): the uploader's one-time AI study of their own ASKODOX video. Free (rate 0) until
# staff set a rate; a viewer never pays for it.
# Owner 2026-11-23: the shop's everyday tools (payment voice, quick bill, dues, sales reports) are free for ever --
# they are never a credits feature, never carry a rate, and a reserve for one always answers free.
assert not set(FEATURES) & set(shop_free_core.keys()), "a free-forever shop tool can never be an AI Credits feature"
MODES = ("live", "test")
FREE_MODE = "free"  # the day's free part: ledger rows only, never added to a balance
IST = timezone(timedelta(hours=5, minutes=30))
PLAN_DEFAULTS: Dict[str, Any] = {  # owner 2026-11-26; staff change them in Command Center -> AI ప్లాన్
    "daily_free_paise": 1000,  # ₹10 a day for everyone, recharge or not
    "daily_free_days": 0,  # 0 = for ever; N = only a person's first N days
    "first_bonus_pct": 100,  # the account's first recharge: ₹100 -> ₹200
    "daily_bonus_pct": 10,  # after that, the first recharge of each day
    "friend_refill": True,  # a friend joined -> the day's free part is full again (once a day)
    "play_fee_pct": 15,  # ESTIMATE only: the store's share of a recharge made through Play billing
}
PLAN_LIMITS = {"daily_free_paise": 1_000_00, "daily_free_days": 3650, "first_bonus_pct": 500, "daily_bonus_pct": 100,
               "play_fee_pct": 50}
PACKS = [  # proposed by the owner; price == credits until staff decide a bonus (financial viability first)
    {"code": "ai_credits_100", "name": "AI Credits ₹100", "price": 100.0},
    {"code": "ai_credits_200", "name": "AI Credits ₹200", "price": 200.0},
    {"code": "ai_credits_300", "name": "AI Credits ₹300", "price": 300.0},
    {"code": "ai_credits_500", "name": "AI Credits ₹500", "price": 500.0},
    {"code": "ai_credits_1000", "name": "AI Credits ₹1000", "price": 1000.0},
]
DEFAULT_SETTINGS: Dict[str, Any] = {
    "charging": False,  # nothing is ever deducted until staff turn this on
    "rates_paise": {f: 0 for f in FEATURES},
    "free_per_day": {f: 0 for f in FEATURES},
    # Trial meter (owner 2026-11-24): each signed-in user sees what their AI use WOULD cost (ai_usage_meter.user_usage)
    # while nothing is deducted. Independent of ``charging``. ON by default.
    "show_usage": True,
}
MAX_RATE_PAISE = 100_00  # ₹100 per use is far above any real cost; guards a typo
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS ai_credit_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,"
    " mode TEXT NOT NULL, delta_paise INTEGER NOT NULL, kind TEXT NOT NULL, feature TEXT NOT NULL DEFAULT '',"
    " ref TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_ai_credit_ledger_user ON ai_credit_ledger(user_id, mode)",
    "CREATE TABLE IF NOT EXISTS ai_credit_settings (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL,"
    " updated_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS ai_credit_first_day (user_id TEXT PRIMARY KEY, day TEXT NOT NULL)",
]


class CreditsError(Exception):
    def __init__(self, code: str, status: int = 409, detail: Optional[Dict[str, Any]] = None) -> None:
        super().__init__(code)
        self.code, self.status, self.detail = code, status, detail or {}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _plan_of(data: Any) -> Dict[str, Any]:
    data = data if isinstance(data, dict) else {}
    return {key: (bool(data.get(key, default)) if isinstance(default, bool) else int(data.get(key, default)))
            for key, default in PLAN_DEFAULTS.items()}


def _percent(part: int, whole: int) -> int:
    return max(0, min(100, round(100 * part / whole))) if whole > 0 else 0


def seed_packs(growth: Any) -> None:
    """Store the proposed packs ONCE, INACTIVE; a staff edit is never overwritten."""
    for pack in PACKS:
        if growth.plan(pack["code"]) is None:
            growth.upsert_plan(pack["code"], name=pack["name"], audience=AUDIENCE, price=pack["price"], period_days=0,
                               credits=pack["price"], entitlements={"ai_credits": True}, active=False)


def pack_credits_paise(plan: Dict[str, Any]) -> int:
    credits = float(plan.get("credits") or 0) or float(plan.get("price") or 0)
    return int(round(credits * 100))


class AiCredits:
    def __init__(self, db_path: str, *, clock=_now) -> None:
        self.db_path = db_path
        self.clock = clock
        with closing(sqlite3.connect(db_path)) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------------------------------------------------- settings --
    def settings(self) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT data, updated_by, updated_at FROM ai_credit_settings WHERE id = 1").fetchone()
        data = json.loads(row["data"]) if row else {}
        out = {"charging": bool(data.get("charging", False)),
               "rates_paise": {f: int((data.get("rates_paise") or {}).get(f, 0)) for f in FEATURES},
               "free_per_day": {f: int((data.get("free_per_day") or {}).get(f, 0)) for f in FEATURES},
               "show_usage": bool(data.get("show_usage", DEFAULT_SETTINGS["show_usage"])),
               "plan": _plan_of(data.get("plan"))}
        out["updated_by"] = row["updated_by"] if row else ""
        out["updated_at"] = row["updated_at"] if row else ""
        return out

    def update_settings(self, data: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
        current = self.settings()
        new = {"charging": bool(data.get("charging", current["charging"])),
               "rates_paise": dict(current["rates_paise"]), "free_per_day": dict(current["free_per_day"]),
               "show_usage": bool(data.get("show_usage", current["show_usage"])),
               "plan": dict(current["plan"])}
        for key, value in (data.get("plan") or {}).items():
            if key not in PLAN_DEFAULTS:
                raise CreditsError("unknown_plan_field", 400, {"field": key})
            if isinstance(PLAN_DEFAULTS[key], bool):
                new["plan"][key] = bool(value)
                continue
            number = int(value if value not in (None, "") else 0)  # an empty box = 0 (for the days: for ever)
            if number < 0 or number > PLAN_LIMITS[key]:
                raise CreditsError("out_of_range", 400, {"field": f"plan.{key}", "max": PLAN_LIMITS[key]})
            new["plan"][key] = number
        for key, limit in (("rates_paise", MAX_RATE_PAISE), ("free_per_day", 10_000)):
            for feature, value in (data.get(key) or {}).items():
                if shop_free_core.is_free(feature):
                    raise CreditsError("free_forever", 400, {"feature": feature})
                if feature not in FEATURES:
                    raise CreditsError("unknown_feature", 400, {"feature": feature})
                number = int(value)
                if number < 0 or number > limit:
                    raise CreditsError("out_of_range", 400, {"field": f"{key}.{feature}", "max": limit})
                new[key][feature] = number
        if new["charging"] and not any(new["rates_paise"].values()):
            raise CreditsError("no_rates", 400)
        with closing(self._connect()) as conn:
            conn.execute("INSERT INTO ai_credit_settings(id, data, updated_by, updated_at) VALUES(1, ?, ?, ?)"
                         " ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_by = excluded.updated_by,"
                         " updated_at = excluded.updated_at", (json.dumps(new), actor, self.clock().isoformat()))
        return self.settings()

    # ------------------------------------------------------------ ledger --
    def _insert(self, conn: sqlite3.Connection, user_id: str, mode: str, delta: int, kind: str, ref: str, *,
                feature: str = "", note: str = "") -> bool:
        try:
            conn.execute("INSERT INTO ai_credit_ledger(user_id, mode, delta_paise, kind, feature, ref, note, created_at)"
                         " VALUES(?,?,?,?,?,?,?,?)",
                         (user_id, mode, int(delta), kind, feature, ref, note[:200], self.clock().isoformat()))
            return True
        except sqlite3.IntegrityError:
            return False  # same ref already recorded: idempotent

    @staticmethod
    def _balance(conn: sqlite3.Connection, user_id: str, mode: str) -> int:
        return int(conn.execute("SELECT COALESCE(SUM(delta_paise), 0) FROM ai_credit_ledger WHERE user_id = ? AND"
                                " mode = ?", (user_id, mode)).fetchone()[0])

    def balance(self, user_id: str) -> Dict[str, int]:
        with closing(self._connect()) as conn:
            return {m: self._balance(conn, user_id, m) for m in MODES}

    def topup(self, user_id: str, *, paise: int, purchase_id: str, mode: str) -> bool:
        """Called ONLY from billing.on_payment after a gateway-confirmed PAID. True when newly added. The plan's
        extra (first recharge / first of the day) is added in the same transaction as its own ``bonus`` row."""
        if mode not in MODES or paise <= 0:
            raise CreditsError("bad_topup", 400)
        plan = self.settings()["plan"]
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            pct, why = self._bonus_now(conn, user_id, mode, plan)
            added = self._insert(conn, user_id, mode, paise, "topup", f"topup:{purchase_id}",
                                 note=f"purchase {purchase_id}")
            if added and pct > 0:
                self._insert(conn, user_id, mode, paise * pct // 100, "bonus", f"bonus:{purchase_id}", note=why)
            conn.execute("COMMIT")
            return added
        finally:
            conn.close()

    def _bonus_now(self, conn: sqlite3.Connection, user_id: str, mode: str, plan: Dict[str, Any]) -> tuple:
        """(percent, reason) the NEXT recharge would get. A refunded recharge still counts as made (no second double)."""
        ever = int(conn.execute("SELECT COUNT(*) FROM ai_credit_ledger WHERE user_id = ? AND mode = ? AND kind ="
                                " 'topup'", (user_id, mode)).fetchone()[0])
        if ever == 0:
            return int(plan["first_bonus_pct"]), "first_recharge"
        today = int(conn.execute("SELECT COUNT(*) FROM ai_credit_ledger WHERE user_id = ? AND mode = ? AND kind ="
                                 " 'topup' AND created_at >= ?", (user_id, mode, self._day_start())).fetchone()[0])
        return (int(plan["daily_bonus_pct"]), "daily_first") if today == 0 else (0, "used_today")

    def reverse_topup(self, user_id: str, *, purchase_id: str) -> bool:
        """Gateway REFUNDED: take the pack's credits back (once), and the extra that came with it."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT mode, delta_paise FROM ai_credit_ledger WHERE ref = ?",
                               (f"topup:{purchase_id}",)).fetchone()
            if not row:
                return False
            done = self._insert(conn, user_id, row["mode"], -int(row["delta_paise"]), "refund",
                                f"refund:{purchase_id}", note=f"purchase {purchase_id} refunded")
            bonus = conn.execute("SELECT delta_paise FROM ai_credit_ledger WHERE ref = ?",
                                 (f"bonus:{purchase_id}",)).fetchone()
            if done and bonus:
                self._insert(conn, user_id, row["mode"], -int(bonus["delta_paise"]), "refund",
                             f"refundbonus:{purchase_id}", note=f"extra of purchase {purchase_id} taken back")
            return done

    # ------------------------------------------------------ the day's free --
    def _today(self):
        return self.clock().astimezone(IST).date()

    def _day_start(self, day=None) -> str:
        """The India day's first moment, as the UTC text the ledger stores (rows compare as text)."""
        return datetime.combine(day or self._today(), time.min, IST).astimezone(timezone.utc).isoformat()

    def _free(self, conn: sqlite3.Connection, user_id: str, plan: Dict[str, Any]) -> Dict[str, int]:
        """Today's free part: {total, left, used}. Yesterday's rows never count (use it or lose it)."""
        total = int(plan["daily_free_paise"])
        today = self._today()
        conn.execute("INSERT OR IGNORE INTO ai_credit_first_day(user_id, day) VALUES(?, ?)", (user_id, today.isoformat()))
        days = int(plan["daily_free_days"])
        if total > 0 and days > 0:
            first = conn.execute("SELECT day FROM ai_credit_first_day WHERE user_id = ?", (user_id,)).fetchone()[0]
            if (today - datetime.fromisoformat(first).date()).days >= days:
                total = 0
        if total <= 0:
            return {"total": 0, "left": 0, "used": 0}
        moved = int(conn.execute("SELECT COALESCE(SUM(delta_paise), 0) FROM ai_credit_ledger WHERE user_id = ? AND"
                                 " mode = ? AND created_at >= ?", (user_id, FREE_MODE, self._day_start())).fetchone()[0])
        left = max(0, min(total, total + moved))
        return {"total": total, "left": left, "used": total - left}

    def friend_joined(self, user_id: str) -> bool:
        """A friend this person invited joined: today's free part is full again -- once per India day."""
        settings = self.settings()
        if not settings["plan"]["friend_refill"]:
            return False
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            free = self._free(conn, user_id, settings["plan"])
            done = free["total"] > 0 and self._insert(conn, user_id, FREE_MODE, free["used"], "refill",
                                                      f"refill:{user_id}:{self._today().isoformat()}", note="friend joined")
            conn.execute("COMMIT")
            return bool(done)
        finally:
            conn.close()

    def _used_today(self, conn: sqlite3.Connection, user_id: str, feature: str) -> int:
        return int(conn.execute("SELECT COUNT(*) FROM ai_credit_ledger WHERE user_id = ? AND feature = ? AND kind IN"
                                " ('usage', 'free') AND ref LIKE 'use:%' AND created_at >= ?",
                                (user_id, feature, self._day_start())).fetchone()[0])

    def reserve(self, user_id: str, feature: str, ref: str) -> Dict[str, Any]:
        """Before one AI use. Returns {charged, paise, mode, free}; raises CreditsError('insufficient', 402).
        Atomic (BEGIN IMMEDIATE): two parallel requests can never both spend the last credits."""
        if shop_free_core.is_free(feature):  # payment voice / quick bill / dues / sales reports: free for ever
            return {"charged": False, "reason": "free_forever", "paise": 0}
        if feature not in FEATURES:
            raise CreditsError("unknown_feature", 400)
        settings = self.settings()
        if not settings["charging"]:
            return {"charged": False, "reason": "charging_off", "paise": 0}
        rate = settings["rates_paise"][feature]
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute("SELECT kind, delta_paise, mode FROM ai_credit_ledger WHERE ref = ?",
                                    (f"use:{ref}",)).fetchone()
            if existing:  # retried request: never charged twice
                conn.execute("COMMIT")
                return {"charged": existing["kind"] == "usage", "paise": -int(existing["delta_paise"]),
                        "mode": existing["mode"], "repeat": True}
            if rate <= 0 or self._used_today(conn, user_id, feature) < settings["free_per_day"][feature]:
                self._insert(conn, user_id, "live", 0, "free", f"use:{ref}", feature=feature)
                conn.execute("COMMIT")
                return {"charged": False, "free": True, "paise": 0}
            from_free = min(rate, self._free(conn, user_id, settings["plan"])["left"])  # the day's free FIRST
            rest = rate - from_free
            if rest == 0:
                self._insert(conn, user_id, FREE_MODE, -rate, "usage", f"use:{ref}", feature=feature)
                conn.execute("COMMIT")
                return {"charged": True, "paise": rate, "mode": FREE_MODE, "pack_paise": 0}
            for mode in MODES:  # real credits first, then TEST credits (billing testers rehearsing)
                if self._balance(conn, user_id, mode) >= rest:
                    self._insert(conn, user_id, mode, -rest, "usage", f"use:{ref}", feature=feature)
                    if from_free:
                        self._insert(conn, user_id, FREE_MODE, -from_free, "usage", f"usefree:{ref}", feature=feature)
                    conn.execute("COMMIT")
                    out = {"charged": True, "paise": rate, "mode": mode}
                    return {**out, "pack_paise": rest} if from_free else out
            if from_free:  # the last of today's free part still gives one whole use
                self._insert(conn, user_id, FREE_MODE, -from_free, "usage", f"use:{ref}", feature=feature)
                conn.execute("COMMIT")
                return {"charged": True, "paise": from_free, "mode": FREE_MODE, "pack_paise": 0}
            conn.execute("COMMIT")  # keeps the first-day row
        finally:
            conn.close()
        raise CreditsError("insufficient", 402, {"needed_paise": rate, "balance": self.balance(user_id)})

    def spend(self, user_id: str, paise: int, ref: str, *, feature: str, note: str = "") -> Dict[str, Any]:
        """One charge of any size (e.g. a notification to N people at a few paise each). Free while charging is OFF;
        atomic like ``reserve``; a repeated ``ref`` is never charged twice. Raises CreditsError('insufficient', 402)."""
        if not self.settings()["charging"] or paise <= 0:
            return {"charged": False, "reason": "charging_off" if paise > 0 else "free", "paise": 0}
        conn = self._connect()
        try:
            conn.execute("BEGIN IMMEDIATE")
            if conn.execute("SELECT 1 FROM ai_credit_ledger WHERE ref = ?", (f"use:{ref}",)).fetchone():
                conn.execute("COMMIT")
                return {"charged": True, "paise": paise, "repeat": True}
            for mode in MODES:
                if self._balance(conn, user_id, mode) >= paise:
                    self._insert(conn, user_id, mode, -paise, "usage", f"use:{ref}", feature=feature, note=note)
                    conn.execute("COMMIT")
                    return {"charged": True, "paise": paise, "mode": mode}
            conn.execute("ROLLBACK")
        finally:
            conn.close()
        raise CreditsError("insufficient", 402, {"needed_paise": paise, "balance": self.balance(user_id)})

    def refund_unused(self, user_id: str, ref: str, paise: int, *, feature: str) -> bool:
        """Part of a ``spend`` was not used (e.g. fewer phones reached): give that part back, once."""
        if paise <= 0:
            return False
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT mode FROM ai_credit_ledger WHERE ref = ? AND kind = 'usage'",
                               (f"use:{ref}",)).fetchone()
            if not row:
                return False
            return self._insert(conn, user_id, row["mode"], paise, "release", f"release:{ref}", feature=feature,
                                note="not delivered")

    def release(self, user_id: str, ref: str) -> bool:
        """The AI call produced nothing: give the reserved charge back (once)."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT mode, delta_paise, feature, kind FROM ai_credit_ledger WHERE ref = ?",
                               (f"use:{ref}",)).fetchone()
            if not row or row["kind"] != "usage":
                return False
            part = conn.execute("SELECT delta_paise FROM ai_credit_ledger WHERE ref = ?", (f"usefree:{ref}",)).fetchone()
            if part:  # the free part of a use paid from both
                self._insert(conn, user_id, FREE_MODE, -int(part["delta_paise"]), "release", f"releasefree:{ref}",
                             feature=row["feature"], note="AI gave no answer")
            return self._insert(conn, user_id, row["mode"], -int(row["delta_paise"]), "release",
                                f"release:{ref}", feature=row["feature"], note="AI gave no answer")

    def history(self, user_id: str, *, limit: int = 100) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT id, mode, delta_paise, kind, feature, note, created_at FROM ai_credit_ledger"
                                " WHERE user_id = ? AND kind != 'free' AND mode != ? ORDER BY id DESC LIMIT ?",
                                (user_id, FREE_MODE, int(limit))).fetchall()
        return [dict(r) for r in rows]

    def usage_today(self, user_id: str) -> Dict[str, int]:
        with closing(self._connect()) as conn:
            return {f: self._used_today(conn, user_id, f) for f in FEATURES}

    def status(self, user_id: str) -> Dict[str, Any]:
        """What the person's AI screen shows: two bars in PERCENT (today's free, my pack), a pace warning, and
        whether the next recharge carries an extra. Rupees are for the recharge screen only."""
        settings = self.settings()
        plan = settings["plan"]
        now = self.clock()
        midnight = datetime.combine(self._today() + timedelta(days=1), time.min, IST)
        with closing(self._connect()) as conn:
            free = self._free(conn, user_id, plan)
            mode = "live" if self._balance(conn, user_id, "live") > 0 or self._balance(conn, user_id, "test") <= 0 \
                else "test"
            balance = self._balance(conn, user_id, mode)
            last = conn.execute("SELECT MAX(id) FROM ai_credit_ledger WHERE user_id = ? AND mode = ? AND kind IN"
                                " ('topup', 'bonus')", (user_id, mode)).fetchone()[0]
            base = int(conn.execute("SELECT COALESCE(SUM(delta_paise), 0) FROM ai_credit_ledger WHERE user_id = ? AND"
                                    " mode = ? AND id <= ?", (user_id, mode, last)).fetchone()[0]) if last else 0
            week = self._day_start(self._today() - timedelta(days=6))
            spent = -int(conn.execute("SELECT COALESCE(SUM(delta_paise), 0) FROM ai_credit_ledger WHERE user_id = ? AND"
                                      " mode = ? AND kind IN ('usage', 'release') AND created_at >= ?",
                                      (user_id, mode, week)).fetchone()[0])
            first = conn.execute("SELECT MIN(created_at) FROM ai_credit_ledger WHERE user_id = ? AND mode = ? AND kind ="
                                 " 'usage' AND created_at >= ?", (user_id, mode, week)).fetchone()[0]
            pct, why = self._bonus_now(conn, user_id, "live", plan)
            conn.commit()
        out_free = {"percent_left": _percent(free["left"], free["total"]), "on": free["total"] > 0,
                    "resets_at": midnight.isoformat(), "runs_out_at": None}
        since = (now.astimezone(IST) - datetime.combine(self._today(), time.min, IST)).total_seconds()
        if free["used"] > 0 and free["left"] > 0 and since > 0:  # at this pace, before midnight?
            ends = now + timedelta(seconds=free["left"] * since / free["used"])
            if ends < midnight:
                out_free["runs_out_at"] = ends.astimezone(IST).isoformat()
        pack = {"percent_left": _percent(balance, base), "has": balance > 0, "test": mode == "test", "days_left": None}
        if spent > 0 and balance > 0 and first:
            days = max(1.0, (now - datetime.fromisoformat(first)).total_seconds() / 86400)
            pack["days_left"] = int(balance / (spent / days))
        return {"charging": settings["charging"], "free": out_free, "pack": pack,
                "bonus": {"percent": pct, "kind": why, "left_today": pct > 0}}

    def plan_estimate(self, *, days: int = 7) -> Dict[str, Any]:
        """Command Center "AI ప్లాన్": what the plan gave away and brought in over the last days (ledger facts; the
        free part is counted at the RATES people are charged, so it is the value given, not ASKODOX's own AI bill)."""
        days = max(1, min(int(days), 90))
        plan = self.settings()["plan"]
        since = self._day_start(self._today() - timedelta(days=days - 1))
        with closing(self._connect()) as conn:
            people, used = conn.execute("SELECT COUNT(DISTINCT user_id), COALESCE(-SUM(delta_paise), 0) FROM"
                                        " ai_credit_ledger WHERE mode = ? AND kind IN ('usage', 'release') AND"
                                        " created_at >= ?", (FREE_MODE, since)).fetchone()
            sums = {r[0]: (r[1], r[2]) for r in conn.execute(
                "SELECT kind, COUNT(*), COALESCE(SUM(delta_paise), 0) FROM ai_credit_ledger WHERE mode = 'live' AND kind"
                " IN ('topup', 'bonus', 'refund') AND created_at >= ? GROUP BY kind", (since,))}
            refills = conn.execute("SELECT COUNT(*) FROM ai_credit_ledger WHERE mode = ? AND kind = 'refill' AND"
                                   " created_at >= ?", (FREE_MODE, since)).fetchone()[0]
        paid = sums.get("topup", (0, 0))[1]
        return {"days": days, "plan": plan, "estimate": True,
                "free": {"people": int(people or 0), "used_paise": int(used or 0),
                         "most_paise": int(people or 0) * int(plan["daily_free_paise"]) * days, "refills": int(refills)},
                "recharges": {"count": sums.get("topup", (0, 0))[0], "paid_paise": int(paid),
                              "extra_given_paise": int(sums.get("bonus", (0, 0))[1]),
                              "refunded_paise": -int(sums.get("refund", (0, 0))[1]),
                              "store_fee_paise": int(paid) * int(plan["play_fee_pct"]) // 100}}

    def summary(self) -> Dict[str, Any]:
        """Staff reconciliation: totals per mode and kind (rupee values; no user detail)."""
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT mode, kind, COUNT(*) AS n, COALESCE(SUM(delta_paise), 0) AS paise FROM"
                                " ai_credit_ledger GROUP BY mode, kind").fetchall()
            users = conn.execute("SELECT COUNT(DISTINCT user_id) FROM ai_credit_ledger WHERE kind = 'topup'").fetchone()[0]
            negative = conn.execute("SELECT COUNT(*) FROM (SELECT user_id, mode, SUM(delta_paise) AS b FROM"
                                    " ai_credit_ledger WHERE mode != 'free' GROUP BY user_id, mode HAVING b < 0)").fetchone()[0]
        by: Dict[str, Dict[str, Any]] = {m: {} for m in MODES}
        for r in rows:
            by.setdefault(r["mode"], {})[r["kind"]] = {"count": r["n"], "paise": r["paise"]}
        outstanding = {m: sum(v["paise"] for v in by.get(m, {}).values()) for m in MODES}
        return {"by_mode": by, "outstanding_paise": outstanding, "buyers": users, "negative_balances": negative}
