"""Affiliate Product Manager: staff-curated marketplace products.

Builds on #127's ``affiliate_products`` table (PartnerRevenueHub) instead of
adding another store. Staff add a product from Meesho / Amazon / Flipkart /
Wishlink / another source with its normal URL and (optionally) an affiliate
link; ASKODOX then keeps four facts apart:

* the product EXISTS (a row, not deleted),
* it is AVAILABLE (``stock_status`` IN_STOCK / OUT_OF_STOCK / UNKNOWN),
* COMMISSION is available (``commission_status`` ACTIVE / INACTIVE / UNKNOWN),
* an AFFILIATE LINK exists (``affiliate_url``).

Eligibility (shown in results) and routing (affiliate vs organic link) are
computed from those facts on every read -- never stored -- so an item that
comes back in stock, or whose commission is restored, is re-enabled
automatically. Nothing here invents stock, prices or commission: every value
comes from a staff edit, a trusted feed import, or a page's own metadata the
staff member confirmed, and each change is recorded with who / when / how.
"""

from __future__ import annotations

import csv
import io
import json
import re
import sqlite3
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any, Callable, ClassVar, Iterable
from urllib.parse import urlparse

STOCK_STATES = ("IN_STOCK", "OUT_OF_STOCK", "UNKNOWN")
COMMISSION_STATES = ("ACTIVE", "INACTIVE", "UNKNOWN")
CHECK_SOURCES = ("manual", "feed", "api", "page_metadata", "postback")
# One reusable item store for everything staff curate (Staff Workspace):
# shopping items appear in chat results; news / video / content items are
# listed through /api/content. Rows created before items existed are LIVE.
ITEM_TYPES = ("product", "offer", "coupon", "service", "link", "news", "video", "content")
RESULT_ITEM_TYPES = ("product", "offer", "coupon", "service", "link")
REVIEW_STATES = ("DRAFT", "NEEDS_REVIEW", "APPROVED", "LIVE", "PAUSED", "EXPIRED")

# Platform id -> display name, hosts its URLs live on (incl. short links),
# and the host a site-restricted organic web search uses (None = no search).
PLATFORMS: dict[str, dict[str, Any]] = {
    "meesho": {"name": "Meesho", "hosts": ("meesho.com", "msho.in"), "search_host": "meesho.com"},
    "amazon": {"name": "Amazon", "hosts": ("amazon.in", "amzn.to", "amzn.in", "amzn.eu"),
               "search_host": "amazon.in"},
    "flipkart": {"name": "Flipkart", "hosts": ("flipkart.com", "fkrt.it", "fkrt.cc", "fkrt.co"),
                 "search_host": "flipkart.com"},
    "wishlink": {"name": "Wishlink", "hosts": ("wishlink.com", "wishlink.in"), "search_host": None},
    "other": {"name": "Other", "hosts": (), "search_host": None},
}

# Per-source settings kept in the existing #113 affiliate provider registry
# (``affiliate_providers``), with these defaults when a field was never set.
SOURCE_DEFAULTS: dict[str, Any] = {
    "organic_enabled": True,        # show its normal (non-affiliate) results
    "monetization_enabled": True,   # admin kill switch for affiliate routing
    "mode": "manual",               # api | feed | manual
    "commission_state": "UNKNOWN",  # source-wide: INACTIVE forces organic
}
SOURCE_MODES = ("api", "feed", "manual")
_SECRET_FIELD = re.compile(r"secret|token|password|api_key|apikey|private|signature", re.IGNORECASE)

EDITABLE_FIELDS = ("title", "platform", "original_product_url", "affiliate_url", "image_url", "images",
                   "price", "mrp", "currency", "category", "subcategory", "description", "variants",
                   "seller", "merchant", "sponsored", "location", "availability", "verified_commission_rate",
                   "brand", "product_id", "canonical_url", "item_type", "offer_text", "rating", "review_count",
                   "coverage", "expires_at", "source_ref")
LINK_FIELDS = {"affiliate_url"}

_NEW_COLUMNS = {
    "brand": "TEXT",
    "product_id": "TEXT",
    "canonical_url": "TEXT",
    "platform": "TEXT NOT NULL DEFAULT ''",
    "mrp": "REAL",
    "images_json": "TEXT NOT NULL DEFAULT '[]'",
    "description": "TEXT NOT NULL DEFAULT ''",
    "variants_json": "TEXT NOT NULL DEFAULT '[]'",
    "seller": "TEXT NOT NULL DEFAULT ''",
    "commission_status": "TEXT NOT NULL DEFAULT 'UNKNOWN'",
    "sponsored": "INTEGER NOT NULL DEFAULT 0",
    "location": "TEXT NOT NULL DEFAULT ''",
    "availability": "TEXT NOT NULL DEFAULT ''",
    "stock_checked_at": "TEXT",
    "stock_check_source": "TEXT NOT NULL DEFAULT ''",
    "commission_checked_at": "TEXT",
    "commission_check_source": "TEXT NOT NULL DEFAULT ''",
    "price_checked_at": "TEXT",
    "deleted_at": "TEXT",
    "created_by": "TEXT NOT NULL DEFAULT ''",
    "updated_by": "TEXT NOT NULL DEFAULT ''",
    "created_at": "TEXT",
    "updated_at": "TEXT",
    # Staff Workspace: item kind, review workflow, duplicate key, source link.
    "item_type": "TEXT NOT NULL DEFAULT 'product'",
    "review_status": "TEXT NOT NULL DEFAULT 'LIVE'",
    "source_ref": "TEXT NOT NULL DEFAULT ''",
    "canonical_key": "TEXT NOT NULL DEFAULT ''",
    "submitted_by": "TEXT NOT NULL DEFAULT ''",
    "reviewed_by": "TEXT NOT NULL DEFAULT ''",
    "reviewed_at": "TEXT",
    "review_note": "TEXT NOT NULL DEFAULT ''",
    "expires_at": "TEXT",
    "offer_text": "TEXT NOT NULL DEFAULT ''",
    "rating": "REAL",
    "review_count": "INTEGER",
    "coverage": "TEXT NOT NULL DEFAULT ''",
}


