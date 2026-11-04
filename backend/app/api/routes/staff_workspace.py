"""Staff Workspace API -- the SAME backend, permissions and audit log as the
Command Center, shaped for fast work from a phone, tablet or laptop.

Sign-in (no extra passwords):
  POST /api/staff/session          app session (OTP-verified number) -> 12 h staff session
  GET  /api/staff/me               is this app user staff? (name / role only)
  POST /api/staff/handoff          one-time 2-minute code to open the workspace in a browser / WebView
  POST /api/staff/handoff/redeem   code -> staff session

Work (any Command Center credential; each route checks its own permission):
  GET  /admin/cc/workspace/me                  sections + counts this person may see
  POST /admin/cc/workspace/import              paste ONE link -> source, duplicates, auto-filled fields
                                               (html = the page as the staff phone read it)
  POST /admin/cc/workspace/uploads/from-url    keep a page photo as our own copy (for reels)
  POST /admin/cc/workspace/import/bulk         up to 50 links (detect + duplicates; details for the first 10)
  POST /admin/cc/workspace/items               save as draft / submit / publish (if allowed)
  GET  /admin/cc/workspace/items               my items (reviewers: all) by status / type
  POST /admin/cc/workspace/items/{id}/review   submit | approve | reject | pause | resume | expire
  POST /admin/cc/workspace/uploads             photo from camera / gallery (jpeg / png / webp, 5 MB)
  GET  /media/staff/{name}                     uploaded photo (public, for result cards)
  GET  /admin/cc/workspace/tasks               my tasks (assigned to me or my role)
  POST /admin/cc/workspace/tasks/from-demand   route an opportunity to staff / a role (deduplicated)
  GET  /admin/cc/workspace/analytics           items, staff activity, source health, pending work
"""
from __future__ import annotations

import hashlib
import os
import re
from typing import Any

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.api.routes.affiliate_catalog import _audit, _brief, catalog
from app.api.routes.command_center import _principal, command_center
from app.services import affiliate_catalog as ac
from app.services import governance as gov
from app.services import staff_sessions

router = APIRouter(tags=["staff-workspace"])

# Which grant lets a person create each kind of item (manage implies create).
TYPE_PERMISSION = {
    "product": "affiliate_products:create", "link": "affiliate_products:create", "service": "affiliate_products:create",
    "offer": "offers:create", "coupon": "offers:create",
    "news": "content:create", "video": "content:create", "content": "content:create",
    # Partner campaigns are commercial: the same grant as other offers.
    "app_install": "offers:create", "referral": "offers:create", "financial_offer": "offers:create",
}
REVIEW_ACTIONS = {
    # action: (allowed from, to, needs)
    "submit": (("DRAFT",), None, "create"),
    "approve": (("NEEDS_REVIEW", "APPROVED", "DRAFT"), "LIVE", "approve"),
    "reject": (("NEEDS_REVIEW", "APPROVED"), "DRAFT", "approve"),
    "pause": (("LIVE",), "PAUSED", "create"),
    "resume": (("PAUSED",), "LIVE", "approve"),
    "expire": (("LIVE", "PAUSED", "APPROVED"), "EXPIRED", "create"),
}
_IMAGE_MAGIC = {b"\xff\xd8\xff": ".jpg", b"\x89PNG": ".png", b"RIFF": ".webp"}
MAX_UPLOAD = 5 * 1024 * 1024


def _can(principal: dict, permission: str) -> bool:
    return gov.has_permission(principal["permissions"], permission)


def _types(principal: dict) -> list[str]:
    return [t for t, perm in TYPE_PERMISSION.items() if _can(principal, perm)]


def _workspace(request: Request) -> dict:
    principal = _principal(request)
    if not (_can(principal, "workspace:view") or gov.is_super(principal)):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs workspace:view)")
    return principal


def _can_publish(principal: dict) -> bool:
    return _can(principal, "workspace:approve") or gov.is_super(principal)


# --------------------------------------------------------------- sign in --

def _app_user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


def _session_payload(request: Request, staff: dict) -> dict:
    secret = request.app.state.container.settings.session_token_secret
    return {"session": staff_sessions.issue(staff["id"], secret), "expires_in": staff_sessions.SESSION_SECONDS,
            "staff": {"id": staff["id"], "name": staff["name"], "role": staff["role"]},
            "permissions": sorted(staff["permissions"])}


@router.get("/api/staff/me")
def staff_me(request: Request) -> dict:
    staff = command_center(request.app.state.container).staff_by_app_user(_app_user(request))
    return {"staff": bool(staff), **({"name": staff["name"], "role": staff["role"]} if staff else {})}


@router.post("/api/staff/session")
def staff_session(request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "staff_session", limit=20)
    staff = command_center(request.app.state.container).staff_by_app_user(_app_user(request))
    if not staff:
        raise HTTPException(status_code=403, detail="This number is not linked to an active staff member")
    command_center(request.app.state.container).audit(f"staff-{staff['id']}", "staff_signed_in", "staff",
                                                      staff["id"], None, {"via": "app_otp"}, role=staff["role"])
    return _session_payload(request, staff)


@router.post("/api/staff/handoff")
def staff_handoff(request: Request) -> dict:
    staff = command_center(request.app.state.container).staff_by_app_user(_app_user(request))
    if not staff:
        raise HTTPException(status_code=403, detail="This number is not linked to an active staff member")
    return {"code": staff_sessions.handoff_code(staff["id"]), "expires_in": staff_sessions.HANDOFF_SECONDS}


