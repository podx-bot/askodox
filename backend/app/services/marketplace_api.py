"""Marketplace product APIs for the Affiliate Product Manager.

ONE adapter per marketplace, driven by the existing Integration registry
(``commerce_finance.PROVIDERS``): credentials are stored there (encrypted,
write-only), the mode decides what happens:

  mock  -> a fixed sample answer marked ``mock: true``; NEVER written to the
           catalog and never shown to customers (it proves the wiring only)
  test / live -> the real API call (Amazon Product Advertising API 5 GetItems,
           Flipkart Affiliate product API). Results update price / MRP /
           stock with ``check_source = "api"`` and the change history.

Nothing is "LIVE" until the registry says so (real credentials AND a
passed Check). Meesho publishes no product API: its rows change only by
staff edits or a feed import (``status`` says so). Credentials and API
approval (Amazon Associates PA-API access needs qualifying sales; Flipkart
affiliate API access is granted per affiliate id) are EXTERNAL SETUP.
"""
from __future__ import annotations

import hashlib
import hmac
import json
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Optional, Tuple

from app.services import commerce_finance as fin

PLATFORM_PROVIDER = {"amazon": "amazon_associates", "flipkart": "flipkart_affiliate", "meesho": None}
NO_API = {"meesho": "Meesho publishes no product API -- stock / price change by staff edits or a feed import."}
EXTERNAL = ("EXTERNAL SETUP REQUIRED: {label} credentials (and the marketplace's API approval) in Command Center "
            "-> Integrations -> {label}, then Check.")

AMAZON_HOST = "webservices.amazon.in"
AMAZON_REGION = "eu-west-1"  # the PA-API 5 region for amazon.in
AMAZON_TARGET = "com.amazon.paapi5.v1.ProductAdvertisingAPIv1.GetItems"
FLIPKART_PRODUCT = "https://affiliate-api.flipkart.net/affiliate/1.0/product.json"

Http = Callable[..., Tuple[int, Any]]


def status(registry: fin.IntegrationRegistry, platform: str) -> Dict[str, Any]:
    """One answer per marketplace: LIVE / CONFIGURED_NOT_VERIFIED / MOCK /
    EXTERNAL_SETUP_REQUIRED / NOT_AVAILABLE (+ why). Never a hand-set flag."""
    provider = PLATFORM_PROVIDER.get(platform)
    if provider is None:
        return {"platform": platform, "provider": None, "status": "NOT_AVAILABLE",
                "reason": NO_API.get(platform, "no product API for this source")}
    s = registry.status(provider)
    if s["status"] == fin.STATUS_LIVE:
        state, reason = "LIVE", "real credentials and a passed check"
    elif s["status"] == fin.STATUS_MOCK:
        state, reason = "MOCK", "mock mode: sample answers only, nothing is written to the catalog"
    elif s["status"] == fin.STATUS_TEST:
        state, reason = "CONFIGURED_NOT_VERIFIED", "credentials present; run Check in Integrations"
    elif s["status"] == fin.STATUS_ERROR:
        state, reason = "CHECK_FAILED", s.get("last_check_detail") or "the last check failed"
    else:
        state, reason = "EXTERNAL_SETUP_REQUIRED", EXTERNAL.format(label=s["label"])
    return {"platform": platform, "provider": provider, "status": state, "reason": reason,
            "missing": s["missing"], "mode": s["mode"], "last_check_at": s.get("last_check_at")}


# ------------------------------------------------------------- Amazon --

