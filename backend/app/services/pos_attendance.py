"""Staff attendance, salary and tasks (owner 2026-11-18).

How attendance is proven -- honestly:
- A phone's fingerprint / face lock only knows the phone's OWN owner. So each person checks in on their OWN phone
  (the app asks the phone's lock first: ``method = device_lock``) and the phone sends where it is; the distance to the
  shop's map pin is saved with the row. Far away = the row says so (the owner decides).
- People without a phone use the shop phone / tablet (``kiosk``): a photo + the time; the owner sees the photo.
  Photos are only for the owner / manager and are deleted after ``PHOTO_KEEP_DAYS``.
- The owner can always mark P / A / OT / leave by hand (``owner``).

Attendance -> salary (worked out, explained line by line) -> "paid" writes the salary into the cashbook -> the night
report reads the same rows. Nothing here moves money.
"""

from __future__ import annotations

import base64
import calendar
import json
import math
import re
import uuid
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services.account_identity import phone_key
from app.services.pos_store import IST, PosError, PosStore

PHOTO_KEEP_DAYS = 90
STATUSES = ("P", "A", "OT", "leave", "half")

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS pos_att_settings (business_id TEXT PRIMARY KEY, start_time TEXT NOT NULL DEFAULT '09:00',"
    " end_time TEXT NOT NULL DEFAULT '21:00', grace_min INTEGER NOT NULL DEFAULT 15, radius_m INTEGER NOT NULL DEFAULT 150,"
    " own_phone INTEGER NOT NULL DEFAULT 1, kiosk INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_staff_pay (business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " salary_kind TEXT NOT NULL DEFAULT 'month', salary_paise INTEGER NOT NULL DEFAULT 0,"
    " ot_rate_paise INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, PRIMARY KEY (business_id, phone_key))",
    "CREATE TABLE IF NOT EXISTS pos_attendance (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " local_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'P', in_at TEXT, out_at TEXT, late_min INTEGER NOT NULL DEFAULT 0,"
    " ot_min INTEGER NOT NULL DEFAULT 0, method TEXT NOT NULL DEFAULT 'owner', distance_m INTEGER, far INTEGER NOT NULL DEFAULT 0,"
    " note TEXT NOT NULL DEFAULT '', marked_by TEXT NOT NULL, updated_at TEXT NOT NULL,"
    " UNIQUE (business_id, phone_key, local_date))",
    "CREATE INDEX IF NOT EXISTS idx_pos_att_day ON pos_attendance(business_id, local_date)",
    "CREATE TABLE IF NOT EXISTS pos_att_photos (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, attendance_id TEXT NOT NULL,"
    " kind TEXT NOT NULL, image BLOB NOT NULL, mime TEXT NOT NULL, created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_staff_advances (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " amount_paise INTEGER NOT NULL, local_date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', by_user TEXT NOT NULL,"
    " removed_at TEXT, created_at TEXT NOT NULL)",
    # Owner 2026-11-20: shop holidays (a paid day for monthly-salary staff) and extra bonus for a month.
    "CREATE TABLE IF NOT EXISTS pos_att_holidays (business_id TEXT NOT NULL, local_date TEXT NOT NULL, name TEXT NOT NULL"
    " DEFAULT '', PRIMARY KEY (business_id, local_date))",
    "CREATE TABLE IF NOT EXISTS pos_staff_bonus (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " month TEXT NOT NULL, amount_paise INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', by_user TEXT NOT NULL,"
    " created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_salary_paid (business_id TEXT NOT NULL, phone_key TEXT NOT NULL, month TEXT NOT NULL,"
    " amount_paise INTEGER NOT NULL, paid_at TEXT NOT NULL, by_user TEXT NOT NULL, cashbook_id TEXT,"
    " PRIMARY KEY (business_id, phone_key, month))",
    "CREATE TABLE IF NOT EXISTS pos_tasks (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, title TEXT NOT NULL,"
    " assignee TEXT NOT NULL, due_at TEXT, status TEXT NOT NULL DEFAULT 'open', done_at TEXT, created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_tasks_biz ON pos_tasks(business_id, status)",
)


