"""Bills after the counter (owner 2026-11-16, "one catalogue, three jobs"): item numbers, how a bill was paid (which app),
sending a bill to the customer, the customer's own bill inbox, the public bill page and the shop's bill history.

Built ON the POS core (``PosStore``), never a copy:

* **Item numbers** -- every active item of a shop gets a small stable number (1, 2, 3 ...) in the order it was added, so a
  cashier can bill "3 two, 1 one". A number is never reused for another item.
* **Pay app** -- a UPI payment may say WHICH app the customer used (PhonePe / Google Pay / Paytm / BHIM / other UPI); stored
  next to the payment (``pos_payments.app``). It is what the cashier chose, never bank-verified.
* **Send** -- the bill goes to the customer's NUMBER: a person who uses ASKODOX gets it in the app ("My bills", push);
  everyone else gets a direct WhatsApp message to that number with a link to a public bill page (``/b/<token>``). The page
  and the inbox show the shop's own UPI pay link for the balance; ASKODOX never holds money.
* **Settle later** -- money received later against one bill is a NEW payment row (``kind = bill_settle``, linked to the
  invoice) plus a ledger credit; the issued invoice row itself is never changed (append-only rule).

Money = integer paise.
"""
from __future__ import annotations

import json
import re
import secrets
import sqlite3
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.account_identity import phone_key
from app.services.pos_store import PAY_METHODS, PosError, PosStore, _clean, _id

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_bill_shares (token TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " invoice_id TEXT NOT NULL, phone_key TEXT NOT NULL DEFAULT '', customer_user TEXT NOT NULL DEFAULT '',"
    " channel TEXT NOT NULL, created_by TEXT NOT NULL, created_at TEXT NOT NULL, seen_at TEXT,"
    " customer_says_paid_at TEXT, customer_says_app TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_pos_bill_shares_user ON pos_bill_shares(customer_user, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_pos_bill_shares_phone ON pos_bill_shares(phone_key, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_pos_bill_shares_inv ON pos_bill_shares(invoice_id)",
]
MIGRATIONS = [
    ("pos_products", "item_no", "INTEGER"),
    ("pos_payments", "app", "TEXT NOT NULL DEFAULT ''"),
]

# What the cashier taps -> (method, app). "other_upi" = any UPI app not named; "upi" alone = UPI, app not said.
PAY_APPS = ("phonepe", "gpay", "paytm", "bhim", "other_upi")
APP_LABELS = {"phonepe": "PhonePe", "gpay": "Google Pay", "paytm": "Paytm", "bhim": "BHIM", "other_upi": "UPI"}
MODE_KEYS = ("cash", "phonepe", "gpay", "paytm", "other_upi", "card", "bank_transfer", "cheque")


def pay_choice(value: Any) -> tuple:
    """'phonepe' -> ('upi', 'phonepe'); 'cash' -> ('cash', ''); unknown -> PosError."""
    v = str(value or "cash").strip().lower().replace(" ", "").replace("_", "")
    v = {"googlepay": "gpay", "gpay": "gpay", "phonepe": "phonepe", "paytm": "paytm", "bhim": "bhim",
         "otherupi": "other_upi", "upi": "upi", "online": "upi", "cash": "cash", "card": "card", "banktransfer": "bank_transfer",
         "cheque": "cheque"}.get(v, v)
    if v in PAY_APPS:
        return "upi", v
    if v in PAY_METHODS:
        return v, ""
    raise PosError(400, "payment", "Choose cash, PhonePe, Google Pay, Paytm, BHIM, other UPI, card, bank or cheque.")


def mode_of(method: str, app: str) -> str:
    """One history bucket per payment: the UPI app when known, else the method ("upi" without an app -> other_upi)."""
    if method == "upi":
        return app if app in PAY_APPS else "other_upi"
    return method


def _digits(value: Any) -> str:
    return re.sub(r"\D", "", str(value or ""))


def whatsapp_number(phone: Any) -> str:
    """10-digit Indian mobile -> 91XXXXXXXXXX; a number given with a country code stays as given."""
    d = _digits(phone)
    if len(d) == 10:
        return "91" + d
    if len(d) == 11 and d.startswith("0"):
        return "91" + d[1:]
    return d


