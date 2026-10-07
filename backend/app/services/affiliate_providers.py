"""Affiliate / marketplace provider adapters for the Affiliate Product Hub.

ONE extraction pipeline for every provider (``affiliate_catalog.parse_metadata``
reads Open Graph + schema.org); an adapter only adds what its provider
legitimately publishes on its own public product page (embedded page data,
short / affiliate link shapes). Meesho is the first adapter; Amazon /
Flipkart / Wishlink plug into the same registry -- never a separate system
per provider.

Truth rules (never relaxed by an adapter):
* a value is kept only when the page or the URL states it; nothing is
  guessed (price, MRP, discount, stock, seller, rating, commission, delivery);
* a discount is derived only from a page-stated price AND MRP and is labelled
  ``derived``;
* commission is never extracted -- it stays UNKNOWN until staff verify it;
* every kept value carries provenance: where it came from and when.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

_AFFILIATE_PARAMS = re.compile(r"(?:^|&)(tag|affid|affExtParam1|affExtParam2|aff_id|aff|affiliate|ref_id|pid_aff|wl)=",
                               re.IGNORECASE)


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _host(url: str) -> str:
    try:
        return (urlparse(str(url or "")).hostname or "").lower().removeprefix("www.")
    except ValueError:
        return ""


def _money(value: Any) -> float | None:
    if value in (None, "", [], {}):
        return None
    if isinstance(value, (int, float)):
        return float(value) if value > 0 else None
    text = re.sub(r"[^\d.]", "", str(value).replace(",", ""))
    try:
        number = float(text)
    except ValueError:
        return None
    return number if number > 0 else None


@dataclass(frozen=True)
class ProviderAdapter:
    """What is specific to one provider. Everything else is shared."""

    id: str
    name: str
    product_hosts: tuple[str, ...]
    short_link_hosts: tuple[str, ...] = ()

    def owns(self, url: str) -> bool:
        host = _host(url)
        return any(host == h or host.endswith("." + h) for h in self.product_hosts + self.short_link_hosts)

    def link_kind(self, url: str) -> str:
        """``affiliate`` for a provider short / tracked link, ``product`` for a
        plain product page, ``unknown`` otherwise. Shape only -- whether the
        link earns commission is never claimed here."""
        host = _host(url)
        if any(host == h or host.endswith("." + h) for h in self.short_link_hosts):
            return "affiliate"
        query = urlparse(url).query or ""
        if _AFFILIATE_PARAMS.search(query):
            return "affiliate"
        return "product" if self.owns(url) else "unknown"

    def embedded(self, html: str) -> dict[str, Any]:
        """Provider page data beyond Open Graph / schema.org (override)."""
        return {}


class _ScriptCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.scripts: dict[str, str] = {}
        self._capture: str | None = None
        self._buffer: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            a = dict(attrs)
            if a.get("id") == "__NEXT_DATA__" or a.get("type") == "application/json":
                self._capture = a.get("id") or "json"
                self._buffer = []

    def handle_endtag(self, tag):
        if tag == "script" and self._capture:
            self.scripts.setdefault(self._capture, "".join(self._buffer))
            self._capture = None

    def handle_data(self, data):
        if self._capture:
            self._buffer.append(data)


def _walk(node: Any, depth: int = 0):
    if depth > 14:
        return
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value, depth + 1)
    elif isinstance(node, list):
        for value in node[:200]:
            yield from _walk(value, depth + 1)


def _first(d: dict, *keys: str) -> Any:
    for key in keys:
        value = d.get(key)
        if value not in (None, "", [], {}):
            return value
    return None


class MeeshoAdapter(ProviderAdapter):
    """Meesho product pages are Next.js pages: the public product data the
    page renders is embedded in ``__NEXT_DATA__``. Only keys that hold the
    product's own facts are read; nothing is inferred."""

    def embedded(self, html: str) -> dict[str, Any]:
        collector = _ScriptCollector()
        try:
            collector.feed(html[:2_000_000])
        except Exception:
            return {}
        raw = collector.scripts.get("__NEXT_DATA__")
        if not raw:
            return {}
        try:
            data = json.loads(raw)
        except ValueError:
            return {}
        best: dict[str, Any] | None = None
        for node in _walk(data):
            name = _first(node, "name", "product_name", "catalog_name", "title")
            price = _first(node, "min_product_price", "price", "selling_price", "final_price", "discounted_price")
            if isinstance(name, str) and name.strip() and _money(price) is not None and (
                    "images" in node or "image" in node or "product_images" in node):
                best = node
                break
        if best is None:
            return {}
        out: dict[str, Any] = {}
        out["title"] = str(_first(best, "name", "product_name", "catalog_name", "title")).strip()[:300]
        price = _money(_first(best, "min_product_price", "price", "selling_price", "final_price",
                              "discounted_price"))
        if price is not None:
            out["price"] = price
        mrp = _money(_first(best, "original_price", "mrp", "mrp_price", "max_retail_price", "strike_price"))
        if mrp is not None:
            out["mrp"] = mrp
        images = _first(best, "images", "product_images", "image")
        imgs: list[str] = []
        for item in images if isinstance(images, list) else [images]:
            url = item.get("url") if isinstance(item, dict) else item
            if isinstance(url, str) and url.startswith("https://"):
                imgs.append(url)
        if imgs:
            out["images"] = list(dict.fromkeys(imgs))[:8]
        supplier = _first(best, "supplier_name", "shop_name", "seller_name")
        if not supplier:
            sup = best.get("supplier") or best.get("shop") or {}
            supplier = _first(sup, "name", "supplier_name", "shop_name") if isinstance(sup, dict) else None
        if isinstance(supplier, str) and supplier.strip():
            out["seller"] = supplier.strip()[:200]
        category = _first(best, "category_name", "sub_sub_category_name", "sub_category_name", "category")
        if isinstance(category, str) and category.strip():
            out["category"] = category.strip()[:160]
        description = _first(best, "description", "full_details", "product_details")
        if isinstance(description, str) and description.strip():
            out["description"] = description.strip()[:4000]
        variants: list[str] = []
        for key in ("variations", "sizes", "variants", "available_sizes"):
            values = best.get(key)
            if isinstance(values, list):
                for v in values[:40]:
                    label = v.get("name") or v.get("size") or v.get("label") if isinstance(v, dict) else v
                    if isinstance(label, (str, int, float)) and str(label).strip():
                        variants.append(str(label).strip()[:60])
        if variants:
            out["variants"] = list(dict.fromkeys(variants))[:40]
        return out


