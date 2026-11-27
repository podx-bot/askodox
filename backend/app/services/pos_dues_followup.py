"""Baaki (credit) follow-up that runs by itself (owner 2026-11-19, reminder days 2026-11-20).

Owner 2026-11-20: every baaki bill has a PAY DATE -- the date chosen when the bill was made (quick bill: one tap,
"1 week" already picked), changed by the shop or given by the customer ("I will pay on"); a bill without one gets
``DEFAULT_DAYS`` after the bill by itself. From ``REMIND_DAYS_BEFORE`` days before that date up to the date, ONCE a
day: the customer gets an ASKODOX push (when on ASKODOX), and the owner gets ONE morning push "today N people to
remind" -> the "Baaki reminders" screen, where each row is ONE tap to WhatsApp (message + pay link already written,
the owner's own WhatsApp -- free, no Meta setup). A changed date starts the days again; a paid bill stops. After the
date the customer is not reminded any more; the owner sees the bill as overdue with "new date".


"Who follows up the credit? Not me by hand." For every bill a shop sent to a customer that still has money due:
- the customer gets a reminder in ASKODOX (push -> My bills) -- first after ``FIRST_AFTER_DAYS``, then every
  ``EVERY_DAYS``, at most ``MAX_REMINDERS`` times;
- the customer can answer with a DATE ("I will pay on ...", one tap in My bills). Until that date nothing is sent; the
  shop owner is told the date at once and again on the day ("promised for today");
- a paid / cancelled bill stops by itself (the due is read from the same ledger the bill screen uses).

Only people on ASKODOX get a push (the bill was already sent to others by WhatsApp link when it was made). No call is
placed. Nothing here moves money.

AUTOMATIC WHATSAPP (owner 2026-11-25, "the reminder should go by itself"): a customer who is NOT on ASKODOX can get the
same once-a-day reminder from ASKODOX's own WhatsApp number, without the owner tapping -- only when ALL of these hold:
staff turned it on (setting ``dues.auto_whatsapp``), an approved UTILITY template is configured (``whatsapp_cloud``
``dues_template_name``, five body values: customer, shop, amount, pay date, bill link), and the SHOP OWNER switched it
on for his shop. At most ``dues.auto_whatsapp_daily_per_shop`` a day per shop; a failed send leaves the bill in the
owner's one-tap list (never lost, never sent twice). Baaki is free for ever (shop_free_core): no credits here.
"""
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

from app.services import shop_messages
from app.services.pos_store import IST, PosError

FIRST_AFTER_DAYS = 2
EVERY_DAYS = 3
MAX_REMINDERS = 10
MAX_PROMISE_DAYS = 60
REMIND_DAYS_BEFORE = 3
DEFAULT_DAYS = 7
LIST_LIMIT = 150

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_due_followups (invoice_id TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " promised_date TEXT NOT NULL DEFAULT '', promised_at TEXT, last_reminded TEXT NOT NULL DEFAULT '',"
    " reminders INTEGER NOT NULL DEFAULT 0, promise_day_told TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS pos_due_owner_days (business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " PRIMARY KEY (business_id, day))",
    "CREATE TABLE IF NOT EXISTS pos_due_settings (business_id TEXT PRIMARY KEY, auto_whatsapp INTEGER NOT NULL DEFAULT 0,"
    " updated_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS pos_due_auto_days (business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " sent INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (business_id, day))",
]
MIGRATIONS = [
    ("pos_due_followups", "set_by", "TEXT NOT NULL DEFAULT ''"),
    ("pos_due_followups", "owner_sent_day", "TEXT NOT NULL DEFAULT ''"),
    ("pos_due_followups", "auto_sent_day", "TEXT NOT NULL DEFAULT ''"),
]


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


