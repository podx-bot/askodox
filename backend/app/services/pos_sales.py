"""Sales page for a shop: today / this week / this month, read ONLY from the bills the shop already made
(owner 2026-11-16). Nothing here is stored or invented: totals = issued invoices minus credit notes, payments = what
the cashier recorded, dues = the unpaid balance on those bills. Cancelled bills are counted separately, never in sales."""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from typing import Any, Dict, List

from app.services.pos_store import PosError, PosStore

PERIODS = ("day", "week", "month")


def period_range(period: str, anchor: str) -> tuple:
    d = date.fromisoformat(anchor)
    if period == "day":
        return d, d
    if period == "week":  # Monday .. Sunday of that week
        start = d - timedelta(days=d.weekday())
        return start, start + timedelta(days=6)
    first = d.replace(day=1)
    nxt = (first + timedelta(days=32)).replace(day=1)
    return first, nxt - timedelta(days=1)


class PosSales:
    def __init__(self, store: PosStore) -> None:
        self.store = store

    def summary(self, business_id: str, user: str, period: str = "day", anchor: str = "") -> Dict[str, Any]:
        if period not in PERIODS:
            raise PosError(400, "period", "period must be day, week or month.")
        today = self.store._local(self.store.clock())
        anchor = anchor or today
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", anchor):
            raise PosError(400, "date", "date must be YYYY-MM-DD.")
        try:
            start, end = period_range(period, anchor)
        except ValueError:
            raise PosError(400, "date", "date must be a real day.")
        a, b = start.isoformat(), end.isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            rows = conn.execute(
                "SELECT id, doc_kind, number, issued_at, local_date, customer_snapshot, totals, status, paid_paise,"
                " balance_paise FROM pos_invoices WHERE business_id = ? AND local_date BETWEEN ? AND ?"
                " ORDER BY issued_at DESC", (business_id, a, b)).fetchall()
            sales_paise = returns_paise = cancelled = dues = 0
            bills = 0
            days: Dict[str, Dict[str, int]] = {}
            recent: List[Dict[str, Any]] = []
            issued_ids: List[str] = []
            for r in rows:
                totals = json.loads(r["totals"])
                grand = int(totals.get("grand_total_paise") or 0)
                if r["status"] == "cancelled":
                    cancelled += 1
                    continue
                if r["status"] != "issued":
                    continue
                day = days.setdefault(r["local_date"], {"sales_paise": 0, "bills": 0})
                if r["doc_kind"] == "credit_note":
                    returns_paise += grand
                    day["sales_paise"] -= grand
                    continue
                if r["doc_kind"] != "invoice":
                    continue
                bills += 1
                sales_paise += grand
                dues += int(r["balance_paise"] or 0)
                day["sales_paise"] += grand
                day["bills"] += 1
                issued_ids.append(r["id"])
                if len(recent) < 40:
                    try:
                        customer = json.loads(r["customer_snapshot"] or "{}").get("name") or ""
                    except ValueError:
                        customer = ""
                    recent.append({"id": r["id"], "number": r["number"], "at": r["issued_at"], "customer": customer,
                                   "total_paise": grand, "paid_paise": int(r["paid_paise"] or 0),
                                   "balance_paise": int(r["balance_paise"] or 0)})
            methods: Dict[str, int] = {}
            for p in conn.execute("SELECT method, amount_paise FROM pos_payments WHERE business_id = ? AND local_date"
                                  " BETWEEN ? AND ?", (business_id, a, b)):
                methods[p["method"]] = methods.get(p["method"], 0) + int(p["amount_paise"])
            top: Dict[str, Dict[str, int]] = {}
            for i in range(0, len(issued_ids), 200):
                chunk = issued_ids[i:i + 200]
                marks = ",".join("?" for _ in chunk)
                for ln in conn.execute(f"SELECT name, qty_milli, total_paise FROM pos_invoice_lines WHERE invoice_id IN ({marks})", chunk):
                    t = top.setdefault(ln["name"], {"qty_milli": 0, "total_paise": 0})
                    t["qty_milli"] += int(ln["qty_milli"])
                    t["total_paise"] += int(ln["total_paise"])
        series = []
        cursor = start
        while cursor <= end:
            d = days.get(cursor.isoformat(), {"sales_paise": 0, "bills": 0})
            series.append({"date": cursor.isoformat(), **d})
            cursor += timedelta(days=1)
        return {
            "period": period, "from": a, "to": b, "today": today,
            "bills": bills, "sales_paise": sales_paise, "returns_paise": returns_paise,
            "net_paise": sales_paise - returns_paise, "cancelled": cancelled, "dues_paise": dues,
            "payments": [{"method": m, "amount_paise": v} for m, v in sorted(methods.items(), key=lambda x: -x[1])],
            "days": series,
            "top_items": [{"name": n, **v} for n, v in sorted(top.items(), key=lambda x: -x[1]["total_paise"])[:8]],
            "recent": recent,
            "note": "From your bills only. UPI / card amounts are what the cashier confirmed.",
        }