class RedeemBody(BaseModel):
    code: str = Field(min_length=10, max_length=64)


@router.post("/api/staff/handoff/redeem")
def staff_handoff_redeem(body: RedeemBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "staff_handoff", limit=20)
    staff_id = staff_sessions.redeem(body.code)
    staff = command_center(request.app.state.container).get_staff(staff_id) if staff_id else None
    if not staff or not staff["active"]:
        raise HTTPException(status_code=401, detail="This sign-in link expired -- open the workspace again")
    return _session_payload(request, staff)


# ------------------------------------------------------------------ home --

@router.get("/admin/cc/workspace/me")
def workspace_me(request: Request) -> dict:
    principal = _workspace(request)
    container = request.app.state.container
    sections = {
        "add": bool(_types(principal)),
        "review": _can_publish(principal),
        "items": bool(_types(principal)) or _can_publish(principal),
        "sources": _can(principal, "sources:view"),
        "tasks": _can(principal, "tasks:view"),
        "support": _can(principal, "support:view"),
        "feedback": _can(principal, "feedback:view"),
        "demand": _can(principal, "demand:view"),
        "analytics": _can(principal, "analytics:view") or _can_publish(principal),
    }
    counts: dict[str, int] = {}
    store = catalog(container)
    with store._connect() as conn:
        if sections["review"]:
            counts["review"] = conn.execute("SELECT COUNT(*) FROM affiliate_products WHERE deleted_at IS NULL AND "
                                            "review_status='NEEDS_REVIEW'").fetchone()[0]
        counts["my_drafts"] = conn.execute("SELECT COUNT(*) FROM affiliate_products WHERE deleted_at IS NULL AND "
                                           "review_status='DRAFT' AND submitted_by=?", (principal["id"],)).fetchone()[0]
    if sections["tasks"]:
        counts["tasks"] = len(_my_tasks(request, principal))
    can_assign = _can(principal, "tasks:create")
    team = [{"id": str(m["id"]), "name": m["name"], "role": m["role"]}
            for m in command_center(container).list_staff() if m.get("active")] if can_assign else []
    return {"id": principal["id"], "name": principal["name"], "role": principal["role"], "sections": sections,
            "item_types": _types(principal), "can_publish": _can_publish(principal), "counts": counts,
            "can_assign": can_assign, "team": team}


# ---------------------------------------------------------------- import --

class ImportBody(BaseModel):
    url: str = Field(min_length=8, max_length=2000)
    item_type: str = Field(default="product", max_length=20)
    # Read by the staff member's PHONE (ASKODOX app, Staff Workspace): stores
    # such as Meesho refuse our server, not a phone. Parsed only -- the server
    # never fetches anything for it.
    html: str | None = Field(default=None, max_length=2_000_000)
    final_url: str | None = Field(default=None, max_length=2000)

STORE_BLOCKED_HINT = ("This store does not let our server read its pages. Open Staff Workspace inside the "
                      "ASKODOX app (Profile → Staff Workspace) and paste the link there -- your phone reads the "
                      "page and everything fills in (or enter the details by hand). / ఈ store మన server ని page చదవనివ్వదు. ASKODOX app లో "
                      "Staff Workspace తెరిచి link పెట్టండి -- phone page చదివి అన్నీ నింపుతుంది.")


def _detect(request: Request, url: str) -> dict:
    from app.api.routes.universal_deals import _universal_sources
    from app.services.universal_sources import detect_source

    platform = ac.detect_platform(url)
    found = None
    try:
        found = detect_source(_universal_sources(request.app.state.container).records(active_only=False), url)
    except Exception:
        pass
    if found:
        return {"kind": "source", "id": found["id"], "name": found.get("name"),
                "connector": found.get("connector"), "monetization": found.get("monetization")}
    if platform != "other":
        return {"kind": "marketplace", "id": platform, "name": ac.PLATFORMS[platform]["name"]}
    return {"kind": "unknown", "id": None, "name": ac._host(url) or None,
            "note": "Not a configured source yet -- it can still be saved; an admin can add the source later."}


def _same_store(a: str, b: str) -> bool:
    return bool(a) and ac.detect_platform(a) == ac.detect_platform(b) and ac.detect_platform(a) != "other"


def _may_link(principal: dict) -> bool:
    return _can(principal, "affiliate_products:links") or gov.is_super(principal)


def _import_one(request: Request, url: str, *, details: bool, html: str | None = None,
                final_url: str | None = None, may_link: bool = True) -> dict:
    # Shared text from a store app ("Check this out https://...") -> just the link.
    found = re.search(r"https://[^\s\"'<>]+", url or "")
    if found:
        url = found.group(0)
    try:
        clean = ac.https_url(url)
    except ValueError:
        clean = ""
    if not clean:
        return {"url": url, "ok": False, "error": "Only https links can be added / https link మాత్రమే పెట్టండి"}
    store = catalog(request.app.state.container)
    out: dict[str, Any] = {"url": clean, "ok": True, "source": _detect(request, clean),
                           "duplicates": store.duplicates(clean)}
    if details:
        fetch = getattr(request.app.state.container, "affiliate_page_fetch", None)
        page_url = clean
        if html:
            fetch = lambda _url: html  # noqa: E731 -- the phone already read it
            try:
                landed = ac.https_url(final_url or "")
            except ValueError:
                landed = ""
            # A short / invite link (af_invite, msho.in) lands on the product page:
            # read the product page, keep the pasted link as the commission link.
            if landed and landed != clean and _same_store(landed, clean):
                page_url = landed
        try:
            from app.services import affiliate_providers

            # Same extractor as the Affiliate Hub: schema.org + the store's own
            # embedded product data (Meesho __NEXT_DATA__: price, MRP, photos, seller).
            meta = affiliate_providers.extract(page_url, fetch=fetch)
        except ValueError as error:
            return {**out, "ok": False, "error": str(error)}
        fields = dict(meta.get("fields") or {})
        if page_url != clean:
            fields["affiliate_url"] = clean  # the pasted (commission) link
        if not may_link:
            fields.pop("affiliate_url", None)  # saving one needs affiliate_products:links
        status = meta.get("status")
        note = meta.get("note")
        if status == "unavailable" and not html:
            note = STORE_BLOCKED_HINT
        if status == "nothing_found" and fields.get("title"):
            status = "ok"  # the store's embedded data had it
            note = "Filled from the store's page -- check and save. / Store page నుండి నింపాం -- చూసి save చేయండి."
        out.update(fields=fields, field_status=ac.field_status(fields), status=status, note=note,
                   suggested_stock=meta.get("suggested_stock"), read_by="phone" if html else "server")
    return out


