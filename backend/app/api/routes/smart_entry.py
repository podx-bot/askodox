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
    csv: str = Field(default="", max_length=500_000)


class ImportItem(BaseModel):
    target: str
    fields: dict[str, Any] = Field(default_factory=dict)
    update_id: Any = None  # set for an UPDATE the staff member chose to apply


class ImportBody(BaseModel):
    items: list[ImportItem] = Field(default_factory=list)
    defaults: dict[str, Any] = Field(default_factory=dict)  # template / form defaults (structure only)
    confirm: bool = False


def _platform(request: Request):
    from app.api.routes.platform import platform

    return platform(request.app.state.container).resources


def _catalog(request: Request):
    from app.api.routes.affiliate_catalog import catalog

    return catalog(request.app.state.container)


def _existing(request: Request, item: dict[str, Any]) -> dict[str, Any] | None:
    """The stored record with the same identity as a prepared item, or None."""
    target = item.get("target")
    vals = {k: (f or {}).get("value") for k, f in (item.get("fields") or {}).items()}
    try:
        if target in ("catalog", "content") and vals.get("source_url"):
            store = _catalog(request)
            same = store.duplicates(vals["source_url"])
            if same:
                full = store.get(int(same[0]["id"])) or same[0]
                images = full.get("images") or []
                return {**full, "images": images, "original_product_url": full.get("original_product_url")}
            return None
        resource = smart_entry.PLATFORM_RESOURCE.get(target or "")
        if not resource:
            return None
        key = {"affiliate_link": ("affiliate_url", vals.get("destination_url") or vals.get("source_url")),
               "video": ("url", vals.get("source_url")), "source": ("domains", vals.get("domain")),
               "merchant_offer": ("title", vals.get("title"))}[target]
        if not key[1]:
            return None
        for rec in _platform(request).list(resource, limit=5000):
            have = rec["data"].get(key[0])
            hit = (str(key[1]).lower() in [str(x).lower() for x in have]) if isinstance(have, list) \
                else str(have or "").strip().lower() == str(key[1]).strip().lower()
            if hit:
                return {"id": rec["id"], "name": rec["name"], **rec["data"]}
    except Exception:
        return None  # a lookup problem never blocks preparing a form
    return None


@router.post("/smart-entry")
def smart_entry_prepare(body: SmartEntryBody, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    target = body.target if body.target in smart_entry.TARGET_FIELDS else "auto"
    needed = [TARGET_PERMISSION[target]] if target != "auto" else sorted(set(TARGET_PERMISSION.values()))
    if not any(gov.has_permission(principal["permissions"], p) for p in needed):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs {needed[0]})")
    inputs = [str(i) for i in body.inputs if str(i or "").strip()]
    if not inputs and not body.csv.strip():
        raise HTTPException(status_code=400, detail="Paste at least one link or text.")
    from app.services import rate_limit

    rate_limit.check(request, "smart_entry", limit=30)
    fetch = getattr(request.app.state.container, "affiliate_page_fetch", None)
    if body.csv.strip():  # staff-typed rows: validated and classified, nothing fetched
        rows = smart_entry.parse_csv(body.csv, target if target != "auto" else "catalog")
        if not rows:
            raise HTTPException(status_code=400, detail="The CSV has a header row but no data rows.")
        result = {"items": rows, "count": len(rows), "duplicates_skipped": 0, "failed": 0, "truncated": 0}
    else:
        result = smart_entry.ingest_batch(inputs, target, fetch=fetch)
    seen: set[str] = set()
    for item in result["items"]:
        smart_entry.verdict(item, _existing(request, item))
        ident = str(((item.get("fields") or {}).get("source_url") or {}).get("value") or "")
        if ident and item["verdict"] in ("NEW", "NEEDS_REVIEW") and ident in seen:
            item["verdict"] = "DUPLICATE"  # the same link twice in one CSV / paste
            item["existing"] = {"id": None, "title": "earlier row in this batch"}
        if ident:
            seen.add(ident)
        item["importable"] = item.get("target") in smart_entry.IMPORTABLE
    result["verdicts"] = smart_entry.summarize(result["items"])
    if target == "auto":  # each item still needs rights for the form it lands in
        for item in result["items"]:
            perm = TARGET_PERMISSION.get(item.get("target") or "")
            item["can_save"] = bool(perm and gov.has_permission(principal["permissions"], perm))
    result["targets"] = sorted(smart_entry.TARGET_FIELDS)
    return result


