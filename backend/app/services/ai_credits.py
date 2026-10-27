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
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

AUDIENCE = "ai_credits"
FEATURES = ("chat", "reasoning", "voice", "web_search", "image")
MODES = ("live", "test")
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
}
MAX_RATE_PAISE = 100_00  # ₹100 per use is far above any real cost; guards a typo
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS ai_credit_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,"
    " mode TEXT NOT NULL, delta_paise INTEGER NOT NULL, kind TEXT NOT NULL, feature TEXT NOT NULL DEFAULT '',"
    " ref TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_ai_credit_ledger_user ON ai_credit_ledger(user_id, mode)",
    "CREATE TABLE IF NOT EXISTS ai_credit_settings (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL,"
    " updated_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)",
]


class CreditsError(Exception):
    def __init__(self, code: str, status: int = 409, detail: Optional[Dict[str, Any]] = None) -> None:
        super().__init__(code)
        self.code, self.status, self.detail = code, status, detail or {}


def _now() -> datetime:
    return datetime.now(timezone.utc)


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
               "free_per_day": {f: int((data.get("free_per_day") or {}).get(f, 0)) for f in FEATURES}}
        out["updated_by"] = row["updated_by"] if row else ""
        out["updated_at"] = row["updated_at"] if row else ""
        return out

    def update_settings(self, data: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
        current = self.settings()
        new = {"charging": bool(data.get("charging", current["charging"])),
               "rates_paise": dict(current["rates_paise"]), "free_per_day": dict(current["free_per_day"])}
        for key, limit in (("rates_paise", MAX_RATE_PAISE), ("free_per_day", 10_000)):
            for feature, value in (data.get(key) or {}).items():
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
        """Called ONLY from billing.on_payment after a gateway-confirmed PAID. True when newly added."""
        if mode not in MODES or paise <= 0:
            raise CreditsError("bad_topup", 400)
        with closing(self._connect()) as conn:
            return self._insert(conn, user_id, mode, paise, "topup", f"topup:{purchase_id}",
                                note=f"purchase {purchase_id}")

    def reverse_topup(self, user_id: str, *, purchase_id: str) -> bool:
        """Gateway REFUNDED: take the pack's credits back (once)."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT mode, delta_paise FROM ai_credit_ledger WHERE ref = ?",
                               (f"topup:{purchase_id}",)).fetchone()
            if not row:
                return False
            return self._insert(conn, user_id, row["mode"], -int(row["delta_paise"]), "refund",
                                f"refund:{purchase_id}", note=f"purchase {purchase_id} refunded")

    def _used_today(self, conn: sqlite3.Connection, user_id: str, feature: str) -> int:
        day = self.clock().date().isoformat()
        return int(conn.execute("SELECT COUNT(*) FROM ai_credit_ledger WHERE user_id = ? AND feature = ? AND kind IN"
                                " ('usage', 'free') AND substr(created_at, 1, 10) = ?",
                                (user_id, feature, day)).fetchone()[0])

    def reserve(self, user_id: str, feature: str, ref: str) -> Dict[str, Any]:
        """Before one AI use. Returns {charged, paise, mode, free}; raises CreditsError('insufficient', 402).
        Atomic (BEGIN IMMEDIATE): two parallel requests can never both spend the last credits."""
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
            for mode in MODES:  # real credits first, then TEST credits (billing testers rehearsing)
                if self._balance(conn, user_id, mode) >= rate:
                    self._insert(conn, user_id, mode, -rate, "usage", f"use:{ref}", feature=feature)
                    conn.execute("COMMIT")
                    return {"charged": True, "paise": rate, "mode": mode}
            conn.execute("ROLLBACK")
        finally:
            conn.close()
        raise CreditsError("insufficient", 402, {"needed_paise": rate, "balance": self.balance(user_id)})

    def release(self, user_id: str, ref: str) -> bool:
        """The AI call produced nothing: give the reserved charge back (once)."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT mode, delta_paise, feature, kind FROM ai_credit_ledger WHERE ref = ?",
                               (f"use:{ref}",)).fetchone()
            if not row or row["kind"] != "usage":
                return False
            return self._insert(conn, user_id, row["mode"], -int(row["delta_paise"]), "release",
                                f"release:{ref}", feature=row["feature"], note="AI gave no answer")

    def history(self, user_id: str, *, limit: int = 100) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT id, mode, delta_paise, kind, feature, note, created_at FROM ai_credit_ledger"
                                " WHERE user_id = ? AND kind != 'free' ORDER BY id DESC LIMIT ?",
                                (user_id, int(limit))).fetchall()
        return [dict(r) for r in rows]

    def usage_today(self, user_id: str) -> Dict[str, int]:
        with closing(self._connect()) as conn:
            return {f: self._used_today(conn, user_id, f) for f in FEATURES}

    def summary(self) -> Dict[str, Any]:
        """Staff reconciliation: totals per mode and kind (rupee values; no user detail)."""
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT mode, kind, COUNT(*) AS n, COALESCE(SUM(delta_paise), 0) AS paise FROM"
                                " ai_credit_ledger GROUP BY mode, kind").fetchall()
            users = conn.execute("SELECT COUNT(DISTINCT user_id) FROM ai_credit_ledger WHERE kind = 'topup'").fetchone()[0]
            negative = conn.execute("SELECT COUNT(*) FROM (SELECT user_id, mode, SUM(delta_paise) AS b FROM"
                                    " ai_credit_ledger GROUP BY user_id, mode HAVING b < 0)").fetchone()[0]
        by: Dict[str, Dict[str, Any]] = {m: {} for m in MODES}
        for r in rows:
            by.setdefault(r["mode"], {})[r["kind"]] = {"count": r["n"], "paise": r["paise"]}
        outstanding = {m: sum(v["paise"] for v in by.get(m, {}).values()) for m in MODES}
        return {"by_mode": by, "outstanding_paise": outstanding, "buyers": users, "negative_balances": negative}