ADAPTERS: dict[str, ProviderAdapter] = {
    "meesho": MeeshoAdapter("meesho", "Meesho", ("meesho.com",), ("msho.in",)),
    "amazon": ProviderAdapter("amazon", "Amazon", ("amazon.in",), ("amzn.to", "amzn.in", "amzn.eu")),
    "flipkart": ProviderAdapter("flipkart", "Flipkart", ("flipkart.com",), ("fkrt.it", "fkrt.cc", "fkrt.co")),
    "wishlink": ProviderAdapter("wishlink", "Wishlink", (), ("wishlink.com", "wishlink.in")),
}


def adapter_for(url: str) -> ProviderAdapter | None:
    for adapter in ADAPTERS.values():
        if adapter.owns(url):
            return adapter
    return None


# ----------------------------------------------------- generic page facts --

class _MetaCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.meta: dict[str, list[str]] = {}
        self.ld: list[str] = []
        self._in_ld = False
        self._buffer: list[str] = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            key = (a.get("property") or a.get("name") or a.get("itemprop") or "").strip().lower()
            if key and a.get("content"):
                self.meta.setdefault(key, []).append(a["content"].strip())
        elif tag == "script" and (a.get("type") or "").lower() == "application/ld+json":
            self._in_ld, self._buffer = True, []

    def handle_endtag(self, tag):
        if tag == "script" and self._in_ld:
            self.ld.append("".join(self._buffer))
            self._in_ld = False

    def handle_data(self, data):
        if self._in_ld:
            self._buffer.append(data)


def page_facts(html: str) -> dict[str, Any]:
    """MRP, variants, keywords and app deep links a page states about itself
    (Open Graph product tags, schema.org offers, App Links meta)."""
    collector = _MetaCollector()
    try:
        collector.feed(html[:1_500_000])
    except Exception:
        return {}
    meta = collector.meta
    out: dict[str, Any] = {}
    mrp = _money((meta.get("product:original_price:amount") or meta.get("og:price:standard_amount") or [None])[0])
    variants: list[str] = []
    for blob in collector.ld:
        try:
            data = json.loads(blob)
        except ValueError:
            continue
        for node in _walk(data):
            types = node.get("@type")
            types = types if isinstance(types, list) else [types]
            if "Product" in types or "ProductGroup" in types:
                for variant in node.get("hasVariant") or []:
                    if isinstance(variant, dict):
                        label = " ".join(str(variant.get(k)) for k in ("size", "color", "name") if variant.get(k))
                        if label.strip():
                            variants.append(label.strip()[:60])
            spec = node.get("priceSpecification")
            for item in spec if isinstance(spec, list) else [spec]:
                if isinstance(item, dict) and re.search(r"ListPrice|Strikethrough|MSRP|SRP",
                                                        str(item.get("priceType") or ""), re.IGNORECASE):
                    mrp = mrp or _money(item.get("price"))
    if mrp is not None:
        out["mrp"] = mrp
    if variants:
        out["variants"] = list(dict.fromkeys(variants))[:40]
    keywords = (meta.get("keywords") or meta.get("news_keywords") or [""])[0]
    words = [w.strip() for w in keywords.split(",") if w.strip()]
    if words:
        out["keywords"] = words[:20]
    deep = (meta.get("al:android:url") or meta.get("al:ios:url") or [""])[0]
    if deep and "://" in deep:
        out["deep_link"] = deep[:500]
    return out


