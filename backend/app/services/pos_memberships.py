"""Term memberships + attendance (owner 2026-11-27, design canvas "కొత్త లుక్" gym screens; phase 3 of the plan).

For EVERY business that sells time by the term and wants to know who came: a gym, yoga / dance / music class,
swimming pool, library, coaching centre, sports club, hostel mess ... (no per-category code; the Business Kit way of
working 5 decides which shop sees the page). ``PosMonthly`` stays the calendar-month due book (milk, tuition).

* a member = name, phone, a term in months, the fee, the day it started and the day it ENDS (worked out, never typed);
* a fee received = a RECORD of what the shop got; it moves the end day on by that many months (from the old end day
  when it has not passed, else from today). ASKODOX never holds the money;
* who is ending soon / has ended, with a reminder DRAFT the owner sends himself from his own WhatsApp;
* attendance once a day per member: the staff taps, or the member types today's 4-digit code shown at the counter
  (being at the counter is the proof; the code changes every India day);
* who has not come for a week, with a message DRAFT; the month's report (new, renewed, ended, collected by week).

Nothing here sends a message, charges or pays: every draft waits for the owner's own tap.
"""
from __future__ import annotations

import calendar
import hashlib
import re
import sqlite3
import urllib.parse
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.account_identity import phone_key
from app.services.pos_store import IST, PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_term_members (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " phone TEXT NOT NULL DEFAULT '', customer_user TEXT NOT NULL DEFAULT '', months INTEGER NOT NULL,"
    " fee_paise INTEGER NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active',"
    " note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_term_members_biz ON pos_term_members(business_id, status, end_date)",
    "CREATE TABLE IF NOT EXISTS pos_term_payments (id TEXT PRIMARY KEY, member_id TEXT NOT NULL, business_id TEXT NOT NULL,"
    " kind TEXT NOT NULL, amount_paise INTEGER NOT NULL, months INTEGER NOT NULL, from_date TEXT NOT NULL,"
    " to_date TEXT NOT NULL, method TEXT NOT NULL DEFAULT '', local_date TEXT NOT NULL, at TEXT NOT NULL, by_user TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_term_payments_biz ON pos_term_payments(business_id, local_date)",
    "CREATE TABLE IF NOT EXISTS pos_term_visits (member_id TEXT NOT NULL, business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " at TEXT NOT NULL, method TEXT NOT NULL, by_user TEXT NOT NULL, PRIMARY KEY (member_id, day))",
    "CREATE INDEX IF NOT EXISTS idx_pos_term_visits_biz ON pos_term_visits(business_id, day)",
]

TERMS = (1, 3, 6, 12)  # the quick choices; any 1..36 is accepted
MAX_MONTHS = 36
MAX_PAISE = 10_00_00_000_00
ENDING_DAYS = 5  # "ending soon" = the end day is within these days (the owner's design: a reminder 5 days before)
ABSENT_DAYS = 7
LEFT_AFTER_DAYS = 30  # ended this long ago and not renewed = left (no more reminders, still in the report)
PAY_METHODS = ("cash", "upi", "card", "bank_transfer", "other")
STATUSES = ("active", "stopped")
LIST_LIMIT = 200


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:20]}"


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _phone(value: Any) -> str:
    digits = re.sub(r"\D", "", str(value or ""))[-10:]
    return digits if len(digits) == 10 else ""


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


def _wa(phone: str, text: str) -> str:
    return f"https://wa.me/91{phone}?text={urllib.parse.quote(text)}" if phone else ""


def add_months(day: date, months: int) -> date:
    """The same day of the month ``months`` later; a day that month does not have becomes its last day
    (31 Jan + 1 month = 28 / 29 Feb)."""
    index = day.month - 1 + months
    year, month = day.year + index // 12, index % 12 + 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def visit_code(business_id: str, salt: str, day: str) -> str:
    """Today's 4-digit counter code of one shop (changes every India day; not a secret worth more than a visit)."""
    return f"{int(hashlib.sha256(f'{business_id}|{salt}|{day}'.encode()).hexdigest(), 16) % 10000:04d}"


