"""Quick bill -> REAL bill (owner 2026-11-15: "the calculator bill must become a proper bill: item, rate, GST only if
the shop has GST, advance and pending").

The person says / types lines ("toor dal quarter kilo 30, cashew half kilo 500 ...") plus an advance. This turns them
into a real POS invoice through ``PosStore.create_invoice`` (same numbering, GST rules, idempotency and audit as the
counter):

* every line is a catalogue item of the shop (found by name, else created once), billed at the amount the person gave
  (a price override that only an owner / manager may make; other roles must use the item's own price);
* GST appears only when the shop is registered: the rate is the shop's own choice for the batch (``rate_bp``), never
  guessed;
* ``advance_paise`` is what was already paid; the rest is the pending balance, put on the named customer's credit
  (found by phone, else created). Nothing is held by ASKODOX.
"""
from __future__ import annotations

from typing import Any, Dict, List

from app.services.account_identity import phone_key
from app.services.pos_store import PERMISSIONS, PosError, PosStore, _clean


class PosQuickBill:
    def __init__(self, store: PosStore) -> None:
        self.store = store

    def _customer(self, business_id: str, user: str, data: Dict[str, Any]) -> str:
        if data.get("customer_id"):
            return str(data["customer_id"])
        name = _clean(data.get("name"), 80)
        phone = _clean(data.get("phone"), 20)
        key = phone_key(phone)
        if len(key) >= 10:
            with self.store._connect() as conn:
                for row in conn.execute("SELECT id, phone FROM pos_customers WHERE business_id = ?", (business_id,)):
                    if phone_key(row["phone"]) == key:
                        return row["id"]
        if not name and len(key) < 10:
            raise PosError(400, "customer", "Pending balance needs the customer's name or phone number.")
        return self.store.add_customer(business_id, user, {"name": name or f"Customer {key[-4:]}", "phone": phone})["id"]

    def make(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        txn = _clean(data.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        raw_lines = list(data.get("lines") or [])
        if not raw_lines or len(raw_lines) > 100:
            raise PosError(400, "lines", "Add 1-100 lines.")
        rate_bp = int(data.get("rate_bp") or 0)
        with self.store._connect() as conn:
            role = self.store._require(conn, business_id, user, "sell")
        can_override = "price_override" in PERMISSIONS[role]
        lines: List[Dict[str, Any]] = []
        total = 0
        for index, raw in enumerate(raw_lines, start=1):
            name = _clean(raw.get("name"), 80) or f"Item {index}"
            amount = int(raw.get("amount_paise") or 0)
            if amount <= 0:
                raise PosError(400, "amount", f"Line {index}: enter the amount.")
            with self.store._connect() as conn:
                found = conn.execute("SELECT id, price_paise FROM pos_products WHERE business_id = ? AND active = 1 AND"
                                     " lower(name) = lower(?)", (business_id, name)).fetchone()
            if found is None:
                made = self.store.add_product(business_id, user, {"name": name, "unit": "pcs", "price_paise": amount,
                                                                  "rate_bp": rate_bp, "price_includes_tax": True})
                product_id, listed = made["id"], amount
            else:
                product_id, listed = found["id"], found["price_paise"]
            line: Dict[str, Any] = {"product_id": product_id, "qty_milli": 1000}
            if amount != listed:
                if not can_override:
                    raise PosError(403, "price_override", f"Line {index}: only a manager / owner can bill {name} at a different price.")
                line["unit_price_paise"] = amount
            lines.append(line)
            total += amount
        advance = max(0, int(data.get("advance_paise") or 0))
        payments: List[Dict[str, Any]] = []
        customer_id = None
        if advance:
            method = str(data.get("method") or "cash")
            payments.append({"method": method, "amount_paise": min(advance, total)})
        # GST can make the bill a little more or less than the typed total: the pending balance is whatever is left.
        invoice_data: Dict[str, Any] = {"lines": lines, "payments": payments, "client_txn_id": txn,
                                        "notes": _clean(data.get("notes"), 200)}
        has_customer = any(data.get(k) for k in ("customer_id", "name", "phone"))
        if has_customer:
            customer_id = self._customer(business_id, user, data)
            invoice_data["customer_id"] = customer_id
        if not payments and not has_customer:
            raise PosError(400, "payment", "Say how much was paid (advance), or give the customer for a pending bill.")
        try:
            result = self.store.create_invoice(business_id, user, invoice_data)
        except PosError as error:
            if error.code == "payment" and "more than the bill" in error.message:
                raise PosError(400, "advance", "The advance is more than the bill total.") from error
            raise
        result["pending_paise"] = int(result.get("balance_paise") or 0)
        result["advance_paise"] = int(result.get("paid_paise") or 0)
        return result