def _now() -> datetime:
    return datetime.now(IST)


def _hhmm(text: str, default: str) -> str:
    return text if re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", str(text or "")) else default


def _distance_m(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> int:
    r = 6371000.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = math.radians(b_lat - a_lat), math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return int(2 * r * math.asin(math.sqrt(h)))


class PosAttendance:
    def __init__(self, store: PosStore, *, notify: Optional[Callable[..., None]] = None,
                 clock: Callable[[], datetime] = _now) -> None:
        self.store = store
        self.notify = notify
        self.clock = clock
        with store._connect() as conn:
            for stmt in SCHEMA:
                conn.execute(stmt)

    # ------------------------------------------------------------------------------------------------ helpers
    def _me(self, conn, business_id: str, user: str) -> Dict[str, Any]:
        """The caller's own member row (anyone in the shop, owner included)."""
        role = self.store._require(conn, business_id, user, "view")
        row = conn.execute("SELECT phone_key, label, role FROM pos_members WHERE business_id = ? AND active = 1"
                           " AND (app_user_id = ? OR phone_key = ?)", (business_id, user, phone_key(user))).fetchone()
        if row is None:
            raise PosError(404, "member", "You are not on this shop's staff list.")
        return {"key": row["phone_key"], "name": row["label"] or "", "role": role}

    def _staff_key(self, conn, business_id: str, ref: str) -> str:
        """A staff reference from the app: the full phone key or its last 4 digits (unique in the shop)."""
        digits = re.sub(r"\D", "", str(ref or ""))
        rows = conn.execute("SELECT phone_key FROM pos_members WHERE business_id = ? AND active = 1",
                            (business_id,)).fetchall()
        exact = [r["phone_key"] for r in rows if r["phone_key"] == digits]
        if exact:
            return exact[0]
        tail = [r["phone_key"] for r in rows if digits and r["phone_key"].endswith(digits)]
        if len(tail) == 1:
            return tail[0]
        raise PosError(404, "staff", "Staff member not found.")

    def settings(self, conn, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_att_settings WHERE business_id = ?", (business_id,)).fetchone()
        base = {"start_time": "09:00", "end_time": "21:00", "grace_min": 15, "radius_m": 150, "own_phone": True,
                "kiosk": True}
        if row:
            base.update({"start_time": row["start_time"], "end_time": row["end_time"], "grace_min": row["grace_min"],
                         "radius_m": row["radius_m"], "own_phone": bool(row["own_phone"]), "kiosk": bool(row["kiosk"])})
        return base

    def _shop_pin(self, conn, business_id: str) -> Optional[tuple]:
        try:
            row = conn.execute("SELECT data FROM shop_profiles WHERE business_id = ?", (business_id,)).fetchone()
            data = json.loads(row["data"]) if row else {}
            return float(data["lat"]), float(data["lng"])
        except Exception:
            return None

    def _purge_photos(self, conn) -> None:
        cutoff = (self.clock() - timedelta(days=PHOTO_KEEP_DAYS)).isoformat()
        conn.execute("DELETE FROM pos_att_photos WHERE created_at < ?", (cutoff,))

    # ------------------------------------------------------------------------------------------------ settings
    def get_settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            out = self.settings(conn, business_id)
            out["shop_pin"] = self._shop_pin(conn, business_id) is not None
            return out

    def set_settings(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            cur = self.settings(conn, business_id)
            cur.update({k: v for k, v in data.items() if k in cur and v is not None})
            conn.execute(
                "INSERT INTO pos_att_settings (business_id, start_time, end_time, grace_min, radius_m, own_phone, kiosk,"
                " updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET"
                " start_time = excluded.start_time, end_time = excluded.end_time, grace_min = excluded.grace_min,"
                " radius_m = excluded.radius_m, own_phone = excluded.own_phone, kiosk = excluded.kiosk,"
                " updated_at = excluded.updated_at",
                (business_id, _hhmm(cur["start_time"], "09:00"), _hhmm(cur["end_time"], "21:00"),
                 max(0, min(int(cur["grace_min"]), 180)), max(30, min(int(cur["radius_m"]), 5000)),
                 int(bool(cur["own_phone"])), int(bool(cur["kiosk"])), self.clock().isoformat()))
            return self.settings(conn, business_id)

    def set_pay(self, business_id: str, user: str, ref: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("salary_kind") or "month")
        if kind not in ("month", "day"):
            raise PosError(400, "salary_kind", "Salary is per month or per day.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            conn.execute(
                "INSERT INTO pos_staff_pay (business_id, phone_key, salary_kind, salary_paise, ot_rate_paise, updated_at)"
                " VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(business_id, phone_key) DO UPDATE SET"
                " salary_kind = excluded.salary_kind, salary_paise = excluded.salary_paise,"
                " ot_rate_paise = excluded.ot_rate_paise, updated_at = excluded.updated_at",
                (business_id, key, kind, max(0, int(data.get("salary_paise") or 0)),
                 max(0, int(data.get("ot_rate_paise") or 0)), self.clock().isoformat()))
        return {"ok": True}

    # ------------------------------------------------------------------------------------------------ check in / out
    def check(self, business_id: str, user: str, action: str, *, lat: Optional[float] = None,
              lng: Optional[float] = None, method: str = "device_lock", photo_b64: str = "",
              for_ref: str = "") -> Dict[str, Any]:
        """``action`` in / out / leave. On the person's own phone ``for_ref`` is empty; the shop phone (kiosk, owner /
        manager signed in) passes the staff reference and a photo."""
        if action not in ("in", "out", "leave", "half"):
            raise PosError(400, "action", "Choose in, out, half or leave.")
        now = self.clock()
        today = now.strftime("%Y-%m-%d")
        with self.store._tx() as conn:
            if for_ref:
                self.store._require(conn, business_id, user, "members")
                key = self._staff_key(conn, business_id, for_ref)
                method = "kiosk"
                if not photo_b64:
                    raise PosError(400, "photo", "Take a photo at the shop phone.")
            else:
                key = self._me(conn, business_id, user)["key"]
                if method not in ("device_lock", "photo"):
                    method = "device_lock"
            st = self.settings(conn, business_id)
            distance, far = None, False
            pin = self._shop_pin(conn, business_id)
            if pin and lat is not None and lng is not None:
                distance = _distance_m(pin[0], pin[1], float(lat), float(lng))
                far = distance > int(st["radius_m"])
            row = conn.execute("SELECT * FROM pos_attendance WHERE business_id = ? AND phone_key = ? AND local_date = ?",
                               (business_id, key, today)).fetchone()
            if action == "leave":
                status, in_at, out_at, late, ot = "leave", None, None, 0, 0
            elif action == "half":
                # Owner 2026-11-19: the staff member says "half day" themselves; the owner does not mark it.
                status, late, ot = "half", (row["late_min"] if row else 0), 0
                in_at = row["in_at"] if row and row["in_at"] else now.isoformat()
                out_at = now.isoformat() if row and row["in_at"] else None
            elif action == "in":
                if row and row["in_at"]:
                    return {"already": True, **self._view(dict(row))}
                start = datetime.strptime(f"{today} {st['start_time']}", "%Y-%m-%d %H:%M").replace(tzinfo=IST)
                late = max(0, int((now - start).total_seconds() // 60) - int(st["grace_min"]))
                status, in_at, out_at, ot = "P", now.isoformat(), None, 0
            else:  # out
                if not row or not row["in_at"]:
                    raise PosError(409, "not_in", "Check in first.")
                in_time = datetime.fromisoformat(row["in_at"])
                shift = (datetime.strptime(st["end_time"], "%H:%M") - datetime.strptime(st["start_time"], "%H:%M"))
                worked = now - in_time
                ot = max(0, int((worked - shift).total_seconds() // 60))
                status = "OT" if ot >= 30 else row["status"]
                # Less than half the shift worked -> a half day by itself (the owner can still change it).
                if status == "P" and shift.total_seconds() > 0 and worked.total_seconds() < shift.total_seconds() / 2:
                    status = "half"
                in_at, out_at, late = row["in_at"], now.isoformat(), row["late_min"]
            att_id = row["id"] if row else "att_" + uuid.uuid4().hex[:14]
            conn.execute(
                "INSERT INTO pos_attendance (id, business_id, phone_key, local_date, status, in_at, out_at, late_min, ot_min,"
                " method, distance_m, far, marked_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                " ON CONFLICT(business_id, phone_key, local_date) DO UPDATE SET status = excluded.status,"
                " in_at = excluded.in_at, out_at = excluded.out_at, late_min = excluded.late_min, ot_min = excluded.ot_min,"
                " method = excluded.method, distance_m = COALESCE(excluded.distance_m, pos_attendance.distance_m),"
                " far = MAX(excluded.far, pos_attendance.far), marked_by = excluded.marked_by, updated_at = excluded.updated_at",
                (att_id, business_id, key, today, status, in_at, out_at, late, ot, method, distance, int(far), user,
                 now.isoformat()))
            if photo_b64:
                try:
                    image = base64.b64decode(photo_b64, validate=True)
                except Exception as exc:
                    raise PosError(400, "photo", "The photo could not be read.") from exc
                if len(image) > 400_000:
                    raise PosError(413, "photo", "The photo is too big (max 400 KB).")
                conn.execute("INSERT INTO pos_att_photos (id, business_id, attendance_id, kind, image, mime, created_at)"
                             " VALUES (?, ?, ?, ?, ?, ?, ?)", ("ap_" + uuid.uuid4().hex[:14], business_id, att_id, action,
                                                               image, "image/jpeg", now.isoformat()))
            self._purge_photos(conn)
            saved = dict(conn.execute("SELECT * FROM pos_attendance WHERE id = ? OR (business_id = ? AND phone_key = ?"
                                      " AND local_date = ?)", (att_id, business_id, key, today)).fetchone())
        return self._view(saved)

    def mark(self, business_id: str, user: str, ref: str, day: str, status: str, ot_min: int = 0,
             note: str = "") -> Dict[str, Any]:
        """The owner's own P / A / OT / leave / half for any day (fixes a missed check-in too)."""
        if status not in STATUSES:
            raise PosError(400, "status", "Choose P, A, OT, leave or half.")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day or ""):
            raise PosError(400, "date", "Choose the day.")
        now = self.clock()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            conn.execute(
                "INSERT INTO pos_attendance (id, business_id, phone_key, local_date, status, ot_min, method, note,"
                " marked_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, 'owner', ?, ?, ?)"
                " ON CONFLICT(business_id, phone_key, local_date) DO UPDATE SET status = excluded.status,"
                " ot_min = excluded.ot_min, note = excluded.note, marked_by = excluded.marked_by,"
                " updated_at = excluded.updated_at",
                ("att_" + uuid.uuid4().hex[:14], business_id, key, day, status, max(0, int(ot_min or 0)),
                 str(note or "")[:120], user, now.isoformat()))
        return {"ok": True}

    def _view(self, r: Dict[str, Any]) -> Dict[str, Any]:
        return {"id": r["id"], "date": r["local_date"], "status": r["status"], "in_at": r["in_at"], "out_at": r["out_at"],
                "late_min": r["late_min"], "ot_min": r["ot_min"], "method": r["method"], "distance_m": r["distance_m"],
                "far": bool(r["far"]), "note": r.get("note") or ""}

    # ------------------------------------------------------------------------------------------------ views
    def today(self, business_id: str, user: str) -> Dict[str, Any]:
        """Owner / manager: everyone today. A staff member: only themself."""
        now = self.clock()
        day = now.strftime("%Y-%m-%d")
        with self.store._connect() as conn:
            role = self.store._require(conn, business_id, user, "view")
            boss = role in ("owner", "manager")
            members = conn.execute("SELECT phone_key, label, role FROM pos_members WHERE business_id = ? AND active = 1"
                                   " AND role != 'owner' ORDER BY created_at", (business_id,)).fetchall()
            if not boss:
                mine = self._me(conn, business_id, user)["key"]
                members = [m for m in members if m["phone_key"] == mine]
            rows = {r["phone_key"]: dict(r) for r in conn.execute(
                "SELECT * FROM pos_attendance WHERE business_id = ? AND local_date = ?", (business_id, day))}
            photos = {r["attendance_id"] for r in conn.execute(
                "SELECT attendance_id FROM pos_att_photos WHERE business_id = ?", (business_id,))} if boss else set()
            people = []
            for m in members:
                att = rows.get(m["phone_key"])
                people.append({"ref": m["phone_key"][-4:], "name": m["label"] or "", "role": m["role"],
                               "today": self._view(att) if att else None,
                               "has_photo": bool(att and att["id"] in photos)})
            st = self.settings(conn, business_id)
        present = sum(1 for p in people if p["today"] and p["today"]["status"] in ("P", "OT", "half"))
        return {"date": day, "people": people, "settings": st, "boss": boss,
                "counts": {"present": present, "absent": len(people) - present -
                           sum(1 for p in people if p["today"] and p["today"]["status"] == "leave"),
                           "late": sum(1 for p in people if p["today"] and p["today"]["late_min"] > 0),
                           "far": sum(1 for p in people if p["today"] and p["today"]["far"])}}

    def photo(self, business_id: str, user: str, attendance_id: str) -> tuple:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "members")
            row = conn.execute("SELECT image, mime FROM pos_att_photos WHERE business_id = ? AND attendance_id = ?"
                               " ORDER BY created_at DESC LIMIT 1", (business_id, attendance_id)).fetchone()
        if not row:
            raise PosError(404, "photo", "No photo.")
        return bytes(row["image"]), row["mime"]

    def month(self, business_id: str, user: str, ref: str, month: str = "") -> Dict[str, Any]:
        now = self.clock()
        if not re.fullmatch(r"\d{4}-\d{2}", month or ""):
            month = now.strftime("%Y-%m")
        y, m = int(month[:4]), int(month[5:])
        last = calendar.monthrange(y, m)[1]
        with self.store._connect() as conn:
            role = self.store._require(conn, business_id, user, "view")
            if role in ("owner", "manager"):
                key = self._staff_key(conn, business_id, ref)
            else:
                key = self._me(conn, business_id, user)["key"]
            member = conn.execute("SELECT label, role FROM pos_members WHERE business_id = ? AND phone_key = ?",
                                  (business_id, key)).fetchone()
            rows = {r["local_date"]: self._view(dict(r)) for r in conn.execute(
                "SELECT * FROM pos_attendance WHERE business_id = ? AND phone_key = ? AND local_date BETWEEN ? AND ?",
                (business_id, key, f"{month}-01", f"{month}-31"))}
            adv = {}
            for r in conn.execute("SELECT local_date, SUM(amount_paise) AS a FROM pos_staff_advances WHERE business_id = ?"
                                  " AND phone_key = ? AND removed_at IS NULL AND local_date BETWEEN ? AND ? GROUP BY local_date",
                                  (business_id, key, f"{month}-01", f"{month}-31")):
                adv[r["local_date"]] = int(r["a"] or 0)
            pay = self._pay(conn, business_id, key)
            holidays = {r["local_date"]: r["name"] for r in conn.execute(
                "SELECT local_date, name FROM pos_att_holidays WHERE business_id = ? AND local_date BETWEEN ? AND ?",
                (business_id, f"{month}-01", f"{month}-31"))}
            bonus = int(conn.execute("SELECT COALESCE(SUM(amount_paise), 0) AS a FROM pos_staff_bonus WHERE business_id = ?"
                                     " AND phone_key = ? AND month = ?", (business_id, key, month)).fetchone()["a"])
            paid = conn.execute("SELECT amount_paise, paid_at FROM pos_salary_paid WHERE business_id = ? AND phone_key = ?"
                                " AND month = ?", (business_id, key, month)).fetchone()
        days = []
        for d in range(1, last + 1):
            day = f"{month}-{d:02d}"
            if day > now.strftime("%Y-%m-%d"):
                break
            days.append({"date": day, "weekday": datetime(y, m, d).weekday(), "att": rows.get(day),
                         "advance_paise": adv.get(day, 0), "holiday": holidays.get(day)})
        counts = self._counts(rows.values())
        # a shop holiday already passed, on which the person did not work, is a paid day (monthly salary)
        today = now.strftime("%Y-%m-%d")
        counts["holiday"] = sum(1 for day in holidays
                                if day <= today and (rows.get(day) or {}).get("status") not in ("P", "OT", "half"))
        salary = self._salary(pay, counts, sum(adv.values()), last, bonus)
        return {"month": month, "ref": key[-4:], "name": (member["label"] if member else "") or "",
                "role": member["role"] if member else "", "days": days, "counts": counts,
                "advance_paise": sum(adv.values()), "pay": pay, "salary": salary,
                "paid": {"amount_paise": paid["amount_paise"], "paid_at": paid["paid_at"]} if paid else None}

    def _pay(self, conn, business_id: str, key: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_staff_pay WHERE business_id = ? AND phone_key = ?", (business_id, key)).fetchone()
        return {"salary_kind": row["salary_kind"], "salary_paise": row["salary_paise"], "ot_rate_paise": row["ot_rate_paise"]} \
            if row else {"salary_kind": "month", "salary_paise": 0, "ot_rate_paise": 0}

    @staticmethod
    def _counts(rows) -> Dict[str, Any]:
        rows = list(rows)
        return {"present": sum(1 for r in rows if r["status"] in ("P", "OT")),
                "half": sum(1 for r in rows if r["status"] == "half"),
                "absent": sum(1 for r in rows if r["status"] == "A"),
                "leave": sum(1 for r in rows if r["status"] == "leave"),
                "ot_min": sum(int(r["ot_min"] or 0) for r in rows),
                "late": sum(1 for r in rows if int(r["late_min"] or 0) > 0)}

    @staticmethod
    def _salary(pay: Dict[str, Any], counts: Dict[str, Any], advance: int, days_in_month: int, bonus: int = 0) -> Dict[str, Any]:
        """Salary worked out in lines the owner can read: days × rate + OT + bonus − advance. Shop holidays are paid
        days for a monthly salary (a per-day salary pays worked days only)."""
        holiday = int(counts.get("holiday") or 0) if pay["salary_kind"] != "day" else 0
        worked = counts["present"] + counts["half"] * 0.5 + holiday
        if pay["salary_kind"] == "day":
            per_day = int(pay["salary_paise"])
        else:
            per_day = int(round(int(pay["salary_paise"]) / max(days_in_month, 1)))
        base = int(round(per_day * worked))
        ot = int(round(int(pay["ot_rate_paise"]) * counts["ot_min"] / 60))
        net = base + ot + int(bonus) - int(advance)
        return {"per_day_paise": per_day, "days": worked, "base_paise": base, "ot_hours": round(counts["ot_min"] / 60, 1),
                "ot_paise": ot, "advance_paise": int(advance), "bonus_paise": int(bonus), "holiday_days": holiday,
                "net_paise": net, "set": int(pay["salary_paise"]) > 0}

    def team_salary(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "members")
            keys = [r["phone_key"] for r in conn.execute(
                "SELECT phone_key FROM pos_members WHERE business_id = ? AND active = 1 AND role != 'owner'"
                " ORDER BY created_at", (business_id,))]
        people = [self.month(business_id, user, k, month) for k in keys]
        return {"month": people[0]["month"] if people else month, "people": [
            {"ref": p["ref"], "name": p["name"], "role": p["role"], "counts": p["counts"], "pay": p["pay"],
             "salary": p["salary"], "paid": p["paid"]} for p in people]}

    # ------------------------------------------------------------------------------------------------ money (recorded only)
    def advance(self, business_id: str, user: str, ref: str, amount_paise: int, note: str = "") -> Dict[str, Any]:
        from app.services.pos_cashbook import PosCashbook

        if int(amount_paise or 0) <= 0:
            raise PosError(400, "amount", "Write the amount.")
        now = self.clock()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            adv_id = "adv_" + uuid.uuid4().hex[:14]
            conn.execute("INSERT INTO pos_staff_advances (id, business_id, phone_key, amount_paise, local_date, note, by_user,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (adv_id, business_id, key, int(amount_paise), now.strftime("%Y-%m-%d"), str(note or "")[:120], user,
                          now.isoformat()))
            name = (conn.execute("SELECT label FROM pos_members WHERE business_id = ? AND phone_key = ?",
                                 (business_id, key)).fetchone() or {"label": ""})["label"]
        PosCashbook(self.store).add(business_id, user, {"kind": "expense", "amount_paise": int(amount_paise),
                                                        "category": "salary", "note": f"advance {name}".strip(),
                                                        "source": "salary", "ref": adv_id, "client_txn_id": adv_id})
        return {"id": adv_id}

    def bonus(self, business_id: str, user: str, ref: str, amount_paise: int, note: str = "", month: str = "") -> Dict[str, Any]:
        """Extra money for a month (festival bonus, good work): added to that month's salary."""
        if int(amount_paise or 0) <= 0:
            raise PosError(400, "amount", "Write the amount.")
        now = self.clock()
        month = month if re.fullmatch(r"\d{4}-\d{2}", month or "") else now.strftime("%Y-%m")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            bonus_id = "bon_" + uuid.uuid4().hex[:14]
            conn.execute("INSERT INTO pos_staff_bonus (id, business_id, phone_key, month, amount_paise, note, by_user,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (bonus_id, business_id, key, month, int(amount_paise), str(note or "")[:120], user, now.isoformat()))
        return {"id": bonus_id, "month": month}

    def holidays(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            since = (self.clock() - timedelta(days=40)).strftime("%Y-%m-%d")
            return [{"date": r["local_date"], "name": r["name"]} for r in conn.execute(
                "SELECT local_date, name FROM pos_att_holidays WHERE business_id = ? AND local_date >= ? ORDER BY local_date",
                (business_id, since))]

    def set_holiday(self, business_id: str, user: str, day: str, name: str = "", remove: bool = False) -> List[Dict[str, Any]]:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day or ""):
            raise PosError(400, "date", "Choose the day.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            if remove:
                conn.execute("DELETE FROM pos_att_holidays WHERE business_id = ? AND local_date = ?", (business_id, day))
            else:
                conn.execute("INSERT INTO pos_att_holidays (business_id, local_date, name) VALUES (?, ?, ?)"
                             " ON CONFLICT(business_id, local_date) DO UPDATE SET name = excluded.name",
                             (business_id, day, re.sub(r"\s+", " ", str(name or "")).strip()[:40]))
        return self.holidays(business_id, user)

    def pay_salary(self, business_id: str, user: str, ref: str, month: str) -> Dict[str, Any]:
        """Records "salary given" for one month: the net amount (advances already taken off) goes into the cashbook."""
        from app.services.pos_cashbook import PosCashbook

        view = self.month(business_id, user, ref, month)
        if view["paid"]:
            return {"already": True, **view["paid"]}
        net = max(0, int(view["salary"]["net_paise"]))
        now = self.clock()
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            conn.execute("INSERT INTO pos_salary_paid (business_id, phone_key, month, amount_paise, paid_at, by_user)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (business_id, key, view["month"], net, now.isoformat(), user))
        if net > 0:
            entry = PosCashbook(self.store).add(business_id, user, {
                "kind": "expense", "amount_paise": net, "category": "salary",
                "note": f"salary {view['name']} {view['month']}".strip(), "source": "salary",
                "client_txn_id": f"salary-{key}-{view['month']}"})
            with self.store._tx() as conn:
                conn.execute("UPDATE pos_salary_paid SET cashbook_id = ? WHERE business_id = ? AND phone_key = ? AND month = ?",
                             (entry.get("id"), business_id, key, view["month"]))
        return {"amount_paise": net, "paid_at": now.isoformat()}

    # ------------------------------------------------------------------------------------------------ tasks
    def tasks(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            role = self.store._require(conn, business_id, user, "view")
            rows = [dict(r) for r in conn.execute(
                "SELECT * FROM pos_tasks WHERE business_id = ? AND (status = 'open' OR done_at >= ?) ORDER BY created_at DESC"
                " LIMIT 200", (business_id, (self.clock() - timedelta(days=2)).isoformat()))]
            names = {r["phone_key"]: r["label"] or "" for r in conn.execute(
                "SELECT phone_key, label FROM pos_members WHERE business_id = ?", (business_id,))}
            if role not in ("owner", "manager"):
                mine = self._me(conn, business_id, user)["key"]
                rows = [r for r in rows if r["assignee"] == mine]
        now = self.clock().isoformat()
        out = [{"id": r["id"], "title": r["title"], "assignee": r["assignee"][-4:], "assignee_name": names.get(r["assignee"], ""),
                "due_at": r["due_at"], "status": r["status"], "done_at": r["done_at"],
                "late": bool(r["status"] == "open" and r["due_at"] and r["due_at"] < now)} for r in rows]
        return {"tasks": out, "counts": {"open": sum(1 for t in out if t["status"] == "open"),
                                         "done": sum(1 for t in out if t["status"] == "done"),
                                         "late": sum(1 for t in out if t["late"])}}

    def add_task(self, business_id: str, user: str, title: str, ref: str, due_at: str = "") -> Dict[str, Any]:
        title = re.sub(r"\s+", " ", str(title or "")).strip()[:120]
        if not title:
            raise PosError(400, "title", "Write the task.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            key = self._staff_key(conn, business_id, ref)
            task_id = "tk_" + uuid.uuid4().hex[:14]
            conn.execute("INSERT INTO pos_tasks (id, business_id, title, assignee, due_at, created_by, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (task_id, business_id, title, key, str(due_at or "")[:25] or None, user, self.clock().isoformat()))
            member = conn.execute("SELECT app_user_id FROM pos_members WHERE business_id = ? AND phone_key = ?",
                                  (business_id, key)).fetchone()
        if self.notify and member and member["app_user_id"]:
            try:
                self.notify(member["app_user_id"], "కొత్త పని", title, f"/biz/{business_id}/staff/tasks", f"task:{task_id}")
            except Exception:
                pass
        return {"id": task_id}

    def task_done(self, business_id: str, user: str, task_id: str, done: bool = True) -> Dict[str, Any]:
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "view")
            row = conn.execute("SELECT assignee FROM pos_tasks WHERE id = ? AND business_id = ?", (task_id, business_id)).fetchone()
            if not row:
                raise PosError(404, "task", "Task not found.")
            if role not in ("owner", "manager") and row["assignee"] != self._me(conn, business_id, user)["key"]:
                raise PosError(403, "task", "Only the person it is given to can finish it.")
            conn.execute("UPDATE pos_tasks SET status = ?, done_at = ? WHERE id = ?",
                         ("done" if done else "open", self.clock().isoformat() if done else None, task_id))
        return {"ok": True}
