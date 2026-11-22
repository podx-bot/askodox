"""Shop link APIs + public pages (see ``app/services/shop_links.py``).

Owner / manager: ``GET|PUT /api/pos/businesses/{id}/link``, ``GET .../link/check?slug=``, ``GET .../link/stats``
(only the OWNER may PUT). Public (no sign-in, rate-limited): ``/s/{slug}`` (shop page), ``/s/{slug}/order``
(the menu form -> WhatsApp page / app page), ``/s/{slug}/go/{kind}`` (counted redirects to https targets),
``POST /s/{slug}/c/{kind}`` (``ping`` counts for call / UPI taps). Proxied on askodox.com (website Caddyfile).
"""
from __future__ import annotations

from typing import Any, Dict, Optional
from urllib.parse import quote

from fastapi import APIRouter, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field

from app.api.routes.pos import _call, _store, _user
from app.services import rate_limit
from app.services import shop_link_pages as pages
from app.services.shop_links import ShopLinks

router = APIRouter(prefix="/api/pos", tags=["Shop link"])
page_router = APIRouter(tags=["Shop link pages"])

CSP = ("default-src 'self'; img-src 'self' https: data:; style-src 'unsafe-inline'; script-src 'none'; "
       "connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
HEADERS = {"Content-Security-Policy": CSP, "Cache-Control": "no-store", "Referrer-Policy": "strict-origin-when-cross-origin",
           "X-Robots-Tag": "noindex"}


def links(request: Request) -> ShopLinks:
    from app.api.routes.payment_methods import payment_methods
    from app.api.routes.pos_frontdesk import _desk

    container: Any = request.app.state.container
    store = _store(request)
    existing = getattr(container, "shop_links", None)
    if existing is None or existing.store is not store:
        methods = payment_methods(container)

        def menu(conn, business_id: str):
            return _desk(request)._menu(conn, business_id)

        def upi(owner: str) -> Optional[Dict[str, Any]]:
            try:
                found = methods.pay_to(owner, amount=None, note="ASKODOX shop link", reference="shoplink")
            except Exception:
                return None
            first = next((m for m in found if m.get("kind") == "upi" and m.get("upi_link")), None)
            return {"upi_id": first["upi_id"], "payee_name": first.get("payee_name") or "", "upi_link": first["upi_link"]} if first else None

        existing = ShopLinks(store, menu=menu, upi=upi)
        try:
            container.shop_links = existing
        except Exception:
            pass
    return existing


class LinkIn(BaseModel):
    slug: str = Field(default="", max_length=40)
    enabled: Optional[bool] = None
    show_menu: Optional[bool] = None
    show_prices: Optional[bool] = None
    show_call: Optional[bool] = None
    show_map: Optional[bool] = None
    show_pay: Optional[bool] = None
    offer: Optional[str] = Field(default=None, max_length=200)
    about: Optional[str] = Field(default=None, max_length=300)
    color: Optional[str] = Field(default=None, max_length=20)
    whatsapp: Optional[str] = Field(default=None, max_length=20)


@router.get("/businesses/{business_id}/link")
def get_link(business_id: str, request: Request) -> dict:
    return _call(links(request).get, business_id, _user(request, "shoplink", 120))


@router.get("/businesses/{business_id}/link/check")
def check_link(business_id: str, slug: str, request: Request) -> dict:
    return _call(links(request).check_slug, business_id, _user(request, "shoplink", 120), slug)


@router.get("/businesses/{business_id}/link/stats")
def link_stats(business_id: str, request: Request) -> dict:
    return _call(links(request).stats, business_id, _user(request, "shoplink", 120))


@router.put("/businesses/{business_id}/link")
def save_link(business_id: str, body: LinkIn, request: Request) -> dict:
    data = {k: v for k, v in body.model_dump().items() if v is not None}
    return _call(links(request).save, business_id, _user(request, "shoplink-save", 30), data)


# ---------------------------------------------------------------------- public pages
def _page_or_redirect(request: Request, slug: str, suffix: str = ""):
    service = links(request)
    found = service.resolve(slug)
    if found.get("moved"):
        return None, RedirectResponse(f"/s/{found['moved']}{suffix}", status_code=301)
    page = service.public(slug) if found.get("business_id") else None
    if page is None:
        return None, HTMLResponse(pages.missing_html(off=bool(found.get("off"))), status_code=404, headers=HEADERS)
    return page, None


@page_router.get("/s/{slug}", response_class=HTMLResponse)
def shop_page(slug: str, request: Request):
    rate_limit.check(request, "shoplink-page", limit=120)
    page, other = _page_or_redirect(request, slug)
    if other is not None:
        return other
    links(request).count(page["business_id"], "view")
    return HTMLResponse(pages.shop_html(page), headers=HEADERS)


@page_router.get("/s/{slug}/order", response_class=HTMLResponse)
def shop_order(slug: str, request: Request):
    rate_limit.check(request, "shoplink-order", limit=30)
    page, other = _page_or_redirect(request, slug, "/order?" + str(request.url.query) if request.url.query else "/order")
    if other is not None:
        return other
    params = request.query_params
    quantities = {key[2:]: value for key, value in params.items() if key.startswith("q_")}
    service = links(request)
    order = service.order(page, quantities, params.get("name", ""), params.get("note", ""))
    via = params.get("via", "wa")
    if via == "app":
        service.count(page["business_id"], "order_app")
        return HTMLResponse(pages.app_html(page, order), headers=HEADERS)
    if not order["lines"]:
        return HTMLResponse(pages.shop_html(page, error="ఏమీ ఎంచుకోలేదు — ఐటమ్ పక్కన ఎన్ని కావాలో రాయండి."), headers=HEADERS)
    service.count(page["business_id"], "order_wa")
    return HTMLResponse(pages.after_html(page, order), headers=HEADERS)


@page_router.get("/s/{slug}/go/{kind}")
def shop_go(slug: str, kind: str, request: Request):
    """Counted taps that leave for an https page: the app (Play), follow / join (Play), map, a WhatsApp chat."""
    rate_limit.check(request, "shoplink-go", limit=60)
    page, other = _page_or_redirect(request, slug, f"/go/{kind}")
    if other is not None:
        return other
    target = ""
    if kind in ("app", "follow"):
        target = page["play"]
    elif kind == "join":
        target = page["join"]
    elif kind == "map" and page.get("address"):
        target = "https://www.google.com/maps/search/?api=1&query=" + quote(f"{page['name']}, {page['address']}", safe="")
    elif kind == "chat" or kind == "wa":
        kind = "chat"
        if page.get("whatsapp"):
            text = f"నమస్తే {page['name']} 🙏 ASKODOX లింక్ చూసి మెసేజ్ చేస్తున్నాను.\n{page['url']}"
            target = f"https://wa.me/91{page['whatsapp']}?text={quote(text, safe='')}"
    if not target:
        return RedirectResponse(f"/s/{page['slug']}", status_code=302)
    links(request).count(page["business_id"], kind)
    return RedirectResponse(target, status_code=302, headers={"Cache-Control": "no-store"})


@page_router.post("/s/{slug}/c/{kind}")
def shop_ping(slug: str, kind: str, request: Request) -> Response:
    """The ``ping`` of a call / UPI link (no script on the page): counted, nothing else."""
    rate_limit.check(request, "shoplink-ping", limit=60)
    service = links(request)
    found = service.resolve(slug)
    if found.get("business_id") and kind in ("call", "pay"):
        service.count(found["business_id"], kind)
    return Response(status_code=204)
