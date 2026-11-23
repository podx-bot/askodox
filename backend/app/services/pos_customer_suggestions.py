"""Customer list grows by itself (owner 2026-11-24): people who already ordered from the shop (front desk / shop link /
table orders with a name + phone) or got a bill sent to their number are SUGGESTED for the shop's customer list;
the shop taps ✓ to save (``PosStore.add_customer``) or ✕ to never see that number again. Nothing is saved without
the tap. Payer names from the phone's payment messages stay on the phone (the app suggests those itself).
"""
from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List

SCHEMA = ("CREATE TABLE IF NOT EXISTS pos_customer_suggest_skips (business_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
          " skipped_by TEXT NOT NULL, skipped_at TEXT NOT NULL, PRIMARY KEY (business_id, phone_key))",)
MAX_SUGGESTIONS = 30


def phone_key(phone: Any) -> str:
    digits = re.sub(r"\D", "", str(phone or ""))
    return digits[-10:] if len(digits) >= 10 else ""


def _table(conn: sqlite3.Connection, name: str) -> bool:
    return bool(conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (name,)).fetchone())


def ensure(conn: sqlite3.Connection) -> None:
    for sql in SCHEMA:
        conn.execute(sql)


def suggestions(conn: sqlite3.Connection, business_id: str) -> List[Dict[str, Any]]:
    """Numbers seen in this shop's orders / sent bills that are not in its customer list and were not skipped."""
    ensure(conn)
    known = {phone_key(r[0]) for r in conn.execute("SELECT phone FROM pos_customers WHERE business_id = ?", (business_id,))}
    known |= {r[0] for r in conn.execute("SELECT phone_key FROM pos_customer_suggest_skips WHERE business_id = ?",
                                         (business_id,))}
    seen: Dict[str, Dict[str, Any]] = {}

    def add(key: str, name: str, source: str, at: str) -> None:
        if not key or key in known:
            return
        row = seen.setdefault(key, {"phone": key, "name": "", "times": 0, "last_at": "", "sources": []})
        row["times"] += 1
        if name and not row["name"]:
            row["name"] = name.strip()[:80]
        if source not in row["sources"]:
            row["sources"].append(source)
        row["last_at"] = max(row["last_at"], at or "")

    if _table(conn, "pos_desk_orders"):
        for r in conn.execute("SELECT customer_name, customer_phone, source, placed_at FROM pos_desk_orders WHERE"
                              " business_id = ? AND customer_phone != '' ORDER BY placed_at DESC LIMIT 2000",
                              (business_id,)):
            add(phone_key(r[1]), r[0] or "", "order", r[3])
    if _table(conn, "pos_bill_shares"):
        for r in conn.execute("SELECT phone_key, created_at FROM pos_bill_shares WHERE business_id = ? AND"
                              " length(phone_key) >= 10 ORDER BY created_at DESC LIMIT 2000", (business_id,)):
            add(phone_key(r[0]), "", "bill", r[1])
    rows = list(seen.values())
    rows.sort(key=lambda r: (r["times"], r["last_at"]), reverse=True)
    return rows[:MAX_SUGGESTIONS]


def skip(conn: sqlite3.Connection, business_id: str, phone: str, user: str) -> bool:
    ensure(conn)
    key = phone_key(phone)
    if not key:
        return False
    conn.execute("INSERT OR IGNORE INTO pos_customer_suggest_skips (business_id, phone_key, skipped_by, skipped_at)"
                 " VALUES (?,?,?,?)", (business_id, key, user, datetime.now(timezone.utc).isoformat()))
    return True
