from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


class ConnectedActionService:
    """Approval-gated, idempotent connected-action orchestration.

    The service persists intent, approval, execution result, and audit timestamps.
    External side effects are delegated to registered executors only after the
    owning user has explicitly approved the action.
    """

    def __init__(self, database_path: str | Path):
        self.database_path = str(database_path)
        self._executors: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {}
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.database_path, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    def _ensure_schema(self) -> None:
        with self._connect() as db:
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS connected_actions (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    action_type TEXT NOT NULL,
                    target TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    status TEXT NOT NULL,
                    approval_required INTEGER NOT NULL DEFAULT 1,
                    approved_at TEXT,
                    executed_at TEXT,
                    result_json TEXT,
                    error_text TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, idempotency_key)
                )
                """
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_connected_actions_user_created ON connected_actions(user_id, created_at DESC)"
            )
            db.execute(
                "CREATE INDEX IF NOT EXISTS idx_connected_actions_status ON connected_actions(status, updated_at)"
            )

    def register_executor(
        self,
        action_type: str,
        executor: Callable[[dict[str, Any]], dict[str, Any]],
    ) -> None:
        key = action_type.strip()
        if not key:
            raise ValueError('action_type is required')
        self._executors[key] = executor

    def create(
        self,
        *,
        user_id: str,
        action_type: str,
        target: str,
        payload: dict[str, Any],
        idempotency_key: str,
        approval_required: bool = True,
    ) -> dict[str, Any]:
        user_id = user_id.strip()
        action_type = action_type.strip()
        target = target.strip()
        idempotency_key = idempotency_key.strip()
        if not user_id or not action_type or not target or not idempotency_key:
            raise ValueError('user_id, action_type, target and idempotency_key are required')

        now = _now_iso()
        action_id = uuid.uuid4().hex
        initial_status = 'pending_approval' if approval_required else 'approved'
        approved_at = None if approval_required else now
        with self._connect() as db:
            try:
                db.execute(
                    """
                    INSERT INTO connected_actions (
                        id, user_id, action_type, target, payload_json,
                        idempotency_key, status, approval_required, approved_at,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        action_id,
                        user_id,
                        action_type,
                        target,
                        json.dumps(payload, ensure_ascii=False, sort_keys=True),
                        idempotency_key,
                        initial_status,
                        int(approval_required),
                        approved_at,
                        now,
                        now,
                    ),
                )
            except sqlite3.IntegrityError:
                row = db.execute(
                    "SELECT * FROM connected_actions WHERE user_id = ? AND idempotency_key = ?",
                    (user_id, idempotency_key),
                ).fetchone()
                if row is None:
                    raise
                return self._serialize(row)
        return self.get(action_id=action_id, user_id=user_id)

    def approve(self, *, action_id: str, user_id: str) -> dict[str, Any]:
        now = _now_iso()
        with self._connect() as db:
            row = db.execute(
                "SELECT * FROM connected_actions WHERE id = ? AND user_id = ?",
                (action_id, user_id),
            ).fetchone()
            if row is None:
                raise KeyError(action_id)
            if row['status'] in {'executed', 'failed'}:
                return self._serialize(row)
            db.execute(
                """
                UPDATE connected_actions
                SET status = 'approved', approved_at = COALESCE(approved_at, ?), updated_at = ?
                WHERE id = ? AND user_id = ?
                """,
                (now, now, action_id, user_id),
            )
        return self.get(action_id=action_id, user_id=user_id)

    def execute(self, *, action_id: str, user_id: str) -> dict[str, Any]:
        with self._connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute(
                "SELECT * FROM connected_actions WHERE id = ? AND user_id = ?",
                (action_id, user_id),
            ).fetchone()
            if row is None:
                raise KeyError(action_id)
            if row['status'] == 'executed':
                return self._serialize(row)
            if row['status'] != 'approved':
                raise PermissionError('Action requires explicit user approval before execution')
            claimed = db.execute(
                """
                UPDATE connected_actions
                SET status = 'executing', updated_at = ?
                WHERE id = ? AND user_id = ? AND status = 'approved'
                """,
                (_now_iso(), action_id, user_id),
            )
            if claimed.rowcount != 1:
                latest = db.execute('SELECT * FROM connected_actions WHERE id = ?', (action_id,)).fetchone()
                if latest is not None and latest['status'] == 'executed':
                    return self._serialize(latest)
                raise RuntimeError('Action is already being executed')

        executor = self._executors.get(row['action_type'])
        if executor is None:
            self._mark_failed(action_id=action_id, error=f"No executor registered for {row['action_type']}")
            raise RuntimeError(f"No executor registered for {row['action_type']}")

        request = {
            'action_id': row['id'],
            'user_id': row['user_id'],
            'action_type': row['action_type'],
            'target': row['target'],
            'payload': json.loads(row['payload_json']),
            'idempotency_key': row['idempotency_key'],
        }
        try:
            result = executor(request)
        except Exception as error:
            self._mark_failed(action_id=action_id, error=str(error))
            raise

        now = _now_iso()
        with self._connect() as db:
            db.execute(
                """
                UPDATE connected_actions
                SET status = 'executed', executed_at = ?, result_json = ?,
                    error_text = NULL, updated_at = ?
                WHERE id = ?
                """,
                (now, json.dumps(result, ensure_ascii=False, sort_keys=True), now, action_id),
            )
        return self.get(action_id=action_id, user_id=user_id)

    def _mark_failed(self, *, action_id: str, error: str) -> None:
        now = _now_iso()
        with self._connect() as db:
            db.execute(
                """
                UPDATE connected_actions
                SET status = 'failed', error_text = ?, updated_at = ?
                WHERE id = ?
                """,
                (error[:2000], now, action_id),
            )

    def get(self, *, action_id: str, user_id: str) -> dict[str, Any]:
        with self._connect() as db:
            row = db.execute(
                "SELECT * FROM connected_actions WHERE id = ? AND user_id = ?",
                (action_id, user_id),
            ).fetchone()
        if row is None:
            raise KeyError(action_id)
        return self._serialize(row)

    def list(self, *, user_id: str, limit: int = 50) -> list[dict[str, Any]]:
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT * FROM connected_actions
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (user_id, max(1, min(limit, 200))),
            ).fetchall()
        return [self._serialize(row) for row in rows]

    @staticmethod
    def _serialize(row: sqlite3.Row) -> dict[str, Any]:
        return {
            'id': row['id'],
            'user_id': row['user_id'],
            'action_type': row['action_type'],
            'target': row['target'],
            'payload': json.loads(row['payload_json']),
            'idempotency_key': row['idempotency_key'],
            'status': row['status'],
            'approval_required': bool(row['approval_required']),
            'approved_at': row['approved_at'],
            'executed_at': row['executed_at'],
            'result': json.loads(row['result_json']) if row['result_json'] else None,
            'error': row['error_text'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
        }
