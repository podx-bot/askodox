"""Payment messages in NEW words (owner 2026-11-23): see ``app/services/payment_alert_shapes.py``.

Phones (signed in):
  POST /api/payment-alerts/shapes  {sender, skeleton, answer}  -- one person's answer about one message SHAPE
                                   (shape words only, never a name / amount / number; refused otherwise)
  GET  /api/payment-alerts/shapes  -- the shapes every phone reads (sender + shape words + in / out / none)
Staff:
  GET  /admin/cc/payment-shapes?status=new|approved|rejected   (payments:view)
  POST /admin/cc/payment-shapes/{id}  {status, kind}             (payments:manage)
"""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.pos import _user
from app.services.payment_alert_shapes import ShapeError, payment_alert_shapes

router = APIRouter(prefix="/api/payment-alerts/shapes", tags=["payment-alerts"])
admin_router = APIRouter(prefix="/admin/cc/payment-shapes", tags=["command-center"])

# One phone answers a handful of new shapes a day at most; this only stops a flood.
ANSWERS_PER_HOUR = 30


class AnswerIn(BaseModel):
    sender: str = Field(min_length=4, max_length=120)
    skeleton: str = Field(min_length=3, max_length=600)
    answer: str = Field(min_length=2, max_length=4)


class DecideIn(BaseModel):
    status: str = Field(min_length=3, max_length=10)
    kind: Optional[str] = Field(default=None, max_length=4)


@router.post("")
def answer(request: Request, body: AnswerIn) -> Dict[str, Any]:
    user = _user(request, "payshape", limit=ANSWERS_PER_HOUR)
    try:
        return payment_alert_shapes(request.app.state.container).answer(user, body.sender, body.skeleton, body.answer)
    except ShapeError as error:
        raise HTTPException(status_code=422, detail={"code": f"shape_{error}", "message": "Only the message shape words may be sent."})


@router.get("")
def shared(request: Request) -> Dict[str, Any]:
    _user(request, "payshape-read", limit=60)
    return {"shapes": payment_alert_shapes(request.app.state.container).shared()}


@admin_router.get("")
def list_shapes(request: Request, status: Optional[str] = None) -> Dict[str, Any]:
    from app.api.routes.command_center import _require

    _require(request, "payments:view")
    return payment_alert_shapes(request.app.state.container).list(status)


@admin_router.post("/{shape_id}")
def decide(request: Request, shape_id: int, body: DecideIn) -> Dict[str, Any]:
    from app.api.routes.command_center import _require

    principal = _require(request, "payments:manage")
    staff = str(principal.get("id") or principal.get("name") or "staff")
    try:
        return payment_alert_shapes(request.app.state.container).decide(shape_id, body.status, body.kind, staff)
    except ShapeError as error:
        raise HTTPException(status_code=422, detail={"code": f"shape_{error}", "message": "status / kind not allowed"})
    except LookupError:
        raise HTTPException(status_code=404, detail="shape not found")
