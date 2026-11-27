"""Morning brief (owner 2026-11-27, design canvas "కొత్త లుక్" screen 1): when the app opens, at most THREE things the
person should do today, each with ONE button, and a small count of what ASKODOX already did.

The owner's rules:

* nothing new is computed by AI and nothing runs all day -- the brief only READS the engines that exist (baaki
  reminders, low stock, regulars not seen, yesterday's bills, the person's own bills / family list / habits);
* nothing is sent, ordered or paid from here: every button opens the page where the person approves it;
* a part the caller may not see (staff without that tick) is simply absent; a non-member gets the shop's 404;
* every number is a real count -- a part with nothing to do is not shown, a count that cannot be read is left out.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import PosError

IST = timezone(timedelta(hours=5, minutes=30))
MAX_TASKS = 3
# The order is the priority: money owed to the shop first, then the shelf, then customers, then a look back.
SHOP_ORDER = ("dues", "low_stock", "winback", "yesterday")
ME_ORDER = ("my_bills", "family", "habit")


def _now() -> datetime:
    return datetime.now(timezone.utc)


class MorningBrief:
    def __init__(self, db_path: str, *, clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.clock = clock

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def _day(self, back: int = 0):
        return self.clock().astimezone(IST).date() - timedelta(days=back)

    @staticmethod
    def _has(conn: sqlite3.Connection, table: str) -> bool:
        return conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone() is not None

    def _head(self, tasks: List[Dict[str, Any]]) -> Dict[str, Any]:
        now = self.clock().astimezone(IST)
        return {"day": now.date().isoformat(), "weekday": now.weekday(), "tasks": tasks[:MAX_TASKS],
                "more": max(0, len(tasks) - MAX_TASKS), "approve_first": True}

    # ------------------------------------------------------------------ shop --
    def shop(self, store: Any, dues: Any, autos: Any, business_id: str, user: str) -> Dict[str, Any]:
        with store._connect() as conn:
            store._require(conn, business_id, user, "view")  # a non-member: 404, as everywhere
        found: Dict[str, Dict[str, Any]] = {}

        def part(key: str, read: Callable[[], Optional[Dict[str, Any]]]) -> None:
            try:
                task = read()
            except PosError as error:
                if error.status == 404:
                    raise
                return  # not this person's work
            if task:
                found[key] = {"key": key, **task}

        def dues_task() -> Optional[Dict[str, Any]]:
            count = dues.to_remind(business_id, user)
            return {"action": "send", "count": count, "route": f"/pos/{business_id}/dues"} if count else None

        def stock_task() -> Optional[Dict[str, Any]]:
            groups = autos.low_stock(store, business_id, user)["suppliers"]
            lines = [line for group in groups for line in group["lines"]]
            if not lines:
                return None
            return {"action": "approve", "count": len(lines), "name": lines[0]["name"],
                    "route": f"/pos/{business_id}/automations"}

        def winback_task() -> Optional[Dict[str, Any]]:
            data = autos.winback(store, business_id, user)
            people = data["people"]
            if not people:
                return None
            return {"action": "send", "count": len(people), "days": data["days"],
                    "route": f"/pos/{business_id}/automations"}

        yesterday = self._day(1).isoformat()

        def yesterday_task() -> Optional[Dict[str, Any]]:
            with store._connect() as conn:
                store._require(conn, business_id, user, "reports")
                rows = conn.execute("SELECT totals FROM pos_invoices WHERE business_id = ? AND local_date = ? AND"
                                    " doc_kind = 'invoice' AND status != 'cancelled'", (business_id, yesterday)).fetchall()
            if not rows:
                return None
            total = 0
            for row in rows:
                try:
                    totals = json.loads(row["totals"] or "{}")
                    total += int(totals.get("grand_total_paise") or totals.get("total_paise") or 0)
                except (TypeError, ValueError):
                    continue
            return {"action": "view", "count": len(rows), "amount_paise": total, "date": yesterday,
                    "route": f"/biz/{business_id}/reports/day?date={yesterday}"}

        part("dues", dues_task)
        part("low_stock", stock_task)
        part("winback", winback_task)
        part("yesterday", yesterday_task)
        out = self._head([found[key] for key in SHOP_ORDER if key in found])
        out["scope"] = "shop"
        out["business_id"] = business_id
        handled = self._shop_handled(store, business_id, user, yesterday)
        if handled is not None:
            out["handled"] = handled
        return out

    def _shop_handled(self, store: Any, business_id: str, user: str, day: str) -> Optional[Dict[str, Any]]:
        """Yesterday's real counts, for a person who may read the shop's reports. A table that is not there yet is
        left out (never shown as 0 work done)."""
        start = datetime.fromisoformat(day).replace(tzinfo=IST)
        lo, hi = start.astimezone(timezone.utc).isoformat(), (start + timedelta(days=1)).astimezone(timezone.utc).isoformat()
        try:
            with store._connect() as conn:
                store._require(conn, business_id, user, "reports")
                out: Dict[str, Any] = {"day": day, "bills": int(conn.execute(
                    "SELECT COUNT(*) FROM pos_invoices WHERE business_id = ? AND local_date = ? AND doc_kind = 'invoice'"
                    " AND status != 'cancelled'", (business_id, day)).fetchone()[0])}
                if self._has(conn, "pos_due_followups"):
                    try:
                        out["reminders"] = int(conn.execute(
                            "SELECT COUNT(*) FROM pos_due_followups WHERE business_id = ? AND (owner_sent_day = ? OR"
                            " auto_sent_day = ?)", (business_id, day, day)).fetchone()[0])
                    except sqlite3.OperationalError:
                        pass
                if self._has(conn, "pos_payment_events"):
                    out["payments"] = int(conn.execute(
                        "SELECT COUNT(*) FROM pos_payment_events WHERE business_id = ? AND test = 0 AND status IN"
                        " ('provider_verified', 'notification_unverified') AND received_at >= ? AND received_at < ?",
                        (business_id, lo, hi)).fetchone()[0])
                return out
        except PosError as error:
            if error.status == 404:
                raise
            return None

    # ---------------------------------------------------------------- person --
    def me(self, bills: Any, autos: Any, user: str) -> Dict[str, Any]:
        """The person's own side. Read only: a bill is not marked seen and no list is made here."""
        found: Dict[str, Dict[str, Any]] = {}
        with closing(self._connect()) as conn:
            if self._has(conn, "pos_bill_shares"):
                key = ""
                try:
                    row = conn.execute("SELECT phone_key FROM auth_accounts WHERE user_id = ?", (user,)).fetchone()
                    key = row["phone_key"] if row else ""
                except sqlite3.OperationalError:
                    pass
                invoices = {r["invoice_id"] for r in conn.execute(
                    "SELECT invoice_id FROM pos_bill_shares WHERE customer_user = ? OR (phone_key = ? AND"
                    " length(phone_key) >= 10) ORDER BY created_at DESC LIMIT 200", (user, key))}
            else:
                invoices = set()
            open_items = 0
            if self._has(conn, "family_list_members"):
                open_items = int(conn.execute(
                    "SELECT COUNT(*) FROM family_list_items i JOIN family_list_members m ON m.list_id = i.list_id WHERE"
                    " m.user_id = ? AND i.state = 'open'", (user,)).fetchone()[0])
        unpaid, amount = 0, 0
        for invoice_id in invoices:
            try:
                due = int(bills.due_of(invoice_id))
            except (PosError, TypeError, ValueError):
                continue
            if due > 0:
                unpaid += 1
                amount += due
        if unpaid:
            found["my_bills"] = {"key": "my_bills", "action": "view", "count": unpaid, "amount_paise": amount,
                                 "route": "/me/bills"}
        if open_items:
            found["family"] = {"key": "family", "action": "view", "count": open_items, "route": "/me/family-list"}
        try:
            cards = autos.habit(user)
        except sqlite3.OperationalError:
            cards = []
        if cards:
            found["habit"] = {"key": "habit", "action": "view", "count": len(cards),
                              "name": cards[0]["order"]["business_name"], "route": "/mode"}
        out = self._head([found[key] for key in ME_ORDER if key in found])
        out["scope"] = "me"
        return out
