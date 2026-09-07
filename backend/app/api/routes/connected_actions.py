from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

from app.services.connected_action_service import ConnectedActionService

router = APIRouter(prefix="/actions", tags=["Connected Actions"])


class ConnectedActionCreateRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=128)
    action_type: str = Field(min_length=1, max_length=128)
    target: str = Field(min_length=1, max_length=512)
    payload: dict = Field(default_factory=dict)
    idempotency_key: str = Field(min_length=1, max_length=256)
    approval_required: bool = True


class ConnectedActionUserRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=128)


def _service(request: Request) -> ConnectedActionService:
    service = getattr(request.app.state.container, "connected_action_service", None)
    if service is None:
        database_path = request.app.state.container.settings.database_path
        service = ConnectedActionService(database_path)
        request.app.state.container.connected_action_service = service
    return service


@router.post("")
def create_connected_action(payload: ConnectedActionCreateRequest, request: Request) -> dict:
    try:
        action = _service(request).create(
            user_id=payload.user_id,
            action_type=payload.action_type,
            target=payload.target,
            payload=payload.payload,
            idempotency_key=payload.idempotency_key,
            approval_required=payload.approval_required,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {"status": "success", "action": action}


@router.get("")
def list_connected_actions(
    request: Request,
    user_id: str = Query(min_length=1, max_length=128),
    limit: int = Query(default=50, ge=1, le=200),
) -> dict:
    actions = _service(request).list(user_id=user_id, limit=limit)
    return {"status": "success", "actions": actions, "count": len(actions)}


@router.get("/{action_id}")
def get_connected_action(
    action_id: str,
    request: Request,
    user_id: str = Query(min_length=1, max_length=128),
) -> dict:
    try:
        action = _service(request).get(action_id=action_id, user_id=user_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Action not found") from error
    return {"status": "success", "action": action}


@router.post("/{action_id}/approve")
def approve_connected_action(
    action_id: str,
    payload: ConnectedActionUserRequest,
    request: Request,
) -> dict:
    try:
        action = _service(request).approve(action_id=action_id, user_id=payload.user_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Action not found") from error
    return {"status": "success", "action": action}


@router.post("/{action_id}/execute")
def execute_connected_action(
    action_id: str,
    payload: ConnectedActionUserRequest,
    request: Request,
) -> dict:
    try:
        action = _service(request).execute(action_id=action_id, user_id=payload.user_id)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="Action not found") from error
    except PermissionError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    return {"status": "success", "action": action}