@router.post("/admin/cc/workspace/import")
def import_link(body: ImportBody, request: Request) -> dict:
    principal = _workspace(request)
    if body.item_type not in ac.ITEM_TYPES or body.item_type not in _types(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (cannot add {body.item_type} items)")
    from app.services import rate_limit

    rate_limit.check(request, "workspace_import", limit=60)
    return _import_one(request, body.url, details=True, html=body.html, final_url=body.final_url,
                       may_link=_may_link(principal))


class DescribeBody(BaseModel):
    fields: dict[str, Any] = Field(default_factory=dict)
    photos: list[str] = Field(default_factory=list, max_length=6)


def _photo_facts(request: Request, photos: list[str]) -> list[str]:
    """What our own uploaded staff photos show (same image brain as chat)."""
    from app.services.attachment_facts import attachment_facts

    service = getattr(request.app.state.container, "universal_image_service", None)
    if service is None:
        return []
    out = []
    for ref in photos[:2]:
        name = ref.rsplit("/", 1)[-1]
        if not re.fullmatch(r"[0-9a-f]{32}\.(jpg|png|webp)", name):
            continue  # only photos uploaded here, never an arbitrary URL
        path = os.path.join(_upload_dir(request), name)
        if not os.path.exists(path):
            continue
        mime = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}[name.rsplit(".", 1)[1]]
        try:
            with open(path, "rb") as handle:
                analysis = service.analyze(handle.read(), mime_type=mime)
            facts = attachment_facts("image", analysis or {})
        except Exception:
            facts = ""
        if facts:
            out.append(str(facts)[:600])
    return out


@router.post("/admin/cc/workspace/describe")
def describe_item(body: DescribeBody, request: Request) -> dict:
    """AI draft description (English + Telugu-English) from page facts and the
    item's photos only; staff review before saving (product_description.py)."""
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    from app.services import product_description, rate_limit

    rate_limit.check(request, "workspace_describe", limit=60)
    brain = request.app.state.container.universal_ai_assistant_service
    return product_description.describe(body.fields, write=lambda text: brain.write_text(text, max_tokens=900),
                                        photo_facts=_photo_facts(request, body.photos))


class BulkImportBody(BaseModel):
    urls: list[str] = Field(min_length=1, max_length=50)
    item_type: str = Field(default="product", max_length=20)


@router.post("/admin/cc/workspace/import/bulk")
def import_bulk(body: BulkImportBody, request: Request) -> dict:
    principal = _workspace(request)
    if body.item_type not in _types(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (cannot add {body.item_type} items)")
    from app.services import rate_limit

    rate_limit.check(request, "workspace_import", limit=60)
    urls = list(dict.fromkeys(u.strip() for u in body.urls if u.strip()))
    may_link = _may_link(principal)
    return {"items": [_import_one(request, u, details=i < 10, may_link=may_link) for i, u in enumerate(urls)]}


# ----------------------------------------------------------------- items --

class ItemBody(BaseModel):
    item_type: str = Field(default="product", max_length=20)
    fields: dict[str, Any]
    action: str = Field(default="submit", pattern="^(draft|submit)$")
    stock_status: str | None = None
    commission_status: str | None = None


@router.post("/admin/cc/workspace/items")
def create_item(body: ItemBody, request: Request) -> dict:
    principal = _workspace(request)
    if body.item_type not in ac.ITEM_TYPES or body.item_type not in _types(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (cannot add {body.item_type} items)")
    if body.fields.get("affiliate_url") and not _can(principal, "affiliate_products:links"):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate_products:links)")
    if body.commission_status and not _can(principal, "affiliate_products:commission"):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs affiliate_products:commission)")
    fields = {k: v for k, v in body.fields.items() if k in ac.EDITABLE_FIELDS}
    fields["item_type"] = body.item_type
    review = "DRAFT" if body.action == "draft" else ("LIVE" if _can_publish(principal) else "NEEDS_REVIEW")
    try:
        item = catalog(request.app.state.container).create(
            fields, actor=principal["id"], check_source="manual", stock_status=body.stock_status,
            commission_status=body.commission_status, review_status=review)
    except (ValueError, LookupError) as error:
        raise HTTPException(status_code=409 if "Already" in str(error) or "already" in str(error) else 400,
                            detail=str(error))
    _audit(request, principal, "workspace_create", item["id"], None, {**(_brief(item) or {}), "review": review})
    return {"item": item, "review_status": review}


