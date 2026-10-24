"""ASKODOX POS -- self-shopping (scan & go) for supermarkets / stores.

Flow:
  1. The owner / manager turns it on. The POS shows TODAY's entry code (6 digits,
     new every day, also as a QR "ASKODOX-SHOP:<code>") at the entrance.
  2. A signed-in customer types / photographs the code -> a time-limited session
     (default 90 min) in THAT shop only.
  3. The customer photographs barcodes on their own phone; each scan adds the
     item (or its box) to the session's list with the shop's own price. Items
     sold by weight or tracked by serial / IMEI are NOT added -- they need the
     counter (weighing / picking the piece).
  4. "Checkout" locks the list and shows an EXIT CODE.
  5. At the exit, staff open the session (exit code or the list), take ONE photo
     of all items with barcodes up; the phone decodes every barcode and the
     server compares them with the list: matched / not seen (check by hand) /
     not billed. A photo shows each DIFFERENT barcode once, so quantities above
     one are always counted by hand -- the result says so.
  6. Staff bill it as a normal invoice (same tax, numbering, stock, append-only
     records). Payment is the counter's own (cash / UPI / card = cashier
     confirmed); ASKODOX never marks a self-shopping list as paid by itself.

Nothing here changes a price, stock or an issued invoice: the list is a
proposal until staff issue the bill through PosStore.create_invoice.
"""
from __future__ import annotations

import json
import secrets
import sqlite3
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from app.services import pos_tax
from app.services.pos_store import PosError, PosStore, _clean, _id, _round_div

DEFAULT_MINUTES = 90
MAX_ITEMS = 150
QR_PREFIX = "ASKODOX-SHOP:"
WEIGHED_UNITS = {"kg", "g", "l", "ml"}

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_selfshop_settings (business_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL,"
    " minutes INTEGER NOT NULL, updated_by TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_selfshop_codes (business_id TEXT NOT NULL, day TEXT NOT NULL, code TEXT NOT NULL,"
    " PRIMARY KEY (business_id, day), UNIQUE (day, code))",
    "CREATE TABLE IF NOT EXISTS pos_selfshop_sessions (id TEXT PRIMARY KEY, business_id TEXT NOT NULL,"
    " customer_user TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL, expires_at TEXT NOT NULL,"
    " exit_code TEXT, checkout_at TEXT, invoice_id TEXT, closed_by TEXT, closed_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_selfshop_business ON pos_selfshop_sessions(business_id, status)",
    "CREATE INDEX IF NOT EXISTS idx_pos_selfshop_customer ON pos_selfshop_sessions(customer_user, status)",
    "CREATE TABLE IF NOT EXISTS pos_selfshop_items (session_id TEXT NOT NULL, product_id TEXT NOT NULL,"
    " pack TEXT NOT NULL DEFAULT '', qty_milli INTEGER NOT NULL, barcode TEXT NOT NULL DEFAULT '',"
    " added_at TEXT NOT NULL, PRIMARY KEY (session_id, product_id, pack))",
    "CREATE TABLE IF NOT EXISTS pos_selfshop_checks (id TEXT PRIMARY KEY, session_id TEXT NOT NULL,"
    " checked_by TEXT NOT NULL, checked_at TEXT NOT NULL, seen TEXT NOT NULL, result TEXT NOT NULL)",
]

# OPEN (customer adding) -> CHECKOUT (locked, exit code shown) -> BILLED (invoice issued)
# OPEN / CHECKOUT -> CANCELLED (customer or staff) ; any open one -> EXPIRED (time over, lazily)
LIVE = ("OPEN", "CHECKOUT")


