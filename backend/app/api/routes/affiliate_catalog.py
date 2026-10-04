"""Affiliate Product Manager + Affiliate Sources (Command Center).

  GET    /admin/cc/affiliate-products                    list + eligibility summary   (affiliate_products:view)
  GET    /admin/cc/affiliate-products/{id}               one product + change history (affiliate_products:view)
  POST   /admin/cc/affiliate-products                    add a product                (affiliate_products:create)
  PATCH  /admin/cc/affiliate-products/{id}               edit fields                  (affiliate_products:edit)
  POST   /admin/cc/affiliate-products/{id}/stock         IN_STOCK / OUT_OF_STOCK / UNKNOWN (affiliate_products:stock)
  POST   /admin/cc/affiliate-products/{id}/commission    ACTIVE / INACTIVE / UNKNOWN  (affiliate_products:commission)
  POST   /admin/cc/affiliate-products/{id}/enable|disable                             (affiliate_products:edit)
  DELETE /admin/cc/affiliate-products/{id}?confirm=true  soft delete, history kept    (affiliate_products:delete)
  POST   /admin/cc/affiliate-products/bulk               JSON rows or CSV; upsert / status (feed) (affiliate_products:bulk_import)
  POST   /admin/cc/affiliate-products/extract            page metadata suggestions    (affiliate_products:create|edit)
  GET    /admin/cc/affiliate-sources                     per-source settings + health (affiliate_products:view)
  PUT    /admin/cc/affiliate-sources/{platform}          organic / monetization / mode / commission (affiliate:manage)
  GET    /admin/cc/marketplace-apis                      Amazon / Flipkart / Meesho product-API status (affiliate_products:view)
  POST   /admin/cc/affiliate-products/{id}/api-refresh   price / MRP / stock from the marketplace API (affiliate_products:stock)

Affiliate links additionally need ``affiliate_products:links``; stock and
commission values set while adding or editing need their own permissions.
Every change is written to the product's history AND the Command Center
audit log. Credentials are never returned.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _principal, _require_confirm, command_center
from app.services import affiliate_catalog as ac
from app.services import governance as gov

router = APIRouter(prefix="/admin/cc", tags=["affiliate-catalog"])


def catalog(container: Any) -> ac.AffiliateCatalog:
    store = getattr(container, "affiliate_catalog", None)
    if store is None:
        store = ac.AffiliateCatalog(container.settings.database_path)
        container.affiliate_catalog = store
    return store


def sources(container: Any) -> dict[str, dict[str, Any]]:
    out = ac.source_settings(getattr(container, "affiliate_provider_config", None))
    try:
        health = catalog(container).health()
    except Exception:
        health = {}
    for pid, row in out.items():
        h = health.get(pid) or {}
        row["health"] = {"status": h.get("last_status") or "not_checked", "last_check_at": h.get("last_check_at"),
                         "last_success_at": h.get("last_success_at"), "last_results": h.get("last_results", 0),
                         "method": h.get("last_method") or None}
    return out


def _allowed(principal: dict[str, Any], verb: str) -> bool:
    held = principal["permissions"]
    return gov.has_permission(held, f"affiliate_products:{verb}") or "affiliate_products:manage" in held


def _need(request: Request, *verbs: str) -> dict[str, Any]:
    principal = _principal(request)
    for verb in verbs:
        if not _allowed(principal, verb):
            raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate_products:{verb})")
    return principal


def _audit(request: Request, principal: dict[str, Any], action: str, product_id: Any, before: Any, after: Any) -> None:
    try:
        command_center(request.app.state.container).audit(
            principal["id"], f"affiliate_product.{action}", "affiliate_product", str(product_id),
            before=before, after=after, role=principal.get("role"))
    except Exception:
        pass  # the product's own history already holds the change


def _brief(item: dict[str, Any] | None) -> dict[str, Any] | None:
    if not item:
        return None
    keys = ("title", "platform", "price", "mrp", "stock_status", "commission_status", "active", "deleted_at",
            "original_product_url", "affiliate_url", "sponsored", "category")
    return {k: item.get(k) for k in keys}


def _bad(error: Exception) -> HTTPException:
    if isinstance(error, LookupError):
        return HTTPException(status_code=404, detail=str(error) or "Product not found")
    return HTTPException(status_code=400, detail=str(error))


class ProductBody(BaseModel):
    title: str | None = Field(default=None, max_length=300)
    platform: str | None = Field(default=None, max_length=20)
    original_product_url: str | None = Field(default=None, max_length=2000)
    affiliate_url: str | None = Field(default=None, max_length=2000)
    image_url: str | None = Field(default=None, max_length=2000)
    images: list[str] | None = None
    price: float | None = None
    mrp: float | None = None
    currency: str | None = Field(default=None, max_length=8)
    category: str | None = Field(default=None, max_length=80)
    subcategory: str | None = Field(default=None, max_length=80)
    description: str | None = Field(default=None, max_length=4000)
    variants: list[str] | None = None
    seller: str | None = Field(default=None, max_length=200)
    sponsored: bool | None = None
    location: str | None = Field(default=None, max_length=200)
    availability: str | None = Field(default=None, max_length=200)
    stock_status: str | None = Field(default=None, max_length=20)
    commission_status: str | None = Field(default=None, max_length=20)
    verified_commission_rate: float | None = None


class StateBody(BaseModel):
    status: str = Field(max_length=20)
    note: str = Field(default="", max_length=500)
    rate: float | None = None


class BulkBody(BaseModel):
    rows: list[dict[str, Any]] = Field(default_factory=list)
    csv: str = Field(default="", max_length=2_000_000)
    mode: str = "upsert"  # upsert | status
    check_source: str = "manual"  # manual | feed
    dry_run: bool = False


class ExtractBody(BaseModel):
    url: str = Field(max_length=2000)


class SourceBody(BaseModel):
    organic_enabled: bool | None = None
    monetization_enabled: bool | None = None
    mode: str | None = None
    commission_state: str | None = None


@router.get("/affiliate-products")
def list_products(request: Request, q: str = "", platform: str = "", stock: str = "", commission: str = "",
                  state: str = "", include_deleted: bool = False, limit: int = 100, offset: int = 0) -> dict[str, Any]:
    principal = _need(request, "view")
    container = request.app.state.container
    data = catalog(container).list(q=q, platform=platform, stock=stock, commission=commission, state=state,
                                   include_deleted=include_deleted, limit=limit, offset=offset,
                                   sources=sources(container))
    data["can"] = {verb: _allowed(principal, verb) for verb in
                   ("create", "edit", "delete", "stock", "commission", "links", "bulk_import")}
    data["platforms"] = {pid: info["name"] for pid, info in ac.PLATFORMS.items()}
    return data


@router.get("/affiliate-products/{product_id}")
def get_product(product_id: int, request: Request) -> dict[str, Any]:
    _need(request, "view")
    container = request.app.state.container
    item = catalog(container).get(product_id, sources(container))
    if not item:
        raise HTTPException(status_code=404, detail="Product not found")
    return {"item": item, "history": catalog(container).history(product_id)}


@router.post("/affiliate-products")
def create_product(body: ProductBody, request: Request) -> dict[str, Any]:
    values = body.model_dump(exclude_none=True)
    stock = values.pop("stock_status", None)
    commission = values.pop("commission_status", None)
    verbs = ["create"]
    if values.get("affiliate_url"):
        verbs.append("links")
    if stock and ac.normalize_stock(stock) != "UNKNOWN":
        verbs.append("stock")
    if commission and ac.normalize_commission(commission) != "UNKNOWN":
        verbs.append("commission")
    if values.get("verified_commission_rate") is not None:
        verbs.append("commission")
    principal = _need(request, *verbs)
    try:
        item = catalog(request.app.state.container).create(values, actor=principal["id"], stock_status=stock,
                                                           commission_status=commission)
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, "create", item["id"], None, _brief(item))
    return {"item": get_product(item["id"], request)["item"]}


@router.patch("/affiliate-products/{product_id}")
def edit_product(product_id: int, body: ProductBody, request: Request) -> dict[str, Any]:
    values = body.model_dump(exclude_unset=True)
    stock = values.pop("stock_status", None)
    commission = values.pop("commission_status", None)
    verbs = ["edit"] if values else []
    if "affiliate_url" in values:
        verbs.append("links")
    if "verified_commission_rate" in values:
        verbs.append("commission")
    if stock is not None:
        verbs.append("stock")
    if commission is not None:
        verbs.append("commission")
    principal = _need(request, *(verbs or ["edit"]))
    store = catalog(request.app.state.container)
    before = store.get(product_id)
    try:
        item = store.update(product_id, values, actor=principal["id"]) if values else before
        if item is None:
            raise LookupError("Product not found")
        if stock is not None:
            item = store.set_stock(product_id, stock, actor=principal["id"])
        if commission is not None:
            item = store.set_commission(product_id, commission, actor=principal["id"])
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, "edit", product_id, _brief(before), _brief(item))
    return {"item": get_product(product_id, request)["item"]}


@router.post("/affiliate-products/{product_id}/stock")
def product_stock(product_id: int, body: StateBody, request: Request) -> dict[str, Any]:
    principal = _need(request, "stock")
    store = catalog(request.app.state.container)
    before = store.get(product_id)
    try:
        item = store.set_stock(product_id, body.status, actor=principal["id"], note=body.note)
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, "stock", product_id, _brief(before), _brief(item))
    return {"item": get_product(product_id, request)["item"]}


@router.post("/affiliate-products/{product_id}/commission")
def product_commission(product_id: int, body: StateBody, request: Request) -> dict[str, Any]:
    principal = _need(request, "commission")
    store = catalog(request.app.state.container)
    before = store.get(product_id)
    try:
        item = store.set_commission(product_id, body.status, actor=principal["id"], rate=body.rate, note=body.note)
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, "commission", product_id, _brief(before), _brief(item))
    return {"item": get_product(product_id, request)["item"]}


def _api_status(container: Any) -> dict[str, Any]:
    from app.api.routes.platform import platform
    from app.services import marketplace_api

    registry = platform(container).registry
    return {p: marketplace_api.status(registry, p) for p in marketplace_api.PLATFORM_PROVIDER}


@router.get("/marketplace-apis")
def marketplace_apis(request: Request) -> dict[str, Any]:
    _need(request, "view")
    return {"items": _api_status(request.app.state.container)}


@router.post("/affiliate-products/{product_id}/api-refresh")
def api_refresh(product_id: int, request: Request) -> dict[str, Any]:
    """Real API answers update price / MRP / stock (history: check_source=api);
    a MOCK answer is returned as a preview and never written."""
    from app.api.routes.platform import platform
    from app.services import comms, marketplace_api

    principal = _need(request, "stock")
    container = request.app.state.container
    store = catalog(container)
    before = store.get(product_id)
    try:
        result = marketplace_api.refresh(store, platform(container).registry,
                                         getattr(container, "comms_http", None) or comms.default_http,
                                         product_id, actor=principal["id"])
    except (ValueError, LookupError) as error:
        raise _bad(error)
    if result.get("applied"):
        _audit(request, principal, "api_refresh", product_id, _brief(before), _brief(result.get("product")))
    result.pop("product", None)
    return result


@router.post("/affiliate-products/{product_id}/{action}")
def product_toggle(product_id: int, action: str, request: Request) -> dict[str, Any]:
    if action not in {"enable", "disable"}:
        raise HTTPException(status_code=404, detail="Unknown action")
    principal = _need(request, "edit")
    store = catalog(request.app.state.container)
    before = store.get(product_id)
    try:
        item = store.set_active(product_id, action == "enable", actor=principal["id"])
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, action, product_id, _brief(before), _brief(item))
    return {"item": get_product(product_id, request)["item"]}


@router.delete("/affiliate-products/{product_id}")
def delete_product(product_id: int, request: Request, confirm: bool = False) -> dict[str, Any]:
    principal = _need(request, "delete")
    _require_confirm(confirm, "delete this product")
    store = catalog(request.app.state.container)
    before = store.get(product_id)
    try:
        store.delete(product_id, actor=principal["id"])
    except (ValueError, LookupError) as error:
        raise _bad(error)
    _audit(request, principal, "delete", product_id, _brief(before), None)
    return {"deleted": True, "id": product_id}


@router.post("/affiliate-products/bulk")
def bulk_products(body: BulkBody, request: Request) -> dict[str, Any]:
    principal = _need(request, "bulk_import")
    if body.mode not in {"upsert", "status"}:
        raise HTTPException(status_code=400, detail="mode must be upsert or status")
    if body.check_source not in {"manual", "feed"}:
        raise HTTPException(status_code=400, detail="check_source must be manual or feed")
    store = catalog(request.app.state.container)
    rows = store.parse_rows(body.rows, body.csv)
    if not rows:
        raise HTTPException(status_code=400, detail="No rows to import")
    result = store.bulk(rows, actor=principal["id"], mode=body.mode, check_source=body.check_source,
                        dry_run=body.dry_run, allowed=lambda verb: _allowed(principal, verb))
    if not body.dry_run:
        _audit(request, principal, f"bulk_{body.mode}", "bulk", None,
               {"rows": len(rows), "ok": result["ok"], "failed": result["failed"], "source": body.check_source})
        if body.check_source == "feed":
            platforms = {r.get("platform") or ac.detect_platform(str(r.get("original_product_url") or ""))
                         for r in rows}
            for platform in platforms & set(ac.PLATFORMS):
                store.record_health(platform, status="ok" if result["ok"] else "error",
                                    results=result["ok"], method="feed")
    return result


@router.post("/affiliate-products/extract")
def extract_product(body: ExtractBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    if not (_allowed(principal, "create") or _allowed(principal, "edit")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate_products:create)")
    from app.services import rate_limit

    rate_limit.check(request, "affiliate_extract", limit=30)
    fetch = getattr(request.app.state.container, "affiliate_page_fetch", None)
    try:
        return ac.extract_metadata(body.url, fetch=fetch)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))


@router.get("/affiliate-sources")
def list_sources(request: Request) -> dict[str, Any]:
    _need(request, "view")
    container = request.app.state.container
    rows = sources(container)
    listing = catalog(container).list(limit=1, sources=rows)  # summary only
    per: dict[str, dict[str, int]] = {}
    for item in catalog(container).list(limit=500, sources=rows)["items"]:
        bucket = per.setdefault(item["platform"] or "other", {"products": 0, "eligible": 0, "out_of_stock": 0,
                                                              "affiliate_routed": 0})
        bucket["products"] += 1
        bucket["eligible"] += int(item["eligibility"]["eligible"])
        bucket["out_of_stock"] += int(item["stock_status"] == "OUT_OF_STOCK")
        bucket["affiliate_routed"] += int(item["eligibility"]["routing"] == "affiliate")
    for pid, row in rows.items():
        row["catalog"] = per.get(pid, {"products": 0, "eligible": 0, "out_of_stock": 0, "affiliate_routed": 0})
    return {"items": list(rows.values()), "summary": listing["summary"],
            "apis": _api_status(container),
            "notes": {"organic": "Organic marketplace results come from a site-restricted web search.",
                      "api": "Amazon PA-API / Flipkart product API refresh price and stock only when their "
                             "integration is configured and checked (see apis); Meesho has no product API. "
                             "Otherwise stock and commission change through staff edits or a feed import."}}


@router.put("/affiliate-sources/{platform}")
def save_source(platform: str, body: SourceBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    if not (gov.has_permission(principal["permissions"], "affiliate:manage")
            or gov.has_permission(principal["permissions"], "integrations:manage")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate:manage)")
    container = request.app.state.container
    config = getattr(container, "affiliate_provider_config", None)
    if config is None:
        raise HTTPException(status_code=503, detail="Affiliate provider registry unavailable")
    before = sources(container).get(platform)
    try:
        ac.save_source(config, platform, body.model_dump(exclude_none=True))
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))
    after = sources(container)[platform]
    try:
        keys = ("organic_enabled", "monetization_enabled", "mode", "commission_state")
        command_center(container).audit(principal["id"], "affiliate_source.save", "affiliate_source", platform,
                                        before={k: (before or {}).get(k) for k in keys},
                                        after={k: after.get(k) for k in keys}, role=principal.get("role"))
    except Exception:
        pass
    return {"item": after}
