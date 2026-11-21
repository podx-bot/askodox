"""ASKODOX Studio routes (owner 2026-11-21) -- Staff Workspace tab "Studio": products bought to shoot, return dates,
stages, returns. Same sign-in and permissions as the Staff Workspace; staff see their own purchases, publishers and
the owner see all."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
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
