"""/api/me/memory -- the signed-in person's conversation memory (view,
correct, delete, disable). Identity only from the session token."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import profile_memory as memory

router = APIRouter(prefix="/api/me/memory", tags=["profile-memory"])


def _db(request: Request) -> str:
    return request.app.state.container.settings.database_path


@router.get("")
def my_memory(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    db = _db(request)
    return {"enabled": memory.enabled(db, user_id), "roles": list(memory.ROLES), "items": memory.items(db, user_id)}


class MemorySettings(BaseModel):
    enabled: bool


@router.put("/settings")
def memory_settings(payload: MemorySettings, request: Request) -> dict:
    return memory.set_enabled(_db(request), _authenticated_app_user(request), payload.enabled)


class MemoryCorrection(BaseModel):
    subject: str | None = Field(default=None, max_length=160)
    details: dict[str, Any] | None = None
    status: str | None = Field(default=None, max_length=20)
    visibility: str | None = Field(default=None, max_length=10)
    consent: bool = False


@router.patch("/{item_id}")
def correct_memory(item_id: int, payload: MemoryCorrection, request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    try:
        item = memory.correct(_db(request), user_id, item_id, **payload.model_dump())
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    if item is None:
        raise HTTPException(status_code=404, detail="not found")
    return item


@router.get("/{item_id}/history")
def memory_history(item_id: int, request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    if memory.get(_db(request), user_id, item_id) is None:
        raise HTTPException(status_code=404, detail="not found")
    return {"history": memory.history(_db(request), user_id, item_id)}


@router.delete("/{item_id}")
def delete_memory_item(item_id: int, request: Request) -> dict:
    n = memory.delete(_db(request), _authenticated_app_user(request), item_id)
    if not n:
        raise HTTPException(status_code=404, detail="not found")
    return {"deleted": n}


@router.delete("")
def delete_all_memory(request: Request, confirm: str = "") -> dict:
    if confirm.strip().upper() != "DELETE":
        raise HTTPException(status_code=422, detail="Type DELETE to confirm")
    return {"deleted": memory.delete(_db(request), _authenticated_app_user(request))}
