"""Shop follow routes: any signed-in person (shop owners too). Identity from the bearer token only."""

from __future__ import annotations

import base64
import binascii
from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.pos import _store, _user
from app.services.pos_store import PosError
from app.services.shop_follows import ShopFollows, shop_categories

router = APIRouter(tags=["Shop follows"])


def _service(request: Request) -> ShopFollows:
    return ShopFollows(_store(request).db_path)


def _call(fn, *args) -> Dict[str, Any]:
    try:
        return fn(*args)
    except PosError as error:
        raise HTTPException(status_code=error.status,
                            detail={"code": error.code, "message": error.message})


@router.get("/api/shops/categories")
def categories(request: Request) -> Dict[str, Any]:
    """Ready-to-pick shop categories + sub-categories (registered BEFORE /api/shops/{business_id})."""
    _user(request, bucket="shop_follow", limit=240)
    return {"categories": shop_categories()}


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


class ShopPostIn(BaseModel):
    caption: str = Field(default="", max_length=600)
    image_base64: str = Field(default="", max_length=1_300_000)


@router.post("/api/shops/{business_id}/posts")
def post_shop_picture(business_id: str, body: ShopPostIn, request: Request) -> Dict[str, Any]:
    """The owner's one picture a day for this shop (the phone draws the shop name and ASKODOX brand into it)."""
    user = _user(request, bucket="shop_post", limit=20)
    try:
        image = base64.b64decode(body.image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=400, detail={"code": "image", "message": "Picture is not valid base64."})
    return _call(_service(request).post, business_id, user, body.caption, image)


@router.get("/api/me/feed")
def my_feed(request: Request) -> Dict[str, Any]:
    """Pictures from the shops this person follows (newest first). Each picture is opened by its own id below."""
    user = _user(request, bucket="shop_feed", limit=240)
    return {"posts": _service(request).feed(user)}


@router.get("/api/shop-posts/{post_id}/image")
def shop_post_image(post_id: str, request: Request) -> Response:
    user = _user(request, bucket="shop_feed", limit=240)
    try:
        data = _service(request).image(post_id, user)
    except PosError as error:
        raise HTTPException(status_code=error.status,
                            detail={"code": error.code, "message": error.message})
    return Response(content=data, media_type="image/png", headers={"Cache-Control": "private, max-age=3600"})


class ShopProfileIn(BaseModel):
    """The shop's own details, in the owner's words. Every field is optional text; the server trims each one."""
    category: str = Field(default="", max_length=400)
    subcategory: str = Field(default="", max_length=400)
    description: str = Field(default="", max_length=2000)
    address: str = Field(default="", max_length=600)
    landmark: str = Field(default="", max_length=400)
    hours: str = Field(default="", max_length=400)
    website: str = Field(default="", max_length=600)
    facebook: str = Field(default="", max_length=600)
    instagram: str = Field(default="", max_length=600)
    youtube: str = Field(default="", max_length=600)
    whatsapp: str = Field(default="", max_length=60)
    offers: str = Field(default="", max_length=1000)
    delivery: str = Field(default="", max_length=400)
    extra: str = Field(default="", max_length=2000)
    reg_number: str = Field(default="", max_length=120)


@router.put("/api/shops/{business_id}/profile")
def save_shop_profile(business_id: str, body: ShopProfileIn, request: Request) -> Dict[str, Any]:
    user = _user(request, bucket="shop_profile", limit=60)
    return _call(_service(request).save_profile, business_id, user, body.model_dump())