class PosBills:
    def __init__(self, store: PosStore, *,
                 notify: Optional[Callable[[str, str, str, str, str], None]] = None,
                 pay_to: Optional[Callable[[str, int, str, str], List[Dict[str, Any]]]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.pay_to = pay_to or (lambda owner, amount, note, ref: [])
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            for table, column, decl in MIGRATIONS:
                try:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")
                except sqlite3.OperationalError:
                    pass

    # ------------------------------------------------------------------ item numbers
    @staticmethod
    def number_items(conn: sqlite3.Connection, business_id: str) -> None:
        """Gives every item without a number the next free one, oldest item first. Numbers never move or repeat.
        Owner 2026-11-18 ("#55 117) Fish Biryani"): a menu read from a photo kept the PRINTED number in the name; that
        number becomes the item number (when free) and leaves the name, so one item has ONE number everywhere."""
        from app.services.pos_menu_sort import printed_number

        try:
            numbered = conn.execute("SELECT id, name, item_no FROM pos_products WHERE business_id = ? AND name GLOB '[0-9]*'",
                                    (business_id,)).fetchall()
        except sqlite3.OperationalError:
            numbered = []
        for row in numbered:
            name, printed = printed_number(row["name"])
            if printed is None or not name:
                continue
            taken = conn.execute("SELECT 1 FROM pos_products WHERE business_id = ? AND item_no = ? AND id != ?",
                                 (business_id, printed, row["id"])).fetchone()
            conn.execute("UPDATE pos_products SET name = ?, item_no = ? WHERE id = ?",
                         (name, row["item_no"] if taken else printed, row["id"]))
        try:
            missing = conn.execute("SELECT id FROM pos_products WHERE business_id = ? AND item_no IS NULL"
                                   " ORDER BY created_at, rowid", (business_id,)).fetchall()
        except sqlite3.OperationalError:
            return
        if not missing:
            return
        top = conn.execute("SELECT COALESCE(MAX(item_no), 0) AS n FROM pos_products WHERE business_id = ?",
                           (business_id,)).fetchone()["n"]
        for offset, row in enumerate(missing, start=1):
            conn.execute("UPDATE pos_products SET item_no = ? WHERE id = ?", (top + offset, row["id"]))

    def numbers(self, business_id: str) -> Dict[str, int]:
        with self.store._connect() as conn:
            self.number_items(conn, business_id)
            return {r["id"]: r["item_no"] for r in conn.execute(
                "SELECT id, item_no FROM pos_products WHERE business_id = ? AND active = 1", (business_id,))}

    def item_by_number(self, conn: sqlite3.Connection, business_id: str, number: int) -> Optional[sqlite3.Row]:
        self.number_items(conn, business_id)
        return conn.execute("SELECT id, name, price_paise, unit FROM pos_products WHERE business_id = ? AND active = 1"
                            " AND item_no = ?", (business_id, number)).fetchone()

    # ------------------------------------------------------------------ pay app on a bill's payments
    def tag_app(self, invoice_id: str, app: str) -> None:
        if app not in PAY_APPS:
            return
        with self.store._connect() as conn:
            conn.execute("UPDATE pos_payments SET app = ? WHERE invoice_id = ? AND method = 'upi' AND app = ''",
                         (app, invoice_id))

    # ------------------------------------------------------------------ helpers
    def _invoice_row(self, conn: sqlite3.Connection, business_id: str, invoice_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_invoices WHERE id = ? AND business_id = ?", (invoice_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "invoice", "Invoice not found.")
        return row

    @staticmethod
    def _settled(conn: sqlite3.Connection, invoice_id: str) -> int:
        row = conn.execute("SELECT COALESCE(SUM(amount_paise), 0) AS s FROM pos_payments WHERE invoice_id = ?"
                           " AND kind = 'bill_settle'", (invoice_id,)).fetchone()
        return int(row["s"])

    def _due(self, conn: sqlite3.Connection, inv: sqlite3.Row) -> int:
        if inv["status"] != "issued":
            return 0
        return max(0, int(inv["balance_paise"] or 0) - self._settled(conn, inv["id"]))

    def _modes(self, conn: sqlite3.Connection, invoice_id: str) -> List[str]:
        try:
            rows = conn.execute("SELECT method, app FROM pos_payments WHERE invoice_id = ? ORDER BY at", (invoice_id,)).fetchall()
        except sqlite3.OperationalError:
            rows = conn.execute("SELECT method, '' AS app FROM pos_payments WHERE invoice_id = ? ORDER BY at",
                                (invoice_id,)).fetchall()
        return list(dict.fromkeys(mode_of(r["method"], r["app"] or "") for r in rows))

    def _account_user(self, conn: sqlite3.Connection, key: str) -> str:
        """The ASKODOX account of this number, or '' (not on ASKODOX)."""
        if len(key) < 10:
            return ""
        try:
            row = conn.execute("SELECT user_id FROM auth_accounts WHERE phone_key = ?", (key,)).fetchone()
        except sqlite3.OperationalError:
            row = None
        return str(row["user_id"]) if row else ""

    def _public_bill(self, conn: sqlite3.Connection, share: sqlite3.Row) -> Dict[str, Any]:
        inv = self._invoice_row(conn, share["business_id"], share["invoice_id"])
        biz = self.store._business_row(conn, share["business_id"])
        totals = json.loads(inv["totals"])
        lines = [{"name": l["name"], "qty_milli": l["qty_milli"], "unit": l["unit"],
                  "amount_paise": l["total_paise"]}
                 for l in conn.execute("SELECT * FROM pos_invoice_lines WHERE invoice_id = ? ORDER BY line_no", (inv["id"],))]
        due = self._due(conn, inv)
        modes = self._modes(conn, inv["id"])
        out = {"token": share["token"], "business_id": share["business_id"], "shop": biz["name"],
               "invoice_id": inv["id"], "number": inv["number"], "title": inv["document_type"],
               "issued_at": inv["issued_at"], "lines": lines, "total_paise": int(totals.get("grand_total_paise") or 0),
               "paid_paise": int(totals.get("grand_total_paise") or 0) - due, "due_paise": due,
               "status": "cancelled" if inv["status"] != "issued" else ("paid" if due == 0 else "due"),
               "paid_with": [APP_LABELS.get(m, m) for m in modes],
               "customer_says_paid": bool(share["customer_says_paid_at"]), "pay": []}
        out.update(self.paper(conn, inv, biz, due))
        if due > 0:
            out["pay"] = self.pay_to(biz["owner_user_id"], due, f"{biz['name']} bill {inv['number']}"[:60], inv["number"])
        return out

    def paper(self, conn: sqlite3.Connection, inv: sqlite3.Row, biz: sqlite3.Row, due: int) -> Dict[str, Any]:
        """Everything a printed shop bill shows (owner 2026-11-17, like a paper bill): the shop's name, what it sells,
        address, phone, GSTIN or "no GST"; the customer; each line with quantity, rate and amount; discount, GST, round-off;
        how it was paid (cash / online with the app / still due) and the bill's name from that (cash / online / credit)."""
        totals = json.loads(inv["totals"])
        try:
            snap = json.loads(inv["customer_snapshot"] or "{}")
        except ValueError:
            snap = {}
        category = ""
        try:
            prof = conn.execute("SELECT data FROM shop_profiles WHERE business_id = ?", (biz["id"],)).fetchone()
            data = json.loads(prof["data"]) if prof else {}
            category = str(data.get("subcategory") or data.get("category") or "")
            category = category.split(":", 1)[1] if category.startswith("other:") else category
        except (sqlite3.Error, ValueError):
            category = ""
        lines = [{"name": l["name"], "qty_milli": l["qty_milli"], "unit": l["unit"], "rate_paise": l["unit_price_paise"],
                  "discount_paise": l["discount_paise"], "rate_bp": l["rate_bp"], "amount_paise": l["total_paise"]}
                 for l in conn.execute("SELECT * FROM pos_invoice_lines WHERE invoice_id = ? ORDER BY line_no", (inv["id"],))]
        cash = online = 0
        apps: List[str] = []
        try:
            rows = conn.execute("SELECT method, amount_paise, app FROM pos_payments WHERE invoice_id = ?", (inv["id"],)).fetchall()
        except sqlite3.OperationalError:
            rows = conn.execute("SELECT method, amount_paise, '' AS app FROM pos_payments WHERE invoice_id = ?", (inv["id"],)).fetchall()
        for r in rows:
            if r["method"] == "cash":
                cash += int(r["amount_paise"])
            else:
                online += int(r["amount_paise"])
                label = APP_LABELS.get(r["app"] or "", "") or {"card": "Card", "bank_transfer": "Bank"}.get(r["method"], "")
                if label and label not in apps:
                    apps.append(label)
        if due > 0:
            kind = "part" if (cash or online) else "credit"
        else:
            kind = "mixed" if cash and online else ("online" if online else "cash")
        return {
            "shop_address": biz["address"], "shop_phone": biz["phone"], "shop_gstin": biz["gstin"] or "",
            "shop_category": category, "gst": biz["registration_type"] != "unregistered",
            "customer_name": str(snap.get("name") or ""), "customer_phone_last4": str(snap.get("phone") or "")[-4:],
            "paper_lines": lines,
            "gross_paise": int(totals.get("gross_paise") or 0), "discount_paise": int(totals.get("discount_paise") or 0),
            "tax_paise": int(totals.get("tax_paise") or 0), "cgst_paise": int(totals.get("cgst_paise") or 0),
            "sgst_paise": int(totals.get("sgst_paise") or 0), "igst_paise": int(totals.get("igst_paise") or 0),
            "round_off_paise": int(totals.get("round_off_paise") or 0),
            "cash_paise": cash, "online_paise": online, "online_apps": apps, "bill_kind": kind,
            "revised_from": "",
        }

    def paper_for(self, business_id: str, user: str, invoice_id: str) -> Dict[str, Any]:
        """The same paper view for the shop's own screen (after billing): what the customer will see."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "sell")
            inv = self._invoice_row(conn, business_id, invoice_id)
            biz = self.store._business_row(conn, business_id)
            due = self._due(conn, inv)
            totals = json.loads(inv["totals"])
            out = {"business_id": business_id, "shop": biz["name"], "invoice_id": inv["id"], "number": inv["number"],
                   "issued_at": inv["issued_at"], "total_paise": int(totals.get("grand_total_paise") or 0),
                   "due_paise": due, "status": "cancelled" if inv["status"] != "issued" else ("paid" if due == 0 else "due")}
            out.update(self.paper(conn, inv, biz, due))
            return out

    # ------------------------------------------------------------------ send
    def send(self, business_id: str, user: str, invoice_id: str, phone: str, *, base_url: str = "") -> Dict[str, Any]:
        """The bill to the customer's number: in-app when that number uses ASKODOX, else a direct WhatsApp message."""
        key = phone_key(phone)
        if len(key) < 10:
            raise PosError(400, "phone", "Type the customer's 10-digit mobile number.")
        now = self.clock().isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "sell")
            inv = self._invoice_row(conn, business_id, invoice_id)
            biz = self.store._business_row(conn, business_id)
            customer_user = self._account_user(conn, key)
            channel = "askodox" if customer_user else "whatsapp"
            token = secrets.token_urlsafe(9).replace("-", "a").replace("_", "b")
            conn.execute("INSERT INTO pos_bill_shares (token, business_id, invoice_id, phone_key, customer_user, channel,"
                         " created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (token, business_id, invoice_id, key, customer_user, channel, user, now))
            self.store._audit(conn, business_id, user, "bill.send", invoice_id, {"channel": channel}, now)
            total = int(json.loads(inv["totals"]).get("grand_total_paise") or 0)
            due = self._due(conn, inv)
        url = f"{base_url.rstrip('/')}/b/{token}" if base_url else f"/b/{token}"
        rupees = f"₹{total // 100}" if total % 100 == 0 else f"₹{total / 100:.2f}"
        text = (f"{biz['name']} బిల్లు {inv['number']} · {rupees}\n"
                + ("చూడటానికి / కట్టడానికి" if due else "చూడటానికి") + f": {url}")
        if customer_user:
            try:
                self.notify(customer_user, f"{biz['name']} బిల్లు {rupees}",
                            "కట్టాల్సింది ఉంది — Pay నొక్కండి" if due else "బిల్లు వచ్చింది", "/me/bills",
                            f"bill:{token}")
            except Exception:
                pass  # the bill is in their inbox either way
        return {"channel": channel, "token": token, "url": url, "text": text, "whatsapp_to": whatsapp_number(phone),
                "on_askodox": bool(customer_user)}

    def share_to_user(self, business_id: str, invoice_id: str, customer_user: str, actor: str) -> Optional[str]:
        """A bill made for an order the customer placed in the app: it appears in THEIR "My bills" (with Pay) at once."""
        if not customer_user:
            return None
        now = self.clock().isoformat()
        with self.store._connect() as conn:
            inv = self._invoice_row(conn, business_id, invoice_id)
            if conn.execute("SELECT 1 FROM pos_bill_shares WHERE invoice_id = ? AND customer_user = ?",
                            (invoice_id, customer_user)).fetchone():
                return None
            biz = self.store._business_row(conn, business_id)
            token = secrets.token_urlsafe(9).replace("-", "a").replace("_", "b")
            conn.execute("INSERT INTO pos_bill_shares (token, business_id, invoice_id, phone_key, customer_user, channel,"
                         " created_by, created_at) VALUES (?, ?, ?, ?, ?, 'askodox', ?, ?)",
                         (token, business_id, invoice_id, phone_key(customer_user), customer_user, actor, now))
            due = self._due(conn, inv)
            total = int(json.loads(inv["totals"]).get("grand_total_paise") or 0)
        rupees = f"₹{total // 100}" if total % 100 == 0 else f"₹{total / 100:.2f}"
        try:
            self.notify(customer_user, f"{biz['name']} బిల్లు {rupees}",
                        "కట్టాల్సింది ఉంది — Pay నొక్కండి" if due else "బిల్లు వచ్చింది", "/me/bills", f"bill:{token}")
        except Exception:
            pass
        return token

    def due_of(self, invoice_id: str) -> int:
        with self.store._connect() as conn:
            inv = conn.execute("SELECT * FROM pos_invoices WHERE id = ?", (invoice_id,)).fetchone()
            return self._due(conn, inv) if inv else 0

    # ------------------------------------------------------------------ customer side
    def my_bills(self, user: str, limit: int = 60) -> List[Dict[str, Any]]:
        key = phone_key(user)
        with self.store._connect() as conn:
            try:
                row = conn.execute("SELECT phone_key FROM auth_accounts WHERE user_id = ?", (user,)).fetchone()
                if row:
                    key = row["phone_key"]
            except sqlite3.OperationalError:
                pass
            shares = conn.execute(
                "SELECT * FROM pos_bill_shares WHERE customer_user = ? OR (phone_key = ? AND length(phone_key) >= 10)"
                " ORDER BY created_at DESC LIMIT ?", (user, key, max(1, min(limit, 200)))).fetchall()
            out, seen = [], set()
            for s in shares:
                if s["invoice_id"] in seen:
                    continue  # sent twice (a reminder) -> one bill
                seen.add(s["invoice_id"])
                try:
                    out.append(self._public_bill(conn, s))
                except PosError:
                    continue
            now = self.clock().isoformat()
            conn.execute("UPDATE pos_bill_shares SET seen_at = ? WHERE seen_at IS NULL AND (customer_user = ? OR"
                         " (phone_key = ? AND length(phone_key) >= 10))", (now, user, key))
        return out

    def public(self, token: str) -> Optional[Dict[str, Any]]:
        if not re.fullmatch(r"[A-Za-z0-9]{8,20}", token or ""):
            return None
        with self.store._connect() as conn:
            share = conn.execute("SELECT * FROM pos_bill_shares WHERE token = ?", (token,)).fetchone()
            if share is None:
                return None
            try:
                return self._public_bill(conn, share)
            except PosError:
                return None

    def customer_says_paid(self, token: str, app: str = "") -> Dict[str, Any]:
        """The customer tapped "I paid": the SHOP is told to check (nothing is marked paid by this)."""
        bill = self.public(token)
        if bill is None:
            raise PosError(404, "bill", "Bill not found.")
        now = self.clock().isoformat()
        app = app if app in PAY_APPS else ""
        with self.store._connect() as conn:
            first = conn.execute("UPDATE pos_bill_shares SET customer_says_paid_at = ?, customer_says_app = ? WHERE token = ?"
                                 " AND customer_says_paid_at IS NULL", (now, app, token)).rowcount
            owner = self.store._business_row(conn, bill["business_id"])["owner_user_id"]
        if first and bill["due_paise"] > 0:
            due = bill["due_paise"]
            rupees = f"₹{due // 100}" if due % 100 == 0 else f"₹{due / 100:.2f}"
            try:
                self.notify(owner, f"బిల్లు {bill['number']}: కస్టమర్ {rupees} కట్టాను అన్నారు",
                            "మీ UPI లో వచ్చిందో చూసి 'కట్టారు' నొక్కండి", f"/bills/{bill['business_id']}",
                            f"bill-paid:{token}")
            except Exception:
                pass
        return {**bill, "customer_says_paid": True}

    # ------------------------------------------------------------------ shop side
    def settle(self, business_id: str, user: str, invoice_id: str, pay: str, amount_paise: int = 0,
               client_txn_id: str = "") -> Dict[str, Any]:
        """Money received later for this bill (full balance unless an amount is given)."""
        method, app = pay_choice(pay)
        txn = _clean(client_txn_id, 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "collect")
            seen = conn.execute("SELECT id FROM pos_payments WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            inv = self._invoice_row(conn, business_id, invoice_id)
            if seen:
                return {"replayed": True, "invoice_id": invoice_id, "due_paise": self._due(conn, inv)}
            due = self._due(conn, inv)
            if due <= 0:
                raise PosError(409, "paid", "This bill has nothing left to pay.")
            amount = int(amount_paise or due)
            if amount <= 0 or amount > due:
                raise PosError(400, "amount", "Amount must be between ₹0.01 and the balance.")
            at = self.store.clock()
            payment_id = self.store._insert_payment(conn, business_id, invoice_id, inv["customer_id"], method, amount,
                                                    f"bill {inv['number']}", "bill_settle", user, at, txn)
            if app:
                conn.execute("UPDATE pos_payments SET app = ? WHERE id = ?", (app, payment_id))
            if inv["customer_id"]:
                self.store._ledger(conn, business_id, inv["customer_id"], "payment", payment_id, credit=amount, at=at,
                                   note=f"bill {inv['number']} ({mode_of(method, app)})", user=user)
            self.store._audit(conn, business_id, user, "bill.settle", invoice_id,
                              {"amount_paise": amount, "method": method, "app": app}, at.isoformat())
            left = self._due(conn, inv)
        return {"replayed": False, "invoice_id": invoice_id, "payment_id": payment_id, "due_paise": left}

    def history(self, business_id: str, user: str, *, date_from: str = "", date_to: str = "", only_due: bool = False,
                query: str = "", limit: int = 300) -> Dict[str, Any]:
        """Bills with how each was paid, what is still due, and whether it was sent; totals per way of paying."""
        q = re.sub(r"\s+", "", str(query or "")).lower()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            sql = "SELECT * FROM pos_invoices WHERE business_id = ? AND doc_kind = 'invoice'"
            args: List[Any] = [business_id]
            if date_from:
                sql += " AND local_date >= ?"
                args.append(date_from)
            if date_to:
                sql += " AND local_date <= ?"
                args.append(date_to)
            rows = conn.execute(sql + " ORDER BY issued_at DESC LIMIT ?", (*args, max(1, min(limit, 1000)))).fetchall()
            totals = {k: 0 for k in MODE_KEYS}
            totals["due"] = 0
            bills = []
            for inv in rows:
                customer = json.loads(inv["customer_snapshot"] or "{}")
                phone = str(customer.get("phone") or "")
                if not phone and inv["customer_id"]:
                    c = conn.execute("SELECT phone FROM pos_customers WHERE id = ?", (inv["customer_id"],)).fetchone()
                    phone = str(c["phone"] or "") if c else ""
                if q and q not in str(inv["number"]).lower() and q not in _digits(phone):
                    continue
                due = self._due(conn, inv)
                if only_due and due <= 0:
                    continue
                try:
                    pays = conn.execute("SELECT method, app, amount_paise FROM pos_payments WHERE invoice_id = ?",
                                        (inv["id"],)).fetchall()
                except sqlite3.OperationalError:
                    pays = conn.execute("SELECT method, '' AS app, amount_paise FROM pos_payments WHERE invoice_id = ?",
                                        (inv["id"],)).fetchall()
                if inv["status"] == "issued":
                    for p in pays:
                        mode = mode_of(p["method"], p["app"] or "")
                        totals[mode] = totals.get(mode, 0) + int(p["amount_paise"])
                    totals["due"] += due
                share = conn.execute("SELECT channel, seen_at, customer_says_paid_at FROM pos_bill_shares WHERE invoice_id = ?"
                                     " ORDER BY created_at DESC LIMIT 1", (inv["id"],)).fetchone()
                bills.append({
                    "id": inv["id"], "number": inv["number"], "issued_at": inv["issued_at"], "local_date": inv["local_date"],
                    "status": inv["status"], "total_paise": int(json.loads(inv["totals"]).get("grand_total_paise") or 0),
                    "due_paise": due, "modes": list(dict.fromkeys(mode_of(p["method"], p["app"] or "") for p in pays)),
                    "customer_name": customer.get("name") or "", "customer_phone_last4": _digits(phone)[-4:],
                    "sent": share["channel"] if share else "", "seen": bool(share and share["seen_at"]),
                    "customer_says_paid": bool(share and share["customer_says_paid_at"]),
                })
        return {"bills": bills, "totals": totals, "labels": APP_LABELS}
