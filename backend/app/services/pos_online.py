"""ASKODOX POS -- where a shop's items are offered: POS only / Online / Both.

* "pos"    -- billed at the counter only (default; nothing is published).
* "online" -- shown to customers in ASKODOX search as the shop's listing, and
              hidden from the counter's item picker (the server still accepts
              it on a bill, e.g. an online order handed over at the counter).
* "both"   -- counter and ASKODOX.

The shop sets a default (``pos_businesses.online_default``); an item may
override it (``pos_products.channel``, NULL = the shop default).

Publishing reuses the ONE seller-listing store (``seller_products``) that
customer search already reads, under the shop owner's account, linked in
``pos_online_links`` (one listing per POS item -- renames never duplicate).
A new or renamed item passes the same screening as any listing
(``listing_quality.check``): block -> not published (state "blocked");
review -> saved hidden and queued for staff (state "needs_review"; only staff
can make it live). Price, unit, stock (in / out of stock) and the shop's
name / address / phone follow the POS on every sync. Turning an item to
"pos" or deactivating it hides the listing (never deletes it).
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services import listing_quality
from app.services.pos_store import PosError, PosStore

CHANNELS = ("pos", "online", "both")

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_online_links (business_id TEXT NOT NULL, product_id TEXT NOT NULL,"
    " listing_id INTEGER, state TEXT NOT NULL, reasons TEXT NOT NULL DEFAULT '[]', published_name TEXT,"
    " synced_at TEXT NOT NULL, PRIMARY KEY (business_id, product_id))",
]


def effective_channel(product: Dict[str, Any], business_default: Optional[str]) -> str:
    channel = product.get("channel") or business_default or "pos"
    return channel if channel in CHANNELS else "pos"


class PosOnline:
    def __init__(self, store: PosStore,
                 screen: Optional[Callable[[str, Dict[str, Any]], Dict[str, Any]]] = None,
                 queue_review: Optional[Callable[[int, str, str, List[str]], None]] = None) -> None:
        self.store = store
        ProductCatalogRepository(store.db_path)  # makes sure seller_products exists
        self.screen = screen or (lambda seller, fields: listing_quality.check(store.db_path, seller, fields))
        self.queue_review = queue_review or (lambda listing_id, seller, subject, reasons: None)
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------- settings
    def set_default(self, business_id: str, user: str, channel: str) -> Dict[str, Any]:
        if channel not in CHANNELS:
            raise PosError(400, "channel", "channel must be pos, online or both.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_businesses SET online_default = ?, updated_at = ? WHERE id = ?",
                         (channel, now, business_id))
            self.store._audit(conn, business_id, user, "online.default", business_id, {"channel": channel}, now)
        self.sync(business_id)
        return self.status(business_id, user)

    def set_channel(self, business_id: str, user: str, product_id: str, channel: Optional[str]) -> Dict[str, Any]:
        if channel is not None and channel not in CHANNELS:
            raise PosError(400, "channel", "channel must be pos, online, both or null (shop default).")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "products")
            row = conn.execute("SELECT id FROM pos_products WHERE id = ? AND business_id = ?",
                               (product_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "product", "Item not found.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_products SET channel = ?, updated_at = ? WHERE id = ?", (channel, now, product_id))
            self.store._audit(conn, business_id, user, "online.channel", product_id, {"channel": channel}, now)
        self.sync(business_id, [product_id])
        return self.status(business_id, user)

    def status(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            business = conn.execute("SELECT online_default FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
            links = {r["product_id"]: r for r in conn.execute(
                "SELECT * FROM pos_online_links WHERE business_id = ?", (business_id,))}
            products = conn.execute("SELECT id, name, channel, active FROM pos_products WHERE business_id = ?",
                                    (business_id,)).fetchall()
        items = []
        for p in products:
            link = links.get(p["id"])
            items.append({"product_id": p["id"], "name": p["name"], "channel": p["channel"],
                          "effective": effective_channel(dict(p), business["online_default"]),
                          "state": link["state"] if link else "not_published",
                          "reasons": json.loads(link["reasons"]) if link else []})
        return {"default": business["online_default"] or "pos", "items": items}

    # ----------------------------------------------------------------- sync
    def sync(self, business_id: str, product_ids: Optional[Iterable[str]] = None) -> Dict[str, int]:
        """Bring the listings of these items (default: all) in line with the POS. Never raises for one item."""
        counts = {"live": 0, "hidden": 0, "needs_review": 0, "blocked": 0}
        with self.store._connect() as conn:
            business = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
            if business is None:
                return counts
            if product_ids is None:
                rows = conn.execute("SELECT * FROM pos_products WHERE business_id = ?", (business_id,)).fetchall()
            else:
                ids = [str(i) for i in product_ids]
                rows = [r for i in ids for r in conn.execute(
                    "SELECT * FROM pos_products WHERE business_id = ? AND id = ?", (business_id, i))]
            stock = self.store._stock_map(conn, business_id)
            linked = {r[0] for r in conn.execute("SELECT product_id FROM pos_online_links WHERE business_id = ?",
                                                 (business_id,))}
        for product in rows:
            wanted = product["active"] and effective_channel(dict(product), business["online_default"]) != "pos"
            if not wanted and product["id"] not in linked:
                continue  # never published, still not wanted: nothing to do
            try:
                state = self._sync_one(business, product, stock.get(product["id"], 0))
                if state in ("live", "needs_review"):
                    with self.store._connect() as conn2:
                        link = conn2.execute("SELECT listing_id FROM pos_online_links WHERE business_id = ? AND"
                                             " product_id = ?", (business_id, product["id"])).fetchone()
                    self._attributes(product, link["listing_id"] if link else None)
            except Exception:  # one item's problem never stops the others
                continue
            counts[state] = counts.get(state, 0) + 1
        return counts

    def _sync_one(self, business: sqlite3.Row, product: sqlite3.Row, stock_milli: int) -> str:
        db = self.store.db_path
        owner = business["owner_user_id"]
        now = datetime.now(timezone.utc).isoformat()
        wanted = product["active"] and effective_channel(dict(product), business["online_default"]) in ("online", "both")
        with sqlite3.connect(db) as conn:
            conn.row_factory = sqlite3.Row
            link = conn.execute("SELECT * FROM pos_online_links WHERE business_id = ? AND product_id = ?",
                                (business["id"], product["id"])).fetchone()
            listing = conn.execute("SELECT id, active FROM seller_products WHERE id = ?",
                                   (link["listing_id"],)).fetchone() if link and link["listing_id"] else None

            def save(state: str, listing_id: Optional[int], reasons: List[str]) -> str:
                conn.execute("INSERT INTO pos_online_links (business_id, product_id, listing_id, state, reasons,"
                             " published_name, synced_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(business_id,"
                             " product_id) DO UPDATE SET listing_id = excluded.listing_id, state = excluded.state,"
                             " reasons = excluded.reasons, published_name = excluded.published_name,"
                             " synced_at = excluded.synced_at",
                             (business["id"], product["id"], listing_id, state, json.dumps(reasons), product["name"], now))
                return state

            if not wanted:
                if listing is not None:
                    conn.execute("UPDATE seller_products SET active = 0, updated_at = ? WHERE id = ?", (now, listing["id"]))
                if link is None:
                    return "hidden"
                return save("hidden", listing["id"] if listing else None, [])

            fields = {
                "subject": " ".join(str(product["name"]).split()),
                "unit": product["unit"],
                "price": (product["online_price_paise"] if "online_price_paise" in product.keys() and
                          product["online_price_paise"] else product["price_paise"]) / 100.0,
                "stock_status": ("IN_STOCK" if stock_milli > 0 else "OUT_OF_STOCK") if product["track_stock"] else "UNKNOWN",
                "seller_name": business["name"],
                "location_label": business["address"] or None,
                "contact_phone": business["phone"] or None,
                "gstin": business["gstin"],
            }
            renamed = link is None or listing is None or link["published_name"] != product["name"]
            if link is not None and link["state"] == "needs_review" and listing is not None and not renamed:
                # Staff decide; a listing staff made live is live, otherwise it stays hidden.
                self._update_listing(conn, listing["id"], fields, now, activate=None)
                live = bool(conn.execute("SELECT active FROM seller_products WHERE id = ?", (listing["id"],)).fetchone()[0])
                return save("live" if live else "needs_review", listing["id"], json.loads(link["reasons"]))
            if renamed:
                decision = self.screen(owner, {"subject": fields["subject"], "seller_name": fields["seller_name"],
                                               "contact_phone": fields["contact_phone"]})
                if decision.get("decision") == "block":
                    if listing is not None:
                        conn.execute("UPDATE seller_products SET active = 0, updated_at = ? WHERE id = ?",
                                     (now, listing["id"]))
                    return save("blocked", listing["id"] if listing else None, list(decision.get("reasons") or []))
                held = decision.get("decision") == "review"
                if listing is None:
                    cur = conn.execute(
                        "INSERT INTO seller_products (seller_user_id, subject, unit, price, currency, stock_status,"
                        " delivery_available, pickup_available, features_json, seller_name, location_label, contact_phone,"
                        " gstin, active, created_at, updated_at) VALUES (?, ?, ?, ?, 'INR', ?, 0, 1, '[]', ?, ?, ?, ?, ?, ?, ?)",
                        (owner, fields["subject"], fields["unit"], fields["price"], fields["stock_status"],
                         fields["seller_name"], fields["location_label"], fields["contact_phone"], fields["gstin"],
                         0 if held else 1, now, now))
                    listing_id = int(cur.lastrowid)
                else:
                    listing_id = int(listing["id"])
                    self._update_listing(conn, listing_id, fields, now, activate=not held)
                if held:
                    conn.commit()
                    try:
                        self.queue_review(listing_id, owner, fields["subject"], list(decision.get("reasons") or []))
                    except Exception:
                        pass
                    return save("needs_review", listing_id, list(decision.get("reasons") or []))
                return save("live", listing_id, [])
            self._update_listing(conn, int(listing["id"]), fields, now, activate=True)
            return save("live", int(listing["id"]), [])

    def _attributes(self, product: sqlite3.Row, listing_id: Optional[int]) -> None:
        """The item's details (size, colour, brand ...) become the listing's filterable attributes."""
        if not listing_id or "attributes" not in product.keys():
            return
        try:
            values = json.loads(product["attributes"] or "{}")
        except (TypeError, ValueError):
            values = {}
        ProductCatalogRepository(self.store.db_path).set_attributes(int(listing_id), values)

    @staticmethod
    def _update_listing(conn: sqlite3.Connection, listing_id: int, fields: Dict[str, Any], now: str,
                        activate: Optional[bool]) -> None:
        sets = ("subject = ?, unit = ?, price = ?, stock_status = ?, seller_name = ?, location_label = ?,"
                " contact_phone = ?, gstin = ?, updated_at = ?")
        values: List[Any] = [fields["subject"], fields["unit"], fields["price"], fields["stock_status"],
                             fields["seller_name"], fields["location_label"], fields["contact_phone"], fields["gstin"], now]
        if activate is not None:
            sets += ", active = ?"
            values.append(1 if activate else 0)
        conn.execute(f"UPDATE seller_products SET {sets} WHERE id = ?", (*values, listing_id))
