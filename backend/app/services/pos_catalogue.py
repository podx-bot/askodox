"""ASKODOX POS -- the ready-made catalogue for a shop, on the ONE catalogue engine
(``catalogue_templates.py``, the same templates "list my products" uses).

* Each shop has a catalogue template (default from its POS business type; the
  owner can change it). The template brings the category's DETAILS
  (attributes: size, colour, brand, warranty ...) with their groups, choices
  and required flags, and a starting list of GENERIC items (no brands, no
  prices).
* "Add from the ready list": the owner ticks items, picks a size and types
  THEIR price (and, for a GST-registered shop, THEIR GST rate) -- nothing is
  added with an invented price or rate. Items already in the shop (same name)
  are skipped, so a repeat is harmless.
* An item's details are cleaned by the template (options only from the list,
  numbers in range, no contact details) and the REQUIRED ones still missing are
  reported so the app can point at them with a guide.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from app.services import catalogue_templates, pos_tax
from app.services.pos_store import PosError, PosStore, _clean

# POS business type -> catalogue template (the owner can choose another one).
DEFAULT_TEMPLATE = {
    "kirana": "grocery", "supermarket": "grocery", "bakery": "grocery", "vegetables": "fruits_vegetables",
    "meat_fish": "meat_poultry", "clothing": "fashion", "electronics": "electronics", "jewellery": "jewellery_beauty",
    "pharmacy": "health_wellness", "salon": "services", "repair": "services", "wholesale": "b2b_industrial",
    "hardware": "b2b_industrial",
}

# Catalogue units -> POS units. Area / bulk units (sq ft, quintal) have no POS unit: those items are not offered.
UNIT_MAP = {
    "kg": "kg", "g": "g", "L": "l", "ml": "ml", "dozen": "dozen", "pack": "pack", "piece": "pcs", "pair": "pcs",
    "set": "pcs", "bunch": "pcs", "hour": "hour", "visit": "service", "course": "service", "project": "service",
    "day": "service", "night": "service", "month": "service", "person": "service", "video": "service",
}


class PosCatalogue:
    def __init__(self, store: PosStore) -> None:
        self.store = store

    def _template_key(self, business) -> Optional[str]:
        chosen = business["catalogue_template"] if "catalogue_template" in business.keys() else None
        key = chosen or DEFAULT_TEMPLATE.get(business["template"])
        return key if key and catalogue_templates.template(key) else None

    def catalogue(self, business_id: str, user: str) -> Dict[str, Any]:
        """The shop's template: details to fill + ready items (each with its POS unit)."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            business = self.store._business_row(conn, business_id)
            names = {r[0].casefold() for r in conn.execute(
                "SELECT name FROM pos_products WHERE business_id = ? AND active = 1", (business_id,))}
        key = self._template_key(business)
        out: Dict[str, Any] = {"template_key": key, "registration_type": business["registration_type"],
                               "choices": catalogue_templates.summaries(), "attributes": [], "categories": []}
        found = catalogue_templates.template(key) if key else None
        if not found:
            return out
        out["name"] = found["name"]
        out["attributes"] = found["attributes"]
        for cat in found["categories"]:
            items = []
            for item in cat.get("items") or []:
                unit = UNIT_MAP.get(item.get("unit"))
                if not unit:
                    continue
                items.append({**item, "pos_unit": unit,
                              "in_shop": any(n.startswith(item["name"]["en"].casefold()) for n in names)})
            if items:
                out["categories"].append({"key": cat["key"], "name": cat["name"], "items": items})
        return out

    def set_template(self, business_id: str, user: str, key: Optional[str]) -> Dict[str, Any]:
        if key and not catalogue_templates.template(key):
            raise PosError(400, "template", "Unknown catalogue.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_businesses SET catalogue_template = ?, updated_at = ? WHERE id = ?",
                         (key or None, now, business_id))
            self.store._audit(conn, business_id, user, "catalogue.template", business_id, {"template": key}, now)
        return self.catalogue(business_id, user)

    def set_attributes(self, business_id: str, user: str, product_id: str, values: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "products")
            business = self.store._business_row(conn, business_id)
            row = conn.execute("SELECT id FROM pos_products WHERE id = ? AND business_id = ?",
                               (product_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "product", "Item not found.")
            key = self._template_key(business)
            kept, missing = catalogue_templates.clean_attributes(key, values) if key else ({}, [])
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_products SET attributes = ?, updated_at = ? WHERE id = ?",
                         (json.dumps(kept, ensure_ascii=False), now, product_id))
            self.store._audit(conn, business_id, user, "product.attributes", product_id, kept, now)
        return {"attributes": kept, "missing": missing, "template_key": key}

    def set_online_price(self, business_id: str, user: str, product_id: str, paise: Optional[int]) -> Dict[str, Any]:
        if paise is not None and (int(paise) <= 0 or int(paise) > 10_00_00_000_00):
            raise PosError(400, "online_price", "Enter the online price, or choose the same as the shop price.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "price_override")
            if conn.execute("SELECT 1 FROM pos_products WHERE id = ? AND business_id = ?",
                            (product_id, business_id)).fetchone() is None:
                raise PosError(404, "product", "Item not found.")
            now = self.store.clock().isoformat()
            conn.execute("UPDATE pos_products SET online_price_paise = ?, updated_at = ? WHERE id = ?",
                         (None if paise is None else int(paise), now, product_id))
            self.store._audit(conn, business_id, user, "product.online_price", product_id, {"online_price_paise": paise}, now)
        return self.store.product(business_id, user, product_id)

    def import_items(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Add ticked ready items with the owner's own price (and GST rate when registered)."""
        rows = list(data.get("items") or [])
        if not rows or len(rows) > 200:
            raise PosError(400, "items", "Choose 1-200 items.")
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "products")
            business = self.store._business_row(conn, business_id)
            existing = {r[0].casefold() for r in conn.execute(
                "SELECT name FROM pos_products WHERE business_id = ? AND active = 1", (business_id,))}
        key = self._template_key(business)
        if not key:
            raise PosError(400, "template", "Choose a ready-made catalogue for this shop first.")
        registered = business["registration_type"] == "regular"
        added: List[Dict[str, Any]] = []
        skipped: List[Dict[str, Any]] = []
        for raw in rows:
            spec = catalogue_templates.item(key, str(raw.get("item_key") or ""))
            unit = UNIT_MAP.get((spec or {}).get("unit"))
            if not spec or not unit:
                skipped.append({"item_key": raw.get("item_key"), "reason": "not_in_catalogue"})
                continue
            size = _clean(raw.get("size"), 40)
            if size and size not in (spec.get("sizes") or []):
                size = ""
            name = f"{spec['name']['en']}{' ' + size if size else ''}"[:80]
            name_te = f"{spec['name'].get('te') or ''}{' ' + size if size else ''}".strip()[:80]
            price = raw.get("price_paise")
            if price is None or int(price) <= 0:
                skipped.append({"item_key": spec["key"], "name": name, "reason": "price_missing"})
                continue
            rate = int(raw.get("rate_bp")) if raw.get("rate_bp") is not None else None
            if registered and (rate is None or rate not in pos_tax.ALLOWED_RATES_BP):
                skipped.append({"item_key": spec["key"], "name": name, "reason": "gst_rate_missing"})
                continue
            if name.casefold() in existing:
                skipped.append({"item_key": spec["key"], "name": name, "reason": "already_in_shop"})
                continue
            try:
                product = self.store.add_product(business_id, user, {
                    "name": name, "name_te": name_te, "unit": unit, "price_paise": int(price),
                    "rate_bp": rate if registered else 0,
                    "price_includes_tax": True, "track_stock": bool(raw.get("track_stock")),
                    "is_service": unit in ("service", "hour"),
                })
            except PosError as error:
                skipped.append({"item_key": spec["key"], "name": name, "reason": error.code})
                continue
            existing.add(name.casefold())
            added.append({"id": product["id"], "name": product["name"]})
        return {"added": added, "skipped": skipped}
