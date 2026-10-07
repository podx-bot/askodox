"""Affiliate Product Hub (Command Center): paste one or many product /
affiliate links, preview what each page truthfully states, edit, then save as
drafts or publish -- plus bulk publish / enable / disable / archive / restore.

  POST /admin/cc/affiliate-hub/preview      {text | urls}           (affiliate_products:create|edit)
  POST /admin/cc/affiliate-hub/import       {items:[...]}           (affiliate_products:create; publish needs :publish)
  POST /admin/cc/affiliate-hub/bulk-action  {ids, action, note}     (per action: edit / publish / delete)
  GET  /admin/cc/affiliate-hub/providers                            (affiliate_products:view)

Built on the existing affiliate catalog (one item store) and provider
adapters; nothing is stored anywhere else.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.affiliate_catalog import _allowed, _audit, _need, _principal, catalog
from app.services import affiliate_hub as hub
from app.services import affiliate_providers as providers
from app.services import governance as gov

router = APIRouter(prefix="/admin/cc/affiliate-hub", tags=["affiliate-hub"])


class PreviewBody(BaseModel):
    text: str = Field(default="", max_length=100_000)
    urls: list[str] = Field(default_factory=list, max_length=hub.MAX_LINKS)


class ImportBody(BaseModel):
    items: list[dict[str, Any]] = Field(default_factory=list, max_length=hub.MAX_LINKS)


class BulkActionBody(BaseModel):
    ids: list[int] = Field(default_factory=list, max_length=500)
    action: str = Field(max_length=20)
    note: str = Field(default="", max_length=500)


@router.get("/providers")
def list_providers(request: Request) -> dict[str, Any]:
    _need(request, "view")
    return {"providers": [{"id": a.id, "name": a.name, "product_hosts": list(a.product_hosts),
                           "short_link_hosts": list(a.short_link_hosts),
                           "embedded_page_data": type(a) is not providers.ProviderAdapter}
                          for a in providers.ADAPTERS.values()]}


@router.post("/preview")
def preview(body: PreviewBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    if not (_allowed(principal, "create") or _allowed(principal, "edit")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate_products:create)")
    links = hub.split_links(body.text, body.urls)
    if not links:
        raise HTTPException(status_code=400, detail="Paste at least one https:// product or affiliate link")
    from app.services import rate_limit

    rate_limit.check(request, "affiliate_hub_preview", limit=20)
    container = request.app.state.container
    fetch = getattr(container, "affiliate_page_fetch", None)
    return hub.preview(catalog(container), links, fetch=fetch)


@router.post("/import")
def import_items(body: ImportBody, request: Request) -> dict[str, Any]:
    principal = _need(request, "create")
    if not body.items:
        raise HTTPException(status_code=400, detail="Nothing to import")
    result = hub.import_items(catalog(request.app.state.container), body.items, actor=principal["id"],
                              allowed=lambda verb: _allowed(principal, verb))
    _audit(request, principal, "hub_import", "bulk", None,
           {"items": len(body.items), "ok": result["ok"], "failed": result["failed"]})
    return result


@router.post("/bulk-action")
def bulk_action(body: BulkActionBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    if not body.ids:
        raise HTTPException(status_code=400, detail="Select at least one product")
    try:
        result = hub.bulk_action(catalog(request.app.state.container), body.ids, body.action,
                                 actor=principal["id"], allowed=lambda verb: _allowed(principal, verb),
                                 note=body.note)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))
    _audit(request, principal, f"hub_bulk_{body.action}", "bulk", None,
           {"ids": body.ids[:50], "ok": result["ok"], "failed": result["failed"]})
    return result
