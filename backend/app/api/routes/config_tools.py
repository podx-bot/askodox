"""Feature-flag targeting + configuration import / export.

Public (app + web, same backend):
  GET  /api/flags                         effective flags for this client (platform / category / role / location)

Command Center:
  POST /admin/cc/flags/evaluate           every flag for a sample context, with the reason (config:view)
  GET  /admin/cc/config-bundle/resources  exportable resources (config:view)
  POST /admin/cc/config-bundle/export     JSON bundle, secrets redacted (config:view + each resource's :view)
  POST /admin/cc/config-bundle/preview    validate + diff + conflicts, changes nothing (config:view)
  POST /admin/cc/config-bundle/apply      apply after preview (config:manage + resources' :manage, confirm)
  GET  /admin/cc/config-bundle/snapshots  applied imports / rollbacks (config:view)
  POST /admin/cc/config-bundle/rollback/{id}  undo one import (config:manage, confirm)
"""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _require, _require_confirm, command_center
from app.repositories.command_center_repository import FEATURE_FLAGS
from app.services import config_bundle as cb
from app.services import flag_targeting as ft
from app.services import governance as gov
from app.services import platform_schema as ps

router = APIRouter(tags=["config-tools"])

# Flags a client (app / web chat) may read; server-side behaviour flags stay
# server-side.
_CLIENT_FLAGS = ("advisor.enabled", "results.videos", "results.online", "results.used", "results.deals",
                 "results.sponsored", "results.affiliate", "ai.assistant", "voice.sarvam_tts", "companion.enabled",
                 "companion.floating_bubble", "companion.screen_guide", "referrals", "coupons", "rewards",
                 "support.escalation", "links.smart", "offers.merchant")


def _pf(container):
    from app.api.routes.platform import platform

    return platform(container)


def _store(container) -> cb.SnapshotStore:
    store = getattr(container, "config_snapshot_store", None)
    if store is None or store.db_path != container.settings.database_path:
        store = cb.SnapshotStore(container.settings.database_path)
        container.config_snapshot_store = store
    return store


@router.get("/api/flags")
def client_flags(request: Request, platform: str = "", category: str = "", role: str = "", location: str = "",
                 subject: str = "") -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "client_flags", limit=60)
    ctx = ft.make_context(platform=platform, category=category, role=role, location=location, subject=subject)
    flags = ft.effective(request.app.state.container, ctx)
    return {"flags": {k: flags.get(k, True) for k in _CLIENT_FLAGS}}


class EvaluateBody(BaseModel):
    category: str = ""
    subcategory: str = ""
    role: str = ""
    platform: str = ""
    location: str = ""
    subject: str = ""


@router.post("/admin/cc/flags/evaluate")
def evaluate(body: EvaluateBody, request: Request) -> dict:
    _require(request, "config:view")
    ctx = ft.make_context(**body.model_dump())
    return {"context": ctx, "flags": ft.effective(request.app.state.container, ctx, explain=True),
            "rules": len(ft.active_rules(request.app.state.container))}


@router.get("/admin/cc/config-bundle/resources")
def bundle_resources(request: Request) -> dict:
    principal = _require(request, "config:view")
    out = []
    for name in cb.CONFIG_RESOURCES:
        res = ps.resource(name)
        out.append({"name": name, "label": res.label, "group": res.group,
                    "can_export": gov.has_permission(principal["permissions"], f"{res.permission}:view"),
                    "can_import": gov.has_permission(principal["permissions"], f"{res.permission}:manage")})
    return {"resources": out, "never_exported": ["integration credentials", "API keys / tokens / secrets",
                                                 "affiliate programs and links", "owner-scoped business data",
                                                 "user data"]}


class ExportBody(BaseModel):
    resources: List[str] = Field(default_factory=lambda: list(cb.CONFIG_RESOURCES))
    include_flags: bool = True


