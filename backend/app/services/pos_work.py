"""Business Kit ways of working 3, 4 and 5 (owner 2026-11-24, "do all of it") -- ONE module each way, for EVERY kind of
business that works that way (no per-category code; the kit decides which shop sees which page):

* ``PosBookings`` (way 3, booking / rental by date and time): the shop's bookable things (hotel rooms, salon chairs,
  a doctor's OP, a function hall, a tractor, a costume ...) -- each by TIME SLOT (minutes) or by DAY (check-in /
  check-out). Free ones for a time, a customer books from the app (signed in), the shop adds phone / walk-in bookings,
  no two bookings of one thing overlap, a booking moves booked -> arrived -> done (or cancelled / no_show).
* ``PosJobs`` (way 4, job card / order ahead): a phone to repair, a blouse to stitch, a cake to bake, a Mee Seva
  application ... -- token number, what and what for, estimate, advance (recorded), ready date; received -> working
  -> ready -> delivered (or cancelled). Ready -> the customer is told in the app, else the shop gets a WhatsApp text.
* ``PosMonthly`` (way 5, monthly): plans (milk 1 L a day, tuition, gym, PG room ...) and members; each month a due per
  active member (made when looked at, never by a timer), paid in full / part or waived; a WhatsApp reminder text.

ASKODOX never holds the money: advances and payments are RECORDS of what the shop received; customers pay the shop.
Way 6 (enquiry -> visit -> deal) is the Business CRM (``pos_crm.py``: enquiries, stages, visits, quotations).
"""
from __future__ import annotations

import json
import re
import sqlite3
import urllib.parse
import uuid
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.account_identity import phone_key
from app.services.pos_store import IST, PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_book_items (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " mode TEXT NOT NULL, slot_minutes INTEGER NOT NULL DEFAULT 30, capacity INTEGER NOT NULL DEFAULT 1,"
    " price_paise INTEGER NOT NULL DEFAULT 0, deposit_paise INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',"
    " active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_book_items_biz ON pos_book_items(business_id)",
    "CREATE TABLE IF NOT EXISTS pos_bookings (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, item_id TEXT NOT NULL,"
    " customer_user TEXT NOT NULL DEFAULT '', customer_name TEXT NOT NULL DEFAULT '', customer_phone TEXT NOT NULL"
    " DEFAULT '', start_utc TEXT NOT NULL, end_utc TEXT NOT NULL, people INTEGER NOT NULL DEFAULT 1, note TEXT NOT NULL"
    " DEFAULT '', status TEXT NOT NULL DEFAULT 'booked', created_by TEXT NOT NULL, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_bookings_biz ON pos_bookings(business_id, start_utc)",
    "CREATE INDEX IF NOT EXISTS idx_pos_bookings_user ON pos_bookings(customer_user, start_utc)",
    "CREATE TABLE IF NOT EXISTS pos_jobs (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, token INTEGER NOT NULL,"
    " customer_name TEXT NOT NULL DEFAULT '', customer_phone TEXT NOT NULL DEFAULT '', customer_user TEXT NOT NULL"
    " DEFAULT '', item TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', estimate_paise INTEGER NOT NULL DEFAULT 0,"
    " advance_paise INTEGER NOT NULL DEFAULT 0, ready_by TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT"
    " 'received', history TEXT NOT NULL DEFAULT '[]', created_by TEXT NOT NULL, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL, client_txn_id TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_pos_jobs_biz ON pos_jobs(business_id, status, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_pos_jobs_user ON pos_jobs(customer_user, created_at)",
    "CREATE TABLE IF NOT EXISTS pos_month_plans (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " amount_paise INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_month_members (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, plan_id TEXT NOT NULL,"
    " customer_name TEXT NOT NULL, customer_phone TEXT NOT NULL DEFAULT '', customer_user TEXT NOT NULL DEFAULT '',"
    " start_month TEXT NOT NULL, due_day INTEGER NOT NULL DEFAULT 5, status TEXT NOT NULL DEFAULT 'active',"
    " note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_month_members_biz ON pos_month_members(business_id, status)",
    "CREATE TABLE IF NOT EXISTS pos_month_dues (member_id TEXT NOT NULL, business_id TEXT NOT NULL, month TEXT NOT NULL,"
    " amount_paise INTEGER NOT NULL, paid_paise INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'due',"
    " paid_at TEXT, updated_at TEXT NOT NULL, PRIMARY KEY (member_id, month))",
]

BOOK_MODES = ("slot", "day")
BOOK_STATUSES = ("booked", "arrived", "done", "cancelled", "no_show")
BOOK_OPEN = ("booked", "arrived")
BOOK_NEXT = {"booked": ("arrived", "cancelled", "no_show", "done"), "arrived": ("done", "cancelled")}
MAX_BOOK_AHEAD_DAYS = 365
CHECK_IN, CHECK_OUT = time(12, 0), time(11, 0)  # day bookings: from noon to 11 AM on the leaving day
JOB_STATUSES = ("received", "working", "ready", "delivered", "cancelled")
JOB_NEXT = {"received": ("working", "ready", "cancelled"), "working": ("ready", "cancelled"),
            "ready": ("delivered", "working"), "delivered": (), "cancelled": ()}
MEMBER_STATUSES = ("active", "paused", "stopped")
MAX_PAISE = 10_00_00_000_00


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:20]}"


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _paise(value: Any, field: str) -> int:
    try:
        amount = int(value or 0)
    except (TypeError, ValueError):
        raise PosError(400, field, f"{field} must be a whole number of paise.")
    if amount < 0 or amount > MAX_PAISE:
        raise PosError(400, field, f"{field} is out of range.")
    return amount


