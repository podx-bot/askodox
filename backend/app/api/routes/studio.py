"""ASKODOX Studio routes (owner 2026-11-21) -- Staff Workspace tab "Studio": products bought to shoot, return dates,
stages, returns. Same sign-in and permissions as the Staff Workspace; staff see their own purchases, publishers and
the owner see all."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

from app.api.routes.staff_workspace import _can_publish, _types, _workspace
from app.services import governance as gov
from app.services import studio_store as ss

router = APIRouter()


def studio(container: Any) -> ss.StudioStore:
    store = getattr(container, "studio_store", None)
    if store is None:
        store = ss.StudioStore(container.settings.database_path)
        container.studio_store = store
    return store


def _principal(request: Request) -> dict:
    principal = _workspace(request)
    if not _types(principal):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    return principal


def _mine(request: Request, principal: dict, purchase_id: int) -> dict:
    row = studio(request.app.state.container).get(purchase_id)
    if not row or (not _can_publish(principal) and row["created_by"] != principal["id"]):
        raise HTTPException(status_code=404, detail="Purchase not found")
    return row


def _run(fn, *args, **kwargs) -> dict:
    try:
        return fn(*args, **kwargs)
    except ss.StudioError as error:
        raise HTTPException(status_code=422, detail=str(error))
    except LookupError as error:
        raise HTTPException(status_code=404, detail=str(error))


@router.get("/admin/cc/workspace/studio")
def studio_home(request: Request) -> dict:
    principal = _principal(request)
    store = studio(request.app.state.container)
    everyone = _can_publish(principal)
    rows = store.list(actor=None if everyone else principal["id"])
    return {"summary": store.summary(rows), "purchases": rows, "accounts": store.accounts(),
            "stores": list(ss.STORES), "all_staff": everyone, "today": store.today().isoformat()}


class PurchaseBody(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    store: str = Field(min_length=1, max_length=30)
    account_id: int | None = None
    account_label: str = Field(default="", max_length=60)
    item_id: int | None = None
    paid: float | str | None = None
    pack: str = Field(default="single", pattern="^(single|pair|combo)$")
    pack_count: int | None = Field(default=None, ge=1, le=50)
    order_date: str = ""
    delivery_date: str = ""
    return_option: str = Field(default="return", pattern="^(return|exchange|none)$")
    return_days: int = Field(default=0, ge=0, le=60)
    affiliate_link: str = Field(default="", max_length=500)
    share_earn_link: str = Field(default="", max_length=500)
    notes: str = Field(default="", max_length=500)


@router.post("/admin/cc/workspace/studio/purchases")
def add_purchase(body: PurchaseBody, request: Request) -> dict:
    principal = _principal(request)
    row = _run(studio(request.app.state.container).create, body.model_dump(), actor=principal["id"])
    print(f"ASKODOX STUDIO BUY id={row['id']} store={row['store']} option={row['return_option']} "
          f"deadline={row['return_deadline'] or '-'} whitelisted={row['account_whitelisted']}", flush=True)
    return {"purchase": row}


class StageBody(BaseModel):
    stage: str = Field(pattern="^(bought|delivered|shot|edited|posted)$")
    delivery_date: str = ""


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/stage")
def set_stage(purchase_id: int, body: StageBody, request: Request) -> dict:
    principal = _principal(request)
    _mine(request, principal, purchase_id)
    return {"purchase": _run(studio(request.app.state.container).set_stage, purchase_id, body.stage,
                             delivery_date=body.delivery_date)}


class ReturnBody(BaseModel):
    return_id: str = Field(default="", max_length=60)
    pickup_date: str = ""
    fee: float | str | None = None
    refund_status: str = Field(default="sent", pattern="^(sent|picked|refunded)$")


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/return")
def record_return(purchase_id: int, body: ReturnBody, request: Request) -> dict:
    principal = _principal(request)
    _mine(request, principal, purchase_id)
    return {"purchase": _run(studio(request.app.state.container).record_return, purchase_id, body.model_dump())}


class KeepBody(BaseModel):
    reason: str = Field(default="studio", max_length=120)


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/keep")
def keep(purchase_id: int, body: KeepBody, request: Request) -> dict:
    principal = _principal(request)
    _mine(request, principal, purchase_id)
    return {"purchase": _run(studio(request.app.state.container).keep, purchase_id, body.reason)}


class AccountBody(BaseModel):
    store: str = Field(min_length=1, max_length=30)
    label: str = Field(min_length=1, max_length=60)
    whitelisted: bool = False


@router.post("/admin/cc/workspace/studio/accounts")
def save_account(body: AccountBody, request: Request) -> dict:
    principal = _principal(request)
    if not _can_publish(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (owner / publisher only)")
    return {"account": _run(studio(request.app.state.container).save_account, body.store, body.label,
                            body.whitelisted)}


def send_reminders(container: Any) -> dict:
    """Periodic job: due Studio reminders -> push to the staff who bought it + the owner (super admins), once each."""
    from app.api.routes.command_center import command_center
    from app.services.push_service import push_service

    store = studio(container)
    due = store.due_reminders()
    if not due:
        return {"due": 0, "pushed": 0}
    staff = [s for s in command_center(container).list_staff()
             if s.get("active") and str(s.get("app_user_id") or "").startswith("app-")]
    owners = {s["app_user_id"] for s in staff if str(s.get("role") or "") == "super_admin"}
    notify = push_service(container).notify
    pushed = sent = 0
    for entry in due:
        row, kind = entry["purchase"], entry["kind"]
        if not store.mark_sent(row["id"], kind):
            continue
        sent += 1
        buyer = {s["app_user_id"] for s in staff if f"staff-{s.get('id')}" == row["created_by"]}
        text = ss.reminder_text(row, kind)
        for user_id in sorted(buyer | owners):
            try:
                pushed += int(notify(user_id, title=text["title"], body=text["body"], route="/profile",
                                     event_key=f"studio:{row['id']}:{kind}") or 0)
            except Exception:
                pass
    print(f"ASKODOX STUDIO REMINDERS due={len(due)} sent={sent} pushed={pushed}", flush=True)
    return {"due": len(due), "sent": sent, "pushed": pushed}


# ------------------------------------------------------------ round 2: video --
MAX_STUDIO_VIDEO = 80 * 1024 * 1024


def _detail(request: Request, row: dict) -> dict:
    from app.api.routes import native_video
    from app.services import studio_video as sv

    base = native_video._base(request)
    pid = row["id"]
    options = row.get("edit_options") or {}
    return {**row, "tips": sv.shoot_tips(row), "checklist": sv.checklist(row, studio(request.app.state.container).today()
                                                                           .isoformat()),
            "captions": sv.captions(row), "script": sv.script(row, options), "price_tag": sv.price_tag(row),
            # staff-only previews (the page fetches them with its sign-in); the public link only after Publish
            "video_url": f"/admin/cc/workspace/studio/purchases/{pid}/media/raw" if row.get("video_file") else "",
            "edited_url": f"/admin/cc/workspace/studio/purchases/{pid}/media/edited" if row.get("edited_file") else "",
            "download_url": f"{base}/media/studio/{row['edited_file']}" if row.get("edited_file") and
            row.get("published_at") else ""}


@router.get("/admin/cc/workspace/studio/purchases/{purchase_id}/media/{kind}")
def studio_media(purchase_id: int, kind: str, request: Request):
    import os

    from fastapi.responses import FileResponse

    from app.api.routes import native_video

    principal = _principal(request)
    row = _mine(request, principal, purchase_id)
    name = row.get("video_file") if kind == "raw" else row.get("edited_file") if kind == "edited" else ""
    path = os.path.join(native_video._folder(request), os.path.basename(name or ""))
    if not name or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, media_type="video/webm" if name.endswith(".webm") else "video/mp4",
                        headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"})


@router.get("/media/studio/{name}")
def studio_public_media(name: str, request: Request):
    """The edited video of a PUBLISHED Studio product (unguessable name) -- for downloading and posting."""
    import os
    import re

    from fastapi.responses import FileResponse

    from app.api.routes import native_video

    if not re.fullmatch(r"[0-9a-f]{32}\.mp4", name) or not studio(request.app.state.container).published_by_file(name):
        raise HTTPException(status_code=404, detail="Not found")
    path = os.path.join(native_video._folder(request), name)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, media_type="video/mp4", filename=f"askodox-{name[:8]}.mp4",
                        headers={"Cache-Control": "public, max-age=3600", "X-Content-Type-Options": "nosniff"})


@router.get("/admin/cc/workspace/studio/purchases/{purchase_id}")
def purchase_detail(purchase_id: int, request: Request) -> dict:
    principal = _principal(request)
    return {"purchase": _detail(request, _mine(request, principal, purchase_id))}


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/video")
async def upload_shoot(purchase_id: int, request: Request, file: UploadFile = File(...)) -> dict:
    """The staff phone video (own video = Meesho payout). Vertical, at most 60 seconds."""
    import os

    from app.api.routes import native_video
    from app.services import studio_video as sv
    from app.services import video_watermark as wm

    principal = _principal(request)
    _mine(request, principal, purchase_id)
    data = await file.read(MAX_STUDIO_VIDEO + 1)
    if len(data) > MAX_STUDIO_VIDEO:
        raise HTTPException(status_code=413, detail="80 MB వరకు మాత్రమే. ఫోన్ కెమెరా 1080p లో షూట్ చేయండి.")
    ext = native_video._video_ext(data)
    if ext is None:
        raise HTTPException(status_code=415, detail="MP4 / WebM వీడియో మాత్రమే")
    name = native_video._save(request, data, ext)
    path = os.path.join(native_video._folder(request), name)
    exe = wm.ffmpeg_exe()
    info = sv.probe(exe, path) if exe else {}
    seconds = float(info.get("seconds") or 0)
    if exe and seconds > sv.MAX_SECONDS:
        raise HTTPException(status_code=422, detail=f"వీడియో {seconds:.0f} సెకన్లు. 60 సెకన్ల లోపు ఉండాలి.")
    if exe and info.get("width") and info.get("height") and info["width"] > info["height"]:
        raise HTTPException(status_code=422, detail="ఫోన్ నిలువుగా పట్టుకుని షూట్ చేయండి (portrait).")
    row = _run(studio(request.app.state.container).set_video, purchase_id, name, seconds)
    print(f"ASKODOX STUDIO SHOOT id={purchase_id} seconds={seconds:.1f} size={info.get('width')}x{info.get('height')}",
          flush=True)
    return {"purchase": _detail(request, row)}


class EditBody(BaseModel):
    language: str = Field(default="te", pattern="^(te|hi|en)$")
    voice: str = Field(default="female", pattern="^(female|male|none)$")
    presenter: bool = True
    line: str = Field(default="", max_length=200)


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/edit")
def auto_edit(purchase_id: int, body: EditBody, request: Request) -> dict:
    """ASKODOX auto edit in the background: staff video + ASKODOX + price / pack tag + presenter + voice + end card."""
    import os
    import shutil
    import tempfile
    import threading

    from app.api.routes import native_video
    from app.services import rate_limit
    from app.services import studio_video as sv
    from app.services import video_watermark as wm

    principal = _principal(request)
    row = _mine(request, principal, purchase_id)
    if not row.get("video_file"):
        raise HTTPException(status_code=422, detail="ముందు షూట్ చేసిన వీడియో upload చేయండి")
    if not row.get("show_price_paise"):
        raise HTTPException(status_code=422, detail="ముందు ఈరోజు యాప్‌లో ఉన్న ధర పెట్టండి (checklist లో)")
    if row.get("edit_status") == "MAKING":
        raise HTTPException(status_code=409, detail="ఇప్పటికే తయారవుతోంది -- కొంచెం ఆగండి")
    rate_limit.check(request, "studio_edit", limit=30)
    container = request.app.state.container
    store = studio(container)
    options = {"language": body.language, "voice": body.voice, "presenter": (body.voice if body.voice != "none" else
                                                                             "female") if body.presenter else "",
               "line": body.line.strip()}
    store.set_edit(purchase_id, status="MAKING", options=options)
    folder = native_video._folder(request)

    def work() -> None:
        outcome, stats = {"ok": False, "reason": "ffmpeg_missing"}, {}
        tmp = tempfile.mkdtemp(prefix="studio-")
        try:
            exe = wm.ffmpeg_exe()
            if exe:
                fresh = store.get(purchase_id) or row
                lines = sv.script(fresh, options)
                voices, stats = (sv.voice_files(container, store, lines, body.voice, folder)
                                 if body.voice != "none" else ([], {}))
                name = f"{os.urandom(16).hex()}.mp4"  # unguessable: public only after Publish
                outcome = sv.render(exe, os.path.join(folder, fresh["video_file"]), fresh, options, voices,
                                    os.path.join(folder, name), tmp)
                if outcome.get("ok"):
                    store.set_edit(purchase_id, status="READY", edited=name)
        except Exception as error:
            outcome = {"ok": False, "reason": f"error:{type(error).__name__}"}
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if not outcome.get("ok"):
            store.set_edit(purchase_id, status="FAILED", reason=str(outcome.get("reason")))
        print(f"ASKODOX STUDIO EDIT id={purchase_id} ok={outcome.get('ok')} reason={outcome.get('reason')} "
              f"seconds={outcome.get('seconds')} voice_cached={stats.get('cached', 0)} voice_new={stats.get('new', 0)} "
              f"voice_failed={stats.get('failed', 0)}", flush=True)

    threading.Thread(target=work, name=f"studio-edit-{purchase_id}", daemon=True).start()
    return {"purchase": _detail(request, store.get(purchase_id))}


class ChecksBody(BaseModel):
    ticks: dict[str, bool] = Field(default_factory=dict)
    show_price: float | str | None = None


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/checks")
def save_checks(purchase_id: int, body: ChecksBody, request: Request) -> dict:
    principal = _principal(request)
    _mine(request, principal, purchase_id)
    row = _run(studio(request.app.state.container).set_checks, purchase_id, body.ticks, body.show_price)
    return {"purchase": _detail(request, row)}


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/publish")
def publish(purchase_id: int, request: Request) -> dict:
    """Stops with the missing items named (Studio spec 6); otherwise the captions become available to post."""
    from app.services import studio_video as sv

    principal = _principal(request)
    row = _mine(request, principal, purchase_id)
    store = studio(request.app.state.container)
    check = sv.checklist(row, store.today().isoformat())
    if not check["ready"]:
        raise HTTPException(status_code=422, detail="Publish ఆగింది -- ఇవి లేవు: " + "; ".join(check["missing"]))
    row = _run(store.mark_published, purchase_id)
    print(f"ASKODOX STUDIO PUBLISH id={purchase_id} store={row['store']}", flush=True)
    return {"purchase": _detail(request, row)}


class PostBody(BaseModel):
    platform: str = Field(pattern="^(instagram|facebook|youtube|whatsapp)$")
    url: str = Field(default="", max_length=500)


@router.post("/admin/cc/workspace/studio/purchases/{purchase_id}/posted")
def posted(purchase_id: int, body: PostBody, request: Request) -> dict:
    principal = _principal(request)
    _mine(request, principal, purchase_id)
    row = _run(studio(request.app.state.container).add_post, purchase_id, body.platform, body.url)
    return {"purchase": _detail(request, row)}
