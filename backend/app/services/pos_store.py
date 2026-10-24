"""ASKODOX Universal POS -- the shared core (businesses, staff roles, products,
customers, invoices, credit notes, payments, customer ledger, stock, day close,
GST summary, audit).

Invariants (POS master command):
- An issued invoice / credit note is NEVER deleted or edited. A mistake is
  corrected by a credit note, or (same day, before day close, no credit note
  yet) by a CANCEL that keeps the row, records who / why, and posts reversing
  stock + ledger entries.
- The customer ledger, stock moves, payments and the audit log are append-only.
- Every write is idempotent on a client transaction id, so an offline queue can
  resend safely and a double tap never bills twice.
- A UPI / card payment entered by the cashier is stored as
  ``cashier_confirmed`` -- never as bank-verified. Only a payment provider's own
  answer may set ``gateway_verified`` (not wired in this round).
- Each business is isolated: every query is scoped by business id and the
  caller's membership + role are checked on every call.
- The AI never writes here: prices, taxes, stock and invoices change only
  through these explicit calls made after the person confirmed.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional

from app.services import pos_tax
from app.services.account_identity import phone_key

IST = timezone(timedelta(hours=5, minutes=30))

ROLES = ("owner", "manager", "cashier", "accountant", "waiter", "kitchen")
PERMISSIONS: Dict[str, frozenset] = {
    "owner": frozenset({"view", "sell", "price_override", "return", "cancel", "products", "stock", "customers",
                        "collect", "reports", "day_close", "drafts", "members", "settings", "tables", "kitchen",
                        "purchases"}),
    "manager": frozenset({"view", "sell", "price_override", "return", "cancel", "products", "stock", "customers",
                          "collect", "reports", "day_close", "drafts", "tables", "kitchen", "purchases"}),
    "cashier": frozenset({"view", "sell", "customers", "collect", "drafts", "tables", "kitchen"}),
    "accountant": frozenset({"view", "reports"}),
    # Restaurant floor staff: take orders / send KOTs (waiter), or work the kitchen screen. Neither can bill.
    "waiter": frozenset({"view", "tables"}),
    "kitchen": frozenset({"view", "kitchen"}),
}
TEMPLATES = ("general", "kirana", "supermarket", "meat_fish", "restaurant", "pharmacy", "salon", "repair",
             "wholesale", "clothing", "electronics", "jewellery", "bakery", "vegetables", "hardware", "stationery")
UNITS = ("pcs", "kg", "g", "l", "ml", "m", "dozen", "box", "plate", "hour", "service", "pack")
PAY_METHODS = ("cash", "upi", "card", "bank_transfer", "cheque")
VERIFICATION = {"cash": "cash_counted", "upi": "cashier_confirmed", "card": "cashier_confirmed",
                "bank_transfer": "cashier_confirmed", "cheque": "cashier_confirmed",
                # Paid from a shop advance: approved by the customer in their own app (pos_advance.py).
                "advance": "customer_approved"}
MAX_OFFLINE_AGE = timedelta(days=7)
DISCLAIMER = ("Prepared from invoices recorded in ASKODOX for accountant review. It is not a filed GST return; "
              "check every figure and classification with your accountant before filing.")


class PosError(Exception):
    def __init__(self, status: int, code: str, message: str, **extra: Any) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:20]}"


def _round_div(numerator: int, denominator: int) -> int:
    return (2 * numerator + denominator) // (2 * denominator)


def _clean(value: Any, limit: int = 120) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _digest(payload: Dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, default=str).encode("utf-8")).hexdigest()


SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_businesses (id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL, name TEXT NOT NULL,"
    " address TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '', gstin TEXT, state_code TEXT NOT NULL,"
    " registration_type TEXT NOT NULL, turnover_above_5cr INTEGER NOT NULL DEFAULT 0, template TEXT NOT NULL,"
    " invoice_prefix TEXT NOT NULL, round_off INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_members (business_id TEXT NOT NULL, phone_key TEXT NOT NULL, app_user_id TEXT,"
    " role TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, added_by TEXT NOT NULL, created_at TEXT NOT NULL,"
    " PRIMARY KEY (business_id, phone_key))",
    "CREATE TABLE IF NOT EXISTS pos_products (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " name_te TEXT NOT NULL DEFAULT '', sku TEXT NOT NULL DEFAULT '', barcode TEXT NOT NULL DEFAULT '',"
    " hsn_sac TEXT NOT NULL DEFAULT '', is_service INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL,"
    " price_paise INTEGER NOT NULL, price_includes_tax INTEGER NOT NULL DEFAULT 1, rate_bp INTEGER NOT NULL DEFAULT 0,"
    " cess_bp INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT 'taxable', track_stock INTEGER NOT NULL DEFAULT 0,"
    " low_stock_milli INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, version INTEGER NOT NULL DEFAULT 1,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_products_biz ON pos_products(business_id)",
    "CREATE TABLE IF NOT EXISTS pos_product_history (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id TEXT NOT NULL,"
    " business_id TEXT NOT NULL, version INTEGER NOT NULL, changes TEXT NOT NULL, changed_by TEXT NOT NULL, at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_customers (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " phone TEXT NOT NULL DEFAULT '', gstin TEXT, address TEXT NOT NULL DEFAULT '', state_code TEXT,"
    " credit_limit_paise INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_customers_biz ON pos_customers(business_id)",
    "CREATE TABLE IF NOT EXISTS pos_price_lists (business_id TEXT NOT NULL, customer_id TEXT NOT NULL,"
    " product_id TEXT NOT NULL, price_paise INTEGER NOT NULL, updated_by TEXT NOT NULL, updated_at TEXT NOT NULL,"
    " PRIMARY KEY (business_id, customer_id, product_id))",
    "CREATE TABLE IF NOT EXISTS pos_series (business_id TEXT NOT NULL, prefix TEXT NOT NULL, fy TEXT NOT NULL,"
    " next_number INTEGER NOT NULL DEFAULT 1, device_id TEXT, kind TEXT NOT NULL DEFAULT 'invoice',"
    " PRIMARY KEY (business_id, prefix, fy))",
    "CREATE TABLE IF NOT EXISTS pos_invoices (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, doc_kind TEXT NOT NULL,"
    " document_type TEXT NOT NULL, number TEXT NOT NULL, series TEXT NOT NULL, fy TEXT NOT NULL, issued_at TEXT NOT NULL,"
    " local_date TEXT NOT NULL, customer_id TEXT, customer_snapshot TEXT NOT NULL, business_snapshot TEXT NOT NULL,"
    " place_of_supply TEXT NOT NULL, mode TEXT NOT NULL, totals TEXT NOT NULL, rate_summary TEXT NOT NULL,"
    " rules_version TEXT NOT NULL, status TEXT NOT NULL, cancel_reason TEXT, cancelled_by TEXT, cancelled_at TEXT,"
    " original_invoice_id TEXT, reason TEXT, client_txn_id TEXT NOT NULL, payload_digest TEXT NOT NULL,"
    " created_by TEXT NOT NULL, device_id TEXT, offline INTEGER NOT NULL DEFAULT 0, synced_at TEXT NOT NULL,"
    " paid_paise INTEGER NOT NULL DEFAULT 0, balance_paise INTEGER NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT '',"
    " UNIQUE (business_id, client_txn_id), UNIQUE (business_id, fy, number))",
    "CREATE INDEX IF NOT EXISTS idx_pos_invoices_date ON pos_invoices(business_id, local_date)",
    "CREATE TABLE IF NOT EXISTS pos_invoice_lines (invoice_id TEXT NOT NULL, line_no INTEGER NOT NULL,"
    " product_id TEXT, name TEXT NOT NULL, hsn_sac TEXT NOT NULL, unit TEXT NOT NULL, qty_milli INTEGER NOT NULL,"
    " unit_price_paise INTEGER NOT NULL, price_source TEXT NOT NULL, discount_paise INTEGER NOT NULL,"
    " rate_bp INTEGER NOT NULL, cess_bp INTEGER NOT NULL, category TEXT NOT NULL, price_includes_tax INTEGER NOT NULL,"
    " taxable_paise INTEGER NOT NULL, cgst_paise INTEGER NOT NULL, sgst_paise INTEGER NOT NULL,"
    " igst_paise INTEGER NOT NULL, cess_paise INTEGER NOT NULL, total_paise INTEGER NOT NULL, weight TEXT,"
    " original_line_no INTEGER, PRIMARY KEY (invoice_id, line_no))",
    "CREATE TABLE IF NOT EXISTS pos_payments (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, invoice_id TEXT,"
    " customer_id TEXT, method TEXT NOT NULL, amount_paise INTEGER NOT NULL, verification TEXT NOT NULL,"
    " reference TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL, received_by TEXT NOT NULL, at TEXT NOT NULL,"
    " local_date TEXT NOT NULL, client_txn_id TEXT, UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_payments_date ON pos_payments(business_id, local_date)",
    "CREATE TABLE IF NOT EXISTS pos_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,"
    " customer_id TEXT NOT NULL, kind TEXT NOT NULL, ref_id TEXT NOT NULL, debit_paise INTEGER NOT NULL DEFAULT 0,"
    " credit_paise INTEGER NOT NULL DEFAULT 0, at TEXT NOT NULL, local_date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',"
    " created_by TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_ledger_cust ON pos_ledger(business_id, customer_id)",
    "CREATE TABLE IF NOT EXISTS pos_stock_moves (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,"
    " product_id TEXT NOT NULL, qty_milli INTEGER NOT NULL, kind TEXT NOT NULL, ref_id TEXT NOT NULL DEFAULT '',"
    " reason TEXT NOT NULL DEFAULT '', at TEXT NOT NULL, created_by TEXT NOT NULL, client_txn_id TEXT,"
    " UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_stock_prod ON pos_stock_moves(business_id, product_id)",
    "CREATE TABLE IF NOT EXISTS pos_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,"
    " actor TEXT NOT NULL, action TEXT NOT NULL, ref TEXT NOT NULL DEFAULT '', detail TEXT NOT NULL DEFAULT '{}',"
    " at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_day_close (business_id TEXT NOT NULL, local_date TEXT NOT NULL,"
    " closed_by TEXT NOT NULL, closed_at TEXT NOT NULL, opening_float_paise INTEGER NOT NULL,"
    " expected_cash_paise INTEGER NOT NULL, counted_cash_paise INTEGER NOT NULL, difference_paise INTEGER NOT NULL,"
    " totals TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', PRIMARY KEY (business_id, local_date))",
    "CREATE TABLE IF NOT EXISTS pos_drafts (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, kind TEXT NOT NULL,"
    " title TEXT NOT NULL, payload TEXT NOT NULL, created_by TEXT NOT NULL, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL)",
]

# Columns added after the first release (added in place, never by recreating a table).
MIGRATIONS = [
    ("pos_products", "track_batches", "INTEGER NOT NULL DEFAULT 0"),
    ("pos_stock_moves", "batch_no", "TEXT"),
    ("pos_stock_moves", "expiry_date", "TEXT"),
    ("pos_invoice_lines", "batches", "TEXT"),
    ("pos_products", "track_serials", "INTEGER NOT NULL DEFAULT 0"),
    ("pos_products", "serial_kind", "TEXT NOT NULL DEFAULT ''"),
    ("pos_invoice_lines", "pack", "TEXT"),
    ("pos_invoice_lines", "base_qty_milli", "INTEGER"),
    ("pos_invoice_lines", "serials", "TEXT"),
    # Where items are offered (pos_online.py): shop default + per-item override (NULL = default).
    ("pos_businesses", "online_default", "TEXT NOT NULL DEFAULT 'pos'"),
    ("pos_products", "channel", "TEXT"),
    # Ready-made catalogue (pos_catalogue.py): the shop's catalogue template + an item's details / online price.
    ("pos_businesses", "catalogue_template", "TEXT"),
    ("pos_products", "attributes", "TEXT"),
    ("pos_products", "online_price_paise", "INTEGER"),
    # Quantity pricing: the least a customer may buy (base units); rates by quantity live in pos_price_tiers.
    ("pos_products", "min_qty_milli", "INTEGER"),
    ("pos_products", "photo_at", "TEXT"),
]

# Selling units beyond the item's base unit (box of 12 pcs, 25 kg bag ...).
EXTRA_SCHEMA = [
    # Rate by quantity: from min_qty_milli (base units) upward the price per base unit is price_paise.
    "CREATE TABLE IF NOT EXISTS pos_price_tiers (business_id TEXT NOT NULL, product_id TEXT NOT NULL,"
    " min_qty_milli INTEGER NOT NULL, price_paise INTEGER NOT NULL, PRIMARY KEY (product_id, min_qty_milli))",
    "CREATE TABLE IF NOT EXISTS pos_product_photos (business_id TEXT NOT NULL, product_id TEXT PRIMARY KEY,"
    " image BLOB NOT NULL, mime TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_product_packs (business_id TEXT NOT NULL, product_id TEXT NOT NULL, name TEXT NOT NULL,"
    " factor_milli INTEGER NOT NULL, price_paise INTEGER, barcode TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,"
    " PRIMARY KEY (business_id, product_id, name))",
    "CREATE TABLE IF NOT EXISTS pos_serials (business_id TEXT NOT NULL, product_id TEXT NOT NULL, serial TEXT NOT NULL,"
    " status TEXT NOT NULL, purchase_id TEXT, invoice_id TEXT, updated_at TEXT NOT NULL,"
    " PRIMARY KEY (business_id, product_id, serial))",
    "CREATE INDEX IF NOT EXISTS idx_pos_serials_lookup ON pos_serials(business_id, serial)",
]


def imei_valid(value: str) -> bool:
    """15-digit IMEI with a correct Luhn check digit."""
    if not re.fullmatch(r"\d{15}", value or ""):
        return False
    total = 0
    for i, ch in enumerate(value[:14]):
        d = int(ch)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - total % 10) % 10 == int(value[14])


class PosStore:
    def __init__(self, db_path: str, clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.clock = clock
        with self._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            for statement in EXTRA_SCHEMA:
                conn.execute(statement)
            for table, column, decl in MIGRATIONS:
                have = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
                if column not in have:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")

    # ------------------------------------------------------------------ basics
    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    class _Tx:
        def __init__(self, store: "PosStore") -> None:
            self.conn = store._connect()

        def __enter__(self) -> sqlite3.Connection:
            self.conn.execute("BEGIN IMMEDIATE")
            return self.conn

        def __exit__(self, exc_type, exc, tb) -> None:
            try:
                self.conn.execute("ROLLBACK" if exc_type else "COMMIT")
            finally:
                self.conn.close()

    def _tx(self) -> "PosStore._Tx":
        return PosStore._Tx(self)

    def _local(self, at: datetime) -> str:
        return at.astimezone(IST).date().isoformat()

    @staticmethod
    def _audit(conn: sqlite3.Connection, business_id: str, actor: str, action: str, ref: str, detail: Dict[str, Any],
               at: str) -> None:
        conn.execute("INSERT INTO pos_audit (business_id, actor, action, ref, detail, at) VALUES (?, ?, ?, ?, ?, ?)",
                     (business_id, actor, action, ref, json.dumps(detail, default=str), at))

    # ------------------------------------------------------------ businesses
    def create_business(self, owner: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 80)
        if not name:
            raise PosError(400, "name", "Business name is required.")
        reg = str(data.get("registration_type") or "unregistered")
        if reg not in ("regular", "composition", "unregistered"):
            raise PosError(400, "registration_type", "registration_type must be regular, composition or unregistered.")
        gstin = str(data.get("gstin") or "").strip().upper() or None
        state = str(data.get("state_code") or "").zfill(2) if data.get("state_code") else ""
        if reg != "unregistered":
            check = pos_tax.validate_gstin(gstin or "")
            if not check["valid"]:
                raise PosError(400, "gstin", f"GSTIN is not valid ({check['reason']}).")
            state = check["state_code"]
        elif gstin:
            raise PosError(400, "gstin", "An unregistered business has no GSTIN; choose regular or composition.")
        if state not in pos_tax.STATE_CODES:
            raise PosError(400, "state_code", "Choose the State / UT where the business is.")
        template = str(data.get("template") or "general")
        if template not in TEMPLATES:
            raise PosError(400, "template", "Unknown business type.")
        prefix = str(data.get("invoice_prefix") or "INV").strip().upper()
        if not re.fullmatch(r"[A-Z0-9]{1,3}", prefix):
            # prefix + type letter + "/2627/" + 6 digits must stay within 16 characters (Rule 46(b))
            raise PosError(400, "invoice_prefix", "Invoice prefix: 1-3 letters / digits.")
        now = self.clock().isoformat()
        business_id = _id("biz")
        with self._tx() as conn:
            conn.execute(
                "INSERT INTO pos_businesses (id, owner_user_id, name, address, phone, gstin, state_code,"
                " registration_type, turnover_above_5cr, template, invoice_prefix, round_off, created_at, updated_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (business_id, owner, name, _clean(data.get("address"), 240), _clean(data.get("phone"), 20), gstin,
                 state, reg, 1 if data.get("turnover_above_5cr") else 0, template, prefix,
                 1 if data.get("round_off") else 0, now, now))
            conn.execute("INSERT INTO pos_members (business_id, phone_key, app_user_id, role, active, added_by,"
                         " created_at) VALUES (?, ?, ?, 'owner', 1, ?, ?)",
                         (business_id, phone_key(owner) or owner, owner, owner, now))
            self._audit(conn, business_id, owner, "business.create", business_id,
                        {"registration_type": reg, "template": template}, now)
        return self.business(business_id, owner)

    def _business_row(self, conn: sqlite3.Connection, business_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        if row is None:
            raise PosError(404, "business", "Business not found.")
        return row

    def role_of(self, conn: sqlite3.Connection, business_id: str, user: str) -> Optional[str]:
        row = conn.execute("SELECT role FROM pos_members WHERE business_id = ? AND active = 1 AND app_user_id = ?",
                           (business_id, user)).fetchone()
        if row:
            return row["role"]
        key = phone_key(user)
        if len(key) >= 10:
            row = conn.execute("SELECT role FROM pos_members WHERE business_id = ? AND active = 1 AND phone_key = ?",
                               (business_id, key)).fetchone()
            if row:
                conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND phone_key = ?",
                             (user, business_id, key))
                return row["role"]
        return None

    def _require(self, conn: sqlite3.Connection, business_id: str, user: str, permission: str) -> str:
        self._business_row(conn, business_id)
        role = self.role_of(conn, business_id, user)
        if role is None:
            # Same answer as a missing business: never reveal another shop exists.
            raise PosError(404, "business", "Business not found.")
        if permission not in PERMISSIONS[role]:
            raise PosError(403, "permission", f"Your role ({role}) cannot do this.", role=role)
        return role

    def business(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            role = self._require(conn, business_id, user, "view")
            row = dict(self._business_row(conn, business_id))
        row.pop("owner_user_id", None)
        row["state"] = pos_tax.STATE_CODES.get(row["state_code"], "")
        row["my_role"] = role
        row["permissions"] = sorted(PERMISSIONS[role])
        row["rules"] = {"version": pos_tax.RULES_VERSION, "einvoice_note": (
            "E-invoicing (IRN) applies above Rs 5 crore aggregate turnover; ASKODOX does not generate IRNs yet."
            if row["turnover_above_5cr"] else "")}
        return row

    def my_businesses(self, user: str) -> List[Dict[str, Any]]:
        key = phone_key(user)
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT b.id, b.name, b.template, b.registration_type, m.role FROM pos_members m"
                " JOIN pos_businesses b ON b.id = m.business_id WHERE m.active = 1 AND (m.app_user_id = ?"
                " OR (length(?) >= 10 AND m.phone_key = ?)) ORDER BY b.created_at",
                (user, key, key)).fetchall()
        return [dict(r) for r in rows]

    def update_settings(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        allowed = {"address": 240, "phone": 20, "name": 80}
        with self._tx() as conn:
            self._require(conn, business_id, user, "settings")
            changes = {k: _clean(data[k], allowed[k]) for k in allowed if k in data}
            if "round_off" in data:
                changes["round_off"] = 1 if data["round_off"] else 0
            if "turnover_above_5cr" in data:
                changes["turnover_above_5cr"] = 1 if data["turnover_above_5cr"] else 0
            if changes:
                now = self.clock().isoformat()
                sets = ", ".join(f"{k} = ?" for k in changes)
                conn.execute(f"UPDATE pos_businesses SET {sets}, updated_at = ? WHERE id = ?",
                             (*changes.values(), now, business_id))
                self._audit(conn, business_id, user, "business.settings", business_id, changes, now)
        return self.business(business_id, user)

    def set_member(self, business_id: str, user: str, phone: str, role: str) -> Dict[str, Any]:
        key = phone_key(phone)
        if len(key) < 10:
            raise PosError(400, "phone", "Enter the staff member's 10-digit mobile number.")
        if role not in ROLES + ("removed",):
            raise PosError(400, "role", "Role must be manager, cashier, accountant, waiter, kitchen or removed.")
        if role == "owner":
            raise PosError(400, "role", "Ownership cannot be transferred here.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "members")
            current = conn.execute("SELECT role FROM pos_members WHERE business_id = ? AND phone_key = ?",
                                   (business_id, key)).fetchone()
            if current and current["role"] == "owner":
                raise PosError(400, "role", "The owner's role cannot be changed.")
            now = self.clock().isoformat()
            if role == "removed":
                conn.execute("UPDATE pos_members SET active = 0 WHERE business_id = ? AND phone_key = ?",
                             (business_id, key))
            else:
                conn.execute(
                    "INSERT INTO pos_members (business_id, phone_key, role, active, added_by, created_at)"
                    " VALUES (?, ?, ?, 1, ?, ?) ON CONFLICT(business_id, phone_key) DO UPDATE SET role = excluded.role,"
                    " active = 1", (business_id, key, role, user, now))
            self._audit(conn, business_id, user, "member.set", key[-4:], {"role": role}, now)
        return {"phone_last4": key[-4:], "role": role}

    def members(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "members")
            rows = conn.execute("SELECT phone_key, role, active, created_at FROM pos_members WHERE business_id = ?"
                                " ORDER BY created_at", (business_id,)).fetchall()
        return [{"phone_last4": r["phone_key"][-4:], "role": r["role"], "active": bool(r["active"]),
                 "created_at": r["created_at"]} for r in rows]

    # -------------------------------------------------------------- products
    def _product_fields(self, data: Dict[str, Any], business: sqlite3.Row, partial: bool) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        if not partial or "name" in data:
            out["name"] = _clean(data.get("name"), 80)
            if not out["name"]:
                raise PosError(400, "name", "Item name is required.")
        for key, limit in (("name_te", 80), ("sku", 40), ("barcode", 64)):
            if key in data:
                out[key] = _clean(data.get(key), limit)
        if not partial or "unit" in data:
            out["unit"] = str(data.get("unit") or "pcs")
            if out["unit"] not in UNITS:
                raise PosError(400, "unit", f"Unit must be one of {', '.join(UNITS)}.")
        if not partial or "price_paise" in data:
            price = int(data.get("price_paise") if data.get("price_paise") is not None else -1)
            if price < 0 or price > 10_00_00_000_00:
                raise PosError(400, "price", "Enter the selling price.")
            out["price_paise"] = price
        for key in ("price_includes_tax", "track_stock", "is_service", "track_batches", "track_serials"):
            if key in data or not partial:
                out[key] = 1 if data.get(key, key == "price_includes_tax") else 0
        if out.get("track_batches") or out.get("track_serials"):
            out["track_stock"] = 1  # batches / serials are stock
        if "serial_kind" in data:
            out["serial_kind"] = "imei" if data.get("serial_kind") == "imei" else ""
        if "low_stock_milli" in data:
            out["low_stock_milli"] = max(0, int(data.get("low_stock_milli") or 0))
        if "category" in data or not partial:
            out["category"] = str(data.get("category") or "taxable")
            if out["category"] not in pos_tax.TAX_CATEGORIES:
                raise PosError(400, "category", "Unknown tax category.")
        if "rate_bp" in data or not partial:
            rate = int(data.get("rate_bp") or 0)
            if rate not in pos_tax.ALLOWED_RATES_BP:
                raise PosError(400, "rate", "Choose a GST rate from the list (from your own classification).")
            out["rate_bp"] = rate
        if "online_price_paise" in data:
            online = data.get("online_price_paise")
            if online is None:
                out["online_price_paise"] = None  # same as the shop price
            else:
                online = int(online)
                if online <= 0 or online > 10_00_00_000_00:
                    raise PosError(400, "online_price", "Enter the online price, or leave it the same as the shop price.")
                out["online_price_paise"] = online
        if "cess_bp" in data:
            out["cess_bp"] = int(data.get("cess_bp") or 0)
        if "hsn_sac" in data or not partial:
            hsn = re.sub(r"\s", "", str(data.get("hsn_sac") or ""))
            if hsn:
                check = pos_tax.check_hsn(hsn, is_service=bool(data.get("is_service")))
                if not check["ok"]:
                    raise PosError(400, "hsn_sac", "HSN / SAC must be 4, 6 or 8 digits (SAC starts with 99).")
            # An empty code is allowed on the item (B2C sales of a business up to Rs 5 crore may omit it);
            # a tax invoice that legally needs it is refused at billing time (``_hsn_problems``).
            out["hsn_sac"] = hsn
        return out

    def add_product(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self._tx() as conn:
            self._require(conn, business_id, user, "products")
            business = self._business_row(conn, business_id)
            fields = self._product_fields(data, business, partial=False)
            now = self.clock().isoformat()
            product_id = _id("prd")
            cols = ["id", "business_id", *fields.keys(), "created_at", "updated_at"]
            conn.execute(f"INSERT INTO pos_products ({', '.join(cols)}) VALUES ({', '.join('?' for _ in cols)})",
                         (product_id, business_id, *fields.values(), now, now))
            conn.execute("INSERT INTO pos_product_history (product_id, business_id, version, changes, changed_by, at)"
                         " VALUES (?, ?, 1, ?, ?, ?)", (product_id, business_id, json.dumps(fields), user, now))
            self._audit(conn, business_id, user, "product.add", product_id, fields, now)
            opening = int(data.get("opening_stock_milli") or 0)
            if opening and fields.get("track_stock"):
                conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, reason, at,"
                             " created_by) VALUES (?, ?, ?, 'opening', 'opening stock', ?, ?)",
                             (business_id, product_id, opening, now, user))
        return self.product(business_id, user, product_id)

    def update_product(self, business_id: str, user: str, product_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Edits apply to FUTURE invoices only (issued lines keep their snapshot)."""
        with self._tx() as conn:
            self._require(conn, business_id, user, "products")
            business = self._business_row(conn, business_id)
            row = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ?",
                               (product_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "product", "Item not found.")
            fields = self._product_fields(data, business, partial=True)
            if "active" in data:
                fields["active"] = 1 if data["active"] else 0
            changes = {k: v for k, v in fields.items() if row[k] != v}
            if changes:
                now = self.clock().isoformat()
                version = row["version"] + 1
                sets = ", ".join(f"{k} = ?" for k in changes)
                conn.execute(f"UPDATE pos_products SET {sets}, version = ?, updated_at = ? WHERE id = ?",
                             (*changes.values(), version, now, product_id))
                before = {k: row[k] for k in changes}
                conn.execute("INSERT INTO pos_product_history (product_id, business_id, version, changes, changed_by,"
                             " at) VALUES (?, ?, ?, ?, ?, ?)",
                             (product_id, business_id, version, json.dumps({"before": before, "after": changes}),
                              user, now))
                self._audit(conn, business_id, user, "product.update", product_id,
                            {"before": before, "after": changes}, now)
        return self.product(business_id, user, product_id)

    def _stock_map(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, int]:
        return {r["product_id"]: r["qty"] for r in conn.execute(
            "SELECT product_id, SUM(qty_milli) AS qty FROM pos_stock_moves WHERE business_id = ? GROUP BY product_id",
            (business_id,))}

    @staticmethod
    def _product_out(row: sqlite3.Row, stock: Optional[int]) -> Dict[str, Any]:
        out = dict(row)
        for key in ("price_includes_tax", "track_stock", "is_service", "active", "track_batches", "track_serials"):
            out[key] = bool(out.get(key))
        out["stock_milli"] = stock if out["track_stock"] else None
        try:
            out["attributes"] = json.loads(out.get("attributes") or "{}")
        except (TypeError, ValueError):
            out["attributes"] = {}
        out["low_stock"] = bool(out["track_stock"] and (stock or 0) <= out["low_stock_milli"])
        return out

    def _tiers(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, List[Dict[str, Any]]]:
        out: Dict[str, List[Dict[str, Any]]] = {}
        for r in conn.execute("SELECT product_id, min_qty_milli, price_paise FROM pos_price_tiers WHERE business_id = ?"
                              " ORDER BY min_qty_milli", (business_id,)):
            out.setdefault(r["product_id"], []).append({"min_qty_milli": r["min_qty_milli"], "price_paise": r["price_paise"]})
        return out

    @staticmethod
    def tier_price(tiers: List[Dict[str, Any]], base_qty_milli: int) -> Optional[int]:
        """Price per base unit for this quantity: the tier with the highest minimum not above it."""
        best = None
        for t in sorted(tiers or [], key=lambda t: t["min_qty_milli"]):
            if base_qty_milli >= t["min_qty_milli"]:
                best = t["price_paise"]
        return best

    def _packs(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, List[Dict[str, Any]]]:
        out: Dict[str, List[Dict[str, Any]]] = {}
        for r in conn.execute("SELECT product_id, name, factor_milli, price_paise, barcode FROM pos_product_packs WHERE"
                              " business_id = ? ORDER BY factor_milli", (business_id,)):
            out.setdefault(r["product_id"], []).append({k: r[k] for k in ("name", "factor_milli", "price_paise", "barcode")})
        return out

    def set_pack(self, business_id: str, user: str, product_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A selling / buying unit of an item: e.g. 'box' = 12 pcs. ``factor_milli`` = base units per pack
        (x1000). ``remove`` deletes the unit (issued bills keep their own copy)."""
        name = _clean(data.get("name"), 20).lower()
        if not re.fullmatch(r"[a-z0-9 \-]{1,20}", name):
            raise PosError(400, "name", "Unit name: 1-20 letters / digits (e.g. box, bag, case).")
        with self._tx() as conn:
            self._require(conn, business_id, user, "products")
            product = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ?",
                                   (product_id, business_id)).fetchone()
            if product is None:
                raise PosError(404, "product", "Item not found.")
            now = self.clock().isoformat()
            if data.get("remove"):
                conn.execute("DELETE FROM pos_product_packs WHERE business_id = ? AND product_id = ? AND name = ?",
                             (business_id, product_id, name))
                self._audit(conn, business_id, user, "pack.remove", product_id, {"name": name}, now)
            else:
                if name == product["unit"]:
                    raise PosError(400, "name", "That is already the item's base unit.")
                factor = int(data.get("factor_milli") or 0)
                if factor <= 0 or factor > 1_000_000_000:
                    raise PosError(400, "factor", f"How many {product['unit']} are in one {name}?")
                price = data.get("price_paise")
                if price is not None and int(price) < 0:
                    raise PosError(400, "price", "Price cannot be negative.")
                conn.execute("INSERT INTO pos_product_packs (business_id, product_id, name, factor_milli, price_paise, barcode,"
                             " created_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id, product_id, name) DO UPDATE"
                             " SET factor_milli = excluded.factor_milli, price_paise = excluded.price_paise,"
                             " barcode = excluded.barcode",
                             (business_id, product_id, name, factor, None if price is None else int(price),
                              _clean(data.get("barcode"), 64), now))
                self._audit(conn, business_id, user, "pack.set", product_id,
                            {"name": name, "factor_milli": factor, "price_paise": price}, now)
        return self.product(business_id, user, product_id)

    def serial_lookup(self, business_id: str, user: str, serial: str) -> Dict[str, Any]:
        """Warranty / theft check: where a serial or IMEI is in this shop's records."""
        sn = _clean(serial, 40).upper()
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            rows = conn.execute("SELECT s.*, p.name FROM pos_serials s JOIN pos_products p ON p.id = s.product_id WHERE"
                                " s.business_id = ? AND s.serial = ?", (business_id, sn)).fetchall()
            out = []
            for r in rows:
                inv = None
                if r["invoice_id"]:
                    i = conn.execute("SELECT number, local_date FROM pos_invoices WHERE id = ?", (r["invoice_id"],)).fetchone()
                    inv = {"id": r["invoice_id"], "number": i["number"], "date": i["local_date"]} if i else None
                out.append({"product_id": r["product_id"], "name": r["name"], "status": r["status"], "invoice": inv,
                            "purchase_id": r["purchase_id"]})
        if not out:
            raise PosError(404, "serial", "This serial / IMEI is not in this shop's records.")
        return {"serial": sn, "records": out}

    def serials_in_stock(self, business_id: str, user: str, product_id: str) -> List[str]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            return [r["serial"] for r in conn.execute(
                "SELECT serial FROM pos_serials WHERE business_id = ? AND product_id = ? AND status = 'in_stock' ORDER BY"
                " updated_at, serial", (business_id, product_id))]

    def product(self, business_id: str, user: str, product_id: str) -> Dict[str, Any]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            row = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ?",
                               (product_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "product", "Item not found.")
            stock = self._stock_map(conn, business_id).get(product_id, 0)
            packs = self._packs(conn, business_id).get(product_id, [])
            tiers = self._tiers(conn, business_id).get(product_id, [])
        return {**self._product_out(row, stock), "packs": packs, "tiers": tiers}

    def products(self, business_id: str, user: str, query: str = "", include_inactive: bool = False) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            sql = "SELECT * FROM pos_products WHERE business_id = ?"
            args: List[Any] = [business_id]
            if not include_inactive:
                sql += " AND active = 1"
            q = _clean(query, 60)
            if q:
                sql += (" AND (name LIKE ? OR name_te LIKE ? OR sku = ? OR barcode = ? OR id IN (SELECT product_id FROM"
                        " pos_product_packs WHERE business_id = ? AND barcode = ?))")
                args += [f"%{q}%", f"%{q}%", q, q, business_id, q]
            rows = conn.execute(sql + " ORDER BY name LIMIT 500", args).fetchall()
            stock = self._stock_map(conn, business_id)
            packs = self._packs(conn, business_id)
            tiers = self._tiers(conn, business_id)
        return [{**self._product_out(r, stock.get(r["id"], 0)), "packs": packs.get(r["id"], []),
                 "tiers": tiers.get(r["id"], [])} for r in rows]

    def product_history(self, business_id: str, user: str, product_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "products")
            rows = conn.execute("SELECT version, changes, at FROM pos_product_history WHERE business_id = ? AND"
                                " product_id = ? ORDER BY version", (business_id, product_id)).fetchall()
        return [{"version": r["version"], "changes": json.loads(r["changes"]), "at": r["at"]} for r in rows]

    # ----------------------------------------------------------------- stock
    def stock_move(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("kind") or "")
        if kind not in ("purchase", "adjustment", "count", "wastage"):
            raise PosError(400, "kind", "kind must be purchase, adjustment, count or wastage.")
        reason = _clean(data.get("reason"), 160)
        if kind in ("adjustment", "wastage") and not reason:
            raise PosError(400, "reason", "Say why the stock changed.")
        txn = _clean(data.get("client_txn_id"), 64) or None
        with self._tx() as conn:
            self._require(conn, business_id, user, "stock")
            if txn:
                seen = conn.execute("SELECT id FROM pos_stock_moves WHERE business_id = ? AND client_txn_id = ?",
                                    (business_id, txn)).fetchone()
                if seen:
                    return {"replayed": True, "move_id": seen["id"]}
            product = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ? AND track_stock = 1",
                                   (data.get("product_id"), business_id)).fetchone()
            if product is None:
                raise PosError(404, "product", "Item not found or stock is not tracked for it.")
            current = self._stock_map(conn, business_id).get(product["id"], 0)
            qty = int(data.get("qty_milli") or 0)
            batch_no = _clean(data.get("batch_no"), 40) or None
            expiry = str(data.get("expiry_date") or "") or None
            if expiry and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", expiry):
                raise PosError(400, "expiry_date", "Expiry date must be YYYY-MM-DD.")
            if product["track_batches"] and kind in ("purchase", "wastage") and not batch_no:
                raise PosError(400, "batch_no", "This item is tracked by batch: enter the batch number.")
            if product["track_batches"] and kind == "count" and batch_no:
                current = sum(b["qty_milli"] for b in self.batch_balances(conn, business_id, product["id"])
                              if b["batch_no"] == batch_no)
            if kind == "count":
                delta = qty - current
            elif kind == "wastage":
                delta = -abs(qty)
            elif kind == "purchase":
                delta = abs(qty)
            else:
                delta = qty
            if kind != "count" and delta == 0:
                raise PosError(400, "qty", "Quantity must not be zero.")
            now = self.clock().isoformat()
            if batch_no and not expiry:
                known = conn.execute("SELECT expiry_date FROM pos_stock_moves WHERE business_id = ? AND product_id = ? AND"
                                     " batch_no = ? AND expiry_date IS NOT NULL LIMIT 1",
                                     (business_id, product["id"], batch_no)).fetchone()
                expiry = known["expiry_date"] if known else None
            cur = conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, reason, at,"
                               " created_by, client_txn_id, batch_no, expiry_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                               (business_id, product["id"], delta, kind, reason or kind, now, user, txn, batch_no, expiry))
            self._audit(conn, business_id, user, f"stock.{kind}", product["id"],
                        {"delta_milli": delta, "before_milli": current, "reason": reason}, now)
        return {"move_id": cur.lastrowid, "delta_milli": delta, "stock_milli": current + delta}

    def batches(self, business_id: str, user: str, product_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            today = self._local(self.clock())
            return [{**b, "expired": bool(b["expiry_date"] and b["expiry_date"] < today)}
                    for b in self.batch_balances(conn, business_id, product_id)]

    def expiry_report(self, business_id: str, user: str, days: int = 30) -> Dict[str, Any]:
        """Batches in stock that are expired or expire within ``days``."""
        days = max(0, min(int(days), 365))
        with self._connect() as conn:
            self._require(conn, business_id, user, "stock")
            today = self._local(self.clock())
            until = (datetime.fromisoformat(today) + timedelta(days=days)).date().isoformat()
            rows = conn.execute(
                "SELECT m.product_id, p.name, p.unit, m.batch_no, m.expiry_date, SUM(m.qty_milli) AS qty FROM pos_stock_moves m"
                " JOIN pos_products p ON p.id = m.product_id WHERE m.business_id = ? AND m.batch_no IS NOT NULL AND"
                " m.expiry_date IS NOT NULL GROUP BY m.product_id, m.batch_no, m.expiry_date HAVING SUM(m.qty_milli) > 0"
                " AND m.expiry_date <= ? ORDER BY m.expiry_date", (business_id, until)).fetchall()
        items = [{"product_id": r["product_id"], "name": r["name"], "unit": r["unit"], "batch_no": r["batch_no"],
                  "expiry_date": r["expiry_date"], "qty_milli": int(r["qty"]), "expired": r["expiry_date"] < today}
                 for r in rows]
        return {"today": today, "until": until, "items": items}

    def stock_moves(self, business_id: str, user: str, product_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "stock")
            rows = conn.execute("SELECT qty_milli, kind, ref_id, reason, at, batch_no, expiry_date FROM pos_stock_moves"
                                " WHERE business_id = ?"
                                " AND product_id = ? ORDER BY id", (business_id, product_id)).fetchall()
        balance = 0
        out = []
        for r in rows:
            balance += r["qty_milli"]
            out.append({**dict(r), "balance_milli": balance})
        return out

    # ------------------------------------------------------------- customers
    def add_customer(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 80)
        if not name:
            raise PosError(400, "name", "Customer name is required.")
        gstin = str(data.get("gstin") or "").strip().upper() or None
        state = str(data.get("state_code") or "").zfill(2) if data.get("state_code") else None
        if gstin:
            check = pos_tax.validate_gstin(gstin)
            if not check["valid"]:
                raise PosError(400, "gstin", f"Customer GSTIN is not valid ({check['reason']}).")
            state = check["state_code"]
        if state and state not in pos_tax.STATE_CODES:
            raise PosError(400, "state_code", "Unknown State code.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "customers")
            now = self.clock().isoformat()
            customer_id = _id("cus")
            conn.execute("INSERT INTO pos_customers (id, business_id, name, phone, gstin, address, state_code,"
                         " credit_limit_paise, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (customer_id, business_id, name, _clean(data.get("phone"), 20), gstin,
                          _clean(data.get("address"), 240), state, max(0, int(data.get("credit_limit_paise") or 0)),
                          now, now))
            self._audit(conn, business_id, user, "customer.add", customer_id, {"b2b": bool(gstin)}, now)
        return self.customer(business_id, user, customer_id)

    def _balance(self, conn: sqlite3.Connection, business_id: str, customer_id: str) -> int:
        row = conn.execute("SELECT COALESCE(SUM(debit_paise - credit_paise), 0) AS bal FROM pos_ledger"
                           " WHERE business_id = ? AND customer_id = ?", (business_id, customer_id)).fetchone()
        return int(row["bal"])

    def customer(self, business_id: str, user: str, customer_id: str) -> Dict[str, Any]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            row = conn.execute("SELECT * FROM pos_customers WHERE id = ? AND business_id = ?",
                               (customer_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "customer", "Customer not found.")
            out = dict(row)
            out["balance_paise"] = self._balance(conn, business_id, customer_id)
        return out

    def customers(self, business_id: str, user: str, query: str = "") -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            q = _clean(query, 60)
            rows = conn.execute(
                "SELECT c.*, COALESCE((SELECT SUM(debit_paise - credit_paise) FROM pos_ledger l WHERE l.business_id ="
                " c.business_id AND l.customer_id = c.id), 0) AS balance_paise FROM pos_customers c WHERE"
                " c.business_id = ? AND (? = '' OR c.name LIKE ? OR c.phone LIKE ?) ORDER BY c.name LIMIT 500",
                (business_id, q, f"%{q}%", f"%{q}%")).fetchall()
        return [dict(r) for r in rows]

    def set_customer_price(self, business_id: str, user: str, customer_id: str, product_id: str,
                           price_paise: Optional[int]) -> Dict[str, Any]:
        """A customer-specific rate (e.g. a restaurant's meat rate). ``None`` removes it."""
        with self._tx() as conn:
            self._require(conn, business_id, user, "products")
            for table, key in (("pos_customers", customer_id), ("pos_products", product_id)):
                if conn.execute(f"SELECT 1 FROM {table} WHERE id = ? AND business_id = ?", (key, business_id)).fetchone() is None:
                    raise PosError(404, "not_found", "Customer or item not found.")
            now = self.clock().isoformat()
            if price_paise is None:
                conn.execute("DELETE FROM pos_price_lists WHERE business_id = ? AND customer_id = ? AND product_id = ?",
                             (business_id, customer_id, product_id))
            else:
                if price_paise < 0:
                    raise PosError(400, "price", "Price cannot be negative.")
                conn.execute("INSERT INTO pos_price_lists (business_id, customer_id, product_id, price_paise, updated_by,"
                             " updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(business_id, customer_id, product_id)"
                             " DO UPDATE SET price_paise = excluded.price_paise, updated_by = excluded.updated_by,"
                             " updated_at = excluded.updated_at",
                             (business_id, customer_id, product_id, int(price_paise), user, now))
            self._audit(conn, business_id, user, "price_list.set", f"{customer_id}:{product_id}",
                        {"price_paise": price_paise}, now)
        return {"customer_id": customer_id, "product_id": product_id, "price_paise": price_paise}

    def customer_prices(self, business_id: str, user: str, customer_id: str) -> Dict[str, int]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            rows = conn.execute("SELECT product_id, price_paise FROM pos_price_lists WHERE business_id = ? AND"
                                " customer_id = ?", (business_id, customer_id)).fetchall()
        return {r["product_id"]: r["price_paise"] for r in rows}

    # ---------------------------------------------------------------- series
    def register_device_series(self, business_id: str, user: str, device_id: str) -> Dict[str, Any]:
        """Give an offline device its OWN invoice series so numbers stay consecutive and unique
        without the server (Rule 46 allows one or more series)."""
        device = _clean(device_id, 64)
        if len(device) < 6:
            raise PosError(400, "device", "Unknown device.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "sell")
            business = self._business_row(conn, business_id)
            fy = pos_tax.financial_year(self._local(self.clock()))
            row = conn.execute("SELECT prefix, next_number FROM pos_series WHERE business_id = ? AND device_id = ?"
                               " AND fy = ? AND kind = 'invoice'", (business_id, device, fy)).fetchone()
            if row is None:
                count = conn.execute("SELECT COUNT(*) AS n FROM pos_series WHERE business_id = ? AND fy = ? AND"
                                     " device_id IS NOT NULL", (business_id, fy)).fetchone()["n"]
                prefix = f"{business['invoice_prefix'][:1]}D{count + 1}"
                if not pos_tax.check_serial(f"{prefix}/{fy}/999999"):
                    raise PosError(400, "series", "Too many device series this year.")
                conn.execute("INSERT INTO pos_series (business_id, prefix, fy, next_number, device_id, kind)"
                             " VALUES (?, ?, ?, 1, ?, 'invoice')", (business_id, prefix, fy, device))
                row = {"prefix": prefix, "next_number": 1}
            self._audit(conn, business_id, user, "series.device", device[-6:], {"prefix": row["prefix"]},
                        self.clock().isoformat())
        return {"prefix": row["prefix"], "fy": fy, "next_number": row["next_number"]}

    def _next_number(self, conn: sqlite3.Connection, business_id: str, prefix: str, fy: str, kind: str) -> str:
        row = conn.execute("SELECT next_number FROM pos_series WHERE business_id = ? AND prefix = ? AND fy = ?",
                           (business_id, prefix, fy)).fetchone()
        number = row["next_number"] if row else 1
        if row is None:
            conn.execute("INSERT INTO pos_series (business_id, prefix, fy, next_number, kind) VALUES (?, ?, ?, 2, ?)",
                         (business_id, prefix, fy, kind))
        else:
            conn.execute("UPDATE pos_series SET next_number = ? WHERE business_id = ? AND prefix = ? AND fy = ?",
                         (number + 1, business_id, prefix, fy))
        try:
            return pos_tax.series_label(prefix, fy, number)
        except pos_tax.TaxError as error:
            raise PosError(400, error.code, error.message)

    def _device_number(self, conn: sqlite3.Connection, business_id: str, device_id: str, label: str, fy: str) -> str:
        """Accept an offline number only from the device's own series, unused, not beyond next."""
        match = re.fullmatch(r"([A-Z0-9]+)/(\d{4})/(\d{6})", label or "")
        if not match or match.group(2) != fy:
            raise PosError(400, "invoice_number", "Offline invoice number has the wrong format or year.")
        row = conn.execute("SELECT next_number FROM pos_series WHERE business_id = ? AND prefix = ? AND fy = ? AND"
                           " device_id = ?", (business_id, match.group(1), fy, device_id)).fetchone()
        if row is None:
            raise PosError(400, "invoice_number", "This device has no invoice series for that year; register it first.")
        number = int(match.group(3))
        if conn.execute("SELECT 1 FROM pos_invoices WHERE business_id = ? AND fy = ? AND number = ?",
                        (business_id, fy, label)).fetchone():
            raise PosError(409, "invoice_number", "That invoice number is already used.")
        if number >= row["next_number"]:
            conn.execute("UPDATE pos_series SET next_number = ? WHERE business_id = ? AND prefix = ? AND fy = ?",
                         (number + 1, business_id, match.group(1), fy))
        return label

    # -------------------------------------------------------------- invoices
    def _snapshot_business(self, business: sqlite3.Row) -> Dict[str, Any]:
        return {"name": business["name"], "address": business["address"], "phone": business["phone"],
                "gstin": business["gstin"], "state_code": business["state_code"],
                "state": pos_tax.STATE_CODES.get(business["state_code"], ""),
                "registration_type": business["registration_type"],
                "heading": pos_tax.RULES["composition_bill_heading"] if business["registration_type"] == "composition" else ""}

    def _issue_time(self, data: Dict[str, Any]) -> datetime:
        now = self.clock()
        raw = data.get("issued_at")
        if not raw or not data.get("offline"):
            return now
        try:
            at = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        except ValueError:
            raise PosError(400, "issued_at", "issued_at is not a date-time.")
        if at.tzinfo is None:
            at = at.replace(tzinfo=IST)
        if at > now + timedelta(minutes=5) or now - at > MAX_OFFLINE_AGE:
            raise PosError(400, "issued_at", "Offline sale time is in the future or older than 7 days.")
        return at

    def create_invoice(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        digest = _digest({k: data.get(k) for k in ("lines", "customer_id", "payments", "place_of_supply",
                                                   "invoice_number", "device_id")})
        with self._tx() as conn:
            role = self._require(conn, business_id, user, "sell")
            seen = conn.execute("SELECT id, payload_digest FROM pos_invoices WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                if seen["payload_digest"] != digest:
                    raise PosError(409, "client_txn_id", "This transaction id was already used for a different sale.")
                invoice_id = seen["id"]
                replay = True
            else:
                invoice_id = self._issue(conn, business_id, user, role, data, txn, digest)
                replay = False
        out = self.invoice(business_id, user, invoice_id)
        out["replayed"] = replay
        return out

    def _issue(self, conn: sqlite3.Connection, business_id: str, user: str, role: str, data: Dict[str, Any],
               txn: str, digest: str) -> str:
        business = self._business_row(conn, business_id)
        customer = None
        if data.get("customer_id"):
            customer = conn.execute("SELECT * FROM pos_customers WHERE id = ? AND business_id = ?",
                                    (data["customer_id"], business_id)).fetchone()
            if customer is None:
                raise PosError(404, "customer", "Customer not found.")
        raw_lines = list(data.get("lines") or [])
        if not raw_lines or len(raw_lines) > 300:
            raise PosError(400, "lines", "Add 1-300 items.")
        prices = {}
        if customer is not None:
            prices = {r["product_id"]: r["price_paise"] for r in conn.execute(
                "SELECT product_id, price_paise FROM pos_price_lists WHERE business_id = ? AND customer_id = ?",
                (business_id, customer["id"]))}
        lines: List[Dict[str, Any]] = []
        for index, raw in enumerate(raw_lines, start=1):
            product = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ? AND active = 1",
                                   (raw.get("product_id"), business_id)).fetchone()
            if product is None:
                raise PosError(400, "product", f"Item on line {index} is not in this shop's active list.")
            pack = None
            if raw.get("pack"):
                pack = conn.execute("SELECT * FROM pos_product_packs WHERE business_id = ? AND product_id = ? AND name = ?",
                                    (business_id, product["id"], str(raw["pack"]))).fetchone()
                if pack is None:
                    raise PosError(400, "pack", f"Line {index}: {product['name']} has no '{raw['pack']}' unit.")
            if pack is not None:
                listed = pack["price_paise"] if pack["price_paise"] is not None else \
                    _round_div(product["price_paise"] * pack["factor_milli"], 1000)
                source = "pack_price"
            else:
                listed = prices.get(product["id"], product["price_paise"])
                source = "customer_rate" if product["id"] in prices else "item_price"
            weight = raw.get("weight") if isinstance(raw.get("weight"), dict) else None
            qty = int(raw.get("qty_milli") or 0)
            if weight:
                gross, tare = int(weight.get("gross_milli") or 0), int(weight.get("tare_milli") or 0)
                if gross <= 0 or tare < 0 or tare >= gross:
                    raise PosError(400, "weight", f"Line {index}: gross weight must be more than tare.")
                qty = gross - tare
                weight = {"gross_milli": gross, "tare_milli": tare, "net_milli": qty,
                          "source": "scale_unverified" if weight.get("source") == "scale" else "typed",
                          "live_weight_milli": int(weight.get("live_weight_milli") or 0) or None}
            if qty <= 0 and not weight:
                raise PosError(400, "qty", f"Line {index}: quantity must be more than zero.")
            base_qty = qty
            if pack is not None:
                if (qty * pack["factor_milli"]) % 1000:
                    raise PosError(400, "qty", f"Line {index}: that many {pack['name']} is not a whole {product['unit']} count.")
                base_qty = qty * pack["factor_milli"] // 1000
            if pack is None and source == "item_price":
                # Rate by quantity (the shop's own tiers) is the listed price for this many.
                tier = self.tier_price(self._tiers(conn, business_id).get(product["id"], []), base_qty)
                if tier is not None and tier != listed:
                    listed, source = tier, "quantity_rate"
            price = int(raw["unit_price_paise"]) if raw.get("unit_price_paise") is not None else listed
            if price != listed:
                if "price_override" not in PERMISSIONS[role]:
                    raise PosError(403, "price_override", f"Line {index}: only a manager / owner can change the price.")
                source = "manual_override"
            if product["min_qty_milli"] and base_qty < product["min_qty_milli"]:
                raise PosError(400, "min_qty", f"Line {index}: the least you sell of {product['name']} is "
                                               f"{product['min_qty_milli'] / 1000:g} {product['unit']}.",
                               min_qty_milli=product["min_qty_milli"])
            serials: List[str] = []
            if product["track_serials"]:
                serials = [_clean(x, 40).upper() for x in (raw.get("serials") or []) if _clean(x, 40)]
                if base_qty % 1000 or len(serials) != base_qty // 1000 or len(set(serials)) != len(serials):
                    raise PosError(400, "serials", f"Line {index}: {product['name']} needs one serial / IMEI per piece "
                                                   f"({base_qty // 1000} expected).")
                for sn in serials:
                    row = conn.execute("SELECT status FROM pos_serials WHERE business_id = ? AND product_id = ? AND serial = ?",
                                       (business_id, product["id"], sn)).fetchone()
                    if row is None or row["status"] != "in_stock":
                        raise PosError(409, "serial_not_in_stock", f"Line {index}: {sn} is not in stock for {product['name']}.")
            lines.append({"line_no": index, "product_id": product["id"], "name": product["name"],
                          "hsn_sac": product["hsn_sac"], "unit": pack["name"] if pack is not None else product["unit"],
                          "qty_milli": qty, "pack": pack["name"] if pack is not None else None, "base_qty_milli": base_qty,
                          "serials": serials,
                          "unit_price_paise": price, "price_source": source,
                          "discount_paise": int(raw.get("discount_paise") or 0), "rate_bp": product["rate_bp"],
                          "cess_bp": product["cess_bp"], "category": product["category"],
                          "price_includes_tax": bool(product["price_includes_tax"]), "weight": weight,
                          "track_stock": bool(product["track_stock"]), "track_batches": bool(product["track_batches"])})
        place = data.get("place_of_supply")
        if place:
            place = str(place).zfill(2)
        elif customer is not None and customer["gstin"] and data.get("bill_to_customer_state"):
            place = customer["state_code"]
        try:
            computed = pos_tax.invoice_totals(lines, registration_type=business["registration_type"],
                                              business_state=business["state_code"], place_of_supply=place,
                                              round_off=bool(business["round_off"]))
        except pos_tax.TaxError as error:
            raise PosError(400, error.code, error.message)
        totals = computed["totals"]
        grand = totals["grand_total_paise"]
        problems = self._hsn_problems(business, customer, computed)
        if problems:
            raise PosError(400, "hsn_sac", "HSN / SAC needed on this tax invoice (Notification 78/2020-CT) for: " +
                           ", ".join(problems) + ". Enter the code from your own classification.", items=problems)
        need = pos_tax.recipient_requirements(recipient_gstin=customer["gstin"] if customer else None,
                                              total_paise=grand, mode=computed["mode"])
        if need:
            missing = [f for f in need if not self._customer_has(customer, f)]
            if missing:
                raise PosError(400, "recipient", "This invoice needs the customer's " + ", ".join(missing) +
                               " (Rule 46).", missing=missing)
        payments = list(data.get("payments") or [])
        paid = 0
        for p in payments:
            if p.get("method") not in PAY_METHODS:
                raise PosError(400, "payment", "Payment method must be cash, upi, card, bank_transfer or cheque.")
            amount = int(p.get("amount_paise") or 0)
            if amount <= 0:
                raise PosError(400, "payment", "Payment amounts must be positive.")
            paid += amount
        if paid > grand:
            raise PosError(400, "payment", "Payments are more than the bill. Enter the amount applied, not the cash tendered.")
        balance = grand - paid
        if balance > 0:
            if customer is None:
                raise PosError(400, "balance", "The bill is not fully paid: choose a customer to put the balance on credit.")
            limit = customer["credit_limit_paise"]
            if limit and self._balance(conn, business_id, customer["id"]) + balance > limit:
                raise PosError(400, "credit_limit", "This sale would cross the customer's credit limit.")
        at = self._issue_time(data)
        local_date = self._local(at)
        fy = pos_tax.financial_year(local_date)
        device = _clean(data.get("device_id"), 64) or None
        if data.get("invoice_number"):
            if not device:
                raise PosError(400, "device", "An offline invoice number needs the device id.")
            number = self._device_number(conn, business_id, device, str(data["invoice_number"]), fy)
            prefix = number.split("/")[0]
        else:
            prefix = business["invoice_prefix"] if computed["document_type"] != "bill_of_supply" else \
                business["invoice_prefix"] + "B"
            number = self._next_number(conn, business_id, prefix, fy, "invoice")
        now = self.clock().isoformat()
        invoice_id = _id("inv")
        snap_customer = self._snapshot_customer(customer)
        conn.execute(
            "INSERT INTO pos_invoices (id, business_id, doc_kind, document_type, number, series, fy, issued_at, local_date,"
            " customer_id, customer_snapshot, business_snapshot, place_of_supply, mode, totals, rate_summary,"
            " rules_version, status, client_txn_id, payload_digest, created_by, device_id, offline, synced_at,"
            " paid_paise, balance_paise, notes) VALUES (?, ?, 'invoice', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,"
            " 'issued', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (invoice_id, business_id, computed["document_type"], number, prefix, fy, at.isoformat(), local_date,
             customer["id"] if customer else None, json.dumps(snap_customer),
             json.dumps(self._snapshot_business(business)), computed["place_of_supply"], computed["mode"],
             json.dumps({**totals, "state_tax_label": computed["state_tax_label"]}),
             json.dumps(pos_tax.rate_summary(computed["lines"])), computed["rules_version"], txn, digest, user,
             device, 1 if data.get("offline") else 0, now, paid, balance, _clean(data.get("notes"), 240)))
        for line in computed["lines"]:
            if line.get("track_batches"):
                line["batches"] = self._allocate_batches(conn, business_id, line, local_date)
            self._insert_line(conn, invoice_id, line)
            if line.get("batches"):
                for b in line["batches"]:
                    conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                                 " created_by, batch_no, expiry_date) VALUES (?, ?, ?, 'sale', ?, ?, ?, ?, ?, ?)",
                                 (business_id, line["product_id"], -b["qty_milli"], invoice_id, number, now, user,
                                  b["batch_no"], b["expiry_date"]))
            elif line["track_stock"]:
                conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                             " created_by) VALUES (?, ?, ?, 'sale', ?, ?, ?, ?)",
                             (business_id, line["product_id"], -line.get("base_qty_milli", line["qty_milli"]), invoice_id,
                              number, now, user))
            for sn in line.get("serials") or []:
                conn.execute("UPDATE pos_serials SET status = 'sold', invoice_id = ?, updated_at = ? WHERE business_id = ?"
                             " AND product_id = ? AND serial = ?", (invoice_id, now, business_id, line["product_id"], sn))
        for p in payments:
            self._insert_payment(conn, business_id, invoice_id, customer["id"] if customer else None, p["method"],
                                 int(p["amount_paise"]), p.get("reference"), "sale", user, at)
        if customer is not None:
            self._ledger(conn, business_id, customer["id"], "invoice", invoice_id, debit=grand, at=at, note=number,
                         user=user)
            if paid:
                self._ledger(conn, business_id, customer["id"], "payment", invoice_id, credit=paid, at=at,
                             note=f"paid with {number}", user=user)
        closed = conn.execute("SELECT 1 FROM pos_day_close WHERE business_id = ? AND local_date = ?",
                              (business_id, local_date)).fetchone()
        self._audit(conn, business_id, user, "invoice.issue", invoice_id,
                    {"number": number, "total_paise": grand, "offline": bool(data.get("offline")),
                     "after_day_close": bool(closed), "price_overrides": [l["line_no"] for l in lines
                                                                         if l["price_source"] == "manual_override"]}, now)
        return invoice_id

    def batch_balances(self, conn: sqlite3.Connection, business_id: str, product_id: str) -> List[Dict[str, Any]]:
        rows = conn.execute("SELECT batch_no, expiry_date, SUM(qty_milli) AS qty FROM pos_stock_moves WHERE business_id = ?"
                            " AND product_id = ? AND batch_no IS NOT NULL GROUP BY batch_no, expiry_date"
                            " HAVING SUM(qty_milli) > 0 ORDER BY COALESCE(expiry_date, '9999-12-31'), batch_no",
                            (business_id, product_id)).fetchall()
        return [{"batch_no": r["batch_no"], "expiry_date": r["expiry_date"], "qty_milli": int(r["qty"])} for r in rows]

    def _allocate_batches(self, conn: sqlite3.Connection, business_id: str, line: Dict[str, Any],
                          local_date: str) -> List[Dict[str, Any]]:
        """First-expiry-first-out from batches that are NOT expired on the sale date (an expiry
        date is the last day it may be sold). Expired stock is never sold; when only expired stock
        is left the sale is refused. No batch stock at all -> no allocation (the line is still
        sold and the stock goes negative, as for any tracked item)."""
        need = int(line.get("base_qty_milli") or line["qty_milli"])
        batches = self.batch_balances(conn, business_id, line["product_id"])
        usable = [b for b in batches if not b["expiry_date"] or b["expiry_date"] >= local_date]
        expired = [b for b in batches if b["expiry_date"] and b["expiry_date"] < local_date]
        out: List[Dict[str, Any]] = []
        for b in usable:
            if need <= 0:
                break
            take = min(need, b["qty_milli"])
            out.append({"batch_no": b["batch_no"], "expiry_date": b["expiry_date"], "qty_milli": take})
            need -= take
        if need > 0 and expired and sum(b["qty_milli"] for b in usable) == 0:
            raise PosError(409, "expired_stock", f"{line['name']}: only expired stock is left (batch "
                           f"{expired[0]['batch_no']}, expired {expired[0]['expiry_date']}). It cannot be sold.")
        if need > 0 and out:
            out.append({"batch_no": None, "expiry_date": None, "qty_milli": need})
        return out

    @staticmethod
    def _hsn_problems(business: sqlite3.Row, customer: Optional[sqlite3.Row], computed: Dict[str, Any]) -> List[str]:
        """Up to Rs 5 crore: 4 digits, optional on B2C invoices; above: 6 digits on every invoice."""
        if computed["document_type"] != "tax_invoice":
            return []
        above = bool(business["turnover_above_5cr"])
        b2b = bool(customer is not None and customer["gstin"])
        if not above and not b2b:
            return []
        need = pos_tax.RULES["hsn_digits"]["above_5cr" if above else "upto_5cr"]
        return [l["name"] for l in computed["lines"] if l["category"] == "taxable" and len(l["hsn_sac"] or "") < need]

    @staticmethod
    def _customer_has(customer: Optional[sqlite3.Row], field: str) -> bool:
        if customer is None:
            return False
        if field in ("name", "address"):
            return bool(customer[field])
        if field == "delivery_address":
            return bool(customer["address"])
        if field == "state_code":
            return bool(customer["state_code"])
        return False

    @staticmethod
    def _snapshot_customer(customer: Optional[sqlite3.Row]) -> Dict[str, Any]:
        if customer is None:
            return {"name": "Walk-in customer"}
        return {"name": customer["name"], "gstin": customer["gstin"], "address": customer["address"],
                "state_code": customer["state_code"], "state": pos_tax.STATE_CODES.get(customer["state_code"] or "", ""),
                "phone_last4": (customer["phone"] or "")[-4:]}

    @staticmethod
    def _insert_line(conn: sqlite3.Connection, invoice_id: str, line: Dict[str, Any]) -> None:
        conn.execute(
            "INSERT INTO pos_invoice_lines (invoice_id, line_no, product_id, name, hsn_sac, unit, qty_milli,"
            " unit_price_paise, price_source, discount_paise, rate_bp, cess_bp, category, price_includes_tax,"
            " taxable_paise, cgst_paise, sgst_paise, igst_paise, cess_paise, total_paise, weight, original_line_no)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (invoice_id, line["line_no"], line.get("product_id"), line["name"], line["hsn_sac"], line["unit"],
             line["qty_milli"], line["unit_price_paise"], line.get("price_source", "item_price"),
             line["discount_paise"], line["rate_bp"], line["cess_bp"], line["category"],
             1 if line["price_includes_tax"] else 0, line["taxable_paise"], line["cgst_paise"], line["sgst_paise"],
             line["igst_paise"], line["cess_paise"], line["total_paise"],
             json.dumps(line["weight"]) if line.get("weight") else None, line.get("original_line_no")))
        if line.get("batches"):
            conn.execute("UPDATE pos_invoice_lines SET batches = ? WHERE invoice_id = ? AND line_no = ?",
                         (json.dumps(line["batches"]), invoice_id, line["line_no"]))
        if line.get("pack") or line.get("serials") or line.get("base_qty_milli") not in (None, line["qty_milli"]):
            conn.execute("UPDATE pos_invoice_lines SET pack = ?, base_qty_milli = ?, serials = ? WHERE invoice_id = ? AND"
                         " line_no = ?", (line.get("pack"), line.get("base_qty_milli"),
                                          json.dumps(line["serials"]) if line.get("serials") else None, invoice_id,
                                          line["line_no"]))

    def _insert_payment(self, conn: sqlite3.Connection, business_id: str, invoice_id: Optional[str],
                        customer_id: Optional[str], method: str, amount: int, reference: Any, kind: str, user: str,
                        at: datetime, txn: Optional[str] = None) -> str:
        payment_id = _id("pay")
        conn.execute("INSERT INTO pos_payments (id, business_id, invoice_id, customer_id, method, amount_paise,"
                     " verification, reference, kind, received_by, at, local_date, client_txn_id)"
                     " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     (payment_id, business_id, invoice_id, customer_id, method, amount, VERIFICATION[method],
                      _clean(reference, 60), kind, user, at.isoformat(), self._local(at), txn))
        return payment_id

    def _ledger(self, conn: sqlite3.Connection, business_id: str, customer_id: str, kind: str, ref: str, *,
                at: datetime, user: str, debit: int = 0, credit: int = 0, note: str = "") -> None:
        conn.execute("INSERT INTO pos_ledger (business_id, customer_id, kind, ref_id, debit_paise, credit_paise, at,"
                     " local_date, note, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     (business_id, customer_id, kind, ref, debit, credit, at.isoformat(), self._local(at), note, user))

    def invoice(self, business_id: str, user: str, invoice_id: str) -> Dict[str, Any]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            row = conn.execute("SELECT * FROM pos_invoices WHERE id = ? AND business_id = ?",
                               (invoice_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "invoice", "Invoice not found.")
            lines = conn.execute("SELECT * FROM pos_invoice_lines WHERE invoice_id = ? ORDER BY line_no",
                                 (invoice_id,)).fetchall()
            payments = conn.execute("SELECT method, amount_paise, verification, reference, kind, at FROM pos_payments"
                                    " WHERE invoice_id = ? ORDER BY at", (invoice_id,)).fetchall()
            credits = conn.execute("SELECT id, number, issued_at FROM pos_invoices WHERE original_invoice_id = ? AND"
                                   " status = 'issued'", (invoice_id,)).fetchall()
            original = None
            if row["original_invoice_id"]:
                o = conn.execute("SELECT number, issued_at FROM pos_invoices WHERE id = ?",
                                 (row["original_invoice_id"],)).fetchone()
                original = {"id": row["original_invoice_id"], "number": o["number"], "issued_at": o["issued_at"]}
        out = dict(row)
        out.pop("payload_digest", None)
        for key in ("customer_snapshot", "business_snapshot", "totals", "rate_summary"):
            out[key] = json.loads(out[key])
        out["offline"] = bool(out["offline"])
        out["lines"] = []
        for line in lines:
            item = dict(line)
            item["price_includes_tax"] = bool(item["price_includes_tax"])
            item["weight"] = json.loads(item["weight"]) if item["weight"] else None
            item["batches"] = json.loads(item["batches"]) if item.get("batches") else None
            item["serials"] = json.loads(item["serials"]) if item.get("serials") else None
            out["lines"].append(item)
        out["payments"] = [dict(p) for p in payments]
        out["credit_notes"] = [dict(c) for c in credits]
        out["original_invoice"] = original
        out["title"] = {"tax_invoice": "Tax Invoice", "bill_of_supply": "Bill of Supply", "bill": "Bill",
                        "credit_note": "Credit Note"}[out["document_type"]]
        return out

    def invoices(self, business_id: str, user: str, *, date_from: str = "", date_to: str = "",
                 customer_id: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            sql = ("SELECT id, doc_kind, document_type, number, issued_at, local_date, customer_id, customer_snapshot,"
                   " totals, status, paid_paise, balance_paise, offline FROM pos_invoices WHERE business_id = ?")
            args: List[Any] = [business_id]
            if date_from:
                sql += " AND local_date >= ?"
                args.append(date_from)
            if date_to:
                sql += " AND local_date <= ?"
                args.append(date_to)
            if customer_id:
                sql += " AND customer_id = ?"
                args.append(customer_id)
            rows = conn.execute(sql + " ORDER BY issued_at DESC LIMIT ?", (*args, max(1, min(limit, 1000)))).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            item["customer_name"] = json.loads(item.pop("customer_snapshot")).get("name")
            item["grand_total_paise"] = json.loads(item.pop("totals"))["grand_total_paise"]
            item["offline"] = bool(item["offline"])
            out.append(item)
        return out

    # ---------------------------------------------------------- credit notes
    def create_credit_note(self, business_id: str, user: str, invoice_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Return / correction against an issued invoice. Uses the ORIGINAL line's price, tax rate
        and supply mode; quantities cannot exceed what is still un-credited."""
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        reason = _clean(data.get("reason"), 160)
        if not reason:
            raise PosError(400, "reason", "Say why (return / damaged / wrong rate ...).")
        digest = _digest({"invoice": invoice_id, "lines": data.get("lines"), "refund": data.get("refund")})
        with self._tx() as conn:
            self._require(conn, business_id, user, "return")
            seen = conn.execute("SELECT id, payload_digest FROM pos_invoices WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                if seen["payload_digest"] != digest:
                    raise PosError(409, "client_txn_id", "This transaction id was already used.")
                note_id, replay = seen["id"], True
            else:
                note_id, replay = self._credit(conn, business_id, user, invoice_id, data, txn, digest, reason), False
        out = self.invoice(business_id, user, note_id)
        out["replayed"] = replay
        return out

    def _credit(self, conn: sqlite3.Connection, business_id: str, user: str, invoice_id: str, data: Dict[str, Any],
                txn: str, digest: str, reason: str) -> str:
        business = self._business_row(conn, business_id)
        original = conn.execute("SELECT * FROM pos_invoices WHERE id = ? AND business_id = ? AND doc_kind = 'invoice'",
                                (invoice_id, business_id)).fetchone()
        if original is None:
            raise PosError(404, "invoice", "Invoice not found.")
        if original["status"] != "issued":
            raise PosError(409, "status", "A cancelled invoice cannot get a credit note.")
        orig_lines = {r["line_no"]: r for r in conn.execute("SELECT * FROM pos_invoice_lines WHERE invoice_id = ?",
                                                             (invoice_id,))}
        credited: Dict[int, int] = {}
        for r in conn.execute("SELECT l.original_line_no, SUM(l.qty_milli) AS q FROM pos_invoice_lines l JOIN"
                              " pos_invoices i ON i.id = l.invoice_id WHERE i.original_invoice_id = ? AND"
                              " i.status = 'issued' GROUP BY l.original_line_no", (invoice_id,)):
            credited[r["original_line_no"]] = r["q"]
        lines: List[Dict[str, Any]] = []
        for n, raw in enumerate(data.get("lines") or [], start=1):
            src = orig_lines.get(int(raw.get("line_no") or 0))
            if src is None:
                raise PosError(400, "line", "Unknown line on the original invoice.")
            qty = int(raw.get("qty_milli") or 0)
            left = src["qty_milli"] - credited.get(src["line_no"], 0)
            if qty <= 0 or qty > left:
                raise PosError(400, "qty", f"Line {src['line_no']}: at most {left / 1000:g} {src['unit']} can be credited.")
            discount = int(round(src["discount_paise"] * qty / src["qty_milli"]))
            src_base = src["base_qty_milli"] if src["base_qty_milli"] is not None else src["qty_milli"]
            if (qty * src_base) % src["qty_milli"]:
                raise PosError(400, "qty", f"Line {src['line_no']}: return a whole number of {src['unit']}.")
            base_qty = qty * src_base // src["qty_milli"]
            sold_serials = json.loads(src["serials"]) if src["serials"] else []
            back_serials: List[str] = []
            if sold_serials:
                back_serials = [_clean(x, 40).upper() for x in (raw.get("serials") or [])]
                still_sold = {r["serial"] for r in conn.execute(
                    "SELECT serial FROM pos_serials WHERE business_id = ? AND product_id = ? AND status = 'sold' AND"
                    " invoice_id = ?", (business_id, src["product_id"], invoice_id))}
                if len(back_serials) != base_qty // 1000 or len(set(back_serials)) != len(back_serials) or \
                        any(sn not in sold_serials or sn not in still_sold for sn in back_serials):
                    raise PosError(400, "serials", f"Line {src['line_no']}: choose which serial / IMEI numbers came back "
                                                   f"({base_qty // 1000} from this bill).")
            lines.append({"line_no": n, "original_line_no": src["line_no"], "product_id": src["product_id"],
                          "pack": src["pack"], "base_qty_milli": base_qty, "serials": back_serials,
                          "name": src["name"], "hsn_sac": src["hsn_sac"], "unit": src["unit"], "qty_milli": qty,
                          "unit_price_paise": src["unit_price_paise"], "price_source": "original_invoice",
                          "discount_paise": discount, "rate_bp": src["rate_bp"], "cess_bp": src["cess_bp"],
                          "category": src["category"], "price_includes_tax": bool(src["price_includes_tax"]),
                          "weight": None, "restock": bool(raw.get("restock", True)),
                          "source_batches": json.loads(src["batches"]) if src["batches"] else []})
        if not lines:
            raise PosError(400, "lines", "Choose the items to credit.")
        snap_business = json.loads(original["business_snapshot"])
        try:
            computed = pos_tax.invoice_totals(lines, registration_type=snap_business["registration_type"],
                                              business_state=snap_business["state_code"],
                                              place_of_supply=original["place_of_supply"], round_off=False)
        except pos_tax.TaxError as error:
            raise PosError(400, error.code, error.message)
        total = computed["totals"]["grand_total_paise"]
        refund = data.get("refund") if isinstance(data.get("refund"), dict) else None
        refund_amount = int(refund.get("amount_paise") or 0) if refund else 0
        if refund and refund.get("method") not in PAY_METHODS:
            raise PosError(400, "refund", "Refund method must be cash, upi, card, bank_transfer or cheque.")
        if refund_amount < 0 or refund_amount > total:
            raise PosError(400, "refund", "Refund cannot be more than the credit note.")
        if original["customer_id"] is None and refund_amount != total:
            raise PosError(400, "refund", "A walk-in sale's return must be refunded in full.")
        at = self.clock()
        fy = pos_tax.financial_year(self._local(at))
        prefix = business["invoice_prefix"] + "C"
        number = self._next_number(conn, business_id, prefix, fy, "credit_note")
        now = at.isoformat()
        note_id = _id("crn")
        conn.execute(
            "INSERT INTO pos_invoices (id, business_id, doc_kind, document_type, number, series, fy, issued_at, local_date,"
            " customer_id, customer_snapshot, business_snapshot, place_of_supply, mode, totals, rate_summary,"
            " rules_version, status, original_invoice_id, reason, client_txn_id, payload_digest, created_by, offline,"
            " synced_at, paid_paise, balance_paise) VALUES (?, ?, 'credit_note', 'credit_note', ?, ?, ?, ?, ?, ?, ?, ?,"
            " ?, ?, ?, ?, ?, 'issued', ?, ?, ?, ?, ?, 0, ?, ?, 0)",
            (note_id, business_id, number, prefix, fy, now, self._local(at), original["customer_id"],
             original["customer_snapshot"], original["business_snapshot"], original["place_of_supply"],
             computed["mode"], json.dumps({**computed["totals"], "state_tax_label": computed["state_tax_label"]}),
             json.dumps(pos_tax.rate_summary(computed["lines"])), original["rules_version"], invoice_id, reason, txn,
             digest, user, now, refund_amount))
        for line in computed["lines"]:
            self._insert_line(conn, note_id, line)
            product = conn.execute("SELECT track_stock FROM pos_products WHERE id = ?", (line["product_id"],)).fetchone()
            if line["restock"] and product is not None and product["track_stock"]:
                # Returned goods go back to the batches they were sold from (same order).
                left = line.get("base_qty_milli") or line["qty_milli"]
                for b in line.get("source_batches") or []:
                    if left <= 0:
                        break
                    take = min(left, int(b["qty_milli"]))
                    conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                                 " created_by, batch_no, expiry_date) VALUES (?, ?, ?, 'return', ?, ?, ?, ?, ?, ?)",
                                 (business_id, line["product_id"], take, note_id, number, now, user, b.get("batch_no"),
                                  b.get("expiry_date")))
                    left -= take
                if left > 0:
                    conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                                 " created_by) VALUES (?, ?, ?, 'return', ?, ?, ?, ?)",
                                 (business_id, line["product_id"], left, note_id, number, now, user))
            # A returned serial goes back on the shelf only when the goods are restocked.
            for sn in line.get("serials") or []:
                conn.execute("UPDATE pos_serials SET status = ?, updated_at = ? WHERE business_id = ? AND product_id = ?"
                             " AND serial = ?", ("in_stock" if line["restock"] else "returned", now, business_id,
                                                 line["product_id"], sn))
        if refund_amount:
            self._insert_payment(conn, business_id, note_id, original["customer_id"], refund["method"], -refund_amount,
                                 refund.get("reference"), "refund", user, at)
        if original["customer_id"]:
            self._ledger(conn, business_id, original["customer_id"], "credit_note", note_id, credit=total, at=at,
                         note=f"{number} against {original['number']}", user=user)
            if refund_amount:
                self._ledger(conn, business_id, original["customer_id"], "refund", note_id, debit=refund_amount, at=at,
                             note=f"refund {number}", user=user)
        self._audit(conn, business_id, user, "credit_note.issue", note_id,
                    {"number": number, "against": original["number"], "total_paise": total, "reason": reason}, now)
        return note_id

    def cancel_invoice(self, business_id: str, user: str, invoice_id: str, reason: str) -> Dict[str, Any]:
        """Same-day, before day close, without credit notes. The row stays (status cancelled)
        and reversing stock / ledger / payment entries are posted."""
        reason = _clean(reason, 160)
        if not reason:
            raise PosError(400, "reason", "Say why the invoice is cancelled.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "cancel")
            row = conn.execute("SELECT * FROM pos_invoices WHERE id = ? AND business_id = ? AND doc_kind = 'invoice'",
                               (invoice_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "invoice", "Invoice not found.")
            if row["status"] != "issued":
                raise PosError(409, "status", "Already cancelled.")
            at = self.clock()
            if row["local_date"] != self._local(at):
                raise PosError(409, "cancel_window", "Only today's invoices can be cancelled; issue a credit note instead.")
            if conn.execute("SELECT 1 FROM pos_day_close WHERE business_id = ? AND local_date = ?",
                            (business_id, row["local_date"])).fetchone():
                raise PosError(409, "day_closed", "The day is closed; issue a credit note instead.")
            if conn.execute("SELECT 1 FROM pos_invoices WHERE original_invoice_id = ? AND status = 'issued'",
                            (invoice_id,)).fetchone():
                raise PosError(409, "has_credit_note", "This invoice already has a credit note.")
            now = at.isoformat()
            conn.execute("UPDATE pos_invoices SET status = 'cancelled', cancel_reason = ?, cancelled_by = ?,"
                         " cancelled_at = ? WHERE id = ?", (reason, user, now, invoice_id))
            for move in conn.execute("SELECT product_id, qty_milli, batch_no, expiry_date FROM pos_stock_moves WHERE"
                                     " ref_id = ? AND kind = 'sale'", (invoice_id,)).fetchall():
                conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                             " created_by, batch_no, expiry_date) VALUES (?, ?, ?, 'cancel', ?, ?, ?, ?, ?, ?)",
                             (business_id, move["product_id"], -move["qty_milli"], invoice_id, reason, now, user,
                              move["batch_no"], move["expiry_date"]))
            conn.execute("UPDATE pos_serials SET status = 'in_stock', invoice_id = NULL, updated_at = ? WHERE business_id = ?"
                         " AND invoice_id = ? AND status = 'sold'", (now, business_id, invoice_id))
            for pay in conn.execute("SELECT method, amount_paise, customer_id FROM pos_payments WHERE invoice_id = ? AND"
                                    " kind = 'sale'", (invoice_id,)).fetchall():
                self._insert_payment(conn, business_id, invoice_id, pay["customer_id"], pay["method"],
                                     -pay["amount_paise"], "cancelled", "reversal", user, at)
            if row["customer_id"]:
                totals = json.loads(row["totals"])
                self._ledger(conn, business_id, row["customer_id"], "cancel", invoice_id,
                             credit=totals["grand_total_paise"], at=at, note=f"cancelled {row['number']}", user=user)
                if row["paid_paise"]:
                    self._ledger(conn, business_id, row["customer_id"], "cancel_payment", invoice_id,
                                 debit=row["paid_paise"], at=at, note=f"payment returned {row['number']}", user=user)
            self._audit(conn, business_id, user, "invoice.cancel", invoice_id, {"number": row["number"], "reason": reason}, now)
        return self.invoice(business_id, user, invoice_id)

    # -------------------------------------------------------------- payments
    def collect(self, business_id: str, user: str, customer_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Money received against a customer's running balance (credit sales)."""
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        method = data.get("method")
        if method not in PAY_METHODS:
            raise PosError(400, "payment", "Payment method must be cash, upi, card, bank_transfer or cheque.")
        amount = int(data.get("amount_paise") or 0)
        if amount <= 0:
            raise PosError(400, "amount", "Amount must be positive.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "collect")
            if conn.execute("SELECT 1 FROM pos_customers WHERE id = ? AND business_id = ?",
                            (customer_id, business_id)).fetchone() is None:
                raise PosError(404, "customer", "Customer not found.")
            seen = conn.execute("SELECT id FROM pos_payments WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                return {"replayed": True, "payment_id": seen["id"], "balance_paise": self._balance(conn, business_id, customer_id)}
            at = self.clock()
            payment_id = self._insert_payment(conn, business_id, None, customer_id, method, amount, data.get("reference"),
                                              "collection", user, at, txn)
            self._ledger(conn, business_id, customer_id, "payment", payment_id, credit=amount, at=at,
                         note=f"received ({method})", user=user)
            self._audit(conn, business_id, user, "payment.collect", payment_id,
                        {"amount_paise": amount, "method": method, "verification": VERIFICATION[method]}, at.isoformat())
            balance = self._balance(conn, business_id, customer_id)
        return {"payment_id": payment_id, "verification": VERIFICATION[method], "balance_paise": balance,
                "replayed": False}

    def statement(self, business_id: str, user: str, customer_id: str, month: str) -> Dict[str, Any]:
        """Monthly statement: opening balance, every entry with a running balance, closing."""
        if not re.fullmatch(r"\d{4}-\d{2}", month or ""):
            raise PosError(400, "month", "month must be YYYY-MM.")
        start = f"{month}-01"
        year, mon = int(month[:4]), int(month[5:])
        end = f"{year + (mon // 12)}-{(mon % 12) + 1:02d}-01"
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            customer = conn.execute("SELECT name, gstin, address FROM pos_customers WHERE id = ? AND business_id = ?",
                                    (customer_id, business_id)).fetchone()
            if customer is None:
                raise PosError(404, "customer", "Customer not found.")
            opening = conn.execute("SELECT COALESCE(SUM(debit_paise - credit_paise), 0) AS b FROM pos_ledger WHERE"
                                   " business_id = ? AND customer_id = ? AND local_date < ?",
                                   (business_id, customer_id, start)).fetchone()["b"]
            rows = conn.execute("SELECT kind, ref_id, debit_paise, credit_paise, at, local_date, note FROM pos_ledger"
                                " WHERE business_id = ? AND customer_id = ? AND local_date >= ? AND local_date < ?"
                                " ORDER BY id", (business_id, customer_id, start, end)).fetchall()
        balance = int(opening)
        entries = []
        for r in rows:
            balance += r["debit_paise"] - r["credit_paise"]
            entries.append({**dict(r), "balance_paise": balance})
        return {"customer": dict(customer), "month": month, "opening_paise": int(opening), "entries": entries,
                "debits_paise": sum(e["debit_paise"] for e in entries),
                "credits_paise": sum(e["credit_paise"] for e in entries), "closing_paise": balance}

    # ------------------------------------------------------------- day close
    def day_summary(self, business_id: str, user: str, local_date: str) -> Dict[str, Any]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "view")
            return self._day(conn, business_id, local_date)

    def _day(self, conn: sqlite3.Connection, business_id: str, local_date: str) -> Dict[str, Any]:
        invoices = conn.execute("SELECT doc_kind, status, totals FROM pos_invoices WHERE business_id = ? AND"
                                " local_date = ?", (business_id, local_date)).fetchall()
        sales = [json.loads(r["totals"]) for r in invoices if r["doc_kind"] == "invoice" and r["status"] == "issued"]
        notes = [json.loads(r["totals"]) for r in invoices if r["doc_kind"] == "credit_note" and r["status"] == "issued"]
        by_method: Dict[str, Dict[str, int]] = {}
        for p in conn.execute("SELECT method, kind, verification, amount_paise FROM pos_payments WHERE business_id = ?"
                              " AND local_date = ?", (business_id, local_date)):
            row = by_method.setdefault(p["method"], {"net_paise": 0, "cashier_confirmed_paise": 0})
            row["net_paise"] += p["amount_paise"]
            if p["verification"] == "cashier_confirmed":
                row["cashier_confirmed_paise"] += p["amount_paise"]
        closed = conn.execute("SELECT * FROM pos_day_close WHERE business_id = ? AND local_date = ?",
                              (business_id, local_date)).fetchone()
        return {
            "local_date": local_date,
            "invoices": len(sales),
            "cancelled": sum(1 for r in invoices if r["status"] == "cancelled"),
            "credit_notes": len(notes),
            "sales_paise": sum(t["grand_total_paise"] for t in sales),
            "tax_paise": sum(t["tax_paise"] for t in sales),
            "credit_notes_paise": sum(t["grand_total_paise"] for t in notes),
            "payments": by_method,
            "note": "UPI / card / bank amounts are what the cashier confirmed; match them with your bank statement.",
            "closed": dict(closed) if closed else None,
        }

    def close_day(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        local_date = str(data.get("local_date") or "")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", local_date):
            raise PosError(400, "local_date", "local_date must be YYYY-MM-DD.")
        if local_date > self._local(self.clock()):
            raise PosError(400, "local_date", "Cannot close a future day.")
        opening = int(data.get("opening_float_paise") or 0)
        counted = int(data.get("counted_cash_paise") if data.get("counted_cash_paise") is not None else -1)
        if counted < 0 or opening < 0:
            raise PosError(400, "counted_cash", "Enter the cash counted in the drawer.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "day_close")
            if conn.execute("SELECT 1 FROM pos_day_close WHERE business_id = ? AND local_date = ?",
                            (business_id, local_date)).fetchone():
                raise PosError(409, "day_closed", "This day is already closed (closing is final).")
            day = self._day(conn, business_id, local_date)
            cash = day["payments"].get("cash", {}).get("net_paise", 0)
            expected = opening + cash
            now = self.clock().isoformat()
            conn.execute("INSERT INTO pos_day_close (business_id, local_date, closed_by, closed_at, opening_float_paise,"
                         " expected_cash_paise, counted_cash_paise, difference_paise, totals, note)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (business_id, local_date, user, now, opening, expected, counted, counted - expected,
                          json.dumps({k: day[k] for k in ("invoices", "sales_paise", "tax_paise", "credit_notes_paise",
                                                          "payments")}), _clean(data.get("note"), 240)))
            self._audit(conn, business_id, user, "day.close", local_date,
                        {"expected_cash_paise": expected, "counted_cash_paise": counted}, now)
            return self._day(conn, business_id, local_date)

    # ----------------------------------------------------------- GST reports
    def gst_summary(self, business_id: str, user: str, date_from: str, date_to: str) -> Dict[str, Any]:
        for value in (date_from, date_to):
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value or ""):
                raise PosError(400, "dates", "Dates must be YYYY-MM-DD.")
        with self._connect() as conn:
            self._require(conn, business_id, user, "reports")
            docs = conn.execute("SELECT i.id, i.doc_kind, i.document_type, i.number, i.local_date, i.place_of_supply,"
                                " i.customer_snapshot, i.totals FROM pos_invoices i WHERE i.business_id = ? AND"
                                " i.status = 'issued' AND i.local_date BETWEEN ? AND ? ORDER BY i.issued_at",
                                (business_id, date_from, date_to)).fetchall()
            lines = conn.execute("SELECT l.*, i.doc_kind, i.customer_snapshot FROM pos_invoice_lines l JOIN pos_invoices i"
                                 " ON i.id = l.invoice_id WHERE i.business_id = ? AND i.status = 'issued' AND"
                                 " i.local_date BETWEEN ? AND ?", (business_id, date_from, date_to)).fetchall()
            cancelled = conn.execute("SELECT COUNT(*) AS n FROM pos_invoices WHERE business_id = ? AND status ="
                                     " 'cancelled' AND local_date BETWEEN ? AND ?",
                                     (business_id, date_from, date_to)).fetchone()["n"]
        keys = ("taxable_paise", "cgst_paise", "sgst_paise", "igst_paise", "cess_paise")

        def bucket() -> Dict[str, int]:
            return {k: 0 for k in keys}

        by_rate: Dict[str, Dict[str, Any]] = {}
        hsn: Dict[tuple, Dict[str, Any]] = {}
        b2b, b2c = bucket(), bucket()
        for line in lines:
            sign = -1 if line["doc_kind"] == "credit_note" else 1
            rate_key = f"{line['rate_bp']}:{line['category']}"
            rate_row = by_rate.setdefault(rate_key, {"rate_bp": line["rate_bp"], "category": line["category"], **bucket()})
            is_b2b = bool(json.loads(line["customer_snapshot"]).get("gstin"))
            h = hsn.setdefault((line["hsn_sac"], line["unit"], line["rate_bp"]),
                               {"hsn_sac": line["hsn_sac"] or "(not entered)", "unit": line["unit"],
                                "rate_bp": line["rate_bp"], "qty_milli": 0, **bucket()})
            h["qty_milli"] += sign * line["qty_milli"]
            for k in keys:
                rate_row[k] += sign * line[k]
                h[k] += sign * line[k]
                (b2b if is_b2b else b2c)[k] += sign * line[k]
        register = []
        for d in docs:
            snap = json.loads(d["customer_snapshot"])
            totals = json.loads(d["totals"])
            register.append({"number": d["number"], "date": d["local_date"], "type": d["document_type"],
                             "customer": snap.get("name"), "customer_gstin": snap.get("gstin") or "",
                             "place_of_supply": d["place_of_supply"], **{k: totals[k] for k in keys},
                             "total_paise": totals["grand_total_paise"]})
        return {"from": date_from, "to": date_to, "by_rate": [by_rate[k] for k in sorted(by_rate)],
                "hsn": sorted(hsn.values(), key=lambda r: (r["hsn_sac"], r["rate_bp"])), "b2b": b2b, "b2c": b2c,
                "register": register, "cancelled_count": cancelled, "rules_version": pos_tax.RULES_VERSION,
                "disclaimer": DISCLAIMER}

    def register_csv(self, business_id: str, user: str, date_from: str, date_to: str) -> str:
        summary = self.gst_summary(business_id, user, date_from, date_to)
        header = ["number", "date", "type", "customer", "customer_gstin", "place_of_supply", "taxable", "cgst", "sgst",
                  "igst", "cess", "total"]
        out = [",".join(header)]

        def rupees(paise: int) -> str:
            sign = "-" if paise < 0 else ""
            return f"{sign}{abs(paise) // 100}.{abs(paise) % 100:02d}"

        def cell(value: Any) -> str:
            text = str(value or "")
            if text[:1] in ("=", "+", "-", "@"):
                text = "'" + text  # never let a spreadsheet run a formula from a name
            return '"' + text.replace('"', '""') + '"'

        for r in summary["register"]:
            out.append(",".join([cell(r["number"]), r["date"], r["type"], cell(r["customer"]), cell(r["customer_gstin"]),
                                 r["place_of_supply"], rupees(r["taxable_paise"]), rupees(r["cgst_paise"]),
                                 rupees(r["sgst_paise"]), rupees(r["igst_paise"]), rupees(r["cess_paise"]),
                                 rupees(r["total_paise"])]))
        return "\n".join(out) + "\n"

    # ---------------------------------------------------------------- drafts
    def save_draft(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Held carts and quotations. Not financial records: editable and deletable."""
        kind = data.get("kind")
        if kind not in ("hold", "quotation"):
            raise PosError(400, "kind", "kind must be hold or quotation.")
        payload = data.get("payload") or {}
        if len(json.dumps(payload)) > 60_000:
            raise PosError(413, "payload", "Draft too large.")
        with self._tx() as conn:
            self._require(conn, business_id, user, "drafts")
            now = self.clock().isoformat()
            draft_id = str(data.get("id") or "") or _id("drf")
            existing = conn.execute("SELECT 1 FROM pos_drafts WHERE id = ? AND business_id = ?",
                                    (draft_id, business_id)).fetchone()
            if existing:
                conn.execute("UPDATE pos_drafts SET title = ?, payload = ?, updated_at = ? WHERE id = ?",
                             (_clean(data.get("title"), 80) or kind, json.dumps(payload), now, draft_id))
            else:
                conn.execute("INSERT INTO pos_drafts (id, business_id, kind, title, payload, created_by, created_at,"
                             " updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                             (draft_id, business_id, kind, _clean(data.get("title"), 80) or kind, json.dumps(payload),
                              user, now, now))
        return {"id": draft_id, "kind": kind}

    def drafts(self, business_id: str, user: str, kind: str = "") -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "drafts")
            rows = conn.execute("SELECT * FROM pos_drafts WHERE business_id = ? AND (? = '' OR kind = ?) ORDER BY"
                                " updated_at DESC LIMIT 100", (business_id, kind, kind)).fetchall()
        return [{**dict(r), "payload": json.loads(r["payload"])} for r in rows]

    def delete_draft(self, business_id: str, user: str, draft_id: str) -> None:
        with self._tx() as conn:
            self._require(conn, business_id, user, "drafts")
            conn.execute("DELETE FROM pos_drafts WHERE id = ? AND business_id = ?", (draft_id, business_id))

    # ----------------------------------------------------------------- audit
    def audit(self, business_id: str, user: str, limit: int = 200) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            self._require(conn, business_id, user, "reports")
            rows = conn.execute("SELECT actor, action, ref, detail, at FROM pos_audit WHERE business_id = ? ORDER BY id"
                                " DESC LIMIT ?", (business_id, max(1, min(limit, 1000)))).fetchall()
        return [{**dict(r), "actor": "…" + str(r["actor"])[-4:], "detail": json.loads(r["detail"])} for r in rows]


def iter_permissions() -> Iterable[tuple]:
    for role in ROLES:
        yield role, sorted(PERMISSIONS[role])
