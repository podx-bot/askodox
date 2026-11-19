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
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services import pos_menu_voice
from app.services.account_identity import phone_key
from app.services.pos_bills import PosBills
from app.services.pos_desk_requests import PosDeskRequests
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
    # Who is told about which step + the shop's auto-confirm switch (owner 2026-11-16). One row per shop.
    "CREATE TABLE IF NOT EXISTS pos_desk_settings (business_id TEXT PRIMARY KEY, routing_json TEXT NOT NULL DEFAULT '{}',"
    " auto_confirm INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL)",
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
    "accepting": ("Order sent. Waiting for the shop to accept.", "ఆర్డర్ పంపాం. షాప్ అంగీకరించే వరకు వేచి ఉండండి."),
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
_FLOOR = ("tables", "kitchen", "sell", "deliver")
ROUTE_EVENTS = ("new", "kitchen", "ready", "delivery")


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



def _rupees(paise: Any) -> str:
    try:
        n = int(paise or 0)
    except (TypeError, ValueError):
        n = 0
    return f"₹{n // 100}" + (f".{n % 100:02d}" if n % 100 else "")

class PosFrontDesk:
    def __init__(self, store: PosStore, restaurant: Any, *,
                 notify: Optional[Callable[[str, str, str, str, str], None]] = None,
                 pay_to: Optional[Callable[[str, int, str, str], List[Dict[str, Any]]]] = None,
                 bills: Optional[PosBills] = None) -> None:
        self.store = store
        # Bills go to the customer's own "My bills" (owner 2026-11-16); the same notify / pay_to unless one is given.
        self.bills = bills
        self.restaurant = restaurant
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.pay_to = pay_to or (lambda owner, amount, note, ref: [])
        if self.bills is None:
            self.bills = PosBills(store, notify=self.notify, pay_to=self.pay_to, clock=self._now)
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            try:
                conn.execute("ALTER TABLE pos_products ADD COLUMN item_no INTEGER")
            except sqlite3.OperationalError:
                pass
            try:  # who the order is assigned to (an app user), next to the typed name
                conn.execute("ALTER TABLE pos_desk_orders ADD COLUMN assignee_user TEXT NOT NULL DEFAULT ''")
            except sqlite3.OperationalError:
                pass
            try:  # owner 2026-11-18: the customer says how they will pay -- cash or online ('' = not said)
                conn.execute("ALTER TABLE pos_desk_orders ADD COLUMN pay_choice TEXT NOT NULL DEFAULT ''")
            except sqlite3.OperationalError:
                pass

        self.requests = PosDeskRequests(self)  # table service requests (water / gravy / onions / bill)
        self._ratings = None
        _ = self.ratings  # ratings / reviews / welcome tables made now, never inside a read

    # ------------------------------------------------------------------ helpers
    def _now(self) -> datetime:
        return self.store.clock()

    def _today(self) -> str:
        return self.store._local(self._now())

    def _floor(self, conn: sqlite3.Connection, business_id: str, user: str, *, delivery_ok: bool = False) -> str:
        """Anyone on the floor (waiter / kitchen / cashier / manager / owner) may work the desk. A delivery person only
        sees and moves the delivery orders assigned to them (delivery_ok)."""
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        if not (PERMISSIONS[role] & set(_FLOOR)):
            raise PosError(403, "permission", f"Your role ({role}) cannot work the order desk.", role=role)
        if role == "delivery" and not delivery_ok:
            raise PosError(403, "permission", "A delivery person can only take the delivery orders assigned to them.", role=role)
        return role

    # ------------------------------------------------------------------ who is told (owner 2026-11-16)
    def _people(self, conn: sqlite3.Connection, business_id: str) -> List[Dict[str, Any]]:
        """The owner + every active member with an app account: the people an order can be assigned / routed to."""
        owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        people = [{"id": owner["owner_user_id"], "role": "owner", "label": "Owner"}] if owner else []
        if people:
            people[0]["accepts_orders"] = True
        for r in conn.execute("SELECT role, app_user_id, label, phone_key, accepts_orders FROM pos_members WHERE"
                              " business_id = ? AND active = 1 AND paused = 0 AND role != 'owner'"
                              " AND app_user_id IS NOT NULL AND app_user_id != ''", (business_id,)):
            people.append({"id": r["app_user_id"], "role": r["role"], "last4": str(r["phone_key"])[-4:],
                           "label": r["label"] or f"••{str(r['phone_key'])[-4:]}",
                           "accepts_orders": bool(r["accepts_orders"])})
        return people

    def _may_accept(self, conn: sqlite3.Connection, business_id: str, user: str) -> None:
        """Owner 2026-11-17: an order is accepted (or turned down) only by the owner, or by a person the owner allowed
        ('accepts orders', not paused). Never by the server on its own."""
        if any(p["id"] == user and p.get("accepts_orders") for p in self._people(conn, business_id)):
            return
        raise PosError(403, "accept", "Only the owner, or a person the owner allowed, can accept orders here.")

    @property
    def ratings(self) -> Any:
        """Ratings / reviews / welcome on the same store (created once)."""
        if getattr(self, "_ratings", None) is None:
            from app.services.pos_ratings import PosRatings

            self._ratings = PosRatings(self.store, clock=self._now)
        return self._ratings

    def _routing(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT routing_json, auto_confirm FROM pos_desk_settings WHERE business_id = ?", (business_id,)).fetchone()
        try:
            routing = json.loads(row["routing_json"]) if row else {}
        except ValueError:
            routing = {}
        # auto-confirm is gone (owner 2026-11-17: a person always accepts); the key stays False for old apps
        return {"routing": {k: [str(x) for x in routing.get(k, []) if x] for k in ROUTE_EVENTS},
                "auto_confirm": False}

    def _targets(self, conn: sqlite3.Connection, business_id: str, event: str) -> List[str]:
        """Who hears about [event]: the people the owner chose; otherwise by role -- new order: owner / manager / cashier,
        kitchen: owner / kitchen, ready: owner / waiter / cashier, delivery: owner / delivery. Never everyone."""
        people = self._people(conn, business_id)
        valid = {p["id"] for p in people if event != "new" or p.get("accepts_orders")}  # a new order rings only accepters
        chosen = [u for u in self._routing(conn, business_id)["routing"].get(event, []) if u in valid]
        if chosen:
            return list(dict.fromkeys(chosen))
        if event == "new":  # the people who may accept it
            return list(dict.fromkeys(p["id"] for p in people if p.get("accepts_orders")))
        roles = {"kitchen": ("owner", "kitchen", "manager"),
                 "ready": ("owner", "waiter", "cashier"), "delivery": ("owner", "delivery")}[event]
        return list(dict.fromkeys(p["id"] for p in people if p["role"] in roles))

    def people(self, business_id: str, user: str) -> Dict[str, Any]:
        """Who an order can be assigned to (the floor staff see it; a delivery person does not)."""
        with self.store._connect() as conn:
            self._floor(conn, business_id, user)
            return {"people": [{**p, "you": p["id"] == user} for p in self._people(conn, business_id)]}

    def desk_settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "settings")
            out = self._routing(conn, business_id)
            out["people"] = [{**p, "you": p["id"] == user} for p in self._people(conn, business_id)]
            out["defaults"] = {e: self._targets_default(conn, business_id, e) for e in ROUTE_EVENTS}
            return out

    def _targets_default(self, conn: sqlite3.Connection, business_id: str, event: str) -> List[str]:
        if event == "new":
            return [p["id"] for p in self._people(conn, business_id) if p.get("accepts_orders")]
        roles = {"new": ("owner", "manager", "cashier"), "kitchen": ("owner", "kitchen", "manager"),
                 "ready": ("owner", "waiter", "cashier"), "delivery": ("owner", "delivery")}[event]
        return [p["id"] for p in self._people(conn, business_id) if p["role"] in roles]

    def set_desk_settings(self, business_id: str, user: str, routing: Optional[Dict[str, Any]],
                          auto_confirm: Optional[bool]) -> Dict[str, Any]:
        """Owner only. routing {event: [user ids]} (empty list = the role defaults); auto_confirm on/off."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            valid = {p["id"] for p in self._people(conn, business_id)}
            current = self._routing(conn, business_id)
            merged = dict(current["routing"])
            for event, ids in (routing or {}).items():
                if event not in ROUTE_EVENTS:
                    raise PosError(400, "routing", f"Unknown step {event}.")
                if not isinstance(ids, list) or any(str(i) not in valid for i in ids):
                    raise PosError(400, "routing", "Choose people who are on this shop's staff.")
                merged[event] = [str(i) for i in ids][:10]
            auto = False  # auto-confirm removed (owner 2026-11-17)
            conn.execute("INSERT INTO pos_desk_settings (business_id, routing_json, auto_confirm, updated_at) VALUES (?, ?, ?, ?)"
                         " ON CONFLICT(business_id) DO UPDATE SET routing_json = excluded.routing_json,"
                         " auto_confirm = excluded.auto_confirm, updated_at = excluded.updated_at",
                         (business_id, json.dumps(merged), 1 if auto else 0, self._now().isoformat()))
        return self.desk_settings(business_id, user)

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

    def _push(self, users: List[str], title: str, body: str, route: str, key: str, speak: bool = False) -> None:
        """speak=True: the phone also SAYS it (new order, a table asking for water) -- owner 2026-11-17."""
        for u in dict.fromkeys(users):
            try:
                if speak:
                    try:
                        self.notify(u, title, body, route, f"{key}:{u}",
                                    speak={"type": "say", "title": title, "text": f"{title}. {body}"[:300]})
                        continue
                    except TypeError:
                        pass  # an older notify without speech: a normal notification
                self.notify(u, title, body, route, f"{key}:{u}")
            except Exception:
                pass  # a push problem never fails an order

    # ------------------------------------------------------------------ menu
    def _menu(self, conn: sqlite3.Connection, business_id: str, *, everything: bool = False) -> List[Dict[str, Any]]:
        today = self._today()
        stock = self.store._stock_map(conn, business_id)
        PosBills.number_items(conn, business_id)  # every item has its menu number (billing by number)
        out = []
        photos: set = set()
        sold: Dict[str, int] = {}
        if everything:  # the owner's menu pages show the photo and how many sold today (owner 2026-11-18)
            try:
                photos = {r[0] for r in conn.execute("SELECT product_id FROM pos_product_photos WHERE business_id = ?",
                                                     (business_id,))}
                for r in conn.execute(
                        "SELECT l.product_id AS pid, SUM(l.qty_milli) AS q FROM pos_invoice_lines l JOIN pos_invoices i"
                        " ON i.id = l.invoice_id WHERE i.business_id = ? AND i.local_date = ? AND i.status != 'cancelled'"
                        " AND i.doc_kind = 'invoice' GROUP BY l.product_id", (business_id, today)):
                    if r["pid"]:
                        sold[r["pid"]] = int((r["q"] or 0) // 1000)
            except Exception:
                pass
        for r in conn.execute("SELECT * FROM pos_products WHERE business_id = ? AND active = 1 ORDER BY item_no, name", (business_id,)):
            only_on = r["only_on"] if "only_on" in r.keys() else None
            if only_on and only_on != today and not everything:
                continue  # a "today only" item of another day
            sold_out = ("sold_out_on" in r.keys() and r["sold_out_on"] == today)
            tracked_out = bool(r["track_stock"]) and stock.get(r["id"], 0) <= 0
            item = {"id": r["id"], "name": r["name"], "name_te": r["name_te"] or "", "price_paise": r["price_paise"],
                    "unit": r["unit"], "today_only": bool(only_on) and only_on == today,
                    "available": not sold_out and not tracked_out, "rate_bp": r["rate_bp"],
                    "price_includes_tax": bool(r["price_includes_tax"]),
                    "item_no": r["item_no"] if "item_no" in r.keys() else None,
                    "menu_group": (r["menu_group"] if "menu_group" in r.keys() else "") or "",
                    "food_type": (r["food_type"] if "food_type" in r.keys() else "") or ""}
            if everything:
                item["today_only_flag"] = bool(only_on)
                item["sold_out"] = sold_out
                item["has_photo"] = r["id"] in photos
                item["sold_today"] = sold.get(r["id"], 0)
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
        # Owner 2026-11-19 (bulk upload): rows pasted from Excel / Sheets / CSV are read as a table first.
        from app.services import pos_menu_table

        items = pos_menu_table.parse(text, default_unit) or pos_menu_voice.parse_menu(text, default_unit)
        for item in items:
            key = pos_menu_voice.normalize(item["name"])
            item["exists"] = key in existing
            item["old_price_paise"] = existing.get(key)
        return {"items": items, "gst": business["registration_type"] != "unregistered"}

    def parse_menu_photo(self, business_id: str, user: str, images: List[Any], image_service: Any) -> Dict[str, Any]:
        """Menu photo(s) -> a PREVIEW (nothing saved): every item with the price printed on the photo, marked when it
        already exists (old price shown) or when the photo had no clear price (the owner types it)."""
        from app.services import pos_menu_photo

        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "products")
            business = self.store._business_row(conn, business_id)
            existing = {pos_menu_voice.normalize(r["name"]): r["price_paise"] for r in conn.execute(
                "SELECT name, price_paise FROM pos_products WHERE business_id = ? AND active = 1", (business_id,))}
        default_unit = "plate" if business["template"] in ("restaurant", "bakery") else "pcs"
        out = pos_menu_photo.read_menu(image_service, images, default_unit)
        for item in out["items"]:
            key = pos_menu_voice.normalize(item["name"])
            item["exists"] = key in existing
            item["old_price_paise"] = existing.get(key)
        return {"items": out["items"], "read": out["read"], "gst": business["registration_type"] != "unregistered"}

    def import_menu(self, business_id: str, user: str, items: List[Dict[str, Any]], rate_bp: int = 0) -> Dict[str, Any]:
        if not items or len(items) > 200:
            raise PosError(400, "items", "Add 1-200 items.")
        created = updated = 0
        today = self._today()
        from app.services.pos_menu_sort import printed_number

        for raw in items:
            name = _clean(raw.get("name"), 80)
            if not name:
                continue
            # "117) Fish Biryani" (read from a photo) -> name "Fish Biryani", item number 117 (owner 2026-11-18).
            name, printed = printed_number(name)
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
            group = _clean(raw.get("menu_group"), 40)
            food = str(raw.get("food_type") or "")
            with self.store._tx() as conn:
                conn.execute("UPDATE pos_products SET only_on = ?, sold_out_on = NULL WHERE id = ? AND business_id = ?",
                             (today if raw.get("today_only") else None, product_id, business_id))
                if group:
                    conn.execute("UPDATE pos_products SET menu_group = ? WHERE id = ?", (group, product_id))
                if food in ("veg", "nonveg", "egg"):
                    conn.execute("UPDATE pos_products SET food_type = ? WHERE id = ?", (food, product_id))
                if printed and not conn.execute("SELECT 1 FROM pos_products WHERE business_id = ? AND item_no = ?"
                                                " AND id != ?", (business_id, printed, product_id)).fetchone():
                    conn.execute("UPDATE pos_products SET item_no = ? WHERE id = ?", (printed, product_id))
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
            name = self.store._business_row(conn, business_id)["name"]
            tables = [{"id": t["id"], "name": t["name"], "area": t["area"], "code": f"{QR_PREFIX}{business_id}:{t['id']}"}
                      for t in conn.execute("SELECT id, name, area FROM pos_tables WHERE business_id = ? AND active = 1"
                                            " ORDER BY area, name", (business_id,))]
        return {"shop": f"{QR_PREFIX}{business_id}", "name": name, "tables": tables}

    _GENERIC = {"the", "and", "shop", "store", "stores", "hotel", "restaurant", "mess", "centre", "center", "mart", "tiffins"}

    @staticmethod
    def _words(text: str) -> set:
        return {w for w in re.findall(r"[\w]+", str(text or "").lower(), flags=re.UNICODE) if len(w) >= 3}

    def find_shops(self, text: str, limit: int = 2) -> List[Dict[str, Any]]:
        """Shops on ASKODOX whose own NAME the person said (data match, no categories): open, with a menu.
        A multi-word name needs at least two of its words in the message (one generic word like 'shop' never counts)."""
        from app.services.name_sound import same, sound, sounds

        said = sounds(text)  # any script: "మురళి మనోహర్" sounds like "Murali Manohar"
        if not said:
            return []
        generic = {sound(g) for g in self._GENERIC}
        found: List[Dict[str, Any]] = []
        with self.store._connect() as conn:
            for r in conn.execute("SELECT id, name, status FROM pos_businesses"):
                if ((r["status"] if "status" in r.keys() else "open") or "open") != "open":
                    continue
                words = list(dict.fromkeys(sounds(r["name"])))
                matched = [w for w in words if any(same(w, x) for x in said)]
                real = [w for w in matched if w not in generic]
                hit = len(matched)
                if not real or hit < min(2, len(words)):
                    continue
                items = conn.execute("SELECT COUNT(*) AS n FROM pos_products WHERE business_id = ? AND active = 1",
                                     (r["id"],)).fetchone()["n"]
                if items:
                    found.append({"id": r["id"], "name": r["name"], "code": f"{QR_PREFIX}{r['id']}", "score": hit})
        found.sort(key=lambda x: -x["score"])
        return found[:limit]

    def search_shops(self, text: str, limit: int = 8) -> List[Dict[str, Any]]:
        """Shops with a menu whose NAME contains what the person typed (any part, any case). For the "find a shop" box
        next to the QR scanner: a customer cannot type a long order code."""
        q = re.sub(r"\s+", " ", str(text or "")).strip().lower()
        if len(q) < 2:
            return []
        found: List[Dict[str, Any]] = []
        with self.store._connect() as conn:
            rows = conn.execute("SELECT id, name, address, status FROM pos_businesses WHERE lower(name) LIKE ? LIMIT 60",
                                (f"%{q}%",)).fetchall()
            if not rows:  # typed in Telugu / Hindi / ... or spelled differently: compare how the words sound
                from app.services.name_sound import same, sounds

                typed = sounds(q)
                if typed:
                    rows = [r for r in conn.execute("SELECT id, name, address, status FROM pos_businesses")
                            if all(any(same(n, t) or same(t, n) or n.startswith(t) for n in sounds(r["name"])) for t in typed)][:60]
            for r in rows:
                status = ((r["status"] if "status" in r.keys() else "open") or "open")
                if status == "closed":
                    continue
                items = conn.execute("SELECT COUNT(*) AS n FROM pos_products WHERE business_id = ? AND active = 1",
                                     (r["id"],)).fetchone()["n"]
                if items:
                    found.append({"id": r["id"], "name": r["name"], "address": r["address"], "open": status == "open",
                                  "code": f"{QR_PREFIX}{r['id']}", "items": items})
        found.sort(key=lambda s: (not s["open"], not s["name"].lower().startswith(q), s["name"].lower()))
        return found[:limit]

    def shop_pins(self, ids: List[str]) -> Dict[str, tuple]:
        """Map pins the owners set in their shop profile (shop_follows.shop_profiles: lat / lng). {} when none."""
        if not ids:
            return {}
        pins: Dict[str, tuple] = {}
        try:
            with self.store._connect() as conn:
                marks = ",".join("?" for _ in ids)
                for r in conn.execute(f"SELECT business_id, data FROM shop_profiles WHERE business_id IN ({marks})", ids):
                    try:
                        data = json.loads(r["data"] or "{}")
                        lat, lng = float(data.get("lat")), float(data.get("lng"))
                    except (TypeError, ValueError):
                        continue
                    if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat, lng) != (0.0, 0.0):
                        pins[r["business_id"]] = (lat, lng)
        except sqlite3.OperationalError:
            return {}
        return pins

    # Owner 2026-11-19: questions about a named ASKODOX shop are answered from the shop's OWN data (its profile +
    # menu), never guessed. Words that ask about a shop (en / te / hi / typed Telugu).
    _ASKS = {
        "hours": ("timing", "timings", "time", "open", "close", "hours", "టైమింగ్", "సమయం", "తెరిచి", "తెరుస్తారు",
                  "समय", "kab", "eppudu", "ఎప్పుడు", "తెరుస్త", "మూస"),
        "address": ("address", "where", "location", "అడ్రస్", "ఎక్కడ", "చిరునామా", "पता", "kahan", "ekkada", "landmark"),
        "delivery": ("delivery", "deliver", "home delivery", "డెలివరీ", "ఇంటికి", "डिलीवरी", "parcel", "పార్సెల్"),
        "offers": ("offer", "offers", "discount", "ఆఫర్", "డిస్కౌంట్", "छूट"),
        "contact": ("phone", "number", "contact", "whatsapp", "నంబర్", "ఫోన్", "నెంబర్", "नंबर"),
        "price": ("price", "cost", "rate", "how much", "ధర", "ఎంత", "రేటు", "कीमत", "kitna", "entha"),
    }

    def shop_answer(self, business_id: str, text: str, te: bool) -> str:
        """A short answer about the shop from its own profile / menu for what the person asked, or '' when the words
        ask nothing about the shop (or the shop never filled that detail -- then it says so, never invents)."""
        words = " " + str(text or "").lower() + " "
        asked = [k for k, cues in self._ASKS.items() if any(c in words for c in cues)]
        if not asked:
            return ""
        profile: Dict[str, Any] = {}
        name = ""
        try:
            with self.store._connect() as conn:
                b = conn.execute("SELECT name, address FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
                name = b["name"] if b else ""
                if b and b["address"]:
                    profile["address"] = b["address"]
                try:
                    row = conn.execute("SELECT data FROM shop_profiles WHERE business_id = ?", (business_id,)).fetchone()
                    if row:
                        profile.update({k: v for k, v in json.loads(row["data"] or "{}").items() if str(v or "").strip()})
                except sqlite3.OperationalError:
                    pass
                menu = self._menu(conn, business_id) if "price" in asked else []
        except Exception:
            return ""
        lines: List[str] = []
        missing = "{} ఈ వివరం ఇంకా ASKODOX లో పెట్టలేదు." if te else "{} has not added this detail on ASKODOX yet."
        for k in asked:
            if k == "hours":
                v = profile.get("hours")
                lines.append((f"⏰ టైమింగ్స్: {v}" if te else f"⏰ Hours: {v}") if v else missing.format(name))
            elif k == "address":
                v = ", ".join(x for x in (profile.get("address"), profile.get("landmark")) if x)
                lines.append((f"📍 అడ్రస్: {v}" if te else f"📍 Address: {v}") if v else missing.format(name))
            elif k == "delivery":
                v = profile.get("delivery")
                lines.append((f"🛵 డెలివరీ: {v}" if te else f"🛵 Delivery: {v}") if v else missing.format(name))
            elif k == "offers":
                v = profile.get("offers")
                lines.append((f"🏷 ఆఫర్లు: {v}" if te else f"🏷 Offers: {v}") if v else
                             (f"{name} లో ఇప్పుడు ఆఫర్లు లేవు." if te else f"{name} has no offers listed now."))
            elif k == "contact":
                v = profile.get("whatsapp")
                lines.append((f"📞 WhatsApp: {v}" if te else f"📞 WhatsApp: {v}") if v else missing.format(name))
            elif k == "price":
                said = self._words(text) - self._GENERIC
                hits = [m for m in menu if m["available"] and said & (self._words(m["name"]) | self._words(m.get("name_te") or ""))]
                for m in hits[:4]:
                    p = int(m["price_paise"])
                    lines.append(f"• {m['name']}: ₹{p // 100}" if p % 100 == 0 else f"• {m['name']}: ₹{p / 100:.2f}")
        return "\n".join(dict.fromkeys(lines))

    @staticmethod
    def _km(a: tuple, b: tuple) -> float:
        import math

        la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
        h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
        return 6371.0 * 2 * math.asin(min(1.0, math.sqrt(h)))

    def nearest_first(self, shops: List[Dict[str, Any]], near: Optional[tuple]) -> List[Dict[str, Any]]:
        """Owner 2026-11-19: the nearest ASKODOX shops first. Shops with a map pin are ordered by distance (and carry
        ``distance_km``); shops without a pin keep their order after them. No location -> unchanged."""
        if not near or not shops:
            return shops
        pins = self.shop_pins([s["id"] for s in shops])
        pinned = []
        for s in shops:
            if s["id"] in pins:
                s["distance_km"] = round(self._km(near, pins[s["id"]]), 1)
                pinned.append(s)
        pinned.sort(key=lambda s: s["distance_km"])
        return pinned + [s for s in shops if s["id"] not in pins]

    def shopping(self, text: str, limit: int = 12, near: Optional[tuple] = None) -> List[Dict[str, Any]]:
        """ASKODOX Shopping (owner 2026-11-18): ONLY businesses on ASKODOX -- shops whose NAME matches, then shops whose
        MENU has it (with those items + prices). Nothing typed = the open shops with a menu (newest first). Data match only.
        With [near] (the person's place) the nearest pinned shops come first (owner 2026-11-19)."""
        return self.nearest_first(self._shopping(text, limit if not near else max(limit, 40)), near)[:limit]

    def _shopping(self, text: str, limit: int = 12) -> List[Dict[str, Any]]:
        q = re.sub(r"\s+", " ", str(text or "")).strip()
        if len(q) < 2:
            out: List[Dict[str, Any]] = []
            with self.store._connect() as conn:
                for r in conn.execute("SELECT id, name, address, status FROM pos_businesses ORDER BY created_at DESC LIMIT 200"):
                    status = ((r["status"] if "status" in r.keys() else "open") or "open")
                    if status != "open":
                        continue
                    n = conn.execute("SELECT COUNT(*) AS n FROM pos_products WHERE business_id = ? AND active = 1",
                                     (r["id"],)).fetchone()["n"]
                    if n:
                        out.append({"id": r["id"], "name": r["name"], "address": r["address"], "open": True,
                                    "code": f"{QR_PREFIX}{r['id']}", "items": [], "item_count": n, "why": "shop"})
                    if len(out) >= limit:
                        break
            return out
        seen: Dict[str, Dict[str, Any]] = {}
        for s in self.search_shops(q, limit):
            seen[s["id"]] = {"id": s["id"], "name": s["name"], "address": s.get("address") or "", "open": s["open"],
                             "code": s["code"], "items": [], "item_count": s.get("items"), "why": "name"}
        for s in self.find_items(q, limit):
            row = seen.setdefault(s["id"], {"id": s["id"], "name": s["name"], "address": "", "open": True,
                                            "code": s["code"], "items": [], "item_count": None, "why": "menu"})
            row["items"] = s["items"]
        return list(seen.values())[:limit]

    def chat_card(self, business_id: str, user: str, text: str = "", te: bool = True, limit: int = 8) -> Dict[str, Any]:
        """The shop's menu as a card INSIDE the chat (owner 2026-11-16): the items to tap, the ways to get it, the
        person's last order ("again"), and -- when their own words already name items ("2 biryani 1 tea") or ask for
        the usual -- that order PREPARED for one confirm tap. Nothing is placed here."""
        data = self.resolve(f"{QR_PREFIX}{business_id}", user)
        menu = data["menu"]
        prepared: List[Dict[str, Any]] = []
        if text and data["open"]:
            heard = pos_menu_voice.assist(text, menu, te=te, cart=[], last_items=data["last_items"])
            prepared = [{"product_id": a["product_id"], "qty": a.get("qty", 1)} for a in heard.get("add") or []]
        wanted = {p["product_id"] for p in prepared}
        # Owner 2026-11-19: asked for "biryani" -> the card shows the biryani items, not the whole menu (one link opens
        # the rest). Matched on the item's own words; a match on most of the menu (e.g. the shop's name) is no focus.
        said = set(re.findall(r"[^\W\d_]{3,}", (text or "").lower()))
        focus = [m["id"] for m in menu
                 if m["id"] in wanted or said & set(re.findall(r"[^\W\d_]{3,}", f"{m['name']} {m.get('name_te') or ''}".lower()))]
        if len(focus) * 10 > len(menu) * 6 and not wanted:
            focus = []
        limit = max(limit, min(len(focus), 12))
        ordered = sorted(menu, key=lambda m: (m["id"] not in wanted, m["id"] not in focus, not m["available"], m.get("item_no") or 0))
        return {"business_id": business_id, "name": data["business"]["name"], "code": f"{QR_PREFIX}{business_id}",
                "open": data["open"], "message": data["message"], "modes": data["modes"],
                "items": [{"id": m["id"], "name": m["name"], "name_te": m["name_te"], "price_paise": m["price_paise"],
                           "available": m["available"], "item_no": m.get("item_no"), "menu_group": m.get("menu_group", ""),
                           "food_type": m.get("food_type", ""), "rating": m.get("rating")} for m in ordered[:limit]],
                "rating": data["business"].get("rating"), "welcome": data.get("welcome"),
                "more": max(0, len(menu) - limit), "last_items": data["last_items"], "prepared": prepared,
                "focus": focus[:12]}

    def find_items(self, text: str, limit: int = 3) -> List[Dict[str, Any]]:
        """Shops on ASKODOX (open) whose MENU has what the person asked for -- matched on the item's own words
        ("biryani" finds "Chicken Dum Biryani"), never on a category list. Only items on sale today. Each shop carries
        its matching items with the menu prices; best match first (owner 2026-11-16: our shops are shown first)."""
        said = self._words(text) - self._GENERIC
        if not said:
            return []
        found: List[Dict[str, Any]] = []
        with self.store._connect() as conn:
            for b in conn.execute("SELECT id, name, status FROM pos_businesses"):
                if ((b["status"] if "status" in b.keys() else "open") or "open") != "open":
                    continue
                hits = []
                for item in self._menu(conn, b["id"]):
                    if not item["available"]:
                        continue
                    score = len((self._words(item["name"]) | self._words(item.get("name_te") or "")) & said)
                    if score:
                        hits.append((score, item))
                if not hits:
                    continue
                hits.sort(key=lambda h: (-h[0], h[1]["price_paise"]))
                found.append({"id": b["id"], "name": b["name"], "code": f"{QR_PREFIX}{b['id']}",
                              "score": sum(h[0] for h in hits[:3]),
                              "items": [{"name": h[1]["name"], "price_paise": h[1]["price_paise"], "unit": h[1]["unit"]}
                                        for h in hits[:3]]})
        found.sort(key=lambda x: -x["score"])
        return found[:limit]

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
            ratings = self.ratings
            items_rated = ratings.item_ratings(conn, row["id"])
            for m in menu:
                if m["id"] in items_rated:
                    m["rating"] = items_rated[m["id"]]
            shop_rating = ratings.summary(conn, row["id"])
            welcome = ratings.welcome(conn, row["id"], user)
        modes = (["dine_in"] if table else []) + ["takeaway", "delivery"]
        return {"business": {"id": row["id"], "name": row["name"], "address": row["address"], "phone": row["phone"],
                             "status": status, "gst": row["registration_type"] != "unregistered", "rating": shop_rating},
                "welcome": welcome,
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
            reserved_note = ""
            if kind == "dine_in" and not table_id and payload.get("reservation_id") and not staff_made:
                # Owner 2026-11-19: a person who reserved a table may order the food BEFORE arriving -- the table comes
                # from their own reservation and the order says when they will come.
                try:
                    res = conn.execute("SELECT table_id, at_utc FROM pos_table_reservations WHERE id = ? AND business_id = ?"
                                       " AND customer_user = ? AND status = 'booked'",
                                       (str(payload["reservation_id"]), business_id, user)).fetchone()
                except sqlite3.OperationalError:
                    res = None
                if res is None:
                    raise PosError(409, "reservation", "That table reservation is not active any more.")
                table_id = res["table_id"]
                when = datetime.fromisoformat(res["at_utc"]).astimezone(timezone(timedelta(hours=5, minutes=30))).strftime("%I:%M %p")
                reserved_note = f"రిజర్వ్ · వచ్చే సమయం {when} (Reserved, arriving {when}). "
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
                 json.dumps(items), _clean(reserved_note + str(payload.get("notes") or ""), 160), txn, now, now))
            self._event(conn, order_id, business_id, "placed", user)
            row = dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone())
            targets = self._targets(conn, business_id, "new")
            view = self._view(conn, row, user)
        total = sum(i["price_paise"] * i["qty_milli"] // 1000 for i in items)
        self._push([u for u in targets if u != user], "కొత్త ఆర్డర్ · New order",
                   f"{len(items)} ఐటమ్స్ · ₹{total // 100} · {kind}", f"/desk/{business_id}", f"desk:{order_id}:new",
                   speak=True)
        # never accepted here: the order waits for the owner / a person the owner allowed (owner 2026-11-17)
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
        """Every event; the FIRST event of a stage is that step ("step"), later ones on the same stage (billed,
        assigned, owner alerted) are notes ("note") -- an app must never show a step twice."""
        out: List[Dict[str, Any]] = []
        seen: set = set()
        for e in conn.execute("SELECT stage, at, note FROM pos_desk_events WHERE order_id = ? ORDER BY id", (order_id,)):
            kind = "note" if e["stage"] in seen else "step"
            seen.add(e["stage"])
            out.append({"stage": e["stage"], "at": e["at"], "note": e["note"], "kind": kind})
        return out

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
            "next_stage": nxt, "flow": list(flow), "reason": row["reason"], "items": [
                {"product_id": i["product_id"], "name": i["name"], "qty": round(i["qty_milli"] / 1000, 3),
                 "price_paise": i["price_paise"], "note": i.get("note", ""), "status": i.get("status", "ok")} for i in items],
            "estimate_paise": estimate, "customer_name": row["customer_name"], "notes": row["notes"],
            "address": row["address"], "landmark": row["landmark"], "lat": row["lat"], "lng": row["lng"],
            "maps_url": _maps_url(row["lat"], row["lng"], row["address"]) if row["kind"] == "delivery" else "",
            "assignee": row["assignee"], "assignee_user": row.get("assignee_user") or "", "placed_at": row["placed_at"], "updated_at": row["updated_at"],
            "can_cancel": row["stage"] == "placed", "timeline": self._timeline(conn, row["id"]),
            "gst": bool(business and business["registration_type"] != "unregistered"),
            "business_phone": business["phone"] if business else "", "invoice": None, "pay": [],
            "pay_choice": row.get("pay_choice") or "",
        }
        if row["invoice_id"]:
            inv = conn.execute("SELECT number, totals, paid_paise, balance_paise FROM pos_invoices WHERE id = ?",
                               (row["invoice_id"],)).fetchone()
            if inv:
                totals = json.loads(inv["totals"])
                total = int(totals.get("grand_total_paise") or totals.get("total_paise") or 0)
                # money the shop marked as received later (bill_settle) is off the balance
                balance = max(0, int(inv["balance_paise"] or 0) - PosBills._settled(conn, row["invoice_id"]))
                out["invoice"] = {"id": row["invoice_id"], "number": inv["number"], "total_paise": total,
                                  "paid_paise": total - balance, "balance_paise": balance}
                if balance > 0 and business:
                    try:
                        out["pay"] = self.pay_to(business["owner_user_id"], balance, f"Bill {inv['number']}", row["id"])
                    except Exception:
                        out["pay"] = []
        if not staff and row["customer_user"] == viewer and row["stage"] in ("served", "handed", "delivered", "done"):
            try:
                welcome = self.ratings.welcome(conn, row["business_id"], viewer)
                out["thanks"] = welcome["thanks"] if welcome else ""
            except Exception:
                out["thanks"] = ""
            out["can_rate"] = not conn.execute("SELECT 1 FROM pos_ratings WHERE user_id = ? AND ref = ? LIMIT 1",
                                               (viewer, row["id"])).fetchone() if self._has_ratings(conn) else True
        if row["kind"] == "dine_in":
            out["requests"] = [{"id": r["id"], "kind": r["kind"], "label": r["label"], "text": r["text"], "qty": r["qty"]}
                               for r in conn.execute("SELECT id, kind, label, text, qty FROM pos_desk_requests WHERE order_id = ?"
                                                     " AND status = 'open' ORDER BY created_at", (row["id"],))]
        if staff:
            out["customer_phone"] = row["customer_phone"]
            out["customer_user_last4"] = (row["customer_user"] or "")[-4:]
            out["pos_order_id"] = row["pos_order_id"]
            out["escalated"] = bool(row["escalated_at"])
        return out

    @staticmethod
    def _has_ratings(conn: sqlite3.Connection) -> bool:
        return conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pos_ratings'").fetchone() is not None

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
                           f"/desk/{d['business_id']}", f"desk:{d['id']}:late")
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

    def set_pay_choice(self, user: str, order_id: str, choice: str) -> Dict[str, Any]:
        """Owner 2026-11-18: the customer chooses cash or online. Cash = the shop collects it at the counter / table;
        nothing is marked paid here (the cashier still records the money). The floor staff are told once."""
        if choice not in ("cash", "online"):
            raise PosError(400, "choice", "choice must be cash or online.")
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if row["stage"] in ("rejected", "cancelled"):
                raise PosError(409, "stage", "This order is closed.")
            changed = (row["pay_choice"] if "pay_choice" in row.keys() else "") != choice
            conn.execute("UPDATE pos_desk_orders SET pay_choice = ?, updated_at = ? WHERE id = ?",
                         (choice, self._now().isoformat(), order_id))
            table = conn.execute("SELECT name FROM pos_tables WHERE id = ?", (row["table_id"],)).fetchone() \
                if row["table_id"] else None
            staff = self._staff_users(conn, row["business_id"]) if changed and choice == "cash" else []
            out = self._view(conn, dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone()), user)
        if staff:
            where = f"{table['name']} · " if table else ""
            self._push(staff, "💵 క్యాష్ కడతారు · Cash", f"{where}{row['customer_name'] or ''} {_rupees(out['estimate_paise'])}".strip(),
                       f"/desk/{row['business_id']}", f"desk:{order_id}:paycash")
        return out

    # ------------------------------------------------------------------ staff side
    def orders(self, business_id: str, user: str, lane: str = "active") -> Dict[str, Any]:
        """lane: active (everything running), new, kitchen, ready, delivery, done."""
        with self.store._tx() as conn:
            role = self._floor(conn, business_id, user, delivery_ok=True)
            self._escalate(conn, business_id)
        with self.store._connect() as conn:
            rows = [dict(r) for r in conn.execute("SELECT * FROM pos_desk_orders WHERE business_id = ? ORDER BY placed_at DESC"
                                                  " LIMIT 300", (business_id,))]
            if role == "delivery":  # a delivery person sees only the orders assigned to them
                rows = [r for r in rows if self._is_mine(r, user)]
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
            role = self._floor(conn, business_id, user, delivery_ok=True)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None or (role == "delivery" and not self._is_mine(dict(row), user)):
                raise PosError(404, "order", "Order not found.")
            return self._view(conn, dict(row), user, staff=True)

    @staticmethod
    def _is_mine(row: Dict[str, Any], user: str) -> bool:
        """A delivery person's own order: a delivery order assigned to them."""
        return row["kind"] == "delivery" and (row.get("assignee_user") or "") == user

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
        self._push([row["customer_user"]], title[:70], (extra or en)[:160], f"/order-desk/track/{row['id']}", f"desk:{row['id']}:{stage}")

    def confirm(self, business_id: str, user: str, order_id: str, decisions: Optional[Dict[str, bool]] = None,
                note: str = "") -> Dict[str, Any]:
        """The kitchen's yes/no per item. Yes for all (or some) -> the order is accepted and a real KOT is cut; an item
        the kitchen cannot make is sold out for today and the customer is told which. Nothing left -> rejected."""
        decisions = decisions or {}
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            self._may_accept(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            if row["stage"] != "placed":
                raise PosError(409, "stage", "This order was already answered.")
            # claim it in this transaction: two people tapping Accept together make ONE acceptance (one event, one KOT)
            claimed = conn.execute("UPDATE pos_desk_orders SET stage = 'accepting', updated_at = ? WHERE id = ? AND stage = 'placed'",
                                   (self._now().isoformat(), order_id)).rowcount
            if not claimed:
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
        try:
            pos_order = self.restaurant.open_order(business_id, owner, {"kind": row["kind"], "table_id": row["table_id"],
                                                                        "notes": f"desk {order_id}"})
            self.restaurant.add_items(business_id, owner, pos_order["id"], [
                {"product_id": i["product_id"], "qty_milli": i["qty_milli"], "note": i.get("note", ""),
                 "client_txn_id": f"{order_id}:{i['product_id']}"} for i in kept])
            self.restaurant.send_kot(business_id, owner, pos_order["id"])
        except Exception:
            with self.store._tx() as conn:  # nothing was accepted: back to waiting
                conn.execute("UPDATE pos_desk_orders SET stage = 'placed' WHERE id = ? AND stage = 'accepting'", (order_id,))
            raise
        with self.store._tx() as conn:
            row = dict(conn.execute("SELECT * FROM pos_desk_orders WHERE id = ?", (order_id,)).fetchone())
            self._set_stage(conn, row, "accepted", user, note, pos_order_id=pos_order["id"])
        names = ", ".join(i["name"] for i in dropped)
        self._tell_customer(row, "accepted", (f"లేనివి: {names}. " if names else "") + STAGE_TEXT["accepted"][1])
        self._bill_on_accept(business_id, owner, row)
        with self.store._connect() as conn:  # the kitchen people the owner chose (or the kitchen role) hear it now
            kitchen = self._targets(conn, business_id, "kitchen")
        self._push([u for u in kitchen if u != user], "వంటగదికి ఆర్డర్ · Kitchen order",
                   ", ".join(f"{i['name']} ×{i['qty_milli'] // 1000}" for i in kept)[:140], f"/desk/{business_id}", f"desk:{order_id}:kitchen")
        return self.order(business_id, user, order_id)

    def _bill_on_accept(self, business_id: str, owner: str, row: Dict[str, Any]) -> None:
        """Owner 2026-11-16: a parcel / delivery order placed from the customer's app is BILLED the moment the shop accepts
        it -- unpaid, on that customer -- so the bill with its Pay button reaches their app at once. Dine-in is billed at
        the end (more may be ordered at the table). A problem here never undoes the acceptance; the cashier can still
        bill by hand."""
        if row["kind"] == "dine_in" or not row["customer_user"] or row.get("invoice_id"):
            return
        try:
            from app.services.pos_quick_bill import PosQuickBill

            phone = row["customer_phone"] or phone_key(row["customer_user"])
            customer_id = PosQuickBill(self.store)._customer(business_id, owner, {"name": row["customer_name"], "phone": phone})
            self.bill(business_id, owner, row["id"], payments=[], customer_id=customer_id)
        except Exception:
            import logging

            logging.getLogger(__name__).exception("desk: bill on accept failed for %s", row["id"])

    def reject(self, business_id: str, user: str, order_id: str, reason: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            if row["stage"] in ("placed", "accepting"):  # turning a NEW order down = answering it
                self._may_accept(conn, business_id, user)
            if row["stage"] in CLOSED:
                raise PosError(409, "stage", "This order is already closed.")
            self._set_stage(conn, row, "rejected", user, reason, reason=_clean(reason, 160))
        self._tell_customer(row, "rejected", _clean(reason, 120))
        return self.order(business_id, user, order_id)

    def advance(self, business_id: str, user: str, order_id: str, stage: str, assignee: str = "",
                assignee_user: str = "") -> Dict[str, Any]:
        """Forward only along this order's own lane; 'preparing' may be skipped."""
        with self.store._tx() as conn:
            role = self._floor(conn, business_id, user, delivery_ok=True)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None or (role == "delivery" and not self._is_mine(dict(row), user)):
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            if role == "delivery" and stage not in ("out_for_delivery", "delivered"):
                raise PosError(403, "permission", "A delivery person can only mark an order out for delivery or delivered.")
            if _clean(assignee_user, 60) and role != "delivery":
                self._assign_user(conn, row, _clean(assignee_user, 60))
                row["assignee_user"] = _clean(assignee_user, 60)
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
        self._tell_staff_step(row, stage, user)
        return self.order(business_id, user, order_id)

    def _tell_staff_step(self, row: Dict[str, Any], stage: str, actor: str) -> None:
        """The next person hears it: the one the order is assigned to; otherwise ready -> waiter (dine-in) / cashier
        (takeaway), packed delivery -> the delivery people. Never the whole team."""
        biz, kind = row["business_id"], row["kind"]
        with self.store._connect() as conn:
            fresh = conn.execute("SELECT assignee_user FROM pos_desk_orders WHERE id = ?", (row["id"],)).fetchone()
            assigned = (fresh["assignee_user"] if fresh else "") or ""
            if stage == "ready" and kind in ("dine_in", "takeaway"):
                who, title = self._targets(conn, biz, "ready"), ("వడ్డించండి · Ready to serve" if kind == "dine_in" else "సిద్ధం — ఇవ్వండి · Ready for pickup")
            elif stage == "packed" and kind == "delivery":
                who, title = self._targets(conn, biz, "delivery"), "డెలివరీకి సిద్ధం · Ready for delivery"
            else:
                return
        if assigned:
            who = [assigned]
        self._push([u for u in who if u != actor], title, f"#{row['id'][-5:]}", f"/desk/{biz}", f"desk:{row['id']}:{stage}:step")

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
        if row["invoice_id"]:
            # Already billed (on accept, unpaid): what the cashier now took is money received for THAT bill.
            for index, p in enumerate(payments or []):
                left = self.bills.due_of(row["invoice_id"])
                if left <= 0:
                    break
                self.bills.settle(business_id, user, row["invoice_id"], str(p.get("app") or p.get("method") or "cash"),
                                  min(int(p.get("amount_paise") or 0) or left, left), f"{txn}:s{index}"[:64])
            return self.order(business_id, user, order_id)
        result = self.restaurant.bill(business_id, user, row["pos_order_id"],
                                      {"client_txn_id": txn, "payments": payments or [], "include_unsent": True,
                                       "customer_id": customer_id})
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_desk_orders SET invoice_id = ?, updated_at = ? WHERE id = ?",
                         (result["id"], self._now().isoformat(), order_id))
            self._event(conn, order_id, business_id, row["stage"], user, f"billed {result.get('number', '')}")
        try:  # the customer who ordered in the app sees this bill in "My bills", with Pay
            self.bills.share_to_user(business_id, result["id"], row["customer_user"], user)
        except Exception:
            pass
        out = self.order(business_id, user, order_id)
        out["invoice_number"] = result.get("number")
        return out

    def _assign_user(self, conn: sqlite3.Connection, row: Dict[str, Any], person_id: str) -> Dict[str, Any]:
        people = {p["id"]: p for p in self._people(conn, row["business_id"])}
        person = people.get(person_id)
        if person is None:
            raise PosError(400, "assignee", "Choose a person who is on this shop's staff.")
        label = _clean(person["label"], 40) or person["role"]
        conn.execute("UPDATE pos_desk_orders SET assignee = ?, assignee_user = ?, updated_at = ? WHERE id = ?",
                     (label, person_id, self._now().isoformat(), row["id"]))
        self._event(conn, row["id"], row["business_id"], row["stage"], "assign", f"assigned to {label}")
        return person

    def assign(self, business_id: str, user: str, order_id: str, assignee: str, assignee_user: str = "") -> Dict[str, Any]:
        """Assign an order to a staff PERSON (they get the alert on their own phone) or, for old callers, a typed name."""
        person_id = ""
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if _clean(assignee_user, 60):
                person_id = _clean(assignee_user, 60)
                self._assign_user(conn, dict(row), person_id)
            else:
                conn.execute("UPDATE pos_desk_orders SET assignee = ?, assignee_user = '', updated_at = ? WHERE id = ? AND business_id = ?",
                             (_clean(assignee, 40), self._now().isoformat(), order_id, business_id))
        if person_id and person_id != user:
            self._push([person_id], "మీకు ఆర్డర్ అసైన్ అయింది · Order for you", f"#{order_id[-5:]}", f"/desk/{business_id}", f"desk:{order_id}:assign")
        return self.order(business_id, user, order_id)
