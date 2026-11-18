"""Cashbook (owner 2026-11-18): money in and money out for one shop, month by month.

- Money IN from bills is NEVER typed: one line per day is read from the shop's own payment rows (sales + settled dues,
  refunds taken off), so the cashbook always matches the bills.
- Everything else (vegetables, gas, rent, salary, a catering advance ...) is typed or spoken as an entry.
- Entries are never edited in place: a mistake is removed (kept with ``removed_at``) and can be brought back (undo).
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from app.services.pos_store import IST, PosError, PosStore

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS pos_cashbook (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, kind TEXT NOT NULL,"
    " category TEXT NOT NULL DEFAULT '', amount_paise INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '',"
    " local_date TEXT NOT NULL, at TEXT NOT NULL, by_user TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'manual',"
    " ref TEXT NOT NULL DEFAULT '', client_txn_id TEXT NOT NULL, removed_at TEXT, removed_by TEXT,"
    " UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_cashbook_month ON pos_cashbook(business_id, local_date)",
)

KINDS = ("income", "expense")
# Shown as chips; any other word the owner says is kept as it is.
CATEGORIES = {
    "expense": ("stock", "salary", "rent", "power", "gas", "transport", "repair", "other"),
    "income": ("sale", "advance", "catering", "other"),
}
CATEGORY_TE = {"stock": "సరుకులు", "salary": "జీతాలు", "rent": "అద్దె", "power": "కరెంట్", "gas": "గ్యాస్",
               "transport": "రవాణా", "repair": "రిపేర్", "other": "ఇతరాలు", "sale": "అమ్మకం", "advance": "అడ్వాన్స్",
               "catering": "క్యాటరింగ్"}


def _month_bounds(month: str) -> tuple:
    if not re.fullmatch(r"\d{4}-\d{2}", month or ""):
        month = datetime.now(IST).strftime("%Y-%m")
    return month, f"{month}-01", f"{month}-31"


class PosCashbook:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for stmt in SCHEMA:
                conn.execute(stmt)

    def month(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        month, start, end = _month_bounds(month)
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            rows: List[Dict[str, Any]] = []
            for r in conn.execute(
                    "SELECT local_date, SUM(CASE WHEN kind = 'refund' THEN -amount_paise ELSE amount_paise END) AS total"
                    " FROM pos_payments WHERE business_id = ? AND local_date BETWEEN ? AND ? GROUP BY local_date",
                    (business_id, start, end)):
                if int(r["total"] or 0) > 0:
                    rows.append({"id": f"bills-{r['local_date']}", "kind": "income", "category": "sale",
                                 "amount_paise": int(r["total"]), "note": "", "local_date": r["local_date"],
                                 "source": "bills", "auto": True})
            for r in conn.execute("SELECT * FROM pos_cashbook WHERE business_id = ? AND local_date BETWEEN ? AND ?"
                                  " AND removed_at IS NULL", (business_id, start, end)):
                rows.append({"id": r["id"], "kind": r["kind"], "category": r["category"], "amount_paise": r["amount_paise"],
                             "note": r["note"], "local_date": r["local_date"], "source": r["source"], "auto": False,
                             "at": r["at"]})
        rows.sort(key=lambda x: (x["local_date"], x.get("at") or ""), reverse=True)
        income = sum(x["amount_paise"] for x in rows if x["kind"] == "income")
        expense = sum(x["amount_paise"] for x in rows if x["kind"] == "expense")
        by_category: Dict[str, int] = {}
        for x in rows:
            if x["kind"] == "expense":
                by_category[x["category"] or "other"] = by_category.get(x["category"] or "other", 0) + x["amount_paise"]
        return {"month": month, "entries": rows, "income_paise": income, "expense_paise": expense,
                "balance_paise": income - expense, "expense_by_category": by_category,
                "categories": {k: list(v) for k, v in CATEGORIES.items()}, "labels_te": CATEGORY_TE}

    def add(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        kind = str(data.get("kind") or "")
        if kind not in KINDS:
            raise PosError(400, "kind", "Choose money in or money out.")
        try:
            amount = int(data.get("amount_paise") or 0)
        except (TypeError, ValueError):
            amount = 0
        if amount <= 0 or amount > 10_000_000_00:
            raise PosError(400, "amount", "Write the amount.")
        category = re.sub(r"\s+", " ", str(data.get("category") or "other")).strip().lower()[:30] or "other"
        note = re.sub(r"\s+", " ", str(data.get("note") or "")).strip()[:120]
        txn = str(data.get("client_txn_id") or "")[:60] or uuid.uuid4().hex
        now = datetime.now(IST)
        day = str(data.get("local_date") or "")[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
            day = now.strftime("%Y-%m-%d")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "reports")
            old = conn.execute("SELECT id FROM pos_cashbook WHERE business_id = ? AND client_txn_id = ?",
                               (business_id, txn)).fetchone()
            if old:
                return {"id": old["id"], "repeat": True}
            entry_id = "cb_" + uuid.uuid4().hex[:16]
            conn.execute("INSERT INTO pos_cashbook (id, business_id, kind, category, amount_paise, note, local_date, at,"
                         " by_user, source, ref, client_txn_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                         (entry_id, business_id, kind, category, amount, note, day, now.isoformat(), user,
                          str(data.get("source") or "manual")[:20], str(data.get("ref") or "")[:60], txn))
        return {"id": entry_id}

    def remove(self, business_id: str, user: str, entry_id: str, undo: bool = False) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "reports")
            row = conn.execute("SELECT id FROM pos_cashbook WHERE id = ? AND business_id = ?",
                               (entry_id, business_id)).fetchone()
            if not row:
                raise PosError(404, "entry", "Entry not found.")
            if undo:
                conn.execute("UPDATE pos_cashbook SET removed_at = NULL, removed_by = NULL WHERE id = ?", (entry_id,))
            else:
                conn.execute("UPDATE pos_cashbook SET removed_at = ?, removed_by = ? WHERE id = ?",
                             (datetime.now(IST).isoformat(), user, entry_id))
        return {"ok": True}

    def dues(self, business_id: str, user: str, bills: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
        """Bills with money still due, grouped by customer (name + last 4 digits), biggest first."""
        people: Dict[str, Dict[str, Any]] = {}
        for b in bills or []:
            if int(b.get("due_paise") or 0) <= 0 or b.get("status") == "cancelled":
                continue
            key = f"{(b.get('customer_name') or '').strip().lower()}|{b.get('customer_phone_last4') or ''}"
            person = people.setdefault(key, {"name": b.get("customer_name") or "", "last4": b.get("customer_phone_last4") or "",
                                             "due_paise": 0, "bills": [], "oldest": b.get("local_date")})
            person["due_paise"] += int(b["due_paise"])
            person["bills"].append(b)
            person["oldest"] = min(person["oldest"] or b.get("local_date"), b.get("local_date") or person["oldest"])
        out = sorted(people.values(), key=lambda p: -p["due_paise"])
        return {"people": out, "total_paise": sum(p["due_paise"] for p in out)}
