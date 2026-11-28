"""Closing-time reminder (owner 2026-11-27, phase 6): the owner's OWN closing time per shop (a clock time, nothing else),
and ONE push to the owner when that time has come -- "close today's stock". The stock figures stay on the phone; the
server holds a time only and never sees a quantity. Off until the owner sets a time.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import PosError, PosStore

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_closing_time (business_id TEXT PRIMARY KEY, hhmm TEXT NOT NULL,"
    " set_by TEXT NOT NULL, sent_day TEXT NOT NULL DEFAULT '')",
]
IST = timezone(timedelta(hours=5, minutes=30))
LATE_MINUTES = 90   # a closing time missed by more than this (server down, phone off) is not pushed late at midnight


def _clean(hhmm: Optional[str]) -> Optional[str]:
    if hhmm in (None, ""):
        return None
    m = re.fullmatch(r"(\d{1,2}):(\d{2})", str(hhmm).strip())
    if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59:
        raise PosError(422, "time", "Closing time must be HH:MM.")
    return f"{int(m.group(1)):02d}:{m.group(2)}"


class PosClosingTime:
    def __init__(self, store: PosStore, clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.clock = clock or store.clock
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _owner(self, conn: Any, business_id: str, user: str) -> None:
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        if role != "owner":
            raise PosError(403, "permission", "Only the owner sets the closing time.", role=role)

    def get(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self._owner(conn, business_id, user)
            row = conn.execute("SELECT hhmm FROM pos_closing_time WHERE business_id = ?", (business_id,)).fetchone()
        return {"closing_time": row["hhmm"] if row else None}

    def set(self, business_id: str, user: str, hhmm: Optional[str]) -> Dict[str, Any]:
        value = _clean(hhmm)
        with self.store._tx() as conn:
            self._owner(conn, business_id, user)
            if value is None:
                conn.execute("DELETE FROM pos_closing_time WHERE business_id = ?", (business_id,))
            else:
                conn.execute("INSERT INTO pos_closing_time (business_id, hhmm, set_by) VALUES (?, ?, ?)"
                             " ON CONFLICT(business_id) DO UPDATE SET hhmm = excluded.hhmm, sent_day = ''",
                             (business_id, value, user))
        return {"closing_time": value}

    def due(self) -> List[Dict[str, Any]]:
        """Shops whose closing time has come today and were not told yet. Each is returned ONCE (marked here)."""
        now = self.clock().astimezone(IST)
        day = now.date().isoformat()
        minutes = now.hour * 60 + now.minute
        out: List[Dict[str, Any]] = []
        with self.store._tx() as conn:
            rows = conn.execute("SELECT c.business_id, c.hhmm, b.owner_user_id AS owner_id FROM pos_closing_time c"
                                " JOIN pos_businesses b ON b.id = c.business_id WHERE c.sent_day != ?", (day,)).fetchall()
            for row in rows:
                h, m = row["hhmm"].split(":")
                at = int(h) * 60 + int(m)
                if minutes < at:
                    continue
                conn.execute("UPDATE pos_closing_time SET sent_day = ? WHERE business_id = ?", (day, row["business_id"]))
                if minutes - at <= LATE_MINUTES:
                    out.append({"business_id": row["business_id"], "owner": row["owner_id"], "day": day})
        return out


def reminder_text(item: Dict[str, Any]) -> Dict[str, str]:
    return {"title": "క్లోజింగ్ టైమ్ అయింది · స్టాక్ చూడండి",
            "body": "ఈ రోజు స్టాక్ క్లోజ్ చేయండి. · Closing time: close today's stock.",
            "route": f"/pos/{item['business_id']}/yield", "key": f"closing:{item['business_id']}:{item['day']}"}