class PosSelfShop:
    def __init__(self, store: PosStore) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------ helpers
    def _now(self) -> datetime:
        return self.store.clock()

    def _settings_row(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_selfshop_settings WHERE business_id = ?", (business_id,)).fetchone()
        return {"enabled": bool(row["enabled"]) if row else False,
                "minutes": int(row["minutes"]) if row else DEFAULT_MINUTES}

    def _today_code(self, conn: sqlite3.Connection, business_id: str) -> str:
        day = self.store._local(self._now())
        row = conn.execute("SELECT code FROM pos_selfshop_codes WHERE business_id = ? AND day = ?",
                           (business_id, day)).fetchone()
        if row:
            return row["code"]
        for _ in range(20):
            code = f"{secrets.randbelow(900000) + 100000}"
            try:
                conn.execute("INSERT INTO pos_selfshop_codes (business_id, day, code) VALUES (?, ?, ?)",
                             (business_id, day, code))
                return code
            except sqlite3.IntegrityError:
                continue
        raise PosError(503, "code", "Could not make today's entry code. Try again.")

    def _expire(self, conn: sqlite3.Connection, where: str, args: tuple) -> None:
        now = self._now().isoformat()
        conn.execute(f"UPDATE pos_selfshop_sessions SET status = 'EXPIRED', closed_at = ? WHERE status IN"
                     f" ('OPEN', 'CHECKOUT') AND expires_at < ? AND {where}", (now, now, *args))

    def _session(self, conn: sqlite3.Connection, session_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_selfshop_sessions WHERE id = ?", (session_id,)).fetchone()
        if row is None:
            raise PosError(404, "session", "Shopping session not found.")
        return row

    def _own(self, conn: sqlite3.Connection, user: str, session_id: str) -> sqlite3.Row:
        self._expire(conn, "id = ?", (session_id,))
        row = self._session(conn, session_id)
        if row["customer_user"] != user:
            raise PosError(404, "session", "Shopping session not found.")
        return row

    def _staff_session(self, conn: sqlite3.Connection, business_id: str, user: str, session_id: str,
                       permission: str = "sell") -> sqlite3.Row:
        self.store._require(conn, business_id, user, permission)
        self._expire(conn, "id = ?", (session_id,))
        row = self._session(conn, session_id)
        if row["business_id"] != business_id:
            raise PosError(404, "session", "Shopping session not found.")
        return row

    @staticmethod
    def _attributes(raw: Any) -> Dict[str, Any]:
        try:
            value = json.loads(raw or "{}")
        except (TypeError, ValueError):
            return {}
        return value if isinstance(value, dict) else {}

    @staticmethod
    def _product_card(product: sqlite3.Row, pack: Optional[sqlite3.Row], stock: Optional[int]) -> Dict[str, Any]:
        try:
            attributes = json.loads(product["attributes"] or "{}")
        except (TypeError, ValueError, IndexError, KeyError):
            attributes = {}
        price = product["price_paise"]
        if pack is not None:
            price = pack["price_paise"] if pack["price_paise"] is not None else \
                _round_div(product["price_paise"] * pack["factor_milli"], 1000)
        card = {"product_id": product["id"], "name": product["name"], "name_te": product["name_te"] or "",
                "unit": pack["name"] if pack is not None else product["unit"], "price_paise": price,
                "price_includes_tax": bool(product["price_includes_tax"]), "rate_bp": product["rate_bp"],
                "attributes": attributes, "pack": pack["name"] if pack is not None else ""}
        if product["track_stock"]:
            card["in_stock"] = (stock or 0) > 0
        return card

    def _find_barcode(self, conn: sqlite3.Connection, business_id: str, barcode: str):
        code = "".join(ch for ch in str(barcode or "") if ch.isalnum())[:64]
        if len(code) < 4:
            raise PosError(400, "barcode", "That does not look like a barcode.")
        product = conn.execute("SELECT * FROM pos_products WHERE business_id = ? AND active = 1 AND barcode = ?"
                               " AND COALESCE(channel, '') != 'online'", (business_id, code)).fetchone()
        pack = None
        if product is None:
            hit = conn.execute("SELECT * FROM pos_product_packs WHERE business_id = ? AND barcode = ?",
                               (business_id, code)).fetchone()
            if hit is not None:
                product = conn.execute("SELECT * FROM pos_products WHERE id = ? AND active = 1 AND"
                                       " COALESCE(channel, '') != 'online'", (hit["product_id"],)).fetchone()
                pack = hit if product is not None else None
        if product is None:
            raise PosError(404, "barcode", "This shop has no item with that barcode. Ask the staff.", barcode=code)
        return code, product, pack

    def _lines(self, conn: sqlite3.Connection, session_id: str) -> List[Dict[str, Any]]:
        out = []
        for r in conn.execute("SELECT i.*, p.name, p.name_te, p.unit, p.price_paise, p.rate_bp, p.cess_bp, p.attributes,"
                              " p.category, p.price_includes_tax, p.barcode AS product_barcode"
                              " FROM pos_selfshop_items i JOIN pos_products p ON p.id = i.product_id"
                              " WHERE i.session_id = ? ORDER BY i.added_at, i.rowid", (session_id,)):
            out.append(dict(r))
        return out

    def _priced(self, conn: sqlite3.Connection, business_id: str, lines: List[Dict[str, Any]]) -> Dict[str, Any]:
        """The shop's own prices (packs, rates by quantity) and a tax preview; the counter bill is final."""
        business = self.store._business_row(conn, business_id)
        tiers = self.store._tiers(conn, business_id)
        priced = []
        for l in lines:
            if l["pack"]:
                pack = conn.execute("SELECT * FROM pos_product_packs WHERE business_id = ? AND product_id = ? AND"
                                    " name = ?", (business_id, l["product_id"], l["pack"])).fetchone()
                unit_price = (pack["price_paise"] if pack and pack["price_paise"] is not None else
                              _round_div(l["price_paise"] * (pack["factor_milli"] if pack else 1000), 1000))
            else:
                unit_price = self.store.tier_price(tiers.get(l["product_id"], []), l["qty_milli"]) or l["price_paise"]
            priced.append({"product_id": l["product_id"], "qty_milli": l["qty_milli"], "unit_price_paise": unit_price,
                           "rate_bp": l["rate_bp"], "cess_bp": l["cess_bp"], "category": l["category"],
                           "price_includes_tax": bool(l["price_includes_tax"])})
        if not priced:
            return {"lines": [], "total_paise": 0, "tax_paise": 0}
        try:
            totals = pos_tax.invoice_totals(priced, registration_type=business["registration_type"],
                                            business_state=business["state_code"] or "36",
                                            round_off=bool(business["round_off"]))
        except pos_tax.TaxError:
            return {"lines": [{"unit_price_paise": p["unit_price_paise"]} for p in priced],
                    "total_paise": sum(_round_div(p["qty_milli"] * p["unit_price_paise"], 1000) for p in priced),
                    "tax_paise": 0}
        return {"lines": [{"unit_price_paise": p["unit_price_paise"], "total_paise": t["total_paise"]}
                          for p, t in zip(priced, totals["lines"])],
                "total_paise": totals["totals"]["grand_total_paise"], "tax_paise": totals["totals"]["tax_paise"]}

    def _view(self, conn: sqlite3.Connection, row: sqlite3.Row, *, staff: bool = False) -> Dict[str, Any]:
        business = self.store._business_row(conn, row["business_id"])
        lines = self._lines(conn, row["id"])
        priced = self._priced(conn, row["business_id"], lines)
        items = []
        for l, p in zip(lines, priced["lines"] or [{}] * len(lines)):
            items.append({"product_id": l["product_id"], "name": l["name"], "name_te": l["name_te"] or "",
                          "pack": l["pack"], "unit": l["pack"] or l["unit"], "qty_milli": l["qty_milli"],
                          "barcode": l["barcode"], "unit_price_paise": p.get("unit_price_paise"),
                          "attributes": self._attributes(l.get("attributes")),
                          "total_paise": p.get("total_paise")})
        out = {"id": row["id"], "business_id": row["business_id"], "shop": business["name"], "status": row["status"],
               "started_at": row["started_at"], "expires_at": row["expires_at"], "items": items,
               "total_paise": priced["total_paise"], "tax_paise": priced["tax_paise"],
               "invoice_id": row["invoice_id"],
               "note": "Pay at the counter. The bill the staff print is final; this list is a preview."}
        if row["status"] == "CHECKOUT" or staff:
            out["exit_code"] = row["exit_code"]
        if staff:
            out["customer"] = row["customer_user"][-4:]
            last = conn.execute("SELECT result, checked_at FROM pos_selfshop_checks WHERE session_id = ? ORDER BY"
                                " checked_at DESC LIMIT 1", (row["id"],)).fetchone()
            out["last_check"] = ({**json.loads(last["result"]), "checked_at": last["checked_at"]} if last else None)
        return out

    # ------------------------------------------------------------ staff: settings
    def settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            s = self._settings_row(conn, business_id)
            self._expire(conn, "business_id = ?", (business_id,))
            code = self._today_code(conn, business_id) if s["enabled"] else None
            rows = conn.execute("SELECT * FROM pos_selfshop_sessions WHERE business_id = ? AND status IN"
                                " ('OPEN', 'CHECKOUT') ORDER BY started_at DESC LIMIT 100", (business_id,)).fetchall()
            sessions = []
            for r in rows:
                count = conn.execute("SELECT COUNT(*) AS n FROM pos_selfshop_items WHERE session_id = ?",
                                     (r["id"],)).fetchone()["n"]
                sessions.append({"id": r["id"], "status": r["status"], "started_at": r["started_at"],
                                 "exit_code": r["exit_code"], "items": count, "customer": r["customer_user"][-4:]})
        return {**s, "code": code, "qr": f"{QR_PREFIX}{code}" if code else None,
                "day": self.store._local(self._now()), "sessions": sessions,
                "rules": ["Items sold by weight or tracked by serial / IMEI are billed at the counter.",
                          "A photo shows each different barcode once: count quantities above one by hand.",
                          "Payment is taken at the counter (cash / UPI / card as the cashier confirms)."]}

    def update_settings(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        minutes = int(data.get("minutes") or DEFAULT_MINUTES)
        if not 15 <= minutes <= 240:
            raise PosError(400, "minutes", "A session can last 15 to 240 minutes.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            now = self._now().isoformat()
            enabled = 1 if data.get("enabled") else 0
            conn.execute("INSERT INTO pos_selfshop_settings (business_id, enabled, minutes, updated_by, updated_at)"
                         " VALUES (?, ?, ?, ?, ?) ON CONFLICT(business_id) DO UPDATE SET enabled = excluded.enabled,"
                         " minutes = excluded.minutes, updated_by = excluded.updated_by, updated_at = excluded.updated_at",
                         (business_id, enabled, minutes, user, now))
            self.store._audit(conn, business_id, user, "selfshop.settings", business_id,
                              {"enabled": bool(enabled), "minutes": minutes}, now)
        return self.settings(business_id, user)

    # ------------------------------------------------------------ customer
    def join(self, user: str, code_text: str) -> Dict[str, Any]:
        code = str(code_text or "").strip().upper()
        if code.startswith(QR_PREFIX):
            code = code[len(QR_PREFIX):]
        code = "".join(ch for ch in code if ch.isdigit())
        if len(code) != 6:
            raise PosError(400, "code", "Type the 6-digit code shown at the shop.")
        with self.store._tx() as conn:
            day = self.store._local(self._now())
            hit = conn.execute("SELECT business_id FROM pos_selfshop_codes WHERE day = ? AND code = ?",
                               (day, code)).fetchone()
            if hit is None or not self._settings_row(conn, hit["business_id"])["enabled"]:
                raise PosError(404, "code", "No shop has that code today. Check the code at the entrance.")
            business_id = hit["business_id"]
            self._expire(conn, "customer_user = ?", (user,))
            row = conn.execute("SELECT * FROM pos_selfshop_sessions WHERE business_id = ? AND customer_user = ? AND"
                               " status IN ('OPEN', 'CHECKOUT') ORDER BY started_at DESC LIMIT 1",
                               (business_id, user)).fetchone()
            if row is None:
                now = self._now()
                minutes = self._settings_row(conn, business_id)["minutes"]
                sid = _id("ss")
                conn.execute("INSERT INTO pos_selfshop_sessions (id, business_id, customer_user, status, started_at,"
                             " expires_at) VALUES (?, ?, ?, 'OPEN', ?, ?)",
                             (sid, business_id, user, now.isoformat(), (now + timedelta(minutes=minutes)).isoformat()))
                row = self._session(conn, sid)
            return self._view(conn, row)

    def mine(self, user: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._expire(conn, "customer_user = ?", (user,))
            rows = conn.execute("SELECT * FROM pos_selfshop_sessions WHERE customer_user = ? AND status IN"
                                " ('OPEN', 'CHECKOUT', 'BILLED') ORDER BY started_at DESC LIMIT 5", (user,)).fetchall()
            return {"sessions": [self._view(conn, r) for r in rows]}

    def view(self, user: str, session_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            return self._view(conn, self._own(conn, user, session_id))

    def scan(self, user: str, session_id: str, barcode: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = self._own(conn, user, session_id)
            if row["status"] != "OPEN":
                raise PosError(409, "status", "This list is locked for checkout. Reopen it to add more.")
            code, product, pack = self._find_barcode(conn, row["business_id"], barcode)
            stock = self.store._stock_map(conn, row["business_id"]).get(product["id"], 0)
            card = self._product_card(product, pack, stock)
            if pack is None and product["unit"] in WEIGHED_UNITS:
                return {"added": False, "reason": "weigh_at_counter", "item": card, "session": self._view(conn, row)}
            if product["track_serials"]:
                return {"added": False, "reason": "serial_at_counter", "item": card, "session": self._view(conn, row)}
            count = conn.execute("SELECT COUNT(*) AS n FROM pos_selfshop_items WHERE session_id = ?",
                                 (session_id,)).fetchone()["n"]
            pack_name = pack["name"] if pack is not None else ""
            existing = conn.execute("SELECT qty_milli FROM pos_selfshop_items WHERE session_id = ? AND product_id = ?"
                                    " AND pack = ?", (session_id, product["id"], pack_name)).fetchone()
            if existing is None and count >= MAX_ITEMS:
                raise PosError(400, "items", f"A list holds at most {MAX_ITEMS} different items.")
            now = self._now().isoformat()
            if existing is None:
                conn.execute("INSERT INTO pos_selfshop_items (session_id, product_id, pack, qty_milli, barcode, added_at)"
                             " VALUES (?, ?, ?, 1000, ?, ?)", (session_id, product["id"], pack_name, code, now))
            else:
                conn.execute("UPDATE pos_selfshop_items SET qty_milli = qty_milli + 1000 WHERE session_id = ? AND"
                             " product_id = ? AND pack = ?", (session_id, product["id"], pack_name))
            return {"added": True, "item": card, "session": self._view(conn, row)}

    def set_qty(self, user: str, session_id: str, product_id: str, pack: str, qty_milli: int,
                *, staff_business: Optional[str] = None) -> Dict[str, Any]:
        if qty_milli < 0 or qty_milli % 1000 or qty_milli > 999_000:
            raise PosError(400, "qty", "Quantity must be a whole number from 0 to 999.")
        with self.store._tx() as conn:
            if staff_business is None:
                row = self._own(conn, user, session_id)
                if row["status"] != "OPEN":
                    raise PosError(409, "status", "This list is locked for checkout. Reopen it to change it.")
            else:
                row = self._staff_session(conn, staff_business, user, session_id)
                if row["status"] not in LIVE:
                    raise PosError(409, "status", "This list is closed.")
            pack = _clean(pack, 30)
            hit = conn.execute("SELECT 1 FROM pos_selfshop_items WHERE session_id = ? AND product_id = ? AND pack = ?",
                               (session_id, product_id, pack)).fetchone()
            if hit is None:
                raise PosError(404, "item", "That item is not in the list.")
            if qty_milli == 0:
                conn.execute("DELETE FROM pos_selfshop_items WHERE session_id = ? AND product_id = ? AND pack = ?",
                             (session_id, product_id, pack))
            else:
                conn.execute("UPDATE pos_selfshop_items SET qty_milli = ? WHERE session_id = ? AND product_id = ? AND"
                             " pack = ?", (qty_milli, session_id, product_id, pack))
            if staff_business is not None:
                self.store._audit(conn, staff_business, user, "selfshop.item", session_id,
                                  {"product_id": product_id, "pack": pack, "qty_milli": qty_milli},
                                  self._now().isoformat())
            return self._view(conn, row, staff=staff_business is not None)

    def checkout(self, user: str, session_id: str, reopen: bool = False) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = self._own(conn, user, session_id)
            if reopen:
                if row["status"] != "CHECKOUT":
                    raise PosError(409, "status", "Only a list waiting at checkout can be reopened.")
                conn.execute("UPDATE pos_selfshop_sessions SET status = 'OPEN', exit_code = NULL, checkout_at = NULL"
                             " WHERE id = ?", (session_id,))
            else:
                if row["status"] != "OPEN":
                    raise PosError(409, "status", "This list is not open.")
                if not self._lines(conn, session_id):
                    raise PosError(400, "items", "Scan at least one item first.")
                code = None
                for _ in range(30):
                    candidate = f"{secrets.randbelow(9000) + 1000}"
                    clash = conn.execute("SELECT 1 FROM pos_selfshop_sessions WHERE business_id = ? AND status ="
                                         " 'CHECKOUT' AND exit_code = ?", (row["business_id"], candidate)).fetchone()
                    if clash is None:
                        code = candidate
                        break
                if code is None:
                    raise PosError(503, "exit_code", "Could not make an exit code. Try again.")
                conn.execute("UPDATE pos_selfshop_sessions SET status = 'CHECKOUT', exit_code = ?, checkout_at = ?"
                             " WHERE id = ?", (code, self._now().isoformat(), session_id))
            return self._view(conn, self._session(conn, session_id))

    def cancel(self, user: str, session_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = self._own(conn, user, session_id)
            if row["status"] not in LIVE:
                raise PosError(409, "status", "This list is already closed.")
            conn.execute("UPDATE pos_selfshop_sessions SET status = 'CANCELLED', closed_by = ?, closed_at = ? WHERE id = ?",
                         (user, self._now().isoformat(), session_id))
            return self._view(conn, self._session(conn, session_id))

    # ------------------------------------------------------------ staff: exit check + bill
    def staff_view(self, business_id: str, user: str, session_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            return self._view(conn, self._staff_session(conn, business_id, user, session_id), staff=True)

    def by_exit_code(self, business_id: str, user: str, code: str) -> Dict[str, Any]:
        digits = "".join(ch for ch in str(code or "") if ch.isdigit())
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            self._expire(conn, "business_id = ?", (business_id,))
            row = conn.execute("SELECT * FROM pos_selfshop_sessions WHERE business_id = ? AND status = 'CHECKOUT' AND"
                               " exit_code = ?", (business_id, digits)).fetchone()
            if row is None:
                raise PosError(404, "exit_code", "No list is waiting with that exit code.")
            return self._view(conn, row, staff=True)

    def verify(self, business_id: str, user: str, session_id: str, codes: List[str]) -> Dict[str, Any]:
        """Compare the barcodes seen in ONE photo with the list. Distinct barcodes only."""
        seen = []
        for c in codes[:200]:
            clean = "".join(ch for ch in str(c or "") if ch.isalnum())[:64]
            if clean and clean not in seen:
                seen.append(clean)
        with self.store._tx() as conn:
            row = self._staff_session(conn, business_id, user, session_id)
            if row["status"] not in LIVE:
                raise PosError(409, "status", "This list is closed.")
            lines = self._lines(conn, session_id)
            expected: Dict[str, Dict[str, Any]] = {}
            for l in lines:
                codes_for_line = {l["barcode"]} if l["barcode"] else set()
                if not l["pack"] and l["product_barcode"]:
                    codes_for_line.add(l["product_barcode"])
                for code in codes_for_line:
                    expected[code] = l
            matched, not_seen, count_by_hand = [], [], []
            for l in lines:
                keys = [k for k, v in expected.items() if v is l]
                entry = {"product_id": l["product_id"], "name": l["name"], "pack": l["pack"], "qty_milli": l["qty_milli"]}
                if any(k in seen for k in keys):
                    matched.append(entry)
                    if l["qty_milli"] > 1000:
                        count_by_hand.append(entry)
                else:
                    not_seen.append(entry)
            not_billed = []
            for code in seen:
                if code in expected:
                    continue
                try:
                    _, product, pack = self._find_barcode(conn, business_id, code)
                    not_billed.append({"barcode": code, "product_id": product["id"], "name": product["name"],
                                       "pack": pack["name"] if pack is not None else ""})
                except PosError:
                    not_billed.append({"barcode": code, "product_id": None, "name": None, "pack": ""})
            result = {"matched": matched, "not_seen": not_seen, "not_billed": not_billed,
                      "count_by_hand": count_by_hand, "seen": len(seen),
                      "all_clear": not not_seen and not [n for n in not_billed if n["product_id"]],
                      "note": "One photo shows each different barcode once: check quantities above one by hand."}
            now = self._now().isoformat()
            conn.execute("INSERT INTO pos_selfshop_checks (id, session_id, checked_by, checked_at, seen, result)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (_id("sc"), session_id, user, now, json.dumps(seen), json.dumps(result)))
            self.store._audit(conn, business_id, user, "selfshop.verify", session_id,
                              {"seen": len(seen), "not_seen": len(not_seen), "not_billed": len(not_billed)}, now)
            return result

    def bill(self, business_id: str, user: str, session_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = self._staff_session(conn, business_id, user, session_id)
            if row["status"] == "BILLED" and row["invoice_id"]:
                return {"invoice": self.store.invoice(business_id, user, row["invoice_id"]), "replayed": True}
            if row["status"] != "CHECKOUT":
                raise PosError(409, "status", "The customer must tap Checkout first (the list shows an exit code).")
            lines = [{"product_id": l["product_id"], "qty_milli": l["qty_milli"], **({"pack": l["pack"]} if l["pack"] else {})}
                     for l in self._lines(conn, session_id)]
        if not lines:
            raise PosError(400, "items", "The list is empty.")
        payload = {"lines": lines, "payments": list(data.get("payments") or []),
                   "customer_id": data.get("customer_id") or None, "client_txn_id": f"selfshop-{session_id}"}
        invoice = self.store.create_invoice(business_id, user, payload)
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_selfshop_sessions SET status = 'BILLED', invoice_id = ?, closed_by = ?, closed_at = ?"
                         " WHERE id = ? AND status = 'CHECKOUT'", (invoice["id"], user, self._now().isoformat(), session_id))
        return {"invoice": invoice, "replayed": bool(invoice.get("replayed"))}

    def staff_cancel(self, business_id: str, user: str, session_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = self._staff_session(conn, business_id, user, session_id)
            if row["status"] not in LIVE:
                raise PosError(409, "status", "This list is already closed.")
            now = self._now().isoformat()
            conn.execute("UPDATE pos_selfshop_sessions SET status = 'CANCELLED', closed_by = ?, closed_at = ? WHERE id = ?",
                         (user, now, session_id))
            self.store._audit(conn, business_id, user, "selfshop.cancel", session_id, {}, now)
            return self._view(conn, self._session(conn, session_id), staff=True)
