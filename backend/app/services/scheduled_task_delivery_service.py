from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class ScheduledTaskDeliveryService:
    """Idempotent in-app delivery store for scheduled task occurrences."""

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
                CREATE TABLE IF NOT EXISTS scheduled_task_deliveries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    task_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    prompt TEXT NOT NULL,
                    scheduled_for TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'DELIVERED',
                    created_at TEXT NOT NULL,
                    read_at TEXT,
                    UNIQUE(task_id, scheduled_for)
                )
                """
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_scheduled_task_delivery_user ON scheduled_task_deliveries(user_id, created_at)"
            )

    def deliver(self, *, task: dict[str, Any], scheduled_for: str) -> dict[str, Any]:
        now = _now_iso()
        with self._connect() as db:
            try:
                cursor = db.execute(
                    """
                    INSERT INTO scheduled_task_deliveries (
                        task_id, user_id, title, prompt, scheduled_for, status, created_at
                    ) VALUES (?, ?, ?, ?, ?, 'DELIVERED', ?)
                    """,
                    (
                        str(task["id"]),
                        str(task["user_id"]),
                        str(task["title"]),
                        str(task["prompt"]),
                        scheduled_for,
                        now,
                    ),
                )
                delivery_id = int(cursor.lastrowid)
            except sqlite3.IntegrityError:
                row = db.execute(
                    "SELECT id FROM scheduled_task_deliveries WHERE task_id = ? AND scheduled_for = ?",
                    (str(task["id"]), scheduled_for),
                ).fetchone()
                if row is None:
                    raise
                delivery_id = int(row["id"])
        return self.get(delivery_id=delivery_id, user_id=str(task["user_id"]))

    def get(self, *, delivery_id: int, user_id: str) -> dict[str, Any]:
        with self._connect() as db:
            row = db.execute(
                "SELECT * FROM scheduled_task_deliveries WHERE id = ? AND user_id = ?",
                (delivery_id, user_id),
            ).fetchone()
        if row is None:
            raise KeyError(delivery_id)
        return dict(row)

    def list(self, *, user_id: str, unread_only: bool = False, limit: int = 50) -> list[dict[str, Any]]:
        query = "SELECT * FROM scheduled_task_deliveries WHERE user_id = ?"
        params: list[Any] = [user_id]
        if unread_only:
            query += " AND read_at IS NULL"
        query += " ORDER BY id DESC LIMIT ?"
        params.append(max(1, min(limit, 200)))
        with self._connect() as db:
            rows = db.execute(query, params).fetchall()
        return [dict(row) for row in rows]

    def mark_read(self, *, delivery_id: int, user_id: str) -> dict[str, Any]:
        with self._connect() as db:
            cursor = db.execute(
                "UPDATE scheduled_task_deliveries SET read_at = COALESCE(read_at, ?) WHERE id = ? AND user_id = ?",
                (_now_iso(), delivery_id, user_id),
            )
        if cursor.rowcount == 0:
            raise KeyError(delivery_id)
        return self.get(delivery_id=delivery_id, user_id=user_id)
