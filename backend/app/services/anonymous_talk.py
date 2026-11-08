"""ASKODOX Talk -- anonymous topic discussions (owner decision 2026-11-08).

A person searches a topic ("paddy prices", "cricket"), joins its room and talks
with others about it. Nobody sees who anybody is:

* Each person gets a made-up name PER ROOM ("నీలి చిలుక 42" / "Blue Parrot 42"),
  derived from a keyed hash, so it stays the same in that room but cannot be
  traced back. The API never returns a user id, number or another person's
  real anything; a person's own messages only carry ``mine: true``.
* Anonymous to people, not to ASKODOX: rows keep the OTP-proven account id so
  staff can act on complaints and lawful requests (Indian IT Rules).
* Every message passes ``talk_moderation.check`` first: contacts hidden, rude
  words masked, severe messages held (never shown). Held messages count as a
  strike; three strikes in a day mute the person for a day.
* Three different people reporting a message hide it until staff decide.
  A person can block an author (by message): that author's messages disappear
  for them in every room.

Reading text costs nothing extra; hearing a message read aloud is one AI
Credits ``voice`` use (the app says so before anyone taps it).
"""
from __future__ import annotations

import hashlib
import hmac
import re
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services import talk_moderation

MAX_TEXT = 500
STRIKES_TO_MUTE = 3
MUTE_HOURS = 24
REPORTS_TO_HIDE = 3

_ADJ = [("నీలి", "Blue"), ("ఎర్ర", "Red"), ("పచ్చ", "Green"), ("బంగారు", "Golden"), ("వెండి", "Silver"),
        ("చురుకైన", "Swift"), ("నిశ్శబ్ద", "Quiet"), ("ధైర్య", "Brave"), ("తెలివైన", "Clever"), ("సంతోష", "Happy"),
        ("చల్లని", "Cool"), ("మెరిసే", "Shining")]
_ANIMAL = [("చిలుక", "Parrot"), ("నెమలి", "Peacock"), ("పులి", "Tiger"), ("ఏనుగు", "Elephant"), ("జింక", "Deer"),
           ("కోయిల", "Cuckoo"), ("గుర్రం", "Horse"), ("డేగ", "Eagle"), ("తాబేలు", "Turtle"), ("కుందేలు", "Rabbit"),
           ("సింహం", "Lion"), ("హంస", "Swan")]

SCHEMA = """
CREATE TABLE IF NOT EXISTS talk_rooms (
    id TEXT PRIMARY KEY, topic TEXT NOT NULL, topic_key TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL, last_active TEXT NOT NULL, messages INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS talk_messages (
    id TEXT PRIMARY KEY, room_id TEXT NOT NULL, seq INTEGER NOT NULL, user_id TEXT NOT NULL,
    alias TEXT NOT NULL, alias_en TEXT NOT NULL, text TEXT NOT NULL, kind TEXT NOT NULL,
    status TEXT NOT NULL, category TEXT NOT NULL, masked INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS talk_messages_room ON talk_messages(room_id, seq);
CREATE TABLE IF NOT EXISTS talk_reports (
    message_id TEXT NOT NULL, reporter TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'OPEN', PRIMARY KEY (message_id, reporter));
CREATE TABLE IF NOT EXISTS talk_blocks (
    blocker TEXT NOT NULL, blocked TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (blocker, blocked));
CREATE TABLE IF NOT EXISTS talk_strikes (
    user_id TEXT NOT NULL, category TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS talk_mutes (user_id TEXT PRIMARY KEY, until TEXT NOT NULL);
"""


class TalkError(Exception):
    def __init__(self, code: str, status: int = 400) -> None:
        super().__init__(code)
        self.code = code
        self.status = status


def _now() -> datetime:
    return datetime.now(timezone.utc)


def topic_key(topic: str) -> str:
    """Same topic, same room: case, spaces and punctuation do not matter."""
    words = re.findall(r"[\w]+", topic.lower(), flags=re.UNICODE)
    return " ".join(words)[:80]


