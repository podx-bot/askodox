"""School / tuition / college register (owner 2026-11-28, design canvas "ఈరోజు చూడాల్సినవి"; Business Kit way of working 7).

For EVERY place that keeps classes of children or students: a school, a tuition, a coaching centre, a play school, a
college (no per-category code: the Business Kit flow 7 decides which shop sees the page). The owner's rule is that AI
shows only PROBLEMS, so ``today`` is a short list of what needs a person, each with its people and a message DRAFT.

* class = a name + the teacher; student = name, class, parent name + phone, hostel yes / no;
* one register per class per day: the teacher lists who is ABSENT, everyone else is present; the day is "marked"
  once it is saved (a class that was never marked is a problem, not a day of full attendance);
* absent in a row: the days the class register was marked, Sundays skipped; three in a row is raised as a problem
  with a parent message DRAFT. It is a QUESTION to the parent, never an accusation (no "bunking" label);
* gate: a child leaves early or is picked up -- who came is checked against the parent's own ``pickups`` list (names
  the parent gave); a name not on the list is raised at once; every out-pass is kept with who / when / by whom;
* health room: a child who is sick (what, what was done, home / hospital), a follow-up day, and a "how is the child
  now" message DRAFT. Only the people with the customers permission see it; it is NEVER put in a report or a
  message that names the illness -- the draft says only that the school wants to check on the child.

Nothing here sends a message, charges or pays: every draft waits for the owner's own tap (WhatsApp ``wa.me``).
"""
from __future__ import annotations

import re
import sqlite3
import urllib.parse
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_school_classes (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " teacher TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_classes_biz ON pos_school_classes(business_id, status)",
    "CREATE TABLE IF NOT EXISTS pos_school_students (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, class_id TEXT NOT NULL,"
    " name TEXT NOT NULL, parent_name TEXT NOT NULL DEFAULT '', parent_phone TEXT NOT NULL DEFAULT '',"
    " hostel INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_students_biz ON pos_school_students(business_id, class_id, status)",
    "CREATE TABLE IF NOT EXISTS pos_school_pickups (id TEXT PRIMARY KEY, student_id TEXT NOT NULL, business_id TEXT NOT NULL,"
    " name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_pickups_student ON pos_school_pickups(student_id)",
    "CREATE TABLE IF NOT EXISTS pos_school_registers (class_id TEXT NOT NULL, day TEXT NOT NULL, business_id TEXT NOT NULL,"
    " marked_at TEXT NOT NULL, by_user TEXT NOT NULL, PRIMARY KEY (class_id, day))",
    "CREATE TABLE IF NOT EXISTS pos_school_absences (student_id TEXT NOT NULL, day TEXT NOT NULL, business_id TEXT NOT NULL,"
    " class_id TEXT NOT NULL, PRIMARY KEY (student_id, day))",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_absences_biz ON pos_school_absences(business_id, day)",
    "CREATE TABLE IF NOT EXISTS pos_school_gate (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, student_id TEXT NOT NULL,"
    " day TEXT NOT NULL, kind TEXT NOT NULL, who_name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '',"
    " listed INTEGER NOT NULL, reason TEXT NOT NULL DEFAULT '', at TEXT NOT NULL, by_user TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_gate_biz ON pos_school_gate(business_id, day)",
    "CREATE TABLE IF NOT EXISTS pos_school_health (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, student_id TEXT NOT NULL,"
    " day TEXT NOT NULL, complaint TEXT NOT NULL, action TEXT NOT NULL DEFAULT '', outcome TEXT NOT NULL DEFAULT 'room',"
    " follow_up TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'open', at TEXT NOT NULL, by_user TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_school_health_biz ON pos_school_health(business_id, status, follow_up)",
]