@router.get("/smart-entry/templates")
def smart_entry_templates(request: Request, target: str = "") -> dict[str, Any]:
    """Built-in templates + the ACTIVE ones staff saved (entry_templates)."""
    principal = _principal(request)
    if not any(gov.has_permission(principal["permissions"], p) for p in set(TARGET_PERMISSION.values())):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    items = [dict(t) for t in smart_entry.TEMPLATES]
    try:
        for rec in _platform(request).list("entry_templates", status="ACTIVE"):
            items.append({"id": rec["id"], "label": rec["name"], "target": rec["data"].get("target"),
                          "defaults": rec["data"].get("defaults") or {}, "example": "",
                          "hint": rec["data"].get("notes") or "Saved by staff", "builtin": False})
    except Exception:
        pass
    if target:
        items = [t for t in items if t["target"] == target]
    return {"items": items, "groups": smart_entry.FIELD_GROUPS, "importable": sorted(smart_entry.IMPORTABLE)}


@router.post("/smart-entry/import")
def smart_entry_import(body: ImportBody, request: Request) -> dict[str, Any]:
    """Saves the items staff selected in the bulk preview as DRAFTS / review
    items (never live): catalog rows NEEDS_REVIEW, platform records in their
    resource's first status. One failing item never stops the rest."""
    principal = _principal(request)
    if not any(gov.has_permission(principal["permissions"], p) for p in set(TARGET_PERMISSION.values())):
        raise HTTPException(status_code=403, detail=gov.FORBIDDEN)
    if not body.confirm:
        raise HTTPException(status_code=400, detail="Confirm the import after checking the preview.")
    if not body.items:
        raise HTTPException(status_code=400, detail="Select at least one item.")
    if len(body.items) > smart_entry.MAX_BATCH * 4:
        raise HTTPException(status_code=400, detail=f"At most {smart_entry.MAX_BATCH * 4} items at a time.")
    facts = sorted(set(body.defaults) & _fact_fields())
    if facts:
        raise HTTPException(status_code=400, detail="Defaults hold structure only, never " + ", ".join(facts))
    from app.services import rate_limit

    rate_limit.check(request, "smart_entry_import", limit=10)
    results: list[dict[str, Any]] = []
    for index, item in enumerate(body.items):
        target = item.target
        perm = TARGET_PERMISSION.get(target)
        if target not in smart_entry.IMPORTABLE or not perm:
            results.append({"index": index, "ok": False, "error": "Open this one in its form (needs a person)."})
            continue
        if not gov.has_permission(principal["permissions"], perm):
            results.append({"index": index, "ok": False, "error": f"{gov.FORBIDDEN} (needs {perm})"})
            continue
        defaults = {k: v for k, v in body.defaults.items() if k not in ("platform",)} \
            if target in ("catalog", "content") else dict(body.defaults)
        values = smart_entry.to_record(target, item.fields, defaults)
        if target in ("catalog", "content") and body.defaults.get("platform"):
            values.setdefault("platform", body.defaults["platform"])
        try:
            if target in ("catalog", "content"):
                store = _catalog(request)
                if item.update_id:
                    rec = store.update(int(item.update_id), {k: v for k, v in values.items()
                                                             if k != "original_product_url"},
                                       actor=principal["id"])
                else:
                    rec = store.create(values, actor=principal["id"], check_source="manual",
                                       review_status="NEEDS_REVIEW")
                results.append({"index": index, "ok": True, "id": rec["id"], "store": "affiliate_products",
                                "status": rec.get("review_status") or "NEEDS_REVIEW"})
            else:
                resource = smart_entry.PLATFORM_RESOURCE[target]
                pf = _platform(request)
                rec = (pf.update(resource, str(item.update_id), values, actor=principal["id"]) if item.update_id
                       else pf.create(resource, values, actor=principal["id"]))
                results.append({"index": index, "ok": True, "id": rec["id"], "store": resource,
                                "status": rec.get("status")})
        except Exception as error:  # SchemaError / ValueError / LookupError: report, continue
            results.append({"index": index, "ok": False, "error": str(error)[:300]})
    ok = sum(1 for r in results if r["ok"])
    try:
        from app.api.routes.affiliate_catalog import command_center

        command_center(request.app.state.container).audit(
            principal["id"], "smart_entry.import", "smart_entry", "bulk", before=None,
            after={"selected": len(body.items), "saved": ok}, role=principal.get("role"))
    except Exception:
        pass
    return {"results": results, "saved": ok, "failed": len(results) - ok}


def _fact_fields() -> frozenset[str]:
    from app.services.platform_schema import TEMPLATE_FACT_FIELDS

    return TEMPLATE_FACT_FIELDS
