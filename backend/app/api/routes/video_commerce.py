"""Registered ASKODOX video commerce (on top of routes/native_video.py).

Owner (seller / provider / creator):
  POST  /api/videos/native/{id}/suggest       metadata suggestions from the analysed video only
  PATCH /api/videos/mine/{id}                 edit title / caption / category / tags / linked listings
                                              / pre-order settings (a published video returns to review)
  GET   /api/videos/mine/{id}/analytics       views, asks, questions, unanswered, top topics, area demand,
                                              pre-orders (no customer identities)
  GET   /api/videos/ai-settings | PUT        AI replies: off / draft / auto (+ pause = take over)
  GET   /api/videos/mine/inbox                ONE inbox: questions needing me, AI drafts, private
                                              messages, pre-orders
  POST  /api/videos/comments/{id}/reply      seller reply (overrides any draft / AI reply)
  POST  /api/videos/comments/{id}/approve    publish the AI draft as is
  POST  /api/videos/preorders/{id}/decide    accept / decline; contact only after accept
Customer:
  GET   /api/videos/native/{id}               published video + linked listings + where it appears
  POST  /api/videos/native/{id}/ask           grounded answer (seen / said / listing / unknown)
  GET   /api/videos/{id}/comments             public Q&A (moderated, masked)
  POST  /api/videos/{id}/comments             question or comment -> AI answer / draft / seller
  POST  /api/videos/{id}/preorder             pre-order a linked item (when the seller enabled it)
  GET   /api/videos/preorders/mine            my pre-orders (seller phone only after accept)
  POST  /api/videos/{id}/event                view / ask / share / request (+ coarse area name)
  GET   /api/videos/{id}/share                ASKODOX link + text for the Android share sheet
  GET   /v/{id}                               public share page (published videos only)
Staff: GET /admin/cc/videos/comments, POST /admin/cc/videos/comments/{id} (show / hide),
       GET /admin/cc/videos/analytics
"""
from __future__ import annotations

import html
import json
import uuid
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, ConfigDict, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.api.routes.native_video import _base, _db as _video_db, _now, _pf, _public, _video
from app.services import video_commerce as vc

router = APIRouter(tags=["video-commerce"])