STREAK_DAYS = 3  # absent this many marked days in a row = a problem
STREAK_LOOKBACK = 21  # calendar days looked at when counting a streak
GATE_KINDS = ("early", "pickup", "visitor")
OUTCOMES = ("room", "home", "hospital")
HEALTH_STATUSES = ("open", "recovered")
MAX_PICKUPS = 8
LIST_LIMIT = 300
MAX_PROBLEM_ITEMS = 20
# The order is the priority: a child with someone unlisted first, then a sick child, then absence, then paperwork.
PROBLEM_ORDER = ("unlisted_pickup", "health_follow_up", "absent_streak", "unmarked", "absent_today")


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:20]}"


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _phone(value: Any) -> str:
    digits = re.sub(r"\D", "", str(value or ""))[-10:]
    return digits if len(digits) == 10 else ""


def _wa(phone: str, text: str) -> str:
    return f"https://wa.me/91{phone}?text={urllib.parse.quote(text)}" if phone else ""


def _same_name(a: str, b: str) -> bool:
    """Two names are the same person when their words match, whatever the case or order ("Ravi Kumar" / "kumar ravi")."""
    words = lambda text: sorted(w for w in re.split(r"[\s.,]+", text.lower()) if w)  # noqa: E731
    return bool(words(a)) and words(a) == words(b)


def _day(value: Any, today: date) -> date:
    if not value:
        return today
    try:
        day = date.fromisoformat(str(value)[:10])
    except ValueError:
        raise PosError(400, "day", "The day must be a date (YYYY-MM-DD).")
    if abs((day - today).days) > 31:
        raise PosError(400, "day", "The day must be within a month of today.")
    return day


