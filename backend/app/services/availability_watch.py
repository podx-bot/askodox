""""Tell me when it is available" (owner request 2026-10-29).

When a search finds nothing, the buyer can ask to be told later. A watch is
the buyer's own subject (+ optional area / category); it lives 30 days. The
background runner (periodic_jobs "availability") looks for a listing that
appeared AFTER the watch was made -- a registered seller's active listing or a
LIVE staff-curated item -- whose title carries every content word of the
subject (strict, so nobody is spammed with near misses), then sends ONE push
and marks the watch NOTIFIED. Buyer identity stays with the watch only; events
carry the subject, never the person.
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Iterable

from app.services.demand_insights import area_key

WATCH_DAYS = 30
MAX_ACTIVE_PER_USER = 20


def now() -> datetime:
    return datetime.now(timezone.utc)


_STOP = {"show", "me", "find", "need", "want", "buy", "a", "an", "the", "for", "in", "near", "i", "to", "of",
         "and", "some", "please", "best", "good", "cheap", "online", "new"}


def _words(text: Any) -> set[str]:
    """Content words incl. model tokens (X10 stays X10; subject_key drops digits)."""
    import re

    return {w for w in re.findall(r"[^\W_]+", str(text or "").casefold()) if w not in _STOP and len(w) > 1}


def title_matches(subject: str, title: str) -> bool:
    """Every content word of the watched subject appears in the item title."""
    wanted = _words(subject)
    return bool(wanted) and wanted <= _words(title)


@dataclass
class AvailabilityWatches:
    db_path: str

    def __post_init__(self) -> None:
        with self._connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS availability_watches ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, app_user_id TEXT NOT NULL, subject TEXT NOT NULL, "
                "subject_key TEXT NOT NULL, area TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '', "
                "status TEXT NOT NULL DEFAULT 'ACTIVE', created_at TEXT NOT NULL, expires_at TEXT NOT NULL, "
                "notified_at TEXT, matched_title TEXT NOT NULL DEFAULT '', matched_source TEXT NOT NULL DEFAULT '')")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_availability_watches_status ON availability_watches(status)")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _public(row: sqlite3.Row) -> dict[str, Any]:
        item = dict(row)
        item.pop("app_user_id", None)
        return item

    def create(self, app_user: str, subject: str, *, location: str = "", category: str = "",
               at: datetime | None = None) -> dict[str, Any]:
        moment = at or now()
        clean = " ".join(str(subject or "").split())[:120]
        key = " ".join(sorted(_words(clean)))
        if not key:
            raise ValueError("Say what you are looking for")
        with self._connect() as conn:
            existing = conn.execute(
                "SELECT * FROM availability_watches WHERE app_user_id=? AND subject_key=? AND status='ACTIVE' "
                "AND expires_at > ?", (app_user, key, moment.isoformat())).fetchone()
            if existing is not None:
                return {**self._public(existing), "already": True}
            active = conn.execute("SELECT COUNT(*) FROM availability_watches WHERE app_user_id=? AND status='ACTIVE' "
                                  "AND expires_at > ?", (app_user, moment.isoformat())).fetchone()[0]
            if active >= MAX_ACTIVE_PER_USER:
                raise ValueError(f"You can keep up to {MAX_ACTIVE_PER_USER} alerts -- remove one first")
            cur = conn.execute(
                "INSERT INTO availability_watches(app_user_id, subject, subject_key, area, category, created_at, expires_at) "
                "VALUES(?,?,?,?,?,?,?)",
                (app_user, clean, key, area_key(location), str(category or "")[:60], moment.isoformat(),
                 (moment + timedelta(days=WATCH_DAYS)).isoformat()))
            row = conn.execute("SELECT * FROM availability_watches WHERE id=?", (cur.lastrowid,)).fetchone()
        return {**self._public(row), "already": False}

    def mine(self, app_user: str) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM availability_watches WHERE app_user_id=? ORDER BY id DESC LIMIT 100",
                                (app_user,)).fetchall()
        return [self._public(r) for r in rows]

    def cancel(self, app_user: str, watch_id: int) -> bool:
        with self._connect() as conn:
            return conn.execute("UPDATE availability_watches SET status='CANCELLED' WHERE id=? AND app_user_id=? "
                                "AND status='ACTIVE'", (int(watch_id), app_user)).rowcount > 0

    def active(self, at: datetime | None = None, limit: int = 500) -> list[dict[str, Any]]:
        moment = at or now()
        with self._connect() as conn:
            conn.execute("UPDATE availability_watches SET status='EXPIRED' WHERE status='ACTIVE' AND expires_at <= ?",
                         (moment.isoformat(),))
            rows = conn.execute("SELECT * FROM availability_watches WHERE status='ACTIVE' ORDER BY id LIMIT ?",
                                (int(limit),)).fetchall()
        return [dict(r) for r in rows]

    def mark_notified(self, watch_id: int, *, title: str, source: str, at: datetime | None = None) -> bool:
        with self._connect() as conn:
            return conn.execute(
                "UPDATE availability_watches SET status='NOTIFIED', notified_at=?, matched_title=?, matched_source=? "
                "WHERE id=? AND status='ACTIVE'",
                ((at or now()).isoformat(), title[:160], source[:40], int(watch_id))).rowcount > 0

    def delete_user(self, app_user: str) -> int:
        with self._connect() as conn:
            return conn.execute("DELETE FROM availability_watches WHERE app_user_id=?", (app_user,)).rowcount


Finder = Callable[[dict[str, Any]], Iterable[dict[str, Any]]]


def _newer(row: dict[str, Any], since: str) -> bool:
    stamp = str(row.get("created_at") or row.get("updated_at") or "")
    if not stamp:
        return False
    try:
        a = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        b = datetime.fromisoformat(since)
        if a.tzinfo is None:
            a = a.replace(tzinfo=timezone.utc)
        return a > b
    except ValueError:
        return stamp > since


def _title(row: dict[str, Any]) -> str:
    return " ".join(str(row.get(k) or "") for k in ("brand", "subject", "title", "variant")).strip()


def finders(container: Any) -> list[tuple[str, Finder]]:
    """Where a newly available item can come from (same stores as results)."""
    out: list[tuple[str, Finder]] = []
    repo = getattr(container, "product_catalog_repository", None)
    if repo is not None:
        out.append(("seller", lambda w: repo.search_active(w["subject"], limit=20)))
    try:
        from app.services import affiliate_catalog as ac

        catalog = getattr(container, "affiliate_catalog", None) or ac.AffiliateCatalog(container.settings.database_path)
        out.append(("catalog", lambda w: catalog.search(w["subject"], limit=10)))
    except Exception:
        pass
    return out


def run(container: Any, store: AvailabilityWatches, *, notify: Callable[..., int] | None = None,
        sources: list[tuple[str, Finder]] | None = None, record: Callable[..., Any] | None = None,
        at: datetime | None = None) -> dict[str, Any]:
    """One pass: every active watch, every source; one push per watch."""
    moment = at or now()
    matched = pushed = 0
    for watch in store.active(moment):
        for source, find in (sources if sources is not None else finders(container)):
            try:
                rows = list(find(watch) or [])
            except Exception:
                continue
            hit = next((r for r in rows if title_matches(watch["subject"], _title(r))
                        and _newer(r, watch["created_at"])), None)
            if hit is None:
                continue
            title = _title(hit)
            if not store.mark_notified(watch["id"], title=title, source=source, at=moment):
                break
            matched += 1
            if notify is not None:
                pushed += int(notify(watch["app_user_id"], title="మీరు అడిగింది ఇప్పుడు దొరుకుతుంది",
                                     body=f"{watch['subject']}: {title}"[:170],
                                     route=f"/?ask={watch['subject']}", event_key=f"availability:{watch['id']}") or 0)
            if record is not None:
                try:
                    record("availability_alert", detail={"subject": watch["subject"], "source": source},
                           category=watch.get("category") or "", location=watch.get("area") or "",
                           source="availability_watch")
                except Exception:
                    pass
            break
    return {"matched": matched, "pushed": pushed}