class PosDuesFollowup:
    def __init__(self, store: Any, bills: Any, *, notify: Optional[Callable[[str, str, str, str, str], Any]] = None,
                 clock: Optional[Callable[[], datetime]] = None,
                 whatsapp: Optional[Callable[[str, List[str]], Tuple[bool, str]]] = None,
                 auto: Optional[Callable[[], Dict[str, Any]]] = None, base_url: str = "",
                 credits: Any = None) -> None:
        self.store = store
        self.bills = bills
        self.notify = notify or (lambda user, title, body, route, key: None)
        # whatsapp(phone, [customer, shop, amount, date, link]) -> (ok, error); auto() -> {"enabled", "daily"}.
        self.whatsapp = whatsapp
        self.auto = auto or (lambda: {"enabled": False, "daily": 0})
        self.base_url = base_url
        # AI Credits (owner 2026-11-27): an automatic send is one paid ``shop_message`` from the SHOP OWNER's credits.
        self.credits = credits
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            for table, column, decl in MIGRATIONS:
                try:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")
                except sqlite3.OperationalError:
                    pass

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
            conn.execute("UPDATE pos_due_followups SET promised_date = ?, promised_at = ?, promise_day_told = '',"
                         " set_by = 'customer', last_reminded = '', owner_sent_day = '' WHERE invoice_id = ?",
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

    # ------------------------------------------------------------------ shop side (owner 2026-11-20)
    def _pay_date(self, inv: sqlite3.Row, row: Optional[sqlite3.Row]) -> str:
        """The bill's pay date: the one set (shop or customer), else DEFAULT_DAYS after the bill."""
        if row is not None and row["promised_date"]:
            return row["promised_date"]
        try:
            day = datetime.fromisoformat(str(inv["local_date"])[:10]).date()
        except ValueError:
            day = self.clock().astimezone(IST).date()
        return (day + timedelta(days=DEFAULT_DAYS)).isoformat()

    def _days_left(self, date: str) -> int:
        today = self.clock().astimezone(IST).date()
        try:
            return (datetime.fromisoformat(date).date() - today).days
        except ValueError:
            return 0

    def set_date(self, business_id: str, user: str, invoice_id: str, date: str) -> Dict[str, Any]:
        """The shop sets / changes the pay date of a baaki bill: the reminder days start again from the new date."""
        today = self._today()
        date = str(date or "")[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            raise PosError(400, "date", "Choose the date.")
        last = (self.clock().astimezone(IST).date() + timedelta(days=MAX_PROMISE_DAYS * 3)).isoformat()
        if date < today or date > last:
            raise PosError(400, "date", "Choose a date from today.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            inv = conn.execute("SELECT * FROM pos_invoices WHERE id = ? AND business_id = ?", (invoice_id, business_id)).fetchone()
            if inv is None:
                raise PosError(404, "invoice", "Bill not found.")
            self._row(conn, invoice_id, business_id)
            conn.execute("UPDATE pos_due_followups SET promised_date = ?, promised_at = ?, set_by = 'shop',"
                         " promise_day_told = '', last_reminded = '', owner_sent_day = '' WHERE invoice_id = ?",
                         (date, self.clock().isoformat(), invoice_id))
        return {"ok": True, "invoice_id": invoice_id, "pay_date": date, "days_left": self._days_left(date)}

    # ------------------------------------------------------------------ automatic WhatsApp (the shop's own switch)
    def _auto_available(self) -> bool:
        try:
            return self.whatsapp is not None and bool(self.auto().get("enabled"))
        except Exception:
            return False

    def _auto_on(self, conn: sqlite3.Connection, business_id: str) -> bool:
        row = conn.execute("SELECT auto_whatsapp FROM pos_due_settings WHERE business_id = ?", (business_id,)).fetchone()
        return bool(row is not None and row["auto_whatsapp"])

    def set_auto(self, business_id: str, user: str, on: bool) -> Dict[str, Any]:
        """Only the shop's OWNER decides that ASKODOX may message his customers by itself."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            if self.store._business_row(conn, business_id)["owner_user_id"] != user:
                raise PosError(403, "owner_only", "Only the shop owner can change this.")
            if on and not self._auto_available():
                raise PosError(409, "auto_unavailable", "Automatic WhatsApp reminders are not available yet.")
            conn.execute(
                "INSERT INTO pos_due_settings (business_id, auto_whatsapp, updated_by, updated_at) VALUES (?, ?, ?, ?)"
                " ON CONFLICT(business_id) DO UPDATE SET auto_whatsapp = excluded.auto_whatsapp,"
                " updated_by = excluded.updated_by, updated_at = excluded.updated_at",
                (business_id, 1 if on else 0, user, self.clock().isoformat()))
        return {"available": self._auto_available(), "on": bool(on)}

    def _phone_of(self, conn: sqlite3.Connection, inv: sqlite3.Row) -> str:
        if inv["customer_id"]:
            c = conn.execute("SELECT phone FROM pos_customers WHERE id = ?", (inv["customer_id"],)).fetchone()
            if c is not None and c["phone"]:
                return str(c["phone"])
        s = conn.execute("SELECT phone_key FROM pos_bill_shares WHERE invoice_id = ? AND phone_key != ''"
                         " ORDER BY created_at DESC LIMIT 1", (inv["id"],)).fetchone()
        return str(s["phone_key"]) if s is not None else ""

    def _pay_link(self, conn: sqlite3.Connection, inv: sqlite3.Row, phone: str, actor: str, base_url: str) -> str:
        """The bill's own public page (see / pay); one link per bill, made the first time it is needed."""
        import secrets

        from app.services.account_identity import phone_key

        share = conn.execute("SELECT token FROM pos_bill_shares WHERE invoice_id = ? ORDER BY created_at LIMIT 1",
                             (inv["id"],)).fetchone()
        if share is not None:
            token = share["token"]
        else:
            token = secrets.token_urlsafe(9).replace("-", "a").replace("_", "b")
            conn.execute("INSERT INTO pos_bill_shares (token, business_id, invoice_id, phone_key, customer_user, channel,"
                         " created_by, created_at) VALUES (?, ?, ?, ?, '', 'reminder', ?, ?)",
                         (token, inv["business_id"], inv["id"], phone_key(phone) if phone else "", actor,
                          self.clock().isoformat()))
        return f"{base_url.rstrip('/')}/b/{token}" if base_url else f"/b/{token}"

    def reminders(self, business_id: str, user: str, *, base_url: str = "") -> Dict[str, Any]:
        """The owner's "Baaki reminders" list: to remind today (3 days before .. the date), overdue, and later."""
        from app.services.pos_bills import whatsapp_number

        today = self._today()
        rows: list = []
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            biz = self.store._business_row(conn, business_id)
            auto = {"available": self._auto_available(), "on": self._auto_on(conn, business_id),
                    "owner": biz["owner_user_id"] == user,
                    # ONE price per automatic message in paise (0 = free right now); the owner's own manual send is free.
                    "price_paise": shop_messages.price(self.credits)}
            invoices = conn.execute(
                "SELECT * FROM pos_invoices WHERE business_id = ? AND status = 'issued' AND balance_paise > 0"
                " ORDER BY issued_at DESC LIMIT 600", (business_id,)).fetchall()
            for inv in invoices:
                due = self.bills._due(conn, inv)
                if due <= 0:
                    continue
                row = conn.execute("SELECT * FROM pos_due_followups WHERE invoice_id = ?", (inv["id"],)).fetchone()
                date = self._pay_date(inv, row)
                left = self._days_left(date)
                state = "overdue" if left < 0 else "remind" if left <= REMIND_DAYS_BEFORE else "later"
                try:
                    name = json.loads(inv["customer_snapshot"] or "{}").get("name") or ""
                except (TypeError, ValueError):
                    name = ""
                phone = self._phone_of(conn, inv)
                item: Dict[str, Any] = {
                    "invoice_id": inv["id"], "number": inv["number"], "customer": name, "phone": phone,
                    "due_paise": due, "pay_date": date, "days_left": left, "state": state,
                    "date_by": (row["set_by"] if row is not None and row["promised_date"] else "") or "auto",
                    "sent_today": bool(row is not None and row["owner_sent_day"] == today),
                    "sent_auto": bool(row is not None and row["auto_sent_day"] == today),
                    "whatsapp_to": whatsapp_number(phone) if phone else "",
                }
                if state == "remind" and phone:
                    link = self._pay_link(conn, inv, phone, user, base_url)
                    when = ("ఈరోజు" if left == 0 else "రేపు" if left == 1 else f"{left} రోజుల్లో")
                    item["text"] = (f"నమస్తే {name},\n{biz['name']} లో మీ బాకీ {_rupees(due)} ({inv['number']}) "
                                    f"{when} ({date}) కట్టాలి.\nచూడటానికి / కట్టడానికి: {link}\n"
                                    f"Reminder from {biz['name']}: {_rupees(due)} due on {date}.")
                rows.append(item)
        order = {"remind": 0, "overdue": 1, "later": 2}
        rows.sort(key=lambda r: (order[r["state"]], r["pay_date"]))
        rows = rows[:LIST_LIMIT]
        return {"today": today, "remind_days_before": REMIND_DAYS_BEFORE, "items": rows, "auto": auto,
                "to_send": sum(1 for r in rows if r["state"] == "remind" and not r["sent_today"])}

    def mark_sent(self, business_id: str, user: str, invoice_id: str) -> Dict[str, Any]:
        """The owner sent today's WhatsApp reminder for this bill (it leaves today's list until tomorrow)."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            if conn.execute("SELECT 1 FROM pos_invoices WHERE id = ? AND business_id = ?", (invoice_id, business_id)).fetchone() is None:
                raise PosError(404, "invoice", "Bill not found.")
            self._row(conn, invoice_id, business_id)
            conn.execute("UPDATE pos_due_followups SET owner_sent_day = ? WHERE invoice_id = ?", (self._today(), invoice_id))
        return {"ok": True}

    # ------------------------------------------------------------------ the job
    def run(self) -> Dict[str, int]:
        """Once a day is enough (it may run more often: every send is once per bill per day)."""
        today = self._today()
        now = self.clock()
        reminded = told = owners = auto_sent = 0
        auto_ok = self._auto_available()
        daily = int(self.auto().get("daily") or 0) if auto_ok else 0
        waiting: List[Dict[str, Any]] = []
        with self.store._connect() as conn:
            invoices = conn.execute(
                "SELECT * FROM pos_invoices WHERE status = 'issued' AND balance_paise > 0 ORDER BY issued_at DESC LIMIT 5000").fetchall()
        to_send: Dict[str, int] = {}
        for inv in invoices:
            with self.store._tx() as conn:
                due = self.bills._due(conn, inv)
                if due <= 0:
                    continue
                biz = self.store._business_row(conn, inv["business_id"])
                row = self._row(conn, inv["id"], inv["business_id"])
                share = conn.execute("SELECT phone_key, customer_user FROM pos_bill_shares WHERE invoice_id = ?"
                                     " ORDER BY (customer_user != '') DESC, created_at LIMIT 1", (inv["id"],)).fetchone()
                from app.services.account_identity import phone_key

                phone = self._phone_of(conn, inv)
                customer = (share["customer_user"] if share is not None and share["customer_user"] else "") or \
                    self.bills._account_user(conn, phone_key(phone) if phone else "")
                date = self._pay_date(inv, row)
                left = self._days_left(date)
                if left < 0 or left > REMIND_DAYS_BEFORE:
                    continue  # reminders run only from REMIND_DAYS_BEFORE days before up to the pay date
                if row["owner_sent_day"] != today and phone:
                    item: Dict[str, Any] = {"business_id": inv["business_id"], "invoice_id": inv["id"], "phone": phone}
                    if auto_ok and not customer and self._auto_on(conn, inv["business_id"]):
                        try:
                            name = json.loads(inv["customer_snapshot"] or "{}").get("name") or ""
                        except (TypeError, ValueError):
                            name = ""
                        item["values"] = [name or "కస్టమర్", str(biz["name"]), _rupees(due), date,
                                          self._pay_link(conn, inv, phone, "auto", self.base_url)]
                    waiting.append(item)
                if left == 0 and row["promised_date"] and row["promise_day_told"] != today:
                    conn.execute("UPDATE pos_due_followups SET promise_day_told = ? WHERE invoice_id = ?", (today, inv["id"]))
                    told += 1
                if not customer or (row["last_reminded"] or "")[:10] == now.astimezone(IST).date().isoformat():
                    continue  # never twice on one day
                conn.execute("UPDATE pos_due_followups SET last_reminded = ?, reminders = reminders + 1 WHERE invoice_id = ?",
                             (now.astimezone(IST).isoformat(), inv["id"]))
                when = "today / ఈరోజు" if left == 0 else f"{date}"
                self.notify(customer, f"{biz['name']}: {_rupees(due)} బాకీ / pending",
                            f"Pay by {when}. Tap to pay, or tell the shop another date. / {when} కట్టాలి. ఇప్పుడు కట్టండి, లేదా వేరే తేదీ చెప్పండి.",
                            "/me/bills", f"due_reminder:{inv['id']}:{today}")
                reminded += 1
        # Outside any transaction: a slow provider never holds the shop's database.
        for item in waiting:
            business_id = item["business_id"]
            if "values" in item and self._auto_send(business_id, item, today, daily):
                auto_sent += 1
                continue
            to_send[business_id] = to_send.get(business_id, 0) + 1
        for business_id, count in to_send.items():
            with self.store._tx() as conn:
                if conn.execute("SELECT 1 FROM pos_due_owner_days WHERE business_id = ? AND day = ?",
                                (business_id, today)).fetchone():
                    continue
                conn.execute("INSERT INTO pos_due_owner_days (business_id, day) VALUES (?, ?)", (business_id, today))
                owner = self.store._business_row(conn, business_id)["owner_user_id"]
            self.notify(owner, f"బాకీ: ఈరోజు {count} మందికి గుర్తు చేయాలి / {count} baaki reminders today",
                        "ఒక్కో పేరు పక్కన WhatsApp నొక్కండి — మెసేజ్ రెడీగా ఉంది. / One tap each on WhatsApp — the message is ready.",
                        f"/pos/{business_id}/dues", f"due_owner:{business_id}:{today}")
            owners += 1
        return {"bills": len(invoices), "reminded": reminded, "owner_told": told, "owners": owners,
                "auto_whatsapp": auto_sent}

    def _auto_send(self, business_id: str, item: Dict[str, Any], today: str, daily: int) -> bool:
        """One automatic WhatsApp reminder; True only when the provider took it (then the bill leaves today's list)."""
        with self.store._tx() as conn:
            row = conn.execute("SELECT sent FROM pos_due_auto_days WHERE business_id = ? AND day = ?",
                               (business_id, today)).fetchone()
            if daily <= 0 or (row is not None and row["sent"] >= daily):
                return False
            owner = str(self.store._business_row(conn, business_id)["owner_user_id"] or "")
        ref = f"shopmsg:dues:{item['invoice_id']}:{today}"
        if not shop_messages.charge(self.credits, owner, ref):
            return False  # too few credits: nothing is sent, the bill stays in the owner's own one-tap list
        try:
            ok, error = self.whatsapp(item["phone"], item["values"])  # type: ignore[misc]
        except Exception as problem:  # a provider fault leaves the bill with the owner
            ok, error = False, type(problem).__name__
        if not ok:
            shop_messages.give_back(self.credits, owner, ref)
            print(f"ASKODOX DUES AUTO failed shop={business_id} bill={item['invoice_id']} error={str(error)[:120]}", flush=True)
            return False
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_due_followups SET owner_sent_day = ?, auto_sent_day = ? WHERE invoice_id = ?",
                         (today, today, item["invoice_id"]))
            conn.execute("INSERT INTO pos_due_auto_days (business_id, day, sent) VALUES (?, ?, 1)"
                         " ON CONFLICT(business_id, day) DO UPDATE SET sent = sent + 1", (business_id, today))
        return True


def auto_whatsapp(container: Any) -> Tuple[Optional[Callable[[str, List[str]], Tuple[bool, str]]], Callable[[], Dict[str, Any]], str]:
    """(sender, state, public base url) for the automatic WhatsApp reminder; the sender is None until the
    WhatsApp Cloud credentials AND the approved baaki template are configured."""
    from app.services import comms, platform_settings
    from app.services.otp_delivery import _registry

    def state() -> Dict[str, Any]:
        return {"enabled": platform_settings.get("dues.auto_whatsapp") >= 1,
                "daily": int(platform_settings.get("dues.auto_whatsapp_daily_per_shop"))}

    base = str(getattr(getattr(container, "settings", None), "public_base_url", "") or "").rstrip("/")
    reg = _registry(container)
    try:
        template = reg.config_value("whatsapp_cloud", "dues_template_name") if reg is not None else ""
        ready = bool(template and reg.config_value("whatsapp_cloud", "phone_number_id")
                     and reg.secret("whatsapp_cloud", "access_token"))
    except Exception:
        template, ready = "", False
    if not ready:
        return None, state, base
    http = getattr(container, "comms_http", None) or comms.default_http

    def send(phone: str, values: List[str]) -> Tuple[bool, str]:
        from app.services.pos_bills import whatsapp_number

        ok, _mid, error = comms.send_whatsapp_named_template(reg, http, whatsapp_number(phone), template, values)
        return ok, error

    return send, state, base
