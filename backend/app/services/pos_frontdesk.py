"""ASKODOX Front Desk -- ONE order desk for every way a customer orders (owner 2026-11-15).

Counter / receptionist, a table QR, the shop QR, a parcel or a home delivery all become the same thing: a *desk
order* that walks the same lanes, on top of the POS core (never a copy of it):

    placed -> accepted -> preparing -> ready -> (packed) -> served | handed | out_for_delivery -> delivered -> done

* The customer uses their OWN phone (signed in with their OTP number): scan the shop / table QR, read the shop's
  live menu, order by tapping or by voice, give a delivery address with a map pin, follow the order, pay the shop
  directly. ASKODOX never holds the money (owner rule).
* Staff accept an order only after the kitchen confirms every item is available (an unavailable item is sold-out
  for the rest of the day and the customer is told). Accepting opens the real POS order + KOT (``PosRestaurant``)
  so tables, kitchen display, billing and GST are the shop's existing ones: GST appears on a bill only when the
  shop is registered (``PosStore._issue``), the shop's own GST rate per item, never guessed here.
* Nobody answers in a minute -> the owner is told (``escalate_due``); the customer never waits unseen.
* Customer orders sit in ``pos_desk_orders`` (a staging record, items as a snapshot) until staff accept them, so a
  customer never needs a POS permission and a prank order never touches the kitchen.

Money = integer paise, quantities = milli-units (the POS core's rules).
"""
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services import pos_menu_voice
from app.services.account_identity import phone_key
from app.services.pos_store import PERMISSIONS, PosError, PosStore, _clean, _id

QR_PREFIX = "ASKODOX-ORDER:"

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_desk_orders (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, source TEXT NOT NULL,"
    " kind TEXT NOT NULL, table_id TEXT, customer_user TEXT NOT NULL DEFAULT '', customer_name TEXT NOT NULL DEFAULT '',"
    " customer_phone TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', landmark TEXT NOT NULL DEFAULT '',"
    " lat REAL, lng REAL, items_json TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', stage TEXT NOT NULL,"
    " reason TEXT NOT NULL DEFAULT '', pos_order_id TEXT, invoice_id TEXT, assignee TEXT NOT NULL DEFAULT '',"
    " client_txn_id TEXT NOT NULL, placed_at TEXT NOT NULL, updated_at TEXT NOT NULL, escalated_at TEXT,"
    " UNIQUE (business_id, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_desk_biz ON pos_desk_orders(business_id, stage)",
    "CREATE INDEX IF NOT EXISTS idx_pos_desk_user ON pos_desk_orders(customer_user, placed_at)",
    "CREATE TABLE IF NOT EXISTS pos_desk_events (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id TEXT NOT NULL,"
    " business_id TEXT NOT NULL, stage TEXT NOT NULL, actor TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_pos_desk_events ON pos_desk_events(order_id)",
]

FLOWS: Dict[str, tuple] = {
    "dine_in": ("placed", "accepted", "preparing", "ready", "served", "done"),
    "takeaway": ("placed", "accepted", "preparing", "ready", "packed", "handed", "done"),
    "delivery": ("placed", "accepted", "preparing", "ready", "packed", "out_for_delivery", "delivered", "done"),
}
CLOSED = ("done", "rejected", "cancelled")
SOURCES = ("table_qr", "shop_qr", "counter", "reception")
ESCALATE_AFTER = timedelta(seconds=60)
MAX_OPEN_PER_CUSTOMER = 3

STAGE_TEXT: Dict[str, tuple] = {  # (English, Telugu)
    "placed": ("Order sent. Waiting for the shop to accept.", "ఆర్డర్ పంపాం. షాప్ అంగీకరించే వరకు వేచి ఉండండి."),
    "accepted": ("Accepted. The kitchen has confirmed your items.", "అంగీకరించారు. వంటగది మీ ఐటమ్స్ నిర్ధారించింది."),
    "preparing": ("Being prepared.", "తయారవుతోంది."),
    "ready": ("Ready.", "సిద్ధంగా ఉంది."),
    "packed": ("Packed.", "ప్యాక్ చేశారు."),
    "served": ("Served. Enjoy!", "వడ్డించారు. ఆనందించండి!"),
    "handed": ("Handed over. Thank you!", "అందజేశారు. ధన్యవాదాలు!"),
    "out_for_delivery": ("On its way to you.", "మీ వైపు వస్తోంది."),
    "delivered": ("Delivered. Thank you, come again!", "డెలివరీ అయింది. ధన్యవాదాలు, మళ్ళీ రండి!"),
    "done": ("Completed. Thank you!", "పూర్తయింది. ధన్యవాదాలు!"),
    "rejected": ("The shop could not take this order.", "షాప్ ఈ ఆర్డర్ తీసుకోలేకపోయింది."),
    "cancelled": ("Cancelled.", "రద్దు చేశారు."),
}
_THANKS = ("served", "handed", "delivered", "done")
_FLOOR = ("tables", "kitchen", "sell")


