"""Family shopping list (family_lists.py): the caller's own lists only; identity from the bearer token."""
from __future__ import annotations

from typing import Any, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.pos import _user
from app.services.family_lists import FamilyListError, FamilyLists

router = APIRouter(prefix="/api/me/family-lists", tags=["Family shopping list"])


def _lists(request: Request) -> FamilyLists:
    container: Any = request.app.state.container
    existing = getattr(container, "family_lists", None)
    if existing is None:
        from app.services.push_service import push_service

        def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
            try:
                push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)
            except Exception:
                pass

        existing = FamilyLists(container.settings.database_path, notify=notify)
        try:
            container.family_lists = existing
        except Exception:
            pass
    return existing


def _call(fn, *args):
    try:
        return fn(*args)
    except FamilyListError as error:
        raise HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message})


class ListIn(BaseModel):
    name: str = Field(default="", max_length=40)


class MemberIn(BaseModel):
    phone: str = Field(default="", max_length=20)
    label: str = Field(default="", max_length=30)


class ItemsIn(BaseModel):
    texts: List[str] = Field(min_length=1, max_length=30)
    qty: str = Field(default="", max_length=20)


class ItemPatch(BaseModel):
    text: Optional[str] = Field(default=None, max_length=80)
    qty: Optional[str] = Field(default=None, max_length=20)
    state: Optional[str] = Field(default=None, pattern="^(open|done|paused)$")


@router.get("")
def mine(request: Request) -> dict:
    return _call(_lists(request).mine, _user(request, "family"))


@router.post("")
def create(body: ListIn, request: Request) -> dict:
    return _call(_lists(request).create, _user(request, "family"), body.name)


@router.patch("/{list_id}")
def rename(list_id: str, body: ListIn, request: Request) -> dict:
    return _call(_lists(request).rename, _user(request, "family"), list_id, body.name)


@router.post("/{list_id}/members")
def add_member(list_id: str, body: MemberIn, request: Request) -> dict:
    return _call(_lists(request).add_member, _user(request, "family", 60), list_id, body.phone, body.label)


@router.patch("/{list_id}/members/{ref}")
def update_member(list_id: str, ref: str, body: MemberIn, request: Request) -> dict:
    return _call(_lists(request).update_member, _user(request, "family"), list_id, ref, body.label)


@router.delete("/{list_id}/members/{ref}")
def remove_member(list_id: str, ref: str, request: Request) -> dict:
    """ref "me" = leave the list."""
    return _call(_lists(request).remove_member, _user(request, "family"), list_id, "" if ref == "me" else ref)


@router.post("/{list_id}/items")
def add_items(list_id: str, body: ItemsIn, request: Request) -> dict:
    return _call(_lists(request).add_items, _user(request, "family"), list_id, body.texts, body.qty)


@router.post("/{list_id}/items/clear-done")
def clear_done(list_id: str, request: Request) -> dict:
    return _call(_lists(request).clear_done, _user(request, "family"), list_id)


@router.patch("/{list_id}/items/{item_id}")
def update_item(list_id: str, item_id: str, body: ItemPatch, request: Request) -> dict:
    return _call(_lists(request).update_item, _user(request, "family"), list_id, item_id,
                 body.model_dump(exclude_none=True))


@router.delete("/{list_id}/items/{item_id}")
def delete_item(list_id: str, item_id: str, request: Request) -> dict:
    return _call(_lists(request).delete_item, _user(request, "family"), list_id, item_id)
