"""Command Center: do shops keep using ASKODOX? (see ``app/services/shop_retention.py``)

Staff only: GET /admin/cc/shop-retention (analytics:view) -- counts, the join-month table, the 30-day trend.
The shops to call (names + the shop's own counter number) are added only for staff who may see users
(users:view); a person's own sign-in number is never shown in full. Nothing here is shown to shops or customers.
"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Request

from app.services.shop_retention import shop_retention

admin_router = APIRouter(prefix="/admin/cc/shop-retention", tags=["command-center"])


@admin_router.get("")
def retention(request: Request, fresh: bool = False) -> Dict[str, Any]:
    from app.api.routes.command_center import _can, _require

    principal = _require(request, "analytics:view")
    names = _can(principal, "users:view")
    out = dict(shop_retention(request.app.state.container).report(lists=names, fresh=bool(fresh)))
    out["can_see_shops"] = names
    return out


guide_admin_router = APIRouter(prefix="/admin/cc/guide-feedback", tags=["command-center"])


@guide_admin_router.get("")
def guide_pages(request: Request, days: int = 30) -> Dict[str, Any]:
    """Pages whose guide people did not understand (owner 2026-11-24): fix these guides / pages first."""
    from app.api.routes.command_center import _require
    from app.api.routes.in_app_assistant import _guide_feedback

    _require(request, "analytics:view")
    return {"days": max(1, min(int(days), 90)),
            "pages": _guide_feedback(request.app.state.container).pages(max(1, min(int(days), 90)))}
