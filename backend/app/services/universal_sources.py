"""Universal Sources: any number of web / marketplace / feed / API sources,
configured in the Command Center (``sources`` schema resource) -- no app
code or APK per source.

Connector modes (what ASKODOX may do with a source):

* ``manual``      staff add items through the Staff Workspace (paste a link);
* ``feed``        an approved JSON / CSV product feed, synced into the item
                  store (``affiliate_products``) -- searchable locally, so it
                  keeps working when a web-search provider (Brave) is down;
* ``json_search`` an approved public / partner JSON search endpoint called
                  live with the user's need (``{q}`` / ``{city}`` / ``{category}``);
* ``site_search`` organic rows from the source's own domain through the
                  configured web-search provider (Brave) -- skipped while that
                  provider is unavailable;
* ``api``         an official API adapter (``marketplace_api``: Amazon PA-API,
                  Flipkart) used to refresh items.

Nothing is scraped beyond a public page's own metadata, nothing is invented:
a value a source does not send is left empty. Every live call is bounded
(timeout, size, public https hosts only) and isolated -- one failed source
is recorded in ``source_health`` and never breaks the rest of the result.
"""
from __future__ import annotations

import csv
import io
import json
import re
import sqlite3
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, wait
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

SOURCE_TYPES = ("registered", "affiliate", "marketplace", "merchant", "product_site", "grocery_food", "travel",
                "finance", "healthcare", "education_jobs", "real_estate", "home_services", "logistics_mobility",
                "used_products", "automobiles", "entertainment", "saas", "ondc", "news_content", "other")
CONNECTORS = ("manual", "feed", "json_search", "site_search", "api")
MONETIZATION = ("organic", "affiliate", "sponsored")
FEED_FORMATS = ("json", "csv")
CARD_FIELDS = ("image", "title", "brand", "seller", "price", "original_price", "discount", "stock", "location",
               "offer", "rating", "source")
# Normalized field -> keys commonly used by feeds (overridden by field_map).
DEFAULT_FIELD_MAP = {
    "title": ("title", "name", "product_name"),
    "url": ("url", "link", "product_url", "original_product_url"),
    "image": ("image", "image_url", "img", "thumbnail"),
    "price": ("price", "sale_price", "selling_price"),
    "original_price": ("mrp", "original_price", "list_price"),
    "brand": ("brand",),
    "seller": ("seller", "merchant", "store"),
    "stock": ("stock", "availability", "in_stock", "stock_status"),
    "category": ("category",),
    "description": ("description", "summary"),
    "offer": ("offer", "deal", "coupon"),
    "rating": ("rating", "stars"),
    "review_count": ("reviews", "review_count", "ratings_count"),
    "location": ("location", "city"),
    "external_id": ("id", "sku", "product_id"),
}
MAX_FEED_BYTES = 5_000_000
MAX_FEED_ITEMS = 2000
MAX_LIVE_SOURCES = 6

Http = Callable[[str, float], tuple[int, Any]]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


# ------------------------------------------------------------- health --