@router.get("/admin/cc/workspace/items")
def list_items(request: Request, status: str = "", item_type: str = "", q: str = "", mine: bool = False,
               limit: int = 100) -> dict:
    principal = _workspace(request)
    sql = "SELECT * FROM affiliate_products WHERE deleted_at IS NULL"
    args: list[Any] = []
    if status:
        sql += " AND review_status=?"
        args.append(status.upper())
    allowed = _types(principal)
    if item_type:
        if item_type not in allowed and not _can_publish(principal):
            raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
        sql += " AND item_type=?"
        args.append(item_type)
    elif not _can_publish(principal):
        sql += " AND item_type IN (" + ",".join("?" * len(allowed or ["-"])) + ")"
        args.extend(allowed or ["-"])
    if mine or not _can_publish(principal):
        sql += " AND submitted_by=?"
        args.append(principal["id"])
    if q:
        sql += " AND LOWER(title) LIKE ?"
        args.append(f"%{q.lower()[:80]}%")
    store = catalog(request.app.state.container)
    with store._connect() as conn:
        rows = conn.execute(sql + " ORDER BY id DESC LIMIT ?", [*args, max(1, min(int(limit), 300))]).fetchall()
    return {"items": [ac._public(dict(r)) for r in rows]}


class ReviewBody(BaseModel):
    action: str = Field(pattern="^(submit|approve|reject|pause|resume|expire)$")
    note: str = Field(default="", max_length=500)


@router.post("/admin/cc/workspace/items/{item_id}/review")
def review_item(item_id: int, body: ReviewBody, request: Request) -> dict:
    principal = _workspace(request)
    store = catalog(request.app.state.container)
    item = store.get(item_id)
    if not item or item.get("deleted_at"):
        raise HTTPException(status_code=404, detail="Item not found")
    allowed_from, to, needs = REVIEW_ACTIONS[body.action]
    if needs == "approve" and not _can_publish(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs workspace:approve)")
    if needs == "create":
        owner = item.get("submitted_by") == principal["id"]
        if not (_can_publish(principal) or (owner and item.get("item_type") in _types(principal))):
            raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    if item.get("review_status") not in allowed_from:
        raise HTTPException(status_code=409, detail=f"Cannot {body.action} an item that is {item.get('review_status')}")
    if body.action == "submit":
        to = "LIVE" if _can_publish(principal) else "NEEDS_REVIEW"
    if body.action == "reject" and not body.note.strip():
        raise HTTPException(status_code=422, detail="Say what needs fixing")
    updated = store.set_review(item_id, to, actor=principal["id"], note=body.note)
    _audit(request, principal, f"workspace_{body.action}", item_id, {"review_status": item.get("review_status")},
           {"review_status": to, "note": body.note})
    return {"item": updated}


@router.post("/admin/cc/workspace/uploads")
async def upload_photo(request: Request, file: UploadFile = File(...)) -> dict:
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    data = await file.read(MAX_UPLOAD + 1)
    return _save_photo(request, data)


class PhotoFromUrlBody(BaseModel):
    url: str = Field(min_length=12, max_length=2000)


@router.post("/admin/cc/workspace/uploads/from-url")
def upload_photo_from_url(body: PhotoFromUrlBody, request: Request) -> dict:
    """Keep a product page's photo as our own copy (so a reel can be made
    from it). Public https images only, 5 MB, real JPEG / PNG / WebP."""
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    from app.services import rate_limit

    rate_limit.check(request, "workspace_photo_url", limit=120)
    fetch = getattr(request.app.state.container, "affiliate_image_fetch", None) or ac.fetch_image
    try:
        data = fetch(body.url)
    except Exception as error:
        raise HTTPException(status_code=422, detail=f"Could not copy that photo ({type(error).__name__})") from None
    return _save_photo(request, data)


def _save_photo(request: Request, data: bytes) -> dict:
    if len(data) > MAX_UPLOAD:
        raise HTTPException(status_code=413, detail="Photos up to 5 MB")
    ext = next((e for magic, e in _IMAGE_MAGIC.items() if data.startswith(magic)), None)
    if ext is None or (ext == ".webp" and data[8:12] != b"WEBP"):
        raise HTTPException(status_code=415, detail="JPEG, PNG or WebP photos only")
    name = hashlib.sha256(data).hexdigest()[:32] + ext
    folder = _upload_dir(request)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "wb") as handle:
        handle.write(data)
    base = str(request.base_url).rstrip("/").replace("http://", "https://")
    return {"url": f"{base}/media/staff/{name}", "name": name}


def _upload_dir(request: Request) -> str:
    return os.path.join(os.path.dirname(os.path.abspath(request.app.state.container.settings.database_path)),
                        "staff_uploads")


@router.get("/media/staff/{name}")
def staff_media(name: str, request: Request) -> FileResponse:
    if not re.fullmatch(r"[0-9a-f]{32}\.(jpg|png|webp)", name):
        raise HTTPException(status_code=404, detail="Not found")
    path = os.path.join(_upload_dir(request), name)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, headers={"Cache-Control": "public, max-age=86400",
                                       "X-Content-Type-Options": "nosniff"})


# ----------------------------------------------------------------- tasks --

ROLE_TO_TASK_ROLE = {"affiliate_product_staff": "affiliate_staff", "affiliate_catalog_staff": "affiliate_staff"}


def _pf(request: Request):
    from app.api.routes.platform import platform

    return platform(request.app.state.container)


