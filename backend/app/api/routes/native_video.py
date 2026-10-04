"""ASKODOX-native videos: upload from the phone, review, publish, feed,
report, and a native message to the video's business (auto-answered only
from the business's APPROVED FAQ, otherwise handed to the owner).

Customer / seller:
  POST /api/videos/upload            multipart (file, title, caption, category, products, language,
                                     video_type, as_business, submit)
  GET  /api/videos/feed              ACTIVE ASKODOX-hosted videos (newest first)
  POST /api/videos/mine/{id}/{submit|pause|resume|remove}
  POST /api/videos/{id}/report       (3 distinct reports pause an ACTIVE video for staff review)
  POST /api/videos/{id}/message      native DM to the business: FAQ auto-reply or handoff
  GET  /api/videos/mine/messages, POST /api/videos/messages/{id}/reply
  GET  /media/videos/{name}          the file (Range supported); unpublished files only to the owner / staff
Staff: GET /admin/cc/videos/reports

Nothing is published without staff review (resource ``videos``: DRAFT ->
PENDING_REVIEW -> ACTIVE). External social platforms are separate
(``social_dm``) and never involved here.
"""
from __future__ import annotations

import hashlib
import os
import re
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field

from app.api.routes.in_app_deal import _authenticated_app_user

router = APIRouter(tags=["native-video"])
REPORTS_TO_PAUSE = 3
_NAME = re.compile(r"[0-9a-f]{32}\.(mp4|webm|jpg|png)")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _pf(request: Request):
    from app.api.routes.platform import platform

    return platform(request.app.state.container)


def _folder(request: Request) -> str:
    return os.path.join(os.path.dirname(os.path.abspath(request.app.state.container.settings.database_path)),
                        "video_uploads")


@contextmanager
def _db(request: Request):
    conn = sqlite3.connect(request.app.state.container.settings.database_path)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("""CREATE TABLE IF NOT EXISTS video_reports (
            id TEXT PRIMARY KEY, video_id TEXT NOT NULL, reporter TEXT NOT NULL, reason TEXT NOT NULL,
            created_at TEXT NOT NULL, UNIQUE(video_id, reporter))""")
        conn.execute("""CREATE TABLE IF NOT EXISTS video_messages (
            id TEXT PRIMARY KEY, video_id TEXT NOT NULL, sender TEXT NOT NULL, owner TEXT NOT NULL,
            text TEXT NOT NULL, reply TEXT, reply_source TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL)""")
        yield conn
        conn.commit()
    finally:
        conn.close()


def _max_bytes(request: Request) -> int:
    try:
        from app.services import platform_settings

        mb = float(platform_settings.get("video_upload.max_mb", 60) or 60)
    except Exception:
        mb = 60
    return int(max(1, min(mb, 200)) * 1024 * 1024)


def _video_ext(data: bytes) -> Optional[str]:
    if len(data) > 12 and data[4:8] == b"ftyp":
        return ".mp4"  # MP4 / MOV / 3GP containers
    if data.startswith(b"\x1aE\xdf\xa3"):
        return ".webm"
    return None


def _image_ext(data: bytes) -> Optional[str]:
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    return None


def _save(request: Request, data: bytes, ext: str) -> str:
    name = hashlib.sha256(data).hexdigest()[:32] + ext
    folder = _folder(request)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        with open(path, "wb") as handle:
            handle.write(data)
    return name


def _base(request: Request) -> str:
    # Railway terminates TLS in front of the app; links are always https.
    return str(request.base_url).rstrip("/").replace("http://", "https://")


def _public(record: Dict[str, Any]) -> Dict[str, Any]:
    d = record.get("data") or {}
    return {"id": record["id"], "status": record["status"], "title": d.get("title") or record.get("name"),
            "caption": d.get("description") or "", "url": d.get("url"), "thumbnail_url": d.get("thumbnail_url"),
            "categories": d.get("categories") or [], "products": d.get("products") or [],
            "language": d.get("language") or "", "video_type": d.get("video_type") or "",
            "label": "From the business" if d.get("relationship") == "merchant" else "Shared on ASKODOX",
            "created_at": record.get("created_at")}


