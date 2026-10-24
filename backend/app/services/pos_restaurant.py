"""ASKODOX POS -- restaurant module on the shared core: tables, open orders,
kitchen order tickets (KOT), kitchen display states, move / merge tables and
split billing by items.

Orders are working documents (not tax records) until they are BILLED: billing
goes through the same ``PosStore._issue`` as the counter, inside the same
transaction, so a bill has the same GST rules, numbering, idempotency and
audit. An item already sent to the kitchen is never deleted: it is VOIDED with
a reason by a manager / owner (logged). Item notes ("less spicy") are text
only; priced modifiers are not built.
"""
from __future__ import annotations

import sqlite3
from typing import Any, Dict, List, Optional

from app.services.pos_store import PERMISSIONS, PosError, PosStore, _clean, _digest, _id

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_tables (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, name TEXT NOT NULL,"
    " area TEXT NOT NULL DEFAULT '', seats INTEGER NOT NULL DEFAULT 4, active INTEGER NOT NULL DEFAULT 1,"
    " created_at TEXT NOT NULL, UNIQUE (business_id, name))",
    "CREATE TABLE IF NOT EXISTS pos_orders (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, table_id TEXT,"
    " kind TEXT NOT NULL, status TEXT NOT NULL, guests INTEGER NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT '',"
    " created_by TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_orders_biz ON pos_orders(business_id, status)",
    "CREATE TABLE IF NOT EXISTS pos_order_items (id TEXT PRIMARY KEY, order_id TEXT NOT NULL, business_id TEXT NOT NULL,"
    " product_id TEXT NOT NULL, name TEXT NOT NULL, qty_milli INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '',"
    " status TEXT NOT NULL, kot_id TEXT, invoice_id TEXT, void_reason TEXT, added_by TEXT NOT NULL, added_at TEXT NOT NULL,"
    " client_txn_id TEXT, UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_order_items_order ON pos_order_items(order_id)",
    "CREATE TABLE IF NOT EXISTS pos_kots (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, order_id TEXT NOT NULL,"
    " number INTEGER NOT NULL, local_date TEXT NOT NULL, status TEXT NOT NULL, created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE (business_id, local_date, number))",
]

ORDER_KINDS = ("dine_in", "takeaway", "delivery")
KOT_FLOW = {"new": ("preparing", "ready"), "preparing": ("ready",), "ready": ("served",), "served": ()}


