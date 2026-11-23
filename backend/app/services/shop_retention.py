"""Do shops KEEP using ASKODOX? (owner 2026-11-23, "1 + 4 do")

How many shops still use ASKODOX a week / a month after they joined, how many have gone quiet, how many stopped --
and which ones, so somebody can call them. For the Command Center only: no app screen, nothing shown to shops.

A shop is ACTIVE on a day when real counter work happened in it that day: a bill, a payment taken, a payment-voice
event, or other work (day close, staff attendance, a table order, a purchase bill). Only opening the app is not use.

The raw rows stay in their own tables. Each (shop, day) is also rolled up into ``shop_activity_days``, because
payment events are deleted after 90 days and "did they still use it in month 2?" needs the old days. The roll-up
runs from the periodic job ``shop_activity`` and lazily when the report is read (no cron). Counts only ever grow
(MAX), so rolling the same days again is safe.

Days are India days (UTC + 5:30), like the POS ``local_date``.

Words used in the report:
* joined      = the day the shop was made in ASKODOX;
* active_7 / active_30 = worked on at least one of the last 7 / 30 days (today included);
* quiet       = worked in the last 30 days, but not in the last 7 (going quiet -- call now);
* stopped     = used ASKODOX before, nothing in the last 30 days;
* never_used  = made a shop and never did anything in it;
* week 1 / week 2 / month 2 = worked on days 0-6 / 7-13 / 30-59 after joining. A rate is given only for shops old
  enough for the whole window (7 / 14 / 60 days), otherwise it is None ("too early"), never a guess.
"""
from __future__ import annotations

import re
import sqlite3
import time
from contextlib import closing
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

IST = timedelta(hours=5, minutes=30)
QUIET_DAYS = 7
STOP_DAYS = 30
ROLL_EVERY_SECONDS = 600  # the report re-rolls at most this often
CACHE_SECONDS = 300
LIST_LIMIT = 200
TREND_DAYS = 30
COLUMNS = ("bills", "payments", "alerts", "other")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS shop_activity_days (business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " bills INTEGER NOT NULL DEFAULT 0, payments INTEGER NOT NULL DEFAULT 0, alerts INTEGER NOT NULL DEFAULT 0,"
    " other INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (business_id, day))",
    "CREATE INDEX IF NOT EXISTS idx_shop_activity_day ON shop_activity_days(day, business_id)",
    "CREATE TABLE IF NOT EXISTS shop_activity_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)",
]

# (roll-up column, table, date column, "day" = already an India date / "iso" = a UTC timestamp, extra WHERE).
# A table that this deployment does not have yet (its service makes it on first use) is skipped.
SOURCES: Tuple[Tuple[str, str, str, str, str], ...] = (
    ("bills", "pos_invoices", "local_date", "day", ""),
    ("payments", "pos_payments", "local_date", "day", ""),
    ("alerts", "pos_payment_events", "received_at", "iso", "test = 0"),
    ("other", "pos_day_close", "local_date", "day", ""),
    ("other", "pos_attendance", "local_date", "day", ""),
    ("other", "pos_orders", "created_at", "iso", ""),
    ("other", "pos_purchases", "created_at", "iso", ""),
)

_JOINED = "COALESCE(date(b.created_at, '+330 minutes'), :today)"
_AGE_OF_DAY = f"(julianday(a.day) - julianday({_JOINED}))"
PER_SHOP = f"""
WITH per AS (
  SELECT b.id AS id, b.name AS name, b.phone AS phone, b.address AS address, b.template AS template,
         b.owner_user_id AS owner, {_JOINED} AS joined,
         CAST(julianday(:today) - julianday({_JOINED}) AS INTEGER) AS age,
         MAX(a.day) AS last_day, COUNT(a.day) AS days_used,
         COALESCE(SUM(a.day >= :d7), 0) AS a7,
         COALESCE(SUM(a.day >= :d30), 0) AS a30,
         COALESCE(SUM({_AGE_OF_DAY} <= 6), 0) AS w1,
         COALESCE(SUM({_AGE_OF_DAY} BETWEEN 7 AND 13), 0) AS w2,
         COALESCE(SUM({_AGE_OF_DAY} BETWEEN 30 AND 59), 0) AS m2,
         COALESCE(SUM(CASE WHEN a.day >= :d30 THEN a.bills ELSE 0 END), 0) AS bills30,
         COALESCE(SUM(CASE WHEN a.day >= :d30 THEN a.payments ELSE 0 END), 0) AS payments30,
         COALESCE(SUM(CASE WHEN a.day >= :d30 THEN a.alerts ELSE 0 END), 0) AS alerts30,
         COALESCE(SUM(CASE WHEN a.day >= :d30 THEN a.other ELSE 0 END), 0) AS other30,
         COALESCE(SUM(a.bills), 0) AS bills_all, COALESCE(SUM(a.payments), 0) AS payments_all,
         COALESCE(SUM(a.alerts), 0) AS alerts_all, COALESCE(SUM(a.other), 0) AS other_all
  FROM pos_businesses b LEFT JOIN shop_activity_days a ON a.business_id = b.id
  GROUP BY b.id)
"""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _rate(kept: int, of: int) -> Optional[float]:
    """Percent with one decimal; None when nobody is old enough yet (too early to say)."""
    return round(100.0 * kept / of, 1) if of > 0 else None


