"""Work Mode teams (owner decision 2026-11-09).

Family or friends do the same Work Mode job together: each person's phone
counts their own steps and moves their own worker in the shared scene; the
team card shows who did how much today.

What is shared, and nothing more: the name each person types for the team, the
outfit of their worker, and their step TOTAL per day. No location, no number,
no account id ever leaves this service (members are told apart by a per-team
``member`` reference). Anyone can leave at any time; the last one out deletes
the team.

A team has a 6-letter invite code (no look-alike letters). The creator picks
the job and task size; people who join take the same job.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
import uuid
from contextlib import closing
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

MAX_MEMBERS = 4
MAX_TEAMS_PER_PERSON = 1
MAX_DAY_STEPS = 100_000
ACTIVE_MINUTES = 10
_CODE_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
WEARS = ("lungi", "saree", "shirt")
SIZES = ("small", "medium", "large")

SCHEMA = """
CREATE TABLE IF NOT EXISTS work_teams (
    id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, job TEXT NOT NULL,
    size TEXT NOT NULL, created_by TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS work_team_members (
    team_id TEXT NOT NULL, user_id TEXT NOT NULL, member TEXT NOT NULL, name TEXT NOT NULL,
    wear TEXT NOT NULL, joined_at TEXT NOT NULL, PRIMARY KEY (team_id, user_id));
CREATE TABLE IF NOT EXISTS work_team_steps (
    team_id TEXT NOT NULL, user_id TEXT NOT NULL, day TEXT NOT NULL, steps INTEGER NOT NULL,
    moved_at TEXT, updated_at TEXT NOT NULL, PRIMARY KEY (team_id, user_id, day));
"""


class TeamError(Exception):
    def __init__(self, code: str, status: int = 400) -> None:
        super().__init__(code)
        self.code = code
        self.status = status


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _clean_name(name: str) -> str:
    text = " ".join((name or "").split())[:24]
    if not text:
        raise TeamError("NAME_REQUIRED")
    return text


def _valid_day(day: str) -> str:
    try:
        parsed = date.fromisoformat(day)
    except (TypeError, ValueError):
        raise TeamError("BAD_DAY") from None
    today = _now().date()
    # The phone's own date may be a day ahead or behind UTC; older days are closed.
    if not today - timedelta(days=2) <= parsed <= today + timedelta(days=1):
        raise TeamError("BAD_DAY")
    return parsed.isoformat()


class WorkTeams:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with closing(self._db()) as db:
            db.executescript(SCHEMA)
            db.commit()

    def _db(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.db_path, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    @staticmethod
    def _member_ref(team_id: str, user_id: str) -> str:
        return "m_" + hashlib.sha256(f"{team_id}:{user_id}".encode()).hexdigest()[:10]

    def _team_of(self, db: sqlite3.Connection, user_id: str) -> Optional[sqlite3.Row]:
        return db.execute(
            "SELECT t.* FROM work_teams t JOIN work_team_members m ON m.team_id = t.id WHERE m.user_id = ?",
            (user_id,),
        ).fetchone()

    def create(self, user_id: str, *, name: str, team_name: str, job: str, size: str, wear: str) -> Dict[str, Any]:
        job = (job or "").strip()[:40]
        if not job:
            raise TeamError("JOB_REQUIRED")
        size = size if size in SIZES else "medium"
        wear = wear if wear in WEARS else "lungi"
        with closing(self._db()) as db:
            if self._team_of(db, user_id) is not None:
                raise TeamError("ALREADY_IN_TEAM", 409)
            team_id = "wt_" + uuid.uuid4().hex[:12]
            for _ in range(20):
                code = "".join(secrets.choice(_CODE_LETTERS) for _ in range(6))
                if db.execute("SELECT 1 FROM work_teams WHERE code = ?", (code,)).fetchone() is None:
                    break
            else:  # pragma: no cover - 31^6 codes
                raise TeamError("TRY_AGAIN", 503)
            now = _now().isoformat()
            db.execute(
                "INSERT INTO work_teams (id, code, name, job, size, created_by, created_at) VALUES (?,?,?,?,?,?,?)",
                (team_id, code, " ".join((team_name or "").split())[:40] or _clean_name(name), job, size, user_id, now),
            )
            db.execute(
                "INSERT INTO work_team_members (team_id, user_id, member, name, wear, joined_at) VALUES (?,?,?,?,?,?)",
                (team_id, user_id, self._member_ref(team_id, user_id), _clean_name(name), wear, now),
            )
            db.commit()
        return self.mine(user_id, day=_now().date().isoformat())

    def join(self, user_id: str, *, code: str, name: str, wear: str) -> Dict[str, Any]:
        code = "".join(ch for ch in (code or "").upper() if ch.isalnum())
        wear = wear if wear in WEARS else "lungi"
        with closing(self._db()) as db:
            team = db.execute("SELECT * FROM work_teams WHERE code = ?", (code,)).fetchone()
            if team is None:
                raise TeamError("CODE_NOT_FOUND", 404)
            current = self._team_of(db, user_id)
            if current is not None:
                if current["id"] == team["id"]:
                    return self.mine(user_id, day=_now().date().isoformat())
                raise TeamError("ALREADY_IN_TEAM", 409)
            count = db.execute("SELECT COUNT(*) FROM work_team_members WHERE team_id = ?", (team["id"],)).fetchone()[0]
            if count >= MAX_MEMBERS:
                raise TeamError("TEAM_FULL", 409)
            db.execute(
                "INSERT INTO work_team_members (team_id, user_id, member, name, wear, joined_at) VALUES (?,?,?,?,?,?)",
                (team["id"], user_id, self._member_ref(team["id"], user_id), _clean_name(name), wear, _now().isoformat()),
            )
            db.commit()
        return self.mine(user_id, day=_now().date().isoformat())

    def leave(self, user_id: str) -> Dict[str, Any]:
        with closing(self._db()) as db:
            team = self._team_of(db, user_id)
            if team is None:
                return {"left": False}
            db.execute("DELETE FROM work_team_members WHERE team_id = ? AND user_id = ?", (team["id"], user_id))
            db.execute("DELETE FROM work_team_steps WHERE team_id = ? AND user_id = ?", (team["id"], user_id))
            left = db.execute("SELECT COUNT(*) FROM work_team_members WHERE team_id = ?", (team["id"],)).fetchone()[0]
            if left == 0:
                db.execute("DELETE FROM work_team_steps WHERE team_id = ?", (team["id"],))
                db.execute("DELETE FROM work_teams WHERE id = ?", (team["id"],))
            db.commit()
        return {"left": True}

    def report_steps(self, user_id: str, *, day: str, steps: int) -> Dict[str, Any]:
        day = _valid_day(day)
        steps = max(0, min(int(steps), MAX_DAY_STEPS))
        with closing(self._db()) as db:
            team = self._team_of(db, user_id)
            if team is None:
                raise TeamError("NOT_IN_TEAM", 404)
            row = db.execute(
                "SELECT steps, moved_at FROM work_team_steps WHERE team_id = ? AND user_id = ? AND day = ?",
                (team["id"], user_id, day),
            ).fetchone()
            now = _now().isoformat()
            # A day's total only grows (the phone counts up); a smaller number is ignored.
            if row is None:
                db.execute(
                    "INSERT INTO work_team_steps (team_id, user_id, day, steps, moved_at, updated_at) VALUES (?,?,?,?,?,?)",
                    (team["id"], user_id, day, steps, now if steps > 0 else None, now),
                )
            elif steps > row["steps"]:
                db.execute(
                    "UPDATE work_team_steps SET steps = ?, moved_at = ?, updated_at = ? "
                    "WHERE team_id = ? AND user_id = ? AND day = ?",
                    (steps, now, now, team["id"], user_id, day),
                )
            db.commit()
        return self.mine(user_id, day=day)

    def mine(self, user_id: str, *, day: str) -> Dict[str, Any]:
        day = _valid_day(day)
        with closing(self._db()) as db:
            team = self._team_of(db, user_id)
            if team is None:
                return {"team": None}
            rows = db.execute(
                "SELECT m.user_id, m.member, m.name, m.wear, m.joined_at, s.steps, s.moved_at "
                "FROM work_team_members m LEFT JOIN work_team_steps s "
                "ON s.team_id = m.team_id AND s.user_id = m.user_id AND s.day = ? "
                "WHERE m.team_id = ? ORDER BY m.joined_at",
                (day, team["id"]),
            ).fetchall()
        cutoff = _now() - timedelta(minutes=ACTIVE_MINUTES)
        members: List[Dict[str, Any]] = []
        for row in rows:
            moved = row["moved_at"]
            active = bool(moved) and datetime.fromisoformat(moved) >= cutoff
            members.append({
                "member": row["member"],
                "name": row["name"],
                "wear": row["wear"],
                "steps": int(row["steps"] or 0),
                "active": active,
                "me": row["user_id"] == user_id,
            })
        return {
            "team": {
                "code": team["code"],
                "name": team["name"],
                "job": team["job"],
                "size": team["size"],
                "day": day,
                "max_members": MAX_MEMBERS,
                "members": members,
            }
        }

    def delete_user(self, user_id: str) -> None:
        """Account deletion: leave the team (its other members keep it)."""
        self.leave(user_id)