class AnonymousTalk:
    def __init__(self, db_path: str, secret: str) -> None:
        self.db_path = db_path
        self._secret = (secret or "askodox-talk").encode()
        with closing(self._connect()) as conn, conn:
            conn.executescript(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------------------------------------------------- names

    def alias(self, user_id: str, room_id: str) -> tuple[str, str]:
        digest = hmac.new(self._secret, f"{room_id}|{user_id}".encode(), hashlib.sha256).digest()
        adj = _ADJ[digest[0] % len(_ADJ)]
        animal = _ANIMAL[digest[1] % len(_ANIMAL)]
        number = 10 + digest[2] % 90
        return f"{adj[0]} {animal[0]} {number}", f"{adj[1]} {animal[1]} {number}"

    # ---------------------------------------------------------- rooms

    def rooms(self, query: str = "", limit: int = 30) -> List[Dict[str, Any]]:
        key = topic_key(query)
        with closing(self._connect()) as conn:
            if key:
                rows = conn.execute(
                    "SELECT * FROM talk_rooms WHERE topic_key LIKE ? ORDER BY last_active DESC LIMIT ?",
                    (f"%{key}%", limit)).fetchall()
            else:
                rows = conn.execute("SELECT * FROM talk_rooms ORDER BY last_active DESC LIMIT ?", (limit,)).fetchall()
        return [self._room(r) for r in rows]

    @staticmethod
    def _room(row: sqlite3.Row) -> Dict[str, Any]:
        return {"id": row["id"], "topic": row["topic"], "messages": row["messages"], "last_active": row["last_active"]}

    def open_room(self, topic: str, user_id: str,
                  write_text: Optional[Callable[..., str]] = None) -> Dict[str, Any]:
        """Joins the room for this topic, starting it when it is new. A topic
        name is checked like a message (no contacts, no rude or severe words)."""
        clean = re.sub(r"\s+", " ", topic or "").strip()
        if len(clean) < 2 or len(clean) > 80:
            raise TalkError("topic_length")
        key = topic_key(clean)
        if not key:
            raise TalkError("topic_length")
        verdict = talk_moderation.check(clean, write_text)
        if not verdict.visible or verdict.masked_words or verdict.contacts_hidden:
            raise TalkError("topic_not_allowed")
        now = _now().isoformat()
        with closing(self._connect()) as conn, conn:
            row = conn.execute("SELECT * FROM talk_rooms WHERE topic_key = ?", (key,)).fetchone()
            if row is None:
                room_id = "tr_" + uuid.uuid4().hex[:16]
                conn.execute("INSERT INTO talk_rooms (id, topic, topic_key, created_at, last_active) VALUES (?,?,?,?,?)",
                             (room_id, clean, key, now, now))
                row = conn.execute("SELECT * FROM talk_rooms WHERE id = ?", (room_id,)).fetchone()
        room = self._room(row)
        te, en = self.alias(user_id, room["id"])
        return {**room, "you": {"alias": te, "alias_en": en}}

    def room(self, room_id: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM talk_rooms WHERE id = ?", (room_id,)).fetchone()
        if row is None:
            raise TalkError("room_not_found", 404)
        return self._room(row)

    # ---------------------------------------------------------- messages

    def muted_until(self, user_id: str) -> Optional[str]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT until FROM talk_mutes WHERE user_id = ?", (user_id,)).fetchone()
        if row and row["until"] > _now().isoformat():
            return row["until"]
        return None

    def post(self, room_id: str, user_id: str, text: str, kind: str = "text",
             write_text: Optional[Callable[..., str]] = None) -> Dict[str, Any]:
        self.room(room_id)
        if kind not in ("text", "voice"):
            raise TalkError("bad_kind")
        body = (text or "").strip()
        if not body:
            raise TalkError("empty")
        if len(body) > MAX_TEXT:
            raise TalkError("too_long")
        until = self.muted_until(user_id)
        if until:
            raise TalkError("muted", 403)
        verdict = talk_moderation.check(body, write_text)
        te, en = self.alias(user_id, room_id)
        now = _now()
        message_id = "tm_" + uuid.uuid4().hex[:16]
        status = "VISIBLE" if verdict.visible else "HELD"
        with closing(self._connect()) as conn, conn:
            seq = (conn.execute("SELECT COALESCE(MAX(seq), 0) FROM talk_messages WHERE room_id = ?",
                                (room_id,)).fetchone()[0] or 0) + 1
            conn.execute(
                "INSERT INTO talk_messages (id, room_id, seq, user_id, alias, alias_en, text, kind, status, category,"
                " masked, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (message_id, room_id, seq, user_id, te, en, verdict.text, kind, status, verdict.category,
                 verdict.masked_words, now.isoformat()))
            if verdict.visible:
                conn.execute("UPDATE talk_rooms SET last_active = ?, messages = messages + 1 WHERE id = ?",
                             (now.isoformat(), room_id))
            elif verdict.category != "self_harm":
                conn.execute("INSERT INTO talk_strikes (user_id, category, created_at) VALUES (?,?,?)",
                             (user_id, verdict.category, now.isoformat()))
                since = (now - timedelta(hours=24)).isoformat()
                strikes = conn.execute("SELECT COUNT(*) FROM talk_strikes WHERE user_id = ? AND created_at > ?",
                                       (user_id, since)).fetchone()[0]
                if strikes >= STRIKES_TO_MUTE:
                    conn.execute("INSERT OR REPLACE INTO talk_mutes (user_id, until) VALUES (?, ?)",
                                 (user_id, (now + timedelta(hours=MUTE_HOURS)).isoformat()))
        out = {"id": message_id, "seq": seq, "posted": verdict.visible, "category": verdict.category,
               "text": verdict.text, "masked_words": verdict.masked_words, "contacts_hidden": verdict.contacts_hidden}
        if not verdict.visible:
            out["muted_until"] = self.muted_until(user_id)
        return out

    def messages(self, room_id: str, viewer: str, after: int = 0, limit: int = 60) -> List[Dict[str, Any]]:
        self.room(room_id)
        with closing(self._connect()) as conn:
            blocked = {r["blocked"] for r in conn.execute("SELECT blocked FROM talk_blocks WHERE blocker = ?", (viewer,))}
            rows = conn.execute(
                "SELECT * FROM talk_messages WHERE room_id = ? AND seq > ? AND status = 'VISIBLE' ORDER BY seq DESC"
                " LIMIT ?", (room_id, after, limit)).fetchall()
        out = []
        for row in reversed(rows):
            if row["user_id"] in blocked:
                continue
            out.append({"id": row["id"], "seq": row["seq"], "alias": row["alias"], "alias_en": row["alias_en"],
                        "text": row["text"], "kind": row["kind"], "masked": bool(row["masked"]),
                        "mine": row["user_id"] == viewer, "created_at": row["created_at"]})
        return out

    def _message(self, message_id: str) -> sqlite3.Row:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM talk_messages WHERE id = ?", (message_id,)).fetchone()
        if row is None:
            raise TalkError("message_not_found", 404)
        return row

    def visible_text(self, message_id: str) -> str:
        row = self._message(message_id)
        if row["status"] != "VISIBLE":
            raise TalkError("message_not_found", 404)
        return str(row["text"])

    # ---------------------------------------------------------- safety

    def report(self, message_id: str, reporter: str, reason: str) -> Dict[str, Any]:
        row = self._message(message_id)
        if row["user_id"] == reporter:
            raise TalkError("own_message")
        now = _now().isoformat()
        with closing(self._connect()) as conn, conn:
            conn.execute("INSERT OR IGNORE INTO talk_reports (message_id, reporter, reason, created_at)"
                         " VALUES (?,?,?,?)", (message_id, reporter, (reason or "other")[:40], now))
            count = conn.execute("SELECT COUNT(*) FROM talk_reports WHERE message_id = ?", (message_id,)).fetchone()[0]
            hidden = False
            if count >= REPORTS_TO_HIDE and row["status"] == "VISIBLE":
                conn.execute("UPDATE talk_messages SET status = 'REPORTED' WHERE id = ?", (message_id,))
                hidden = True
        return {"reported": True, "reports": count, "hidden": hidden}

    def block(self, message_id: str, blocker: str) -> Dict[str, Any]:
        row = self._message(message_id)
        if row["user_id"] == blocker:
            raise TalkError("own_message")
        with closing(self._connect()) as conn, conn:
            conn.execute("INSERT OR IGNORE INTO talk_blocks (blocker, blocked, created_at) VALUES (?,?,?)",
                         (blocker, row["user_id"], _now().isoformat()))
        return {"blocked": True}

    # ---------------------------------------------------------- staff

    def open_reports(self, limit: int = 100) -> List[Dict[str, Any]]:
        """For staff: reported messages with counts and reasons. Staff see the
        message and its alias, not the author's number (that needs a lawful
        request, handled outside the app)."""
        with closing(self._connect()) as conn:
            rows = conn.execute(
                "SELECT m.id, m.room_id, m.alias_en, m.text, m.status, m.category, COUNT(r.reporter) AS reports,"
                " GROUP_CONCAT(DISTINCT r.reason) AS reasons, MAX(r.created_at) AS last_report"
                " FROM talk_reports r JOIN talk_messages m ON m.id = r.message_id WHERE r.status = 'OPEN'"
                " GROUP BY m.id ORDER BY reports DESC, last_report DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]

    def decide(self, message_id: str, remove: bool) -> Dict[str, Any]:
        row = self._message(message_id)
        status = "REMOVED" if remove else "VISIBLE"
        with closing(self._connect()) as conn, conn:
            conn.execute("UPDATE talk_messages SET status = ? WHERE id = ?", (status, message_id))
            conn.execute("UPDATE talk_reports SET status = ? WHERE message_id = ?",
                         ("ACTIONED" if remove else "DISMISSED", message_id))
            if remove:
                conn.execute("INSERT INTO talk_strikes (user_id, category, created_at) VALUES (?,?,?)",
                             (row["user_id"], "reported", _now().isoformat()))
        return {"id": message_id, "status": status}