def canonical_key(url: Any) -> str:
    """Duplicate key for a URL: host without www, path without trailing
    slash, tracking parameters dropped (two staff pasting the same product
    from different share links collide here)."""
    try:
        clean = _strip_tracking(https_url(url) or str(url or ""))
    except ValueError:
        clean = str(url or "").strip()
    parsed = urlparse(clean if "://" in clean else "https://" + clean)
    host = (parsed.hostname or "").lower()
    host = host[4:] if host.startswith("www.") else host
    path = re.sub(r"/+$", "", parsed.path or "")
    platform = detect_platform(f"https://{host}/")
    pid = product_id_from_url(clean) if platform != "other" else ""
    if pid:
        return f"{platform}:{pid}"
    return f"{host}{path}" + (f"?{parsed.query}" if parsed.query else "")


def policy() -> dict[str, bool]:
    """Admin toggles (Platform settings) for automatic product health."""
    try:
        from app.services import platform_settings as ps

        get = ps.get
    except Exception:  # pragma: no cover
        get = lambda key, default=None: default  # noqa: E731
    return {"hide_out_of_stock": bool(get("catalog.hide_out_of_stock", None)),
            "organic_when_commission_inactive": bool(get("catalog.organic_when_commission_inactive", None)),
            "pause_on_out_of_stock": bool(get("catalog.pause_on_out_of_stock", None))}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _host(url: str) -> str:
    try:
        return (urlparse(str(url or "")).hostname or "").lower().removeprefix("www.")
    except ValueError:
        return ""


def detect_platform(url: str) -> str:
    host = _host(url)
    for pid, info in PLATFORMS.items():
        if any(host == h or host.endswith("." + h) for h in info["hosts"]):
            return pid
    return "other"


def https_url(value: Any) -> str:
    url = str(value or "").strip()
    if not url:
        return ""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("Links must be full https:// URLs")
    return url[:2000]


def normalize_stock(value: Any) -> str:
    low = re.sub(r"[\s_-]+", " ", str(value or "").strip().lower())
    if low in {"in stock", "instock", "available", "yes", "in", "limited stock", "limitedavailability"}:
        return "IN_STOCK"
    if low in {"out of stock", "outofstock", "oos", "sold out", "soldout", "unavailable", "no", "out",
               "discontinued"}:
        return "OUT_OF_STOCK"
    return "UNKNOWN"


def normalize_commission(value: Any) -> str:
    low = str(value or "").strip().lower()
    if low in {"active", "yes", "on", "available", "enabled", "true", "1"}:
        return "ACTIVE"
    if low in {"inactive", "no", "off", "removed", "unavailable", "disabled", "paused", "false", "0"}:
        return "INACTIVE"
    return "UNKNOWN"