class PosMemberships:
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

    def _months(self, value: Any) -> int:
        try:
            months = int(value or 0)
        except (TypeError, ValueError):
            months = 0
        if not 1 <= months <= MAX_MONTHS:
            raise PosError(400, "months", f"The term must be 1 to {MAX_MONTHS} months.")
        return months

    @staticmethod
    def _amount(value: Any, *, allow_zero: bool = False) -> int:
        try:
            amount = int(value or 0)
        except (TypeError, ValueError):
            raise PosError(400, "fee_paise", "The fee must be a whole number of paise.")
        if amount < (0 if allow_zero else 1) or amount > MAX_PAISE:
            raise PosError(400, "fee_paise", "Give the fee.")
        return amount

    def _member(self, conn: sqlite3.Connection, business_id: str, member_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_term_members WHERE id = ? AND business_id = ?", (member_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "member", "Member not found.")
        return row

    def _view(self, row: sqlite3.Row, shop: str, today: date, last_visit: str = "") -> Dict[str, Any]:
        end = date.fromisoformat(row["end_date"])
        left = (end - today).days
        state = ("stopped" if row["status"] != "active" else "left" if left < -LEFT_AFTER_DAYS else "ended" if left < 0
                 else "ending" if left <= ENDING_DAYS else "ok")
        out: Dict[str, Any] = {"id": row["id"], "name": row["name"], "phone": row["phone"], "months": row["months"],
                               "fee_paise": row["fee_paise"], "start_date": row["start_date"], "end_date": row["end_date"],
                               "days_left": left, "state": state, "status": row["status"], "last_visit": last_visit}
        if state in ("ending", "ended") and row["phone"]:
            fee = _rupees(row["fee_paise"])
            when = ("ఈ రోజు ముగుస్తుంది" if left == 0 else f"{left} రోజుల్లో ముగుస్తుంది" if left > 0
                    else f"{row['end_date']} తో ముగిసింది")
            out["reminder"] = (f"నమస్తే {row['name']}, {shop} లో మీ సభ్యత్వం {when} ({row['end_date']}). "
                               f"కొనసాగించడానికి {row['months']} నెలలకు {fee}. "
                               f"Reminder from {shop}: your membership ends on {row['end_date']}; renewal {fee}.")
            out["whatsapp_url"] = _wa(row["phone"], out["reminder"])
        return out

    def _last_visits(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, str]:
        return {r["member_id"]: r["day"] for r in conn.execute(
            "SELECT member_id, MAX(day) AS day FROM pos_term_visits WHERE business_id = ? GROUP BY member_id", (business_id,))}

    # ------------------------------------------------------------------ the shop's page
    def overview(self, business_id: str, user: str) -> Dict[str, Any]:
        """The numbers on top (members, ending this month, fee to come), who is ending / has ended, and everyone."""
        today = self._today()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            shop = self.store._business_row(conn, business_id)["name"]
            rows = conn.execute("SELECT * FROM pos_term_members WHERE business_id = ? ORDER BY end_date, name LIMIT ?",
                                (business_id, LIST_LIMIT * 5)).fetchall()
            visits = self._last_visits(conn, business_id)
            came = int(conn.execute("SELECT COUNT(*) FROM pos_term_visits WHERE business_id = ? AND day = ?",
                                    (business_id, today.isoformat())).fetchone()[0])
        members = [self._view(r, shop, today, visits.get(r["id"], "")) for r in rows]
        live = [m for m in members if m["state"] in ("ok", "ending", "ended")]
        month_end = add_months(today.replace(day=1), 1) - timedelta(days=1)
        return {"today": today.isoformat(), "terms": list(TERMS), "ending_days": ENDING_DAYS,
                "counts": {"members": sum(1 for m in live if m["state"] != "ended"),
                           "ending_this_month": sum(1 for m in live if today.isoformat() <= m["end_date"] <= month_end.isoformat()),
                           "fee_due": sum(1 for m in live if m["state"] == "ended"), "came_today": came},
                "ending": [m for m in live if m["state"] in ("ending", "ended")][:LIST_LIMIT],
                "members": members[:LIST_LIMIT], "draft_only": True}

    def add(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A new member. The end day is worked out from the start day and the term; ``paid`` records the first fee."""
        name = _clean(data.get("name"), 60)
        if not name:
            raise PosError(400, "name", "Give the member's name.")
        months = self._months(data.get("months"))
        fee = self._amount(data.get("fee_paise"))
        today = self._today()
        try:
            start = date.fromisoformat(str(data.get("start_date") or today.isoformat())[:10])
        except ValueError:
            raise PosError(400, "start_date", "The start day must be a date (YYYY-MM-DD).")
        if abs((start - today).days) > 366:
            raise PosError(400, "start_date", "The start day must be within a year of today.")
        phone = _phone(data.get("phone"))
        end = add_months(start, months)
        now = self._now()
        paid = bool(data.get("paid"))
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "collect" if paid else "customers")
            if phone and conn.execute("SELECT 1 FROM pos_term_members WHERE business_id = ? AND phone = ? AND status = 'active'",
                                      (business_id, phone)).fetchone():
                raise PosError(409, "duplicate", "A member with this phone number is already here.")
            member_id = _id("tmb")
            conn.execute("INSERT INTO pos_term_members (id, business_id, name, phone, customer_user, months, fee_paise,"
                         " start_date, end_date, status, note, created_by, created_at, updated_at) VALUES"
                         " (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)",
                         (member_id, business_id, name, phone, f"app-phone-{phone}" if phone else "", months, fee,
                          start.isoformat(), end.isoformat(), _clean(data.get("note"), 200), user, now, now))
            if paid:
                self._record(conn, business_id, member_id, user, "join", fee, months, start, end,
                             str(data.get("method") or "cash"), today, now)
            shop = self.store._business_row(conn, business_id)["name"]
            row = self._member(conn, business_id, member_id)
        return self._view(row, shop, today)

    @staticmethod
    def _record(conn: sqlite3.Connection, business_id: str, member_id: str, user: str, kind: str, amount: int,
                months: int, start: date, end: date, method: str, today: date, now: str) -> None:
        conn.execute("INSERT INTO pos_term_payments (id, member_id, business_id, kind, amount_paise, months, from_date,"
                     " to_date, method, local_date, at, by_user) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     (_id("tpy"), member_id, business_id, kind, amount, months, start.isoformat(), end.isoformat(),
                      method if method in PAY_METHODS else "other", today.isoformat(), now, user))

    def renew(self, business_id: str, user: str, member_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """The fee came: record it and move the end day on -- from the old end day when it has not passed, else from
        today (a person who comes back after a gap does not pay for the days away)."""
        today = self._today()
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "collect")
            row = self._member(conn, business_id, member_id)
            months = self._months(data.get("months") or row["months"])
            amount = self._amount(data.get("amount_paise") or row["fee_paise"])
            old_end = date.fromisoformat(row["end_date"])
            start = old_end if old_end >= today else today
            end = add_months(start, months)
            conn.execute("UPDATE pos_term_members SET end_date = ?, months = ?, fee_paise = ?, status = 'active',"
                         " updated_at = ? WHERE id = ?", (end.isoformat(), months, amount, now, member_id))
            self._record(conn, business_id, member_id, user, "renew", amount, months, start, end,
                         str(data.get("method") or "cash"), today, now)
            shop = self.store._business_row(conn, business_id)["name"]
            out = self._view(self._member(conn, business_id, member_id), shop, today)
        out["renewed"] = {"from": row["end_date"], "to": end.isoformat(), "amount_paise": amount, "months": months}
        return out

    def set_status(self, business_id: str, user: str, member_id: str, status: str) -> Dict[str, Any]:
        if status not in STATUSES:
            raise PosError(400, "status", "status must be active or stopped.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            self._member(conn, business_id, member_id)
            conn.execute("UPDATE pos_term_members SET status = ?, updated_at = ? WHERE id = ?", (status, self._now(), member_id))
        return {"ok": True, "status": status}

    # ------------------------------------------------------------------ attendance
    def _code(self, conn: sqlite3.Connection, business_id: str, day: str) -> str:
        return visit_code(business_id, str(self.store._business_row(conn, business_id)["created_at"]), day)

    def attendance(self, business_id: str, user: str) -> Dict[str, Any]:
        """Today: who came, today's counter code, and the active members who have not come for a week."""
        today = self._today()
        day = today.isoformat()
        week_ago = (today - timedelta(days=ABSENT_DAYS)).isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            shop = self.store._business_row(conn, business_id)["name"]
            code = self._code(conn, business_id, day)
            came = [{"member_id": r["member_id"], "name": r["name"], "at": r["at"], "method": r["method"]}
                    for r in conn.execute("SELECT v.member_id, v.at, v.method, m.name FROM pos_term_visits v JOIN"
                                          " pos_term_members m ON m.id = v.member_id WHERE v.business_id = ? AND v.day = ?"
                                          " ORDER BY v.at DESC", (business_id, day))]
            visits = self._last_visits(conn, business_id)
            rows = conn.execute("SELECT * FROM pos_term_members WHERE business_id = ? AND status = 'active' AND"
                                " end_date >= ? ORDER BY name LIMIT ?", (business_id, day, LIST_LIMIT * 5)).fetchall()
        here = {c["member_id"] for c in came}
        absent, waiting = [], []
        for row in rows:
            last = visits.get(row["id"], "")
            since = last or row["start_date"]
            if row["id"] not in here:
                waiting.append({"id": row["id"], "name": row["name"], "last_visit": last})
            if since <= week_ago:
                days = (today - date.fromisoformat(since)).days
                text = (f"నమస్తే {row['name']}, {shop} కి మీరు వచ్చి {days} రోజులైంది. మీ కోసం ఎదురుచూస్తున్నాం, రేపు రండి! "
                        f"From {shop}: we have missed you for {days} days. See you tomorrow!")
                absent.append({"id": row["id"], "name": row["name"], "phone": row["phone"], "days": days,
                               "last_visit": last, "message": text, "whatsapp_url": _wa(row["phone"], text)})
        return {"day": day, "code": code, "qr": f"ASKODOX-VISIT:{business_id}:{code}", "came": came,
                "came_count": len(came), "waiting": waiting[:LIST_LIMIT], "absent": absent[:LIST_LIMIT],
                "absent_days": ABSENT_DAYS, "draft_only": True}

    def _visit(self, conn: sqlite3.Connection, business_id: str, member_id: str, user: str, method: str) -> bool:
        cursor = conn.execute("INSERT OR IGNORE INTO pos_term_visits (member_id, business_id, day, at, method, by_user)"
                              " VALUES (?, ?, ?, ?, ?, ?)", (member_id, business_id, self._today().isoformat(), self._now(),
                                                             method, user))
        return cursor.rowcount > 0

    def mark(self, business_id: str, user: str, member_id: str, came: bool = True) -> Dict[str, Any]:
        """The staff taps a member who came today (once a day); ``came`` False takes a wrong tap back."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            self._member(conn, business_id, member_id)
            if came:
                new = self._visit(conn, business_id, member_id, user, "tap")
            else:
                new = conn.execute("DELETE FROM pos_term_visits WHERE member_id = ? AND day = ?",
                                   (member_id, self._today().isoformat())).rowcount > 0
        return {"ok": True, "came": came, "changed": new}

    # ------------------------------------------------------------------ the month
    def report(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        today = self._today()
        month = month[:7] if re.fullmatch(r"\d{4}-\d{2}", month[:7] or "") else today.strftime("%Y-%m")
        first = date.fromisoformat(month + "-01")
        last = add_months(first, 1) - timedelta(days=1)
        lo, hi = first.isoformat(), last.isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            shop = self.store._business_row(conn, business_id)["name"]
            pays = conn.execute("SELECT kind, amount_paise, local_date FROM pos_term_payments WHERE business_id = ? AND"
                                " local_date BETWEEN ? AND ?", (business_id, lo, hi)).fetchall()
            joined = int(conn.execute("SELECT COUNT(*) FROM pos_term_members WHERE business_id = ? AND start_date BETWEEN"
                                      " ? AND ?", (business_id, lo, hi)).fetchone()[0])
            ended = conn.execute("SELECT * FROM pos_term_members WHERE business_id = ? AND end_date BETWEEN ? AND ? AND"
                                 " end_date < ? ORDER BY end_date DESC LIMIT ?",
                                 (business_id, lo, hi, today.isoformat(), LIST_LIMIT)).fetchall()
        weeks = [0, 0, 0, 0]
        for pay in pays:
            weeks[min(3, (int(pay["local_date"][8:10]) - 1) // 7)] += int(pay["amount_paise"])
        left = []
        for row in ended:
            text = (f"నమస్తే {row['name']}, {shop} లో మీ సభ్యత్వం {row['end_date']} తో ముగిసింది. తిరిగి రండి, "
                    f"మీ కోసం ఎదురుచూస్తున్నాం! From {shop}: your membership ended on {row['end_date']}. Come back!")
            left.append({"id": row["id"], "name": row["name"], "phone": row["phone"], "end_date": row["end_date"],
                         "message": text, "whatsapp_url": _wa(row["phone"], text)})
        return {"month": month, "new": joined, "renewed": sum(1 for p in pays if p["kind"] == "renew"),
                "left": len(left), "collected_paise": sum(weeks), "weeks_paise": weeks, "left_members": left,
                "draft_only": True}

    def ending_count(self, business_id: str, user: str) -> int:
        """Members whose term ends within ENDING_DAYS or has just ended (the morning brief; read only)."""
        today = self._today()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            return int(conn.execute(
                "SELECT COUNT(*) FROM pos_term_members WHERE business_id = ? AND status = 'active' AND end_date <= ? AND"
                " end_date >= ?", (business_id, (today + timedelta(days=ENDING_DAYS)).isoformat(),
                                   (today - timedelta(days=LEFT_AFTER_DAYS)).isoformat())).fetchone()[0])

    # ------------------------------------------------------------------ the member's own side
    def _mine_rows(self, conn: sqlite3.Connection, user: str) -> List[sqlite3.Row]:
        key = (phone_key(user) or "")[-10:]
        return conn.execute("SELECT m.*, b.name AS shop FROM pos_term_members m JOIN pos_businesses b ON b.id = m.business_id"
                            " WHERE m.status = 'active' AND (m.customer_user = ? OR (? != '' AND m.phone = ?))"
                            " ORDER BY m.end_date", (user, key, key)).fetchall()

    def mine(self, user: str) -> List[Dict[str, Any]]:
        today = self._today()
        with self.store._connect() as conn:
            rows = self._mine_rows(conn, user)
            out = []
            for row in rows:
                came = conn.execute("SELECT 1 FROM pos_term_visits WHERE member_id = ? AND day = ?",
                                    (row["id"], today.isoformat())).fetchone() is not None
                out.append({"business_id": row["business_id"], "shop": row["shop"], "months": row["months"],
                            "fee_paise": row["fee_paise"], "end_date": row["end_date"],
                            "days_left": (date.fromisoformat(row["end_date"]) - today).days, "came_today": came})
        return out

    def check_in(self, user: str, business_id: str, code: str) -> Dict[str, Any]:
        """The member's own "I came": today's counter code of that shop, typed or read from its QR."""
        today = self._today().isoformat()
        with self.store._tx() as conn:
            row = next((r for r in self._mine_rows(conn, user) if r["business_id"] == business_id), None)
            if row is None:
                raise PosError(404, "member", "You are not a member here.")
            if re.sub(r"\D", "", str(code or "")) != self._code(conn, business_id, today):
                raise PosError(400, "code", "That is not today's code. Ask at the counter.")
            new = self._visit(conn, business_id, row["id"], user, "code")
        return {"ok": True, "day": today, "already": not new, "shop": row["shop"]}
