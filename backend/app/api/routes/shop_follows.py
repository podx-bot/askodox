"""Shop follow routes: any signed-in person (shop owners too). Identity from the bearer token only."""

from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request

from app.api.routes.pos import _store, _user
from app.services.pos_store import PosError
from app.services.shop_follows import ShopFollows

router = APIRouter(tags=["Shop follows"])


def _service(request: Request) -> ShopFollows:
    return ShopFollows(_store(request).db_path)


def _call(fn, *args) -> Dict[str, Any]:
    try:
        return fn(*args)
    except PosError as error:
        raise HTTPException(status_code=error.status,
                            detail={"code": error.code, "message": error.message})


@router.get("/api/shops/{business_id}")
def shop_state(business_id: str, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="shop_follow", limit=240)
    return _call(_service(request).get, business_id, user)


@router.post("/api/shops/{business_id}/follow")
def follow_shop(business_id: str, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="shop_follow", limit=120)
    return _call(_service(request).follow, business_id, user)


@router.delete("/api/shops/{business_id}/follow")
def unfollow_shop(business_id: str, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="shop_follow", limit=120)
    return _call(_service(request).unfollow, business_id, user)


@router.get("/api/me/follows")
def my_follows(request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="shop_follow", limit=120)
    return {"follows": _service(request).my_follows(user)}
