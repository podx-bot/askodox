"""Integration Setup Wizard (Command Center, permission integrations:view).

GET /admin/cc/integrations/catalog          every integration with its computed status
GET /admin/cc/integrations/owner-checklist  what only the Owner can do next, in order
No secret value is ever returned (the catalog holds names and links only).
"""
from __future__ import annotations

from collections import Counter

from fastapi import APIRouter, Request

from app.services import integration_catalog

admin_router = APIRouter(prefix="/admin/cc/integrations", tags=["command-center"])


def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


@admin_router.get("/catalog")
def integration_catalog_view(request: Request) -> dict:
    _require(request, "integrations:view")
    rows = integration_catalog.catalog(request.app.state.container)
    return {"statuses": list(integration_catalog.STATUSES), "categories": integration_catalog.CATEGORIES,
            "summary": dict(Counter(r["status"] for r in rows)), "items": rows}


@admin_router.get("/owner-checklist")
def owner_checklist(request: Request) -> dict:
    _require(request, "integrations:view")
    rows = integration_catalog.catalog(request.app.state.container)
    return {"owner_actions": integration_catalog.owner_checklist(rows),
            "development_pending": [{"key": r["key"], "name": r["name"], "category": r["category_label"],
                                     "note": r["reason"]} for r in rows
                                    if r["status"] == integration_catalog.NOT_BUILT],
            "verified": [{"key": r["key"], "name": r["name"], "status": r["status"]} for r in rows
                         if r["status"] in integration_catalog.DONE_STATUSES]}
