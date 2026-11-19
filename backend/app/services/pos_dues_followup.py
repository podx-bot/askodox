"""Baaki (credit) follow-up that runs by itself (owner 2026-11-19).

"Who follows up the credit? Not me by hand." For every bill a shop sent to a customer that still has money due:
- the customer gets a reminder in ASKODOX (push -> My bills) -- first after ``FIRST_AFTER_DAYS``, then every
  ``EVERY_DAYS``, at most ``MAX_REMINDERS`` times;
- the customer can answer with a DATE ("I will pay on ...", one tap in My bills). Until that date nothing is sent; the
  shop owner is told the date at once and again on the day ("promised for today");
- a paid / cancelled bill stops by itself (the due is read from the same ledger the bill screen uses).

Only people on ASKODOX get a push (the bill was already sent to others by WhatsApp link when it was made). No call is
placed and no message is sent outside ASKODOX from here. Nothing here moves money.
"""
from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Optional

from app.services.pos_store import IST, PosError

FIRST_AFTER_DAYS = 2
EVERY_DAYS = 3
MAX_REMINDERS = 10
MAX_PROMISE_DAYS = 60

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_due_followups (invoice_id TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " promised_date TEXT NOT NULL DEFAULT '', promised_at TEXT, last_reminded TEXT NOT NULL DEFAULT '',"
    " reminders INTEGER NOT NULL DEFAULT 0, promise_day_told TEXT NOT NULL DEFAULT '')",
]


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


class PosDuesFollowup:
    def __init__(self, store: Any, bills: Any, *, notify: Optional[Callable[[str, str, str, str, str], Any]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.bills = bills
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _today(self) -> str:
        return self.clock().astimezone(IST).date().isoformat()

    def _row(self, conn: sqlite3.Connection, invoice_id: str, business_id: str) -> sqlite3.Row:
        conn.execute("INSERT OR IGNORE INTO pos_due_followups (invoice_id, business_id) VALUES (?, ?)", (invoice_id, business_id))
        return conn.execute("SELECT * FROM pos_due_followups WHERE invoice_id = ?", (invoice_id,)).fetchone()

    # ------------------------------------------------------------------ customer
    def promise(self, user: str, token: str, date: str) -> Dict[str, Any]:
        """The customer's own answer: "I will pay on <date>" (today .. 60 days)."""
        today = self._today()
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(date or "")):
            raise PosError(400, "date", "Choose the date.")
        last = (self.clock().astimezone(IST).date() + timedelta(days=MAX_PROMISE_DAYS)).isoformat()
        if date < today or date > last:
            raise PosError(400, "date", f"Choose a date from today up to {MAX_PROMISE_DAYS} days.")
        mine = {b["token"]: b for b in self.bills.my_bills(user, 200)}
        bill = mine.get(token)
        if bill is None:
            raise PosError(404, "bill", "Bill not found.")
        if int(bill["due_paise"]) <= 0:
            raise PosError(409, "paid", "This bill has nothing due.")
        with self.store._tx() as conn:
            self._row(conn, bill["invoice_id"], bill["business_id"])
            conn.execute("UPDATE pos_due_followups SET promised_date = ?, promised_at = ?, promise_day_told = '' WHERE invoice_id = ?",
                         (date, self.clock().isoformat(), bill["invoice_id"]))
            owner = self.store._business_row(conn, bill["business_id"])["owner_user_id"]
        self.notify(owner, "Baaki: date given / బాకీ: తేదీ చెప్పారు",
                    f"Bill {bill['number']} · {_rupees(int(bill['due_paise']))} · {date}",
                    f"/pos/{bill['business_id']}/invoices", f"due_promise:{bill['invoice_id']}:{date}")
        return {"ok": True, "promised_date": date}

    def promises(self, invoice_ids: list) -> Dict[str, str]:
        """invoice id -> the date the customer gave (for the shop's own lists)."""
        if not invoice_ids:
            return {}
        with self.store._connect() as conn:
            marks = ",".join("?" for _ in invoice_ids)
            return {r["invoice_id"]: r["promised_date"] for r in conn.execute(
                f"SELECT invoice_id, promised_date FROM pos_due_followups WHERE promised_date != '' AND invoice_id IN ({marks})",
                tuple(invoice_ids))}

    # ------------------------------------------------------------------ the job
    def run(self) -> Dict[str, int]:
        today = self._today()
        now = self.clock()
        reminded = told = 0
        with self.store._connect() as conn:
            shares = conn.execute(
                "SELECT s.invoice_id, s.business_id, s.phone_key, s.customer_user, MIN(s.created_at) AS first_at"
                " FROM pos_bill_shares s JOIN pos_invoices i ON i.id = s.invoice_id WHERE i.status = 'issued'"
                " AND i.balance_paise > 0 GROUP BY s.invoice_id").fetchall()
        for s in shares:
            with self.store._tx() as conn:
                inv = conn.execute("SELECT * FROM pos_invoices WHERE id = ?", (s["invoice_id"],)).fetchone()
                due = self.bills._due(conn, inv) if inv else 0
                if due <= 0:
                    continue
                biz = self.store._business_row(conn, s["business_id"])
                row = self._row(conn, s["invoice_id"], s["business_id"])
                customer = s["customer_user"] or self.bills._account_user(conn, s["phone_key"])
                promised = row["promised_date"]
                if promised and promised > today:
                    continue  # the customer gave a date: quiet until then
                if promised == today and row["promise_day_told"] != today:
                    conn.execute("UPDATE pos_due_followups SET promise_day_told = ? WHERE invoice_id = ?", (today, s["invoice_id"]))
                    self.notify(biz["owner_user_id"], "Baaki: promised for today / ఈరోజు ఇస్తానన్నారు",
                                f"Bill {inv['number']} · {_rupees(due)}", f"/pos/{s['business_id']}/invoices",
                                f"due_today_owner:{s['invoice_id']}:{today}")
                    told += 1
                if not customer or row["reminders"] >= MAX_REMINDERS:
                    continue
                since = row["last_reminded"] or ""
                if since:
                    wait_until = (datetime.fromisoformat(since) + timedelta(days=EVERY_DAYS)).isoformat()
                else:
                    wait_until = (datetime.fromisoformat(s["first_at"]) + timedelta(days=FIRST_AFTER_DAYS)).isoformat()
                if promised != today and now.isoformat() < wait_until:
                    continue
                if since[:10] == now.isoformat()[:10]:
                    continue  # never twice on one day
                conn.execute("UPDATE pos_due_followups SET last_reminded = ?, reminders = reminders + 1 WHERE invoice_id = ?",
                             (now.isoformat(), s["invoice_id"]))
                self.notify(customer, f"{biz['name']}: {_rupees(due)} బాకీ / pending",
                            "Pay now, or tell the shop the date you will pay. / ఇప్పుడు కట్టండి, లేదా ఎప్పుడు కడతారో చెప్పండి.",
                            "/me/bills", f"due_reminder:{s['invoice_id']}:{row['reminders'] + 1}")
                reminded += 1
        return {"bills": len(shares), "reminded": reminded, "owner_told": told}
