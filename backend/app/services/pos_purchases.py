"""ASKODOX POS -- suppliers, purchase bills, supplier payments / statements,
stock valuation and input-tax summary, on the shared core.

A purchase bill RECORDS a supplier's invoice (it is not issued by the shop):
quantities go into stock (with batch / expiry for batch-tracked items), the
amount owed goes to the supplier ledger, and the GST shown on the bill is kept
as "input tax as recorded" -- whether it can be claimed as input tax credit is
the accountant's decision (ASKODOX never says it is eligible). Like invoices,
recorded bills are never edited or deleted: a mistake is reversed by CANCEL
(row kept, reversing stock + ledger entries). The computed bill total must
match the supplier's printed total within Re 1 (rounding), otherwise the
cashier is asked to check the lines.
"""
from __future__ import annotations

import json
import re
import sqlite3
from typing import Any, Dict, List

from app.services import pos_tax
from app.services.pos_store import PAY_METHODS, PosError, PosStore, _clean, _digest, _id, imei_valid

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_suppliers (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " phone TEXT NOT NULL DEFAULT '', gstin TEXT, address TEXT NOT NULL DEFAULT '', state_code TEXT,"
    " created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_purchases (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, supplier_id TEXT NOT NULL,"
    " supplier_bill_no TEXT NOT NULL, bill_date TEXT NOT NULL, mode TEXT NOT NULL, totals TEXT NOT NULL,"
    " status TEXT NOT NULL, cancel_reason TEXT, client_txn_id TEXT NOT NULL, payload_digest TEXT NOT NULL,"
    " created_by TEXT NOT NULL, created_at TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',"
    " UNIQUE (business_id, client_txn_id))",
    "CREATE TABLE IF NOT EXISTS pos_purchase_lines (purchase_id TEXT NOT NULL, line_no INTEGER NOT NULL,"
    " product_id TEXT NOT NULL, name TEXT NOT NULL, qty_milli INTEGER NOT NULL, cost_paise INTEGER NOT NULL,"
    " rate_bp INTEGER NOT NULL, taxable_paise INTEGER NOT NULL, cgst_paise INTEGER NOT NULL, sgst_paise INTEGER NOT NULL,"
    " igst_paise INTEGER NOT NULL, cess_paise INTEGER NOT NULL, total_paise INTEGER NOT NULL, batch_no TEXT,"
    " expiry_date TEXT, PRIMARY KEY (purchase_id, line_no))",
    "CREATE TABLE IF NOT EXISTS pos_supplier_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, business_id TEXT NOT NULL,"
    " supplier_id TEXT NOT NULL, kind TEXT NOT NULL, ref_id TEXT NOT NULL, owed_paise INTEGER NOT NULL DEFAULT 0,"
    " paid_paise INTEGER NOT NULL DEFAULT 0, method TEXT, reference TEXT NOT NULL DEFAULT '', at TEXT NOT NULL,"
    " local_date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL, client_txn_id TEXT,"
    " UNIQUE (business_id, client_txn_id))",
]

PURCHASE_MIGRATIONS = [
    ("pos_purchase_lines", "pack", "TEXT"),
    ("pos_purchase_lines", "base_qty_milli", "INTEGER"),
    ("pos_purchase_lines", "serials", "TEXT"),
    ("pos_purchases", "po_id", "TEXT"),
]

PO_SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_purchase_orders (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, supplier_id TEXT NOT NULL,"
    " number TEXT NOT NULL, status TEXT NOT NULL, lines TEXT NOT NULL, expected_date TEXT, notes TEXT NOT NULL DEFAULT '',"
    " created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE (business_id, number))",
]

TOLERANCE_PAISE = 100  # Re 1 rounding difference allowed against the supplier's printed total