@router.post("/api/videos/upload")
async def upload_video(request: Request, file: UploadFile = File(...), title: str = Form("", max_length=140),
                       caption: str = Form("", max_length=2000), category: str = Form("", max_length=60),
                       products: str = Form("", max_length=400), language: str = Form("", max_length=10),
                       video_type: str = Form("demo", max_length=30), as_business: bool = Form(False),
                       submit: bool = Form(True), thumbnail: Optional[UploadFile] = File(None)) -> dict:
    """A user / seller uploads a video from the camera or gallery. It is
    stored on ASKODOX and goes to staff review (or stays a draft)."""
    user = _authenticated_app_user(request)
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.platform import user_ref
    from app.services import pii_mask, rate_limit

    # The app's uploader sends only the file part; its details come as query
    # parameters (same names). Form fields win when both are present.
    q = request.query_params
    title = (title or q.get("title", ""))[:140]
    caption = (caption or q.get("caption", ""))[:2000]
    category = (category or q.get("category", ""))[:60]
    products = (products or q.get("products", ""))[:400]
    language = (language or q.get("language", ""))[:10]
    if "video_type" in q and video_type == "demo":
        video_type = q.get("video_type", "demo")[:30]
    if "as_business" in q:
        as_business = q.get("as_business") in ("1", "true", "yes")
    if "submit" in q:
        submit = q.get("submit") in ("1", "true", "yes")
    if not title.strip():
        raise HTTPException(status_code=422, detail="Give the video a title")
    if not feature_enabled(request.app.state.container, "videos.upload"):
        raise HTTPException(status_code=409, detail="Video upload is switched off right now")
    rate_limit.check(request, "video_upload", limit=10)
    pf = _pf(request)
    if pf.repo.account_state("user", user_ref(user))["blocked"]:
        raise HTTPException(status_code=403, detail="Account blocked")
    limit = _max_bytes(request)
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(status_code=413, detail=f"Videos up to {limit // (1024 * 1024)} MB")
    ext = _video_ext(data)
    if ext is None:
        raise HTTPException(status_code=415, detail="MP4 or WebM videos only")
    name = _save(request, data, ext)
    thumb_url = None
    if thumbnail is not None:
        tdata = await thumbnail.read(3 * 1024 * 1024 + 1)
        text = _image_ext(tdata)
        if text and len(tdata) <= 3 * 1024 * 1024:
            thumb_url = f"{_base(request)}/media/videos/{_save(request, tdata, text)}"
    from app.services.platform_schema import VIDEO_TYPES

    record = pf.resources.create("videos", {
        "title": pii_mask.mask_sensitive(title.strip())[:140] or "Video",
        "platform": "askodox", "url": f"{_base(request)}/media/videos/{name}",
        "thumbnail_url": thumb_url, "description": pii_mask.mask_sensitive(caption.strip()),
        "categories": [category.strip().lower()] if category.strip() else [],
        "products": [p.strip() for p in products.split(",") if p.strip()][:10],
        "keywords": [w for w in re.findall(r"[^\W_]{3,}", f"{title} {category}".lower())][:12],
        "language": language.strip().lower(), "video_type": video_type if video_type in VIDEO_TYPES else "demo",
        "relationship": "merchant" if as_business else "creator", "merchant_ref": user_ref(user),
    }, actor=f"user:{user_ref(user)}", owner_ref=user, status="PENDING_REVIEW" if submit else "DRAFT")
    return _public(record)


@router.get("/api/videos/feed")
def video_feed(request: Request, category: str = "", limit: int = 20) -> dict:
    pf = _pf(request)
    rows = [r for r in pf.resources.repo.list("videos") if r.get("status") == "ACTIVE" and not r.get("archived")
            and (r.get("data") or {}).get("platform") == "askodox"]
    if category.strip():
        rows = [r for r in rows if category.strip().lower() in [c.lower() for c in (r["data"].get("categories") or [])]]
    rows.sort(key=lambda r: r.get("updated_at") or r.get("created_at") or "", reverse=True)
    return {"items": [_public(r) for r in rows[:max(1, min(limit, 50))]],
            "empty_reason": None if rows else "No ASKODOX videos are published yet."}


