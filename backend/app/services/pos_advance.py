"""ASKODOX POS -- shop advance (store credit) that only the CUSTOMER can spend.

What it is: a record, kept by ASKODOX, of money a customer paid a shop in
advance. The money itself is with the SHOP (cash / UPI the shop received);
ASKODOX never holds, moves or guarantees it. Usable only at that one shop,
never paid out as cash except a refund the shop gives back. (A closed-system
prepaid record; ASKODOX is not a wallet, bank or payment company.)

What ASKODOX enforces:
  * The owner turns it on once, accepting the terms (TERMS_VERSION).
  * Every change waits for the customer's own approval in the ASKODOX app
    (the signed-in number must be the customer's number): a deposit counts
    only after the customer confirms they paid it; a deduction (paying a bill
    from the advance) or a refund only after the customer approves it. The
    shop can never lower the balance by itself.
  * Entries are append-only (pending -> approved / rejected / withdrawn /
    expired); nothing is edited or deleted.
  * The balance never goes below zero or above the shop's limit
    (default Rs 2,000, never above HARD_MAX_PAISE).
  * Paying a bill from the advance = a customer-approved collection against
    the customer's dues (method "advance"); it can never exceed what is due.
"""
from __future__ import annotations

import sqlite3
from datetime import timedelta
from typing import Any, Dict, Optional

from app.services.account_identity import phone_key
from app.services.pos_store import PAY_METHODS, PosError, PosStore, _clean, _id

TERMS_VERSION = "2026-10-24"
DEFAULT_MAX_PAISE = 200_000      # Rs 2,000
HARD_MAX_PAISE = 1_000_000       # Rs 10,000 -- ASKODOX's own cap per customer per shop
EXPIRY = {"deposit": timedelta(days=7), "redeem": timedelta(minutes=15), "refund": timedelta(days=1)}

TERMS = {
    "en": ("ASKODOX only keeps a record of this advance. The money is with the shop, not with ASKODOX or any bank. "
           "ASKODOX does not hold, guarantee, insure or refund this money and is not responsible for it. It is not a "
           "wallet or bank account and earns no interest. It can be used only at this shop, and only when you approve "
           "each use in your ASKODOX app. Give an advance only to a shop you trust."),
    "te": ("ఈ అడ్వాన్స్‌కి ASKODOX కేవలం రికార్డు మాత్రమే ఉంచుతుంది. డబ్బు షాప్ దగ్గర ఉంటుంది — ASKODOX దగ్గర గానీ, ఏ బ్యాంక్ "
           "దగ్గర గానీ కాదు. ఈ డబ్బుకి ASKODOX కి ఏ సంబంధం లేదు: దాన్ని ఉంచదు, హామీ ఇవ్వదు, బీమా లేదు, తిరిగి ఇవ్వదు, బాధ్యత "
           "వహించదు. ఇది వాలెట్ లేదా బ్యాంక్ ఖాతా కాదు, వడ్డీ రాదు. ఈ షాప్‌లో మాత్రమే, మీరు మీ ASKODOX యాప్‌లో ప్రతిసారీ "
           "ఆమోదిస్తేనే వాడబడుతుంది. మీరు నమ్మే షాప్‌కి మాత్రమే అడ్వాన్స్ ఇవ్వండి."),
}

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_advance_settings (business_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL,"
    " max_balance_paise INTEGER NOT NULL, terms_version TEXT NOT NULL, accepted_by TEXT NOT NULL,"
    " accepted_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_advance_entries (id TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " customer_id TEXT NOT NULL, kind TEXT NOT NULL, amount_paise INTEGER NOT NULL, method TEXT,"
    " reference TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, requested_by TEXT NOT NULL, requested_at TEXT NOT NULL,"
    " expires_at TEXT NOT NULL, decided_by TEXT, decided_at TEXT, payment_id TEXT, note TEXT NOT NULL DEFAULT '',"
    " client_txn_id TEXT NOT NULL, UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_advance_customer ON pos_advance_entries(business_id, customer_id)",
    "CREATE TABLE IF NOT EXISTS pos_advance_consents (business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " terms_version TEXT NOT NULL, accepted_at TEXT NOT NULL, PRIMARY KEY (business_id, phone_key, terms_version))",
]

KINDS = ("deposit", "redeem", "refund")


def _verified_key(user: str) -> str:
    """The 10+ digit number of an OTP-proven app account, else '' (other ids never match a customer)."""
    if not str(user or "").startswith("app-phone-"):
        return ""
    key = phone_key(user)
    return key if len(key) >= 10 else ""


