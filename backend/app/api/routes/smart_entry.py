"""Universal Smart Entry (Command Center / Staff Workspace).

  POST /admin/cc/smart-entry   {inputs: [url | text, ...], target}
                               -> prepared forms (fields with value /
                                  confidence / provenance), nothing saved

``target`` is one of ``smart_entry.TARGET_FIELDS`` or ``auto`` (best fit per
input). The caller needs create rights for the module it is filling in
(``<module>:manage`` implies create); ``auto`` needs any of them. Pages are
read through the same guarded fetcher as the affiliate extractor (public
https only, every redirect re-checked).
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _principal
from app.services import governance as gov
from app.services import smart_entry

router = APIRouter(prefix="/admin/cc", tags=["smart-entry"])

TARGET_PERMISSION = {  # the permission the form's own save endpoint checks
    "offer": "growth:manage", "merchant_offer": "offers:create", "affiliate_link": "affiliate:create",
    "catalog": "affiliate_products:create", "content": "affiliate_products:create", "source": "sources:create",
    "video": "content:create", "sponsored": "sponsored:manage",
}


class SmartEntryBody(BaseModel):
    inputs: list[str] = Field(default_factory=list)
    target: str = "auto"


@router.post("/smart-entry")
def smart_entry_prepare(body: SmartEntryBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    target = body.target if body.target in smart_entry.TARGET_FIELDS else "auto"
    needed = [TARGET_PERMISSION[target]] if target != "auto" else sorted(set(TARGET_PERMISSION.values()))
    if not any(gov.has_permission(principal["permissions"], p) for p in needed):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs {needed[0]})")
    inputs = [str(i) for i in body.inputs if str(i or "").strip()]
    if not inputs:
        raise HTTPException(status_code=400, detail="Paste at least one link or text.")
    from app.services import rate_limit

    rate_limit.check(request, "smart_entry", limit=30)
    fetch = getattr(request.app.state.container, "affiliate_page_fetch", None)
    result = smart_entry.ingest_batch(inputs, target, fetch=fetch)
    if target == "auto":  # each item still needs rights for the form it lands in
        for item in result["items"]:
            perm = TARGET_PERMISSION.get(item.get("target") or "")
            item["can_save"] = bool(perm and gov.has_permission(principal["permissions"], perm))
    result["targets"] = sorted(smart_entry.TARGET_FIELDS)
    return result