def _my_tasks(request: Request, principal: dict) -> list[dict]:
    role = ROLE_TO_TASK_ROLE.get(principal["role"], principal["role"])
    out = []
    for record in _pf(request).repo.list("staff_tasks"):
        if record.get("archived") or record.get("status") not in ("OPEN", "IN_PROGRESS", "WAITING"):
            continue
        data = record.get("data") or {}
        staff = str(data.get("assignee_staff") or "")
        if staff and staff in (principal["id"], principal["id"].removeprefix("staff-")):
            out.append(record)
        elif not staff and data.get("assignee_role") in (role, "any"):
            out.append(record)
    return out


@router.get("/admin/cc/workspace/tasks")
def my_tasks(request: Request) -> dict:
    principal = _workspace(request)
    if not _can(principal, "tasks:view"):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs tasks:view)")
    return {"items": _my_tasks(request, principal)}


@router.post("/admin/cc/workspace/tasks/{task_id}/{action}")
def update_my_task(task_id: str, action: str, request: Request) -> dict:
    """The assignee (or a tasks manager) moves a task along -- staff never
    need tasks:manage just to mark their own work done."""
    principal = _workspace(request)
    if action not in ("start", "wait", "done"):
        raise HTTPException(status_code=404, detail="Unknown action")
    pf = _pf(request)
    mine = any(t["id"] == task_id for t in _my_tasks(request, principal))
    if not (mine or _can(principal, "tasks:manage")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (not your task)")
    try:
        record = pf.resources.action("staff_tasks", task_id, action, actor=principal["id"])
    except Exception as error:
        raise HTTPException(status_code=409, detail=str(error))
    return {"task": record}


class DemandTaskBody(BaseModel):
    title: str = Field(min_length=3, max_length=200)
    why: str = Field(default="", max_length=2000)
    expected_action: str = Field(default="", max_length=2000)
    priority: str = Field(default="normal", pattern="^(?i:low|normal|high|urgent)$")
    assignee_staff: str = Field(default="", max_length=40)
    assignee_role: str = Field(default="", max_length=40)
    region: str = Field(default="", max_length=120)
    dedupe_key: str = Field(min_length=3, max_length=200)
    evidence: dict[str, Any] = Field(default_factory=dict)
    kind: str = Field(default="demand_opportunity", max_length=40)


def create_task_once(pf: Any, data: dict[str, Any], *, actor: str) -> tuple[dict, bool]:
    """One open task per dedupe key -- repeated demand never spams staff."""
    key = str(data.get("dedupe_key") or "")
    for record in pf.repo.list("staff_tasks"):
        if (record.get("data") or {}).get("dedupe_key") == key and record.get("status") in (
                "OPEN", "IN_PROGRESS", "WAITING") and not record.get("archived"):
            return record, False
    return pf.resources.create("staff_tasks", {k: v for k, v in data.items() if v not in (None, "")}, actor=actor), True


def task_alert_targets(staff: list[dict[str, Any]], data: dict[str, Any]) -> list[str]:
    """App accounts to alert for a new task: the assigned staff member, or every
    active staff member with the assigned role. Staff without a linked app
    account (``app_user_id``) are skipped -- they still see the task in the
    workspace."""
    person = str(data.get("assignee_staff") or "").removeprefix("staff-")
    role = str(data.get("assignee_role") or "").strip().lower()
    out = []
    for s in staff:
        if not s.get("active") or not str(s.get("app_user_id") or "").startswith("app-"):
            continue
        if (person and str(s.get("id")) == person) or (not person and role and str(s.get("role") or "").lower() == role):
            out.append(str(s["app_user_id"]))
    return sorted(set(out))


def alert_new_task(container: Any, record: dict[str, Any]) -> int:
    """Push a new task to its staff's phones, once per task. Best effort: a
    push failure never fails the task (it is already saved)."""
    try:
        from app.services.push_service import push_service

        data = record.get("data") or {}
        title = str(data.get("title") or "New task")[:120]
        notify = push_service(container).notify
        sent = 0
        for user_id in task_alert_targets(command_center(container).list_staff(), data):
            sent += int(notify(user_id, title="ASKODOX: మీకు కొత్త పని", body=title, route="/profile",
                               event_key=f"staff_task:{record.get('id')}") or 0)
        return sent
    except Exception:
        return 0


@router.post("/admin/cc/workspace/tasks/from-demand")
def task_from_demand(body: DemandTaskBody, request: Request) -> dict:
    principal = _principal(request)
    if not (_can(principal, "tasks:create") or _can(principal, "demand:notify")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs tasks:create)")
    if not (body.assignee_staff or body.assignee_role):
        raise HTTPException(status_code=422, detail="Assign the task to a staff member or a role")
    data = body.model_dump()
    data["priority"] = data["priority"].lower()
    record, created = create_task_once(_pf(request), data, actor=principal["id"])
    alerted = alert_new_task(request.app.state.container, record) if created else 0
    return {"task": record, "created": created, "alerted": alerted}


class LinkBatchBody(BaseModel):
    links: list[str] = Field(min_length=1, max_length=500)
    # Optional commission / affiliate link per product link (same order).
    affiliate_links: list[str] = Field(default_factory=list, max_length=500)
    assignees: list[str] = Field(min_length=1, max_length=50)  # staff ids
    per_task: int = Field(default=25, ge=1, le=100)
    note: str = Field(default="", max_length=500)


@router.post("/admin/cc/workspace/tasks/batch-links")
def task_batch_links(body: LinkBatchBody, request: Request) -> dict:
    """Owner / manager pastes many product links (+ commission links); they are
    split into tasks and shared round-robin between the chosen staff. Each task
    lists its links; staff open one, the page fills itself, AI writes the
    description, staff check and save. Re-sending the same batch never
    duplicates tasks."""
    principal = _principal(request)
    if not _can(principal, "tasks:create"):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs tasks:create)")
    pairs, seen = [], set()
    for i, raw in enumerate(body.links):
        url = raw.strip()
        if not url.startswith("https://") or ac.canonical_key(url) in seen:
            continue
        seen.add(ac.canonical_key(url))
        aff = body.affiliate_links[i].strip() if i < len(body.affiliate_links) else ""
        pairs.append({"url": url, **({"affiliate_url": aff} if aff.startswith("https://") else {})})
    if not pairs:
        raise HTTPException(status_code=422, detail="No https product links found")
    cc = command_center(request.app.state.container)
    staff = {str(s["id"]): s for s in cc.list_staff() if s.get("active")}
    assignees = [a.removeprefix("staff-") for a in body.assignees if a.removeprefix("staff-") in staff]
    if not assignees:
        raise HTTPException(status_code=422, detail="Choose at least one active staff member")
    batch = hashlib.sha256("|".join(p["url"] for p in pairs).encode()).hexdigest()[:10]
    chunks = [pairs[i:i + body.per_task] for i in range(0, len(pairs), body.per_task)]
    pf = _pf(request)
    tasks, created = [], 0
    for n, chunk in enumerate(chunks):
        who = assignees[n % len(assignees)]
        record, fresh = create_task_once(pf, {
            "title": f"Add {len(chunk)} products ({n + 1}/{len(chunks)})",
            "why": body.note or "Product links to add to ASKODOX results",
            "expected_action": "Open each link: details fill themselves, press AI description, check, then save.",
            "priority": "normal", "assignee_staff": who, "dedupe_key": f"links:{batch}:{n}",
            "kind": "add_products", "evidence": {"batch": batch, "links": chunk}}, actor=principal["id"])
        created += int(fresh)
        alerted = alert_new_task(request.app.state.container, record) if fresh else 0
        tasks.append({"id": record["id"], "assignee": staff[who]["name"], "links": len(chunk), "alerted": alerted})
    return {"batch": batch, "links": len(pairs), "tasks": tasks, "created": created}


