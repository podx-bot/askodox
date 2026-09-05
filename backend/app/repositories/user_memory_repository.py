"""Persistent, user-scoped long-term memory for ASKODOX."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any


class UserMemoryRepository:
    TABLE = "user_memory"

    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _clean(value: Any, field: str) -> str:
        text = " ".join(str(value or "").strip().split())
        if not text:
            raise ValueError(f"{field} is required")
        return text

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                f"""
                CREATE TABLE IF NOT EXISTS {self.TABLE}(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    memory_key TEXT NOT NULL,
                    memory_value TEXT NOT NULL,
                    memory_type TEXT NOT NULL DEFAULT 'FACT',
                    source TEXT,
                    active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, memory_key)
                );
                CREATE INDEX IF NOT EXISTS idx_user_memory_user_active
                    ON {self.TABLE}(user_id, active, updated_at DESC, id DESC);
                """
            )

    def remember(
        self,
        user_id: str,
        memory_key: str,
        memory_value: str,
        *,
        memory_type: str = "FACT",
        source: str | None = None,
    ) -> dict[str, Any]:
        uid = self._clean(user_id, "user_id")
        key = self._clean(memory_key, "memory_key").casefold()
        value = self._clean(memory_value, "memory_value")
        kind = self._clean(memory_type, "memory_type").upper()
        now = self._now()
        with self._connect() as conn:
            conn.execute(
                f"""
                INSERT INTO {self.TABLE}(
                    user_id,memory_key,memory_value,memory_type,source,active,created_at,updated_at
                ) VALUES(?,?,?,?,?,1,?,?)
                ON CONFLICT(user_id,memory_key) DO UPDATE SET
                    memory_value=excluded.memory_value,
                    memory_type=excluded.memory_type,
                    source=excluded.source,
                    active=1,
                    updated_at=excluded.updated_at
                """,
                (uid, key, value, kind, source, now, now),
            )
        return self.get(uid, key) or {}

    def get(self, user_id: str, memory_key: str) -> dict[str, Any] | None:
        uid = self._clean(user_id, "user_id")
        key = self._clean(memory_key, "memory_key").casefold()
        with self._connect() as conn:
            row = conn.execute(
                f"SELECT * FROM {self.TABLE} WHERE user_id=? AND memory_key=? AND active=1 LIMIT 1",
                (uid, key),
            ).fetchone()
        return dict(row) if row else None

    def list_active(self, user_id: str, limit: int = 50) -> list[dict[str, Any]]:
        uid = self._clean(user_id, "user_id")
        with self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT * FROM {self.TABLE}
                WHERE user_id=? AND active=1
                ORDER BY updated_at DESC, id DESC LIMIT ?
                """,
                (uid, max(1, min(int(limit), 100))),
            ).fetchall()
        return [dict(row) for row in rows]

    def forget(self, user_id: str, memory_key: str) -> bool:
        uid = self._clean(user_id, "user_id")
        key = self._clean(memory_key, "memory_key").casefold()
        with self._connect() as conn:
            cur = conn.execute(
                f"UPDATE {self.TABLE} SET active=0, updated_at=? WHERE user_id=? AND memory_key=? AND active=1",
                (self._now(), uid, key),
            )
        return cur.rowcount > 0

    def clear_user(self, user_id: str) -> int:
        uid = self._clean(user_id, "user_id")
        with self._connect() as conn:
            cur = conn.execute(
                f"UPDATE {self.TABLE} SET active=0, updated_at=? WHERE user_id=? AND active=1",
                (self._now(), uid),
            )
        return int(cur.rowcount)