class PosAdvances:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------ helpers
    def _settings(self, conn: sqlite3.Connection, business_id: str) -> Optional[sqlite3.Row]:
        return conn.execute("SELECT * FROM pos_advance_settings WHERE business_id = ?", (business_id,)).fetchone()

    def _expire(self, conn: sqlite3.Connection, where: str, args: tuple) -> None:
        now = self.store.clock().isoformat()
        conn.execute(f"UPDATE pos_advance_entries SET status = 'expired', decided_at = ? WHERE status = 'pending'"
                     f" AND expires_at < ? AND {where}", (now, now, *args))

    def _balance(self, conn: sqlite3.Connection, business_id: str, customer_id: str) -> int:
        row = conn.execute(
            "SELECT COALESCE(SUM(CASE WHEN kind = 'deposit' THEN amount_paise ELSE -amount_paise END), 0) AS b"
            " FROM pos_advance_entries WHERE business_id = ? AND customer_id = ? AND status = 'approved'",
            (business_id, customer_id)).fetchone()
        return int(row["b"])

    def _customer(self, conn: sqlite3.Connection, business_id: str, customer_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_customers WHERE id = ? AND business_id = ?",
                           (customer_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "customer", "Customer not found.")
        return row

    @staticmethod
    def _entry(row: sqlite3.Row) -> Dict[str, Any]:
        out = dict(row)
        out.pop("client_txn_id", None)
        return out

    # ------------------------------------------------------- shop settings
    def settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            row = self._settings(conn, business_id)
        return {"enabled": bool(row and row["enabled"]),
                "max_balance_paise": row["max_balance_paise"] if row else DEFAULT_MAX_PAISE,
                "hard_max_paise": HARD_MAX_PAISE, "terms_version": TERMS_VERSION,
                "accepted_terms_version": row["terms_version"] if row else None, "terms": TERMS}

    def update_settings(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        enabled = bool(data.get("enabled"))
        limit = int(data.get("max_balance_paise") or DEFAULT_MAX_PAISE)
        if limit <= 0 or limit > HARD_MAX_PAISE:
            raise PosError(400, "max_balance", f"The limit must be between Re 1 and Rs {HARD_MAX_PAISE // 100:,}.")
        if enabled and data.get("accept_terms_version") != TERMS_VERSION:
            raise PosError(400, "terms", "Read and accept the shop-advance terms first.", terms=TERMS,
                           terms_version=TERMS_VERSION)
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            now = self.store.clock().isoformat()
            current = self._settings(conn, business_id)
            terms = TERMS_VERSION if enabled else (current["terms_version"] if current else "")
            conn.execute("INSERT INTO pos_advance_settings (business_id, enabled, max_balance_paise, terms_version,"
                         " accepted_by, accepted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id)"
                         " DO UPDATE SET enabled = excluded.enabled, max_balance_paise = excluded.max_balance_paise,"
                         " terms_version = excluded.terms_version, accepted_by = CASE WHEN excluded.enabled = 1 THEN"
                         " excluded.accepted_by ELSE pos_advance_settings.accepted_by END, accepted_at = CASE WHEN"
                         " excluded.enabled = 1 THEN excluded.accepted_at ELSE pos_advance_settings.accepted_at END,"
                         " updated_at = excluded.updated_at",
                         (business_id, 1 if enabled else 0, limit, terms, user, now, now))
            self.store._audit(conn, business_id, user, "advance.settings", business_id,
                              {"enabled": enabled, "max_balance_paise": limit, "terms_version": terms}, now)
        return self.settings(business_id, user)

    # ------------------------------------------------------- shop requests
    def request(self, business_id: str, user: str, customer_id: str, kind: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A deposit, deduction (redeem) or refund that waits for the customer's approval."""
        if kind not in KINDS:
            raise PosError(400, "kind", "kind must be deposit, redeem or refund.")
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        amount = int(data.get("amount_paise") or 0)
        if amount <= 0:
            raise PosError(400, "amount", "Amount must be positive.")
        method = data.get("method") if kind != "redeem" else "advance"
        if kind != "redeem" and method not in PAY_METHODS:
            raise PosError(400, "payment", "Payment method must be cash, upi, card, bank_transfer or cheque.")
        permission = {"deposit": "collect", "redeem": "collect", "refund": "return"}[kind]
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, permission)
            settings = self._settings(conn, business_id)
            if not (settings and settings["enabled"]):
                raise PosError(409, "advance_off", "Shop advance is not turned on for this shop.")
            customer = self._customer(conn, business_id, customer_id)
            if len(phone_key(customer["phone"])) < 10:
                raise PosError(400, "customer_phone", "Add the customer's mobile number: they approve every change "
                                                      "in their own ASKODOX app.")
            seen = conn.execute("SELECT * FROM pos_advance_entries WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                if (seen["kind"], seen["amount_paise"], seen["customer_id"]) != (kind, amount, customer_id):
                    raise PosError(409, "client_txn_id", "This transaction id was already used for a different request.")
                return {**self._entry(seen), "replayed": True}
            self._expire(conn, "business_id = ? AND customer_id = ?", (business_id, customer_id))
            balance = self._balance(conn, business_id, customer_id)
            if kind == "deposit" and balance + amount > settings["max_balance_paise"]:
                raise PosError(400, "max_balance", "This would take the advance over the shop's limit.",
                               balance_paise=balance, max_balance_paise=settings["max_balance_paise"])
            if kind in ("redeem", "refund") and amount > balance:
                raise PosError(400, "insufficient", "The advance balance is less than this amount.", balance_paise=balance)
            if kind == "redeem":
                due = self.store._balance(conn, business_id, customer_id)
                if amount > due:
                    raise PosError(400, "more_than_due", "Only what the customer owes can be paid from the advance.",
                                   due_paise=max(due, 0))
            at = self.store.clock()
            entry_id = _id("adv")
            conn.execute("INSERT INTO pos_advance_entries (id, business_id, customer_id, kind, amount_paise, method,"
                         " reference, status, requested_by, requested_at, expires_at, note, client_txn_id)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)",
                         (entry_id, business_id, customer_id, kind, amount, method, _clean(data.get("reference"), 60),
                          user, at.isoformat(), (at + EXPIRY[kind]).isoformat(), _clean(data.get("note"), 160), txn))
            self.store._audit(conn, business_id, user, f"advance.{kind}.request", entry_id,
                              {"amount_paise": amount, "customer_id": customer_id, "method": method}, at.isoformat())
            row = conn.execute("SELECT * FROM pos_advance_entries WHERE id = ?", (entry_id,)).fetchone()
        return {**self._entry(row), "replayed": False}

    def withdraw(self, business_id: str, user: str, entry_id: str) -> Dict[str, Any]:
        """The shop takes back a request the customer has not answered yet."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "collect")
            row = conn.execute("SELECT * FROM pos_advance_entries WHERE id = ? AND business_id = ?",
                               (entry_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "entry", "Request not found.")
            if row["status"] != "pending":
                raise PosError(409, "status", f"This request is already {row['status']}.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_advance_entries SET status = 'withdrawn', decided_by = ?, decided_at = ? WHERE id = ?",
                         (user, now, entry_id))
            self.store._audit(conn, business_id, user, "advance.withdraw", entry_id, {}, now)
            row = conn.execute("SELECT * FROM pos_advance_entries WHERE id = ?", (entry_id,)).fetchone()
        return self._entry(row)

    def customer_view(self, business_id: str, user: str, customer_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "view")
            self._customer(conn, business_id, customer_id)
            self._expire(conn, "business_id = ? AND customer_id = ?", (business_id, customer_id))
            rows = conn.execute("SELECT * FROM pos_advance_entries WHERE business_id = ? AND customer_id = ?"
                                " ORDER BY requested_at DESC LIMIT 100", (business_id, customer_id)).fetchall()
            balance = self._balance(conn, business_id, customer_id)
            due = self.store._balance(conn, business_id, customer_id)
        return {"balance_paise": balance, "due_paise": max(due, 0), "entries": [self._entry(r) for r in rows]}

    # ------------------------------------------------------ customer side
    def mine(self, user: str) -> Dict[str, Any]:
        """Every shop where the signed-in number is a customer with advance activity."""
        key = _verified_key(user)
        if not key:
            return {"shops": [], "terms": TERMS, "terms_version": TERMS_VERSION}
        with self.store._tx() as conn:
            customers = [c for c in conn.execute(
                "SELECT c.id, c.business_id, c.name, c.phone, b.name AS shop FROM pos_customers c JOIN pos_businesses b"
                " ON b.id = c.business_id WHERE replace(replace(replace(c.phone, ' ', ''), '-', ''), '+', '') LIKE ?"
                " AND EXISTS (SELECT 1 FROM pos_advance_entries e WHERE e.customer_id = c.id AND e.business_id ="
                " c.business_id)", (f"%{key[-10:]}",)).fetchall() if phone_key(c["phone"]) == key]
            shops = []
            for c in customers:
                self._expire(conn, "business_id = ? AND customer_id = ?", (c["business_id"], c["id"]))
                rows = conn.execute("SELECT * FROM pos_advance_entries WHERE business_id = ? AND customer_id = ?"
                                    " ORDER BY requested_at DESC LIMIT 50", (c["business_id"], c["id"])).fetchall()
                consent = conn.execute("SELECT 1 FROM pos_advance_consents WHERE business_id = ? AND phone_key = ? AND"
                                       " terms_version = ?", (c["business_id"], key, TERMS_VERSION)).fetchone()
                shops.append({"business_id": c["business_id"], "shop": c["shop"], "customer_id": c["id"],
                              "balance_paise": self._balance(conn, c["business_id"], c["id"]),
                              "accepted_terms": bool(consent),
                              "pending": [self._entry(r) for r in rows if r["status"] == "pending"],
                              "history": [self._entry(r) for r in rows if r["status"] != "pending"]})
        return {"shops": shops, "terms": TERMS, "terms_version": TERMS_VERSION}

    def decide(self, user: str, entry_id: str, approve: bool, accept_terms_version: Optional[str] = None) -> Dict[str, Any]:
        key = _verified_key(user)
        with self.store._tx() as conn:
            row = conn.execute("SELECT e.*, c.phone AS customer_phone FROM pos_advance_entries e JOIN pos_customers c"
                               " ON c.id = e.customer_id AND c.business_id = e.business_id WHERE e.id = ?",
                               (entry_id,)).fetchone()
            # Someone else's request answers 404, exactly like a missing one.
            if row is None or not key or phone_key(row["customer_phone"]) != key:
                raise PosError(404, "entry", "Request not found.")
            business_id, customer_id = row["business_id"], row["customer_id"]
            self._expire(conn, "id = ?", (entry_id,))
            row = conn.execute("SELECT * FROM pos_advance_entries WHERE id = ?", (entry_id,)).fetchone()
            if row["status"] != "pending":
                raise PosError(409, "status", f"This request is already {row['status']}.")
            at = self.store.clock()
            now = at.isoformat()
            if not approve:
                conn.execute("UPDATE pos_advance_entries SET status = 'rejected', decided_by = ?, decided_at = ?"
                             " WHERE id = ?", (user, now, entry_id))
                self.store._audit(conn, business_id, user, "advance.reject", entry_id, {}, now)
            else:
                consent = conn.execute("SELECT 1 FROM pos_advance_consents WHERE business_id = ? AND phone_key = ? AND"
                                       " terms_version = ?", (business_id, key, TERMS_VERSION)).fetchone()
                if not consent:
                    if accept_terms_version != TERMS_VERSION:
                        raise PosError(400, "terms", "Read and accept the terms first.", terms=TERMS,
                                       terms_version=TERMS_VERSION)
                    conn.execute("INSERT INTO pos_advance_consents (business_id, phone_key, terms_version, accepted_at)"
                                 " VALUES (?, ?, ?, ?)", (business_id, key, TERMS_VERSION, now))
                settings = self._settings(conn, business_id)
                if not (settings and settings["enabled"]):
                    raise PosError(409, "advance_off", "This shop has turned shop advance off.")
                balance = self._balance(conn, business_id, customer_id)
                amount = row["amount_paise"]
                kind = row["kind"]
                if kind == "deposit" and balance + amount > settings["max_balance_paise"]:
                    raise PosError(400, "max_balance", "This would take the advance over the shop's limit.")
                if kind in ("redeem", "refund") and amount > balance:
                    raise PosError(400, "insufficient", "The advance balance is less than this amount.")
                payment_id = None
                if kind == "deposit":
                    # The money the customer handed over: counted in the shop's day close by its method.
                    payment_id = self.store._insert_payment(conn, business_id, None, customer_id, row["method"], amount,
                                                            row["reference"], "advance_deposit", user, at)
                elif kind == "refund":
                    payment_id = self.store._insert_payment(conn, business_id, None, customer_id, row["method"], -amount,
                                                            row["reference"], "advance_refund", user, at)
                else:
                    due = self.store._balance(conn, business_id, customer_id)
                    if amount > due:
                        raise PosError(400, "more_than_due", "This is more than you owe this shop now.")
                    payment_id = self.store._insert_payment(conn, business_id, None, customer_id, "advance", amount,
                                                            f"advance {entry_id}", "collection", user, at)
                    self.store._ledger(conn, business_id, customer_id, "payment", payment_id, credit=amount, at=at,
                                       note="paid from shop advance (customer approved)", user=user)
                conn.execute("UPDATE pos_advance_entries SET status = 'approved', decided_by = ?, decided_at = ?,"
                             " payment_id = ? WHERE id = ?", (user, now, payment_id, entry_id))
                self.store._audit(conn, business_id, user, f"advance.{kind}.approve", entry_id,
                                  {"amount_paise": amount, "payment_id": payment_id}, now)
            row = conn.execute("SELECT * FROM pos_advance_entries WHERE id = ?", (entry_id,)).fetchone()
            balance = self._balance(conn, business_id, customer_id)
        return {**self._entry(row), "balance_paise": balance}