@router.get("/admin/cc/workspace/tasks/batch-links/{batch}")
def task_batch_progress(batch: str, request: Request) -> dict:
    """How far each staff member got: a link counts as done once an item with
    the same product (canonical key) exists in the item store."""
    principal = _principal(request)
    if not (_can(principal, "tasks:view") or _can(principal, "tasks:create")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs tasks:view)")
    store = catalog(request.app.state.container)
    with store._connect() as conn:
        added = {r[0] for r in conn.execute("SELECT canonical_key FROM affiliate_products WHERE deleted_at IS NULL "
                                            "AND canonical_key IS NOT NULL")}
    out = []
    for record in _pf(request).repo.list("staff_tasks"):
        data = record.get("data") or {}
        evidence = data.get("evidence") or {}
        if data.get("kind") != "add_products" or evidence.get("batch") != batch:
            continue
        links = evidence.get("links") or []
        done = sum(1 for link in links if ac.canonical_key(link.get("url")) in added)
        out.append({"task": record["id"], "status": record.get("status"), "assignee_staff": data.get("assignee_staff"),
                    "links": len(links), "added": done})
    if not out:
        raise HTTPException(status_code=404, detail="No such batch")
    return {"batch": batch, "tasks": out, "links": sum(t["links"] for t in out), "added": sum(t["added"] for t in out)}


# ------------------------------------------------------------- analytics --

@router.get("/admin/cc/workspace/analytics")
def workspace_analytics(request: Request) -> dict:
    principal = _workspace(request)
    if not (_can(principal, "analytics:view") or _can_publish(principal)):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs analytics:view)")
    store = catalog(request.app.state.container)
    with store._connect() as conn:
        by_status = {r[0]: r[1] for r in conn.execute("SELECT review_status, COUNT(*) FROM affiliate_products WHERE "
                                                      "deleted_at IS NULL GROUP BY review_status")}
        by_type = {r[0]: r[1] for r in conn.execute("SELECT item_type, COUNT(*) FROM affiliate_products WHERE "
                                                    "deleted_at IS NULL GROUP BY item_type")}
        oos = conn.execute("SELECT product_id, COUNT(*) n FROM affiliate_product_history WHERE action='stock' AND "
                           "changes_json LIKE '%OUT_OF_STOCK%' GROUP BY product_id ORDER BY n DESC LIMIT 10").fetchall()
        staff = conn.execute("SELECT actor, action, COUNT(*) n FROM affiliate_product_history WHERE at >= "
                             "datetime('now','-30 days') GROUP BY actor, action ORDER BY n DESC LIMIT 50").fetchall()
    from app.api.routes.universal_deals import _universal_sources

    try:
        sources = _universal_sources(request.app.state.container).overview()
    except Exception:
        sources = []
    tasks = [r for r in _pf(request).repo.list("staff_tasks") if r.get("status") in ("OPEN", "IN_PROGRESS", "WAITING")]
    return {"items": {"by_status": by_status, "by_type": by_type},
            "repeatedly_out_of_stock": [{"item": r["product_id"], "times": r["n"]} for r in oos],
            "staff_activity_30d": [{"actor": r["actor"], "action": r["action"], "count": r["n"]} for r in staff],
            "sources": sources, "open_tasks": len(tasks)}


