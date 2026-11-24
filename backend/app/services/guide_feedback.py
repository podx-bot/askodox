"""Did the page guide help? (owner 2026-11-24: fewer sales executives -- the app itself must explain.)

Every "understood" / "not understood" tap on a page guide is counted per page and India day (no person, no phone),
plus how far the person had to go: simpler words -> shown on the screen -> told the chat what to do. Staff see the
pages people do not understand first, so that page's guide (or the page) gets fixed.
"""
from __future__ import annotations

import re
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

IST = timezone(timedelta(hours=5, minutes=30))
STEPS = ("understood", "not_understood", "simpler", "shown", "told")
SCHEMA = ("CREATE TABLE IF NOT EXISTS guide_feedback (day TEXT NOT NULL, path TEXT NOT NULL, step TEXT NOT NULL,"
          " n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, path, step))",)
_PATH = re.compile(r"^/[A-Za-z0-9_:/\-]{0,119}$")


class GuideFeedback:
    def __init__(self, db_path: str, clock=lambda: datetime.now(timezone.utc)) -> None:
        self.db_path = db_path
        self.clock = clock
        with closing(sqlite3.connect(db_path)) as conn:
            for sql in SCHEMA:
                conn.execute(sql)
            conn.commit()

    def record(self, path: str, step: str) -> bool:
        """``path`` is the router PATTERN (e.g. /pos/:id/sale), never a real id; anything else is refused."""
        if step not in STEPS or not _PATH.match(path or "") or re.search(r"/\d{3,}|[a-f0-9]{16,}", path):
            return False
        day = self.clock().astimezone(IST).strftime("%Y-%m-%d")
        with closing(sqlite3.connect(self.db_path)) as conn:
            conn.execute("INSERT INTO guide_feedback (day, path, step, n) VALUES (?,?,?,1) ON CONFLICT(day, path, step)"
                         " DO UPDATE SET n = n + 1", (day, path, step))
            conn.commit()
        return True

    def pages(self, days: int = 30) -> List[Dict[str, Any]]:
        """Pages by how often people did not understand them (last ``days`` days)."""
        since = (self.clock().astimezone(IST) - timedelta(days=days)).strftime("%Y-%m-%d")
        with closing(sqlite3.connect(self.db_path)) as conn:
            rows = conn.execute("SELECT path, step, SUM(n) FROM guide_feedback WHERE day >= ? GROUP BY path, step",
                                (since,)).fetchall()
        by: Dict[str, Dict[str, Any]] = {}
        for path, step, n in rows:
            by.setdefault(path, {"path": path, **{s: 0 for s in STEPS}})[step] = int(n or 0)
        out = list(by.values())
        for row in out:
            asked = row["understood"] + row["not_understood"]
            row["not_understood_share"] = round(row["not_understood"] / asked, 3) if asked else None
        out.sort(key=lambda r: (-r["not_understood"], -(r["not_understood_share"] or 0)))
        return out