def _money(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        number = float(str(value).replace(",", "").replace("₹", "").strip())
    except ValueError:
        raise ValueError(f"Not a price: {value!r}")
    if number < 0:
        raise ValueError("Prices cannot be negative")
    return round(number, 2)


def _list(value: Any) -> list[str]:
    if value in (None, ""):
        return []
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                value = parsed
        except ValueError:
            value = re.split(r"[|\n,]", value)
    return [str(v).strip()[:200] for v in value if str(v).strip()][:20]


# --------------------------------------------------------------- sources --

def source_settings(config: Any) -> dict[str, dict[str, Any]]:
    """Every catalog platform's source settings, credentials never included."""
    providers = dict(getattr(config, "providers", {}) or {})
    out: dict[str, dict[str, Any]] = {}
    for pid, info in PLATFORMS.items():
        stored = dict(providers.get(pid) or {})
        row = {**SOURCE_DEFAULTS, **{k: v for k, v in stored.items() if k in SOURCE_DEFAULTS}}
        row.update({
            "platform": pid, "name": stored.get("name") or info["name"],
            "registry_active": bool(stored.get("active", False)) if stored else False,
            "api_enabled": bool(stored.get("api_enabled", False)),
            "callback_enabled": bool(stored.get("callback_enabled", False)),
            "tracking_template_set": bool(str(stored.get("tracking_template") or "").strip()),
            "deep_link_set": bool(str(stored.get("deep_link") or "").strip()),
            "has_credentials": any(_SECRET_FIELD.search(k) and v for k, v in stored.items()),
            "organic_search": bool(info["search_host"]),
            "staff_permissions": ["affiliate_products:view", "affiliate_products:create",
                                  "affiliate_products:edit", "affiliate_products:stock",
                                  "affiliate_products:commission", "affiliate_products:links",
                                  "affiliate_products:bulk_import"],
        })
        row["commission_state"] = normalize_commission(row.get("commission_state"))
        row["mode"] = row["mode"] if row["mode"] in SOURCE_MODES else "manual"
        out[pid] = row
    return out


def save_source(config: Any, platform: str, changes: dict[str, Any]) -> dict[str, Any]:
    if platform not in PLATFORMS:
        raise ValueError("Unknown source")
    clean: dict[str, Any] = {}
    for key in ("organic_enabled", "monetization_enabled"):
        if key in changes and changes[key] is not None:
            clean[key] = bool(changes[key])
    if changes.get("mode") is not None:
        if changes["mode"] not in SOURCE_MODES:
            raise ValueError("mode must be api, feed or manual")
        clean["mode"] = changes["mode"]
    if changes.get("commission_state") is not None:
        clean["commission_state"] = normalize_commission(changes["commission_state"])
    existing = dict((getattr(config, "providers", {}) or {}).get(platform) or {})
    if not existing:
        existing = {"name": PLATFORMS[platform]["name"], "category": "product", "active": False,
                    "api_enabled": False, "callback_enabled": False, "gateway": "external",
                    "disclosure": "Affiliate link"}
    existing.pop("provider_id", None)
    config.register(platform, **{**existing, **clean})
    return source_settings(config)[platform]


# --------------------------------------------------- eligibility / routing --

def evaluate(row: dict[str, Any], sources: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    """Result eligibility and link routing for one product row.

    Eligible = exists (not deleted) + enabled by staff + not OUT_OF_STOCK +
    its source's organic results switched on. Routing is ``affiliate`` only
    when commission is ACTIVE, an affiliate URL exists, the source allows
    monetization and the source-wide commission is not INACTIVE; otherwise
    the useful result stays, through its normal (organic) URL."""
    source = (sources or {}).get(str(row.get("platform") or "other")) or {**SOURCE_DEFAULTS}
    reasons: list[str] = []
    if row.get("deleted_at"):
        reasons.append("deleted")
    if not row.get("active"):
        reasons.append("disabled_by_staff")
    rules = policy()
    if row.get("stock_status") == "OUT_OF_STOCK" and rules["hide_out_of_stock"]:
        reasons.append("out_of_stock")
    review = str(row.get("review_status") or "LIVE")
    if review != "LIVE":
        reasons.append("review_" + review.lower())
    expires = str(row.get("expires_at") or "")
    if expires and expires[:19] < now_iso()[:19]:
        reasons.append("expired")
    if row.get("commission_status") == "INACTIVE" and not rules["organic_when_commission_inactive"] \
            and str(row.get("affiliate_url") or "").strip():
        reasons.append("commission_inactive_hidden")
    if not source.get("organic_enabled", True):
        reasons.append("source_off")
    affiliate_reasons: list[str] = []
    if row.get("commission_status") != "ACTIVE":
        affiliate_reasons.append("commission_" + str(row.get("commission_status") or "UNKNOWN").lower())
    if not str(row.get("affiliate_url") or "").strip():
        affiliate_reasons.append("no_affiliate_link")
    if not source.get("monetization_enabled", True):
        affiliate_reasons.append("source_monetization_off")
    if source.get("commission_state") == "INACTIVE":
        affiliate_reasons.append("source_commission_inactive")
    affiliate = not affiliate_reasons
    return {
        "eligible": not reasons,
        "state": "ACTIVE" if not reasons else "DISABLED",
        "reasons": reasons,
        "routing": "affiliate" if affiliate else "organic",
        "routing_reasons": affiliate_reasons,
        "destination_url": row.get("affiliate_url") if affiliate else row.get("original_product_url"),
        "link": "AFFILIATE" if str(row.get("affiliate_url") or "").strip() else "ORGANIC",
        "last_checked": max([v for v in (row.get("stock_checked_at"), row.get("commission_checked_at"),
                                         row.get("price_checked_at")) if v] or [None], key=lambda v: v or ""),
    }


def _public(row: dict[str, Any], sources: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    item = dict(row)
    item["images"] = _list(item.pop("images_json", "[]"))
    item["variants"] = _list(item.pop("variants_json", "[]"))
    item.pop("metadata_json", None)
    item["active"] = bool(item.get("active"))
    item["sponsored"] = bool(item.get("sponsored"))
    price, mrp = item.get("price"), item.get("mrp")
    item["discount_percent"] = (round((mrp - price) / mrp * 100) if isinstance(price, (int, float))
                                and isinstance(mrp, (int, float)) and mrp > price > 0 else None)
    item["platform_name"] = PLATFORMS.get(item.get("platform") or "other", PLATFORMS["other"])["name"]
    item["eligibility"] = evaluate(item, sources)
    return item


# ---------------------------------------------------------------- store --

@dataclass
class AffiliateCatalog:
    db_path: str

    def __post_init__(self) -> None:
        from app.services.partner_revenue_hub import PartnerRevenueHub

        PartnerRevenueHub(self.db_path)  # owns the base table (#127)
        with self._connect() as conn:
            have = {r["name"] for r in conn.execute("PRAGMA table_info(affiliate_products)")}
            for column, ddl in _NEW_COLUMNS.items():
                if column not in have:
                    conn.execute(f"ALTER TABLE affiliate_products ADD COLUMN {column} {ddl}")
            # #127 rows: platform from the URL, stock text to the three states.
            for row in conn.execute("SELECT id, original_product_url, stock_status, platform FROM affiliate_products"
                                    " WHERE platform='' OR stock_status NOT IN ('IN_STOCK','OUT_OF_STOCK','UNKNOWN')"
                                    ).fetchall():
                conn.execute("UPDATE affiliate_products SET platform=?, stock_status=? WHERE id=?",
                             (row["platform"] or detect_platform(row["original_product_url"]),
                              normalize_stock(row["stock_status"]), row["id"]))
            for row in conn.execute("SELECT id, original_product_url FROM affiliate_products WHERE canonical_key=''"
                                    ).fetchall():
                conn.execute("UPDATE affiliate_products SET canonical_key=? WHERE id=?",
                             (canonical_key(row["original_product_url"]), row["id"]))
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS affiliate_product_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                at TEXT NOT NULL,
                actor TEXT NOT NULL,
                action TEXT NOT NULL,
                check_source TEXT NOT NULL DEFAULT 'manual',
                changes_json TEXT NOT NULL DEFAULT '{}',
                note TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_affiliate_product_history ON affiliate_product_history(product_id, id);
            CREATE TABLE IF NOT EXISTS affiliate_source_health (
                platform TEXT PRIMARY KEY,
                last_check_at TEXT,
                last_success_at TEXT,
                last_status TEXT NOT NULL DEFAULT '',
                last_results INTEGER NOT NULL DEFAULT 0,
                last_method TEXT NOT NULL DEFAULT ''
            );
            """)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------------------------------------------------- reads --

    def _row(self, conn: sqlite3.Connection, product_id: int) -> dict[str, Any] | None:
        row = conn.execute("SELECT * FROM affiliate_products WHERE id=?", (int(product_id),)).fetchone()
        return dict(row) if row else None

    def get(self, product_id: int, sources: dict | None = None) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = self._row(conn, product_id)
        return _public(row, sources) if row else None

    def list(self, *, q: str = "", platform: str = "", stock: str = "", commission: str = "", state: str = "",
             include_deleted: bool = False, limit: int = 100, offset: int = 0,
             sources: dict | None = None) -> dict[str, Any]:
        sql, args = "SELECT * FROM affiliate_products WHERE 1=1", []
        if not include_deleted:
            sql += " AND deleted_at IS NULL"
        if platform:
            sql += " AND platform=?"; args.append(platform)
        if stock:
            sql += " AND stock_status=?"; args.append(stock.upper())
        if commission:
            sql += " AND commission_status=?"; args.append(commission.upper())
        for token in [t for t in str(q or "").lower().split() if t][:6]:
            sql += " AND (LOWER(title) LIKE ? OR LOWER(seller) LIKE ? OR LOWER(category) LIKE ? OR LOWER(original_product_url) LIKE ?)"
            args.extend([f"%{token}%"] * 4)
        with self._connect() as conn:
            rows = [_public(dict(r), sources) for r in conn.execute(sql + " ORDER BY id DESC", args).fetchall()]
        if state:
            rows = [r for r in rows if r["eligibility"]["state"] == state.upper()]
        summary = {
            "total": len(rows),
            "eligible": sum(1 for r in rows if r["eligibility"]["eligible"]),
            "out_of_stock": sum(1 for r in rows if r["stock_status"] == "OUT_OF_STOCK"),
            "commission_active": sum(1 for r in rows if r["commission_status"] == "ACTIVE"),
            "affiliate_routed": sum(1 for r in rows if r["eligibility"]["routing"] == "affiliate"),
        }
        start = max(0, int(offset or 0))
        return {"items": rows[start:start + max(1, min(int(limit or 100), 500))], "summary": summary}

    def history(self, product_id: int, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM affiliate_product_history WHERE product_id=? ORDER BY id DESC LIMIT ?",
                                (int(product_id), max(1, min(limit, 500)))).fetchall()
        out = []
        for r in rows:
            item = dict(r)
            item["changes"] = json.loads(item.pop("changes_json") or "{}")
            out.append(item)
        return out

    # --------------------------------------------------------- writes --

    @staticmethod
    def _clean(values: dict[str, Any]) -> dict[str, Any]:
        """Validated column values for the editable fields present."""
        out: dict[str, Any] = {}
        for key, value in values.items():
            if key not in EDITABLE_FIELDS:
                continue
            if key in {"original_product_url", "affiliate_url", "image_url", "canonical_url"}:
                out[key] = https_url(value)
            elif key in {"price", "mrp", "verified_commission_rate", "rating"}:
                out[key] = _money(value)
            elif key == "review_count":
                out[key] = int(_money(value) or 0) if value not in (None, "") else None
            elif key == "item_type":
                if value and value not in ITEM_TYPES:
                    raise ValueError("item type must be one of " + ", ".join(ITEM_TYPES))
                out[key] = value or "product"
            elif key == "expires_at":
                out[key] = str(value or "").strip()[:25] or None
            elif key in {"offer_text", "coverage"}:
                out[key] = str(value or "").strip()[:500]
            elif key == "images":
                out["images_json"] = json.dumps([https_url(v) for v in _list(value)])
            elif key == "variants":
                out["variants_json"] = json.dumps(_list(value), ensure_ascii=False)
            elif key == "sponsored":
                out[key] = int(bool(value) and str(value).lower() not in {"false", "0", "no"})
            elif key == "platform":
                if value and value not in PLATFORMS:
                    raise ValueError("platform must be meesho, amazon, flipkart, wishlink or other")
                out[key] = value or ""
            elif key in {"category", "subcategory"}:
                out[key] = str(value or "").strip().lower()[:80]
            elif key == "description":
                out[key] = str(value or "").strip()[:4000]
            else:
                out[key] = str(value or "").strip()[:300]
        if out.get("price") is not None and out.get("mrp") is not None and out["mrp"] < out["price"]:
            raise ValueError("Original price / MRP cannot be lower than the current price")
        return out

    def _record(self, conn, product_id: int, actor: str, action: str, changes: dict[str, Any],
                check_source: str = "manual", note: str = "") -> None:
        conn.execute("""INSERT INTO affiliate_product_history(product_id,at,actor,action,check_source,changes_json,note)
            VALUES(?,?,?,?,?,?,?)""", (int(product_id), now_iso(), actor, action, check_source,
                                       json.dumps(changes, ensure_ascii=False, default=str), note[:500]))

    def duplicates(self, url: Any) -> list[dict[str, Any]]:
        """Existing (not deleted) items for the same canonical URL / product id."""
        key = canonical_key(url)
        if not key:
            return []
        with self._connect() as conn:
            rows = conn.execute("SELECT id, title, review_status, item_type, submitted_by, created_by FROM "
                                "affiliate_products WHERE canonical_key=? AND deleted_at IS NULL", (key,)).fetchall()
        return [dict(r) for r in rows]

    def create(self, values: dict[str, Any], *, actor: str, check_source: str = "manual",
               stock_status: Any = None, commission_status: Any = None,
               review_status: str = "LIVE") -> dict[str, Any]:
        clean = self._clean(values)
        url = clean.get("original_product_url")
        if not url:
            raise ValueError("The product's normal URL is required")
        if not clean.get("title"):
            raise ValueError("A product name is required")
        platform = clean.get("platform") or detect_platform(url)
        clean["platform"] = platform
        at = now_iso()
        stock = normalize_stock(stock_status)
        commission = normalize_commission(commission_status)
        images = json.loads(clean.get("images_json") or "[]")
        if not clean.get("image_url") and images:
            clean["image_url"] = images[0]
        columns = {
            "partner_id": platform, "source": "staff_catalog", "merchant": clean.get("merchant") or PLATFORMS[platform]["name"],
            "currency": clean.get("currency") or "INR", "category": clean.get("category") or "general",
            "active": 1, "stock_status": stock, "commission_status": commission,
            "stock_checked_at": at if stock != "UNKNOWN" else None,
            "stock_check_source": check_source if stock != "UNKNOWN" else "",
            "commission_checked_at": at if commission != "UNKNOWN" else None,
            "commission_check_source": check_source if commission != "UNKNOWN" else "",
            "price_checked_at": at if clean.get("price") is not None else None,
            "created_by": actor, "updated_by": actor, "created_at": at, "updated_at": at, "metadata_json": "{}",
            "review_status": review_status if review_status in REVIEW_STATES else "NEEDS_REVIEW",
            "submitted_by": actor, "canonical_key": canonical_key(url), "item_type": clean.get("item_type") or "product",
            **{k: v for k, v in clean.items() if k not in {"merchant", "currency", "category"}},
        }
        with self._connect() as conn:
            existing = conn.execute("SELECT id, deleted_at FROM affiliate_products WHERE partner_id=? AND original_product_url=?",
                                    (platform, url)).fetchone()
            if existing and not existing["deleted_at"]:
                raise ValueError(f"This {PLATFORMS[platform]['name']} product is already in the catalog (#{existing['id']})")
            same = conn.execute("SELECT id FROM affiliate_products WHERE canonical_key=? AND deleted_at IS NULL",
                                (columns["canonical_key"],)).fetchone()
            if same and not existing:
                raise ValueError(f"Already in the catalog as #{same['id']} (same product / link)")
            if existing:  # re-adding a deleted product restores its row and history
                conn.execute("UPDATE affiliate_products SET deleted_at=NULL WHERE id=?", (existing["id"],))
                sets = ", ".join(f"{k}=?" for k in columns if k != "created_at")
                conn.execute(f"UPDATE affiliate_products SET {sets} WHERE id=?",
                             [v for k, v in columns.items() if k != "created_at"] + [existing["id"]])
                product_id = int(existing["id"])
            else:
                cur = conn.execute(f"INSERT INTO affiliate_products({','.join(columns)}) VALUES({','.join('?' * len(columns))})",
                                   list(columns.values()))
                product_id = int(cur.lastrowid)
            self._record(conn, product_id, actor, "create", {k: columns[k] for k in columns
                                                             if k not in {"metadata_json", "created_at", "updated_at"}},
                         check_source)
            row = self._row(conn, product_id)
        return _public(row)

    def update(self, product_id: int, values: dict[str, Any], *, actor: str, action: str = "edit",
               check_source: str = "manual", note: str = "") -> dict[str, Any]:
        clean = self._clean(values)
        with self._connect() as conn:
            before = self._row(conn, product_id)
            if not before or before.get("deleted_at"):
                raise LookupError("Product not found")
            if "price" in clean and clean["price"] is not None and before.get("mrp") and "mrp" not in clean \
                    and clean["price"] > before["mrp"]:
                raise ValueError("Current price is above the saved original price / MRP")
            if "mrp" in clean and clean["mrp"] is not None and "price" not in clean and before.get("price") \
                    and clean["mrp"] < before["price"]:
                raise ValueError("Original price / MRP cannot be lower than the current price")
            changes = {k: {"from": before.get(k), "to": v} for k, v in clean.items() if before.get(k) != v}
            if not changes:
                return _public(before)
            at = now_iso()
            sets = {k: v for k, v in clean.items()}
            if clean.get("original_product_url"):
                sets["canonical_key"] = canonical_key(clean["original_product_url"])
            if "price" in clean:
                sets["price_checked_at"] = at
            sets.update({"updated_by": actor, "updated_at": at})
            conn.execute(f"UPDATE affiliate_products SET {', '.join(f'{k}=?' for k in sets)} WHERE id=?",
                         list(sets.values()) + [int(product_id)])
            self._record(conn, product_id, actor, action, changes, check_source, note)
            row = self._row(conn, product_id)
        return _public(row)

    def _set_state(self, product_id: int, column: str, value: str, *, actor: str, check_source: str,
                   note: str = "", extra: dict[str, Any] | None = None) -> dict[str, Any]:
        prefix = "stock" if column == "stock_status" else "commission"
        with self._connect() as conn:
            before = self._row(conn, product_id)
            if not before or before.get("deleted_at"):
                raise LookupError("Product not found")
            at = now_iso()
            sets = {column: value, f"{prefix}_checked_at": at, f"{prefix}_check_source": check_source,
                    "updated_by": actor, "updated_at": at, **(extra or {})}
            conn.execute(f"UPDATE affiliate_products SET {', '.join(f'{k}=?' for k in sets)} WHERE id=?",
                         list(sets.values()) + [int(product_id)])
            changes = {column: {"from": before.get(column), "to": value}}
            for k, v in (extra or {}).items():
                if before.get(k) != v:
                    changes[k] = {"from": before.get(k), "to": v}
            self._record(conn, product_id, actor, prefix, changes, check_source, note)
            row = self._row(conn, product_id)
        return _public(row)

    def set_stock(self, product_id: int, status: Any, *, actor: str, check_source: str = "manual",
                  note: str = "") -> dict[str, Any]:
        value = str(status or "").upper()
        if value not in STOCK_STATES:
            value = normalize_stock(status)
        item = self._set_state(product_id, "stock_status", value, actor=actor, check_source=check_source, note=note)
        # Automatic product health (admin toggle): pause while out of stock,
        # back to LIVE when stock returns -- only for items the rule paused.
        if value == "OUT_OF_STOCK" and policy()["pause_on_out_of_stock"] and item.get("review_status") == "LIVE":
            item = self.set_review(product_id, "PAUSED", actor="system", note="auto:out_of_stock")
        elif value == "IN_STOCK" and item.get("review_status") == "PAUSED" \
                and item.get("review_note") == "auto:out_of_stock":
            item = self.set_review(product_id, "LIVE", actor="system", note="auto:back_in_stock")
        return item

    def set_review(self, product_id: int, status: str, *, actor: str, note: str = "") -> dict[str, Any]:
        if status not in REVIEW_STATES:
            raise ValueError("review status must be one of " + ", ".join(REVIEW_STATES))
        with self._connect() as conn:
            before = self._row(conn, product_id)
            if not before or before.get("deleted_at"):
                raise LookupError("Product not found")
            at = now_iso()
            conn.execute("UPDATE affiliate_products SET review_status=?, reviewed_by=?, reviewed_at=?, review_note=?, "
                         "updated_by=?, updated_at=? WHERE id=?",
                         (status, actor, at, note[:500], actor, at, int(product_id)))
            self._record(conn, product_id, actor, "review",
                         {"review_status": {"from": before.get("review_status"), "to": status}}, "manual", note)
            row = self._row(conn, product_id)
        return _public(row)

    def set_commission(self, product_id: int, status: Any, *, actor: str, check_source: str = "manual",
                       rate: Any = None, note: str = "") -> dict[str, Any]:
        value = str(status or "").upper()
        if value not in COMMISSION_STATES:
            value = normalize_commission(status)
        extra = {"verified_commission_rate": _money(rate)} if rate not in (None, "") else None
        return self._set_state(product_id, "commission_status", value, actor=actor, check_source=check_source,
                               note=note, extra=extra)

    def set_active(self, product_id: int, active: bool, *, actor: str, note: str = "") -> dict[str, Any]:
        with self._connect() as conn:
            before = self._row(conn, product_id)
            if not before or before.get("deleted_at"):
                raise LookupError("Product not found")
            conn.execute("UPDATE affiliate_products SET active=?, updated_by=?, updated_at=? WHERE id=?",
                         (int(active), actor, now_iso(), int(product_id)))
            self._record(conn, product_id, actor, "enable" if active else "disable",
                         {"active": {"from": bool(before.get("active")), "to": active}}, "manual", note)
            row = self._row(conn, product_id)
        return _public(row)

    def delete(self, product_id: int, *, actor: str, note: str = "") -> dict[str, Any]:
        """Soft delete: never shown again, history kept (re-adding restores it)."""
        with self._connect() as conn:
            before = self._row(conn, product_id)
            if not before or before.get("deleted_at"):
                raise LookupError("Product not found")
            at = now_iso()
            conn.execute("UPDATE affiliate_products SET deleted_at=?, active=0, updated_by=?, updated_at=? WHERE id=?",
                         (at, actor, at, int(product_id)))
            self._record(conn, product_id, actor, "delete", {"deleted_at": {"from": None, "to": at}}, "manual", note)
            row = self._row(conn, product_id)
        return _public(row)

    # ----------------------------------------------------------- bulk --

    @staticmethod
    def parse_rows(rows: Iterable[dict[str, Any]] | None = None, csv_text: str = "") -> list[dict[str, Any]]:
        out = [dict(r) for r in (rows or []) if isinstance(r, dict)]
        if csv_text.strip():
            reader = csv.DictReader(io.StringIO(csv_text.strip()))
            out.extend({(k or "").strip().lower(): (v or "").strip() for k, v in r.items()} for r in reader)
        aliases = {"url": "original_product_url", "product_url": "original_product_url", "link": "original_product_url",
                   "affiliate_link": "affiliate_url", "deep_link": "affiliate_url", "name": "title",
                   "original_price": "mrp", "stock": "stock_status", "commission": "commission_status",
                   "image": "image_url", "source": "platform"}
        return [{aliases.get(k, k): v for k, v in r.items()} for r in out][:500]

    def bulk(self, rows: list[dict[str, Any]], *, actor: str, mode: str = "upsert", check_source: str = "manual",
             dry_run: bool = False, allowed: Callable[[str], bool] = lambda _: True) -> dict[str, Any]:
        """``upsert`` creates or edits products; ``status`` only applies stock /
        commission / price updates to products that already exist (a trusted
        feed). Each row succeeds or fails on its own."""
        results: list[dict[str, Any]] = []
        for index, raw in enumerate(rows):
            try:
                url = https_url(raw.get("original_product_url"))
                pid_value = raw.get("id")
                existing = None
                if pid_value not in (None, ""):
                    existing = self.get(int(pid_value))
                elif url:
                    platform = raw.get("platform") or detect_platform(url)
                    with self._connect() as conn:
                        hit = conn.execute("SELECT id FROM affiliate_products WHERE partner_id=? AND original_product_url=?"
                                           " AND deleted_at IS NULL", (platform, url)).fetchone()
                    existing = self.get(hit["id"]) if hit else None
                stock = raw.get("stock_status")
                commission = raw.get("commission_status")
                if stock not in (None, "") and not allowed("stock"):
                    raise PermissionError("needs affiliate_products:stock")
                if commission not in (None, "") and not allowed("commission"):
                    raise PermissionError("needs affiliate_products:commission")
                if raw.get("affiliate_url") and not allowed("links"):
                    raise PermissionError("needs affiliate_products:links")
                if mode == "status":
                    if existing is None:
                        raise LookupError("not in the catalog (status updates never create products)")
                    if dry_run:
                        results.append({"row": index, "ok": True, "action": "status", "id": existing["id"]})
                        continue
                    if stock not in (None, ""):
                        self.set_stock(existing["id"], stock, actor=actor, check_source=check_source)
                    if commission not in (None, ""):
                        self.set_commission(existing["id"], commission, actor=actor, check_source=check_source,
                                            rate=raw.get("verified_commission_rate"))
                    if raw.get("price") not in (None, ""):
                        self.update(existing["id"], {"price": raw["price"], **({"mrp": raw["mrp"]} if raw.get("mrp") else {})},
                                    actor=actor, action="price", check_source=check_source)
                    results.append({"row": index, "ok": True, "action": "status", "id": existing["id"]})
                    continue
                fields = {k: v for k, v in raw.items() if k in EDITABLE_FIELDS and v not in (None, "")}
                if existing is not None:
                    if not allowed("edit"):
                        raise PermissionError("needs affiliate_products:edit")
                    if dry_run:
                        results.append({"row": index, "ok": True, "action": "update", "id": existing["id"]})
                        continue
                    self.update(existing["id"], fields, actor=actor, action="bulk_edit", check_source=check_source)
                    if stock not in (None, ""):
                        self.set_stock(existing["id"], stock, actor=actor, check_source=check_source)
                    if commission not in (None, ""):
                        self.set_commission(existing["id"], commission, actor=actor, check_source=check_source)
                    results.append({"row": index, "ok": True, "action": "update", "id": existing["id"]})
                else:
                    if not allowed("create"):
                        raise PermissionError("needs affiliate_products:create")
                    self._clean(fields)  # validate before a dry run reports ok
                    if not fields.get("title"):
                        raise ValueError("A product name is required")
                    if dry_run:
                        results.append({"row": index, "ok": True, "action": "create"})
                        continue
                    item = self.create(fields, actor=actor, check_source=check_source,
                                       stock_status=stock, commission_status=commission)
                    results.append({"row": index, "ok": True, "action": "create", "id": item["id"]})
            except (ValueError, LookupError, PermissionError) as error:
                results.append({"row": index, "ok": False, "error": str(error)})
        return {"results": results, "ok": sum(1 for r in results if r["ok"]),
                "failed": sum(1 for r in results if not r["ok"]), "dry_run": dry_run}

    # ---------------------------------------------------- source health --

    _health_written: ClassVar[dict[str, float]] = {}

    def record_health(self, platform: str, *, status: str, results: int, method: str) -> None:
        key = f"{self.db_path}:{platform}"
        if time.monotonic() - self._health_written.get(key, -1e9) < 300 and status == "ok":
            return  # at most one write per source per 5 minutes on the search path
        self._health_written[key] = time.monotonic()
        at = now_iso()
        with self._connect() as conn:
            conn.execute("""INSERT INTO affiliate_source_health(platform,last_check_at,last_success_at,last_status,
                last_results,last_method) VALUES(?,?,?,?,?,?) ON CONFLICT(platform) DO UPDATE SET
                last_check_at=excluded.last_check_at, last_status=excluded.last_status,
                last_results=excluded.last_results, last_method=excluded.last_method,
                last_success_at=COALESCE(excluded.last_success_at, affiliate_source_health.last_success_at)""",
                         (platform, at, at if results > 0 else None, status, int(results), method))

    def health(self) -> dict[str, dict[str, Any]]:
        with self._connect() as conn:
            return {r["platform"]: dict(r) for r in conn.execute("SELECT * FROM affiliate_source_health")}

    # ------------------------------------------------------- discovery --

    def search(self, subject: str, *, sources: dict | None = None, limit: int = 6,
               category: str = "") -> list[dict[str, Any]]:
        """Eligible products relevant to the need (relevance first; whether a
        product is monetized never decides if it is shown)."""
        from app.services.universal_external_result_service import relevant_to

        tokens = [t for t in re.findall(r"[a-z0-9]+", str(subject or "").lower()) if len(t) > 1][:6]
        if not tokens:
            return []
        sql = ("SELECT * FROM affiliate_products WHERE deleted_at IS NULL AND active=1 AND review_status='LIVE'"
               " AND item_type IN (" + ",".join("'" + t + "'" for t in RESULT_ITEM_TYPES) + ")")
        if policy()["hide_out_of_stock"]:
            sql += " AND stock_status!='OUT_OF_STOCK'"
        sql += " AND (" + " OR ".join(["LOWER(title) LIKE ? OR LOWER(subcategory) LIKE ? OR LOWER(category) LIKE ?"]
                                       * len(tokens)) + ")"
        args = [f"%{t}%" for t in tokens for _ in range(3)]
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(sql + " ORDER BY id DESC LIMIT 200", args).fetchall()]
        out = []
        for row in rows:
            text = " ".join(str(row.get(k) or "") for k in ("title", "subcategory", "category", "description"))
            if not relevant_to(subject, text):
                continue
            item = _public(row, sources)
            if item["eligibility"]["eligible"]:
                out.append(item)
            if len(out) >= limit:
                break
        return out


def result_row(item: dict[str, Any]) -> dict[str, Any]:
    """A chat result card for one eligible catalog product."""
    ev = item["eligibility"]
    affiliate = ev["routing"] == "affiliate"
    return {
        "id": f"catalog-{item['id']}",
        "match_id": f"catalog-{item['id']}",
        "provider_id": item.get("platform") or "other",
        "title": item.get("title") or "Product",
        "subtitle": item.get("seller") or item.get("platform_name"),
        "price": item.get("price"),
        "original_price": item.get("mrp"),
        "discount_percent": item.get("discount_percent"),
        "currency": item.get("currency") or "INR",
        "price_verified": False,
        "price_source": "catalog" if item.get("price") is not None else None,
        "price_checked_at": item.get("price_checked_at"),
        "image_url": item.get("image_url") or (item.get("images") or [None])[0],
        "images": item.get("images") or [],
        "match_source": "online",
        "source": "online",
        "origin": "affiliate_catalog",
        "source_name": item.get("platform_name"),
        "marketplace": item.get("platform"),
        "destination_url": ev["destination_url"],
        "web_fallback_url": item.get("original_product_url"),
        "open_strategy": "web",
        "affiliate": affiliate,
        "routing": ev["routing"],
        "disclosure": "Affiliate link" if affiliate else "",
        "sponsored": bool(item.get("sponsored")),
        "stock_status": item.get("stock_status"),
        "last_checked": ev["last_checked"],
        "location": item.get("location") or item.get("availability") or None,
        "item_type": item.get("item_type") or "product",
        "offer": item.get("offer_text") or None,
        "rating": item.get("rating"),
        "review_count": item.get("review_count"),
        "brand": item.get("brand") or None,
        "demo": False,
    }


# ------------------------------------------------- metadata extraction --

class _MetaParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.meta: dict[str, list[str]] = {}
        self.ld: list[str] = []
        self.title = ""
        self._in_ld = self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "meta":
            key = (a.get("property") or a.get("name") or a.get("itemprop") or "").lower()
            if key and a.get("content"):
                self.meta.setdefault(key, []).append(a["content"].strip())
        elif tag == "script" and "ld+json" in a.get("type", ""):
            self._in_ld = True
            self.ld.append("")
        elif tag == "title":
            self._in_title = True
        elif tag == "link" and "canonical" in a.get("rel", "").lower() and a.get("href", "").startswith("https://"):
            self.meta.setdefault("canonical", []).append(a["href"].strip())

    def handle_endtag(self, tag):
        if tag == "script":
            self._in_ld = False
        elif tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_ld:
            self.ld[-1] += data
        elif self._in_title:
            self.title += data


def _ld_products(blobs: list[str]) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []

    def walk(node):
        if isinstance(node, list):
            for x in node:
                walk(x)
        elif isinstance(node, dict):
            kind = node.get("@type")
            kinds = kind if isinstance(kind, list) else [kind]
            if "Product" in kinds:
                found.append(node)
            for value in node.values():
                if isinstance(value, (list, dict)):
                    walk(value)

    for blob in blobs:
        try:
            walk(json.loads(blob))
        except ValueError:
            continue
    return found


def parse_metadata(html: str, url: str) -> dict[str, Any]:
    """Product facts a page states about itself (Open Graph / schema.org).
    Suggestions only: staff confirm or correct them before saving."""
    parser = _MetaParser()
    try:
        parser.feed(html[:1_500_000])
    except Exception:
        pass
    meta = parser.meta
    first = lambda *keys: next((meta[k][0] for k in keys if meta.get(k)), "")
    fields: dict[str, Any] = {"original_product_url": url, "platform": detect_platform(url)}
    title = first("og:title", "twitter:title") or parser.title.strip()
    if title:
        fields["title"] = title[:300]
    images = [u for k in ("og:image", "og:image:secure_url", "twitter:image") for u in meta.get(k, [])
              if u.startswith("https://")]
    description = first("og:description", "description", "twitter:description")
    if description:
        fields["description"] = description[:4000]
    price = first("product:price:amount", "og:price:amount")
    stock_hint = first("product:availability", "og:availability")
    for product in _ld_products(parser.ld)[:1]:
        fields["title"] = str(product.get("name") or fields.get("title") or "")[:300]
        image = product.get("image")
        for value in (image if isinstance(image, list) else [image]):
            value = value.get("url") if isinstance(value, dict) else value
            if isinstance(value, str) and value.startswith("https://"):
                images.append(value)
        if product.get("description") and "description" not in fields:
            fields["description"] = str(product["description"])[:4000]
        offers = product.get("offers")
        offer = (offers[0] if isinstance(offers, list) and offers else offers) or {}
        if isinstance(offer, dict):
            price = price or str(offer.get("price") or offer.get("lowPrice") or "")
            stock_hint = stock_hint or str(offer.get("availability") or "")
    if images:
        fields["images"] = list(dict.fromkeys(images))[:8]
        fields["image_url"] = fields["images"][0]
    try:
        if price:
            fields["price"] = _money(price)
    except ValueError:
        pass
    suggested_stock = None
    if stock_hint:
        hint = stock_hint.rsplit("/", 1)[-1]
        suggested_stock = normalize_stock(re.sub(r"(?<!^)(?=[A-Z])", " ", hint))
    canonical = first("canonical", "og:url")
    fields["canonical_url"] = canonical if canonical.startswith("https://") else _strip_tracking(url)
    product_id = product_id_from_url(url) or product_id_from_url(canonical)
    for product in _ld_products(parser.ld)[:1]:
        product_id = product_id or str(product.get("sku") or product.get("productID") or product.get("mpn") or "")
        if product.get("category"):
            fields["category"] = str(product["category"])[:120]
        brand = product.get("brand")
        if isinstance(brand, dict):
            brand = brand.get("name")
        if brand:
            fields["brand"] = str(brand)[:120]
        offers = product.get("offers")
        offer = (offers[0] if isinstance(offers, list) and offers else offers) or {}
        seller = offer.get("seller") if isinstance(offer, dict) else None
        if isinstance(seller, dict) and seller.get("name"):
            fields["seller"] = str(seller["name"])[:200]
    if product_id:
        fields["product_id"] = product_id[:80]
    if "category" not in fields:
        crumbs = _breadcrumbs(parser.ld)
        if crumbs:
            fields["category"] = " > ".join(crumbs[-3:])[:160]
    if suggested_stock:
        fields["availability"] = suggested_stock
    fields["source"] = PLATFORMS.get(fields["platform"], {}).get("name") or _host(url)
    found = sorted(k for k in fields if k not in {"original_product_url", "platform"})
    return {"fields": fields, "suggested_stock": suggested_stock, "found": found,
            "field_status": field_status(fields)}


# What staff need before saving a product, and whether the page supplied it.
METADATA_FIELDS = ("title", "images", "price", "seller", "brand", "source", "product_id", "category",
                   "availability", "canonical_url")


def field_status(fields: dict[str, Any]) -> dict[str, str]:
    return {k: ("fetched" if fields.get(k) not in (None, "", []) else "manual_entry_required")
            for k in METADATA_FIELDS}


_PRODUCT_ID_PATTERNS = (
    ("amazon", re.compile(r"/(?:dp|gp/product|gp/aw/d)/([A-Z0-9]{10})(?:[/?]|$)")),
    ("flipkart", re.compile(r"[?&]pid=([A-Z0-9]{8,20})")),
    ("flipkart", re.compile(r"/p/(itm[a-z0-9]{6,})")),
    ("meesho", re.compile(r"/p/([a-z0-9]{3,20})(?:[/?]|$)")),
)


def product_id_from_url(url: str) -> str:
    """The marketplace's own product id from a URL (ASIN, Flipkart pid / itm,
    Meesho p/<id>) -- only from the URL itself, never guessed."""
    if not url:
        return ""
    platform = detect_platform(url)
    for pid, pattern in _PRODUCT_ID_PATTERNS:
        if pid == platform:
            match = pattern.search(url)
            if match:
                return match.group(1)
    return ""


def _strip_tracking(url: str) -> str:
    try:
        parts = urlparse(url)
    except ValueError:
        return url
    keep = [q for q in (parts.query or "").split("&") if q and not re.match(
        r"(utm_|ref|tag=|affid|affExtParam|srsltid|gclid|fbclid|_encoding|psc=|smid=|qid=|sr=|crid=|sprefix=|keywords=)",
        q, re.IGNORECASE)]
    return parts._replace(query="&".join(keep), fragment="").geturl()


def _breadcrumbs(blobs: list[str]) -> list[str]:
    for blob in blobs:
        try:
            data = json.loads(blob)
        except ValueError:
            continue
        nodes = data if isinstance(data, list) else [data]
        for node in nodes:
            if isinstance(node, dict) and node.get("@type") == "BreadcrumbList":
                items = sorted(node.get("itemListElement") or [], key=lambda i: int((i or {}).get("position") or 0))
                names = []
                for item in items:
                    item = item or {}
                    inner = item.get("item") if isinstance(item.get("item"), dict) else {}
                    name = item.get("name") or inner.get("name")
                    if name and str(name).casefold() not in ("home",):
                        names.append(str(name))
                if names:
                    return names
    return []


def fetch_page(url: str, *, timeout: float = 6.0, max_bytes: int = 1_500_000) -> str:
    """GET one public https page (no private / local hosts, every redirect
    re-checked, size and time bounded)."""
    import urllib.request

    from app.services.universal_external_result_service import PartnerApiConnector

    _safe_public_host = PartnerApiConnector._safe_public_host

    class Guard(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            target = urlparse(newurl)
            if target.scheme != "https" or not _safe_public_host(target.hostname or "", {}):
                raise ValueError("redirected to a non-public address")
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    parsed = urlparse(url)
    if parsed.scheme != "https" or not _safe_public_host(parsed.hostname or "", {}):
        raise ValueError("Only public https pages can be read")
    opener = urllib.request.build_opener(Guard())
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; ASKODOX-catalog/1.0)",
                                                   "Accept": "text/html"})
    with opener.open(request, timeout=timeout) as response:
        if "html" not in str(response.headers.get("content-type") or "html"):
            raise ValueError("not an HTML page")
        return response.read(max_bytes).decode("utf-8", errors="replace")


def extract_metadata(url: str, fetch: Callable[[str], str] | None = None) -> dict[str, Any]:
    url = https_url(url)
    if not url:
        raise ValueError("A product URL is required")
    try:
        html = (fetch or fetch_page)(url)
    except Exception as error:  # blocked by the site, timeout, non-public host
        fields = {"original_product_url": url, "platform": detect_platform(url),
                  "canonical_url": _strip_tracking(url), "product_id": product_id_from_url(url),
                  "source": PLATFORMS.get(detect_platform(url), {}).get("name") or _host(url)}
        fields = {k: v for k, v in fields.items() if v}
        return {"status": "unavailable", "fields": fields, "field_status": field_status(fields),
                "found": [], "suggested_stock": None,
                "note": f"The page could not be read automatically ({type(error).__name__}). Enter the details by hand."}
    parsed = parse_metadata(html, url)
    parsed["status"] = "ok" if parsed["found"] else "nothing_found"
    parsed["note"] = ("Suggested from the page's own metadata -- check and correct before saving."
                      if parsed["found"] else "The page did not publish product details. Enter them by hand.")
    return parsed
