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
