"""ASKODOX's own YouTube channel: connect (Google sign-in) + post a published Studio video.

  POST /admin/cc/workspace/youtube/connect       publisher -> a one-time link (10 min)
  GET  /youtube/oauth/start?t=<state>            that link -> Google's consent page
  GET  /youtube/oauth/callback                   Google comes back -> the channel is saved (token encrypted)
  GET  /admin/cc/workspace/youtube               staff -> connected? which channel? last uploads
  POST /admin/cc/workspace/youtube/disconnect    publisher -> token revoked at Google + removed
  POST /admin/cc/workspace/studio/purchases/{id}/youtube   publisher -> the PUBLISHED video goes to the channel

No token is ever shown, returned or logged. See ``app/services/youtube_channel.py``.
"""
from __future__ import annotations

import html
import os
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field

from app.api.routes.staff_workspace import _can_publish, _types, _workspace
from app.services import governance as gov
from app.services import youtube_channel as yt
from app.services.secret_box import SecretsNotConfigured, box_from_settings

router = APIRouter(tags=["YouTube channel"])


def channel_store(container: Any) -> yt.YouTubeChannelStore:
    store = getattr(container, "youtube_channel_store", None)
    if store is None:
        store = yt.YouTubeChannelStore(container.settings.database_path, box_from_settings(container.settings))
        container.youtube_channel_store = store
    return store


def _staff(request: Request) -> dict:
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    return principal


