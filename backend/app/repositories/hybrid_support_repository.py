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
            # 2026-09-26 (Command Center): workflow fields for staff.
            # 2026-09-29: support tickets (priority, channel, SLA, history).
            for column in ("assigned_to TEXT", "resolution_note TEXT", "priority TEXT", "channel TEXT",
                           "sla_due_at TEXT", "first_response_at TEXT", "resolved_at TEXT",
                           "attachments_json TEXT"):
                try:
                    conn.execute(f"ALTER TABLE support_escalations ADD COLUMN {column}")
                except sqlite3.OperationalError:
                    pass  # already present
            conn.execute(
                """CREATE TABLE IF NOT EXISTS support_escalation_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, escalation_id INTEGER NOT NULL, at TEXT NOT NULL,
                    actor TEXT NOT NULL, action TEXT NOT NULL, detail_json TEXT NOT NULL DEFAULT '{}'
                )"""
            )

    PRIORITIES = ("LOW", "NORMAL", "HIGH", "URGENT")
    CHANNELS = ("in_app", "whatsapp", "email", "phone")
    SLA_HOURS = {"URGENT": 2, "HIGH": 8, "NORMAL": 24, "LOW": 72}

    def create(self, requester_user_id: str, issue: str, category: str, critical: bool, context: Dict[str, Any],
               *, channel: str = "in_app", priority: str | None = None) -> Dict[str, Any]:
        from datetime import timedelta

        now_dt = datetime.now(timezone.utc)
        now = now_dt.isoformat()
        priority = (priority or ("URGENT" if critical else "NORMAL")).upper()
        if priority not in self.PRIORITIES:
            priority = "NORMAL"
        channel = channel if channel in self.CHANNELS else "in_app"
        due = (now_dt + timedelta(hours=self.SLA_HOURS[priority])).isoformat()
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "INSERT INTO support_escalations(requester_user_id,issue,category,critical,context_json,status,created_at,updated_at,"
                "priority,channel,sla_due_at,attachments_json) VALUES(?,?,?,?,?,'OPEN',?,?,?,?,?,'[]')",
                (str(requester_user_id), str(issue).strip()[:2000], str(category or "GENERAL").upper(), int(bool(critical)),
                 json.dumps(context, ensure_ascii=False), now, now, priority, channel, due),
            )
            new_id = int(cur.lastrowid)
        self.add_history(new_id, "customer", "created", {"priority": priority, "channel": channel})
        return self.get(new_id) or {}

    def add_history(self, escalation_id: int, actor: str, action: str, detail: Dict[str, Any] | None = None) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT INTO support_escalation_history(escalation_id,at,actor,action,detail_json) "
                         "VALUES(?,?,?,?,?)", (int(escalation_id), datetime.now(timezone.utc).isoformat(),
                                               str(actor)[:120], action[:40],
                                               json.dumps(detail or {}, ensure_ascii=False)))

    def history(self, escalation_id: int) -> List[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute("SELECT * FROM support_escalation_history WHERE escalation_id=? ORDER BY id",
                                (int(escalation_id),)).fetchall()
        return [dict(r, detail=json.loads(r["detail_json"] or "{}")) for r in rows]

    def set_ticket_fields(self, escalation_id: int, *, actor: str, priority: str | None = None,
                          channel: str | None = None, attachments: List[str] | None = None,
                          note: str | None = None) -> Optional[Dict[str, Any]]:
        """Priority (re-computes the SLA from creation), channel, attachment
        references and internal notes -- each change goes to the history."""
        from datetime import timedelta

        current = self.get(escalation_id)
        if not current:
            return None
        changes: Dict[str, Any] = {}
        sets, params = [], []
        if priority:
            priority = priority.upper()
            if priority not in self.PRIORITIES:
                raise ValueError(f"priority must be one of {', '.join(self.PRIORITIES)}")
            created = datetime.fromisoformat(current["created_at"])
            sets += ["priority=?", "sla_due_at=?"]
            params += [priority, (created + timedelta(hours=self.SLA_HOURS[priority])).isoformat()]
            changes["priority"] = [current.get("priority"), priority]
        if channel:
            if channel not in self.CHANNELS:
                raise ValueError(f"channel must be one of {', '.join(self.CHANNELS)}")
            sets.append("channel=?")
            params.append(channel)
            changes["channel"] = [current.get("channel"), channel]
        if attachments is not None:
            refs = [str(a)[:200] for a in attachments][:20]
            sets.append("attachments_json=?")
            params.append(json.dumps(refs))
            changes["attachments"] = len(refs)
        if sets:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(f"UPDATE support_escalations SET {', '.join(sets)}, updated_at=? WHERE id=?",
                             (*params, datetime.now(timezone.utc).isoformat(), int(escalation_id)))
            self.add_history(escalation_id, actor, "fields", changes)
        if note:
            self.add_history(escalation_id, actor, "note", {"note": note[:2000]})
        return self.get(escalation_id)

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

    def list(self, status: str | None = None, category: str | None = None, limit: int = 100) -> List[Dict[str, Any]]:
        clauses, params = [], []
        if status:
            clauses.append("status=?")
            params.append(status)
        if category:
            clauses.append("category=?")
            params.append(category.upper())
        sql = "SELECT * FROM support_escalations"
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY critical DESC, id DESC LIMIT ?"
        params.append(max(1, min(int(limit), 500)))
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(sql, tuple(params)).fetchall()
        return [self._row(row) for row in rows]

    def update(self, escalation_id: int, *, status: str | None = None, assigned_to: str | None = None,
               resolution_note: str | None = None, actor: str = "") -> Optional[Dict[str, Any]]:
        current = self.get(escalation_id)
        if not current:
            return None
        now = datetime.now(timezone.utc).isoformat()
        new_status = status or current["status"]
        # The first staff action on an open ticket is its first response.
        first_response = current.get("first_response_at") or (
            now if (new_status != "OPEN" or assigned_to) else None)
        resolved = current.get("resolved_at")
        if new_status in ("RESOLVED", "CLOSED") and not resolved:
            resolved = now
        elif new_status not in ("RESOLVED", "CLOSED"):
            resolved = None
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "UPDATE support_escalations SET status=?, assigned_to=?, resolution_note=?, updated_at=?, "
                "first_response_at=?, resolved_at=? WHERE id=?",
                (new_status,
                 assigned_to if assigned_to is not None else current.get("assigned_to"),
                 resolution_note if resolution_note is not None else current.get("resolution_note"),
                 now, first_response, resolved, int(escalation_id)),
            )
        self.add_history(escalation_id, actor or "staff", "update",
                         {k: v for k, v in (("status", status), ("assigned_to", assigned_to),
                                            ("resolution_note", resolution_note)) if v is not None})
        return self.get(escalation_id)

    @staticmethod
    def _row(row) -> Dict[str, Any]:
        data = dict(row)
        data["critical"] = bool(data.get("critical"))
        data["context"] = json.loads(data.pop("context_json") or "{}")
        data["attachments"] = json.loads(data.pop("attachments_json", None) or "[]")
        data["priority"] = data.get("priority") or ("URGENT" if data["critical"] else "NORMAL")
        data["channel"] = data.get("channel") or "in_app"
        data["sla_state"] = SupportEscalationRepository.sla_state(data)
        return data

    @staticmethod
    def sla_state(ticket: Dict[str, Any], now: datetime | None = None) -> str:
        """MET / BREACHED (resolved late) for closed tickets; ON_TRACK /
        DUE_SOON (< 25% of the window left) / OVERDUE for open ones."""
        due_text = ticket.get("sla_due_at")
        if not due_text:
            return "NO_SLA"
        due = datetime.fromisoformat(due_text)
        if ticket.get("resolved_at"):
            return "MET" if datetime.fromisoformat(ticket["resolved_at"]) <= due else "BREACHED"
        now = now or datetime.now(timezone.utc)
        if now > due:
            return "OVERDUE"
        created = datetime.fromisoformat(ticket["created_at"])
        return "DUE_SOON" if (due - now) < (due - created) / 4 else "ON_TRACK"
