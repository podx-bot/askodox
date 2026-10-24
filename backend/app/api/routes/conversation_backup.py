"""/api/me/conversations -- the signed-in user's chat history backup (see conversation_backup.py)."""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import conversation_backup as backup
from app.services import rate_limit

router = APIRouter(prefix="/api/me/conversations", tags=["history"])


def _db(request: Request) -> str:
    return request.app.state.container.settings.database_path


class SnapshotIn(BaseModel):
    snapshot: Dict[str, Any] = Field(default_factory=dict)


@router.get("")
def my_conversations(request: Request, limit: int = 50) -> dict:
    user = _authenticated_app_user(request)
    return {"conversations": backup.list_all(_db(request), user, limit)}


@router.put("/{conversation_id}")
def save_conversation(conversation_id: str, body: SnapshotIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, f"history:{user}", limit=240)
    snapshot = dict(body.snapshot)
    if str(snapshot.get("id") or conversation_id) != conversation_id:
        raise HTTPException(status_code=400, detail="Snapshot id does not match the path")
    try:
        return backup.save(_db(request), user, conversation_id, snapshot)
    except backup.BackupError as error:
        raise HTTPException(status_code=413 if "large" in str(error) else 400, detail=str(error))


@router.delete("/{conversation_id}")
def delete_conversation(conversation_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"deleted": backup.delete(_db(request), user, conversation_id)}
