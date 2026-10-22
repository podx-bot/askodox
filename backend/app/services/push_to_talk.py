"""ASKODOX push-to-talk (walkie-talkie) over the internet: hold to record a
short voice clip, the group hears it. Store-and-forward, not a live radio.

Limits that are stated, not hidden (master command 16):
- Works only with internet on both phones; phones cannot act as long-range
  offline radios (``device_registry`` lists that as unsupported_on_phone).
- Joining is explicit (a 6-character code shared by a member); only members
  can post or play clips; clips expire after ``CLIP_TTL_HOURS``.
- No background / hidden recording: the app records only while the user
  holds the button.
"""
from __future__ import annotations

import base64
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

CLIP_TTL_HOURS = 24
MAX_CLIP_BYTES = 1_500_000
MAX_CLIP_MS = 60_000
MAX_MEMBERS = 50
ALLOWED_MIME = {"audio/mp4", "audio/aac", "audio/m4a", "audio/x-m4a", "audio/ogg", "audio/opus", "audio/webm",
                "audio/mpeg", "audio/wav"}
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I confusion


class PttError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def _now() -> datetime:
    return datetime.now(timezone.utc)


class PushToTalk:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        self.clip_dir = Path(os.path.dirname(os.path.abspath(db_path)) or ".") / "ptt_clips"
        with self._connect() as conn:
            conn.executescript(
                "CREATE TABLE IF NOT EXISTS ptt_channels (id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL,"
                " name TEXT NOT NULL, owner_user_id TEXT NOT NULL, created_at TEXT NOT NULL);"
                "CREATE TABLE IF NOT EXISTS ptt_members (channel_id TEXT NOT NULL, app_user_id TEXT NOT NULL,"
                " display_name TEXT NOT NULL, joined_at TEXT NOT NULL, PRIMARY KEY(channel_id, app_user_id));"
                "CREATE TABLE IF NOT EXISTS ptt_clips (id TEXT PRIMARY KEY, channel_id TEXT NOT NULL,"
                " sender_user_id TEXT NOT NULL, sender_name TEXT NOT NULL, mime TEXT NOT NULL, duration_ms INTEGER,"
                " size INTEGER NOT NULL, path TEXT NOT NULL, created_at TEXT NOT NULL, expires_at TEXT NOT NULL);"
                "CREATE INDEX IF NOT EXISTS idx_ptt_clips_channel ON ptt_clips(channel_id, created_at);"
                "CREATE INDEX IF NOT EXISTS idx_ptt_members_user ON ptt_members(app_user_id);")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    # -------------------------------------------------------------- channels

    def _member(self, conn: sqlite3.Connection, channel_id: str, user_id: str) -> bool:
        return conn.execute("SELECT 1 FROM ptt_members WHERE channel_id=? AND app_user_id=?",
                            (channel_id, user_id)).fetchone() is not None

    def _channel(self, conn: sqlite3.Connection, channel_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM ptt_channels WHERE id=?", (channel_id,)).fetchone()
        if row is None:
            raise PttError(404, "channel not found")
        count = conn.execute("SELECT COUNT(*) FROM ptt_members WHERE channel_id=?", (channel_id,)).fetchone()[0]
        return {"id": row["id"], "code": row["code"], "name": row["name"], "members": count,
                "created_at": row["created_at"]}

    def create(self, user_id: str, name: str, display_name: str) -> Dict[str, Any]:
        name = " ".join(str(name or "").split())[:60] or "Group"
        display = " ".join(str(display_name or "").split())[:40] or "Member"
        channel_id = "ptt_" + uuid.uuid4().hex[:16]
        with self._connect() as conn:
            for _ in range(8):
                code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(6))
                try:
                    conn.execute("INSERT INTO ptt_channels (id, code, name, owner_user_id, created_at) VALUES (?,?,?,?,?)",
                                 (channel_id, code, name, user_id, _now().isoformat()))
                    break
                except sqlite3.IntegrityError:
                    continue
            else:
                raise PttError(503, "could not allocate a code, try again")
            conn.execute("INSERT INTO ptt_members (channel_id, app_user_id, display_name, joined_at) VALUES (?,?,?,?)",
                         (channel_id, user_id, display, _now().isoformat()))
            return self._channel(conn, channel_id)

    def join(self, user_id: str, code: str, display_name: str) -> Dict[str, Any]:
        code = str(code or "").strip().upper().replace(" ", "")
        display = " ".join(str(display_name or "").split())[:40] or "Member"
        with self._connect() as conn:
            row = conn.execute("SELECT id FROM ptt_channels WHERE code=?", (code,)).fetchone()
            if row is None:
                raise PttError(404, "no group with this code")
            channel_id = row["id"]
            if not self._member(conn, channel_id, user_id):
                count = conn.execute("SELECT COUNT(*) FROM ptt_members WHERE channel_id=?", (channel_id,)).fetchone()[0]
                if count >= MAX_MEMBERS:
                    raise PttError(409, "group is full")
                conn.execute("INSERT INTO ptt_members (channel_id, app_user_id, display_name, joined_at) VALUES (?,?,?,?)",
                             (channel_id, user_id, display, _now().isoformat()))
            return self._channel(conn, channel_id)

    def mine(self, user_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            ids = [r[0] for r in conn.execute("SELECT channel_id FROM ptt_members WHERE app_user_id=? ORDER BY joined_at DESC",
                                              (user_id,)).fetchall()]
            return [self._channel(conn, cid) for cid in ids]

    def leave(self, user_id: str, channel_id: str) -> bool:
        with self._connect() as conn:
            cur = conn.execute("DELETE FROM ptt_members WHERE channel_id=? AND app_user_id=?", (channel_id, user_id))
            left = cur.rowcount > 0
            remaining = conn.execute("SELECT COUNT(*) FROM ptt_members WHERE channel_id=?", (channel_id,)).fetchone()[0]
            if left and remaining == 0:
                self._delete_clips(conn, "channel_id=?", (channel_id,))
                conn.execute("DELETE FROM ptt_channels WHERE id=?", (channel_id,))
        return left

    # -------------------------------------------------------------- clips

    def _delete_clips(self, conn: sqlite3.Connection, where: str, args: tuple) -> int:
        rows = conn.execute(f"SELECT id, path FROM ptt_clips WHERE {where}", args).fetchall()
        for row in rows:
            try:
                os.remove(row["path"])
            except OSError:
                pass
        conn.execute(f"DELETE FROM ptt_clips WHERE {where}", args)
        return len(rows)

    def purge_expired(self) -> int:
        with self._connect() as conn:
            return self._delete_clips(conn, "expires_at < ?", (_now().isoformat(),))

    def post_clip(self, user_id: str, channel_id: str, *, audio_base64: str, mime: str, duration_ms: int) -> Dict[str, Any]:
        mime = str(mime or "").strip().lower()
        if mime not in ALLOWED_MIME:
            raise PttError(415, "send an audio clip (m4a / aac / ogg / mp3 / wav)")
        try:
            data = base64.b64decode(audio_base64 or "", validate=True)
        except (ValueError, TypeError) as error:
            raise PttError(400, "invalid audio data") from error
        if not data:
            raise PttError(400, "empty clip")
        if len(data) > MAX_CLIP_BYTES:
            raise PttError(413, "clip too long (about 60 seconds max)")
        if duration_ms is not None and (duration_ms < 0 or duration_ms > MAX_CLIP_MS + 2000):
            raise PttError(413, "clip too long (60 seconds max)")
        with self._connect() as conn:
            self._channel(conn, channel_id)
            if not self._member(conn, channel_id, user_id):
                raise PttError(403, "join the group first")
            name = conn.execute("SELECT display_name FROM ptt_members WHERE channel_id=? AND app_user_id=?",
                                (channel_id, user_id)).fetchone()["display_name"]
            clip_id = "clip_" + uuid.uuid4().hex[:20]
            self.clip_dir.mkdir(parents=True, exist_ok=True)
            path = self.clip_dir / f"{clip_id}.bin"
            path.write_bytes(data)
            now = _now()
            conn.execute(
                "INSERT INTO ptt_clips (id, channel_id, sender_user_id, sender_name, mime, duration_ms, size, path,"
                " created_at, expires_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                (clip_id, channel_id, user_id, name, mime, int(duration_ms or 0), len(data), str(path),
                 now.isoformat(), (now + timedelta(hours=CLIP_TTL_HOURS)).isoformat()))
        return {"id": clip_id, "channel_id": channel_id, "sender_name": name, "mine": True, "mime": mime,
                "duration_ms": int(duration_ms or 0), "created_at": now.isoformat()}

    def clips(self, user_id: str, channel_id: str, after: str = "") -> List[Dict[str, Any]]:
        self.purge_expired()
        with self._connect() as conn:
            self._channel(conn, channel_id)
            if not self._member(conn, channel_id, user_id):
                raise PttError(403, "join the group first")
            rows = conn.execute(
                "SELECT * FROM ptt_clips WHERE channel_id=? AND created_at > ? ORDER BY created_at ASC LIMIT 100",
                (channel_id, str(after or ""))).fetchall()
        return [{"id": r["id"], "channel_id": r["channel_id"], "sender_name": r["sender_name"],
                 "mine": r["sender_user_id"] == user_id, "mime": r["mime"], "duration_ms": r["duration_ms"],
                 "created_at": r["created_at"]} for r in rows]

    def audio(self, user_id: str, clip_id: str) -> tuple[bytes, str]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM ptt_clips WHERE id=?", (clip_id,)).fetchone()
            if row is None or row["expires_at"] < _now().isoformat():
                raise PttError(404, "clip not found or expired")
            if not self._member(conn, row["channel_id"], user_id):
                raise PttError(403, "members only")
        try:
            return Path(row["path"]).read_bytes(), row["mime"]
        except OSError as error:
            raise PttError(404, "clip not found") from error
