"""Public ASKODOX product pages: ``/p/{id}``, ``/p/{id}/buy`` (counted, then the commission link), ``/shop``.
See ``app/services/product_pages.py``. Served by the backend and proxied on askodox.com."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from app.api.routes.affiliate_catalog import catalog
from app.services import affiliate_catalog as ac
from app.services import product_pages as pp

router = APIRouter(tags=["product-pages"])

CSP = ("default-src 'self'; img-src 'self' https: data:; media-src 'self' https:; style-src 'unsafe-inline'; "
       "script-src 'none'; frame-ancestors 'none'; base-uri 'none'")


def _videos(request: Request) -> list:
    from app.api.routes.platform import platform

    try:
        return platform(request.app.state.container).resources.repo.list("videos")
    except Exception:
        return []


def _live_item(request: Request, item_id: int) -> dict:
    item = catalog(request.app.state.container).get(item_id)
    if not pp.live(item):
        raise HTTPException(status_code=404, detail="Not found")
    return item


@router.get("/p/{item_id}", response_class=HTMLResponse)
def product_page(item_id: int, request: Request) -> HTMLResponse:
    item = _live_item(request, item_id)
    source = pp.source_of(request.query_params.get("from", ""))
    pp.record(request.app.state.container, item_id, source, "view")
    page = pp.product_html(item, pp.latest_video(_videos(request), item_id), source)
    return HTMLResponse(page, headers={"Content-Security-Policy": CSP, "Cache-Control": "no-store"})


@router.get("/p/{item_id}/buy")
def product_buy(item_id: int, request: Request) -> RedirectResponse:
    item = _live_item(request, item_id)
    target = pp.buy_target(item)
    if not target:
        raise HTTPException(status_code=404, detail="No buy link")
    pp.record(request.app.state.container, item_id, request.query_params.get("from", ""), "buy")
    return RedirectResponse(target, status_code=302, headers={"Cache-Control": "no-store",
                                                              "Referrer-Policy": "no-referrer-when-downgrade"})


@router.get("/shop", response_class=HTMLResponse)
def shop(request: Request) -> HTMLResponse:
    store = catalog(request.app.state.container)
    with store._connect() as conn:
        rows = conn.execute("SELECT * FROM affiliate_products WHERE deleted_at IS NULL AND review_status='LIVE' "
                            "AND item_type='product' ORDER BY id DESC LIMIT 60").fetchall()
    items = [ac._public(dict(r)) for r in rows]
    return HTMLResponse(pp.shop_html(items), headers={"Content-Security-Policy": CSP, "Cache-Control": "no-store"})
