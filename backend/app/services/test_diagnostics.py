"""Test Mode Diagnostics (owner request 2026-10-29).

When the owner tests ASKODOX on a phone, Claude should see what happened
without asking for screenshots. A STAFF member's app (never a customer's) can
turn Test Mode on for itself; while it is on (it expires by itself after
``TEST_MODE_HOURS``) the app sends small, allow-listed events:

  screen  -- a page was opened (route path)
  send    -- a chat turn was sent (typed / voice, length, the text masked)
  reply   -- the assistant answered (mode, grounding verified, honesty guard)
  voice   -- how a reply was spoken (engine: server audio vs device fallback)
  guide   -- what a guide SHOWED next to what it SPOKE
  tap     -- a named button / action
  search  -- results shown (counts per section)
  error   -- an app error (first line, masked)
  note    -- anything else the app wants to record

Every text value goes through ``pii_mask.mask_sensitive`` and is cut short;
events older than ``RETENTION_DAYS`` are deleted; nothing is stored when Test
Mode is off. Staff with ``qa:view`` read the events (``/admin/cc/test-mode``),
so a read-only staff token can be given to the CI reader workflow.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

from app.services.pii_mask import mask_sensitive

KINDS = ("screen", "send", "reply", "voice", "guide", "tap", "search", "error", "note")
TEST_MODE_HOURS = 7 * 24
RETENTION_DAYS = 14
MAX_EVENTS_PER_CALL = 50
MAX_DETAIL_KEYS = 20
MAX_VALUE_CHARS = 600


def now() -> datetime:
    return datetime.now(timezone.utc)


def user_ref(app_user: str) -> str:
    """A stable short reference instead of the phone-based id."""
    return hashlib.sha256(f"testmode:{app_user}".encode()).hexdigest()[:12] if app_user else ""


def _clean_value(value: Any) -> Any:
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, (list, tuple)):
        return [_clean_value(v) for v in list(value)[:10]]
    if isinstance(value, dict):
        return {str(k)[:40]: _clean_value(v) for k, v in list(value.items())[:10]}
    return mask_sensitive(str(value))[:MAX_VALUE_CHARS]


def clean_event(raw: dict[str, Any]) -> dict[str, Any] | None:
    kind = str(raw.get("kind") or "").strip().lower()
    if kind not in KINDS:
        return None
    detail = raw.get("detail") if isinstance(raw.get("detail"), dict) else {}
    clean_detail = {str(k)[:40]: _clean_value(v) for k, v in list(detail.items())[:MAX_DETAIL_KEYS]}
    at = str(raw.get("at") or "")[:40]
    return {
        "kind": kind,
        "screen": mask_sensitive(str(raw.get("screen") or ""))[:120],
        "at": at,
        "detail": clean_detail,
    }


@dataclass
class TestDiagnosticsStore:
    db_path: str

    def __post_init__(self) -> None:
        with self._connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS test_mode_testers ("
                "app_user_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0, staff_name TEXT NOT NULL DEFAULT '', "
                "enabled_at TEXT, expires_at TEXT, updated_at TEXT NOT NULL)")
            conn.execute(
                "CREATE TABLE IF NOT EXISTS test_mode_events ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, user_ref TEXT NOT NULL, session TEXT NOT NULL DEFAULT '', "
                "kind TEXT NOT NULL, screen TEXT NOT NULL DEFAULT '', at TEXT NOT NULL DEFAULT '', "
                "app_version TEXT NOT NULL DEFAULT '', detail_json TEXT NOT NULL DEFAULT '{}', received_at TEXT NOT NULL)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_test_mode_events_received ON test_mode_events(received_at)")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------------------------------------------------------- state --
    def status(self, app_user: str, at: datetime | None = None) -> dict[str, Any]:
        moment = at or now()
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM test_mode_testers WHERE app_user_id=?", (app_user,)).fetchone()
        if row is None or not row["enabled"]:
            return {"enabled": False, "expires_at": None}
        expires = row["expires_at"]
        if expires and datetime.fromisoformat(expires) <= moment:
            return {"enabled": False, "expires_at": expires, "expired": True}
        return {"enabled": True, "expires_at": expires}

    def set_enabled(self, app_user: str, enabled: bool, *, staff_name: str = "",
                    hours: int = TEST_MODE_HOURS, at: datetime | None = None) -> dict[str, Any]:
        moment = at or now()
        hours = max(1, min(int(hours), TEST_MODE_HOURS))
        expires = (moment + timedelta(hours=hours)).isoformat() if enabled else None
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO test_mode_testers(app_user_id, enabled, staff_name, enabled_at, expires_at, updated_at) "
                "VALUES(?,?,?,?,?,?) ON CONFLICT(app_user_id) DO UPDATE SET enabled=excluded.enabled, "
                "staff_name=excluded.staff_name, enabled_at=excluded.enabled_at, expires_at=excluded.expires_at, "
                "updated_at=excluded.updated_at",
                (app_user, 1 if enabled else 0, staff_name[:80], moment.isoformat() if enabled else None, expires,
                 moment.isoformat()))
        return self.status(app_user, moment)

    # --------------------------------------------------------------- events --
    def record(self, app_user: str, events: Iterable[dict[str, Any]], *, session: str = "", app_version: str = "",
               at: datetime | None = None) -> dict[str, Any]:
        moment = at or now()
        if not self.status(app_user, moment)["enabled"]:
            return {"stored": 0, "enabled": False}
        rows = []
        for raw in list(events or [])[:MAX_EVENTS_PER_CALL]:
            event = clean_event(raw) if isinstance(raw, dict) else None
            if event is None:
                continue
            rows.append((user_ref(app_user), session[:40], event["kind"], event["screen"], event["at"],
                         app_version[:40], json.dumps(event["detail"], ensure_ascii=False)[:6000], moment.isoformat()))
        with self._connect() as conn:
            conn.executemany(
                "INSERT INTO test_mode_events(user_ref, session, kind, screen, at, app_version, detail_json, received_at) "
                "VALUES(?,?,?,?,?,?,?,?)", rows)
            conn.execute("DELETE FROM test_mode_events WHERE received_at < ?",
                         ((moment - timedelta(days=RETENTION_DAYS)).isoformat(),))
        return {"stored": len(rows), "enabled": True}

    def events(self, *, since_minutes: int = 180, kind: str = "", ref: str = "", limit: int = 300,
               at: datetime | None = None) -> list[dict[str, Any]]:
        moment = at or now()
        since = (moment - timedelta(minutes=max(1, min(int(since_minutes), RETENTION_DAYS * 24 * 60)))).isoformat()
        sql = "SELECT * FROM test_mode_events WHERE received_at >= ?"
        params: list[Any] = [since]
        if kind:
            sql += " AND kind = ?"
            params.append(kind)
        if ref:
            sql += " AND user_ref = ?"
            params.append(ref)
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(max(1, min(int(limit), 2000)))
        with self._connect() as conn:
            rows = conn.execute(sql, params).fetchall()
        out = []
        for row in reversed(rows):
            item = dict(row)
            item["detail"] = json.loads(item.pop("detail_json") or "{}")
            out.append(item)
        return out

    def summary(self, events: list[dict[str, Any]]) -> dict[str, Any]:
        """What a reader needs first: counts, voice engines, honesty hits, errors."""
        kinds: dict[str, int] = {}
        engines: dict[str, int] = {}
        honesty = 0
        unverified = 0
        mismatched_guides = 0
        errors: list[str] = []
        for event in events:
            kinds[event["kind"]] = kinds.get(event["kind"], 0) + 1
            detail = event.get("detail") or {}
            if event["kind"] == "voice":
                engine = str(detail.get("engine") or "unknown")
                engines[engine] = engines.get(engine, 0) + 1
            if event["kind"] == "reply":
                honesty += 1 if detail.get("honesty") else 0
                unverified += 1 if detail.get("grounding_verified") is False else 0
            if event["kind"] == "guide" and detail.get("shown") and detail.get("spoken") and \
                    str(detail.get("shown")).strip() != str(detail.get("spoken")).strip():
                mismatched_guides += 1
            if event["kind"] == "error":
                errors.append(str(detail.get("error") or "")[:160])
        return {"events": len(events), "by_kind": kinds, "voice_engines": engines,
                "honesty_guard_hits": honesty, "unverified_live_answers": unverified,
                "guide_shown_vs_spoken_mismatch": mismatched_guides, "errors": errors[-10:]}

    def testers(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM test_mode_testers ORDER BY updated_at DESC").fetchall()
        return [{"user_ref": user_ref(r["app_user_id"]), "staff_name": r["staff_name"], "enabled": bool(r["enabled"]),
                 "expires_at": r["expires_at"]} for r in rows]