# --------------------------------------------------------------- reels --

class ReelBody(BaseModel):
    voice_text: str = Field(default="", max_length=600)   # staff's own narration (else the AI writes the story)
    seconds: int = Field(default=30, ge=6, le=60)
    # Owner 2026-11-04: a STORY reel (AI script from facts + real reviews, one voice,
    # captions) is the default; "slides" keeps the old photo slideshow.
    style: str = Field(default="story", pattern="^(story|slides)$")
    languages: list[str] = Field(default_factory=lambda: ["te"], max_length=4)


def _own_photo_paths(request: Request, item: dict[str, Any]) -> list[str]:
    """Only photos uploaded to ASKODOX (Staff Workspace camera / gallery)."""
    refs = [item.get("image_url") or ""] + list(item.get("images") or [])
    out = []
    for ref in refs:
        name = str(ref or "").rsplit("/", 1)[-1]
        if re.fullmatch(r"[0-9a-f]{32}\.(jpg|png|webp)", name):
            path = os.path.join(_upload_dir(request), name)
            if os.path.exists(path) and path not in out:
                out.append(path)
    return out


def _reel_audio(container: Any, text: str, folder: str, stem: str) -> str | None:
    if not text.strip():
        return None
    try:
        from app.api.routes.in_app_assistant import _elevenlabs

        spoken = _elevenlabs(container).synthesize(text.strip())
    except Exception:
        return None
    if not spoken.get("success") or not spoken.get("content"):
        return None
    path = os.path.join(folder, stem + ".voice.mp3")
    with open(path, "wb") as handle:
        handle.write(spoken["content"])
    return path


@router.post("/admin/cc/workspace/items/{item_id}/reel")
def make_item_reel(item_id: int, body: ReelBody, request: Request) -> dict:
    """ASKODOX Creations: a short reel from the item's own photos, title and
    stated price (+ optional voice). Made in the background as a DRAFT
    ASKODOX video; when ready it goes to the normal video review
    (PENDING_REVIEW -> ACTIVE). Nothing is published without review."""
    import hashlib as _hashlib
    import threading
    import time

    from app.services import rate_limit, reel_maker

    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    rate_limit.check(request, "workspace_reel", limit=20)
    container = request.app.state.container
    item = catalog(container).get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    photos = _own_photo_paths(request, item)
    if not photos:
        raise HTTPException(status_code=422, detail="Add the item's photos in the workspace first (camera / gallery)")
    title = str(item.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=422, detail="The item needs a title")
    price = reel_maker.price_text(item.get("price"), str(item.get("currency") or "INR"))
    folder = os.path.join(os.path.dirname(os.path.abspath(container.settings.database_path)), "video_uploads")
    os.makedirs(folder, exist_ok=True)
    from app.services import reel_story

    languages = [code for code in dict.fromkeys(body.languages or ["te"]) if code in reel_story.LANGUAGES] or ["te"]
    if body.style == "slides":
        languages = languages[:1]
    base = str(request.base_url).rstrip("/").replace("http://", "https://")
    pf = _pf(request)
    repo = pf.resources.repo
    jobs = []
    for code in languages:
        stem = _hashlib.sha256(f"reel:{item_id}:{code}:{time.time_ns()}".encode()).hexdigest()[:32]
        label = "" if code == "te" else f" ({reel_story.LANGUAGES[code]})"
        record = pf.resources.create("videos", {
            "title": (title[:120] + label)[:140], "platform": "askodox", "url": f"{base}/media/videos/{stem}.mp4",
            "description": str(item.get("description") or "")[:2000],
            "categories": [str(item.get("category") or "").lower()] if item.get("category") else [],
            "products": [title[:80]], "video_type": "demo", "relationship": "merchant", "merchant_ref": "askodox",
        }, actor=f"staff:{principal.get('id')}", status="DRAFT")
        # Marked at once so the workspace "Reels" tab shows it as MAKING.
        repo.update(record["id"], actor="system:reel", action="reel",
                    data={**(record.get("data") or {}),
                          "reel": {"item_id": item_id, "status": "MAKING", "language": code, "style": body.style}})
        jobs.append((code, stem, record))

    def finish(record: dict, code: str, outcome: dict, extra: dict) -> None:
        current = repo.get(record["id"]) or record
        data = dict(current.get("data") or {})
        data["reel"] = {"item_id": item_id, "status": "READY" if outcome.get("ok") else "FAILED",
                        "reason": outcome.get("reason"), "price_shown": price, "language": code,
                        "style": body.style, **extra}
        repo.update(record["id"], actor="system:reel", action="reel",
                    status="PENDING_REVIEW" if outcome.get("ok") else None, data=data)

    def work_slides() -> None:
        code, stem, record = jobs[0]
        audio = _reel_audio(container, body.voice_text, folder, stem)
        outcome = reel_maker.make_reel(photos, title, price, os.path.join(folder, stem + ".mp4"),
                                       seconds=body.seconds, audio=audio)
        if audio:
            try:
                os.remove(audio)
            except OSError:
                pass
        finish(record, code, outcome, {"voice": bool(audio)})

    def work_story() -> None:
        brain = getattr(container, "universal_ai_assistant_service", None)
        write = (lambda text: brain.write_text(text, max_tokens=1400)) if brain is not None else (lambda text: "")
        first = languages[0]
        if body.voice_text.strip():
            script = reel_story.custom_script(body.voice_text, first)
            reviews: list[dict] = []
        else:
            try:
                from app.api.routes.universal_deals import _web_search

                search = _web_search(container)
            except Exception:
                search = None
            reviews = reel_story.gather_reviews(search, title, str(item.get("brand") or ""))
            script = reel_story.write_script(write, item, language=first, photo_facts=_photo_facts_for(container, photos),
                                             reviews=reviews)
        tts = None
        try:
            from app.api.routes.in_app_assistant import _elevenlabs

            tts = _elevenlabs(container)
        except Exception:
            tts = None
        for code, stem, record in jobs:
            current = script if code == first else (
                reel_story.translate_script(write, script, code) if script.get("ok") else script)
            if not current.get("ok"):
                finish(record, code, {"ok": False, "reason": current.get("reason") or "script_failed"}, {})
                continue

            def voice(text: str, _code: str = code) -> bytes | None:
                if tts is None:
                    return None
                spoken = tts.synthesize(text, locale=_code)
                return spoken.get("content") if spoken.get("success") else None

            outcome = reel_story.render(photos, current, title, price, os.path.join(folder, stem + ".mp4"), voice=voice)
            finish(record, code, outcome, {
                "voice": bool(outcome.get("voiced_scenes")), "script": current.get("scenes"),
                "review_sources": [r["host"] for r in reviews][:6], "custom": bool(current.get("custom")),
                "seconds": outcome.get("seconds")})

    threading.Thread(target=work_slides if body.style == "slides" else work_story,
                     name=f"reel-{item_id}", daemon=True).start()
    return {"video_id": jobs[0][2]["id"], "video_ids": [j[2]["id"] for j in jobs], "status": "MAKING",
            "photos": len(photos), "price_shown": price, "style": body.style, "languages": languages,
            "voice": True if body.style == "story" else bool(body.voice_text.strip())}


