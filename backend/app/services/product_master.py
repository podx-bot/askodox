"""ASKODOX product master (owner 2026-11-24): items come in by themselves -- never typed one by one.

ONE place that knows a packaged product (its name, brand, pack, the MRP printed on it and a pack photo), learned from
what shops already keep on ASKODOX and, by barcode, from Open Food Facts (open data, ODbL, credited on the item):

* ``lookup(barcode)``: a shop on ASKODOX that already sells that barcode (their item's name, brand, pack, MRP, pack
  photo -- NEVER their selling price), else Open Food Facts (kept here once found), else nothing.
* ``match(name)``: the best barcoded item on ASKODOX with that name (any shop), for a list / note / shelf photo.
* ``enrich(items)``: preview items get brand / pack / MRP / photo; an item without a price takes the MRP printed on the
  pack (``price_from`` "mrp") -- never a guessed price.

Only BARCODED items are shared between shops: a barcode means a factory pack, so its photo is a pack shot. A shop's own
dish / loose-item photo (no barcode) is never shown to another shop.
"""
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS product_master (barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT NOT NULL"
    " DEFAULT '', pack TEXT NOT NULL DEFAULT '', mrp_paise INTEGER, photo BLOB, photo_mime TEXT, source TEXT NOT NULL,"
    " found INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)",
)
OFF_URL = "https://world.openfoodfacts.org/api/v2/product/{code}.json?fields=product_name,brands,quantity,image_front_small_url"
OFF_CREDIT = "Open Food Facts"
MAX_PHOTO_BYTES = 300_000
_STOP = {"the", "and", "with", "pack", "of", "for", "new", "fresh", "pouch", "pkt", "packet"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def clean_barcode(value: Any) -> str:
    code = re.sub(r"\D", "", str(value or ""))
    return code if 8 <= len(code) <= 14 else ""


def _tokens(text: str) -> List[str]:
    return [t for t in re.findall(r"[a-z0-9ऀ-ॿఀ-౿]+", str(text or "").lower())
            if len(t) >= 2 and t not in _STOP]


def _attrs(raw: Any) -> Dict[str, Any]:
    try:
        value = json.loads(raw) if isinstance(raw, str) else (raw or {})
        return value if isinstance(value, dict) else {}
    except ValueError:
        return {}


def _mrp_paise(value: Any) -> Optional[int]:
    try:
        rupees = float(str(value).replace(",", "").replace("₹", "").strip())
    except (TypeError, ValueError):
        return None
    return int(round(rupees * 100)) if 0 < rupees <= 1_000_000 else None


def _default_fetch(url: str, timeout: float) -> Tuple[int, bytes, str]:
    import httpx

    response = httpx.get(url, timeout=timeout, follow_redirects=True,
                         headers={"User-Agent": "ASKODOX/1.0 (admin@askodox.com)"})
    return response.status_code, response.content, response.headers.get("content-type", "")


class ProductMaster:
    def __init__(self, db_path: str, fetch: Optional[Callable[[str, float], Tuple[int, bytes, str]]] = None) -> None:
        self.db_path = db_path
        self.fetch = fetch or _default_fetch
        with self._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    # ---- from shops on ASKODOX (barcoded items only)

    def _shop_row(self, row: sqlite3.Row) -> Dict[str, Any]:
        attrs = _attrs(row["attributes"])
        return {"name": row["name"], "name_te": row["name_te"] or "", "unit": row["unit"],
                "brand": str(attrs.get("brand") or ""), "pack": str(attrs.get("pack") or attrs.get("size") or ""),
                "mrp_paise": _mrp_paise(attrs.get("mrp")), "barcode": row["barcode"], "source": "askodox",
                "photo": f"p:{row['id']}" if row["has_photo"] else ""}

    _SHOP_SELECT = ("SELECT p.id, p.name, p.name_te, p.unit, p.barcode, p.attributes,"
                    " (SELECT 1 FROM pos_product_photos ph WHERE ph.product_id = p.id) AS has_photo FROM pos_products p")

    def lookup(self, barcode: Any, *, online: bool = True) -> Optional[Dict[str, Any]]:
        code = clean_barcode(barcode)
        if not code:
            return None
        with self._connect() as conn:
            try:
                rows = conn.execute(self._SHOP_SELECT + " WHERE p.barcode = ? AND p.active = 1 ORDER BY has_photo DESC,"
                                    " p.updated_at DESC LIMIT 5", (code,)).fetchall()
            except sqlite3.OperationalError:
                rows = []
            if rows:
                best = self._shop_row(rows[0])
                for other in rows[1:]:  # fill what the first shop left empty
                    extra = self._shop_row(other)
                    for key in ("brand", "pack", "mrp_paise", "photo", "name_te"):
                        best[key] = best[key] or extra[key]
                return best
            kept = conn.execute("SELECT * FROM product_master WHERE barcode = ?", (code,)).fetchone()
        if kept is not None:
            return self._kept(kept) if kept["found"] else None
        return self._open_food_facts(code) if online else None

    def _kept(self, row: sqlite3.Row) -> Dict[str, Any]:
        return {"name": row["name"], "name_te": "", "unit": "pcs", "brand": row["brand"], "pack": row["pack"],
                "mrp_paise": row["mrp_paise"], "barcode": row["barcode"], "source": row["source"],
                "credit": OFF_CREDIT if row["source"] == "openfoodfacts" else "",
                "photo": f"m:{row['barcode']}" if row["photo"] else ""}

    def _open_food_facts(self, code: str) -> Optional[Dict[str, Any]]:
        """Open data by barcode (no key, no cost). A miss is remembered so the same code is not asked again."""
        try:
            status, body, _ = self.fetch(OFF_URL.format(code=code), 4.0)
            data = json.loads(body.decode("utf-8")) if status == 200 else {}
        except Exception:
            return None  # network trouble: nothing is remembered, the next try asks again
        product = data.get("product") if isinstance(data, dict) and data.get("status") == 1 else None
        name = re.sub(r"\s+", " ", str((product or {}).get("product_name") or "")).strip()[:80]
        photo, mime = None, None
        if name:
            url = str(product.get("image_front_small_url") or "")
            if url.startswith("https://"):
                try:
                    p_status, p_body, p_type = self.fetch(url, 4.0)
                    if p_status == 200 and 0 < len(p_body) <= MAX_PHOTO_BYTES and p_type.startswith("image/"):
                        photo, mime = p_body, p_type.split(";")[0]
                except Exception:
                    pass
        with self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO product_master (barcode, name, brand, pack, mrp_paise, photo, photo_mime, source,"
                " found, updated_at) VALUES (?, ?, ?, ?, NULL, ?, ?, 'openfoodfacts', ?, ?)",
                (code, name or code, str((product or {}).get("brands") or "").split(",")[0].strip()[:60],
                 str((product or {}).get("quantity") or "").strip()[:30],
                 sqlite3.Binary(photo) if photo else None, mime, 1 if name else 0, _now()))
            row = conn.execute("SELECT * FROM product_master WHERE barcode = ?", (code,)).fetchone()
        return self._kept(row) if name else None

    def match(self, name: str, *, exclude_business: str = "") -> Optional[Dict[str, Any]]:
        """The barcoded item on ASKODOX whose name holds every word of [name] (or the other way round)."""
        want = set(_tokens(name))
        if not want:
            return None
        first = max(want, key=len)
        with self._connect() as conn:
            try:
                rows = conn.execute(self._SHOP_SELECT + " WHERE p.barcode != '' AND p.active = 1 AND p.business_id != ?"
                                    " AND lower(p.name) LIKE ? LIMIT 60", (exclude_business, f"%{first}%")).fetchall()
            except sqlite3.OperationalError:
                rows = []
            kept = conn.execute("SELECT * FROM product_master WHERE found = 1 AND lower(name) LIKE ? LIMIT 30",
                                (f"%{first}%",)).fetchall()
        best: Optional[Tuple[Tuple[int, int, int], Dict[str, Any]]] = None
        for entry in [self._shop_row(r) for r in rows] + [self._kept(r) for r in kept]:
            have = set(_tokens(f"{entry['brand']} {entry['name']} {entry['pack']}"))
            if not (want <= have or (have and set(_tokens(entry["name"])) <= want)):
                continue
            score = (1 if entry["photo"] else 0, 1 if entry["mrp_paise"] else 0, -abs(len(have) - len(want)))
            if best is None or score > best[0]:
                best = (score, entry)
        return best[1] if best else None

    def enrich(self, items: Iterable[Dict[str, Any]], *, business_id: str = "") -> List[Dict[str, Any]]:
        """Preview items with what ASKODOX knows of them. Fills only what is empty; a price only from a printed MRP."""
        out = []
        for item in items:
            item = dict(item)
            found = self.lookup(item.get("barcode"), online=False) if item.get("barcode") else None
            found = found or self.match(item.get("name", ""), exclude_business=business_id)
            if found:
                for key in ("brand", "pack", "barcode"):
                    item[key] = item.get(key) or found.get(key) or ""
                item["mrp_paise"] = item.get("mrp_paise") or found.get("mrp_paise")
                item["photo"] = item.get("photo") or found.get("photo") or ""
                item["known"] = found.get("source")
                if found.get("credit"):
                    item["credit"] = found["credit"]
            mrp = item.get("mrp_paise")
            if (not item.get("price_paise") or item.get("needs_price")) and mrp:
                item["price_paise"], item["needs_price"], item["price_from"] = int(mrp), False, "mrp"
            out.append(item)
        return out

    def photo(self, ref: str) -> Optional[Tuple[bytes, str]]:
        """A shared pack photo: 'p:<product id>' (a BARCODED shop item) or 'm:<barcode>' (kept from open data)."""
        kind, _, key = str(ref or "").partition(":")
        with self._connect() as conn:
            if kind == "p":
                row = conn.execute("SELECT ph.image, ph.mime FROM pos_product_photos ph JOIN pos_products p ON"
                                   " p.id = ph.product_id WHERE ph.product_id = ? AND p.barcode != ''", (key,)).fetchone()
                return (bytes(row["image"]), row["mime"]) if row else None
            if kind == "m":
                row = conn.execute("SELECT photo, photo_mime FROM product_master WHERE barcode = ? AND photo IS NOT NULL",
                                   (key,)).fetchone()
                return (bytes(row["photo"]), row["photo_mime"] or "image/jpeg") if row else None
        return None