class PosRestaurant:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ---------------------------------------------------------------- tables
    def add_table(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        name = _clean(data.get("name"), 30)
        if not name:
            raise PosError(400, "name", "Table name is required (e.g. T1).")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            if conn.execute("SELECT 1 FROM pos_tables WHERE business_id = ? AND name = ?", (business_id, name)).fetchone():
                raise PosError(409, "name", "A table with that name exists.")
            table_id = _id("tbl")
            now = self.store.clock().isoformat()
            conn.execute("INSERT INTO pos_tables (id, business_id, name, area, seats, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                         (table_id, business_id, name, _clean(data.get("area"), 30),
                          max(1, min(int(data.get("seats") or 4), 50)), now))
            self.store._audit(conn, business_id, user, "table.add", table_id, {"name": name}, now)
        return {"id": table_id, "name": name}

    def tables(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        """Floor view: every table with its open order (if any) and running total."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "tables")
            rows = conn.execute("SELECT * FROM pos_tables WHERE business_id = ? AND active = 1 ORDER BY area, name",
                                (business_id,)).fetchall()
            out = []
            for t in rows:
                order = conn.execute("SELECT id, created_at, guests FROM pos_orders WHERE business_id = ? AND table_id = ?"
                                     " AND status = 'open'", (business_id, t["id"])).fetchone()
                item = dict(t)
                item["order"] = None
                if order is not None:
                    summary = self._summary(conn, business_id, order["id"])
                    item["order"] = {"id": order["id"], "since": order["created_at"], "guests": order["guests"], **summary}
                out.append(item)
            return out

    # ---------------------------------------------------------------- orders
    def open_order(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("kind") or "dine_in")
        if kind not in ORDER_KINDS:
            raise PosError(400, "kind", "kind must be dine_in, takeaway or delivery.")
        table_id = data.get("table_id")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            if kind == "dine_in":
                if not table_id or conn.execute("SELECT 1 FROM pos_tables WHERE id = ? AND business_id = ? AND active = 1",
                                                (table_id, business_id)).fetchone() is None:
                    raise PosError(400, "table", "Choose a table for a dine-in order.")
                existing = conn.execute("SELECT id FROM pos_orders WHERE business_id = ? AND table_id = ? AND status ="
                                        " 'open'", (business_id, table_id)).fetchone()
                if existing:
                    return self._order(conn, business_id, existing["id"])
            else:
                table_id = None
            order_id = _id("ord")
            now = self.store.clock().isoformat()
            conn.execute("INSERT INTO pos_orders (id, business_id, table_id, kind, status, guests, notes, created_by,"
                         " created_at, updated_at) VALUES (?, ?, ?, ?, 'open', ?, ?, ?, ?, ?)",
                         (order_id, business_id, table_id, kind, max(0, int(data.get("guests") or 0)),
                          _clean(data.get("notes"), 160), user, now, now))
            self.store._audit(conn, business_id, user, "order.open", order_id, {"kind": kind, "table_id": table_id}, now)
            return self._order(conn, business_id, order_id)

    def _order_row(self, conn: sqlite3.Connection, business_id: str, order_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "order", "Order not found.")
        return row

    def _summary(self, conn: sqlite3.Connection, business_id: str, order_id: str) -> Dict[str, Any]:
        rows = conn.execute("SELECT i.status, i.qty_milli, p.price_paise FROM pos_order_items i JOIN pos_products p ON"
                            " p.id = i.product_id WHERE i.order_id = ? AND i.business_id = ?",
                            (order_id, business_id)).fetchall()
        live = [r for r in rows if r["status"] not in ("void", "billed")]
        return {"item_count": len(live), "pending": sum(1 for r in live if r["status"] == "pending"),
                "estimate_paise": sum(r["qty_milli"] * r["price_paise"] // 1000 for r in live)}

    def _order(self, conn: sqlite3.Connection, business_id: str, order_id: str) -> Dict[str, Any]:
        row = dict(self._order_row(conn, business_id, order_id))
        items = conn.execute("SELECT i.*, p.price_paise, p.unit FROM pos_order_items i JOIN pos_products p ON"
                             " p.id = i.product_id WHERE i.order_id = ? ORDER BY i.added_at", (order_id,)).fetchall()
        kots = conn.execute("SELECT id, number, status, created_at FROM pos_kots WHERE order_id = ? ORDER BY number",
                            (order_id,)).fetchall()
        invoices = conn.execute("SELECT DISTINCT invoice_id FROM pos_order_items WHERE order_id = ? AND invoice_id IS NOT"
                                " NULL", (order_id,)).fetchall()
        table = None
        if row["table_id"]:
            t = conn.execute("SELECT name FROM pos_tables WHERE id = ?", (row["table_id"],)).fetchone()
            table = t["name"] if t else None
        row["table_name"] = table
        row["items"] = [dict(i) for i in items]
        row["kots"] = [dict(k) for k in kots]
        row["invoice_ids"] = [r["invoice_id"] for r in invoices]
        row.update(self._summary(conn, business_id, order_id))
        row["note"] = "Estimate at today's item prices; the bill is computed with GST when you bill."
        return row

    def order(self, business_id: str, user: str, order_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "tables")
            return self._order(conn, business_id, order_id)

    def open_orders(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "tables")
            ids = [r["id"] for r in conn.execute("SELECT id FROM pos_orders WHERE business_id = ? AND status = 'open'"
                                                  " ORDER BY created_at", (business_id,))]
            return [self._order(conn, business_id, i) for i in ids]

    def add_items(self, business_id: str, user: str, order_id: str, items: List[Dict[str, Any]]) -> Dict[str, Any]:
        if not items or len(items) > 100:
            raise PosError(400, "items", "Add 1-100 items.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            if self._order_row(conn, business_id, order_id)["status"] != "open":
                raise PosError(409, "status", "This order is closed.")
            now = self.store.clock().isoformat()
            for raw in items:
                txn = _clean(raw.get("client_txn_id"), 64) or None
                if txn and conn.execute("SELECT 1 FROM pos_order_items WHERE business_id = ? AND client_txn_id = ?",
                                        (business_id, txn)).fetchone():
                    continue  # resent by a flaky connection
                product = conn.execute("SELECT id, name FROM pos_products WHERE id = ? AND business_id = ? AND active = 1",
                                       (raw.get("product_id"), business_id)).fetchone()
                if product is None:
                    raise PosError(400, "product", "An item is not in this restaurant's active menu.")
                qty = int(raw.get("qty_milli") or 1000)
                if qty <= 0:
                    raise PosError(400, "qty", "Quantity must be more than zero.")
                conn.execute("INSERT INTO pos_order_items (id, order_id, business_id, product_id, name, qty_milli, note,"
                             " status, added_by, added_at, client_txn_id) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)",
                             (_id("itm"), order_id, business_id, product["id"], product["name"], qty,
                              _clean(raw.get("note"), 120), user, now, txn))
            conn.execute("UPDATE pos_orders SET updated_at = ? WHERE id = ?", (now, order_id))
            return self._order(conn, business_id, order_id)

    def remove_item(self, business_id: str, user: str, order_id: str, item_id: str, reason: str = "") -> Dict[str, Any]:
        """Not yet sent -> removed. Sent to the kitchen -> VOID with a reason (manager / owner only)."""
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "tables")
            item = conn.execute("SELECT * FROM pos_order_items WHERE id = ? AND order_id = ? AND business_id = ?",
                                (item_id, order_id, business_id)).fetchone()
            if item is None:
                raise PosError(404, "item", "Item not found.")
            now = self.store.clock().isoformat()
            if item["status"] == "pending":
                conn.execute("DELETE FROM pos_order_items WHERE id = ?", (item_id,))
                action = "order.item_removed"
            elif item["status"] == "sent":
                if "cancel" not in PERMISSIONS[role]:
                    raise PosError(403, "permission", "Only a manager / owner can void an item already sent to the kitchen.")
                reason = _clean(reason, 120)
                if not reason:
                    raise PosError(400, "reason", "Say why the item is voided.")
                conn.execute("UPDATE pos_order_items SET status = 'void', void_reason = ? WHERE id = ?", (reason, item_id))
                action = "order.item_void"
            else:
                raise PosError(409, "status", "A billed or voided item cannot change.")
            self.store._audit(conn, business_id, user, action, item_id, {"order": order_id, "name": item["name"],
                                                                         "reason": reason}, now)
            return self._order(conn, business_id, order_id)

    def send_kot(self, business_id: str, user: str, order_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            if self._order_row(conn, business_id, order_id)["status"] != "open":
                raise PosError(409, "status", "This order is closed.")
            pending = conn.execute("SELECT id FROM pos_order_items WHERE order_id = ? AND status = 'pending'",
                                   (order_id,)).fetchall()
            if not pending:
                raise PosError(400, "nothing_to_send", "No new items to send to the kitchen.")
            at = self.store.clock()
            local = self.store._local(at)
            number = conn.execute("SELECT COALESCE(MAX(number), 0) + 1 AS n FROM pos_kots WHERE business_id = ? AND"
                                  " local_date = ?", (business_id, local)).fetchone()["n"]
            kot_id = _id("kot")
            now = at.isoformat()
            conn.execute("INSERT INTO pos_kots (id, business_id, order_id, number, local_date, status, created_by, created_at,"
                         " updated_at) VALUES (?, ?, ?, ?, ?, 'new', ?, ?, ?)",
                         (kot_id, business_id, order_id, number, local, user, now, now))
            conn.execute("UPDATE pos_order_items SET status = 'sent', kot_id = ? WHERE order_id = ? AND status = 'pending'",
                         (kot_id, order_id))
            self.store._audit(conn, business_id, user, "kot.send", kot_id, {"order": order_id, "number": number,
                                                                            "items": len(pending)}, now)
            out = self._order(conn, business_id, order_id)
            out["kot"] = self._kot(conn, kot_id)
            return out

    def _kot(self, conn: sqlite3.Connection, kot_id: str) -> Dict[str, Any]:
        kot = dict(conn.execute("SELECT * FROM pos_kots WHERE id = ?", (kot_id,)).fetchone())
        order = conn.execute("SELECT o.kind, t.name AS table_name FROM pos_orders o LEFT JOIN pos_tables t ON"
                             " t.id = o.table_id WHERE o.id = ?", (kot["order_id"],)).fetchone()
        kot["table_name"] = order["table_name"] if order else None
        kot["kind"] = order["kind"] if order else None
        kot["items"] = [dict(r) for r in conn.execute(
            "SELECT i.name, i.qty_milli, i.note, i.status, p.unit FROM pos_order_items i JOIN pos_products p ON"
            " p.id = i.product_id WHERE i.kot_id = ? ORDER BY i.added_at", (kot_id,))]
        return kot

    def kitchen(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        """Kitchen display: tickets not yet served, oldest first."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "kitchen")
            ids = [r["id"] for r in conn.execute("SELECT id FROM pos_kots WHERE business_id = ? AND status != 'served'"
                                                  " ORDER BY created_at", (business_id,))]
            return [self._kot(conn, i) for i in ids]

    def set_kot_status(self, business_id: str, user: str, kot_id: str, status: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "kitchen")
            kot = conn.execute("SELECT status FROM pos_kots WHERE id = ? AND business_id = ?",
                               (kot_id, business_id)).fetchone()
            if kot is None:
                raise PosError(404, "kot", "Ticket not found.")
            if status not in KOT_FLOW.get(kot["status"], ()):
                raise PosError(409, "status", f"A {kot['status']} ticket cannot become {status}.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_kots SET status = ?, updated_at = ? WHERE id = ?", (status, now, kot_id))
            self.store._audit(conn, business_id, user, f"kot.{status}", kot_id, {}, now)
            return self._kot(conn, kot_id)

    def move(self, business_id: str, user: str, order_id: str, table_id: str) -> Dict[str, Any]:
        """Move an open dine-in order to another table; if that table has an open order, MERGE into it."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            order = self._order_row(conn, business_id, order_id)
            if order["status"] != "open":
                raise PosError(409, "status", "This order is closed.")
            if conn.execute("SELECT 1 FROM pos_tables WHERE id = ? AND business_id = ? AND active = 1",
                            (table_id, business_id)).fetchone() is None:
                raise PosError(404, "table", "Table not found.")
            if table_id == order["table_id"]:
                return self._order(conn, business_id, order_id)
            now = self.store.clock().isoformat()
            target = conn.execute("SELECT id FROM pos_orders WHERE business_id = ? AND table_id = ? AND status = 'open'",
                                  (business_id, table_id)).fetchone()
            if target is None:
                conn.execute("UPDATE pos_orders SET table_id = ?, kind = 'dine_in', updated_at = ? WHERE id = ?",
                             (table_id, now, order_id))
                self.store._audit(conn, business_id, user, "order.move", order_id, {"to": table_id}, now)
                return self._order(conn, business_id, order_id)
            conn.execute("UPDATE pos_order_items SET order_id = ? WHERE order_id = ?", (target["id"], order_id))
            conn.execute("UPDATE pos_kots SET order_id = ? WHERE order_id = ?", (target["id"], order_id))
            conn.execute("UPDATE pos_orders SET status = 'merged', notes = ?, updated_at = ? WHERE id = ?",
                         (f"merged into {target['id']}", now, order_id))
            self.store._audit(conn, business_id, user, "order.merge", order_id, {"into": target["id"]}, now)
            return self._order(conn, business_id, target["id"])

    def bill(self, business_id: str, user: str, order_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Bill all (or the chosen ``item_ids`` -- split bill) un-billed items through the
        counter's invoice engine, at the CURRENT item prices. Idempotent on client_txn_id."""
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "sell")
            seen = conn.execute("SELECT id FROM pos_invoices WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                invoice_id, replay = seen["id"], True
            else:
                order = self._order_row(conn, business_id, order_id)
                if order["status"] != "open":
                    raise PosError(409, "status", "This order is closed.")
                wanted: Optional[set] = set(data.get("item_ids") or []) or None
                rows = conn.execute("SELECT * FROM pos_order_items WHERE order_id = ? AND status IN ('pending', 'sent')"
                                    " ORDER BY added_at", (order_id,)).fetchall()
                rows = [r for r in rows if wanted is None or r["id"] in wanted]
                if not rows:
                    raise PosError(400, "items", "Nothing left to bill on this order.")
                if wanted is not None and len(rows) != len(wanted):
                    raise PosError(400, "items", "Some chosen items are not on this order or are already billed.")
                if any(r["status"] == "pending" for r in rows) and not data.get("include_unsent"):
                    raise PosError(409, "unsent", "Some items were never sent to the kitchen; send the KOT first"
                                                  " or confirm billing them.")
                merged: Dict[str, int] = {}
                for r in rows:
                    merged[r["product_id"]] = merged.get(r["product_id"], 0) + r["qty_milli"]
                invoice_data = {"lines": [{"product_id": p, "qty_milli": q} for p, q in merged.items()],
                                "customer_id": data.get("customer_id"), "payments": data.get("payments") or [],
                                "notes": f"order {order_id}"}
                digest = _digest({"order": order_id, "items": sorted(r["id"] for r in rows),
                                  "payments": data.get("payments"), "customer_id": data.get("customer_id")})
                invoice_id = self.store._issue(conn, business_id, user, role, invoice_data, txn, digest)
                conn.execute(f"UPDATE pos_order_items SET status = 'billed', invoice_id = ? WHERE id IN"
                             f" ({', '.join('?' for _ in rows)})", (invoice_id, *[r["id"] for r in rows]))
                left = conn.execute("SELECT COUNT(*) AS n FROM pos_order_items WHERE order_id = ? AND status IN"
                                    " ('pending', 'sent')", (order_id,)).fetchone()["n"]
                now = self.store.clock().isoformat()
                if left == 0:
                    conn.execute("UPDATE pos_orders SET status = 'billed', updated_at = ? WHERE id = ?", (now, order_id))
                self.store._audit(conn, business_id, user, "order.bill", order_id,
                                  {"invoice": invoice_id, "items": len(rows), "remaining": left}, now)
                replay = False
        out = self.store.invoice(business_id, user, invoice_id)
        out["replayed"] = replay
        with self.store._connect() as conn:
            out["order"] = self._order(conn, business_id, order_id)
        return out

    def void_order(self, business_id: str, user: str, order_id: str, reason: str) -> Dict[str, Any]:
        """Close an order with nothing billed (guest left). Kept with the reason."""
        reason = _clean(reason, 160)
        if not reason:
            raise PosError(400, "reason", "Say why the order is closed without a bill.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "cancel")
            order = self._order_row(conn, business_id, order_id)
            if order["status"] != "open":
                raise PosError(409, "status", "This order is closed.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_order_items SET status = 'void', void_reason = ? WHERE order_id = ? AND status IN"
                         " ('pending', 'sent')", (reason, order_id))
            conn.execute("UPDATE pos_orders SET status = 'void', notes = ?, updated_at = ? WHERE id = ?",
                         (reason, now, order_id))
            self.store._audit(conn, business_id, user, "order.void", order_id, {"reason": reason}, now)
            return self._order(conn, business_id, order_id)
