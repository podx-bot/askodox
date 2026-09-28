"""Real order persistence for buyer requests against real seller_products rows.

Added 2026-09-15 (round 5) after the product owner's own end-to-end test
showed that "placing an order" in the app was purely a local UI animation --
nothing was ever saved anywhere, so neither the buyer nor the seller could
ever see it again. This repository is the real, minimal fix: a plain
`orders` table recording who ordered what from whom, at what price/quantity,
and its status -- everything short of actually moving money (there is still
no real payment processing; see docs/ASKODOX_EXECUTION_TRACKER.md, Master
Architecture Point 21). Mirrors the exact same schema/migration shape as
`product_catalog_repository.py` for consistency.
"""
from __future__ import annotations
import json
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.services.deal_lifecycle import ALL_STATUSES, MESSAGE_KINDS, PAYMENT_STATES

# An order moves through this fixed set of statuses. PLACED is the only
# status a buyer can create; everything else is set by the seller (or by
# the buyer cancelling their own still-open order) via update_status().
# 2026-09-27: the universal lifecycle (deal_lifecycle.py) adds product and
# service execution states, customer confirmation, disputes and CLOSED; the
# original five remain valid for existing clients.
VALID_STATUSES = ALL_STATUSES


class OrderRepository:
    # Columns added after the original schema shipped, following the same
    # ALTER-TABLE-guarded-against-duplicate-column convention as
    # product_catalog_repository.py (CREATE TABLE IF NOT EXISTS never alters
    # an already-existing table on Railway's persistent volume).
    _ADDED_COLUMNS: tuple[str, ...] = (
        "kind", "payment_state", "payment_reference", "payment_verified_by",
        "dispute_escalation_id", "dispute_from_status", "request_context", "closed_at",
        # Engine 11/12: settlement method + return/refund trail.
        "settlement_method", "paid_at", "return_reason", "return_from_status", "refund_reference",
        # Offers engine: the applied offer and its discount (total_amount is after discount).
        "offer_json", "discount",
    )

    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS orders (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    buyer_user_id TEXT NOT NULL,
                    seller_user_id TEXT NOT NULL,
                    product_id INTEGER NOT NULL,
                    product_title TEXT NOT NULL,
                    quantity REAL,
                    unit TEXT,
                    price REAL,
                    currency TEXT NOT NULL DEFAULT 'INR',
                    total_amount REAL,
                    status TEXT NOT NULL DEFAULT 'PLACED',
                    buyer_note TEXT,
                    seller_note TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_orders_buyer ON orders(buyer_user_id, created_at);
                CREATE INDEX IF NOT EXISTS idx_orders_seller ON orders(seller_user_id, created_at);
                CREATE INDEX IF NOT EXISTS idx_orders_product ON orders(product_id);
                CREATE TABLE IF NOT EXISTS order_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    order_id INTEGER NOT NULL,
                    from_role TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    text TEXT,
                    amount REAL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_order_messages_order ON order_messages(order_id, id);
                """
            )
            for column in self._ADDED_COLUMNS:
                try:
                    conn.execute(f"ALTER TABLE orders ADD COLUMN {column} TEXT")
                except sqlite3.OperationalError:
                    pass  # column already exists from a previous startup

    def create_order(
        self,
        *,
        buyer_user_id: str,
        seller_user_id: str,
        product_id: int,
        product_title: str,
        quantity: Optional[float] = None,
        unit: Optional[str] = None,
        price: Optional[float] = None,
        currency: str = "INR",
        buyer_note: Optional[str] = None,
        kind: str = "product",
        request_context: Optional[Dict[str, Any]] = None,
        settlement_method: str = "DIRECT_UPI",
    ) -> int:
        buyer = str(buyer_user_id or "").strip()
        seller = str(seller_user_id or "").strip()
        title = " ".join(str(product_title or "").strip().split())
        if not buyer:
            raise ValueError("buyer_user_id required")
        if not seller:
            raise ValueError("seller_user_id required")
        if not title:
            raise ValueError("product_title required")
        total_amount = (
            float(quantity) * float(price) if quantity is not None and price is not None else price
        )
        now = self._now()
        with self._connect() as conn:
            cur = conn.execute(
                """INSERT INTO orders(
                       buyer_user_id, seller_user_id, product_id, product_title,
                       quantity, unit, price, currency, total_amount, status,
                       buyer_note, seller_note, created_at, updated_at,
                       kind, payment_state, request_context, settlement_method
                   ) VALUES(?,?,?,?,?,?,?,?,?, 'PLACED', ?, NULL, ?, ?, ?, 'NOT_STARTED', ?, ?)""",
                (
                    buyer, seller, int(product_id), title,
                    quantity, unit, price, str(currency or "INR"), total_amount,
                    (str(buyer_note).strip() or None) if buyer_note else None,
                    now, now, str(kind or "product"),
                    json.dumps(request_context, ensure_ascii=False) if request_context else None,
                    str(settlement_method or "DIRECT_UPI"),
                ),
            )
            return int(cur.lastrowid)

    def get(self, order_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM orders WHERE id=?", (int(order_id),)).fetchone()
        return self._row(row) if row else None

    @staticmethod
    def _row(row) -> Dict[str, Any]:
        item = dict(row)
        item["kind"] = item.get("kind") or "product"
        item["payment_state"] = item.get("payment_state") or "NOT_STARTED"
        item["settlement_method"] = item.get("settlement_method") or "DIRECT_UPI"
        raw_offer = item.pop("offer_json", None)
        try:
            item["offer"] = json.loads(raw_offer) if raw_offer else None
        except (TypeError, ValueError):
            item["offer"] = None
        raw = item.get("request_context")
        try:
            item["request_context"] = json.loads(raw) if raw else None
        except (TypeError, ValueError):
            item["request_context"] = None
        return item

    def update_fields(self, order_id: int, **fields: Any) -> bool:
        allowed = {"status", "payment_state", "payment_reference", "payment_verified_by", "dispute_escalation_id",
                   "dispute_from_status", "closed_at", "price", "total_amount", "seller_note",
                   "settlement_method", "paid_at", "return_reason", "return_from_status", "refund_reference",
                   "offer_json", "discount"}
        fields = {k: v for k, v in fields.items() if k in allowed}
        if "status" in fields and fields["status"] not in VALID_STATUSES:
            raise ValueError(f"invalid status: {fields['status']!r}")
        if "payment_state" in fields and fields["payment_state"] not in PAYMENT_STATES:
            raise ValueError(f"invalid payment state: {fields['payment_state']!r}")
        if not fields:
            return False
        fields["updated_at"] = self._now()
        assignments = ", ".join(f"{key}=?" for key in fields)
        with self._connect() as conn:
            cur = conn.execute(f"UPDATE orders SET {assignments} WHERE id=?", (*fields.values(), int(order_id)))
            return cur.rowcount > 0

    def add_message(self, order_id: int, from_role: str, kind: str, text: str = "",
                    amount: Optional[float] = None) -> Dict[str, Any]:
        if kind not in MESSAGE_KINDS:
            raise ValueError(f"invalid message kind: {kind!r}")
        now = self._now()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO order_messages(order_id,from_role,kind,text,amount,created_at) VALUES(?,?,?,?,?,?)",
                (int(order_id), str(from_role), kind, str(text or "").strip()[:2000] or None, amount, now),
            )
            conn.execute("UPDATE orders SET updated_at=? WHERE id=?", (now, int(order_id)))
        return {"id": cur.lastrowid, "order_id": int(order_id), "from_role": from_role, "kind": kind,
                "text": str(text or "").strip()[:2000] or None, "amount": amount, "created_at": now}

    def messages(self, order_id: int) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM order_messages WHERE order_id=? ORDER BY id", (int(order_id),)).fetchall()
        return [dict(row) for row in rows]

    def list_for_buyer(self, buyer_user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        safe_limit = max(1, min(int(limit or 50), 200))
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM orders WHERE buyer_user_id=? ORDER BY id DESC LIMIT ?",
                (str(buyer_user_id or "").strip(), safe_limit),
            ).fetchall()
        return [self._row(row) for row in rows]

    def list_for_seller(self, seller_user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        safe_limit = max(1, min(int(limit or 50), 200))
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM orders WHERE seller_user_id=? ORDER BY id DESC LIMIT ?",
                (str(seller_user_id or "").strip(), safe_limit),
            ).fetchall()
        return [self._row(row) for row in rows]

    def update_status(
        self,
        order_id: int,
        status: str,
        *,
        seller_note: Optional[str] = None,
    ) -> bool:
        clean_status = str(status or "").strip().upper()
        if clean_status not in VALID_STATUSES:
            raise ValueError(f"invalid status: {status!r}")
        now = self._now()
        with self._connect() as conn:
            cur = conn.execute(
                """UPDATE orders SET status=?, seller_note=COALESCE(?, seller_note), updated_at=?
                   WHERE id=?""",
                (clean_status, (str(seller_note).strip() or None) if seller_note else None, now, int(order_id)),
            )
            return cur.rowcount > 0