"""Commission Dashboard (commission engine on the Partner Hub ledger).

GET  /admin/cc/commissions/summary                       (commissions:view)
GET  /admin/cc/commissions/conversions/{id}              conversion + its state history
POST /admin/cc/commissions/conversions/{id}/transition   forward-only (commissions:approve, confirm)
POST /admin/cc/commissions/promote-payable               CONFIRMED past hold -> PAYABLE (commissions:approve)
POST /admin/cc/commissions/reconcile/{partner_id}        statement CSV vs ledger, read-only (commissions:view)
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services import commission_engine

admin_router = APIRouter(prefix="/admin/cc/commissions", tags=["command-center"])


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


def _repo(request: Request):
    from app.api.routes.partners import partner_repo

    return partner_repo(request.app.state.container)


def _audit(request: Request, principal: dict, action: str, target: str, detail: dict) -> None:
    try:
        from app.api.routes.command_center import command_center

        command_center(request.app.state.container).audit(principal["id"], action, "commission", target, after=detail)
    except Exception:
        pass


@admin_router.get("/summary")
def commission_summary(request: Request) -> dict:
    _require(request, "commissions:view")
    return commission_engine.summary(_repo(request))


@admin_router.get("/conversions/{conversion_id}")
def conversion_detail(conversion_id: int, request: Request) -> dict:
    _require(request, "commissions:view")
    repo = _repo(request)
    conversion = repo.get_conversion(conversion_id)
    if not conversion:
        raise HTTPException(status_code=404, detail="Conversion not found")
    return {"conversion": conversion, "history": repo.conversion_events(conversion_id)}


class TransitionBody(BaseModel):
    to: str = Field(pattern="^(CONFIRMED|PAYABLE|PAID|REJECTED|REVERSED)$")
    note: str = Field(default="", max_length=200)
    confirm: bool = False


@admin_router.post("/conversions/{conversion_id}/transition")
def conversion_transition(conversion_id: int, body: TransitionBody, request: Request) -> dict:
    principal = _require(request, "commissions:approve")
    if not body.confirm:
        raise HTTPException(status_code=409, detail="Confirmation required")
    try:
        conversion = commission_engine.transition(_repo(request), conversion_id, body.to,
                                                  actor=f"staff:{principal.get('id')}", note=body.note)
    except KeyError:
        raise HTTPException(status_code=404, detail="Conversion not found") from None
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
    _audit(request, principal, "commission.transition", f"conversion:{conversion_id}", {"to": body.to})
    return {"conversion": conversion}


class ConfirmBody(BaseModel):
    confirm: bool = False


@admin_router.post("/promote-payable")
def promote(body: ConfirmBody, request: Request) -> dict:
    principal = _require(request, "commissions:approve")
    if not body.confirm:
        raise HTTPException(status_code=409, detail="Confirmation required")
    out = commission_engine.promote_payable(_repo(request), actor=f"staff:{principal.get('id')}")
    _audit(request, principal, "commission.promote_payable", "all", {"moved": len(out["moved_to_payable"])})
    return out


class StatementBody(BaseModel):
    csv: str = Field(min_length=1, max_length=2_000_000)


@admin_router.post("/reconcile/{partner_id}")
def reconcile(partner_id: int, body: StatementBody, request: Request) -> dict:
    _require(request, "commissions:view")
    repo = _repo(request)
    partner = repo.get_partner(partner_id)
    if not partner:
        raise HTTPException(status_code=404, detail="Partner not found")
    return commission_engine.reconcile(repo, partner, body.csv)