class SourceHealth:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS source_health (
                source_id TEXT PRIMARY KEY, last_check_at TEXT, last_success_at TEXT, last_status TEXT NOT NULL
                DEFAULT '', last_error TEXT NOT NULL DEFAULT '', last_results INTEGER NOT NULL DEFAULT 0,
                failures_in_row INTEGER NOT NULL DEFAULT 0, last_sync_at TEXT, rows_shown INTEGER NOT NULL DEFAULT 0)""")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def record(self, source_id: str, *, ok: bool, results: int = 0, error: str = "", synced: bool = False) -> None:
        at = now_iso()
        with self._connect() as conn:
            conn.execute("""INSERT INTO source_health(source_id, last_check_at, last_success_at, last_status,
                last_error, last_results, failures_in_row, last_sync_at, rows_shown) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(source_id) DO UPDATE SET last_check_at=excluded.last_check_at,
                last_success_at=COALESCE(excluded.last_success_at, source_health.last_success_at),
                last_status=excluded.last_status, last_error=excluded.last_error, last_results=excluded.last_results,
                failures_in_row=CASE WHEN excluded.last_status='ok' THEN 0 ELSE source_health.failures_in_row + 1 END,
                last_sync_at=COALESCE(excluded.last_sync_at, source_health.last_sync_at),
                rows_shown=source_health.rows_shown + excluded.rows_shown""",
                         (source_id, at, at if ok else None, "ok" if ok else "error", "" if ok else error[:200],
                          int(results), 0 if ok else 1, at if synced else None, int(results) if ok else 0))

    def all(self) -> Dict[str, Dict[str, Any]]:
        with self._connect() as conn:
            return {r["source_id"]: dict(r) for r in conn.execute("SELECT * FROM source_health")}


# ---------------------------------------------------------- matching --

def _words(text: Any) -> set:
    return {w for w in re.findall(r"[a-z0-9]+", str(text or "").lower()) if len(w) > 2}


def _list(value: Any) -> List[str]:
    if isinstance(value, (list, tuple)):
        return [str(v).strip() for v in value if str(v).strip()]
    return [v.strip() for v in str(value or "").split(",") if v.strip()]


def applies(source: Dict[str, Any], demand: Dict[str, Any]) -> Optional[str]:
    """None when this source fits the need (sector + coverage), else why not."""
    sectors = [s.lower() for s in _list(source.get("sectors"))]
    if sectors:
        need = _words(" ".join(str(demand.get(k) or "") for k in ("domain", "category", "subject")))
        need |= {str(demand.get("domain") or "").lower(), str(demand.get("category") or "").lower()}
        if not any(s in need or any(s in w or w in s for w in need if len(w) > 3) for s in sectors):
            return "sector"
    place = str(demand.get("location_text") or "").lower()
    coverage = [c.lower() for c in _list(source.get("cities")) + _list(source.get("states"))]
    if coverage and place and not any(c in place for c in coverage):
        return "coverage"
    pincodes = _list(source.get("pincodes"))
    pin = re.search(r"\b\d{6}\b", place)
    if pincodes and pin and pin.group(0) not in pincodes:
        return "coverage"
    countries = [c.upper() for c in _list(source.get("countries"))]
    if countries and str(demand.get("country") or "IN").upper() not in countries:
        return "country"
    return None


# ------------------------------------------------------- normalizing --

def _path(data: Any, path: str) -> Any:
    for part in [p for p in str(path or "").split(".") if p]:
        if isinstance(data, list):
            try:
                data = data[int(part)]
            except (ValueError, IndexError):
                return None
        elif isinstance(data, dict):
            data = data.get(part)
        else:
            return None
    return data


def _pick(raw: Dict[str, Any], field: str, field_map: Dict[str, Any]) -> Any:
    if field in field_map:
        return _path(raw, str(field_map[field]))
    for key in DEFAULT_FIELD_MAP.get(field, ()):
        if raw.get(key) not in (None, ""):
            return raw[key]
    return None


def _money(value: Any) -> Optional[float]:
    if value in (None, "") or isinstance(value, bool):
        return None
    if isinstance(value, dict):
        value = value.get("amount", value.get("value"))
    try:
        number = float(re.sub(r"[^0-9.]", "", str(value)) or "x")
    except ValueError:
        return None
    return number if number > 0 else None


def _stock(value: Any) -> str:
    text = str(value).strip().lower()
    if value is True or text in ("in stock", "instock", "in_stock", "available", "true", "yes", "1"):
        return "IN_STOCK"
    if value is False or text in ("out of stock", "outofstock", "out_of_stock", "sold out", "false", "no", "0"):
        return "OUT_OF_STOCK"
    return "UNKNOWN"


def _https(url: Any) -> Optional[str]:
    text = str(url or "").strip()
    return text if text.startswith("https://") else None


def link_for(source: Dict[str, Any], url: str) -> tuple[str, bool]:
    """(destination, affiliate?) -- an approved affiliate deep-link only when
    the source is affiliate-monetized, its commission is ACTIVE and a link
    template exists; otherwise the useful organic link."""
    template = str(source.get("affiliate_link_template") or "")
    if (source.get("monetization") == "affiliate" and str(source.get("commission_status") or "").upper() == "ACTIVE"
            and "{url}" in template and url):
        return template.replace("{url}", urllib.parse.quote(url, safe="")), True
    return url, False


def normalize(source: Dict[str, Any], raw: Dict[str, Any], index: int) -> Optional[Dict[str, Any]]:
    """One source item -> an ASKODOX result card (same fields as catalog rows)."""
    field_map = source.get("field_map") if isinstance(source.get("field_map"), dict) else {}
    title = str(_pick(raw, "title", field_map) or "").strip()
    url = _https(_pick(raw, "url", field_map))
    if not title or not url:
        return None  # a card without a name or a safe link is not useful
    price, mrp = _money(_pick(raw, "price", field_map)), _money(_pick(raw, "original_price", field_map))
    if price is not None and mrp is not None and mrp < price:
        mrp = None
    destination, affiliate = link_for(source, url)
    stock = _stock(_pick(raw, "stock", field_map)) if _pick(raw, "stock", field_map) is not None else "UNKNOWN"
    sid = str(source.get("id") or "")
    rating = _money(_pick(raw, "rating", field_map))
    return {
        "id": f"source-{sid}-{index}", "match_id": f"source-{sid}-{index}", "provider_id": f"source:{sid}",
        "title": title[:200], "subtitle": str(_pick(raw, "seller", field_map) or source.get("name") or "")[:120],
        "price": price, "original_price": mrp,
        "discount_percent": round((mrp - price) / mrp * 100) if price and mrp and mrp > price else None,
        "currency": "INR", "price_verified": False, "price_source": "source" if price is not None else None,
        "image_url": _https(_pick(raw, "image", field_map)), "images": [],
        "match_source": "online", "source": "online", "origin": "universal_source", "source_id": sid,
        "source_name": source.get("name"), "source_logo": _https(source.get("logo_url")),
        "destination_url": destination, "web_fallback_url": url, "open_strategy": "web",
        "affiliate": affiliate, "routing": "affiliate" if affiliate else "organic",
        "disclosure": "Affiliate link" if affiliate else "", "sponsored": source.get("monetization") == "sponsored",
        "stock_status": stock, "brand": _pick(raw, "brand", field_map) or None,
        "location": _pick(raw, "location", field_map) or None, "offer": _pick(raw, "offer", field_map) or None,
        "rating": rating if rating and rating <= 5 else None,
        "review_count": int(_money(_pick(raw, "review_count", field_map)) or 0) or None,
        "demo": False,
    }


# ------------------------------------------------------------ fetching --

def safe_fetch(url: str, *, timeout: float, max_bytes: int = MAX_FEED_BYTES) -> tuple[int, str, str]:
    """GET a public https URL (private / local hosts refused, redirects
    re-checked, size bounded) -> (status, content type, text)."""
    import urllib.request
    from urllib.parse import urlparse

    from app.services.universal_external_result_service import PartnerApiConnector

    public = PartnerApiConnector._safe_public_host

    class Guard(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            target = urlparse(newurl)
            if target.scheme != "https" or not public(target.hostname or "", {}):
                raise ValueError("redirected to a non-public address")
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    parsed = urlparse(url)
    if parsed.scheme != "https" or not public(parsed.hostname or "", {}):
        raise ValueError("only public https URLs are allowed")
    request = urllib.request.Request(url, headers={"User-Agent": "ASKODOX-sources/1.0",
                                                   "Accept": "application/json, text/csv, */*"})
    with urllib.request.build_opener(Guard()).open(request, timeout=timeout) as response:
        return (response.status, str(response.headers.get("content-type") or ""),
                response.read(max_bytes).decode("utf-8", errors="replace"))


def parse_items(text: str, fmt: str, items_path: str = "") -> List[Dict[str, Any]]:
    if fmt == "csv":
        return [dict(r) for r in csv.DictReader(io.StringIO(text))][:MAX_FEED_ITEMS]
    data = json.loads(text or "null")
    data = _path(data, items_path) if items_path else data
    if isinstance(data, dict):
        data = next((v for v in data.values() if isinstance(v, list)), [])
    return [d for d in (data or []) if isinstance(d, dict)][:MAX_FEED_ITEMS]


# -------------------------------------------------------------- engine --

class UniversalSources:
    def __init__(self, pf: Any, catalog: Any = None, *, fetch: Callable[..., tuple[int, str, str]] | None = None,
                 settings: Callable[[str], float] | None = None) -> None:
        self.pf = pf
        self.catalog = catalog
        self.fetch = fetch or safe_fetch
        self.health = SourceHealth(pf.repo.db_path)
        if settings is None:
            from app.services import platform_settings

            settings = lambda key: platform_settings.get(key)  # noqa: E731
        self.setting = settings

    def records(self, *, active_only: bool = True) -> List[Dict[str, Any]]:
        out = []
        for record in self.pf.repo.list("sources"):
            if record.get("archived") or (active_only and record.get("status") != "ACTIVE"):
                continue
            out.append({**(record.get("data") or {}), "id": record["id"], "status": record.get("status")})
        out.sort(key=lambda s: (-int(s.get("priority") or 0), str(s.get("name") or "")))
        return out

    def site_hosts(self, demand: Dict[str, Any]) -> Dict[str, tuple[str, str]]:
        """``site_search`` sources for the marketplace web-search step."""
        sites = {}
        for source in self.records():
            if source.get("connector") != "site_search" or applies(source, demand):
                continue
            domain = (_list(source.get("domains")) or [""])[0].lower().removeprefix("www.")
            if domain:
                sites[f"src-{source['id']}"] = (domain, str(source.get("name") or domain))
        return sites

    # live search ------------------------------------------------------
    def _json_search(self, source: Dict[str, Any], demand: Dict[str, Any]) -> List[Dict[str, Any]]:
        template = str(source.get("search_url_template") or "")
        values = {"q": demand.get("subject") or "", "city": demand.get("location_text") or "",
                  "category": demand.get("category") or demand.get("domain") or ""}
        url = template
        for key, value in values.items():
            url = url.replace("{" + key + "}", urllib.parse.quote(str(value)))
        from app.services import external_call_budget

        def call():
            status, _, text = self.fetch(url, timeout=float(self.setting("sources.timeout_seconds")),
                                         max_bytes=1_000_000)
            if status != 200:
                raise ValueError(f"HTTP {status}")
            return parse_items(text, "json", str((source.get("field_map") or {}).get("items") or ""))

        items = external_call_budget.cached_call("source_search", (source["id"], url), call, ttl=600)
        rows = [normalize(source, raw, i) for i, raw in enumerate(items or [])]
        return [r for r in rows if r][: int(source.get("max_results") or 4)]

    def search_rows(self, demand: Dict[str, Any]) -> tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """Live ``json_search`` sources for this need, in priority order. A
        source that fails or times out is recorded and skipped."""
        info: Dict[str, Any] = {"searched": [], "skipped": {}, "failed": {}}
        live = []
        for source in self.records():
            reason = applies(source, demand)
            if source.get("connector") != "json_search":
                continue
            if reason:
                info["skipped"][source["id"]] = reason
                continue
            live.append(source)
        live = live[:MAX_LIVE_SOURCES]
        if not live or not str(demand.get("subject") or "").strip():
            return [], info
        timeout = float(self.setting("sources.timeout_seconds")) + 1
        pool = ThreadPoolExecutor(max_workers=min(4, len(live)))
        futures = {pool.submit(self._json_search, s, demand): s for s in live}
        done, pending = wait(futures, timeout=timeout)
        pool.shutdown(wait=False, cancel_futures=True)
        rows: List[Dict[str, Any]] = []
        for future, source in futures.items():
            info["searched"].append(source["id"])
            if future in pending:
                info["failed"][source["id"]] = "timeout"
                self.health.record(source["id"], ok=False, error="timeout")
                continue
            try:
                found = future.result()
            except Exception as error:  # isolated: never breaks the result
                info["failed"][source["id"]] = type(error).__name__
                self.health.record(source["id"], ok=False, error=f"{type(error).__name__}: {error}"[:200])
                continue
            self.health.record(source["id"], ok=True, results=len(found))
            rows.extend(found)
        return rows, info

    # feeds --------------------------------------------------------------
    def due(self, source: Dict[str, Any]) -> bool:
        last = (self.health.all().get(source["id"]) or {}).get("last_sync_at")
        hours = float(self.setting("sources.feed_refresh_hours"))
        return not last or datetime.fromisoformat(last) <= datetime.now(timezone.utc) - timedelta(hours=hours)

    def sync_due_feeds(self, *, actor: str, limit: int = 3) -> Dict[str, Any]:
        """Scheduled (background runner) -- never on a user's search."""
        done: Dict[str, Any] = {}
        for source in self.records():
            if len(done) >= limit:
                break
            if source.get("connector") != "feed" or not source.get("feed_url") or not self.due(source):
                continue
            try:
                done[source["id"]] = self.sync_feed(source, actor=actor)
            except Exception as error:  # recorded in source_health; the next feed still runs
                done[source["id"]] = {"error": type(error).__name__}
        return done

    def sync_feed(self, source: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
        """Approved feed -> item store (create new, update price / stock of
        known items). Items need review unless the source auto-publishes."""
        if self.catalog is None:
            raise RuntimeError("item store not available")
        try:
            status, _, text = self.fetch(str(source.get("feed_url") or ""), timeout=15.0)
            if status != 200:
                raise ValueError(f"HTTP {status}")
            items = parse_items(text, str(source.get("feed_format") or "json"),
                                str((source.get("field_map") or {}).get("items") or ""))
        except Exception as error:
            self.health.record(source["id"], ok=False, error=f"{type(error).__name__}: {error}"[:200], synced=True)
            raise
        created = updated = skipped = 0
        review = "LIVE" if source.get("auto_publish") else "NEEDS_REVIEW"
        for index, raw in enumerate(items):
            row = normalize(source, raw, index)
            if row is None:
                skipped += 1
                continue
            existing = self.catalog.duplicates(row["web_fallback_url"])
            fields = {"title": row["title"], "original_product_url": row["web_fallback_url"],
                      "price": row["price"], "mrp": row["original_price"], "image_url": row["image_url"],
                      "brand": row["brand"], "seller": row["subtitle"], "offer_text": row["offer"],
                      "rating": row["rating"], "review_count": row["review_count"],
                      "location": row["location"], "source_ref": source["id"],
                      "category": str(_pick(raw, "category", source.get("field_map") or {}) or "")}
            if row["affiliate"]:
                fields["affiliate_url"] = row["destination_url"]
            fields = {k: v for k, v in fields.items() if v not in (None, "")}
            try:
                if existing:
                    pid = existing[0]["id"]
                    change = {k: fields[k] for k in ("price", "mrp") if k in fields}
                    if change:
                        self.catalog.update(pid, change, actor=actor, action="feed", check_source="feed")
                    if row["stock_status"] != "UNKNOWN":
                        self.catalog.set_stock(pid, row["stock_status"], actor=actor, check_source="feed")
                    updated += 1
                else:
                    self.catalog.create(fields, actor=actor, check_source="feed", stock_status=row["stock_status"],
                                        commission_status="ACTIVE" if row["affiliate"] else None,
                                        review_status=review)
                    created += 1
            except (ValueError, LookupError):
                skipped += 1
        self.health.record(source["id"], ok=True, results=created + updated, synced=True)
        return {"created": created, "updated": updated, "skipped": skipped, "review_status": review}

    def overview(self) -> List[Dict[str, Any]]:
        health = self.health.all()
        out = []
        for source in self.records(active_only=False):
            h = health.get(source["id"]) or {}
            out.append({"id": source["id"], "name": source.get("name"), "status": source.get("status"),
                        "source_type": source.get("source_type"), "connector": source.get("connector"),
                        "priority": source.get("priority"), "monetization": source.get("monetization"),
                        "domains": _list(source.get("domains")), "sectors": _list(source.get("sectors")),
                        "health": {"status": h.get("last_status") or "not_checked",
                                   "last_success_at": h.get("last_success_at"), "last_error": h.get("last_error"),
                                   "failures_in_row": h.get("failures_in_row", 0),
                                   "last_sync_at": h.get("last_sync_at"), "rows_shown": h.get("rows_shown", 0)}})
        return out


def detect_source(records: List[Dict[str, Any]], url: str) -> Optional[Dict[str, Any]]:
    """The configured source whose domain the URL belongs to (longest match)."""
    from urllib.parse import urlparse

    host = (urlparse(str(url or "")).hostname or "").lower().removeprefix("www.")
    best = None
    for source in records:
        for domain in _list(source.get("domains")):
            d = domain.lower().removeprefix("www.")
            if d and (host == d or host.endswith("." + d)) and (best is None or len(d) > best[0]):
                best = (len(d), source)
    return best[1] if best else None