def mask_phone(value: Any) -> str:
    """A person's own number is never shown in full in the Command Center: only the last four digits stay."""
    return re.sub(r"\d(?=\d{4})", "•", str(value or ""))


class ShopRetention:
    def __init__(self, db_path: str, *, clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.clock = clock
        self._cache: Dict[bool, Tuple[float, Dict[str, Any]]] = {}
        with closing(sqlite3.connect(db_path)) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    def today(self) -> date:
        return (self.clock().astimezone(timezone.utc) + IST).date()

    @staticmethod
    def _tables(conn: sqlite3.Connection) -> set:
        return {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}

    @staticmethod
    def _meta(conn: sqlite3.Connection, key: str) -> Optional[str]:
        row = conn.execute("SELECT v FROM shop_activity_meta WHERE k = ?", (key,)).fetchone()
        return row[0] if row else None

    @staticmethod
    def _set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
        conn.execute("INSERT INTO shop_activity_meta(k, v) VALUES(?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v",
                     (key, value))

    # ------------------------------------------------------------ roll-up --
    def roll(self) -> Dict[str, Any]:
        """Copy each (shop, day) of work into shop_activity_days. The first run takes all history; later runs take
        the days since the last roll (two days of overlap for bills that sync late from an offline phone)."""
        today = self.today()
        with closing(self._connect()) as conn:
            last = self._meta(conn, "rolled_day")
            try:
                since = date.fromisoformat(last) - timedelta(days=2) if last else date(2000, 1, 1)
            except ValueError:
                since = date(2000, 1, 1)
            since_day = since.isoformat()
            # a UTC timestamp one day before the first India day we want: the exact day is checked again in HAVING
            since_iso = (datetime(since.year, since.month, since.day) - timedelta(days=1)).isoformat()
            tables = self._tables(conn)
            done: List[str] = []
            skipped: List[str] = []
            for column, table, date_col, kind, where in SOURCES:
                if table not in tables:
                    skipped.append(table)
                    continue
                extra = f" AND {where}" if where else ""
                if kind == "day":
                    select = (f"SELECT business_id, {date_col} AS d, COUNT(*) FROM {table}"
                              f" WHERE {date_col} >= ?{extra} GROUP BY business_id, d")
                    params: Tuple[Any, ...] = (since_day,)
                else:
                    select = (f"SELECT business_id, date({date_col}, '+330 minutes') AS d, COUNT(*) FROM {table}"
                              f" WHERE {date_col} >= ?{extra} GROUP BY business_id, d HAVING d IS NOT NULL AND d >= ?")
                    params = (since_iso, since_day)
                try:
                    conn.execute(
                        f"INSERT INTO shop_activity_days (business_id, day, {column}) {select}"
                        f" ON CONFLICT(business_id, day) DO UPDATE SET"
                        f" {column} = MAX(shop_activity_days.{column}, excluded.{column})", params)
                    done.append(table)
                except sqlite3.Error:  # an older shape of that table: the other sources still count
                    skipped.append(table)
            self._set_meta(conn, "rolled_day", today.isoformat())
            self._set_meta(conn, "rolled_at", self.clock().isoformat())
        self._cache.clear()
        return {"since": since_day, "sources": done, "skipped": skipped, "first": last is None}

    def _roll_if_due(self, force: bool) -> None:
        with closing(self._connect()) as conn:
            at = self._meta(conn, "rolled_at")
        try:
            age = (self.clock() - datetime.fromisoformat(at)).total_seconds() if at else None
        except ValueError:
            age = None
        if force or age is None or age >= ROLL_EVERY_SECONDS or age < 0:
            self.roll()

    # ------------------------------------------------------------- report --
    def report(self, *, lists: bool = False, fresh: bool = False) -> Dict[str, Any]:
        """Counts, the join-month table and the daily trend; ``lists`` adds the shops to call (names + contact)."""
        cached = self._cache.get(lists)
        if cached and not fresh and time.monotonic() - cached[0] < CACHE_SECONDS:
            return cached[1]
        self._roll_if_due(fresh)
        today = self.today()
        args = {"today": today.isoformat(), "d7": (today - timedelta(days=QUIET_DAYS - 1)).isoformat(),
                "d30": (today - timedelta(days=STOP_DAYS - 1)).isoformat()}
        with closing(self._connect()) as conn:
            if "pos_businesses" not in self._tables(conn):  # no shop was ever made on this deployment
                out = self._empty(today, lists)
                self._cache[lists] = (time.monotonic(), out)
                return out
            t = conn.execute(PER_SHOP + """
                SELECT COUNT(*) AS shops, SUM(days_used > 0) AS ever_used, SUM(days_used = 0) AS never_used,
                       SUM(a7 > 0) AS active_7, SUM(a30 > 0) AS active_30,
                       SUM(a30 > 0 AND a7 = 0) AS quiet, SUM(days_used > 0 AND a30 = 0) AS stopped,
                       SUM(joined >= :d7) AS new_7, SUM(joined >= :d30) AS new_30,
                       SUM(age >= 7) AS w1_of, SUM(age >= 7 AND w1 > 0) AS w1_kept,
                       SUM(age >= 14) AS w2_of, SUM(age >= 14 AND w2 > 0) AS w2_kept,
                       SUM(age >= 60) AS m2_of, SUM(age >= 60 AND m2 > 0) AS m2_kept,
                       SUM(bills30 > 0) AS use_bills, SUM(payments30 > 0) AS use_payments,
                       SUM(alerts30 > 0) AS use_alerts, SUM(other30 > 0) AS use_other
                FROM per""", args).fetchone()
            n = {k: int(t[k] or 0) for k in t.keys()}
            months = conn.execute(PER_SHOP + """
                SELECT substr(joined, 1, 7) AS month, COUNT(*) AS shops,
                       SUM(age >= 7) AS w1_of, SUM(age >= 7 AND w1 > 0) AS w1_kept,
                       SUM(age >= 14) AS w2_of, SUM(age >= 14 AND w2 > 0) AS w2_kept,
                       SUM(age >= 60) AS m2_of, SUM(age >= 60 AND m2 > 0) AS m2_kept,
                       SUM(a7 > 0) AS active_7
                FROM per GROUP BY month ORDER BY month DESC LIMIT 12""", args).fetchall()
            trend_from = (today - timedelta(days=TREND_DAYS - 1)).isoformat()
            # only shops that still exist are counted (a roll-up row can outlive its shop)
            per_day = {r["day"]: int(r["n"]) for r in conn.execute(
                "SELECT a.day AS day, COUNT(*) AS n FROM shop_activity_days a"
                " JOIN pos_businesses b ON b.id = a.business_id WHERE a.day >= ? AND a.day <= ? GROUP BY a.day",
                (trend_from, today.isoformat()))}
            out: Dict[str, Any] = {
                "as_of": today.isoformat(),
                "rolled_at": self._meta(conn, "rolled_at") or "",
                "rules": {"quiet_days": QUIET_DAYS, "stop_days": STOP_DAYS,
                          "active_means": "bill / payment / payment voice / day close / attendance / order / purchase"},
                "totals": {k: n[k] for k in ("shops", "ever_used", "never_used", "active_7", "active_30", "quiet",
                                               "stopped", "new_7", "new_30")},
                "kept": {
                    "week_1": {"of": n["w1_of"], "kept": n["w1_kept"], "pct": _rate(n["w1_kept"], n["w1_of"])},
                    "week_2": {"of": n["w2_of"], "kept": n["w2_kept"], "pct": _rate(n["w2_kept"], n["w2_of"])},
                    "month_2": {"of": n["m2_of"], "kept": n["m2_kept"], "pct": _rate(n["m2_kept"], n["m2_of"])},
                },
                # which free tools the shops that worked in the last 30 days really use
                "tools_30": {"bills": n["use_bills"], "payments": n["use_payments"], "payment_voice": n["use_alerts"],
                             "other": n["use_other"]},
                "months": [{"month": r["month"], "shops": int(r["shops"] or 0),
                            "week_1": self._cell(r, "w1"), "week_2": self._cell(r, "w2"),
                            "month_2": self._cell(r, "m2"), "active_7": int(r["active_7"] or 0)} for r in months],
                "trend": [{"day": (today - timedelta(days=i)).isoformat(),
                           "active": per_day.get((today - timedelta(days=i)).isoformat(), 0)}
                          for i in range(TREND_DAYS - 1, -1, -1)],
                "lists": None,
            }
            if lists:
                out["lists"] = {
                    "quiet": self._list(conn, args, "a30 > 0 AND a7 = 0", "last_day ASC, name"),
                    "stopped": self._list(conn, args, "days_used > 0 AND a30 = 0", "last_day DESC, name"),
                    "never_used": self._list(conn, args, "days_used = 0", "joined DESC, name"),
                    "limit": LIST_LIMIT,
                }
        self._cache[lists] = (time.monotonic(), out)
        return out

    @staticmethod
    def _cell(row: sqlite3.Row, prefix: str) -> Dict[str, Any]:
        of, kept = int(row[prefix + "_of"] or 0), int(row[prefix + "_kept"] or 0)
        return {"of": of, "kept": kept, "pct": _rate(kept, of)}

    def _list(self, conn: sqlite3.Connection, args: Dict[str, str], where: str, order: str) -> List[Dict[str, Any]]:
        rows = conn.execute(
            PER_SHOP + f"SELECT *, CAST(julianday(:today) - julianday(last_day) AS INTEGER) AS silent FROM per"
                       f" WHERE {where} ORDER BY {order} LIMIT {LIST_LIMIT}", args).fetchall()
        out = []
        for r in rows:
            shop_phone = str(r["phone"] or "").strip()
            out.append({
                "id": r["id"], "name": r["name"], "kind": r["template"], "address": str(r["address"] or "")[:80],
                # the shop's own counter number (it is on its bills); the owner's sign-in number only masked
                "phone": shop_phone, "owner": mask_phone(r["owner"]),
                "joined": r["joined"], "last_day": r["last_day"] or "",
                "silent_days": int(r["silent"]) if r["silent"] is not None else None,
                "days_used": int(r["days_used"] or 0),
                "bills": int(r["bills_all"] or 0), "payments": int(r["payments_all"] or 0),
                "payment_voice": int(r["alerts_all"] or 0), "other": int(r["other_all"] or 0),
            })
        return out

    def _empty(self, today: date, lists: bool) -> Dict[str, Any]:
        zero = {"of": 0, "kept": 0, "pct": None}
        return {"as_of": today.isoformat(), "rolled_at": "",
                "rules": {"quiet_days": QUIET_DAYS, "stop_days": STOP_DAYS,
                          "active_means": "bill / payment / payment voice / day close / attendance / order / purchase"},
                "totals": {k: 0 for k in ("shops", "ever_used", "never_used", "active_7", "active_30", "quiet",
                                          "stopped", "new_7", "new_30")},
                "kept": {"week_1": dict(zero), "week_2": dict(zero), "month_2": dict(zero)},
                "tools_30": {"bills": 0, "payments": 0, "payment_voice": 0, "other": 0},
                "months": [],
                "trend": [{"day": (today - timedelta(days=i)).isoformat(), "active": 0}
                          for i in range(TREND_DAYS - 1, -1, -1)],
                "lists": {"quiet": [], "stopped": [], "never_used": [], "limit": LIST_LIMIT} if lists else None}


def shop_retention(container: Any) -> ShopRetention:
    service = getattr(container, "shop_retention", None)
    if service is None:
        service = ShopRetention(container.settings.database_path)
        try:
            container.shop_retention = service
        except Exception:
            pass
    return service