def _check_resources(principal, names, level: str) -> None:
    for name in names:
        if name not in cb.CONFIG_RESOURCES:
            raise HTTPException(status_code=400, detail=f"'{name}' is not an importable configuration resource")
        need = f"{ps.resource(name).permission}:{level}"
        if not gov.has_permission(principal["permissions"], need):
            raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs {need})")


@router.post("/admin/cc/config-bundle/export")
def export_bundle(body: ExportBody, request: Request) -> dict:
    principal = _require(request, "config:view")
    _check_resources(principal, body.resources, "view")
    container = request.app.state.container
    cc = command_center(container)
    bundle = cb.export(_pf(container).repo, cc.flags_map(), body.resources, actor=principal["id"],
                       include_flags=body.include_flags)
    cc.audit(principal["id"], "config_export", "config_bundle", ",".join(body.resources)[:200], None,
             {"records": sum(len(v) for v in bundle["resources"].values())}, "", role=principal.get("role"))
    return bundle


class BundleBody(BaseModel):
    bundle: Dict[str, Any]
    confirm: bool = False
    allow_conflicts: bool = False
    reason: str = Field(default="", max_length=300)


def _preview(request, principal, body: BundleBody, level: str) -> dict:
    container = request.app.state.container
    _check_resources(principal, list((body.bundle.get("resources") or {}).keys()), level)
    try:
        return cb.preview(_pf(container).repo, command_center(container).flags_map(), body.bundle,
                          known_flags=FEATURE_FLAGS)
    except cb.BundleError as error:
        raise HTTPException(status_code=400, detail=str(error)) from None


@router.post("/admin/cc/config-bundle/preview")
def preview_bundle(body: BundleBody, request: Request) -> dict:
    principal = _require(request, "config:view")
    plan = _preview(request, principal, body, "view")
    risky = [f["key"] for f in plan["flags"] if gov.flag_risk(f["key"]) != gov.GREEN]
    plan["needs_owner"] = risky
    return plan


@router.post("/admin/cc/config-bundle/apply")
def apply_bundle(body: BundleBody, request: Request) -> dict:
    principal = _require(request, "config:manage")
    plan = _preview(request, principal, body, "manage")
    risky = [f["key"] for f in plan["flags"] if gov.flag_risk(f["key"]) != gov.GREEN]
    if risky and not gov.is_super(principal):
        raise HTTPException(status_code=403, detail=f"Only the Owner can import changes to: {', '.join(risky)}")
    _require_confirm(body.confirm, "apply this configuration")
    container = request.app.state.container
    try:
        return cb.apply(_pf(container).resources, command_center(container), _store(container), body.bundle,
                        actor=principal["id"], reason=body.reason, allow_conflicts=body.allow_conflicts,
                        role=principal.get("role"))
    except cb.BundleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None


@router.get("/admin/cc/config-bundle/snapshots")
def snapshots(request: Request) -> dict:
    _require(request, "config:view")
    return {"items": _store(request.app.state.container).list()}


class RollbackBody(BaseModel):
    confirm: bool = False


@router.post("/admin/cc/config-bundle/rollback/{snapshot_id}")
def rollback(snapshot_id: str, body: RollbackBody, request: Request) -> dict:
    principal = _require(request, "config:manage")
    _require_confirm(body.confirm, "roll back this import")
    container = request.app.state.container
    snap = _store(container).get(snapshot_id)
    if snap is None:
        raise HTTPException(status_code=404, detail="Unknown snapshot")
    _check_resources(principal, list((snap["bundle"].get("resources") or {}).keys()), "manage")
    if snap["bundle"].get("flags") and not gov.is_super(principal) and any(
            gov.flag_risk(k) != gov.GREEN for k in snap["bundle"]["flags"]):
        raise HTTPException(status_code=403, detail="Only the Owner can roll back flag changes")
    try:
        return cb.rollback(_pf(container).resources, command_center(container), _store(container), snapshot_id,
                           actor=principal["id"], role=principal.get("role"))
    except cb.BundleError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
