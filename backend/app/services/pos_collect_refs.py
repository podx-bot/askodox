"""Owner 2026-11-24: ONE rule for every way of working -- the customer pays to the OWNER's own UPI QR, and BOTH the owner
and the person who showed the QR hear "<label> ₹X వచ్చింది" when the notice of that money arrives (`PosPaymentAlerts.
_tell_both`). This module only works out WHAT is being collected (a job card balance, a booking price, a monthly due) and
records the money on that thing once the owner confirms. ASKODOX never holds the money; the owner still checks the bank."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable, Dict, Optional

from app.services.pos_store import PosError

KINDS = ("job", "booking", "member")


def _label_amount(conn: Any, business_id: str, kind: str, ref_id: str, month: str) -> tuple:
    if kind == "job":
        row = conn.execute("SELECT * FROM pos_jobs WHERE id = ? AND business_id = ?", (ref_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "job", "Job not found.")
        left = max(0, int(row["estimate_paise"]) - int(row["advance_paise"]))
        return left, f"టోకెన్ {row['token']} {row['item']}".strip()[:60]
    if kind == "booking":
        row = conn.execute("SELECT b.*, i.name AS item_name, i.price_paise, i.deposit_paise FROM pos_bookings b JOIN"
                           " pos_book_items i ON i.id = b.item_id WHERE b.id = ? AND b.business_id = ?",
                           (ref_id, business_id)).fetchone()
        if row is None:
            raise PosError(404, "booking", "Booking not found.")
        return int(row["price_paise"] or row["deposit_paise"] or 0), f"{row['item_name']} {row['customer_name']}".strip()[:60]
    if kind == "member":
        due = conn.execute("SELECT d.*, m.customer_name FROM pos_month_dues d JOIN pos_month_members m ON m.id = d.member_id"
                           " WHERE d.member_id = ? AND d.business_id = ? AND d.month = ?",
                           (ref_id, business_id, month)).fetchone()
        if due is None:
            raise PosError(404, "member", "No due for that member and month.")
        return max(0, int(due["amount_paise"]) - int(due["paid_paise"])), f"{due['customer_name']} {month}".strip()[:60]
    raise PosError(400, "kind", "kind must be job, booking or member.")


def ask(store: Any, collect: Any, business_id: str, user: str, kind: str, ref_id: str, month: str = "") -> Dict[str, Any]:
    """The owner's UPI QR for a job card balance / booking price / monthly due (one open QR per thing)."""
    month = (month or datetime.now(timezone.utc).strftime("%Y-%m"))[:7]
    with store._connect() as conn:
        store._require(conn, business_id, user, "collect" if kind == "member" else "customers")
        amount, label = _label_amount(conn, business_id, kind, ref_id, month)
        key = f"{kind}:{ref_id}:{month}" if kind == "member" else f"{kind}:{ref_id}"
        got = conn.execute("SELECT * FROM pos_payment_requests WHERE business_id = ? AND ref_key = ? AND status IN"
                           " ('pending', 'matched') ORDER BY created_at DESC LIMIT 1", (business_id, key)).fetchone()
    if got is not None:
        return collect._request_out(got)
    if amount <= 0:
        raise PosError(409, "nothing_due", "Nothing left to collect on this one.")
    out = collect.create_request(business_id, user, {"amount_paise": amount, "label": label, "ref_key": key}, any_member=True)
    return out


def settle(store: Any, business_id: str, request_row: Any, notify: Optional[Callable[..., Any]] = None) -> None:
    """The owner confirmed the money: record it on the job card / monthly due (a record only -- money is with the owner)."""
    key = request_row["ref_key"] if "ref_key" in request_row.keys() else ""
    if not key:
        return
    kind, _, rest = key.partition(":")
    amount = int(request_row["amount_paise"])
    now = datetime.now(timezone.utc).isoformat()
    with store._tx() as conn:
        if kind == "job":
            conn.execute("UPDATE pos_jobs SET advance_paise = MIN(estimate_paise, advance_paise + ?), updated_at = ?"
                         " WHERE id = ? AND business_id = ?", (amount, now, rest, business_id))
        elif kind == "member":
            member_id, _, month = rest.partition(":")
            conn.execute("UPDATE pos_month_dues SET paid_paise = MIN(amount_paise, paid_paise + ?), status = CASE WHEN"
                         " paid_paise + ? >= amount_paise THEN 'paid' ELSE 'due' END, paid_at = ?, updated_at = ?"
                         " WHERE member_id = ? AND business_id = ? AND month = ?",
                         (amount, amount, now, now, member_id, business_id, month))