def _photo_facts_for(container: Any, paths: list[str]) -> list[str]:
    """What the item's own photos show (same image brain as chat), for the script."""
    from app.services.attachment_facts import attachment_facts

    service = getattr(container, "universal_image_service", None)
    if service is None:
        return []
    out = []
    for path in paths[:2]:
        ext = path.rsplit(".", 1)[-1].lower()
        mime = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp"}.get(ext)
        if not mime:
            continue
        try:
            with open(path, "rb") as handle:
                facts = attachment_facts("image", service.analyze(handle.read(), mime_type=mime) or {})
        except Exception:
            facts = ""
        if facts:
            out.append(str(facts)[:600])
    return out


# ------------------------------------------------------------------ reels --
# Owner 2026-11-04: "where do I see the ready video?" -- reels are platform
# `videos` records; the workspace lists them, plays them (staff only, any status)
# and lets a publisher approve / reject (same lifecycle as the console review).

def _reel_records(request: Request) -> list[dict[str, Any]]:
    out = []
    for r in _pf(request).resources.repo.list("videos"):
        data = r.get("data") or {}
        reel = data.get("reel")
        if not isinstance(reel, dict) or r.get("archived"):
            continue
        out.append({"video_id": r["id"], "title": data.get("title") or r.get("name") or "",
                    "status": r.get("status"), "reel_status": reel.get("status") or "MAKING",
                    "reason": reel.get("reason"), "item_id": reel.get("item_id"),
                    "price_shown": reel.get("price_shown"), "voice": bool(reel.get("voice")),
                    "style": reel.get("style") or "slides", "language": reel.get("language") or "te",
                    "script": [str(s.get("say") or "") for s in (reel.get("script") or []) if isinstance(s, dict)],
                    "review_sources": reel.get("review_sources") or [], "seconds": reel.get("seconds"),
                    "file": str(data.get("url") or "").rsplit("/", 1)[-1],
                    "created_at": r.get("created_at"), "updated_at": r.get("updated_at")})
    out.sort(key=lambda x: str(x.get("created_at") or ""), reverse=True)
    return out


@router.get("/admin/cc/workspace/reels")
def list_reels(request: Request, item_id: int | None = None) -> dict:
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    rows = _reel_records(request)
    if item_id is not None:
        rows = [r for r in rows if str(r.get("item_id")) == str(item_id)]
    return {"items": rows[:100], "can_publish": _can_publish(principal)}


@router.get("/admin/cc/workspace/reels/{video_id}/file")
def reel_file(video_id: str, request: Request) -> FileResponse:
    """The reel's mp4 for staff preview (before approval too)."""
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    row = next((r for r in _reel_records(request) if r["video_id"] == video_id), None)
    name = (row or {}).get("file") or ""
    if not row or not re.fullmatch(r"[0-9a-f]{32}\.mp4", name):
        raise HTTPException(status_code=404, detail="Reel not found")
    folder = os.path.join(os.path.dirname(os.path.abspath(request.app.state.container.settings.database_path)),
                          "video_uploads")
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="The reel file is not ready yet")
    return FileResponse(path, media_type="video/mp4", headers={"Cache-Control": "no-store"})


class ReelReviewBody(BaseModel):
    action: str = Field(pattern="^(approve|reject)$")


@router.post("/admin/cc/workspace/reels/{video_id}/review")
def review_reel(video_id: str, body: ReelReviewBody, request: Request) -> dict:
    principal = _workspace(request)
    if not _can_publish(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs workspace:approve)")
    if not any(r["video_id"] == video_id for r in _reel_records(request)):
        raise HTTPException(status_code=404, detail="Reel not found")
    try:
        item = _pf(request).resources.action("videos", video_id, body.action, actor=f"staff:{principal.get('id')}")
    except Exception as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
    return {"video_id": video_id, "status": item.get("status")}
