"""Structured purchase and usage memory for ASKODOX history/OASAT recall."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any


class PurchaseHistoryRepository:
    """Persist repeat-purchase context without depending on chat reconstruction."""

    TABLE = "purchase_history"

    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _clean_text(value: Any, field: str) -> str:
        text = " ".join(str(value or "").strip().split())
        if not text:
            raise ValueError(f"{field} is required")
        return text

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                f"""
                CREATE TABLE IF NOT EXISTS {self.TABLE}(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    seller_id TEXT,
                    seller_name TEXT,
                    item_name TEXT NOT NULL,
                    quantity REAL NOT NULL,
                    unit TEXT,
                    unit_price REAL NOT NULL,
                    total_price REAL NOT NULL,
                    purchased_at TEXT NOT NULL,
                    usage_days INTEGER,
                    remaining_status TEXT,
                    repeat_cycle_days INTEGER,
                    preference_note TEXT,
                    conversation_rationale TEXT,
                    source_reference TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_purchase_history_user_recent
                    ON {self.TABLE}(user_id, purchased_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS idx_purchase_history_user_item
                    ON {self.TABLE}(user_id, item_name, purchased_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS idx_purchase_history_user_seller
                    ON {self.TABLE}(user_id, seller_name, purchased_at DESC, id DESC);
                """
            )

    def add_purchase(
        self,
        user_id: str,
        *,
        item_name: str,
        quantity: float,
        unit_price: float,
        seller_id: str | None = None,
        seller_name: str | None = None,
        unit: str | None = None,
        purchased_at: str | None = None,
        usage_days: int | None = None,
        remaining_status: str | None = None,
        repeat_cycle_days: int | None = None,
        preference_note: str | None = None,
        conversation_rationale: str | None = None,
        source_reference: str | None = None,
    ) -> int:
        uid = self._clean_text(user_id, "user_id")
        item = self._clean_text(item_name, "item_name")
        qty = float(quantity)
        price = float(unit_price)
        if qty <= 0:
            raise ValueError("quantity must be greater than zero")
        if price < 0:
            raise ValueError("unit_price must be zero or greater")
        total = round(qty * price, 2)
        when = str(purchased_at or self._now())
        usage = None if usage_days is None else max(0, int(usage_days))
        repeat = None if repeat_cycle_days is None else max(0, int(repeat_cycle_days))
        status = None if remaining_status is None else str(remaining_status).strip().upper()
        if status not in {None, "REMAINING", "FINISHED", "UNKNOWN"}:
            raise ValueError("remaining_status must be REMAINING, FINISHED, or UNKNOWN")

        with self._connect() as conn:
            cur = conn.execute(
                f"""
                INSERT INTO {self.TABLE}(
                    user_id,seller_id,seller_name,item_name,quantity,unit,unit_price,
                    total_price,purchased_at,usage_days,remaining_status,repeat_cycle_days,
                    preference_note,conversation_rationale,source_reference,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    uid,
                    None if seller_id is None else str(seller_id),
                    None if seller_name is None else " ".join(str(seller_name).strip().split()),
                    item,
                    qty,
                    None if unit is None else str(unit).strip(),
                    round(price, 2),
                    total,
                    when,
                    usage,
                    status,
                    repeat,
                    preference_note,
                    conversation_rationale,
                    source_reference,
                    self._now(),
                ),
            )
            return int(cur.lastrowid)

    def recent_purchases(self, user_id: str, limit: int = 20) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                f"SELECT * FROM {self.TABLE} WHERE user_id=? ORDER BY purchased_at DESC, id DESC LIMIT ?",
                (str(user_id), max(1, min(int(limit), 100))),
            ).fetchall()
        return [dict(row) for row in rows]

    def item_history(self, user_id: str, item_name: str, limit: int = 10) -> list[dict[str, Any]]:
        item = self._clean_text(item_name, "item_name")
        with self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT * FROM {self.TABLE}
                WHERE user_id=? AND lower(item_name)=lower(?)
                ORDER BY purchased_at DESC, id DESC LIMIT ?
                """,
                (str(user_id), item, max(1, min(int(limit), 50))),
            ).fetchall()
        return [dict(row) for row in rows]

    def latest_item_purchase(self, user_id: str, item_name: str) -> dict[str, Any] | None:
        rows = self.item_history(user_id, item_name, limit=1)
        return rows[0] if rows else None

    def update_usage(
        self,
        purchase_id: int,
        *,
        usage_days: int | None = None,
        remaining_status: str | None = None,
        repeat_cycle_days: int | None = None,
    ) -> bool:
        updates: list[str] = []
        params: list[Any] = []
        if usage_days is not None:
            updates.append("usage_days=?")
            params.append(max(0, int(usage_days)))
        if remaining_status is not None:
            status = str(remaining_status).strip().upper()
            if status not in {"REMAINING", "FINISHED", "UNKNOWN"}:
                raise ValueError("remaining_status must be REMAINING, FINISHED, or UNKNOWN")
            updates.append("remaining_status=?")
            params.append(status)
        if repeat_cycle_days is not None:
            updates.append("repeat_cycle_days=?")
            params.append(max(0, int(repeat_cycle_days)))
        if not updates:
            return False
        params.append(int(purchase_id))
        with self._connect() as conn:
            cur = conn.execute(
                f"UPDATE {self.TABLE} SET {', '.join(updates)} WHERE id=?",
                tuple(params),
            )
            return cur.rowcount > 0

    def repeat_context(self, user_id: str, item_name: str) -> dict[str, Any] | None:
        """Return compact OASAT-ready recall for a repeat purchase decision."""
        latest = self.latest_item_purchase(user_id, item_name)
        if latest is None:
            return None
        return {
            "purchase_id": latest["id"],
            "item_name": latest["item_name"],
            "seller_id": latest["seller_id"],
            "seller_name": latest["seller_name"],
            "last_quantity": latest["quantity"],
            "unit": latest["unit"],
            "last_unit_price": latest["unit_price"],
            "last_total_price": latest["total_price"],
            "purchased_at": latest["purchased_at"],
            "usage_days": latest["usage_days"],
            "remaining_status": latest["remaining_status"],
            "repeat_cycle_days": latest["repeat_cycle_days"],
            "preference_note": latest["preference_note"],
            "conversation_rationale": latest["conversation_rationale"],
        }
