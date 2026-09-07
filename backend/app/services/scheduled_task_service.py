from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


_ALLOWED_KINDS = {"reminder", "scheduled", "condition_watch"}
_ALLOWED_RECURRENCES = {"once", "hourly", "daily", "weekly"}


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z") if value else None


def _parse_datetime(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise ValueError("run_at must include a timezone offset")
    return parsed.astimezone(timezone.utc)


@dataclass(frozen=True)
class ScheduledTask:
    id: str
    user_id: str
    title: str
    prompt: str
    kind: str
    recurrence: str
    timezone: str
    next_run_at: str | None
    enabled: bool
    condition: dict[str, Any] | None
    created_at: str
    updated_at: str
    last_run_at: str | None = None
    last_status: str | None = None


class ScheduledTaskService:
    """Persistent reminder/schedule/monitoring task registry.

    Workers should use ``claim_due`` rather than ``due`` for execution. Claiming
    is atomic and lease-based, so multiple application replicas cannot execute
    the same scheduled occurrence concurrently. ``mark_run`` acknowledges the
    attempt and clears the lease.
    """

    def __init__(self, database_path: str | Path):
        self.database_path = str(database_path)
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _ensure_schema(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS scheduled_tasks (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    prompt TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    recurrence TEXT NOT NULL,
                    timezone TEXT NOT NULL,
                    next_run_at TEXT,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    condition_json TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_run_at TEXT,
                    last_status TEXT,
                    claim_token TEXT,
                    claim_until TEXT,
                    claim_scheduled_for TEXT
                )
                """
            )
            columns = {row["name"] for row in db.execute("PRAGMA table_info(scheduled_tasks)")}
            for name in ("claim_token", "claim_until", "claim_scheduled_for"):
                if name not in columns:
                    db.execute(f"ALTER TABLE scheduled_tasks ADD COLUMN {name} TEXT")
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_due ON scheduled_tasks(enabled, next_run_at)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_user ON scheduled_tasks(user_id, created_at)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_claim ON scheduled_tasks(claim_until)"
            )

    @staticmethod
    def _validate_timezone(name: str) -> str:
        try:
            ZoneInfo(name)
        except ZoneInfoNotFoundError as error:
            raise ValueError(f"Unknown timezone: {name}") from error
        return name

    @staticmethod
    def _next_after(current: datetime, recurrence: str) -> datetime | None:
        if recurrence == "once":
            return None
        if recurrence == "hourly":
            return current + timedelta(hours=1)
        if recurrence == "daily":
            return current + timedelta(days=1)
        if recurrence == "weekly":
            return current + timedelta(weeks=1)
        raise ValueError(f"Unsupported recurrence: {recurrence}")

    def create(
        self,
        *,
        user_id: str,
        title: str,
        prompt: str,
        kind: str,
        run_at: str,
        recurrence: str = "once",
        timezone_name: str = "UTC",
        condition: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        user_id = user_id.strip()
        title = title.strip()
        prompt = prompt.strip()
        if not user_id or not title or not prompt:
            raise ValueError("user_id, title and prompt are required")
        if kind not in _ALLOWED_KINDS:
            raise ValueError(f"Unsupported task kind: {kind}")
        if recurrence not in _ALLOWED_RECURRENCES:
            raise ValueError(f"Unsupported recurrence: {recurrence}")
        if kind == "condition_watch" and recurrence == "once":
            raise ValueError("condition_watch tasks must recur")
        if kind == "condition_watch" and not condition:
            raise ValueError("condition_watch tasks require a condition")
        self._validate_timezone(timezone_name)

        run_at_utc = _parse_datetime(run_at)
        now = _utc_now()
        if run_at_utc <= now:
            raise ValueError("run_at must be in the future")

        task_id = uuid.uuid4().hex
        now_iso = _iso(now)
        with self._connect() as db:
            db.execute(
                """
                INSERT INTO scheduled_tasks (
                    id, user_id, title, prompt, kind, recurrence, timezone,
                    next_run_at, enabled, condition_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
                """,
                (
                    task_id,
                    user_id,
                    title,
                    prompt,
                    kind,
                    recurrence,
                    timezone_name,
                    _iso(run_at_utc),
                    json.dumps(condition, ensure_ascii=False) if condition else None,
                    now_iso,
                    now_iso,
                ),
            )
        return self.get(task_id=task_id, user_id=user_id)

    def get(self, *, task_id: str, user_id: str | None = None) -> dict[str, Any]:
        query = "SELECT * FROM scheduled_tasks WHERE id = ?"
        params: list[Any] = [task_id]
        if user_id is not None:
            query += " AND user_id = ?"
            params.append(user_id)
        with self._connect() as db:
            row = db.execute(query, params).fetchone()
        if row is None:
            raise KeyError(task_id)
        return self._serialize(row)

    def list(self, *, user_id: str, include_disabled: bool = False) -> list[dict[str, Any]]:
        query = "SELECT * FROM scheduled_tasks WHERE user_id = ?"
        params: list[Any] = [user_id]
        if not include_disabled:
            query += " AND enabled = 1"
        query += " ORDER BY created_at DESC"
        with self._connect() as db:
            rows = db.execute(query, params).fetchall()
        return [self._serialize(row) for row in rows]

    def cancel(self, *, task_id: str, user_id: str) -> dict[str, Any]:
        now_iso = _iso(_utc_now())
        with self._connect() as db:
            cursor = db.execute(
                """
                UPDATE scheduled_tasks
                SET enabled = 0, updated_at = ?, claim_token = NULL,
                    claim_until = NULL, claim_scheduled_for = NULL
                WHERE id = ? AND user_id = ?
                """,
                (now_iso, task_id, user_id),
            )
        if cursor.rowcount == 0:
            raise KeyError(task_id)
        return self.get(task_id=task_id, user_id=user_id)

    def due(self, *, now: datetime | None = None, limit: int = 100) -> list[dict[str, Any]]:
        instant = (now or _utc_now()).astimezone(timezone.utc)
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT * FROM scheduled_tasks
                WHERE enabled = 1 AND next_run_at IS NOT NULL AND next_run_at <= ?
                ORDER BY next_run_at ASC LIMIT ?
                """,
                (_iso(instant), max(1, min(limit, 500))),
            ).fetchall()
        return [self._serialize(row) for row in rows]

    def claim_due(
        self,
        *,
        now: datetime | None = None,
        limit: int = 100,
        lease_seconds: int = 90,
    ) -> list[dict[str, Any]]:
        instant = (now or _utc_now()).astimezone(timezone.utc)
        now_iso = _iso(instant)
        claim_until = _iso(instant + timedelta(seconds=max(15, min(lease_seconds, 900))))
        bounded_limit = max(1, min(limit, 500))
        claimed: list[dict[str, Any]] = []

        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            rows = db.execute(
                """
                SELECT * FROM scheduled_tasks
                WHERE enabled = 1
                  AND next_run_at IS NOT NULL
                  AND next_run_at <= ?
                  AND (claim_until IS NULL OR claim_until <= ?)
                ORDER BY next_run_at ASC
                LIMIT ?
                """,
                (now_iso, now_iso, bounded_limit),
            ).fetchall()
            for row in rows:
                token = uuid.uuid4().hex
                scheduled_for = row["next_run_at"]
                cursor = db.execute(
                    """
                    UPDATE scheduled_tasks
                    SET claim_token = ?, claim_until = ?, claim_scheduled_for = ?, updated_at = ?
                    WHERE id = ?
                      AND enabled = 1
                      AND next_run_at = ?
                      AND (claim_until IS NULL OR claim_until <= ?)
                    """,
                    (token, claim_until, scheduled_for, now_iso, row["id"], scheduled_for, now_iso),
                )
                if cursor.rowcount != 1:
                    continue
                item = self._serialize(row)
                item["claim_token"] = token
                item["scheduled_for"] = scheduled_for
                claimed.append(item)
        return claimed

    def mark_run(
        self,
        *,
        task_id: str,
        status: str,
        ran_at: datetime | None = None,
        claim_token: str | None = None,
    ) -> dict[str, Any]:
        if status not in {"delivered", "condition_false", "failed"}:
            raise ValueError("Unsupported run status")
        current = (ran_at or _utc_now()).astimezone(timezone.utc)

        with self._connect() as db:
            row = db.execute(
                "SELECT next_run_at, recurrence, enabled, claim_token, claim_scheduled_for FROM scheduled_tasks WHERE id = ?",
                (task_id,),
            ).fetchone()
            if row is None:
                raise KeyError(task_id)
            if claim_token is not None and row["claim_token"] != claim_token:
                raise RuntimeError("Scheduled task claim is no longer owned by this worker")

            scheduled_for_text = row["claim_scheduled_for"] or row["next_run_at"]
            scheduled_for = _parse_datetime(scheduled_for_text) if scheduled_for_text else current
            if status == "failed":
                next_run = scheduled_for
                enabled = bool(row["enabled"])
            else:
                next_run = self._next_after(scheduled_for, row["recurrence"])
                enabled = next_run is not None

            db.execute(
                """
                UPDATE scheduled_tasks
                SET next_run_at = ?, enabled = ?, updated_at = ?, last_run_at = ?, last_status = ?,
                    claim_token = NULL, claim_until = NULL, claim_scheduled_for = NULL
                WHERE id = ?
                """,
                (_iso(next_run), int(enabled), _iso(current), _iso(current), status, task_id),
            )
        return self.get(task_id=task_id)

    @staticmethod
    def _serialize(row: sqlite3.Row) -> dict[str, Any]:
        task = ScheduledTask(
            id=row["id"],
            user_id=row["user_id"],
            title=row["title"],
            prompt=row["prompt"],
            kind=row["kind"],
            recurrence=row["recurrence"],
            timezone=row["timezone"],
            next_run_at=row["next_run_at"],
            enabled=bool(row["enabled"]),
            condition=json.loads(row["condition_json"]) if row["condition_json"] else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            last_run_at=row["last_run_at"],
            last_status=row["last_status"],
        )
        return asdict(task)
