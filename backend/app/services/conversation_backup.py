"""Chat history backup per account, so History survives uninstall / reinstall /
a new phone. The app keeps its own copy (fast, offline) and mirrors every saved
conversation here; after a fresh install it restores from here.

Stored as the app's own opaque snapshot (the user's own conversations), at most
MAX_CONVERSATIONS per account (oldest dropped) and MAX_BYTES each. Exported with
the account (table has user_id) and deleted with it (account_privacy).
"""
from __future__ import annotations

import json
import sqlite3
import time
from contextlib import closing
from typing import Any, Dict, List

MAX_CONVERSATIONS = 200
MAX_BYTES = 400_000

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS conversation_backups (user_id TEXT NOT NULL, conversation_id TEXT NOT NULL,"
    " title TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', updated_at TEXT NOT NULL,"
    " snapshot TEXT NOT NULL, saved_at REAL NOT NULL, PRIMARY KEY (user_id, conversation_id))"
)


class BackupError(ValueError):
    pass


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute(SCHEMA)
    return conn


def save(db_path: str, user_id: str, conversation_id: str, snapshot: Dict[str, Any]) -> Dict[str, Any]:
    cid = str(conversation_id or "").strip()[:80]
    if not cid:
        raise BackupError("conversation id missing")
    raw = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"))
    if len(raw.encode("utf-8")) > MAX_BYTES:
        raise BackupError("conversation too large to back up")
    title = str(snapshot.get("title") or "")[:200]
    status = str(snapshot.get("status") or "active")[:20]
    updated = str(snapshot.get("updatedAt") or "")[:40]
    with closing(_connect(db_path)) as conn:
        existing = conn.execute("SELECT updated_at FROM conversation_backups WHERE user_id=? AND conversation_id=?",
                                (user_id, cid)).fetchone()
        if existing is not None and existing["updated_at"] > updated:
            return {"saved": False, "reason": "newer_copy_kept", "id": cid}  # an older phone copy never wins
        conn.execute("INSERT OR REPLACE INTO conversation_backups (user_id, conversation_id, title, status, updated_at,"
                     " snapshot, saved_at) VALUES (?,?,?,?,?,?,?)", (user_id, cid, title, status, updated, raw, time.time()))
        conn.execute("DELETE FROM conversation_backups WHERE user_id=? AND conversation_id NOT IN (SELECT conversation_id"
                     " FROM conversation_backups WHERE user_id=? ORDER BY updated_at DESC LIMIT ?)",
                     (user_id, user_id, MAX_CONVERSATIONS))
        conn.commit()
    return {"saved": True, "id": cid}


def list_all(db_path: str, user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        rows = conn.execute("SELECT snapshot FROM conversation_backups WHERE user_id=? ORDER BY updated_at DESC LIMIT ?",
                            (user_id, max(1, min(limit, MAX_CONVERSATIONS)))).fetchall()
    out = []
    for r in rows:
        try:
            out.append(json.loads(r["snapshot"]))
        except ValueError:
            continue
    return out


def delete(db_path: str, user_id: str, conversation_id: str | None = None) -> int:
    with closing(_connect(db_path)) as conn:
        if conversation_id is None:
            n = conn.execute("DELETE FROM conversation_backups WHERE user_id=?", (user_id,)).rowcount
        else:
            n = conn.execute("DELETE FROM conversation_backups WHERE user_id=? AND conversation_id=?",
                             (user_id, conversation_id)).rowcount
        conn.commit()
    return n


def recent_requests(db_path: str, user_id: str, limit: int = 8) -> List[str]:
    """Short lines of what this user asked before (their own words, newest first) for the brain."""
    lines: List[str] = []
    with closing(_connect(db_path)) as conn:
        rows = conn.execute("SELECT title, status, updated_at FROM conversation_backups WHERE user_id=? AND title != ''"
                            " ORDER BY updated_at DESC LIMIT ?", (user_id, limit)).fetchall()
    for r in rows:
        lines.append(f"{r['updated_at'][:10]}: asked about \"{r['title'][:120]}\" ({r['status']})")
    return lines
