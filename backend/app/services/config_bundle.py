"""Command Center configuration import / export.

Export: the configuration resources (advisor, demand rules, settings, flag
targeting, notification templates / rules, greetings, referral rules) plus
the feature-flag states, as ONE JSON bundle. Secrets never leave: secret-like
keys and values are redacted and integration / affiliate / owner-scoped data
is not exportable at all.

Import: preview first (schema validation per record, create / update /
unchanged per record, conflicts = the record changed here after the bundle
was exported), then apply. Apply stores a snapshot of everything it is about
to touch, so one rollback restores it (records the import created are
archived, never deleted; every change keeps record history + audit).
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional

from app.services import platform_schema as ps
from app.services.governance import REDACTED, redact

FORMAT = "askodox-config"
VERSION = 1
CONFIG_RESOURCES = ("advisor_categories", "advisor_questions", "advisor_rules", "demand_alert_rules",
                    "platform_settings", "flag_rollouts", "notification_templates", "notification_rules",
                    "greeting_templates", "referral_credit_rules")
MAX_RECORDS = 2000


class BundleError(ValueError):
    pass


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _has_redaction(value: Any) -> bool:
    if isinstance(value, dict):
        return any(_has_redaction(v) for v in value.values())
    if isinstance(value, list):
        return any(_has_redaction(v) for v in value)
    return value == REDACTED or (isinstance(value, str) and REDACTED in value)


def export(repo, flags: Dict[str, bool], resources: Iterable[str], *, actor: str,
           include_flags: bool = True) -> Dict[str, Any]:
    out: Dict[str, Any] = {"format": FORMAT, "version": VERSION, "exported_at": _now(), "exported_by": actor,
                           "resources": {}, "flags": {}}
    for name in resources:
        if name not in CONFIG_RESOURCES:
            raise BundleError(f"'{name}' cannot be exported")
        rows = repo.list(name, include_archived=False)
        out["resources"][name] = [{"id": r["id"], "status": r["status"], "version": r["version"],
                                   "updated_at": r["updated_at"], "data": redact(r["data"])} for r in rows]
    if include_flags:
        out["flags"] = {k: bool(v) for k, v in flags.items()}
    return out


def _load(bundle: Any) -> Dict[str, Any]:
    if isinstance(bundle, str):
        try:
            bundle = json.loads(bundle)
        except ValueError as error:
            raise BundleError(f"not valid JSON: {error}") from None
    if not isinstance(bundle, dict) or bundle.get("format") != FORMAT:
        raise BundleError(f"not an {FORMAT} bundle")
    if int(bundle.get("version") or 0) != VERSION:
        raise BundleError(f"unsupported bundle version {bundle.get('version')}")
    if not isinstance(bundle.get("resources") or {}, dict) or not isinstance(bundle.get("flags") or {}, dict):
        raise BundleError("resources / flags must be objects")
    if sum(len(v or []) for v in (bundle.get("resources") or {}).values()) > MAX_RECORDS:
        raise BundleError(f"more than {MAX_RECORDS} records")
    return bundle


def preview(repo, current_flags: Dict[str, bool], bundle: Any, *, known_flags: Iterable[str]) -> Dict[str, Any]:
    bundle = _load(bundle)
    exported_at = str(bundle.get("exported_at") or "")
    result: Dict[str, Any] = {"valid": True, "errors": [], "conflicts": [], "resources": {}, "flags": [],
                              "summary": {"create": 0, "update": 0, "unchanged": 0, "invalid": 0}}
    for name, rows in (bundle.get("resources") or {}).items():
        if name not in CONFIG_RESOURCES:
            result["errors"].append(f"{name}: not an importable configuration resource")
            result["valid"] = False
            continue
        res = ps.resource(name)
        plan = []
        for index, row in enumerate(rows or []):
            entry: Dict[str, Any] = {"index": index, "id": (row or {}).get("id")}
            try:
                if not isinstance(row, dict) or not isinstance(row.get("data"), dict):
                    raise ps.SchemaError("record needs a data object")
                if _has_redaction(row["data"]):
                    raise ps.SchemaError("contains a redacted secret -- enter secrets in the Command Center")
                clean = ps.clean_data(res, row["data"])
                status = row.get("status") or res.initial_status
                if status not in res.statuses:
                    raise ps.SchemaError(f"unknown status {status}")
                entry.update(name=ps.record_name(res, clean), status=status)
                existing = repo.get(row["id"]) if row.get("id") else None
                if existing and existing["resource"] != name:
                    existing = None
                if existing is None:
                    entry["op"] = "create"
                elif existing["data"] == clean and existing["status"] == status and not existing["archived"]:
                    entry["op"] = "unchanged"
                else:
                    entry["op"] = "update"
                    entry["changed_fields"] = sorted(k for k in set(clean) | set(existing["data"])
                                                     if clean.get(k) != existing["data"].get(k))
                    if exported_at and str(existing["updated_at"]) > exported_at:
                        entry["conflict"] = True
                        result["conflicts"].append(f"{name}/{row['id']} changed here after the bundle was exported")
                result["summary"][entry["op"]] += 1
            except (ps.SchemaError, ValueError, TypeError) as error:
                entry.update(op="invalid", error=str(error))
                result["summary"]["invalid"] += 1
                result["errors"].append(f"{name}[{index}]: {error}")
                result["valid"] = False
            plan.append(entry)
        result["resources"][name] = plan
    known = set(known_flags)
    for key, value in (bundle.get("flags") or {}).items():
        if key not in known:
            result["errors"].append(f"flag {key}: unknown")
            result["valid"] = False
            continue
        if bool(value) != bool(current_flags.get(key)):
            result["flags"].append({"key": key, "from": bool(current_flags.get(key)), "to": bool(value)})
    return result


class SnapshotStore:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS config_snapshots (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, "
                         "actor TEXT NOT NULL, reason TEXT, kind TEXT NOT NULL, bundle_json TEXT NOT NULL, "
                         "applied_json TEXT, rolled_back_at TEXT)")

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def save(self, *, actor: str, reason: str, kind: str, bundle: Dict[str, Any], applied: Dict[str, Any]) -> str:
        sid = "cfs_" + uuid.uuid4().hex[:12]
        with self._connect() as conn:
            conn.execute("INSERT INTO config_snapshots VALUES (?,?,?,?,?,?,?,NULL)",
                         (sid, _now(), actor, reason[:300], kind, json.dumps(bundle, default=str),
                          json.dumps(applied, default=str)))
        return sid

    def get(self, sid: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM config_snapshots WHERE id=?", (sid,)).fetchone()
        if not row:
            return None
        item = dict(row)
        item["bundle"] = json.loads(item.pop("bundle_json"))
        item["applied"] = json.loads(item.pop("applied_json") or "{}")
        return item

    def list(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT id, created_at, actor, reason, kind, applied_json, rolled_back_at "
                                "FROM config_snapshots ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r, applied=json.loads(r["applied_json"] or "{}")) | {"applied_json": None} for r in rows]

    def mark_rolled_back(self, sid: str) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE config_snapshots SET rolled_back_at=? WHERE id=?", (_now(), sid))


def apply(resources, cc, store: SnapshotStore, bundle: Any, *, actor: str, reason: str = "",
          allow_conflicts: bool = False, role: str | None = None, kind: str = "import") -> Dict[str, Any]:
    """Apply a previewed bundle; returns the snapshot id that undoes it."""
    from app.repositories.command_center_repository import FEATURE_FLAGS

    repo = resources.repo
    bundle = _load(bundle)
    plan = preview(repo, cc.flags_map(), bundle, known_flags=FEATURE_FLAGS)
    if not plan["valid"]:
        raise BundleError("; ".join(plan["errors"][:5]))
    if plan["conflicts"] and not allow_conflicts:
        raise BundleError("conflicts: " + "; ".join(plan["conflicts"][:5]))
    # Snapshot exactly what will change (full current records + flag states).
    before: Dict[str, Any] = {"format": FORMAT, "version": VERSION, "exported_at": _now(), "exported_by": actor,
                              "resources": {}, "flags": {}}
    for name, rows in plan["resources"].items():
        before["resources"][name] = []
        for entry in rows:
            if entry["op"] == "update":
                current = repo.get(entry["id"])
                before["resources"][name].append({"id": current["id"], "status": current["status"],
                                                  "data": current["data"], "archived": current["archived"]})
    flags_now = cc.flags_map()
    before["flags"] = {f["key"]: flags_now.get(f["key"]) for f in plan["flags"]}
    created: List[Dict[str, str]] = []
    for name, rows in plan["resources"].items():
        source = bundle["resources"][name]
        for entry in rows:
            row = source[entry["index"]]
            if entry["op"] == "create":
                record = resources.create(name, row["data"], actor=actor, status=entry["status"])
                created.append({"resource": name, "id": record["id"]})
            elif entry["op"] == "update":
                clean = ps.clean_data(ps.resource(name), row["data"])
                repo.update(entry["id"], actor=actor, action=f"{kind}:update", name=entry["name"], data=clean,
                            status=entry["status"], archived=False)
    for change in plan["flags"]:
        cc.set_flag(change["key"], change["to"], actor)
        cc.audit(actor, f"config_{kind}", "feature_flag", change["key"], {"enabled": change["from"]},
                 {"enabled": change["to"]}, reason, role=role)
    applied = {"created": created, "summary": plan["summary"], "flags": plan["flags"]}
    sid = store.save(actor=actor, reason=reason, kind=kind, bundle=before, applied=applied)
    cc.audit(actor, f"config_{kind}", "config_bundle", sid, None, {"summary": plan["summary"],
                                                                     "flags": len(plan["flags"])}, reason, role=role)
    return {"snapshot_id": sid, **applied}


def rollback(resources, cc, store: SnapshotStore, sid: str, *, actor: str, role: str | None = None
             ) -> Dict[str, Any]:
    snap = store.get(sid)
    if snap is None:
        raise KeyError(sid)
    if snap.get("rolled_back_at"):
        raise BundleError("this change was already rolled back")
    repo = resources.repo
    restored = 0
    for name, rows in (snap["bundle"].get("resources") or {}).items():
        for row in rows:
            if repo.get(row["id"]) is None:
                continue
            repo.update(row["id"], actor=actor, action="rollback", data=row["data"], status=row["status"],
                        archived=bool(row.get("archived")))
            restored += 1
    archived = 0
    for item in snap["applied"].get("created") or []:
        if repo.get(item["id"]) is not None:
            repo.update(item["id"], actor=actor, action="rollback:archive", archived=True)
            archived += 1
    flags = 0
    for key, value in (snap["bundle"].get("flags") or {}).items():
        if value is None:
            continue
        cc.set_flag(key, bool(value), actor)
        flags += 1
    store.mark_rolled_back(sid)
    cc.audit(actor, "config_rollback", "config_bundle", sid, None,
             {"restored": restored, "archived": archived, "flags": flags}, "", role=role)
    return {"snapshot_id": sid, "restored": restored, "archived": archived, "flags": flags}