# ------------------------------------------------------------- enrich -----

PROVENANCE_FIELDS = ("title", "images", "price", "mrp", "discount_percent", "seller", "category", "description",
                     "variants", "keywords", "brand", "product_id", "canonical_url", "availability",
                     "affiliate_url", "original_product_url", "deep_link")


def enrich(result: dict[str, Any], html: str | None, url: str) -> dict[str, Any]:
    """Add provider facts, link classification and per-field provenance to an
    ``affiliate_catalog.extract_metadata`` result (in place, also returned)."""
    fields: dict[str, Any] = result.setdefault("fields", {})
    checked = _now()
    provenance: dict[str, dict[str, Any]] = {}
    base_method = "page_metadata" if result.get("status") == "ok" else "url"
    for key in PROVENANCE_FIELDS:
        if fields.get(key) not in (None, "", []):
            provenance[key] = {"source": base_method if key not in {"original_product_url", "product_id",
                                                                    "canonical_url"} else "url",
                               "verified": False, "checked_at": checked}
    adapter = adapter_for(url)
    if html:
        if adapter is not None:
            for key, value in adapter.embedded(html).items():
                # Page-embedded data fills gaps; it never overrides schema.org.
                # Exception: the page <title> ("Name | Meesho") yields to the
                # product's own name when it is exactly that name + a suffix.
                current = fields.get(key)
                if key == "title" and isinstance(current, str) and isinstance(value, str) \
                        and current != value and current.startswith(value):
                    current = None
                if current in (None, "", []):
                    fields[key] = value
                    provenance[key] = {"source": "page_embedded_data", "verified": False, "checked_at": checked}
        for key, value in page_facts(html).items():
            if fields.get(key) in (None, "", []):
                fields[key] = value
                provenance[key] = {"source": "page_metadata", "verified": False, "checked_at": checked}
    if fields.get("images") and not fields.get("image_url"):
        fields["image_url"] = fields["images"][0]
    price, mrp = fields.get("price"), fields.get("mrp")
    if isinstance(price, (int, float)) and isinstance(mrp, (int, float)) and mrp > price > 0:
        fields["discount_percent"] = round((mrp - price) / mrp * 100)
        provenance["discount_percent"] = {"source": "derived", "from": ["price", "mrp"], "verified": False,
                                          "checked_at": checked}
    elif isinstance(price, (int, float)) and isinstance(mrp, (int, float)) and mrp < price:
        # A page "MRP" below the selling price is not an MRP: dropped, never shown.
        fields.pop("mrp", None)
        provenance.pop("mrp", None)
    kind = adapter.link_kind(url) if adapter else "unknown"
    if kind == "affiliate":
        # The pasted link is the provider's tracked / short link: it becomes
        # the affiliate link; the product's normal URL is the page's own
        # canonical address when the page stated one.
        fields["affiliate_url"] = url
        provenance["affiliate_url"] = {"source": "pasted_link", "verified": False, "checked_at": checked}
        canonical = fields.get("canonical_url")
        if canonical and _host(canonical) != _host(url):
            fields["original_product_url"] = canonical
            provenance["original_product_url"] = {"source": "page_metadata", "verified": False,
                                                  "checked_at": checked}
    result["provider"] = adapter.id if adapter else "other"
    result["provider_name"] = adapter.name if adapter else (_host(url) or "Other")
    result["link_kind"] = kind
    result["provenance"] = provenance
    result["checked_at"] = checked
    # Commission is never read from a page.
    result["commission"] = {"status": "UNKNOWN", "label": "Needs verification", "source": None}
    missing = [k for k in ("title", "price", "images", "seller", "category") if fields.get(k) in (None, "", [])]
    result["missing"] = missing
    return result


def extract(url: str, fetch: Callable[[str], str] | None = None) -> dict[str, Any]:
    """``affiliate_catalog.extract_metadata`` + provider enrichment. The page is
    fetched ONCE and the same HTML feeds both."""
    from app.services import affiliate_catalog as ac

    fetched: dict[str, str] = {}

    def once(target: str) -> str:
        if target not in fetched:
            fetched[target] = (fetch or ac.fetch_page)(target)
        return fetched[target]

    result = ac.extract_metadata(url, fetch=once)
    return enrich(result, fetched.get(ac.https_url(url)), ac.https_url(url))
