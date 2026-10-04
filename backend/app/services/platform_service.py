"""Generic Command Center resource engine on top of PlatformRepository.

Every resource defined in platform_schema gets the same real operations:
create, edit (optimistic lock), view, delete, lifecycle actions (approve /
reject / enable / disable / pause / resume / schedule / expire / verify /
feature ...), duplicate, archive, restore, search, filter, sort, export (CSV)
and audit history. Effects that need more than a status change (link health
test, template preview) are delegated to their engines.
"""
from __future__ import annotations

import csv
import io
from typing import Any, Callable, Dict, List, Optional

from app.repositories.platform_repository import PlatformRepository
from app.services import platform_schema as ps


class ResourceService:
    def __init__(self, repo: PlatformRepository, *, effects: Dict[str, Callable[..., Dict[str, Any]]] | None = None,
                 ref_exists: Callable[[str, str], bool] | None = None) -> None:
        self.repo = repo
        self.effects = effects or {}
        self.ref_exists = ref_exists

    # ------------------------------------------------------------ helpers --

    def _check_refs(self, res: ps.Resource, data: Dict[str, Any]) -> None:
        for spec in res.fields:
            value = data.get(spec.name)
            if spec.kind != "ref" or not value or not spec.ref:
                continue
            if spec.ref in ps.RESOURCES:
                target = self.repo.get(str(value))
                if not target or target["resource"] != spec.ref:
                    raise ps.SchemaError(f"{spec.name}: no {ps.RESOURCES[spec.ref].label.lower()} {value}")
            elif self.ref_exists and not self.ref_exists(spec.ref, str(value)):
                raise ps.SchemaError(f"{spec.name}: unknown {spec.ref} {value}")

    def _unique(self, res: ps.Resource, data: Dict[str, Any], record_id: str | None = None) -> None:
        unique = {"smart_links": "slug", "notification_templates": "key", "advisor_categories": "key"}.get(res.name)
        if not unique:
            return
        value = str(data.get(unique) or "").lower()
        for other in self.repo.list(res.name, include_archived=True):
            if other["id"] != record_id and str(other["data"].get(unique) or "").lower() == value:
                if res.name == "notification_templates" and (
                        other["data"].get("channel"), other["data"].get("language")) != (
                        data.get("channel"), data.get("language")):
                    continue
                raise ps.SchemaError(f"{unique} '{value}' is already used")

    # ---------------------------------------------------------------- CRUD --

    def create(self, name: str, data: Dict[str, Any], *, actor: str, owner_ref: str | None = None,
               status: str | None = None) -> Dict[str, Any]:
        res = ps.resource(name)
        clean = ps.clean_data(res, data)
        self._check_refs(res, clean)
        self._unique(res, clean)
        initial = status or res.initial_status
        if initial not in res.statuses:
            raise ps.SchemaError("unknown status")
        return self.repo.create(name, res.prefix, name=ps.record_name(res, clean), status=initial, data=clean,
                                actor=actor, owner_ref=owner_ref)

    def update(self, name: str, record_id: str, data: Dict[str, Any], *, actor: str,
               expected_version: int | None = None, owner_ref: str | None = None) -> Dict[str, Any]:
        res = ps.resource(name)
        record = self._get(name, record_id, owner_ref=owner_ref)
        clean = ps.clean_data(res, data, partial=True, existing=record["data"])
        self._check_refs(res, clean)
        self._unique(res, clean, record_id)
        # Changing what a live, customer-facing record shows needs review
        # again when the resource has a review step.
        status = None
        if record["status"] == "ACTIVE" and "PENDING_REVIEW" in res.statuses and owner_ref:
            status = "PENDING_REVIEW"
        return self.repo.update(record_id, actor=actor, action="edit", name=ps.record_name(res, clean), data=clean,
                                status=status, expected_version=expected_version)

    def _get(self, name: str, record_id: str, *, owner_ref: str | None = None) -> Dict[str, Any]:
        record = self.repo.get(record_id)
        if not record or record["resource"] != name or (owner_ref is not None and record["owner_ref"] != owner_ref):
            raise KeyError(record_id)
        return record

    def get(self, name: str, record_id: str, *, owner_ref: str | None = None) -> Dict[str, Any]:
        return self._get(name, record_id, owner_ref=owner_ref)

    def delete(self, name: str, record_id: str, *, actor: str) -> None:
        self._get(name, record_id)
        self.repo.delete(record_id, actor=actor)

    def action(self, name: str, record_id: str, action_name: str, *, actor: str,
               params: Dict[str, Any] | None = None, owner_ref: str | None = None) -> Dict[str, Any]:
        res = ps.resource(name)
        record = self._get(name, record_id, owner_ref=owner_ref)
        params = params or {}
        if action_name == "archive":
            return self.repo.update(record_id, actor=actor, action="archive", archived=True)
        if action_name == "restore":
            return self.repo.update(record_id, actor=actor, action="restore", archived=False)
        if action_name == "duplicate":
            data = dict(record["data"])
            name_key = res.name_field if res.name_field in data else "title"
            if name_key in data and data[name_key]:
                data[name_key] = f"{data[name_key]} (copy)"[:300]
            for unique in ("slug", "key"):
                if unique in data and res.name in ("smart_links", "notification_templates"):
                    data[unique] = f"{data[unique]}-copy"[:63]
            first = "DRAFT" if "DRAFT" in res.statuses else res.initial_status
            return self.create(name, data, actor=actor, owner_ref=record["owner_ref"], status=first)
        if record["archived"]:
            raise ps.SchemaError("restore the record first")
        action = ps.allowed_action(res, action_name, record["status"])
        data = dict(record["data"])
        if action.effect == "schedule":
            start = params.get("start") or data.get("valid_from") or data.get("start_at")
            if not start:
                raise ps.SchemaError("scheduling needs a start date")
            key = "valid_from" if res.field("valid_from") else "start_at"
            data[key] = ps.clean_value(ps.F(key, "Start", "date"), start)
        elif action.effect in ("feature", "unfeature"):
            data["featured"] = action.effect == "feature"
        elif action.effect in ("verify", "unverify"):
            data["verified"] = action.effect == "verify"
        elif action.effect in self.effects:
            result = self.effects[action.effect](record, params)
            if result.get("data") is not None:
                data = result["data"]
                self.repo.update(record_id, actor=actor, action=action_name, data=data)
            if action.to_status:  # an effect that is also a status transition
                self.repo.update(record_id, actor=actor, action=action_name, status=action.to_status)
            return {**(self.repo.get(record_id) or {}), "result": result.get("result")}
        return self.repo.update(record_id, actor=actor, action=action_name, status=action.to_status, data=data)

    # ------------------------------------------------------------- queries --

    def list(self, name: str, *, q: str = "", status: str = "", archived: bool = False,
             filters: Dict[str, str] | None = None, sort: str = "-updated_at", owner_ref: str | None = None,
             limit: int = 500) -> List[Dict[str, Any]]:
        res = ps.resource(name)
        items = self.repo.list(name, include_archived=archived, status=status or None, owner_ref=owner_ref)
        if archived:
            items = [i for i in items if i["archived"]]
        needle = q.strip().lower()
        if needle:
            items = [i for i in items if needle in i["name"].lower() or needle in i["id"].lower()
                     or any(needle in str(v).lower() for v in i["data"].values())]
        for key, value in (filters or {}).items():
            spec = res.field(key)
            if not spec or not value:
                continue
            want = str(value).lower()
            items = [i for i in items if (want in [str(x).lower() for x in i["data"].get(key) or []]
                                          if spec.kind == "list" else str(i["data"].get(key) or "").lower() == want)]
        reverse = sort.startswith("-")
        key = sort.lstrip("-")

        def sort_key(item: Dict[str, Any]) -> Any:
            if key in ("updated_at", "created_at", "name", "status", "id"):
                return str(item.get(key) or "")
            value = item["data"].get(key)
            return (value is None, value if isinstance(value, (int, float)) else str(value or ""))

        items.sort(key=sort_key, reverse=reverse)
        return items[:limit]

    def export_csv(self, name: str, **query: Any) -> str:
        res = ps.resource(name)
        items = self.list(name, **query)
        out = io.StringIO()
        writer = csv.writer(out)
        cols = [f.name for f in res.fields]
        writer.writerow(["id", "status", "archived", "updated_at", *cols])
        for item in items:
            row = [item["id"], item["status"], item["archived"], item["updated_at"]]
            for col in cols:
                value = item["data"].get(col)
                row.append(", ".join(map(str, value)) if isinstance(value, list) else ("" if value is None else value))
            writer.writerow(row)
        return out.getvalue()

    def history(self, name: str, record_id: str) -> List[Dict[str, Any]]:
        self._get(name, record_id)
        return self.repo.history(record_id)

    def live(self, name: str) -> List[Dict[str, Any]]:
        return [r for r in self.repo.list(name) if ps.is_live(r)]

    def search_all(self, q: str, *, limit: int = 30) -> List[Dict[str, Any]]:
        needle = q.strip().lower()
        if len(needle) < 2:
            return []
        hits: List[Dict[str, Any]] = []
        for record in self.repo.all_records(ps.RESOURCES):
            text = f"{record['name']} {record['id']} " + " ".join(str(v) for v in record["data"].values())
            if needle in text.lower():
                res = ps.RESOURCES[record["resource"]]
                hits.append({"id": record["id"], "resource": record["resource"], "resource_label": res.label,
                             "name": record["name"], "status": record["status"]})
            if len(hits) >= limit:
                break
        return hits


def single(items: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    return items[0] if items else None