class PosPurchases:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA + PO_SCHEMA:
                conn.execute(statement)
            for table, column, decl in PURCHASE_MIGRATIONS:
                have = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
                if column not in have:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")

    # ------------------------------------------------------------- suppliers
    def add_supplier(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 80)
        if not name:
            raise PosError(400, "name", "Supplier name is required.")
        gstin = str(data.get("gstin") or "").strip().upper() or None
        state = str(data.get("state_code") or "").zfill(2) if data.get("state_code") else None
        if gstin:
            check = pos_tax.validate_gstin(gstin)
            if not check["valid"]:
                raise PosError(400, "gstin", f"Supplier GSTIN is not valid ({check['reason']}).")
            state = check["state_code"]
        if state and state not in pos_tax.STATE_CODES:
            raise PosError(400, "state_code", "Unknown State code.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            supplier_id = _id("sup")
            now = self.store.clock().isoformat()
            conn.execute("INSERT INTO pos_suppliers (id, business_id, name, phone, gstin, address, state_code, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (supplier_id, business_id, name, _clean(data.get("phone"), 20), gstin,
                          _clean(data.get("address"), 240), state, now))
            self.store._audit(conn, business_id, user, "supplier.add", supplier_id, {"gstin": bool(gstin)}, now)
        return self.supplier(business_id, user, supplier_id)

    def _owed(self, conn: sqlite3.Connection, business_id: str, supplier_id: str) -> int:
        row = conn.execute("SELECT COALESCE(SUM(owed_paise - paid_paise), 0) AS b FROM pos_supplier_ledger WHERE"
                           " business_id = ? AND supplier_id = ?", (business_id, supplier_id)).fetchone()
        return int(row["b"])

    def supplier(self, business_id: str, user: str, supplier_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            row = conn.execute("SELECT * FROM pos_suppliers WHERE id = ? AND business_id = ?",
                               (supplier_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "supplier", "Supplier not found.")
            return {**dict(row), "owed_paise": self._owed(conn, business_id, supplier_id)}

    def suppliers(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            rows = conn.execute("SELECT * FROM pos_suppliers WHERE business_id = ? ORDER BY name", (business_id,)).fetchall()
            return [{**dict(r), "owed_paise": self._owed(conn, business_id, r["id"])} for r in rows]

    # ------------------------------------------------------------- purchases
    def record_purchase(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        digest = _digest({k: data.get(k) for k in ("supplier_id", "supplier_bill_no", "lines", "supplier_total_paise")})
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            seen = conn.execute("SELECT id, payload_digest FROM pos_purchases WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                if seen["payload_digest"] != digest:
                    raise PosError(409, "client_txn_id", "This transaction id was already used for a different bill.")
                purchase_id, replay = seen["id"], True
            else:
                purchase_id, replay = self._record(conn, business_id, user, data, txn, digest), False
        out = self.purchase(business_id, user, purchase_id)
        out["replayed"] = replay
        return out

    def _record(self, conn: sqlite3.Connection, business_id: str, user: str, data: Dict[str, Any], txn: str,
                digest: str) -> str:
        business = self.store._business_row(conn, business_id)
        supplier = conn.execute("SELECT * FROM pos_suppliers WHERE id = ? AND business_id = ?",
                                (data.get("supplier_id"), business_id)).fetchone()
        if supplier is None:
            raise PosError(404, "supplier", "Supplier not found.")
        bill_no = _clean(data.get("supplier_bill_no"), 40)
        if not bill_no:
            raise PosError(400, "supplier_bill_no", "Enter the supplier's bill number.")
        if conn.execute("SELECT 1 FROM pos_purchases WHERE business_id = ? AND supplier_id = ? AND supplier_bill_no = ? AND"
                        " status = 'recorded'", (business_id, supplier["id"], bill_no)).fetchone():
            raise PosError(409, "duplicate_bill", "This supplier bill number is already recorded.")
        bill_date = str(data.get("bill_date") or self.store._local(self.store.clock()))
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", bill_date) or bill_date > self.store._local(self.store.clock()):
            raise PosError(400, "bill_date", "Bill date must be YYYY-MM-DD and not in the future.")
        registered_supplier = bool(supplier["gstin"])
        supplier_state = supplier["state_code"] or business["state_code"]
        mode = "intra" if supplier_state == business["state_code"] else "inter"
        raw_lines = list(data.get("lines") or [])
        if not raw_lines or len(raw_lines) > 300:
            raise PosError(400, "lines", "Add 1-300 lines.")
        lines = []
        for n, raw in enumerate(raw_lines, start=1):
            product = conn.execute("SELECT * FROM pos_products WHERE id = ? AND business_id = ?",
                                   (raw.get("product_id"), business_id)).fetchone()
            if product is None:
                raise PosError(400, "product", f"Line {n}: item not found.")
            qty = int(raw.get("qty_milli") or 0)
            cost = int(raw.get("cost_paise") if raw.get("cost_paise") is not None else -1)
            if qty <= 0 or cost < 0:
                raise PosError(400, "line", f"Line {n}: enter quantity and cost per {product['unit']} (before GST).")
            rate = int(raw.get("rate_bp") if raw.get("rate_bp") is not None else product["rate_bp"])
            batch_no = _clean(raw.get("batch_no"), 40) or None
            expiry = str(raw.get("expiry_date") or "") or None
            pack = None
            base_qty = qty
            if raw.get("pack"):
                pack = conn.execute("SELECT * FROM pos_product_packs WHERE business_id = ? AND product_id = ? AND name = ?",
                                    (business_id, product["id"], str(raw["pack"]))).fetchone()
                if pack is None:
                    raise PosError(400, "pack", f"Line {n}: {product['name']} has no '{raw['pack']}' unit.")
                if (qty * pack["factor_milli"]) % 1000:
                    raise PosError(400, "qty", f"Line {n}: not a whole {product['unit']} count.")
                base_qty = qty * pack["factor_milli"] // 1000
            serials: List[str] = []
            if product["track_serials"]:
                serials = [_clean(x, 40).upper() for x in (raw.get("serials") or []) if _clean(x, 40)]
                if base_qty % 1000 or len(serials) != base_qty // 1000 or len(set(serials)) != len(serials):
                    raise PosError(400, "serials", f"Line {n}: {product['name']} needs one serial / IMEI per piece "
                                                   f"({base_qty // 1000} expected).")
                for sn in serials:
                    if product["serial_kind"] == "imei" and not imei_valid(sn):
                        raise PosError(400, "imei", f"Line {n}: {sn} is not a valid 15-digit IMEI (check digit).")
                    if conn.execute("SELECT 1 FROM pos_serials WHERE business_id = ? AND product_id = ? AND serial = ?",
                                    (business_id, product["id"], sn)).fetchone():
                        raise PosError(409, "serial_exists", f"Line {n}: {sn} is already recorded for {product['name']}.")
            if product["track_batches"] and not batch_no:
                raise PosError(400, "batch_no", f"Line {n}: {product['name']} is tracked by batch; enter the batch number.")
            if expiry and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", expiry):
                raise PosError(400, "expiry_date", f"Line {n}: expiry date must be YYYY-MM-DD.")
            try:
                tax = pos_tax.line_tax(qty_milli=qty, unit_price_paise=cost, discount_paise=int(raw.get("discount_paise") or 0),
                                       rate_bp=rate, cess_bp=int(raw.get("cess_bp") or 0), price_includes_tax=False,
                                       category="taxable", mode=mode, collect_tax=registered_supplier)
            except pos_tax.TaxError as error:
                raise PosError(400, error.code, f"Line {n}: {error.message}")
            lines.append({"line_no": n, "product": product, "qty_milli": qty, "cost_paise": cost, "rate_bp": rate,
                          "batch_no": batch_no, "expiry_date": expiry, "pack": pack["name"] if pack is not None else None,
                          "base_qty_milli": base_qty, "serials": serials, **tax})
        keys = ("taxable_paise", "cgst_paise", "sgst_paise", "igst_paise", "cess_paise", "tax_paise", "total_paise")
        totals = {k: sum(l[k] for l in lines) for k in keys}
        printed = data.get("supplier_total_paise")
        if printed is not None:
            diff = int(printed) - totals["total_paise"]
            if abs(diff) > TOLERANCE_PAISE:
                raise PosError(400, "total_mismatch",
                               f"Lines add up to Rs {totals['total_paise'] / 100:.2f} but the supplier bill says Rs "
                               f"{int(printed) / 100:.2f}. Check quantities, costs and GST rates.",
                               computed_paise=totals["total_paise"])
            totals["round_off_paise"] = diff
            totals["total_paise"] = int(printed)
        else:
            totals["round_off_paise"] = 0
        totals["input_tax_note"] = ("Input tax as recorded from the supplier bill; whether it can be claimed is for your"
                                    " accountant to decide.") if registered_supplier else "Unregistered supplier: no GST charged."
        at = self.store.clock()
        now = at.isoformat()
        purchase_id = _id("pur")
        conn.execute("INSERT INTO pos_purchases (id, business_id, supplier_id, supplier_bill_no, bill_date, mode, totals,"
                     " status, client_txn_id, payload_digest, created_by, created_at, notes, po_id) VALUES (?, ?, ?, ?, ?, ?, ?,"
                     " 'recorded', ?, ?, ?, ?, ?, ?)",
                     (purchase_id, business_id, supplier["id"], bill_no, bill_date, mode, json.dumps(totals), txn, digest,
                      user, now, _clean(data.get("notes"), 240), data.get("po_id")))
        for l in lines:
            p = l["product"]
            conn.execute("INSERT INTO pos_purchase_lines (purchase_id, line_no, product_id, name, qty_milli, cost_paise,"
                         " rate_bp, taxable_paise, cgst_paise, sgst_paise, igst_paise, cess_paise, total_paise, batch_no,"
                         " expiry_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (purchase_id, l["line_no"], p["id"], p["name"], l["qty_milli"], l["cost_paise"], l["rate_bp"],
                          l["taxable_paise"], l["cgst_paise"], l["sgst_paise"], l["igst_paise"], l["cess_paise"],
                          l["total_paise"], l["batch_no"], l["expiry_date"]))
            conn.execute("UPDATE pos_purchase_lines SET pack = ?, base_qty_milli = ?, serials = ? WHERE purchase_id = ? AND"
                         " line_no = ?", (l["pack"], l["base_qty_milli"], json.dumps(l["serials"]) if l["serials"] else None,
                                          purchase_id, l["line_no"]))
            for sn in l["serials"]:
                conn.execute("INSERT INTO pos_serials (business_id, product_id, serial, status, purchase_id, updated_at)"
                             " VALUES (?, ?, ?, 'in_stock', ?, ?)", (business_id, p["id"], sn, purchase_id, now))
            if p["track_stock"]:
                conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                             " created_by, batch_no, expiry_date) VALUES (?, ?, ?, 'purchase', ?, ?, ?, ?, ?, ?)",
                             (business_id, p["id"], l["base_qty_milli"], purchase_id, f"bill {bill_no}", now, user,
                              l["batch_no"], l["expiry_date"]))
        conn.execute("INSERT INTO pos_supplier_ledger (business_id, supplier_id, kind, ref_id, owed_paise, at, local_date,"
                     " note, created_by) VALUES (?, ?, 'bill', ?, ?, ?, ?, ?, ?)",
                     (business_id, supplier["id"], purchase_id, totals["total_paise"], now, self.store._local(at),
                      f"bill {bill_no}", user))
        self.store._audit(conn, business_id, user, "purchase.record", purchase_id,
                          {"supplier": supplier["id"], "bill_no": bill_no, "total_paise": totals["total_paise"]}, now)
        return purchase_id

    def purchase(self, business_id: str, user: str, purchase_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            row = conn.execute("SELECT p.*, s.name AS supplier_name, s.gstin AS supplier_gstin FROM pos_purchases p JOIN"
                               " pos_suppliers s ON s.id = p.supplier_id WHERE p.id = ? AND p.business_id = ?",
                               (purchase_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "purchase", "Purchase bill not found.")
            lines = conn.execute("SELECT * FROM pos_purchase_lines WHERE purchase_id = ? ORDER BY line_no",
                                 (purchase_id,)).fetchall()
        out = dict(row)
        out.pop("payload_digest", None)
        out["totals"] = json.loads(out["totals"])
        out["lines"] = [dict(l) for l in lines]
        return out

    def purchases(self, business_id: str, user: str, supplier_id: str = "") -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            rows = conn.execute("SELECT p.id, p.supplier_bill_no, p.bill_date, p.status, p.totals, s.name AS supplier_name"
                                " FROM pos_purchases p JOIN pos_suppliers s ON s.id = p.supplier_id WHERE p.business_id = ?"
                                " AND (? = '' OR p.supplier_id = ?) ORDER BY p.created_at DESC LIMIT 300",
                                (business_id, supplier_id, supplier_id)).fetchall()
        return [{**{k: r[k] for k in ("id", "supplier_bill_no", "bill_date", "status", "supplier_name")},
                 "total_paise": json.loads(r["totals"])["total_paise"]} for r in rows]

    def cancel_purchase(self, business_id: str, user: str, purchase_id: str, reason: str) -> Dict[str, Any]:
        reason = _clean(reason, 160)
        if not reason:
            raise PosError(400, "reason", "Say why the bill is cancelled.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            row = conn.execute("SELECT * FROM pos_purchases WHERE id = ? AND business_id = ?",
                               (purchase_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "purchase", "Purchase bill not found.")
            if row["status"] != "recorded":
                raise PosError(409, "status", "Already cancelled.")
            if conn.execute("SELECT 1 FROM pos_serials WHERE business_id = ? AND purchase_id = ? AND status != 'in_stock'",
                            (business_id, purchase_id)).fetchone():
                raise PosError(409, "serials_sold", "Some serial / IMEI numbers from this bill are already sold; return them"
                                                    " first or record a debit note with the supplier.")
            at = self.store.clock()
            now = at.isoformat()
            conn.execute("UPDATE pos_purchases SET status = 'cancelled', cancel_reason = ? WHERE id = ?", (reason, purchase_id))
            conn.execute("DELETE FROM pos_serials WHERE business_id = ? AND purchase_id = ? AND status = 'in_stock'",
                         (business_id, purchase_id))
            for m in conn.execute("SELECT product_id, qty_milli, batch_no, expiry_date FROM pos_stock_moves WHERE ref_id = ?"
                                  " AND kind = 'purchase'", (purchase_id,)).fetchall():
                conn.execute("INSERT INTO pos_stock_moves (business_id, product_id, qty_milli, kind, ref_id, reason, at,"
                             " created_by, batch_no, expiry_date) VALUES (?, ?, ?, 'purchase_cancel', ?, ?, ?, ?, ?, ?)",
                             (business_id, m["product_id"], -m["qty_milli"], purchase_id, reason, now, user, m["batch_no"],
                              m["expiry_date"]))
            total = json.loads(row["totals"])["total_paise"]
            conn.execute("INSERT INTO pos_supplier_ledger (business_id, supplier_id, kind, ref_id, owed_paise, at, local_date,"
                         " note, created_by) VALUES (?, ?, 'bill_cancel', ?, ?, ?, ?, ?, ?)",
                         (business_id, row["supplier_id"], purchase_id, -total, now, self.store._local(at),
                          f"cancelled bill {row['supplier_bill_no']}", user))
            self.store._audit(conn, business_id, user, "purchase.cancel", purchase_id, {"reason": reason}, now)
        return self.purchase(business_id, user, purchase_id)

    # -------------------------------------------------------------- payments
    def pay_supplier(self, business_id: str, user: str, supplier_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        method = data.get("method")
        if method not in PAY_METHODS:
            raise PosError(400, "payment", "Payment method must be cash, upi, card, bank_transfer or cheque.")
        amount = int(data.get("amount_paise") or 0)
        if amount <= 0:
            raise PosError(400, "amount", "Amount must be positive.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            if conn.execute("SELECT 1 FROM pos_suppliers WHERE id = ? AND business_id = ?",
                            (supplier_id, business_id)).fetchone() is None:
                raise PosError(404, "supplier", "Supplier not found.")
            seen = conn.execute("SELECT id FROM pos_supplier_ledger WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen is None:
                at = self.store.clock()
                conn.execute("INSERT INTO pos_supplier_ledger (business_id, supplier_id, kind, ref_id, paid_paise, method,"
                             " reference, at, local_date, note, created_by, client_txn_id) VALUES (?, ?, 'payment', ?, ?, ?,"
                             " ?, ?, ?, ?, ?, ?)",
                             (business_id, supplier_id, txn, amount, method, _clean(data.get("reference"), 60), at.isoformat(),
                              self.store._local(at), f"paid ({method})", user, txn))
                self.store._audit(conn, business_id, user, "supplier.pay", supplier_id,
                                  {"amount_paise": amount, "method": method}, at.isoformat())
            return {"replayed": seen is not None, "owed_paise": self._owed(conn, business_id, supplier_id)}

    def supplier_statement(self, business_id: str, user: str, supplier_id: str, month: str) -> Dict[str, Any]:
        if not re.fullmatch(r"\d{4}-\d{2}", month or ""):
            raise PosError(400, "month", "month must be YYYY-MM.")
        start = f"{month}-01"
        year, mon = int(month[:4]), int(month[5:])
        end = f"{year + (mon // 12)}-{(mon % 12) + 1:02d}-01"
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            supplier = conn.execute("SELECT name, gstin FROM pos_suppliers WHERE id = ? AND business_id = ?",
                                    (supplier_id, business_id)).fetchone()
            if supplier is None:
                raise PosError(404, "supplier", "Supplier not found.")
            opening = conn.execute("SELECT COALESCE(SUM(owed_paise - paid_paise), 0) AS b FROM pos_supplier_ledger WHERE"
                                   " business_id = ? AND supplier_id = ? AND local_date < ?",
                                   (business_id, supplier_id, start)).fetchone()["b"]
            rows = conn.execute("SELECT kind, ref_id, owed_paise, paid_paise, method, reference, local_date, note FROM"
                                " pos_supplier_ledger WHERE business_id = ? AND supplier_id = ? AND local_date >= ? AND"
                                " local_date < ? ORDER BY id", (business_id, supplier_id, start, end)).fetchall()
        balance = int(opening)
        entries = []
        for r in rows:
            balance += r["owed_paise"] - r["paid_paise"]
            entries.append({**dict(r), "balance_paise": balance})
        return {"supplier": dict(supplier), "month": month, "opening_paise": int(opening), "entries": entries,
                "closing_paise": balance}

    # --------------------------------------------------------------- reports
    def valuation(self, business_id: str, user: str) -> Dict[str, Any]:
        """Stock x average purchase cost (before GST) of recorded, uncancelled bills. Items never
        bought through a recorded bill have no cost and are listed as 'cost unknown'."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            stock = self.store._stock_map(conn, business_id)
            costs = {r["product_id"]: (int(r["q"]), int(r["c"])) for r in conn.execute(
                "SELECT l.product_id, SUM(COALESCE(l.base_qty_milli, l.qty_milli)) AS q, SUM(l.taxable_paise) AS c FROM"
                " pos_purchase_lines l JOIN"
                " pos_purchases p ON p.id = l.purchase_id WHERE p.business_id = ? AND p.status = 'recorded'"
                " GROUP BY l.product_id", (business_id,))}
            products = conn.execute("SELECT id, name, unit FROM pos_products WHERE business_id = ? AND track_stock = 1"
                                    " AND active = 1 ORDER BY name", (business_id,)).fetchall()
        rows, total, unknown = [], 0, 0
        for p in products:
            qty = stock.get(p["id"], 0)
            q, c = costs.get(p["id"], (0, 0))
            avg = c * 1000 // q if q else None  # paise per whole unit
            value = qty * avg // 1000 if (avg is not None and qty > 0) else None
            if value is None and qty > 0:
                unknown += 1
            total += value or 0
            rows.append({"product_id": p["id"], "name": p["name"], "unit": p["unit"], "stock_milli": qty,
                         "avg_cost_paise": avg, "value_paise": value})
        return {"items": rows, "total_value_paise": total, "items_without_cost": unknown,
                "method": "average purchase cost before GST, from recorded bills"}

    def input_tax(self, business_id: str, user: str, date_from: str, date_to: str) -> Dict[str, Any]:
        for value in (date_from, date_to):
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value or ""):
                raise PosError(400, "dates", "Dates must be YYYY-MM-DD.")
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            rows = conn.execute("SELECT p.supplier_bill_no, p.bill_date, p.totals, s.name, s.gstin FROM pos_purchases p JOIN"
                                " pos_suppliers s ON s.id = p.supplier_id WHERE p.business_id = ? AND p.status = 'recorded'"
                                " AND p.bill_date BETWEEN ? AND ? ORDER BY p.bill_date", (business_id, date_from, date_to)).fetchall()
        keys = ("taxable_paise", "cgst_paise", "sgst_paise", "igst_paise", "cess_paise")
        bills = []
        sums = {k: 0 for k in keys}
        for r in rows:
            t = json.loads(r["totals"])
            bills.append({"supplier": r["name"], "supplier_gstin": r["gstin"] or "", "bill_no": r["supplier_bill_no"],
                          "bill_date": r["bill_date"], **{k: t[k] for k in keys}, "total_paise": t["total_paise"]})
            for k in keys:
                sums[k] += t[k]
        return {"from": date_from, "to": date_to, "bills": bills, "totals": sums,
                "disclaimer": "Tax as recorded from supplier bills. Input tax credit eligibility (registration, GSTR-2B"
                              " match, blocked credits) is decided by your accountant, not by ASKODOX."}


    # --------------------------------------------------------- purchase orders
    def _po_lines(self, conn: sqlite3.Connection, business_id: str, raw_lines: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not raw_lines or len(raw_lines) > 200:
            raise PosError(400, "lines", "Add 1-200 lines.")
        out = []
        for n, raw in enumerate(raw_lines, start=1):
            product = conn.execute("SELECT id, name, unit FROM pos_products WHERE id = ? AND business_id = ?",
                                   (raw.get("product_id"), business_id)).fetchone()
            if product is None:
                raise PosError(400, "product", f"Line {n}: item not found.")
            qty = int(raw.get("qty_milli") or 0)
            if qty <= 0:
                raise PosError(400, "qty", f"Line {n}: quantity must be more than zero.")
            pack = str(raw.get("pack") or "") or None
            if pack and conn.execute("SELECT 1 FROM pos_product_packs WHERE business_id = ? AND product_id = ? AND name = ?",
                                     (business_id, product["id"], pack)).fetchone() is None:
                raise PosError(400, "pack", f"Line {n}: {product['name']} has no '{pack}' unit.")
            cost = raw.get("cost_paise")
            out.append({"line_no": n, "product_id": product["id"], "name": product["name"], "unit": pack or product["unit"],
                        "pack": pack, "qty_milli": qty, "cost_paise": None if cost is None else max(0, int(cost)),
                        "received_milli": 0})
        return out

    def create_po(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """A purchase ORDER (what the shop asks a supplier for). Not a tax record and not stock:
        stock and money owed change only when the supplier's bill is recorded against it."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            if conn.execute("SELECT 1 FROM pos_suppliers WHERE id = ? AND business_id = ?",
                            (data.get("supplier_id"), business_id)).fetchone() is None:
                raise PosError(404, "supplier", "Supplier not found.")
            lines = self._po_lines(conn, business_id, list(data.get("lines") or []))
            expected = str(data.get("expected_date") or "") or None
            if expected and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", expected):
                raise PosError(400, "expected_date", "Expected date must be YYYY-MM-DD.")
            count = conn.execute("SELECT COUNT(*) AS n FROM pos_purchase_orders WHERE business_id = ?",
                                 (business_id,)).fetchone()["n"]
            now = self.store.clock().isoformat()
            po_id = _id("po")
            number = f"PO-{count + 1:05d}"
            conn.execute("INSERT INTO pos_purchase_orders (id, business_id, supplier_id, number, status, lines, expected_date,"
                         " notes, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, 'draft', ?, ?, ?, ?, ?, ?)",
                         (po_id, business_id, data["supplier_id"], number, json.dumps(lines), expected,
                          _clean(data.get("notes"), 240), user, now, now))
            self.store._audit(conn, business_id, user, "po.create", po_id, {"number": number}, now)
        return self.po(business_id, user, po_id)

    def po(self, business_id: str, user: str, po_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            row = conn.execute("SELECT o.*, s.name AS supplier_name, s.phone AS supplier_phone FROM pos_purchase_orders o"
                               " JOIN pos_suppliers s ON s.id = o.supplier_id WHERE o.id = ? AND o.business_id = ?",
                               (po_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "po", "Purchase order not found.")
            bills = [dict(r) for r in conn.execute("SELECT id, supplier_bill_no, bill_date, status FROM pos_purchases WHERE"
                                                    " business_id = ? AND po_id = ? ORDER BY created_at", (business_id, po_id))]
        out = dict(row)
        out["lines"] = json.loads(out["lines"])
        out["bills"] = bills
        out["text"] = self._po_text(out)
        return out

    @staticmethod
    def _po_text(po: Dict[str, Any]) -> str:
        rows = [f"Purchase order {po['number']}" + (f" -- needed by {po['expected_date']}" if po.get("expected_date") else "")]
        for l in po["lines"]:
            qty = l["qty_milli"] / 1000
            rows.append(f"- {l['name']}: {qty:g} {l['unit']}")
        if po.get("notes"):
            rows.append(po["notes"])
        return "\n".join(rows)

    def pos_list(self, business_id: str, user: str, status: str = "") -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "purchases")
            rows = conn.execute("SELECT o.id, o.number, o.status, o.expected_date, o.created_at, s.name AS supplier_name FROM"
                                " pos_purchase_orders o JOIN pos_suppliers s ON s.id = o.supplier_id WHERE o.business_id = ?"
                                " AND (? = '' OR o.status = ?) ORDER BY o.created_at DESC LIMIT 200",
                                (business_id, status, status)).fetchall()
        return [dict(r) for r in rows]

    def set_po_status(self, business_id: str, user: str, po_id: str, status: str) -> Dict[str, Any]:
        flow = {"draft": ("sent", "cancelled"), "sent": ("cancelled",), "partially_received": ("cancelled",)}
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "purchases")
            row = conn.execute("SELECT status FROM pos_purchase_orders WHERE id = ? AND business_id = ?",
                               (po_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "po", "Purchase order not found.")
            if status not in flow.get(row["status"], ()):
                raise PosError(409, "status", f"A {row['status']} order cannot become {status}.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_purchase_orders SET status = ?, updated_at = ? WHERE id = ?", (status, now, po_id))
            self.store._audit(conn, business_id, user, f"po.{status}", po_id, {}, now)
        return self.po(business_id, user, po_id)

    def receive_po(self, business_id: str, user: str, po_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Record the supplier's bill for (part of) an order. The bill is an ordinary purchase
        bill (same checks); the order tracks how much has arrived."""
        current = self.po(business_id, user, po_id)
        if current["status"] not in ("draft", "sent", "partially_received"):
            raise PosError(409, "status", "This order is closed.")
        by_line = {l["line_no"]: l for l in current["lines"]}
        bill_lines = []
        for raw in data.get("lines") or []:
            src = by_line.get(int(raw.get("line_no") or 0))
            if src is None:
                raise PosError(400, "line", "Unknown order line.")
            bill_lines.append({k: v for k, v in {
                "product_id": src["product_id"], "pack": src["pack"], "qty_milli": int(raw.get("qty_milli") or 0),
                "cost_paise": raw.get("cost_paise", src["cost_paise"]), "rate_bp": raw.get("rate_bp"),
                "batch_no": raw.get("batch_no"), "expiry_date": raw.get("expiry_date"), "serials": raw.get("serials"),
            }.items() if v is not None})
        purchase = self.record_purchase(business_id, user, {
            "client_txn_id": data.get("client_txn_id"), "supplier_id": current["supplier_id"],
            "supplier_bill_no": data.get("supplier_bill_no"), "bill_date": data.get("bill_date"), "lines": bill_lines,
            "supplier_total_paise": data.get("supplier_total_paise"), "po_id": po_id,
            "notes": f"against {current['number']}"})
        if not purchase.get("replayed"):
            with self.store._tx() as conn:
                row = conn.execute("SELECT lines FROM pos_purchase_orders WHERE id = ?", (po_id,)).fetchone()
                lines = json.loads(row["lines"])
                for raw in data.get("lines") or []:
                    for l in lines:
                        if l["line_no"] == int(raw.get("line_no") or 0):
                            l["received_milli"] = l.get("received_milli", 0) + int(raw.get("qty_milli") or 0)
                done = all(l.get("received_milli", 0) >= l["qty_milli"] for l in lines)
                now = self.store.clock().isoformat()
                conn.execute("UPDATE pos_purchase_orders SET lines = ?, status = ?, updated_at = ? WHERE id = ?",
                             (json.dumps(lines), "received" if done else "partially_received", now, po_id))
                self.store._audit(conn, business_id, user, "po.receive", po_id, {"purchase": purchase["id"]}, now)
        return {"purchase": purchase, "order": self.po(business_id, user, po_id)}