def _sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def sigv4_headers(*, access_key: str, secret_key: str, body: bytes, now: datetime,
                  host: str = AMAZON_HOST, region: str = AMAZON_REGION, path: str = "/paapi5/getitems",
                  target: str = AMAZON_TARGET, service: str = "ProductAdvertisingAPI") -> Dict[str, str]:
    """AWS Signature Version 4 for one PA-API 5 POST (standard library only)."""
    amz_date, day = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    headers = {"content-encoding": "amz-1.0", "content-type": "application/json; charset=utf-8",
               "host": host, "x-amz-date": amz_date, "x-amz-target": target}
    signed = ";".join(sorted(headers))
    canonical = "\n".join(["POST", path, "", "".join(f"{k}:{headers[k]}\n" for k in sorted(headers)), signed,
                           hashlib.sha256(body).hexdigest()])
    scope = f"{day}/{region}/{service}/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = _sign(_sign(_sign(_sign(("AWS4" + secret_key).encode(), day), region), service), "aws4_request")
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    headers["Authorization"] = (f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, SignedHeaders={signed}, "
                                f"Signature={signature}")
    return headers


def _amount(node: Any) -> Optional[float]:
    try:
        node = node or {}
        return float(node.get("Amount", node.get("amount")))  # PA-API "Amount", Flipkart "amount"
    except (TypeError, ValueError):
        return None


def amazon_get_item(registry: fin.IntegrationRegistry, http: Http, asin: str, *,
                    now: datetime | None = None) -> Dict[str, Any]:
    p = "amazon_associates"
    body = json.dumps({
        "ItemIds": [asin], "PartnerTag": registry.config_value(p, "partner_tag"), "PartnerType": "Associates",
        "Marketplace": "www.amazon.in",
        "Resources": ["ItemInfo.Title", "Offers.Listings.Price", "Offers.Listings.SavingBasis",
                      "Offers.Listings.Availability.Type", "Images.Primary.Large"],
    }, separators=(",", ":")).encode()
    headers = sigv4_headers(access_key=registry.config_value(p, "access_key"),
                            secret_key=registry.secret(p, "secret_key"), body=body,
                            now=now or datetime.now(timezone.utc))
    code, data = http("POST", f"https://{AMAZON_HOST}/paapi5/getitems", headers=headers, content=body)
    items = (((data or {}).get("ItemsResult") or {}).get("Items") or []) if isinstance(data, dict) else []
    if code != 200 or not items:
        errors = (data or {}).get("Errors") if isinstance(data, dict) else None
        detail = (errors[0].get("Code") if errors else "") or f"HTTP {code}"
        return {"ok": False, "error": str(detail)[:120]}
    item = items[0]
    listing = (((item.get("Offers") or {}).get("Listings")) or [{}])[0]
    availability = str(((listing.get("Availability") or {}).get("Type")) or "")
    return {"ok": True, "fields": {
        "title": (((item.get("ItemInfo") or {}).get("Title") or {}).get("DisplayValue")),
        "price": _amount(listing.get("Price")), "mrp": _amount(listing.get("SavingBasis")),
        "stock": "IN_STOCK" if availability == "Now" else ("OUT_OF_STOCK" if availability else "UNKNOWN"),
        "availability": availability, "canonical_url": item.get("DetailPageURL"),
        "image_url": ((((item.get("Images") or {}).get("Primary") or {}).get("Large")) or {}).get("URL"),
    }}


# ----------------------------------------------------------- Flipkart --

def flipkart_get_item(registry: fin.IntegrationRegistry, http: Http, pid: str) -> Dict[str, Any]:
    p = "flipkart_affiliate"
    code, data = http("GET", FLIPKART_PRODUCT, params={"id": pid},
                      headers={"Fk-Affiliate-Id": registry.config_value(p, "affiliate_id"),
                               "Fk-Affiliate-Token": registry.secret(p, "token")})
    info = ((data or {}).get("productBaseInfoV1") if isinstance(data, dict) else None) or {}
    if code != 200 or not info:
        return {"ok": False, "error": f"HTTP {code}"}
    images = info.get("imageUrls") or {}
    in_stock = info.get("inStock")
    return {"ok": True, "fields": {
        "title": info.get("title"),
        "price": _amount(info.get("flipkartSpecialPrice")) or _amount(info.get("flipkartSellingPrice")),
        "mrp": _amount(info.get("maximumRetailPrice")),
        "stock": "IN_STOCK" if in_stock is True else ("OUT_OF_STOCK" if in_stock is False else "UNKNOWN"),
        "availability": "in stock" if in_stock else ("out of stock" if in_stock is False else ""),
        "canonical_url": info.get("productUrl"),
        "image_url": images.get("400x400") or next(iter(images.values()), None) if images else None,
    }}