def _own_video(request: Request, video_id: str, user: str) -> Dict[str, Any]:
    try:
        return _pf(request).resources.get("videos", video_id, owner_ref=user)
    except KeyError:
        raise HTTPException(status_code=404, detail="Video not found") from None


_OWNER_MOVES = {"submit": ({"DRAFT", "REJECTED"}, "PENDING_REVIEW"), "pause": ({"ACTIVE"}, "PAUSED"),
                "resume": ({"PAUSED"}, "PENDING_REVIEW")}


@router.post("/api/videos/mine/{video_id}/{action}")
def my_video_action(video_id: str, action: str, request: Request) -> dict:
    """The owner submits a draft, pauses / resumes (resume goes back to
    review) or removes their video."""
    user = _authenticated_app_user(request)
    record = _own_video(request, video_id, user)
    repo = _pf(request).resources.repo
    if action == "remove":
        return _public(repo.update(video_id, actor=f"user:{user}", action="archive", archived=True))
    if action not in _OWNER_MOVES:
        raise HTTPException(status_code=404, detail="Unknown action")
    allowed, to = _OWNER_MOVES[action]
    if record["status"] not in allowed:
        raise HTTPException(status_code=409, detail=f"Cannot {action} a {record['status'].lower()} video")
    return _public(repo.update(video_id, actor=f"user:{user}", action=action, status=to))


class ReportBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    reason: str = Field(min_length=3, max_length=500)


def _video(request: Request, video_id: str) -> Dict[str, Any]:
    record = _pf(request).resources.repo.get(video_id)
    if not record or record.get("resource") != "videos" or record.get("archived"):
        raise HTTPException(status_code=404, detail="Video not found")
    return record


