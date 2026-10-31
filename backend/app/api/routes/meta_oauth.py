"""Facebook Login callback for Page + Instagram connection (App Review flow).

Flow:
  GET /meta/oauth/start     -> redirects the owner to Facebook Login
  GET /meta/oauth/callback  -> exchanges the code, lists the Pages the user manages

This module does NOT persist access tokens. Token storage (encrypted, per business)
is a separate, owner-approved step.
"""

from __future__ import annotations

import html
import os
import secrets
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

router = APIRouter(tags=["Meta OAuth"])

STATE_COOKIE = "askodox_meta_oauth_state"
DEFAULT_REDIRECT_URI = "https://admin.askodox.com/meta/oauth/callback"
DEFAULT_SCOPES = (
    "pages_show_list",
    "pages_read_engagement",
    "pages_manage_posts",
    "instagram_basic",
    "instagram_content_publish",
)


def _graph_version() -> str:
    return os.getenv("META_GRAPH_API_VERSION", "v24.0").strip() or "v24.0"


def _app_id() -> str:
    return os.getenv("META_APP_ID", "").strip()


def _app_secret() -> str:
    return os.getenv("META_APP_SECRET", "").strip()


def _redirect_uri() -> str:
    return os.getenv("META_OAUTH_REDIRECT_URI", DEFAULT_REDIRECT_URI).strip() or DEFAULT_REDIRECT_URI


def _exchange_code(code: str) -> str:
    """Return a user access token for the authorization code. Raises on failure."""
    params = {
        "client_id": _app_id(),
        "client_secret": _app_secret(),
        "redirect_uri": _redirect_uri(),
        "code": code,
    }
    url = f"https://graph.facebook.com/{_graph_version()}/oauth/access_token"
    with httpx.Client(timeout=15) as client:
        response = client.get(url, params=params)
        response.raise_for_status()
        return str(response.json().get("access_token") or "")


def _list_pages(user_token: str) -> list[dict]:
    """Return [{'id','name'}] for Pages the user manages. Token is not stored."""
    url = f"https://graph.facebook.com/{_graph_version()}/me/accounts"
    with httpx.Client(timeout=15) as client:
        response = client.get(url, params={"fields": "id,name", "access_token": user_token})
        response.raise_for_status()
        return list(response.json().get("data") or [])


def _page(title: str, body: str, status: int = 200) -> HTMLResponse:
    doc = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{html.escape(title)}</title></head>"
        "<body style='font-family:system-ui,sans-serif;max-width:560px;margin:40px auto;padding:0 16px'>"
        f"<h2>{html.escape(title)}</h2>{body}</body></html>"
    )
    return HTMLResponse(doc, status_code=status)


@router.get("/meta/oauth/start", response_model=None)
def meta_oauth_start():
    if not _app_id():
        return JSONResponse({"error": "META_APP_ID is not configured"}, status_code=503)
    state = secrets.token_urlsafe(24)
    query = urlencode(
        {
            "client_id": _app_id(),
            "redirect_uri": _redirect_uri(),
            "state": state,
            "response_type": "code",
            "scope": ",".join(DEFAULT_SCOPES),
        }
    )
    response = RedirectResponse(f"https://www.facebook.com/{_graph_version()}/dialog/oauth?{query}", status_code=302)
    response.set_cookie(STATE_COOKIE, state, max_age=600, httponly=True, secure=True, samesite="lax")
    return response


@router.get("/meta/oauth/callback", response_model=None)
def meta_oauth_callback(request: Request, code: str = "", state: str = "", error: str = "") -> HTMLResponse:
    if error:
        return _page("Connection cancelled", "<p>Facebook did not complete the connection. You can try again.</p>", 400)
    expected = request.cookies.get(STATE_COOKIE, "")
    if not expected or not state or not secrets.compare_digest(expected, state):
        return _page("Connection failed", "<p>Invalid or expired login session. Please start again.</p>", 400)
    if not code:
        return _page("Connection failed", "<p>Missing authorization code.</p>", 400)
    if not _app_id() or not _app_secret():
        return _page("Not configured", "<p>Meta app settings are missing on the server.</p>", 503)
    try:
        user_token = _exchange_code(code)
        pages = _list_pages(user_token)
    except httpx.HTTPError:
        return _page("Connection failed", "<p>Facebook could not verify this login. Please try again.</p>", 502)
    items = "".join(f"<li>{html.escape(str(p.get('name') or 'Unnamed Page'))}</li>" for p in pages)
    body = (
        f"<p>Pages found: {len(pages)}</p><ul>{items}</ul>"
        if pages
        else "<p>No Facebook Pages were found for this login.</p>"
    )
    response = _page("Facebook connected", body)
    response.delete_cookie(STATE_COOKIE)
    return response