def _maps_url(lat: Optional[float], lng: Optional[float], address: str) -> str:
    if lat is not None and lng is not None:
        return f"https://www.google.com/maps/search/?api=1&query={lat:.6f},{lng:.6f}"
    if address:
        from urllib.parse import quote

        return "https://www.google.com/maps/search/?api=1&query=" + quote(address)
    return ""


def parse_code(code: str) -> Dict[str, Optional[str]]:
    text = str(code or "").strip()
    if text.upper().startswith(QR_PREFIX):
        text = text[len(QR_PREFIX):]
    parts = [p for p in text.split(":") if p]
    if not parts or not re.fullmatch(r"biz_[A-Za-z0-9]{6,40}", parts[0]):
        raise PosError(400, "code", "This QR is not a shop order QR.")
    table = parts[1] if len(parts) > 1 and re.fullmatch(r"tbl_[A-Za-z0-9]{6,40}", parts[1]) else None
    return {"business_id": parts[0], "table_id": table}


class PosFrontDesk:
    def __init__(self, store: PosStore, restaurant: Any, *,
                 notify: Optional[Callable[[str, str, str, str, str], None]] = None,
                 pay_to: Optional[Callable[[str, int, str, str], List[Dict[str, Any]]]] = None) -> None:
        self.store = store
        self.restaurant = restaurant
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.pay_to = pay_to or (lambda owner, amount, note, ref: [])
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------------ helpers
    def _now(self) -> datetime:
        return self.store.clock()

    def _today(self) -> str:
        return self.store._local(self._now())

    def _floor(self, conn: sqlite3.Connection, business_id: str, user: str) -> str:
        """Anyone on the floor (waiter / kitchen / cashier / manager / owner) may work the desk."""
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        if not (PERMISSIONS[role] & set(_FLOOR)):
            raise PosError(403, "permission", f"Your role ({role}) cannot work the order desk.", role=role)
        return role

    def _staff_users(self, conn: sqlite3.Connection, business_id: str) -> List[str]:
        """The owner + every active member who can work the floor (and has an app account)."""
        owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        users = [owner["owner_user_id"]] if owner else []
        for r in conn.execute("SELECT role, app_user_id FROM pos_members WHERE business_id = ? AND active = 1 AND"
                              " app_user_id IS NOT NULL AND app_user_id != ''", (business_id,)):
            if PERMISSIONS.get(r["role"], frozenset()) & set(_FLOOR):
                users.append(r["app_user_id"])
        return list(dict.fromkeys(users))

    def _event(self, conn: sqlite3.Connection, order_id: str, business_id: str, stage: str, actor: str, note: str = "") -> None:
        conn.execute("INSERT INTO pos_desk_events (order_id, business_id, stage, actor, note, at) VALUES (?, ?, ?, ?, ?, ?)",
                     (order_id, business_id, stage, actor, _clean(note, 160), self._now().isoformat()))

    def _push(self, users: List[str], title: str, body: str, route: str, key: str) -> None:
        for u in dict.fromkeys(users):
            try:
                self.notify(u, title, body, route, f"{key}:{u}")
            except Exception:
                pass  # a push problem never fails an order

    # ------------------------------------------------------------------ menu
    def _menu(self, conn: sqlite3.Connection, business_id: str, *, everything: bool = False) -> List[Dict[str, Any]]:
        today = self._today()
        stock = self.store._stock_map(conn, business_id)
        out = []
        for r in conn.execute("SELECT * FROM pos_products WHERE business_id = ? AND active = 1 ORDER BY name", (business_id,)):
            only_on = r["only_on"] if "only_on" in r.keys() else None
            if only_on and only_on != today and not everything:
                continue  # a "today only" item of another day
            sold_out = ("sold_out_on" in r.keys() and r["sold_out_on"] == today)
            tracked_out = bool(r["track_stock"]) and stock.get(r["id"], 0) <= 0
            item = {"id": r["id"], "name": r["name"], "name_te": r["name_te"] or "", "price_paise": r["price_paise"],
                    "unit": r["unit"], "today_only": bool(only_on) and only_on == today,
                    "available": not sold_out and not tracked_out, "rate_bp": r["rate_bp"],
                    "price_includes_tax": bool(r["price_includes_tax"])}
            if everything:
                item["today_only_flag"] = bool(only_on)
                item["sold_out"] = sold_out
            out.append(item)
        return out

    def menu_admin(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self._floor(conn, business_id, user)
            return {"items": self._menu(conn, business_id, everything=True), "today": self._today()}

    def parse_menu(self, business_id: str, user: str, text: str) -> Dict[str, Any]:
        """Spoken / typed menu -> a PREVIEW (nothing is saved). The owner reviews, then calls import_menu."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "products")
            business = self.store._business_row(conn, business_id)
            existing = {pos_menu_voice.normalize(r["name"]): r["price_paise"] for r in conn.execute(
                "SELECT name, price_paise FROM pos_products WHERE business_id = ? AND active = 1", (business_id,))}
        default_unit = "plate" if business["template"] in ("restaurant", "bakery") else "pcs"
        items = pos_menu_voice.parse_menu(text, default_unit)
        for item in items:
            key = pos_menu_voice.normalize(item["name"])
            item["exists"] = key in existing
            item["old_price_paise"] = existing.get(key)
        return {"items": items, "gst": business["registration_type"] != "unregistered"}

    def import_menu(self, business_id: str, user: str, items: List[Dict[str, Any]], rate_bp: int = 0) -> Dict[str, Any]:
        if not items or len(items) > 200:
            raise PosError(400, "items", "Add 1-200 items.")
        created = updated = 0
        today = self._today()
        for raw in items:
            name = _clean(raw.get("name"), 80)
            if not name:
                continue
            price = int(raw.get("price_paise") or 0)
            unit = str(raw.get("unit") or "plate")
            with self.store._connect() as conn:
                found = conn.execute("SELECT id FROM pos_products WHERE business_id = ? AND lower(name) = lower(?)",
                                     (business_id, name)).fetchone()
            if found:
                product_id = found["id"]
                self.store.update_product(business_id, user, product_id, {"price_paise": price, "active": True})
                updated += 1
            else:
                made = self.store.add_product(business_id, user, {"name": name, "unit": unit, "price_paise": price,
                                                                  "rate_bp": int(rate_bp or 0), "price_includes_tax": True})
                product_id = made["id"]
                created += 1
            with self.store._tx() as conn:
                conn.execute("UPDATE pos_products SET only_on = ?, sold_out_on = NULL WHERE id = ? AND business_id = ?",
                             (today if raw.get("today_only") else None, product_id, business_id))
        return {"created": created, "updated": updated}

    def set_availability(self, business_id: str, user: str, product_id: str, available: bool) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            if conn.execute("SELECT 1 FROM pos_products WHERE id = ? AND business_id = ?", (product_id, business_id)).fetchone() is None:
                raise PosError(404, "product", "Item not found.")
            conn.execute("UPDATE pos_products SET sold_out_on = ? WHERE id = ?", (None if available else self._today(), product_id))
            self.store._audit(conn, business_id, user, "menu.availability", product_id, {"available": available},
                              self._now().isoformat())
            return {"id": product_id, "available": bool(available)}

    def set_today_only(self, business_id: str, user: str, product_id: str, today_only: bool) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "products")
            conn.execute("UPDATE pos_products SET only_on = ? WHERE id = ? AND business_id = ?",
                         (self._today() if today_only else None, product_id, business_id))
            return {"id": product_id, "today_only": bool(today_only)}

    # ------------------------------------------------------------------ QR + resolve
    def qr_codes(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "tables")
            tables = [{"id": t["id"], "name": t["name"], "area": t["area"], "code": f"{QR_PREFIX}{business_id}:{t['id']}"}
                      for t in conn.execute("SELECT id, name, area FROM pos_tables WHERE business_id = ? AND active = 1"
                                            " ORDER BY area, name", (business_id,))]
        return {"shop": f"{QR_PREFIX}{business_id}", "tables": tables}

    def resolve(self, code: str, user: str) -> Dict[str, Any]:
        ref = parse_code(code)
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (ref["business_id"],)).fetchone()
            if row is None:
                raise PosError(404, "code", "This shop is not on ASKODOX any more.")
            status = (row["status"] if "status" in row.keys() else "open") or "open"
            table = None
            if ref["table_id"]:
                t = conn.execute("SELECT id, name FROM pos_tables WHERE id = ? AND business_id = ? AND active = 1",
                                 (ref["table_id"], row["id"])).fetchone()
                table = dict(t) if t else None
            menu = self._menu(conn, row["id"]) if status == "open" else []
            last = self._last_items(conn, row["id"], user)
        modes = (["dine_in"] if table else []) + ["takeaway", "delivery"]
        return {"business": {"id": row["id"], "name": row["name"], "address": row["address"], "phone": row["phone"],
                             "status": status, "gst": row["registration_type"] != "unregistered"},
                "table": table, "modes": modes, "menu": menu, "open": status == "open", "last_items": last,
                "message": "" if status == "open" else "ఈ షాప్ ఇప్పుడు తెరిచి లేదు (This shop is closed right now)."}

    def _last_items(self, conn: sqlite3.Connection, business_id: str, user: str) -> List[Dict[str, Any]]:
        row = conn.execute("SELECT items_json FROM pos_desk_orders WHERE business_id = ? AND customer_user = ? AND stage NOT IN"
                           " ('rejected', 'cancelled') ORDER BY placed_at DESC LIMIT 1", (business_id, user)).fetchone()
        if row is None:
            return []
        return [{"product_id": i["product_id"], "name": i["name"], "qty": round(i["qty_milli"] / 1000, 3)}
                for i in json.loads(row["items_json"])]

    def assist(self, code: str, user: str, text: str, cart: Optional[List[Dict[str, Any]]] = None,
               te: bool = True) -> Dict[str, Any]:
        """The receptionist for a customer who scanned the QR: one sentence in, a reply + cart changes out."""
        return self._assist(parse_code(code)["business_id"], user, text, cart, te)

    def assist_counter(self, business_id: str, user: str, text: str, cart: Optional[List[Dict[str, Any]]] = None,
                       te: bool = True) -> Dict[str, Any]:
        """The same receptionist for staff taking a walk-in's order at the counter."""
        with self.store._connect() as conn:
            self._floor(conn, business_id, user)
        return self._assist(business_id, "", text, cart, te)

    def _assist(self, business_id: str, user: str, text: str, cart: Optional[List[Dict[str, Any]]], te: bool) -> Dict[str, Any]:
        with self.store._connect() as conn:
            menu = self._menu(conn, business_id)
            last = self._last_items(conn, business_id, user) if user else []
            popular = {r["product_id"]: r["n"] for r in conn.execute(
                "SELECT product_id, COUNT(*) AS n FROM pos_order_items WHERE business_id = ? GROUP BY product_id", (business_id,))}
        return pos_menu_voice.assist(text, menu, te=te, cart=cart or [], last_items=last, popular=popular)

    # ------------------------------------------------------------------ placing
    def _items_from(self, conn: sqlite3.Connection, business_id: str, raw_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not raw_items or len(raw_items) > 60:
            raise PosError(400, "items", "Choose 1-60 items.")
        menu = {m["id"]: m for m in self._menu(conn, business_id)}
        merged: Dict[str, Dict[str, Any]] = {}
        for raw in raw_items:
            pid = str(raw.get("product_id") or "")
            item = menu.get(pid)
            if item is None:
                raise PosError(400, "items", "An item is not on the menu today.")
            if not item["available"]:
                raise PosError(409, "unavailable", f"{item['name']} is finished for today.", product_id=pid)
            try:
                qty = int(round(float(raw.get("qty") or 1) * 1000))
            except (TypeError, ValueError):
                raise PosError(400, "qty", "Quantity must be a number.")
            if not 1 <= qty <= 50_000:
                raise PosError(400, "qty", "Quantity must be between 1 and 50.")
            line = merged.setdefault(pid, {"product_id": pid, "name": item["name"], "qty_milli": 0, "note": "",
                                           "price_paise": item["price_paise"]})
            line["qty_milli"] += qty
            if raw.get("note"):
                line["note"] = _clean(raw.get("note"), 120)
        return list(merged.values())

    def place(self, user: str, code: Optional[str], payload: Dict[str, Any], *, business_id: Optional[str] = None,
              source: Optional[str] = None) -> Dict[str, Any]:
        """A customer (code = the QR text) or a staff member for a walk-in (business_id + source counter / reception)."""
        txn = _clean(payload.get("client_txn_id"), 64)
        if len(txn) < 8:
            raise PosError(400, "client_txn_id", "client_txn_id (8-64 characters) is required.")
        table_id: Optional[str] = None
        staff_made = business_id is not None
        if code:
            ref = parse_code(code)
            business_id, table_id = ref["business_id"], ref["table_id"]
        if not business_id:
            raise PosError(400, "code", "Scan the shop's QR first.")
        kind = str(payload.get("kind") or ("dine_in" if table_id else "takeaway"))
        if kind not in FLOWS:
            raise PosError(400, "kind", "kind must be dine_in, takeaway or delivery.")
        src = source or ("table_qr" if table_id else "shop_qr")
        if src not in SOURCES:
            raise PosError(400, "source", "Unknown source.")
        with self.store._tx() as conn:
            business = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
            if business is None:
                raise PosError(404, "code", "This shop is not on ASKODOX any more.")
            if staff_made:
                self._floor(conn, business_id, user)
                table_id = payload.get("table_id") or table_id
            if (business["status"] or "open") != "open":
                raise PosError(409, "shop", "ఈ షాప్ ఇప్పుడు తెరిచి లేదు (This shop is closed right now).")
            seen = conn.execute("SELECT * FROM pos_desk_orders WHERE business_id = ? AND client_txn_id = ?",
                                (business_id, txn)).fetchone()
            if seen:
                return self._view(conn, dict(seen), user)
            if kind == "dine_in":
                if not table_id or conn.execute("SELECT 1 FROM pos_tables WHERE id = ? AND business_id = ? AND active = 1",
                                                (table_id, business_id)).fetchone() is None:
                    raise PosError(400, "table", "Scan the QR on your table for dine-in.")
            else:
                table_id = None
            if not staff_made:
                open_now = conn.execute("SELECT COUNT(*) AS n FROM pos_desk_orders WHERE business_id = ? AND customer_user = ?"
                                        " AND stage NOT IN ('done', 'rejected', 'cancelled')", (business_id, user)).fetchone()["n"]
                if open_now >= MAX_OPEN_PER_CUSTOMER:
                    raise PosError(429, "too_many", "You already have 3 orders running here. Wait for one to finish.")
            items = self._items_from(conn, business_id, payload.get("items") or [])
            address = _clean(payload.get("address"), 240)
            lat, lng = self._pin(payload.get("lat"), payload.get("lng"))
            if kind == "delivery" and len(address) < 6 and lat is None:
                raise PosError(400, "address", "Give the delivery address (or drop a map pin).")
            phone = phone_key(payload.get("phone") or "") or (phone_key(user) if not staff_made else "")
            if kind == "delivery" and len(phone) < 10:
                raise PosError(400, "phone", "Give a phone number the delivery person can call.")
            order_id = _id("dsk")
            now = self._now().isoformat()
            conn.execute(
                "INSERT INTO pos_desk_orders (id, business_id, source, kind, table_id, customer_user, customer_name,"
                " customer_phone, address, landmark, lat, lng, items_json, notes, stage, client_txn_id, placed_at,"
                " updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'placed', ?, ?, ?)",
                (order_id, business_id, src, kind, table_id, "" if staff_made else user,
                 _clean(payload.get("name"), 40), phone[-15:], address, _clean(payload.get("landmark"), 80), lat, lng,
                 json.dumps(items), _clean(payload.get("notes"), 160), txn, now, now))
            self._event(conn, order_id, business_id, "placed", user)
            row = dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone())
            targets = self._staff_users(conn, business_id)
            view = self._view(conn, row, user)
        total = sum(i["price_paise"] * i["qty_milli"] // 1000 for i in items)
        self._push([u for u in targets if u != user], "కొత్త ఆర్డర్ · New order",
                   f"{len(items)} ఐటమ్స్ · ₹{total // 100} · {kind}", f"/pos/{business_id}/orders", f"desk:{order_id}:new")
        return view

    @staticmethod
    def _pin(lat: Any, lng: Any) -> tuple:
        """A map pin only when both numbers are real coordinates; otherwise no pin (the typed address still works)."""
        try:
            a, b = float(lat), float(lng)
        except (TypeError, ValueError):
            return None, None
        return (a, b) if -90 <= a <= 90 and -180 <= b <= 180 else (None, None)

    # ------------------------------------------------------------------ views
    def _timeline(self, conn: sqlite3.Connection, order_id: str) -> List[Dict[str, Any]]:
        return [{"stage": e["stage"], "at": e["at"], "note": e["note"]} for e in conn.execute(
            "SELECT stage, at, note FROM pos_desk_events WHERE order_id = ? ORDER BY id", (order_id,))]

    def _view(self, conn: sqlite3.Connection, row: Dict[str, Any], viewer: str, *, staff: bool = False) -> Dict[str, Any]:
        items = json.loads(row["items_json"])
        estimate = sum(i["price_paise"] * i["qty_milli"] // 1000 for i in items if i.get("status") != "unavailable")
        business = conn.execute("SELECT name, owner_user_id, registration_type, phone, address FROM pos_businesses WHERE id = ?",
                                (row["business_id"],)).fetchone()
        table = conn.execute("SELECT name FROM pos_tables WHERE id = ?", (row["table_id"],)).fetchone() if row["table_id"] else None
        flow = FLOWS[row["kind"]]
        nxt = None
        if row["stage"] in flow and row["stage"] != flow[-1]:
            nxt = flow[flow.index(row["stage"]) + 1]
        out: Dict[str, Any] = {
            "id": row["id"], "business_id": row["business_id"], "business_name": business["name"] if business else "",
            "source": row["source"], "kind": row["kind"], "table_name": table["name"] if table else None,
            "stage": row["stage"], "stage_text": {"en": STAGE_TEXT[row["stage"]][0], "te": STAGE_TEXT[row["stage"]][1]},
            "next_stage": nxt, "reason": row["reason"], "items": [
                {"product_id": i["product_id"], "name": i["name"], "qty": round(i["qty_milli"] / 1000, 3),
                 "price_paise": i["price_paise"], "note": i.get("note", ""), "status": i.get("status", "ok")} for i in items],
            "estimate_paise": estimate, "customer_name": row["customer_name"], "notes": row["notes"],
            "address": row["address"], "landmark": row["landmark"], "lat": row["lat"], "lng": row["lng"],
            "maps_url": _maps_url(row["lat"], row["lng"], row["address"]) if row["kind"] == "delivery" else "",
            "assignee": row["assignee"], "placed_at": row["placed_at"], "updated_at": row["updated_at"],
            "can_cancel": row["stage"] == "placed", "timeline": self._timeline(conn, row["id"]),
            "gst": bool(business and business["registration_type"] != "unregistered"),
            "business_phone": business["phone"] if business else "", "invoice": None, "pay": [],
        }
        if row["invoice_id"]:
            inv = conn.execute("SELECT number, totals, paid_paise, balance_paise FROM pos_invoices WHERE id = ?",
                               (row["invoice_id"],)).fetchone()
            if inv:
                totals = json.loads(inv["totals"])
                total = int(totals.get("grand_total_paise") or totals.get("total_paise") or 0)
                out["invoice"] = {"id": row["invoice_id"], "number": inv["number"], "total_paise": total,
                                  "paid_paise": inv["paid_paise"], "balance_paise": inv["balance_paise"]}
                if inv["balance_paise"] > 0 and business:
                    try:
                        out["pay"] = self.pay_to(business["owner_user_id"], inv["balance_paise"], f"Bill {inv['number']}", row["id"])
                    except Exception:
                        out["pay"] = []
        if staff:
            out["customer_phone"] = row["customer_phone"]
            out["customer_user_last4"] = (row["customer_user"] or "")[-4:]
            out["pos_order_id"] = row["pos_order_id"]
            out["escalated"] = bool(row["escalated_at"])
        return out

    def _escalate(self, conn: sqlite3.Connection, business_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Orders nobody accepted for a minute -> tell the OWNER once (the team's lane is the first minute)."""
        cutoff = (self._now() - ESCALATE_AFTER).isoformat()
        sql = "SELECT id, business_id, kind FROM pos_desk_orders WHERE stage = 'placed' AND escalated_at IS NULL AND placed_at <= ?"
        args: List[Any] = [cutoff]
        if business_id:
            sql += " AND business_id = ?"
            args.append(business_id)
        due = [dict(r) for r in conn.execute(sql, args)]
        for d in due:
            conn.execute("UPDATE pos_desk_orders SET escalated_at = ? WHERE id = ?", (self._now().isoformat(), d["id"]))
            self._event(conn, d["id"], d["business_id"], "placed", "system", "owner alerted: nobody accepted in 1 minute")
        return due

    def escalate_due(self) -> int:
        """Called by the periodic runner and lazily by every desk / tracking read."""
        with self.store._tx() as conn:
            due = self._escalate(conn)
            owners = {d["id"]: (conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?",
                                             (d["business_id"],)).fetchone() or [None])[0] for d in due}
        for d in due:
            if owners.get(d["id"]):
                self._push([owners[d["id"]]], "ఆర్డర్ వేచి ఉంది · Order waiting", "ఒక నిమిషం అయింది, ఎవరూ అంగీకరించలేదు",
                           f"/pos/{d['business_id']}/orders", f"desk:{d['id']}:late")
        return len(due)

    # ------------------------------------------------------------------ customer side
    def mine(self, user: str) -> List[Dict[str, Any]]:
        self.escalate_due()
        with self.store._connect() as conn:
            rows = [dict(r) for r in conn.execute("SELECT * FROM pos_desk_orders WHERE customer_user = ? ORDER BY placed_at DESC"
                                                  " LIMIT 20", (user,))]
            return [self._view(conn, r, user) for r in rows]

    def view_mine(self, user: str, order_id: str) -> Dict[str, Any]:
        self.escalate_due()
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            return self._view(conn, dict(row), user)

    def cancel_mine(self, user: str, order_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if row["stage"] != "placed":
                raise PosError(409, "stage", "The shop already accepted this order. Ask the shop to cancel it.")
            conn.execute("UPDATE pos_desk_orders SET stage = 'cancelled', updated_at = ? WHERE id = ?", (self._now().isoformat(), order_id))
            self._event(conn, order_id, row["business_id"], "cancelled", user, "cancelled by the customer")
            return self._view(conn, dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone()), user)

    # ------------------------------------------------------------------ staff side
    def orders(self, business_id: str, user: str, lane: str = "active") -> Dict[str, Any]:
        """lane: active (everything running), new, kitchen, ready, delivery, done."""
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            self._escalate(conn, business_id)
        with self.store._connect() as conn:
            rows = [dict(r) for r in conn.execute("SELECT * FROM pos_desk_orders WHERE business_id = ? ORDER BY placed_at DESC"
                                                  " LIMIT 300", (business_id,))]
            lanes = {
                "new": lambda r: r["stage"] == "placed",
                "kitchen": lambda r: r["stage"] in ("accepted", "preparing"),
                "ready": lambda r: r["stage"] in ("ready", "packed", "served", "handed"),
                "delivery": lambda r: r["kind"] == "delivery" and r["stage"] in ("packed", "out_for_delivery"),
                "done": lambda r: r["stage"] in CLOSED or r["stage"] in ("delivered",),
                "active": lambda r: r["stage"] not in CLOSED,
            }
            pick = lanes.get(lane, lanes["active"])
            counts = {k: sum(1 for r in rows if f(r)) for k, f in lanes.items()}
            return {"orders": [self._view(conn, r, user, staff=True) for r in rows if pick(r)], "counts": counts}

    def order(self, business_id: str, user: str, order_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            return self._view(conn, dict(row), user, staff=True)

    def _set_stage(self, conn: sqlite3.Connection, row: Dict[str, Any], stage: str, actor: str, note: str = "",
                   **fields: Any) -> None:
        now = self._now().isoformat()
        sets = ", ".join(["stage = ?", "updated_at = ?"] + [f"{k} = ?" for k in fields])
        conn.execute(f"UPDATE pos_desk_orders SET {sets} WHERE id = ?", (stage, now, *fields.values(), row["id"]))
        self._event(conn, row["id"], row["business_id"], stage, actor, note)

    def _tell_customer(self, row: Dict[str, Any], stage: str, extra: str = "") -> None:
        if not row.get("customer_user"):
            return
        en, te = STAGE_TEXT[stage]
        title = f"{te.split('.')[0]}" if stage not in _THANKS else te
        self._push([row["customer_user"]], title[:70], (extra or en)[:160], f"/order/track/{row['id']}", f"desk:{row['id']}:{stage}")

    def confirm(self, business_id: str, user: str, order_id: str, decisions: Optional[Dict[str, bool]] = None,
                note: str = "") -> Dict[str, Any]:
        """The kitchen's yes/no per item. Yes for all (or some) -> the order is accepted and a real KOT is cut; an item
        the kitchen cannot make is sold out for today and the customer is told which. Nothing left -> rejected."""
        decisions = decisions or {}
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            if row["stage"] != "placed":
                raise PosError(409, "stage", "This order was already answered.")
            items = json.loads(row["items_json"])
            kept, dropped = [], []
            for i in items:
                if i.get("status") != "unavailable" and decisions.get(i["product_id"], True):
                    i["status"] = "ok"
                    kept.append(i)
                else:
                    i["status"] = "unavailable"
                    dropped.append(i)
                    conn.execute("UPDATE pos_products SET sold_out_on = ? WHERE id = ? AND business_id = ?",
                                 (self._today(), i["product_id"], business_id))
            conn.execute("UPDATE pos_desk_orders SET items_json = ? WHERE id = ?", (json.dumps(items), order_id))
            owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()["owner_user_id"]
            if not kept:
                self._set_stage(conn, row, "rejected", user, note or "no item available", reason=_clean(note, 160) or "not_available")
        if not kept:
            self._tell_customer(row, "rejected", "ఈ ఐటమ్స్ ఇప్పుడు లేవు (these items are finished)")
            return self.order(business_id, user, order_id)
        # the real POS order + KOT, made as the owner (a system action; the actor is in the desk timeline)
        pos_order = self.restaurant.open_order(business_id, owner, {"kind": row["kind"], "table_id": row["table_id"],
                                                                    "notes": f"desk {order_id}"})
        self.restaurant.add_items(business_id, owner, pos_order["id"], [
            {"product_id": i["product_id"], "qty_milli": i["qty_milli"], "note": i.get("note", ""),
             "client_txn_id": f"{order_id}:{i['product_id']}"} for i in kept])
        self.restaurant.send_kot(business_id, owner, pos_order["id"])
        with self.store._tx() as conn:
            row = dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone())
            self._set_stage(conn, row, "accepted", user, note, pos_order_id=pos_order["id"])
        names = ", ".join(i["name"] for i in dropped)
        self._tell_customer(row, "accepted", (f"లేనివి: {names}. " if names else "") + STAGE_TEXT["accepted"][1])
        return self.order(business_id, user, order_id)

    def reject(self, business_id: str, user: str, order_id: str, reason: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            if row["stage"] in CLOSED:
                raise PosError(409, "stage", "This order is already closed.")
            self._set_stage(conn, row, "rejected", user, reason, reason=_clean(reason, 160))
        self._tell_customer(row, "rejected", _clean(reason, 120))
        return self.order(business_id, user, order_id)

    def advance(self, business_id: str, user: str, order_id: str, stage: str, assignee: str = "") -> Dict[str, Any]:
        """Forward only along this order's own lane; 'preparing' may be skipped."""
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            flow = FLOWS[row["kind"]]
            if row["stage"] in CLOSED or row["stage"] == "placed":
                raise PosError(409, "stage", "Accept the order first." if row["stage"] == "placed" else "This order is closed.")
            if stage not in flow or flow.index(stage) <= flow.index(row["stage"]):
                raise PosError(409, "stage", f"A {row['stage']} order cannot go to {stage}.")
            expected = flow[flow.index(row["stage"]) + 1]
            if stage != expected and not (row["stage"] == "accepted" and stage == "ready"):
                raise PosError(409, "stage", f"Next step is {expected}.")
            if stage == "done" and not row["invoice_id"]:
                raise PosError(409, "bill", "Make the bill before closing the order.")
            if stage == "out_for_delivery" and not (_clean(assignee, 40) or row["assignee"]):
                raise PosError(400, "assignee", "Say who is taking it (delivery person's name).")
            fields: Dict[str, Any] = {}
            if _clean(assignee, 40):
                fields["assignee"] = _clean(assignee, 40)
            self._set_stage(conn, row, stage, user, **fields)
            # keep the kitchen display in step
            if row["pos_order_id"] and stage in ("preparing", "ready"):
                for kot in conn.execute("SELECT id, status FROM pos_kots WHERE order_id = ?", (row["pos_order_id"],)).fetchall():
                    if stage == "preparing" and kot["status"] == "new":
                        conn.execute("UPDATE pos_kots SET status = 'preparing', updated_at = ? WHERE id = ?", (self._now().isoformat(), kot["id"]))
                    if stage == "ready" and kot["status"] in ("new", "preparing"):
                        conn.execute("UPDATE pos_kots SET status = 'ready', updated_at = ? WHERE id = ?", (self._now().isoformat(), kot["id"]))
        if stage in ("ready", "out_for_delivery") or stage in _THANKS:
            extra = f"{fields.get('assignee', row['assignee'])} తీసుకొస్తున్నారు" if stage == "out_for_delivery" else ""
            self._tell_customer(row, stage, extra)
        return self.order(business_id, user, order_id)

    def bill(self, business_id: str, user: str, order_id: str, payments: Optional[List[Dict[str, Any]]] = None,
             client_txn_id: str = "", customer_id: Optional[str] = None) -> Dict[str, Any]:
        """Bill through the POS core (GST only if the shop is registered). ``payments`` are the cashier's confirmation of
        what was paid; a bill not fully paid needs a ``customer_id`` (the balance goes on that customer's credit)."""
        with self.store._connect() as conn:
            role = self._floor(conn, business_id, user)
            if "sell" not in PERMISSIONS[role]:
                raise PosError(403, "permission", f"Your role ({role}) cannot bill.", role=role)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
        if not row["pos_order_id"]:
            raise PosError(409, "stage", "Accept the order before billing it.")
        txn = _clean(client_txn_id, 64) or f"dskbill-{order_id}"
        result = self.restaurant.bill(business_id, user, row["pos_order_id"],
                                      {"client_txn_id": txn, "payments": payments or [], "include_unsent": True,
                                       "customer_id": customer_id})
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_desk_orders SET invoice_id = ?, updated_at = ? WHERE id = ?",
                         (result["id"], self._now().isoformat(), order_id))
            self._event(conn, order_id, business_id, row["stage"], user, f"billed {result.get('number', '')}")
        out = self.order(business_id, user, order_id)
        out["invoice_number"] = result.get("number")
        return out

    def assign(self, business_id: str, user: str, order_id: str, assignee: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            conn.execute("UPDATE pos_desk_orders SET assignee = ?, updated_at = ? WHERE id = ? AND business_id = ?",
                         (_clean(assignee, 40), self._now().isoformat(), order_id, business_id))
        return self.order(business_id, user, order_id)