def _phone(value: Any) -> str:
    digits = re.sub(r"\D", "", str(value or ""))[-10:]
    return digits if len(digits) == 10 else ""


def _app_user(phone: str) -> str:
    """The ASKODOX account of a 10-digit number (an account id is 'app-phone-<number>'); '' when there is no number."""
    return f"app-phone-{phone}" if phone else ""


def _wa(phone: str, text: str) -> str:
    return f"https://wa.me/91{phone}?text={urllib.parse.quote(text)}" if phone else ""


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


class _Base:
    def __init__(self, store: Any, *, notify: Optional[Callable[[str, str, str, str, str], Any]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _now(self) -> str:
        return self.clock().isoformat()

    def _shop(self, conn: sqlite3.Connection, business_id: str) -> sqlite3.Row:
        return self.store._business_row(conn, business_id)


# ================================================================== way 3: bookings
class PosBookings(_Base):
    def _span(self, item: sqlite3.Row, data: Dict[str, Any]) -> tuple:
        """(start, end) in UTC for one booking of [item]: slot = start + its minutes; day = check-in .. check-out."""
        now = self.clock()
        if item["mode"] == "day":
            try:
                first = date.fromisoformat(str(data.get("from_date") or "")[:10])
                last = date.fromisoformat(str(data.get("to_date") or "")[:10])
            except ValueError:
                raise PosError(400, "dates", "Choose the day you come and the day you leave.")
            if last <= first:
                raise PosError(400, "dates", "The leaving day must be after the coming day.")
            if (last - first).days > 60:
                raise PosError(400, "dates", "Book at most 60 days at a time.")
            start = datetime.combine(first, CHECK_IN, IST).astimezone(timezone.utc)
            end = datetime.combine(last, CHECK_OUT, IST).astimezone(timezone.utc)
            if first < now.astimezone(IST).date():
                raise PosError(400, "dates", "Choose today or a later day.")
        else:
            try:
                start = datetime.fromisoformat(str(data.get("at") or "").replace("Z", "+00:00"))
            except ValueError:
                raise PosError(400, "at", "Choose the time.")
            if start.tzinfo is None:
                start = start.replace(tzinfo=IST)
            start = start.astimezone(timezone.utc)
            if start < now - timedelta(minutes=10):
                raise PosError(400, "at", "Choose a time from now on.")
            end = start + timedelta(minutes=int(item["slot_minutes"]))
        if start > now + timedelta(days=MAX_BOOK_AHEAD_DAYS):
            raise PosError(400, "at", "Choose a time within a year.")
        return start, end

    @staticmethod
    def _taken(conn: sqlite3.Connection, item_id: str, start: datetime, end: datetime, skip: str = "") -> bool:
        return conn.execute(
            "SELECT 1 FROM pos_bookings WHERE item_id = ? AND id != ? AND status IN ('booked', 'arrived')"
            " AND start_utc < ? AND end_utc > ?", (item_id, skip, end.isoformat(), start.isoformat())).fetchone() is not None

    @staticmethod
    def _item_view(row: sqlite3.Row) -> Dict[str, Any]:
        return {"id": row["id"], "name": row["name"], "mode": row["mode"], "slot_minutes": row["slot_minutes"],
                "capacity": row["capacity"], "price_paise": row["price_paise"], "deposit_paise": row["deposit_paise"],
                "note": row["note"], "active": bool(row["active"])}

    def _view(self, conn: sqlite3.Connection, row: sqlite3.Row, *, for_shop: bool) -> Dict[str, Any]:
        item = conn.execute("SELECT name, mode FROM pos_book_items WHERE id = ?", (row["item_id"],)).fetchone()
        out = {"id": row["id"], "business_id": row["business_id"], "item_id": row["item_id"],
               "item": item["name"] if item else "", "mode": item["mode"] if item else "slot",
               "start": row["start_utc"], "end": row["end_utc"], "people": row["people"], "note": row["note"],
               "status": row["status"], "customer_name": row["customer_name"]}
        if for_shop:
            out["customer_phone"] = row["customer_phone"]
            out["from_app"] = bool(row["customer_user"])
        else:
            out["shop"] = self._shop(conn, row["business_id"])["name"]
        return out

    # ---- the shop's bookable things (owner / manager)
    def items(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            return [self._item_view(r) for r in conn.execute(
                "SELECT * FROM pos_book_items WHERE business_id = ? ORDER BY active DESC, name", (business_id,))]

    def save_item(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 60)
        mode = str(data.get("mode") or "slot")
        if not name:
            raise PosError(400, "name", "Give it a name (Room 101, Chair 1, Dr. Rao OP, Main hall ...).")
        if mode not in BOOK_MODES:
            raise PosError(400, "mode", "mode must be slot (by time) or day (by day).")
        minutes = max(5, min(int(data.get("slot_minutes") or 30), 24 * 60))
        capacity = max(1, min(int(data.get("capacity") or 1), 5000))
        price, deposit = _paise(data.get("price_paise"), "price_paise"), _paise(data.get("deposit_paise"), "deposit_paise")
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            item_id = str(data.get("id") or "")
            if item_id:
                if conn.execute("SELECT 1 FROM pos_book_items WHERE id = ? AND business_id = ?",
                                (item_id, business_id)).fetchone() is None:
                    raise PosError(404, "item", "Not found.")
                conn.execute("UPDATE pos_book_items SET name = ?, mode = ?, slot_minutes = ?, capacity = ?, price_paise = ?,"
                             " deposit_paise = ?, note = ?, active = ?, updated_at = ? WHERE id = ?",
                             (name, mode, minutes, capacity, price, deposit, _clean(data.get("note"), 200),
                              0 if data.get("active") is False else 1, now, item_id))
            else:
                item_id = _id("bki")
                conn.execute("INSERT INTO pos_book_items (id, business_id, name, mode, slot_minutes, capacity, price_paise,"
                             " deposit_paise, note, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)",
                             (item_id, business_id, name, mode, minutes, capacity, price, deposit,
                              _clean(data.get("note"), 200), now, now))
            return self._item_view(conn.execute("SELECT * FROM pos_book_items WHERE id = ?", (item_id,)).fetchone())

    # ---- free things for a time (anyone signed in; the shop page and the chat)
    def free(self, business_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        people = max(1, min(int(data.get("people") or 1), 5000))
        with self.store._connect() as conn:
            shop = self._shop(conn, business_id)
            out = []
            for item in conn.execute("SELECT * FROM pos_book_items WHERE business_id = ? AND active = 1 ORDER BY name",
                                     (business_id,)):
                if (data.get("mode") and item["mode"] != data["mode"]) or int(item["capacity"]) < people:
                    continue
                try:
                    start, end = self._span(item, data)
                except PosError:
                    continue
                if not self._taken(conn, item["id"], start, end):
                    out.append({**self._item_view(item), "start": start.isoformat(), "end": end.isoformat()})
        return {"business_id": business_id, "shop": shop["name"], "open": (shop["status"] or "open") == "open",
                "free": out}

    def _insert(self, conn: sqlite3.Connection, business_id: str, item_id: str, data: Dict[str, Any], *,
                by: str, customer_user: str, name: str, phone: str) -> Dict[str, Any]:
        item = conn.execute("SELECT * FROM pos_book_items WHERE id = ? AND business_id = ? AND active = 1",
                            (item_id, business_id)).fetchone()
        if item is None:
            raise PosError(404, "item", "That is not bookable here.")
        people = max(1, min(int(data.get("people") or 1), 5000))
        if people > int(item["capacity"]):
            raise PosError(400, "people", f"{item['name']} takes at most {item['capacity']}.")
        start, end = self._span(item, data)
        if self._taken(conn, item_id, start, end):
            raise PosError(409, "taken", f"{item['name']} is already booked for that time. Choose another time.")
        booking_id = _id("bkg")
        now = self._now()
        conn.execute("INSERT INTO pos_bookings (id, business_id, item_id, customer_user, customer_name, customer_phone,"
                     " start_utc, end_utc, people, note, status, created_by, created_at, updated_at) VALUES"
                     " (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'booked', ?, ?, ?)",
                     (booking_id, business_id, item_id, customer_user, name, phone, start.isoformat(), end.isoformat(),
                      people, _clean(data.get("note"), 200), by, now, now))
        return {"row": conn.execute("SELECT * FROM pos_bookings WHERE id = ?", (booking_id,)).fetchone(), "item": item}

    def book(self, user: str, business_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A signed-in customer books. Confirmed at once (less work for the owner); the owner is told."""
        name = _clean(data.get("name"), 60)
        with self.store._tx() as conn:
            shop = self._shop(conn, business_id)
            if (shop["status"] or "open") != "open":
                raise PosError(409, "closed", "This shop is not taking bookings now.")
            if conn.execute("SELECT COUNT(*) AS n FROM pos_bookings WHERE customer_user = ? AND business_id = ? AND"
                            " status = 'booked'", (user, business_id)).fetchone()["n"] >= 5:
                raise PosError(409, "too_many", "You already have 5 bookings here. Cancel one first.")
            made = self._insert(conn, business_id, str(data.get("item_id") or ""), data, by=user, customer_user=user,
                                name=name, phone=phone_key(user)[-10:] if phone_key(user) else "")
            view = self._view(conn, made["row"], for_shop=False)
            owner = shop["owner_user_id"]
        when = datetime.fromisoformat(view["start"]).astimezone(IST).strftime("%d %b %I:%M %p")
        self.notify(owner, f"కొత్త బుకింగ్ / New booking: {made['item']['name']}", f"{name or 'Customer'} · {when}",
                    f"/biz/{business_id}/bookings", f"booking:{view['id']}")
        return view

    def add(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """The shop adds a phone / walk-in booking."""
        phone = _phone(data.get("phone"))
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            made = self._insert(conn, business_id, str(data.get("item_id") or ""), data, by=user,
                                customer_user=_app_user(phone), name=_clean(data.get("name"), 60), phone=phone)
            return self._view(conn, made["row"], for_shop=True)

    def for_business(self, business_id: str, user: str, day: str = "") -> Dict[str, Any]:
        """The shop's bookings touching one India day (default today), plus what is coming next."""
        try:
            on = date.fromisoformat(day[:10]) if day else self.clock().astimezone(IST).date()
        except ValueError:
            raise PosError(400, "day", "day must be YYYY-MM-DD.")
        low = datetime.combine(on, time(0, 0), IST).astimezone(timezone.utc).isoformat()
        high = datetime.combine(on + timedelta(days=1), time(0, 0), IST).astimezone(timezone.utc).isoformat()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            cut = (self.clock() - timedelta(minutes=30)).isoformat()
            conn.execute("UPDATE pos_bookings SET status = 'no_show', updated_at = ? WHERE business_id = ? AND"
                         " status = 'booked' AND end_utc < ?", (self._now(), business_id, cut))
            rows = conn.execute("SELECT * FROM pos_bookings WHERE business_id = ? AND start_utc < ? AND end_utc > ?"
                                " ORDER BY start_utc", (business_id, high, low)).fetchall()
            upcoming = conn.execute("SELECT COUNT(*) AS n FROM pos_bookings WHERE business_id = ? AND status = 'booked'"
                                    " AND start_utc >= ?", (business_id, high)).fetchone()["n"]
            return {"day": on.isoformat(), "bookings": [self._view(conn, r, for_shop=True) for r in rows],
                    "upcoming": int(upcoming)}

    def set_status(self, business_id: str, user: str, booking_id: str, status: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            row = conn.execute("SELECT * FROM pos_bookings WHERE id = ? AND business_id = ?",
                               (booking_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "booking", "Booking not found.")
            if status not in BOOK_NEXT.get(row["status"], ()):
                raise PosError(409, "status", f"A {row['status']} booking cannot become {status}.")
            conn.execute("UPDATE pos_bookings SET status = ?, updated_at = ? WHERE id = ?", (status, self._now(), booking_id))
            view = self._view(conn, conn.execute("SELECT * FROM pos_bookings WHERE id = ?", (booking_id,)).fetchone(),
                              for_shop=True)
            customer = row["customer_user"]
        if status == "cancelled" and customer:
            self.notify(customer, "బుకింగ్ రద్దు / Booking cancelled", f"{view['item']}", "/me/bookings",
                        f"booking-cancel:{booking_id}")
        return view

    def mine(self, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            rows = conn.execute("SELECT * FROM pos_bookings WHERE customer_user = ? ORDER BY start_utc DESC LIMIT 50",
                                (user,)).fetchall()
            return [self._view(conn, r, for_shop=False) for r in rows]

    def cancel_mine(self, user: str, booking_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_bookings WHERE id = ? AND customer_user = ?", (booking_id, user)).fetchone()
            if row is None:
                raise PosError(404, "booking", "Booking not found.")
            if row["status"] != "booked":
                raise PosError(409, "status", "Only a booking that has not started can be cancelled.")
            conn.execute("UPDATE pos_bookings SET status = 'cancelled', updated_at = ? WHERE id = ?", (self._now(), booking_id))
            view = self._view(conn, conn.execute("SELECT * FROM pos_bookings WHERE id = ?", (booking_id,)).fetchone(),
                              for_shop=False)
            owner = self._shop(conn, row["business_id"])["owner_user_id"]
        self.notify(owner, "బుకింగ్ రద్దు / Booking cancelled", f"{view['item']} · {row['customer_name']}",
                    f"/biz/{row['business_id']}/bookings", f"booking-cancel:{booking_id}")
        return view


# ================================================================== way 4: job cards
class PosJobs(_Base):
    @staticmethod
    def _view(row: sqlite3.Row, shop: str = "", *, for_shop: bool = True) -> Dict[str, Any]:
        out = {"id": row["id"], "business_id": row["business_id"], "token": row["token"], "item": row["item"],
               "details": row["details"], "estimate_paise": row["estimate_paise"], "advance_paise": row["advance_paise"],
               "balance_paise": max(0, row["estimate_paise"] - row["advance_paise"]), "ready_by": row["ready_by"],
               "status": row["status"], "customer_name": row["customer_name"], "created_at": row["created_at"],
               "history": json.loads(row["history"] or "[]")}
        if for_shop:
            out["customer_phone"] = row["customer_phone"]
            out["in_app"] = bool(row["customer_user"])
        else:
            out["shop"] = shop
        return out

    def create(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        item = _clean(data.get("item"), 80)
        if not item:
            raise PosError(400, "item", "What is it? (phone model, blouse, cake, application ...)")
        phone = _phone(data.get("phone"))
        estimate, advance = _paise(data.get("estimate_paise"), "estimate_paise"), _paise(data.get("advance_paise"), "advance_paise")
        ready_by = str(data.get("ready_by") or "")[:10]
        if ready_by:
            try:
                date.fromisoformat(ready_by)
            except ValueError:
                raise PosError(400, "ready_by", "ready_by must be YYYY-MM-DD.")
        txn = _clean(data.get("client_txn_id"), 64)
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            if txn:
                again = conn.execute("SELECT * FROM pos_jobs WHERE business_id = ? AND client_txn_id = ?",
                                     (business_id, txn)).fetchone()
                if again is not None:
                    return self._view(again)
            token = int(conn.execute("SELECT COALESCE(MAX(token), 0) AS t FROM pos_jobs WHERE business_id = ?",
                                     (business_id,)).fetchone()["t"]) + 1
            job_id = _id("job")
            conn.execute("INSERT INTO pos_jobs (id, business_id, token, customer_name, customer_phone, customer_user, item,"
                         " details, estimate_paise, advance_paise, ready_by, status, history, created_by, created_at,"
                         " updated_at, client_txn_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'received', ?, ?, ?, ?, ?)",
                         (job_id, business_id, token, _clean(data.get("name"), 60), phone, _app_user(phone), item,
                          _clean(data.get("details"), 600), estimate, advance, ready_by,
                          json.dumps([{"status": "received", "at": now}]), user, now, now, txn))
            return self._view(conn.execute("SELECT * FROM pos_jobs WHERE id = ?", (job_id,)).fetchone())

    def for_business(self, business_id: str, user: str, status: str = "open") -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            if status == "open":
                rows = conn.execute("SELECT * FROM pos_jobs WHERE business_id = ? AND status IN ('received', 'working',"
                                    " 'ready') ORDER BY CASE status WHEN 'ready' THEN 0 ELSE 1 END, ready_by = '',"
                                    " ready_by, token", (business_id,)).fetchall()
            elif status in JOB_STATUSES:
                rows = conn.execute("SELECT * FROM pos_jobs WHERE business_id = ? AND status = ? ORDER BY updated_at DESC"
                                    " LIMIT 100", (business_id, status)).fetchall()
            else:
                raise PosError(400, "status", "status must be open or one of " + ", ".join(JOB_STATUSES))
            counts = {r["status"]: r["n"] for r in conn.execute(
                "SELECT status, COUNT(*) AS n FROM pos_jobs WHERE business_id = ? GROUP BY status", (business_id,))}
        return {"jobs": [self._view(r) for r in rows], "counts": counts}

    def update(self, business_id: str, user: str, job_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Move a job on (status) and / or change its estimate, advance, ready date, details. Ready -> the customer is told
        in the app; the answer carries a WhatsApp text for a customer who is not on ASKODOX."""
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            row = conn.execute("SELECT * FROM pos_jobs WHERE id = ? AND business_id = ?", (job_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "job", "Job not found.")
            shop = self._shop(conn, business_id)["name"]
            changes: Dict[str, Any] = {}
            status = str(data.get("status") or "")
            if status and status != row["status"]:
                if status not in JOB_NEXT.get(row["status"], ()):
                    raise PosError(409, "status", f"A {row['status']} job cannot become {status}.")
                changes["status"] = status
            for key in ("estimate_paise", "advance_paise"):
                if key in data and data[key] is not None:
                    changes[key] = _paise(data[key], key)
            if "ready_by" in data and data["ready_by"] is not None:
                ready_by = str(data["ready_by"])[:10]
                if ready_by:
                    try:
                        date.fromisoformat(ready_by)
                    except ValueError:
                        raise PosError(400, "ready_by", "ready_by must be YYYY-MM-DD.")
                changes["ready_by"] = ready_by
            if "details" in data and data["details"] is not None:
                changes["details"] = _clean(data["details"], 600)
            if not changes:
                return self._view(row)
            history = json.loads(row["history"] or "[]")
            if "status" in changes:
                history.append({"status": changes["status"], "at": now})
            sets = ", ".join(f"{k} = ?" for k in changes)
            conn.execute(f"UPDATE pos_jobs SET {sets}, history = ?, updated_at = ? WHERE id = ?",
                         (*changes.values(), json.dumps(history[-20:]), now, job_id))
            fresh = conn.execute("SELECT * FROM pos_jobs WHERE id = ?", (job_id,)).fetchone()
        out = self._view(fresh)
        if changes.get("status") == "ready":
            balance = out["balance_paise"]
            words = (f"{shop}: మీ {fresh['item']} రెడీ (టోకెన్ {fresh['token']})."
                     + (f" మిగతా {_rupees(balance)}." if balance else "") + " వచ్చి తీసుకోండి.")
            if fresh["customer_user"]:
                self.notify(fresh["customer_user"], f"{shop}: రెడీ / Ready", words, "/me/jobs", f"job-ready:{job_id}")
            out["whatsapp_url"] = _wa(fresh["customer_phone"], words)
        return out

    def mine(self, user: str) -> List[Dict[str, Any]]:
        key = phone_key(user)[-10:] if phone_key(user) else ""
        with self.store._connect() as conn:
            rows = conn.execute("SELECT j.*, b.name AS shop FROM pos_jobs j JOIN pos_businesses b ON b.id = j.business_id"
                                " WHERE j.customer_user = ? OR (? != '' AND j.customer_phone = ?) ORDER BY j.created_at"
                                " DESC LIMIT 50", (user, key, key)).fetchall()
        return [self._view(r, r["shop"], for_shop=False) for r in rows]


# ================================================================== way 5: monthly
class PosMonthly(_Base):
    def _month(self) -> str:
        return self.clock().astimezone(IST).strftime("%Y-%m")

    def plans(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "customers")
            return [{"id": r["id"], "name": r["name"], "amount_paise": r["amount_paise"], "note": r["note"],
                     "active": bool(r["active"]),
                     "members": conn.execute("SELECT COUNT(*) AS n FROM pos_month_members WHERE plan_id = ? AND"
                                             " status = 'active'", (r["id"],)).fetchone()["n"]}
                    for r in conn.execute("SELECT * FROM pos_month_plans WHERE business_id = ? ORDER BY active DESC, name",
                                          (business_id,))]

    def save_plan(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 60)
        amount = _paise(data.get("amount_paise"), "amount_paise")
        if not name or amount <= 0:
            raise PosError(400, "plan", "Give the plan a name and its monthly amount.")
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            plan_id = str(data.get("id") or "")
            if plan_id:
                if conn.execute("SELECT 1 FROM pos_month_plans WHERE id = ? AND business_id = ?",
                                (plan_id, business_id)).fetchone() is None:
                    raise PosError(404, "plan", "Plan not found.")
                conn.execute("UPDATE pos_month_plans SET name = ?, amount_paise = ?, note = ?, active = ?, updated_at = ?"
                             " WHERE id = ?", (name, amount, _clean(data.get("note"), 200),
                                               0 if data.get("active") is False else 1, now, plan_id))
            else:
                plan_id = _id("mpl")
                conn.execute("INSERT INTO pos_month_plans (id, business_id, name, amount_paise, note, active, created_at,"
                             " updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)",
                             (plan_id, business_id, name, amount, _clean(data.get("note"), 200), now, now))
        return next(p for p in self.plans(business_id, user) if p["id"] == plan_id)

    def add_member(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 60)
        phone = _phone(data.get("phone"))
        if not name:
            raise PosError(400, "name", "Whose plan is it? Give the name.")
        due_day = max(1, min(int(data.get("due_day") or 5), 28))
        now = self._now()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            if conn.execute("SELECT 1 FROM pos_month_plans WHERE id = ? AND business_id = ? AND active = 1",
                            (str(data.get("plan_id") or ""), business_id)).fetchone() is None:
                raise PosError(404, "plan", "Choose one of the shop's plans.")
            member_id = _id("mmb")
            conn.execute("INSERT INTO pos_month_members (id, business_id, plan_id, customer_name, customer_phone,"
                         " customer_user, start_month, due_day, status, note, created_at, updated_at) VALUES"
                         " (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)",
                         (member_id, business_id, data["plan_id"], name, phone, _app_user(phone),
                          str(data.get("start_month") or self._month())[:7], due_day, _clean(data.get("note"), 200),
                          now, now))
        return self.month(business_id, user)

    def _ensure_dues(self, conn: sqlite3.Connection, business_id: str, month: str) -> None:
        """This month's due for every active member who started by then (made when looked at, never twice)."""
        now = self._now()
        for m in conn.execute("SELECT m.id, p.amount_paise FROM pos_month_members m JOIN pos_month_plans p ON"
                              " p.id = m.plan_id WHERE m.business_id = ? AND m.status = 'active' AND m.start_month <= ?",
                              (business_id, month)).fetchall():
            conn.execute("INSERT OR IGNORE INTO pos_month_dues (member_id, business_id, month, amount_paise, updated_at)"
                         " VALUES (?, ?, ?, ?, ?)", (m["id"], business_id, month, m["amount_paise"], now))

    def month(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        month = month[:7] if re.fullmatch(r"\d{4}-\d{2}", month[:7] or "") else self._month()
        today = self.clock().astimezone(IST)
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            shop = self._shop(conn, business_id)["name"]
            self._ensure_dues(conn, business_id, month)
            rows = conn.execute(
                "SELECT m.*, p.name AS plan, d.amount_paise AS due, d.paid_paise, d.status AS due_status FROM"
                " pos_month_members m JOIN pos_month_plans p ON p.id = m.plan_id LEFT JOIN pos_month_dues d ON"
                " d.member_id = m.id AND d.month = ? WHERE m.business_id = ? ORDER BY m.status, m.customer_name",
                (month, business_id)).fetchall()
        members, owed, collected = [], 0, 0
        for r in rows:
            due, paid = int(r["due"] or 0), int(r["paid_paise"] or 0)
            left = max(0, due - paid) if r["due_status"] == "due" else 0
            late = bool(left) and month == today.strftime("%Y-%m") and today.day > int(r["due_day"])
            owed += left
            collected += paid
            text = f"{shop}: {r['plan']} {month} నెల {_rupees(left)} కట్టాలి. దయచేసి కట్టండి."
            members.append({"id": r["id"], "name": r["customer_name"], "phone": r["customer_phone"], "plan": r["plan"],
                            "plan_id": r["plan_id"], "status": r["status"], "due_day": r["due_day"],
                            "due_paise": due, "paid_paise": paid, "left_paise": left,
                            "due_status": r["due_status"] or "", "late": late,
                            "whatsapp_url": _wa(r["customer_phone"], text) if left else ""})
        return {"month": month, "members": members, "owed_paise": owed, "collected_paise": collected}

    def pay(self, business_id: str, user: str, member_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record what the shop received for a member's month (full, part) or waive it. Money stays with the shop."""
        month = str(data.get("month") or self._month())[:7]
        waive = bool(data.get("waive"))
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "collect" if not waive else "customers")
            self._ensure_dues(conn, business_id, month)
            due = conn.execute("SELECT * FROM pos_month_dues WHERE member_id = ? AND business_id = ? AND month = ?",
                               (member_id, business_id, month)).fetchone()
            if due is None:
                raise PosError(404, "member", "No due for that member and month.")
            now = self._now()
            if waive:
                conn.execute("UPDATE pos_month_dues SET status = 'waived', updated_at = ? WHERE member_id = ? AND month = ?",
                             (now, member_id, month))
            else:
                amount = _paise(data.get("amount_paise") or (due["amount_paise"] - due["paid_paise"]), "amount_paise")
                paid = min(due["amount_paise"], due["paid_paise"] + amount)
                conn.execute("UPDATE pos_month_dues SET paid_paise = ?, status = ?, paid_at = ?, updated_at = ? WHERE"
                             " member_id = ? AND month = ?", (paid, "paid" if paid >= due["amount_paise"] else "due",
                                                               now, now, member_id, month))
        return self.month(business_id, user, month)

    def set_member(self, business_id: str, user: str, member_id: str, status: str) -> Dict[str, Any]:
        if status not in MEMBER_STATUSES:
            raise PosError(400, "status", "status must be active, paused or stopped.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "customers")
            if conn.execute("UPDATE pos_month_members SET status = ?, updated_at = ? WHERE id = ? AND business_id = ?",
                            (status, self._now(), member_id, business_id)).rowcount == 0:
                raise PosError(404, "member", "Member not found.")
        return self.month(business_id, user)

    def mine(self, user: str) -> List[Dict[str, Any]]:
        key = phone_key(user)[-10:] if phone_key(user) else ""
        month = self._month()
        with self.store._tx() as conn:
            rows = conn.execute("SELECT m.*, p.name AS plan, p.amount_paise, b.name AS shop FROM pos_month_members m JOIN"
                                " pos_month_plans p ON p.id = m.plan_id JOIN pos_businesses b ON b.id = m.business_id WHERE"
                                " m.status = 'active' AND (m.customer_user = ? OR (? != '' AND m.customer_phone = ?))",
                                (user, key, key)).fetchall()
            out = []
            for r in rows:
                self._ensure_dues(conn, r["business_id"], month)
                due = conn.execute("SELECT * FROM pos_month_dues WHERE member_id = ? AND month = ?", (r["id"], month)).fetchone()
                left = max(0, due["amount_paise"] - due["paid_paise"]) if due and due["status"] == "due" else 0
                out.append({"shop": r["shop"], "business_id": r["business_id"], "plan": r["plan"], "month": month,
                            "amount_paise": r["amount_paise"], "left_paise": left, "due_day": r["due_day"]})
        return out
