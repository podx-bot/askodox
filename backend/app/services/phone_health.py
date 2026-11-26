"""Phone health reports (owner 2026-11-26, design 56PnG1xhJvNEbG8q3PGE1d boards 1-2 + Command Center).

The app checks ONLY ITS OWN settings on the phone (its notification switch, its battery rule, its payment-voice
access, its voice) and walks the person through fixing each one on the phone maker's own settings page. It never
reads other apps, messages or photos, and it never taps settings for the person (no Accessibility automation: a
Google Play rule).

A report reaches ASKODOX only when the person presses "పంపు" -- every single time (``consent`` must be true in that
request; nothing is sent in the background). What is kept: the phone maker, Android version, app build, and the
fixed check ids with ok / not ok. No free text from the phone, no phone model serial, no notification content.
The person's sign-in number is shown to staff masked (last 4).
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List

# The only things a report may carry. An id outside this list is dropped (a newer app can add one here first).
CHECKS = ("notifications", "battery", "autostart", "payment_access", "payment_alive", "voice", "voice_language",
          "volume", "internet", "pending_upload")
STATES = ("ok", "bad", "unknown")
WHY = ("payment_voice_missing", "setup_stuck", "user_asked", "")
MAX_PER_DAY = 5
KEEP_DAYS = 90
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS phone_health_reports (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,"
    " maker TEXT NOT NULL DEFAULT '', android TEXT NOT NULL DEFAULT '', app_build TEXT NOT NULL DEFAULT '',"
    " why TEXT NOT NULL DEFAULT '', checks TEXT NOT NULL, bad INTEGER NOT NULL DEFAULT 0, at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_phone_health_at ON phone_health_reports(at)",
]


class PhoneHealthError(Exception):
    def __init__(self, code: str, status: int = 400) -> None:
        super().__init__(code)
        self.code, self.status = code, status


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _word(value: Any, limit: int) -> str:
    """Letters, digits, dot, dash, space only: a report can never smuggle text in."""
    return "".join(ch for ch in str(value or "") if ch.isalnum() or ch in ".- ")[:limit].strip().lower()


def mask_user(user: Any) -> str:
    digits = "".join(ch for ch in str(user or "") if ch.isdigit())
    return ("••••" + digits[-4:]) if len(digits) >= 4 else "user"


class PhoneHealth:
    def __init__(self, db_path: str, *, clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.clock = clock
        with closing(sqlite3.connect(db_path)) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def report(self, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        if data.get("consent") is not True:  # the person pressed "పంపు" for THIS report
            raise PhoneHealthError("consent_needed", 400)
        checks: Dict[str, str] = {}
        for key, state in (data.get("checks") or {}).items():
            if key in CHECKS and state in STATES:
                checks[key] = state
        if not checks:
            raise PhoneHealthError("no_checks", 400)
        now = self.clock()
        with closing(self._connect()) as conn:
            today = conn.execute("SELECT COUNT(*) FROM phone_health_reports WHERE user_id = ? AND at >= ?",
                                 (user, (now - timedelta(days=1)).isoformat())).fetchone()[0]
            if today >= MAX_PER_DAY:
                raise PhoneHealthError("too_many", 429)
            conn.execute("DELETE FROM phone_health_reports WHERE at < ?", ((now - timedelta(days=KEEP_DAYS)).isoformat(),))
            why = data.get("why") if data.get("why") in WHY else ""
            cursor = conn.execute(
                "INSERT INTO phone_health_reports(user_id, maker, android, app_build, why, checks, bad, at)"
                " VALUES(?,?,?,?,?,?,?,?)",
                (user, _word(data.get("maker"), 24), _word(data.get("android"), 8), _word(data.get("app_build"), 12), why,
                 json.dumps(checks, sort_keys=True), sum(1 for s in checks.values() if s == "bad"), now.isoformat()))
            conn.commit()
        return {"id": cursor.lastrowid, "kept": sorted(checks), "bad": sum(1 for s in checks.values() if s == "bad")}

    def forget(self, user: str) -> int:
        """Account deleted: its reports go too."""
        with closing(self._connect()) as conn:
            count = conn.execute("DELETE FROM phone_health_reports WHERE user_id = ?", (user,)).rowcount
            conn.commit()
        return int(count)

    def overview(self, *, days: int = 30, limit: int = 100) -> Dict[str, Any]:
        """Command Center "Phone reports": what breaks on which maker's phones, and the newest reports."""
        days = max(1, min(int(days), KEEP_DAYS))
        since = (self.clock() - timedelta(days=days)).isoformat()
        with closing(self._connect()) as conn:
            rows = [dict(r) for r in conn.execute("SELECT id, user_id, maker, android, app_build, why, checks, bad, at"
                                                  " FROM phone_health_reports WHERE at >= ? ORDER BY id DESC", (since,))]
        by_check: Dict[str, int] = {}
        by_maker: Dict[str, Dict[str, Any]] = {}
        newest: List[Dict[str, Any]] = []
        for row in rows:
            checks = json.loads(row["checks"])
            failing = sorted(k for k, s in checks.items() if s == "bad")
            maker = by_maker.setdefault(row["maker"] or "unknown", {"maker": row["maker"] or "unknown", "reports": 0,
                                                                   "with_problem": 0, "checks": {}})
            maker["reports"] += 1
            maker["with_problem"] += 1 if failing else 0
            for key in failing:
                by_check[key] = by_check.get(key, 0) + 1
                maker["checks"][key] = maker["checks"].get(key, 0) + 1
            if len(newest) < limit:
                newest.append({"id": row["id"], "user": mask_user(row["user_id"]), "maker": row["maker"],
                               "android": row["android"], "app_build": row["app_build"], "why": row["why"],
                               "failing": failing, "at": row["at"]})
        makers = sorted(by_maker.values(), key=lambda m: -m["with_problem"])
        for maker in makers:
            maker["top"] = max(maker["checks"], key=maker["checks"].get) if maker["checks"] else ""
        return {"days": days, "reports": len(rows), "with_problem": sum(1 for r in rows if r["bad"]),
                "by_check": sorted(({"check": k, "count": v} for k, v in by_check.items()), key=lambda x: -x["count"]),
                "by_maker": makers, "newest": newest}