# -------------------------------------------------------------- shared --

def mock_item(platform: str, product_id: str) -> Dict[str, Any]:
    return {"ok": True, "mock": True, "fields": {
        "title": f"MOCK {platform} item {product_id} (not a real product)", "price": 999.0, "mrp": 1299.0,
        "stock": "IN_STOCK", "availability": "mock", "canonical_url": None, "image_url": None}}


def lookup(registry: fin.IntegrationRegistry, http: Http, platform: str, product_id: str) -> Dict[str, Any]:
    state = status(registry, platform)
    base = {"platform": platform, "product_id": product_id, "status": state["status"], "reason": state["reason"]}
    if not product_id:
        return base | {"ok": False, "error": "this product has no marketplace product id (ASIN / Flipkart pid)"}
    if state["status"] == "MOCK":
        return base | mock_item(platform, product_id)
    if state["status"] not in ("LIVE", "CONFIGURED_NOT_VERIFIED"):
        return base | {"ok": False, "error": state["reason"]}
    try:
        if platform == "amazon":
            return base | amazon_get_item(registry, http, product_id)
        return base | flipkart_get_item(registry, http, product_id)
    except Exception as error:  # a marketplace outage is a failed lookup, never a 500
        return base | {"ok": False, "error": type(error).__name__}


def refresh(catalog: Any, registry: fin.IntegrationRegistry, http: Http, product_id: int, *,
            actor: str) -> Dict[str, Any]:
    """Refresh one catalog row from its marketplace API. Mock answers are
    returned as a preview only (``applied: false``)."""
    row = catalog.get(product_id)
    if not row:
        raise LookupError("Product not found")
    platform = str(row.get("platform") or "")
    result = lookup(registry, http, platform, str(row.get("product_id") or ""))
    if not result.get("ok") or result.get("mock"):
        if platform in PLATFORM_PROVIDER and result.get("status") in ("LIVE", "CONFIGURED_NOT_VERIFIED"):
            catalog.record_health(platform, status="api_error", results=0, method="api")
        return result | {"applied": False}
    fields = result["fields"]
    changes = {k: fields[k] for k in ("price", "mrp", "canonical_url") if fields.get(k) not in (None, "")}
    if changes.get("price") is not None and changes.get("mrp") is not None and changes["mrp"] < changes["price"]:
        changes.pop("mrp")
    if changes:
        catalog.update(product_id, changes, actor=actor, action="api_refresh", check_source="api")
    if fields.get("stock") in ("IN_STOCK", "OUT_OF_STOCK"):
        catalog.set_stock(product_id, fields["stock"], actor=actor, check_source="api")
    catalog.record_health(platform, status="ok", results=1, method="api")
    return result | {"applied": True, "product": catalog.get(product_id)}


# Read-only live checks for the Integrations "Check" button.

def probe_amazon(registry: fin.IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    asin = registry.config_value("amazon_associates", "probe_asin") or "B0CHX1W1XY"
    result = amazon_get_item(registry, http, asin)
    if result["ok"]:
        return True, "PA-API 5 GetItems answered"
    # A signed request for an unknown item still proves the credentials work.
    if result["error"] in ("ItemNotAccessible", "InvalidParameterValue"):
        return True, f"PA-API 5 credentials accepted ({result['error']} for the probe item)"
    return False, f"PA-API 5: {result['error']}"


def probe_flipkart(registry: fin.IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    affiliate = registry.config_value("flipkart_affiliate", "affiliate_id")
    code, _ = http("GET", f"https://affiliate-api.flipkart.net/affiliate/api/{affiliate}.json",
                   headers={"Fk-Affiliate-Id": affiliate,
                            "Fk-Affiliate-Token": registry.secret("flipkart_affiliate", "token")})
    return (True, "Flipkart affiliate API directory answered") if code == 200 else (False, f"HTTP {code}")
