"""Connectivity, pairing and push-to-talk APIs.

Public:   GET  /api/devices/compatibility           what ASKODOX can connect to, and why not
Signed-in (token-proven, ``_authenticated_app_user``):
          GET    /api/devices                       my paired devices
          POST   /api/devices                       register a device the phone paired (BLE)
          PATCH  /api/devices/{device_id}           connection status
          DELETE /api/devices/{device_id}           forget / revoke
          POST   /api/ptt/channels                  create a push-to-talk group (returns a join code)
          POST   /api/ptt/join                      join by code
          GET    /api/ptt/channels                  my groups
          POST   /api/ptt/channels/{id}/leave
          POST   /api/ptt/channels/{id}/clips       send a voice clip (base64, <= 60 s)
          GET    /api/ptt/channels/{id}/clips       clips after a timestamp
          GET    /api/ptt/clips/{clip_id}/audio     members only
"""
from __future__ import annotations

from typing import Any, List

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import rate_limit
from app.services.device_registry import DeviceRegistry, compatibility, match_services
from app.services.push_to_talk import PttError, PushToTalk

router = APIRouter(tags=["Devices"])


def _registry(request: Request) -> DeviceRegistry:
    container: Any = request.app.state.container
    existing = getattr(container, "device_registry", None)
    if existing is None:
        existing = DeviceRegistry(container.settings.database_path, container.settings.session_token_secret)
        try:
            container.device_registry = existing
        except Exception:
            pass
    return existing


def _ptt(request: Request) -> PushToTalk:
    container: Any = request.app.state.container
    existing = getattr(container, "push_to_talk", None)
    if existing is None:
        existing = PushToTalk(container.settings.database_path)
        try:
            container.push_to_talk = existing
        except Exception:
            pass
    return existing


def _raise(error: PttError) -> HTTPException:
    return HTTPException(status_code=error.status, detail=error.message)


class DeviceIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    protocol: str = Field(default="BLE", pattern="^(BLE)$")
    identifier: str = Field(min_length=4, max_length=64)
    service_uuids: List[str] = Field(default_factory=list, max_length=40)
    manufacturer: str = Field(default="", max_length=60)
    model: str = Field(default="", max_length=60)


class DeviceStatusIn(BaseModel):
    status: str = Field(pattern="^(connected|disconnected|paired|error)$")


@router.get("/api/devices/compatibility")
def device_compatibility(request: Request) -> dict:
    rate_limit.check(request, "devices_public", limit=60)
    return {"status": "success", "devices": compatibility()}


@router.post("/api/devices/match")
def device_match(payload: dict, request: Request) -> dict:
    """Which supported profiles a device's services match (no sign-in, nothing stored)."""
    rate_limit.check(request, "devices_public", limit=60)
    uuids = payload.get("service_uuids") if isinstance(payload, dict) else None
    if not isinstance(uuids, list) or len(uuids) > 40:
        raise HTTPException(status_code=422, detail="service_uuids must be a list (max 40)")
    return {"status": "success", "matches": match_services([str(u)[:40] for u in uuids])}


@router.get("/api/devices")
def my_devices(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"status": "success", "devices": _registry(request).list(user)}


@router.post("/api/devices")
def add_device(payload: DeviceIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, "devices_write", limit=30)
    device = _registry(request).add(user, name=payload.name.strip(), protocol=payload.protocol,
                                    identifier=payload.identifier, service_uuids=payload.service_uuids,
                                    manufacturer=payload.manufacturer.strip(), model=payload.model.strip())
    return {"status": "success", "device": device}


@router.patch("/api/devices/{device_id}")
def device_status(device_id: str, payload: DeviceStatusIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    device = _registry(request).update_status(user, device_id, payload.status)
    if device is None:
        raise HTTPException(status_code=404, detail="device not found")
    return {"status": "success", "device": device}


@router.delete("/api/devices/{device_id}")
def forget_device(device_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    if not _registry(request).remove(user, device_id):
        raise HTTPException(status_code=404, detail="device not found")
    return {"status": "success", "removed": True}


# ------------------------------------------------------------------ push-to-talk

class ChannelIn(BaseModel):
    name: str = Field(default="", max_length=60)
    display_name: str = Field(default="", max_length=40)


class JoinIn(BaseModel):
    code: str = Field(min_length=4, max_length=12)
    display_name: str = Field(default="", max_length=40)


class ClipIn(BaseModel):
    audio_base64: str = Field(min_length=4, max_length=2_100_000)
    mime_type: str = Field(default="audio/mp4", max_length=40)
    duration_ms: int = Field(default=0, ge=0, le=70_000)


@router.post("/api/ptt/channels")
def ptt_create(payload: ChannelIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, "ptt_write", limit=20)
    try:
        return {"status": "success", "channel": _ptt(request).create(user, payload.name, payload.display_name)}
    except PttError as error:
        raise _raise(error) from error


@router.post("/api/ptt/join")
def ptt_join(payload: JoinIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, "ptt_join", limit=10)
    try:
        return {"status": "success", "channel": _ptt(request).join(user, payload.code, payload.display_name)}
    except PttError as error:
        raise _raise(error) from error


@router.get("/api/ptt/channels")
def ptt_mine(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"status": "success", "channels": _ptt(request).mine(user)}


@router.post("/api/ptt/channels/{channel_id}/leave")
def ptt_leave(channel_id: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"status": "success", "left": _ptt(request).leave(user, channel_id)}


@router.post("/api/ptt/channels/{channel_id}/clips")
def ptt_post(channel_id: str, payload: ClipIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, "ptt_clip", limit=30)
    try:
        clip = _ptt(request).post_clip(user, channel_id, audio_base64=payload.audio_base64,
                                       mime=payload.mime_type, duration_ms=payload.duration_ms)
    except PttError as error:
        raise _raise(error) from error
    return {"status": "success", "clip": clip}


@router.get("/api/ptt/channels/{channel_id}/clips")
def ptt_clips(channel_id: str, request: Request, after: str = "") -> dict:
    user = _authenticated_app_user(request)
    try:
        return {"status": "success", "clips": _ptt(request).clips(user, channel_id, after[:40])}
    except PttError as error:
        raise _raise(error) from error


@router.get("/api/ptt/clips/{clip_id}/audio")
def ptt_audio(clip_id: str, request: Request) -> Response:
    user = _authenticated_app_user(request)
    try:
        data, mime = _ptt(request).audio(user, clip_id)
    except PttError as error:
        raise _raise(error) from error
    return Response(content=data, media_type=mime, headers={"Cache-Control": "private, max-age=3600"})