@contextmanager
def _db(request: Request):
    with _video_db(request) as conn:
        conn.execute("""CREATE TABLE IF NOT EXISTS video_comments (
            id TEXT PRIMARY KEY, video_id TEXT NOT NULL, author TEXT NOT NULL, kind TEXT NOT NULL,
            text TEXT NOT NULL, status TEXT NOT NULL, reasons TEXT, reply TEXT, reply_by TEXT,
            reply_status TEXT NOT NULL, basis TEXT, evidence TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
        conn.execute("""CREATE TABLE IF NOT EXISTS video_ai_settings (
            owner TEXT PRIMARY KEY, mode TEXT NOT NULL, paused INTEGER NOT NULL DEFAULT 0, updated_at TEXT)""")
        conn.execute("""CREATE TABLE IF NOT EXISTS video_preorders (
            id TEXT PRIMARY KEY, video_id TEXT NOT NULL, listing_id TEXT, buyer TEXT NOT NULL, owner TEXT NOT NULL,
            quantity REAL, variant TEXT, note TEXT, status TEXT NOT NULL, seller_note TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
        conn.execute("""CREATE TABLE IF NOT EXISTS video_events (
            id TEXT PRIMARY KEY, video_id TEXT NOT NULL, kind TEXT NOT NULL, area TEXT, created_at TEXT NOT NULL)""")
        yield conn


def _uid(prefix: str) -> str:
    return prefix + uuid.uuid4().hex[:14]


def _optional_user(request: Request) -> Optional[str]:
    try:
        return _authenticated_app_user(request)
    except HTTPException:
        return None


def _phone_of(user_id: str) -> str:
    digits = "".join(ch for ch in str(user_id or "") if ch.isdigit())
    return "+" + digits if str(user_id or "").startswith("app-phone-") and len(digits) >= 10 else ""


def _owned(request: Request, video_id: str, user: str) -> Dict[str, Any]:
    record = _video(request, video_id)
    if record.get("owner_ref") != user:
        raise HTTPException(status_code=404, detail="Video not found")
    return record


def _published(request: Request, video_id: str) -> Dict[str, Any]:
    record = _video(request, video_id)
    if record["status"] != "ACTIVE":
        raise HTTPException(status_code=404, detail="Video not found")
    return record


def _settings(request: Request, owner: str) -> Dict[str, Any]:
    with _db(request) as conn:
        row = conn.execute("SELECT mode, paused FROM video_ai_settings WHERE owner=?", (owner,)).fetchone()
    return {"mode": row["mode"] if row else "draft", "paused": bool(row["paused"]) if row else False}


def _listings(request: Request, record: Dict[str, Any]) -> List[Dict[str, Any]]:
    repo = getattr(request.app.state.container, "product_catalog_repository", None)
    out = []
    for raw in (record.get("data") or {}).get("listing_ids") or []:
        try:
            row = repo.get(int(raw)) if repo is not None else None
        except (TypeError, ValueError):
            row = None
        if row and str(row.get("seller_user_id")) == str(record.get("owner_ref")) and row.get("active", 1):
            out.append({k: row.get(k) for k in ("id", "subject", "brand", "variant", "price", "currency",
                                                "stock_status", "location_label", "service_area",
                                                "delivery_available", "pickup_available")})
    return out


def _faq(request: Request, listing_id: Any) -> Dict[str, str]:
    import sqlite3

    repo = getattr(request.app.state.container, "product_catalog_repository", None)
    if repo is None or listing_id is None:
        return {}
    try:
        with sqlite3.connect(repo.db_path) as conn:
            rows = conn.execute("SELECT question_key, answer FROM product_faq WHERE product_id=?",
                                (int(listing_id),)).fetchall()
        return {k: a for k, a in rows}
    except Exception:
        return {}


def _visible_in(record: Dict[str, Any]) -> List[str]:
    if record["status"] != "ACTIVE":
        return []
    d = record.get("data") or {}
    places = ["ASKODOX videos feed", "Search results when relevant (video section)", "Seller's videos"]
    if d.get("categories"):
        places.append("Category: " + ", ".join(d["categories"]))
    if d.get("listing_ids"):
        places.append("Linked listings")
    return places


def _event(request: Request, video_id: str, kind: str, area: str = "") -> None:
    with _db(request) as conn:
        conn.execute("INSERT INTO video_events VALUES(?,?,?,?,?)",
                     (_uid("ve_"), video_id, kind, area.strip()[:40] or None, _now()))


# ----------------------------------------------------------- customer --
class AskBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(min_length=1, max_length=500)
    language: str = Field(default="en", max_length=8)
    area: str = Field(default="", max_length=40)


@router.post("/api/videos/native/{video_id}/ask")
def ask_video(video_id: str, body: AskBody, request: Request) -> dict:
    """Any natural question about a published registered video, answered
    only from the analysed video, the seller's listing / FAQ, or honestly
    'not confirmed'. Each answer carries its basis."""
    from app.services import rate_limit

    rate_limit.check(request, "video_commerce_ask", limit=40)
    record = _video(request, video_id)
    user = _optional_user(request)
    if record["status"] != "ACTIVE" and user != record.get("owner_ref"):
        raise HTTPException(status_code=404, detail="Video not found")
    pf = _pf(request)
    ref = "nv_" + video_id
    study = pf.video_study.store.get(ref)
    study_answer = pf.video_study.answer(study, body.question, language=body.language) if study else None
    listings = _listings(request, record)
    first = listings[0] if listings else None
    grounded = vc.ground_answer(body.question, study=study, study_answer=study_answer, listing=first,
                                faq=_faq(request, first and first.get("id")))
    if body.area and first and first.get("location_label") and not grounded["found"] and \
            any(w in body.question.lower() for w in ("near", "available", "deliver", "దగ్గర", "డెలివరీ")):
        grounded = {"found": True, "basis": "askodox", "fact_keys": ["location_label"], "timestamps": [],
                    "answer": f"The seller lists: {first['location_label']}"
                              + (f"; delivers to {first['service_area']}" if first.get("service_area") else "")
                              + f". ASKODOX has not confirmed delivery to {body.area.title()}."}
    _event(request, video_id, "ask", body.area)
    actions = ["ask_seller"]
    if first:
        actions = ["view_listing", "order"] + actions
    if (record.get("data") or {}).get("preorder_enabled"):
        actions.append("pre_order")
    return {"ref": ref, "studied": bool(study), **grounded, "actions": actions, "listing": first}


@router.get("/api/videos/{video_id}/comments")
def list_comments(video_id: str, request: Request) -> dict:
    record = _video(request, video_id)
    user = _optional_user(request)
    owner = user is not None and user == record.get("owner_ref")
    if record["status"] != "ACTIVE" and not owner:
        raise HTTPException(status_code=404, detail="Video not found")
    with _db(request) as conn:
        rows = [dict(r) for r in conn.execute("SELECT * FROM video_comments WHERE video_id=? ORDER BY created_at",
                                              (video_id,)).fetchall()]
    out = []
    for r in rows:
        if r["status"] != "VISIBLE" and not (owner or r["author"] == user):
            continue
        published_reply = r["reply"] if r["reply_status"] in ("ai_answered", "seller_answered") else None
        out.append({"id": r["id"], "kind": r["kind"], "text": r["text"], "mine": r["author"] == user,
                    "reply": published_reply if not owner else r["reply"], "reply_by": r["reply_by"]
                    if published_reply or owner else None, "reply_status": r["reply_status"],
                    "basis": r["basis"], "created_at": r["created_at"], "status": r["status"]})
    return {"items": out}


class CommentBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(min_length=1, max_length=1000)
    kind: str = Field(default="question", pattern="^(question|comment)$")
    language: str = Field(default="en", max_length=8)


@router.post("/api/videos/{video_id}/comments")
def add_comment(video_id: str, body: CommentBody, request: Request) -> dict:
    """A question / comment on a published video. Questions get an AI answer
    only when grounded and the seller allows it (auto) -- or an AI draft the
    seller approves (draft) -- otherwise they wait for the seller."""
    user = _authenticated_app_user(request)
    from app.services import rate_limit
    from app.services.listing_quality import prohibited_terms

    rate_limit.check(request, "video_comment", limit=20)
    record = _published(request, video_id)
    owner = record.get("owner_ref") or ""
    pf = _pf(request)
    mod = vc.moderate(body.text, prohibited_terms(pf.repo))
    reply = basis = evidence = reply_by = None
    status = "none"
    if body.kind == "question" and user != owner and mod["status"] == "VISIBLE":
        study = pf.video_study.store.get("nv_" + video_id)
        study_answer = pf.video_study.answer(study, mod["text"], language=body.language) if study else None
        listings = _listings(request, record)
        first = listings[0] if listings else None
        grounded = vc.ground_answer(mod["text"], study=study, study_answer=study_answer, listing=first,
                                    faq=_faq(request, first and first.get("id")))
        settings = _settings(request, owner)
        plan = vc.reply_plan(settings["mode"], settings["paused"], grounded)
        basis = grounded["basis"]
        evidence = json.dumps({"fact_keys": grounded.get("fact_keys") or [],
                               "timestamps": grounded.get("timestamps") or []})
        if plan == "auto":
            reply, reply_by, status = grounded["answer"], "askodox_ai", "ai_answered"
        elif plan == "draft":
            reply, reply_by, status = grounded["answer"], "askodox_ai_draft", "draft_pending"
        else:
            status = "waiting_seller"
    cid = _uid("vc_")
    with _db(request) as conn:
        conn.execute("INSERT INTO video_comments VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                     (cid, video_id, user, body.kind, mod["text"], mod["status"], ",".join(mod["reasons"]),
                      reply, reply_by, status, basis, evidence, _now(), _now()))
    if body.kind == "question" and status in ("waiting_seller", "draft_pending"):
        _notify_owner(request, owner, video_id)
    return {"id": cid, "status": mod["status"], "reply_status": status,
            "reply": reply if status == "ai_answered" else None,
            "reply_label": "ASKODOX AI answer (from the video / listing)" if status == "ai_answered" else None,
            "basis": basis if status == "ai_answered" else None,
            "notice": {"waiting_seller": "Asked the seller -- you will see their reply here.",
                       "draft_pending": "The seller will confirm the answer shortly."}.get(status)}


def _notify_owner(request: Request, owner: str, video_id: str) -> None:
    try:
        from app.api.routes.platform import platform

        platform(request.app.state.container).repo.record_event(
            "video_question", detail={"owner": owner, "video_id": video_id})
    except Exception:
        pass


class PreorderBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    listing_id: str = Field(default="", max_length=20)
    quantity: float = Field(default=1, gt=0, le=10000)
    variant: str = Field(default="", max_length=80)
    note: str = Field(default="", max_length=300)


@router.post("/api/videos/{video_id}/preorder")
def preorder(video_id: str, body: PreorderBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services.pii_mask import mask_sensitive

    record = _published(request, video_id)
    d = record.get("data") or {}
    if not d.get("preorder_enabled"):
        raise HTTPException(status_code=409, detail="Pre-orders are not open for this video")
    if user == record.get("owner_ref"):
        raise HTTPException(status_code=422, detail="This is your own video")
    pid = _uid("vp_")
    with _db(request) as conn:
        conn.execute("INSERT INTO video_preorders VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                     (pid, video_id, body.listing_id or None, user, record.get("owner_ref"), body.quantity,
                      body.variant or None, mask_sensitive(body.note) or None, "REQUESTED", None, _now(), _now()))
    _event(request, video_id, "request")
    _notify_owner(request, record.get("owner_ref") or "", video_id)
    return {"id": pid, "status": "REQUESTED",
            "message": "Pre-order sent -- not confirmed until the seller accepts.",
            "available_date": d.get("preorder_date"), "expected_price": d.get("preorder_price"),
            "price_confirmed": bool(d.get("preorder_price_confirmed"))}


@router.get("/api/videos/preorders/mine")
def my_preorders(request: Request) -> dict:
    user = _authenticated_app_user(request)
    with _db(request) as conn:
        rows = [dict(r) for r in conn.execute("SELECT * FROM video_preorders WHERE buyer=? ORDER BY created_at DESC",
                                              (user,)).fetchall()]
    return {"items": [{k: v for k, v in r.items() if k not in ("buyer", "owner")}
                      | ({"seller_phone": _phone_of(r["owner"])} if r["status"] == "ACCEPTED" else {})
                      for r in rows]}


class EventBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: str = Field(pattern="^(view|ask|share|request)$")
    area: str = Field(default="", max_length=40)


@router.post("/api/videos/{video_id}/event")
def video_event(video_id: str, body: EventBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "video_event", limit=120)
    _published(request, video_id)
    _event(request, video_id, body.kind, body.area)
    return {"ok": True}


@router.get("/api/videos/{video_id}/share")
def share(video_id: str, request: Request) -> dict:
    record = _published(request, video_id)
    title = (record.get("data") or {}).get("title") or "Video"
    link = f"{_base(request)}/v/{video_id}"
    return {"link": link, "text": f"{title} -- watch on ASKODOX: {link}",
            "note": "Shared only where you choose (Android share sheet); ASKODOX never posts for you."}


@router.get("/v/{video_id}", response_class=HTMLResponse)
def share_page(video_id: str, request: Request) -> HTMLResponse:
    record = _published(request, video_id)
    d = record.get("data") or {}
    title, caption = html.escape(d.get("title") or "ASKODOX video"), html.escape(d.get("description") or "")
    src = html.escape(d.get("url") or "")
    return HTMLResponse(
        "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,"
        f"initial-scale=1'><title>{title}</title><meta property='og:title' content='{title}'>"
        "<style>body{font-family:sans-serif;margin:0;padding:16px;background:#fff;color:#111}"
        "video{width:100%;max-height:70vh;background:#000}</style></head><body>"
        f"<h1 style='font-size:20px'>{title}</h1><video controls playsinline src='{src}'></video>"
        f"<p>{caption}</p><p>Open the ASKODOX app to ask about this video or order.</p></body></html>")


# -------------------------------------------------------------- owner --
@router.post("/api/videos/native/{video_id}/suggest")
def suggest(video_id: str, request: Request) -> dict:
    """Title / caption / category / brand / features / tags suggested ONLY
    from the analysed video (studied first if needed). Never applied
    automatically: the owner reviews and edits."""
    user = _authenticated_app_user(request)
    _owned(request, video_id, user)
    from app.api.routes.native_video import StudyBody, study_native_video
    from app.api.routes.taxonomy import taxonomy

    pf = _pf(request)
    study = pf.video_study.store.get("nv_" + video_id)
    if not study:
        result = study_native_video(video_id, StudyBody(), request)
        if result.get("status") != "ready":
            return {"status": result.get("status"), "message": result.get("message")
                    or "The video could not be analysed; fill the details yourself.", "suggestions": {}}
        study = pf.video_study.store.get("nv_" + video_id) or {}
    tax = taxonomy(request.app.state.container)
    return {"status": "ready", "suggestions": vc.suggestions_from_study(study, tax.resolve),
            "note": "Suggested from what the video shows. Check before submitting."}


class EditBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: Optional[str] = Field(default=None, max_length=140)
    caption: Optional[str] = Field(default=None, max_length=2000)
    category: Optional[str] = Field(default=None, max_length=60)
    tags: Optional[List[str]] = Field(default=None, max_length=20)
    products: Optional[List[str]] = Field(default=None, max_length=10)
    listing_ids: Optional[List[str]] = Field(default=None, max_length=10)
    preorder_enabled: Optional[bool] = None
    preorder_date: Optional[str] = Field(default=None, max_length=10)
    preorder_price: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    preorder_price_confirmed: Optional[bool] = None


@router.patch("/api/videos/mine/{video_id}")
def edit_video(video_id: str, body: EditBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services.pii_mask import mask_sensitive

    record = _owned(request, video_id, user)
    data = dict(record.get("data") or {})
    if body.title is not None:
        data["title"] = mask_sensitive(body.title.strip()) or data.get("title")
    if body.caption is not None:
        data["description"] = mask_sensitive(body.caption.strip())
    if body.category is not None:
        data["categories"] = [body.category.strip().lower()] if body.category.strip() else []
    if body.tags is not None:
        data["keywords"] = [t.strip().lower()[:40] for t in body.tags if t.strip()]
    if body.products is not None:
        data["products"] = [p.strip()[:80] for p in body.products if p.strip()]
    if body.listing_ids is not None:
        repo = getattr(request.app.state.container, "product_catalog_repository", None)
        mine = []
        for raw in body.listing_ids:
            try:
                row = repo.get(int(raw)) if repo is not None else None
            except (TypeError, ValueError):
                row = None
            if not row or str(row.get("seller_user_id")) != user:
                raise HTTPException(status_code=422, detail=f"Listing {raw} is not yours")
            mine.append(str(row["id"]))
        data["listing_ids"] = mine
    for key in ("preorder_enabled", "preorder_date", "preorder_price", "preorder_price_confirmed"):
        value = getattr(body, key)
        if value is not None:
            data[key] = value
    meta_changed = any(getattr(body, k) is not None for k in ("title", "caption", "category", "products"))
    status = "PENDING_REVIEW" if meta_changed and record["status"] == "ACTIVE" else None
    updated = _pf(request).resources.repo.update(video_id, actor=f"user:{user}", action="edit", data=data,
                                                 name=data.get("title"), status=status)
    return _public(updated) | {"listing_ids": data.get("listing_ids") or [],
                               "returned_to_review": status == "PENDING_REVIEW"}


@router.get("/api/videos/mine/{video_id}/analytics")
def analytics(video_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    _owned(request, video_id, user)
    return _analytics(request, [video_id])


def _analytics(request: Request, video_ids: List[str]) -> dict:
    if not video_ids:
        return vc.demand_summary([], [], [])
    marks = ",".join("?" * len(video_ids))
    with _db(request) as conn:
        comments = [dict(r) for r in conn.execute(
            f"SELECT kind, text, reply_status FROM video_comments WHERE video_id IN ({marks})", video_ids)]
        events = [dict(r) for r in conn.execute(
            f"SELECT kind, area FROM video_events WHERE video_id IN ({marks})", video_ids)]
        pre = [dict(r) for r in conn.execute(
            f"SELECT status FROM video_preorders WHERE video_id IN ({marks})", video_ids)]
    return vc.demand_summary(comments, events, pre)


class SettingsBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: str = Field(pattern="^(off|draft|auto)$")
    paused: bool = False


@router.get("/api/videos/ai-settings")
def get_settings(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return _settings(request, user) | {
        "modes": {"off": "AI replies off", "draft": "AI drafts a reply for my approval",
                  "auto": "AI answers safe factual questions automatically"},
        "never_auto": ["payments and refund disputes", "legal claims", "medical / safety claims",
                       "price negotiation", "private details"]}


@router.put("/api/videos/ai-settings")
def put_settings(body: SettingsBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    with _db(request) as conn:
        conn.execute("INSERT INTO video_ai_settings VALUES(?,?,?,?) ON CONFLICT(owner) DO UPDATE SET "
                     "mode=excluded.mode, paused=excluded.paused, updated_at=excluded.updated_at",
                     (user, body.mode, int(body.paused), _now()))
    return _settings(request, user)


@router.get("/api/videos/mine/inbox")
def inbox(request: Request) -> dict:
    """ONE seller inbox for videos: questions waiting for me, AI drafts to
    approve, private messages and pre-orders (no customer phone until accept)."""
    user = _authenticated_app_user(request)
    with _db(request) as conn:
        comments = [dict(r) for r in conn.execute(
            "SELECT c.* FROM video_comments c JOIN pf_records v ON v.id=c.video_id WHERE v.owner_ref=? "
            "AND c.kind='question' ORDER BY c.created_at DESC LIMIT 200", (user,)).fetchall()] \
            if _has_pf(conn) else []
        messages = [dict(r) for r in conn.execute(
            "SELECT * FROM video_messages WHERE owner=? ORDER BY created_at DESC LIMIT 100", (user,)).fetchall()]
        pre = [dict(r) for r in conn.execute(
            "SELECT * FROM video_preorders WHERE owner=? ORDER BY created_at DESC LIMIT 100", (user,)).fetchall()]

    def strip(rows, extra=()):
        return [{k: v for k, v in r.items() if k not in ("author", "sender", "owner", "buyer") + tuple(extra)}
                for r in rows]

    return {"needs_me": strip([c for c in comments if c["reply_status"] == "waiting_seller"]),
            "drafts": strip([c for c in comments if c["reply_status"] == "draft_pending"]),
            "answered": strip([c for c in comments if c["reply_status"] in ("ai_answered", "seller_answered")]),
            "messages": strip(messages),
            "pre_orders": [{k: v for k, v in p.items() if k not in ("buyer", "owner")}
                           | ({"buyer_phone": _phone_of(p["buyer"])} if p["status"] == "ACCEPTED" else {})
                           for p in pre],
            "settings": _settings(request, user)}


def _has_pf(conn) -> bool:
    return bool(conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='pf_records'").fetchone())


def _owned_comment(request: Request, comment_id: str, user: str) -> Dict[str, Any]:
    with _db(request) as conn:
        row = conn.execute("SELECT * FROM video_comments WHERE id=?", (comment_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    _owned(request, row["video_id"], user)
    return dict(row)


class ReplyBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(min_length=1, max_length=1000)


@router.post("/api/videos/comments/{comment_id}/reply")
def seller_reply(comment_id: str, body: ReplyBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services.pii_mask import mask_sensitive

    _owned_comment(request, comment_id, user)
    with _db(request) as conn:
        conn.execute("UPDATE video_comments SET reply=?, reply_by='seller', reply_status='seller_answered', "
                     "basis='seller', updated_at=? WHERE id=?", (mask_sensitive(body.text.strip()), _now(), comment_id))
    return {"id": comment_id, "reply_status": "seller_answered"}


@router.post("/api/videos/comments/{comment_id}/approve")
def approve_draft(comment_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    row = _owned_comment(request, comment_id, user)
    if row["reply_status"] != "draft_pending":
        raise HTTPException(status_code=409, detail="No AI draft to approve")
    with _db(request) as conn:
        conn.execute("UPDATE video_comments SET reply_by='askodox_ai', reply_status='ai_answered', updated_at=? "
                     "WHERE id=?", (_now(), comment_id))
    return {"id": comment_id, "reply_status": "ai_answered"}


class DecideBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    accept: bool
    note: str = Field(default="", max_length=300)


@router.post("/api/videos/preorders/{preorder_id}/decide")
def decide_preorder(preorder_id: str, body: DecideBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    from app.services.pii_mask import mask_sensitive

    with _db(request) as conn:
        row = conn.execute("SELECT * FROM video_preorders WHERE id=?", (preorder_id,)).fetchone()
        if not row or row["owner"] != user:
            raise HTTPException(status_code=404, detail="Not found")
        if row["status"] != "REQUESTED":
            raise HTTPException(status_code=409, detail="Already decided")
        status = "ACCEPTED" if body.accept else "DECLINED"
        conn.execute("UPDATE video_preorders SET status=?, seller_note=?, updated_at=? WHERE id=?",
                     (status, mask_sensitive(body.note) or None, _now(), preorder_id))
    out = {"id": preorder_id, "status": status}
    if body.accept:
        out["buyer_phone"] = _phone_of(row["buyer"])
    return out


# -------------------------------------------------------------- staff --
@router.get("/admin/cc/videos/comments")
def staff_comments(request: Request, status: str = "FLAGGED") -> dict:
    from app.api.routes.command_center import _require

    _require(request, "content:view")
    with _db(request) as conn:
        rows = [dict(r) for r in conn.execute(
            "SELECT id, video_id, kind, text, status, reasons, reply, reply_by, reply_status, created_at "
            "FROM video_comments WHERE status=? ORDER BY created_at DESC LIMIT 200", (status.upper(),)).fetchall()]
    return {"items": rows}


class ModerateBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: str = Field(pattern="^(VISIBLE|HIDDEN)$")


@router.post("/admin/cc/videos/comments/{comment_id}")
def staff_moderate(comment_id: str, body: ModerateBody, request: Request) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "content:manage")
    with _db(request) as conn:
        conn.execute("UPDATE video_comments SET status=?, updated_at=? WHERE id=?", (body.status, _now(), comment_id))
    return {"id": comment_id, "status": body.status}


@router.get("/admin/cc/videos/analytics")
def staff_analytics(request: Request) -> dict:
    from app.api.routes.command_center import _require

    _require(request, "content:view")
    ids = [r["id"] for r in _pf(request).resources.repo.list("videos")
           if (r.get("data") or {}).get("platform") == "askodox"]
    return _analytics(request, ids) | {"videos": len(ids)}


# Registered last: the static /api/videos/... paths above must win.
@router.get("/api/videos/native/{video_id}")
def video_detail(video_id: str, request: Request) -> dict:
    record = _video(request, video_id)
    user = _optional_user(request)
    if record["status"] != "ACTIVE" and user != record.get("owner_ref"):
        raise HTTPException(status_code=404, detail="Video not found")
    d = record.get("data") or {}
    out = _public(record) | {"listings": _listings(request, record), "visible_in": _visible_in(record),
                             "preorder": {"enabled": bool(d.get("preorder_enabled")),
                                          "available_date": d.get("preorder_date"),
                                          "expected_price": d.get("preorder_price"),
                                          "price_confirmed": bool(d.get("preorder_price_confirmed"))},
                             "tags": d.get("keywords") or [], "mine": user == record.get("owner_ref")}
    return out