class PosSchool:
    def __init__(self, store: Any, *, clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _now(self) -> str:
        return self.clock().isoformat()

    def _today(self) -> date:
        return self.clock().astimezone(IST).date()

    def _class(self, conn: sqlite3.Connection, business_id: str, class_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_school_classes WHERE id = ? AND business_id = ?", (class_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "class", "Class not found.")
        return row

    def _student(self, conn: sqlite3.Connection, business_id: str, student_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_school_students WHERE id = ? AND business_id = ?", (student_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "student", "Student not found.")
        return row

    # ------------------------------------------------------------------ classes + students
    def add_class(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 40)
        if not name:
            raise PosError(400, "name", "Give the class a name (for example 5-A).")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            if conn.execute("SELECT 1 FROM pos_school_classes WHERE business_id = ? AND lower(name) = ? AND status = 'active'",
                            (business_id, name.lower())).fetchone():
                raise PosError(409, "duplicate", "This class is already here.")
            class_id = _id("scl")
            conn.execute("INSERT INTO pos_school_classes (id, business_id, name, teacher, created_at) VALUES (?, ?, ?, ?, ?)",
                         (class_id, business_id, name, _clean(data.get("teacher"), 60), self._now()))
        return {"id": class_id, "name": name, "teacher": _clean(data.get("teacher"), 60), "students": 0}

    def add_student(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 60)
        if not name:
            raise PosError(400, "name", "Give the student's name.")
        phone = _phone(data.get("parent_phone"))
        pickups = [(_clean(p.get("name"), 60), _clean(p.get("relation"), 30)) for p in (data.get("pickups") or [])
                   if isinstance(p, dict) and _clean(p.get("name"), 60)][:MAX_PICKUPS]
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            self._class(conn, business_id, str(data.get("class_id") or ""))
            student_id = _id("stu")
            conn.execute("INSERT INTO pos_school_students (id, business_id, class_id, name, parent_name, parent_phone, hostel,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (student_id, business_id, str(data["class_id"]), name, _clean(data.get("parent_name"), 60), phone,
                          1 if data.get("hostel") else 0, self._now()))
            for pick_name, relation in pickups:
                conn.execute("INSERT INTO pos_school_pickups (id, student_id, business_id, name, relation) VALUES (?, ?, ?, ?, ?)",
                             (_id("spk"), student_id, business_id, pick_name, relation))
        return {"id": student_id, "name": name, "class_id": data["class_id"], "pickups": len(pickups)}

    def set_pickups(self, business_id: str, user: str, student_id: str, pickups: List[Dict[str, Any]]) -> Dict[str, Any]:
        """The people the parent allows to take the child (replaces the list)."""
        rows = [(_clean(p.get("name"), 60), _clean(p.get("relation"), 30)) for p in pickups
                if isinstance(p, dict) and _clean(p.get("name"), 60)][:MAX_PICKUPS]
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            self._student(conn, business_id, student_id)
            conn.execute("DELETE FROM pos_school_pickups WHERE student_id = ?", (student_id,))
            for pick_name, relation in rows:
                conn.execute("INSERT INTO pos_school_pickups (id, student_id, business_id, name, relation) VALUES (?, ?, ?, ?, ?)",
                             (_id("spk"), student_id, business_id, pick_name, relation))
        return {"ok": True, "pickups": len(rows)}

    def classes(self, business_id: str, user: str) -> Dict[str, Any]:
        """Every class with its students (name, parent, hostel, who may pick the child up)."""
        today = self._today().isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            classes = conn.execute("SELECT * FROM pos_school_classes WHERE business_id = ? AND status = 'active' ORDER BY name",
                                   (business_id,)).fetchall()
            students = conn.execute("SELECT * FROM pos_school_students WHERE business_id = ? AND status = 'active' ORDER BY name"
                                    " LIMIT ?", (business_id, LIST_LIMIT * 10)).fetchall()
            pickups: Dict[str, List[Dict[str, str]]] = {}
            for row in conn.execute("SELECT student_id, name, relation FROM pos_school_pickups WHERE business_id = ?", (business_id,)):
                pickups.setdefault(row["student_id"], []).append({"name": row["name"], "relation": row["relation"]})
            marked = {r["class_id"] for r in conn.execute("SELECT class_id FROM pos_school_registers WHERE business_id = ? AND day = ?",
                                                          (business_id, today))}
        by_class: Dict[str, List[Dict[str, Any]]] = {}
        for s in students:
            by_class.setdefault(s["class_id"], []).append(
                {"id": s["id"], "name": s["name"], "parent_name": s["parent_name"], "parent_phone": s["parent_phone"],
                 "hostel": bool(s["hostel"]), "pickups": pickups.get(s["id"], [])})
        return {"today": today, "classes": [{"id": c["id"], "name": c["name"], "teacher": c["teacher"],
                                             "marked_today": c["id"] in marked, "students": by_class.get(c["id"], [])[:LIST_LIMIT]}
                                            for c in classes]}

    # ------------------------------------------------------------------ the day's register
    def register(self, business_id: str, user: str, class_id: str, absent: List[str], day: Any = None) -> Dict[str, Any]:
        """Save the class's day: ``absent`` = the students who did not come, every other student is present. Saving
        again replaces the day (a wrong tap is fixed by saving again)."""
        today = self._today()
        the_day = _day(day, today)
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            row = self._class(conn, business_id, class_id)
            ids = {r["id"] for r in conn.execute("SELECT id FROM pos_school_students WHERE business_id = ? AND class_id = ? AND"
                                                 " status = 'active'", (business_id, class_id))}
            wrong = [a for a in absent if a not in ids]
            if wrong:
                raise PosError(400, "absent", "A name in the absent list is not in this class.")
            day_text = the_day.isoformat()
            conn.execute("DELETE FROM pos_school_absences WHERE class_id = ? AND day = ?", (class_id, day_text))
            for student_id in dict.fromkeys(absent):
                conn.execute("INSERT INTO pos_school_absences (student_id, day, business_id, class_id) VALUES (?, ?, ?, ?)",
                             (student_id, day_text, business_id, class_id))
            conn.execute("INSERT OR REPLACE INTO pos_school_registers (class_id, day, business_id, marked_at, by_user)"
                         " VALUES (?, ?, ?, ?, ?)", (class_id, day_text, business_id, self._now(), user))
            shop = self.store._business_row(conn, business_id)["name"]
            drafts = self._absent_drafts(conn, business_id, class_id, day_text, shop)
        return {"ok": True, "class": row["name"], "day": day_text, "present": len(ids) - len(set(absent)),
                "absent": len(set(absent)), "drafts": drafts, "draft_only": True}

    def _absent_drafts(self, conn: sqlite3.Connection, business_id: str, class_id: str, day: str, shop: str) -> List[Dict[str, Any]]:
        rows = conn.execute("SELECT s.id, s.name, s.parent_name, s.parent_phone FROM pos_school_absences a JOIN pos_school_students s"
                            " ON s.id = a.student_id WHERE a.class_id = ? AND a.day = ? ORDER BY s.name", (class_id, day)).fetchall()
        out = []
        for r in rows:
            text = (f"నమస్తే {r['parent_name'] or ''}".strip() + f", {shop} నుండి: {r['name']} ఈ రోజు ({day}) రాలేదు. అంతా బాగుందా? "
                    f"From {shop}: {r['name']} was not in school today ({day}). Is everything fine?")
            out.append({"student_id": r["id"], "name": r["name"], "phone": r["parent_phone"], "message": text,
                        "whatsapp_url": _wa(r["parent_phone"], text)})
        return out

    def _streak(self, conn: sqlite3.Connection, business_id: str, student_id: str, class_id: str, today: date) -> int:
        """Marked days in a row (newest first, Sundays skipped) on which this student was absent."""
        lo = (today - timedelta(days=STREAK_LOOKBACK)).isoformat()
        marked = [r["day"] for r in conn.execute("SELECT day FROM pos_school_registers WHERE class_id = ? AND day >= ? AND day <= ?"
                                                 " ORDER BY day DESC", (class_id, lo, today.isoformat()))]
        gone = {r["day"] for r in conn.execute("SELECT day FROM pos_school_absences WHERE student_id = ? AND day >= ?", (student_id, lo))}
        count = 0
        for day in marked:
            if date.fromisoformat(day).weekday() == 6:
                continue
            if day in gone:
                count += 1
            else:
                break
        return count

    # ------------------------------------------------------------------ gate
    def gate(self, business_id: str, user: str, student_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A child goes out early, is picked up, or a visitor comes for the child. ``listed`` says whether the person
        is on the parent's list; an unlisted person is raised in ``today`` and the answer says so at once."""
        kind = str(data.get("kind") or "pickup")
        if kind not in GATE_KINDS:
            raise PosError(400, "kind", "kind must be early, pickup or visitor.")
        who = _clean(data.get("who_name"), 60)
        if not who:
            raise PosError(400, "who_name", "Who is taking the child? Give the name.")
        today = self._today().isoformat()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            student = self._student(conn, business_id, student_id)
            allowed = [r["name"] for r in conn.execute("SELECT name FROM pos_school_pickups WHERE student_id = ?", (student_id,))]
            listed = any(_same_name(who, name) for name in allowed) or (bool(student["parent_name"]) and _same_name(who, student["parent_name"]))
            gate_id = _id("sgt")
            conn.execute("INSERT INTO pos_school_gate (id, business_id, student_id, day, kind, who_name, relation, listed, reason,"
                         " at, by_user) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (gate_id, business_id, student_id, today, kind, who, _clean(data.get("relation"), 30), 1 if listed else 0,
                          _clean(data.get("reason"), 120), self._now(), user))
        out: Dict[str, Any] = {"id": gate_id, "student": student["name"], "listed": listed, "kind": kind}
        if not listed:
            out["warning"] = ("ఈ పేరు తల్లిదండ్రులు ఇచ్చిన జాబితాలో లేదు. తల్లిదండ్రులకు ఫోన్ చేసి అడగండి. "
                              "This name is not on the parent's list. Call the parent before the child leaves.")
            if student["parent_phone"]:
                out["call_parent"] = f"tel:{student['parent_phone']}"
        return out

    # ------------------------------------------------------------------ health room
    def sick(self, business_id: str, user: str, student_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A child in the health room: what happened, what was done, where the child went, and when to ask again."""
        complaint = _clean(data.get("complaint"), 160)
        if not complaint:
            raise PosError(400, "complaint", "Say what is wrong (for example fever, stomach pain).")
        outcome = str(data.get("outcome") or "room")
        if outcome not in OUTCOMES:
            raise PosError(400, "outcome", "outcome must be room, home or hospital.")
        today = self._today()
        follow = ""
        if data.get("follow_up"):
            follow = _day(data["follow_up"], today).isoformat()
        elif outcome != "room":
            follow = (today + timedelta(days=1)).isoformat()  # a child sent home / to hospital is asked after tomorrow
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            self._student(conn, business_id, student_id)
            health_id = _id("shl")
            conn.execute("INSERT INTO pos_school_health (id, business_id, student_id, day, complaint, action, outcome, follow_up,"
                         " at, by_user) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (health_id, business_id, student_id, today.isoformat(), complaint, _clean(data.get("action"), 160), outcome,
                          follow, self._now(), user))
        return {"id": health_id, "outcome": outcome, "follow_up": follow}

    def recovered(self, business_id: str, user: str, health_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            cursor = conn.execute("UPDATE pos_school_health SET status = 'recovered' WHERE id = ? AND business_id = ?",
                                  (health_id, business_id))
            if cursor.rowcount == 0:
                raise PosError(404, "health", "Record not found.")
        return {"ok": True, "status": "recovered"}

    # ------------------------------------------------------------------ today: only what needs a person
    def today(self, business_id: str, user: str) -> Dict[str, Any]:
        """The owner's list: at most the problems below, each with its people and a draft. Nothing that is fine is shown."""
        today = self._today()
        day = today.isoformat()
        found: Dict[str, Dict[str, Any]] = {}
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            shop = self.store._business_row(conn, business_id)["name"]
            classes = conn.execute("SELECT * FROM pos_school_classes WHERE business_id = ? AND status = 'active' ORDER BY name",
                                   (business_id,)).fetchall()
            students = conn.execute("SELECT * FROM pos_school_students WHERE business_id = ? AND status = 'active'",
                                    (business_id,)).fetchall()
            names = {s["id"]: s for s in students}
            marked = {r["class_id"] for r in conn.execute("SELECT class_id FROM pos_school_registers WHERE business_id = ? AND day = ?",
                                                          (business_id, day))}
            sunday = today.weekday() == 6
            unmarked = [] if sunday else [{"class_id": c["id"], "name": c["name"], "teacher": c["teacher"]}
                                          for c in classes if c["id"] not in marked and any(s["class_id"] == c["id"] for s in students)]
            if unmarked:
                found["unmarked"] = {"count": len(unmarked), "items": unmarked[:MAX_PROBLEM_ITEMS], "route": f"/biz/{business_id}/school"}
            # absent today (class marked) -- parents to ask
            absent_today: List[Dict[str, Any]] = []
            for c in classes:
                if c["id"] in marked:
                    absent_today.extend(self._absent_drafts(conn, business_id, c["id"], day, shop))
            if absent_today:
                found["absent_today"] = {"count": len(absent_today), "items": absent_today[:MAX_PROBLEM_ITEMS],
                                         "route": f"/biz/{business_id}/school"}
            # absent several days in a row
            streaks = []
            for s in students:
                days = self._streak(conn, business_id, s["id"], s["class_id"], today)
                if days >= STREAK_DAYS:
                    text = (f"నమస్తే {s['parent_name'] or ''}".strip() + f", {shop} నుండి: {s['name']} {days} రోజులుగా రావడం లేదు. "
                            f"ఏదైనా సహాయం కావాలా? From {shop}: {s['name']} has not come for {days} days. Can we help?")
                    streaks.append({"student_id": s["id"], "name": s["name"], "days": days, "phone": s["parent_phone"],
                                    "message": text, "whatsapp_url": _wa(s["parent_phone"], text)})
            if streaks:
                streaks.sort(key=lambda x: -x["days"])
                found["absent_streak"] = {"count": len(streaks), "items": streaks[:MAX_PROBLEM_ITEMS], "route": f"/biz/{business_id}/school"}
            # someone not on the parent's list took a child today
            unlisted = [{"gate_id": r["id"], "student": names[r["student_id"]]["name"] if r["student_id"] in names else "",
                         "who": r["who_name"], "kind": r["kind"], "at": r["at"],
                         "call_parent": f"tel:{names[r['student_id']]['parent_phone']}"
                         if r["student_id"] in names and names[r["student_id"]]["parent_phone"] else ""}
                        for r in conn.execute("SELECT * FROM pos_school_gate WHERE business_id = ? AND day = ? AND listed = 0 ORDER BY at DESC",
                                              (business_id, day))]
            if unlisted:
                found["unlisted_pickup"] = {"count": len(unlisted), "items": unlisted[:MAX_PROBLEM_ITEMS], "route": f"/biz/{business_id}/school"}
            # sick children whose follow-up day has come
            follow = []
            for r in conn.execute("SELECT * FROM pos_school_health WHERE business_id = ? AND status = 'open' AND follow_up != '' AND"
                                  " follow_up <= ? ORDER BY follow_up", (business_id, day)):
                s = names.get(r["student_id"])
                if s is None:
                    continue
                text = (f"నమస్తే {s['parent_name'] or ''}".strip() + f", {shop} నుండి: {s['name']} ఇప్పుడు ఎలా ఉన్నాడు/ఉంది? "
                        f"From {shop}: how is {s['name']} now? We would like to check on the child.")
                follow.append({"health_id": r["id"], "student": s["name"], "outcome": r["outcome"], "since": r["day"],
                               "phone": s["parent_phone"], "message": text, "whatsapp_url": _wa(s["parent_phone"], text)})
            if follow:
                found["health_follow_up"] = {"count": len(follow), "items": follow[:MAX_PROBLEM_ITEMS], "route": f"/biz/{business_id}/school"}
            gone_early = int(conn.execute("SELECT COUNT(*) FROM pos_school_gate WHERE business_id = ? AND day = ? AND kind = 'early'",
                                          (business_id, day)).fetchone()[0])
            sick_now = int(conn.execute("SELECT COUNT(*) FROM pos_school_health WHERE business_id = ? AND day = ?",
                                        (business_id, day)).fetchone()[0])
        problems = [{"key": key, **found[key]} for key in PROBLEM_ORDER if key in found]
        return {"day": day, "problems": problems, "all_clear": not problems,
                "counts": {"classes": len(classes), "students": len(students), "marked": len(marked), "left_early": gone_early,
                           "health_room": sick_now},
                "draft_only": True}

    # ------------------------------------------------------------------ the month (reports permission)
    def report(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        """Attendance per class for a month from the saved registers only (no health detail, no names of the sick)."""
        today = self._today()
        month = month[:7] if re.fullmatch(r"\d{4}-\d{2}", month[:7] or "") else today.strftime("%Y-%m")
        lo, hi = month + "-01", month + "-31"
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            out = []
            for c in conn.execute("SELECT * FROM pos_school_classes WHERE business_id = ? AND status = 'active' ORDER BY name",
                                  (business_id,)):
                days = int(conn.execute("SELECT COUNT(*) FROM pos_school_registers WHERE class_id = ? AND day BETWEEN ? AND ?",
                                        (c["id"], lo, hi)).fetchone()[0])
                kids = int(conn.execute("SELECT COUNT(*) FROM pos_school_students WHERE class_id = ? AND status = 'active'",
                                        (c["id"],)).fetchone()[0])
                gone = int(conn.execute("SELECT COUNT(*) FROM pos_school_absences WHERE class_id = ? AND day BETWEEN ? AND ?",
                                        (c["id"], lo, hi)).fetchone()[0])
                possible = days * kids
                out.append({"class_id": c["id"], "name": c["name"], "days_marked": days, "students": kids, "absences": gone,
                            "attendance_percent": round(100 * (possible - gone) / possible) if possible else None})
            early = int(conn.execute("SELECT COUNT(*) FROM pos_school_gate WHERE business_id = ? AND kind = 'early' AND day BETWEEN ? AND ?",
                                     (business_id, lo, hi)).fetchone()[0])
            unlisted = int(conn.execute("SELECT COUNT(*) FROM pos_school_gate WHERE business_id = ? AND listed = 0 AND day BETWEEN ? AND ?",
                                        (business_id, lo, hi)).fetchone()[0])
        return {"month": month, "classes": out, "left_early": early, "unlisted_pickups": unlisted}

    def problem_count(self, business_id: str, user: str) -> int:
        """How many problem groups are open now (the morning brief; read only)."""
        return len(self.today(business_id, user)["problems"])
