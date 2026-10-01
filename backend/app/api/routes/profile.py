"""GET/PUT /api/me/profile -- the signed-in user's own profile.

One canonical profile for Home, Chat, matching, selling, requests and the
Admin user view. Identity comes only from the session token; the mobile
number is derived from it and cannot be edited here.
"""
from __future__ import annotations

import base64
import binascii
import re
from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.repositories.user_profile_repository import UserProfileRepository

router = APIRouter(prefix="/api/me/profile", tags=["profile"])

PHOTO_LIMIT = 600 * 1024


def profiles(container: Any) -> UserProfileRepository:
    repo = getattr(container, "user_profile_repository", None)
    if repo is None:
        repo = UserProfileRepository(container.settings.database_path)
        container.user_profile_repository = repo
    return repo


def _verification(container: Any, user_id: str) -> dict:
    """Read-only: what ASKODOX actually knows about the seller."""
    seller_repo = getattr(container, "seller_profile_repository", None)
    row = None
    try:
        row = seller_repo.get(user_id) if seller_repo is not None else None
    except Exception:
        row = None
    if not row:
        return {"status": "not_a_seller", "tier": None, "listings": 0, "gstin_on_file": False}
    return {
        "status": "business_verified" if row.get("has_gstin") else "unverified",
        "tier": row.get("tier"),
        "listings": int(row.get("total_listing_count") or 0),
        "gstin_on_file": bool(row.get("has_gstin")),
        "service_provider": bool(row.get("is_service_provider")),
    }


def _view(request: Request, user_id: str, data: dict) -> dict:
    return {**data, "verification": _verification(request.app.state.container, user_id),
            "photo_url": "/api/me/profile/photo" if data.get("has_photo") else None}


class ProfileUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    address: str | None = Field(default=None, max_length=240)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    language: str | None = Field(default=None, max_length=8)
    roles: list[str] | None = Field(default=None, max_length=20)
    business_name: str | None = Field(default=None, max_length=120)
    business_address: str | None = Field(default=None, max_length=240)
    business_category: str | None = Field(default=None, max_length=80)
    gstin: str | None = Field(default=None, max_length=15)
    upi_id: str | None = Field(default=None, max_length=120)
    email: str | None = Field(default=None, max_length=160)
    active_role: str | None = Field(default=None, max_length=30)
    links: list[dict] | None = Field(default=None, max_length=10)
    role_details: dict | None = None


@router.get("")
def my_profile(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    return _view(request, user_id, profiles(request.app.state.container).get(user_id))


@router.put("")
def update_my_profile(payload: ProfileUpdate, request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    fields = {k: (v.strip() if isinstance(v, str) else v) for k, v in payload.model_dump(exclude_unset=True).items()}
    if "gstin" in fields and fields["gstin"]:
        fields["gstin"] = str(fields["gstin"]).upper()
        if len(fields["gstin"]) != 15 or not fields["gstin"].isalnum():
            raise HTTPException(status_code=422, detail="GSTIN must be 15 letters/digits")
    if "upi_id" in fields and fields["upi_id"]:
        from app.services.payment_gateway import valid_vpa

        if not valid_vpa(fields["upi_id"]):
            raise HTTPException(status_code=422, detail="Enter a valid UPI ID, e.g. name@okbank")
    if "roles" in fields:
        fields["roles"] = [str(r).strip()[:30] for r in (fields["roles"] or []) if str(r).strip()]
    repo = profiles(request.app.state.container)
    current = repo.get(user_id)
    if fields.get("email"):
        if not _EMAIL.match(fields["email"]):
            raise HTTPException(status_code=422, detail="Enter a valid e-mail address")
    if "links" in fields:
        fields["links"] = _clean_links(fields["links"] or [])
    if "role_details" in fields:
        fields["role_details"] = _clean_role_details(fields["role_details"] or {}, current.get("role_details") or {})
    if fields.get("active_role"):
        # A role is switched only explicitly, and only to one the user holds.
        roles = fields.get("roles", current.get("roles") or [])
        if fields["active_role"] not in roles:
            raise HTTPException(status_code=422, detail="Add this role to your profile before switching to it")
    if "roles" in fields and current.get("active_role") and current["active_role"] not in fields["roles"] \
            and "active_role" not in fields:
        fields["active_role"] = None  # the removed role cannot stay active
    return _view(request, user_id, profiles(request.app.state.container).update(user_id, fields))


_EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,120}\.[a-z]{2,24}$", re.IGNORECASE)
_LINK_KINDS = {"website", "whatsapp", "instagram", "facebook", "youtube", "linkedin", "x", "telegram", "maps", "other"}


def _clean_links(links: list) -> list:
    out = []
    for item in links[:10]:
        url = str((item or {}).get("url") or "").strip()
        kind = str((item or {}).get("kind") or "other").strip().lower()
        if not url:
            continue
        if not (url.startswith("https://") or url.startswith("http://") or kind == "whatsapp"):
            raise HTTPException(status_code=422, detail="Links must start with https://")
        out.append({"kind": kind if kind in _LINK_KINDS else "other", "url": url[:300]})
    return out


def _clean_role_details(details: dict, current: dict) -> dict:
    """Per-role extension of the ONE profile. Known roles keep only their
    fields; future roles are accepted generically. Text values only, small."""
    from app.repositories.user_profile_repository import ROLE_FIELDS

    merged = dict(current)
    for role, values in list(details.items())[:12]:
        role = str(role).strip().lower()[:30]
        if not role or not isinstance(values, dict):
            continue
        allowed = ROLE_FIELDS.get(role)
        clean = {}
        for key, value in list(values.items())[:20]:
            key = str(key).strip()[:40]
            if allowed is not None and key not in allowed:
                continue
            if isinstance(value, list):
                value = [str(v)[:80] for v in value[:20]]
            elif value is not None:
                value = str(value)[:400]
            clean[key] = value
        merged[role] = {**(merged.get(role) or {}), **clean}
    return merged


@router.get("/schema")
def profile_schema() -> dict:
    """The roles a person can hold and the fields each adds (for the app's forms)."""
    from app.repositories.user_profile_repository import ROLE_FIELDS

    return {"roles": {role: list(fields) for role, fields in ROLE_FIELDS.items()},
            "link_kinds": sorted(_LINK_KINDS)}


class PhotoUpload(BaseModel):
    photo_base64: str = Field(min_length=1)


@router.put("/photo")
def upload_photo(payload: PhotoUpload, request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    try:
        data = base64.b64decode(payload.photo_base64, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail="invalid photo data") from error
    if not data:
        raise HTTPException(status_code=400, detail="empty photo")
    if len(data) > PHOTO_LIMIT:
        raise HTTPException(status_code=413, detail="photo too large (max 600 KB)")
    if not (data[:3] == b"\xff\xd8\xff" or data[:8] == b"\x89PNG\r\n\x1a\n"):
        raise HTTPException(status_code=415, detail="photo must be JPEG or PNG")
    return _view(request, user_id, profiles(request.app.state.container).set_photo(user_id, data))


@router.delete("/photo")
def remove_photo(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    return _view(request, user_id, profiles(request.app.state.container).set_photo(user_id, None))


@router.get("/photo")
def my_photo(request: Request) -> Response:
    user_id = _authenticated_app_user(request)
    data = profiles(request.app.state.container).photo(user_id)
    if data is None:
        raise HTTPException(status_code=404, detail="no photo")
    media = "image/png" if data[:4] == b"\x89PNG" else "image/jpeg"
    return Response(content=data, media_type=media, headers={"Cache-Control": "private, max-age=300"})