def _publisher(request: Request) -> dict:
    principal = _staff(request)
    if not _can_publish(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    return principal


def _page(title: str, body: str, status: int = 200) -> HTMLResponse:
    doc = ("<!doctype html><html lang='te'><head><meta charset='utf-8'>"
           "<meta name='viewport' content='width=device-width,initial-scale=1'>"
           f"<title>{html.escape(title)}</title></head>"
           "<body style='font-family:system-ui,sans-serif;max-width:560px;margin:40px auto;padding:0 16px'>"
           f"<h2>{html.escape(title)}</h2>{body}</body></html>")
    return HTMLResponse(doc, status_code=status, headers={"Cache-Control": "no-store"})


@router.get("/admin/cc/workspace/youtube")
def youtube_status(request: Request) -> dict:
    _staff(request)
    return channel_store(request.app.state.container).status()


@router.post("/admin/cc/workspace/youtube/connect")
def youtube_connect(request: Request) -> dict:
    principal = _publisher(request)
    store = channel_store(request.app.state.container)
    if not yt.configured():
        raise HTTPException(status_code=503, detail="YOUTUBE_OAUTH_CLIENT_ID / YOUTUBE_OAUTH_CLIENT_SECRET Railway లో లేవు")
    if not store.box.configured:
        raise HTTPException(status_code=503, detail="ASKODOX_SECRETS_KEY లేదు -- token దాచలేం")
    base = str(request.base_url).rstrip("/").replace("http://", "https://")
    return {"url": f"{base}/youtube/oauth/start?t={store.new_state(principal['id'])}", "minutes": yt.STATE_MINUTES}


@router.get("/youtube/oauth/start", response_model=None)
def youtube_oauth_start(request: Request, t: str = ""):
    store = channel_store(request.app.state.container)
    if not yt.configured():
        return _page("YouTube సెటప్ కాలేదు", "<p>Server లో YouTube sign-in వివరాలు లేవు.</p>", 503)
    if not t or not store.state_open(t):
        return _page("లింక్ గడువు అయిపోయింది", "<p>Staff Workspace లో మళ్లీ “YouTube Connect” నొక్కండి.</p>", 400)
    return RedirectResponse(yt.auth_url(t), status_code=302)


@router.get("/youtube/oauth/callback", response_model=None)
def youtube_oauth_callback(request: Request, code: str = "", state: str = "", error: str = "") -> HTMLResponse:
    store = channel_store(request.app.state.container)
    if error:
        return _page("Connect ఆగింది", "<p>Google sign-in పూర్తి కాలేదు. మళ్లీ ప్రయత్నించవచ్చు.</p>", 400)
    actor = store.take_state(state) if state else ""
    if not actor:
        return _page("Connect కాలేదు", "<p>లింక్ చెల్లదు లేదా గడువు అయిపోయింది. మళ్లీ మొదలుపెట్టండి.</p>", 400)
    if not code:
        return _page("Connect కాలేదు", "<p>Google నుంచి code రాలేదు.</p>", 400)
    try:
        tokens = yt.exchange_code(code)
        refresh = str(tokens.get("refresh_token") or "")
        if not refresh:
            raise yt.YouTubeError("Google refresh token ఇవ్వలేదు. మళ్లీ Connect చేసి అన్ని అనుమతులు ఇవ్వండి.")
        channel = yt.channel_of(str(tokens.get("access_token") or ""))
        store.save(channel, refresh, actor=actor)
    except yt.YouTubeError as problem:
        return _page("Connect కాలేదు", f"<p>{html.escape(str(problem))}</p>", 502)
    except SecretsNotConfigured:
        return _page("Connect కాలేదు", "<p>Server లో ASKODOX_SECRETS_KEY లేదు.</p>", 503)
    except Exception:
        return _page("Connect కాలేదు", "<p>Google తో మాట్లాడలేకపోయాం. మళ్లీ ప్రయత్నించండి.</p>", 502)
    print(f"ASKODOX YOUTUBE CONNECT channel={channel['id']} by={actor}", flush=True)
    return _page("YouTube connect అయింది ✓",
                 f"<p>Channel: <b>{html.escape(channel['title'])}</b></p><p>ఈ పేజీ మూసి Staff Workspace కి వెళ్లండి.</p>")


@router.post("/admin/cc/workspace/youtube/disconnect")
def youtube_disconnect(request: Request) -> dict:
    principal = _publisher(request)
    store = channel_store(request.app.state.container)
    token = store.disconnect()
    if token:
        yt.revoke(token)
    print(f"ASKODOX YOUTUBE DISCONNECT by={principal['id']}", flush=True)
    return store.status()


class UploadBody(BaseModel):
    privacy: str = Field(default="private", pattern="^(private|unlisted|public)$")


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/youtube")
def studio_to_youtube(purchase_id: int, body: UploadBody, request: Request) -> dict:
    """A PUBLISHED Studio video -> ASKODOX's channel, once. The post link is saved on the purchase by itself."""
    from app.api.routes import native_video
    from app.api.routes import studio as studio_routes
    from app.services import studio_video as sv

    principal = _publisher(request)
    container = request.app.state.container
    store = channel_store(container)
    purchases = studio_routes.studio(container)
    row = purchases.get(purchase_id)
    if not row:
        raise HTTPException(status_code=404, detail="Purchase not found")
    if not row.get("published_at") or not row.get("edited_file"):
        raise HTTPException(status_code=422, detail="ముందు వీడియో ఎడిట్ చేసి Publish చేయండి")
    ref = f"studio:{purchase_id}"
    done = store.uploaded(ref)
    if done:
        return {"upload": done, "already": True, "purchase": studio_routes._detail(request, row)}
    refresh = store.refresh_token()
    if not refresh:
        raise HTTPException(status_code=409, detail="YouTube connect కాలేదు -- ముందు Connect చేయండి")
    path = os.path.join(native_video._folder(request), str(row["edited_file"]))
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="వీడియో ఫైల్ లేదు -- మళ్లీ ఎడిట్ చేయండి")
    caption = sv.captions(row)["youtube"]
    try:
        video_id = yt.upload_file(yt.access_token(refresh), path, title=caption.get("title") or row["title"],
                                  description=caption.get("text") or "", privacy=body.privacy)
    except yt.YouTubeError as problem:
        print(f"ASKODOX YOUTUBE UPLOAD failed ref={ref} why={problem}", flush=True)
        raise HTTPException(status_code=502, detail=str(problem))
    upload = store.record_upload(ref, video_id, body.privacy, actor=principal["id"])
    row = purchases.add_post(purchase_id, "youtube", upload["url"])
    print(f"ASKODOX YOUTUBE UPLOAD ok ref={ref} video={video_id} privacy={body.privacy}", flush=True)
    return {"upload": upload, "already": False, "purchase": studio_routes._detail(request, row)}