@router.post("/api/videos/{video_id}/report")
def report_video(video_id: str, body: ReportBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services import pii_mask, rate_limit

    rate_limit.check(request, "video_report", limit=20)
    record = _video(request, video_id)
    with _db(request) as conn:
        conn.execute("INSERT OR IGNORE INTO video_reports VALUES(?,?,?,?,?)",
                     ("vr_" + uuid.uuid4().hex[:12], video_id, user, pii_mask.mask_sensitive(body.reason), _now()))
        count = conn.execute("SELECT COUNT(*) FROM video_reports WHERE video_id=?", (video_id,)).fetchone()[0]
    paused = False
    if count >= REPORTS_TO_PAUSE and record["status"] == "ACTIVE":
        _pf(request).resources.repo.update(video_id, actor="system:reports", action="auto_pause", status="PAUSED")
        paused = True
    return {"reported": True, "reports": count, "paused_for_review": paused}


class MessageBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(min_length=1, max_length=1000)


@router.post("/api/videos/{video_id}/message")
def message_business(video_id: str, body: MessageBody, request: Request) -> dict:
    """Native ASKODOX DM about a video. The business's APPROVED FAQ answers
    when it covers the question; otherwise the owner gets it in
    /api/videos/mine/messages. Contact details stay masked both ways."""
    user = _authenticated_app_user(request)
    from app.api.routes.command_center import feature_enabled
    from app.services import auto_response, pii_mask, rate_limit

    rate_limit.check(request, "video_message", limit=30)
    record = _video(request, video_id)
    if record["status"] != "ACTIVE":
        raise HTTPException(status_code=404, detail="Video not found")
    owner = record.get("owner_ref") or ""
    if not owner:
        raise HTTPException(status_code=409, detail="This video has no ASKODOX business to message")
    if owner == user:
        raise HTTPException(status_code=422, detail="This is your own video")
    text = pii_mask.mask_sensitive(body.text.strip())
    result = {"status": "unknown", "text": None, "source": None}
    if feature_enabled(request.app.state.container, "autoresponse.enabled"):
        rule = auto_response.rule_for(_pf(request).repo.list("auto_response_rules"), owner, trigger="video",
                                      target=video_id, message=text)
        if rule is not None:
            result = auto_response.answer(text, rule)
    answered = result["status"] in ("answered", "out_of_hours") and bool(result["text"])
    status = "AUTO_ANSWERED" if answered else "WAITING_FOR_OWNER"
    mid = "vm_" + uuid.uuid4().hex[:14]
    with _db(request) as conn:
        conn.execute("INSERT INTO video_messages VALUES(?,?,?,?,?,?,?,?,?,?)",
                     (mid, video_id, user, owner, text, result["text"] if answered else None,
                      result["source"] if answered else None, status, _now(), _now()))
    return {"id": mid, "status": status, "reply": result["text"] if answered else None,
            "reply_label": ("Auto-reply" if result["status"] == "answered" else "Auto-reply (outside business hours)")
            if answered else None,
            "handoff_to_owner": not answered or result["status"] == "out_of_hours"}


@router.get("/api/videos/mine/messages")
def my_video_messages(request: Request) -> dict:
    """Owner inbox + the customer's own sent questions (no phone numbers)."""
    user = _authenticated_app_user(request)
    with _db(request) as conn:
        inbox = [dict(r) for r in conn.execute("SELECT * FROM video_messages WHERE owner=? ORDER BY created_at DESC "
                                               "LIMIT 100", (user,)).fetchall()]
        sent = [dict(r) for r in conn.execute("SELECT * FROM video_messages WHERE sender=? ORDER BY created_at DESC "
                                              "LIMIT 100", (user,)).fetchall()]
    strip = lambda rows: [{k: v for k, v in r.items() if k not in ("sender", "owner")} for r in rows]  # noqa: E731
    return {"inbox": strip(inbox), "sent": strip(sent)}


@router.post("/api/videos/messages/{message_id}/reply")
def reply_video_message(message_id: str, body: MessageBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services import pii_mask

    with _db(request) as conn:
        row = conn.execute("SELECT * FROM video_messages WHERE id=?", (message_id,)).fetchone()
        if not row or row["owner"] != user:
            raise HTTPException(status_code=404, detail="Message not found")
        reply = pii_mask.mask_sensitive(body.text.strip())
        conn.execute("UPDATE video_messages SET reply=?, reply_source='owner', status='ANSWERED', updated_at=? "
                     "WHERE id=?", (reply, _now(), message_id))
    return {"id": message_id, "status": "ANSWERED", "reply": reply}


@router.get("/admin/cc/videos/reports")
def video_reports(request: Request) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "content:view")
    with _db(request) as conn:
        rows = conn.execute("SELECT video_id, COUNT(*) AS reports, MAX(created_at) AS last_at, "
                            "GROUP_CONCAT(reason, ' | ') AS reasons FROM video_reports GROUP BY video_id "
                            "ORDER BY last_at DESC LIMIT 200").fetchall()
    return {"items": [dict(r) for r in rows]}


def _may_preview(request: Request, url_name: str) -> bool:
    pf = _pf(request)
    owners = []
    for r in pf.resources.repo.list("videos"):
        d = r.get("data") or {}
        if str(d.get("url") or "").endswith("/" + url_name) or str(d.get("thumbnail_url") or "").endswith(
                "/" + url_name):
            if r.get("status") == "ACTIVE" and not r.get("archived"):
                return True
            owners.append(r.get("owner_ref"))
    try:
        if _authenticated_app_user(request) in owners:
            return True
    except HTTPException:
        pass
    try:
        from app.api.routes.command_center import _require

        _require(request, "content:view")
        return True
    except HTTPException:
        return False


@router.get("/media/videos/{name}")
def video_media(name: str, request: Request) -> FileResponse:
    if not _NAME.fullmatch(name):
        raise HTTPException(status_code=404, detail="Not found")
    path = os.path.join(_folder(request), name)
    if not os.path.exists(path) or not _may_preview(request, name):
        raise HTTPException(status_code=404, detail="Not found")
    media = {"mp4": "video/mp4", "webm": "video/webm", "jpg": "image/jpeg", "png": "image/png"}[name.rsplit(".", 1)[1]]
    return FileResponse(path, media_type=media, headers={"Cache-Control": "public, max-age=3600",
                                                         "X-Content-Type-Options": "nosniff"})
