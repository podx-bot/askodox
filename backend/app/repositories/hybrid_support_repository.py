"""Persistent unresolved-question tickets for PODX hybrid support."""
from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


class HybridSupportRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS hybrid_support_tickets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    requester_user_id TEXT NOT NULL,
                    question TEXT NOT NULL,
                    question_key TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'PENDING',
                    answer TEXT,
                    answered_by TEXT,
                    knowledge_id INTEGER,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_hybrid_support_status ON hybrid_support_tickets(status, id);
                CREATE INDEX IF NOT EXISTS idx_hybrid_support_requester ON hybrid_support_tickets(requester_user_id, id);
                """
            )

    @staticmethod
    def question_key(question: str) -> str:
        normalized = " ".join(str(question or "").casefold().strip().split())
        return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:24]

    def create_once(self, requester_user_id: str, question: str) -> Dict[str, Any]:
        key = self.question_key(question)
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM hybrid_support_tickets WHERE requester_user_id=? AND question_key=? AND status='PENDING' ORDER BY id DESC LIMIT 1",
                (str(requester_user_id), key),
            ).fetchone()
            if row:
                data = dict(row); data["created"] = False; return data
            now = self._now()
            cur = conn.execute(
                "INSERT INTO hybrid_support_tickets(requester_user_id,question,question_key,status,created_at,updated_at) VALUES(?,?,?,'PENDING',?,?)",
                (str(requester_user_id), str(question).strip(), key, now, now),
            )
            row = conn.execute("SELECT * FROM hybrid_support_tickets WHERE id=?", (int(cur.lastrowid),)).fetchone()
        data = dict(row); data["created"] = True; return data

    def get(self, ticket_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM hybrid_support_tickets WHERE id=?", (int(ticket_id),)).fetchone()
        return dict(row) if row else None

    def answer(self, ticket_id: int, answer: str, answered_by: str, knowledge_id: int | None = None) -> Optional[Dict[str, Any]]:
        text = " ".join(str(answer or "").strip().split())
        if not text:
            return None
        now = self._now()
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE hybrid_support_tickets SET status='ANSWERED',answer=?,answered_by=?,knowledge_id=?,updated_at=? WHERE id=? AND status='PENDING'",
                (text, str(answered_by), knowledge_id, now, int(ticket_id)),
            )
            if cur.rowcount != 1:
                return None
            row = conn.execute("SELECT * FROM hybrid_support_tickets WHERE id=?", (int(ticket_id),)).fetchone()
        return dict(row) if row else None


class SupportEscalationRepository:
    """In-app escalations to ASKODOX Support, with the full AI context.

    Added 2026-09-26: when ASKODOX AI (first-line support) cannot resolve an
    issue, the Support/Admin Command Center receives the user's issue, the AI
    conversation, requirement, deal/order id, counterpart, what was already
    tried and the current status -- so the user never repeats themselves.
    """

    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """CREATE TABLE IF NOT EXISTS support_escalations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    requester_user_id TEXT NOT NULL,
                    issue TEXT NOT NULL,
                    category TEXT NOT NULL,
                    critical INTEGER NOT NULL DEFAULT 0,
                    context_json TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'OPEN',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )"""
            )

    def create(self, requester_user_id: str, issue: str, category: str, critical: bool, context: Dict[str, Any]) -> Dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat()
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "INSERT INTO support_escalations(requester_user_id,issue,category,critical,context_json,status,created_at,updated_at) VALUES(?,?,?,?,?,'OPEN',?,?)",
                (str(requester_user_id), str(issue).strip()[:2000], str(category or "GENERAL").upper(), int(bool(critical)),
                 json.dumps(context, ensure_ascii=False), now, now),
            )
            new_id = int(cur.lastrowid)
        return self.get(new_id) or {}

    def get(self, escalation_id: int) -> Optional[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute("SELECT * FROM support_escalations WHERE id=?", (int(escalation_id),)).fetchone()
        return self._row(row) if row else None

    def list_open(self, limit: int = 50) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT * FROM support_escalations WHERE status='OPEN' ORDER BY critical DESC, id DESC LIMIT ?",
                (max(1, min(int(limit), 200)),),
            ).fetchall()
        return [self._row(row) for row in rows]

    @staticmethod
    def _row(row) -> Dict[str, Any]:
        data = dict(row)
        data["critical"] = bool(data.get("critical"))
        data["context"] = json.loads(data.pop("context_json") or "{}")
        return data
