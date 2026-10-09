"""/api/business/creations -- the signed-in owner's My Creations."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import business_creations as creations

router = APIRouter(prefix="/api/business/creations", tags=["business-creations"])


def _db(request: Request) -> str:
    return request.app.state.container.settings.database_path


def _ai(request: Request):
    return getattr(request.app.state.container, "universal_ai_assistant_service", None)


def _ai_ready(request: Request) -> bool:
    ai = _ai(request)
    return bool(ai is not None and (getattr(ai, "configured", False) or getattr(ai, "openai_api_key", "")))


@router.get("")
def my_creations(request: Request) -> dict:
    owner = _authenticated_app_user(request)
    return {"items": creations.items(_db(request), owner), "kinds": list(creations.KINDS),
            "capabilities": creations.capabilities(_ai_ready(request))}


class CreationBody(BaseModel):
    kind: str = Field(max_length=30)
    body: str = Field(min_length=1, max_length=6000)
    title: str = Field(default="", max_length=120)
    status: str = Field(default="draft", max_length=10)
    source: str = Field(default="owner", max_length=10)


@router.post("")
def save_creation(payload: CreationBody, request: Request) -> dict:
    owner = _authenticated_app_user(request)
    try:
        return creations.create(_db(request), owner, kind=payload.kind, body=payload.body, title=payload.title,
                                status=payload.status, source="ai" if payload.source == "ai" else "owner")
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None


class CreationPatch(BaseModel):
    title: str | None = Field(default=None, max_length=120)
    body: str | None = Field(default=None, max_length=6000)
    status: str | None = Field(default=None, max_length=10)


@router.patch("/{item_id}")
def edit_creation(item_id: int, payload: CreationPatch, request: Request) -> dict:
    owner = _authenticated_app_user(request)
    try:
        row = creations.update(_db(request), owner, item_id, **payload.model_dump())
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None
    if row is None:
        raise HTTPException(status_code=404, detail="not found")
    return row


@router.delete("/{item_id}")
def delete_creation(item_id: int, request: Request) -> dict:
    if not creations.delete(_db(request), _authenticated_app_user(request), item_id):
        raise HTTPException(status_code=404, detail="not found")
    return {"deleted": True}


class DraftBody(BaseModel):
    kind: str = Field(max_length=30)
    about: str = Field(min_length=3, max_length=2000)
    language: str = Field(default="en", max_length=8)


@router.post("/draft")
def draft_creation(payload: DraftBody, request: Request) -> dict:
    """An AI draft from the owner's facts. Nothing is saved or published."""
    _authenticated_app_user(request)
    from app.services import rate_limit

    rate_limit.check(request, "creation_draft", limit=30)
    if payload.kind not in creations.KINDS:
        raise HTTPException(status_code=422, detail="unknown kind")
    ai = _ai(request)
    text = ai.write_text(creations.draft_prompt(payload.kind, payload.about, payload.language)) \
        if ai is not None and _ai_ready(request) else ""
    if not text:
        raise HTTPException(status_code=503, detail="AI writing is not available right now -- write it yourself "
                                                    "or try again later.")
    return {"kind": payload.kind, "text": text, "source": "ai",
            "note": "AI draft from your facts only -- check it before you share. Nothing is posted automatically."}
