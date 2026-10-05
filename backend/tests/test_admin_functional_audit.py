"""Functional audit of every Command Center module (platform resources) with
dummy data: create -> save -> persist (read back) -> edit (versioned) ->
pause / disable -> archive -> restore -> history, and the permission wall
(a role without <module>:manage gets 403). Dummy values come from each
field's own schema, so a new module is audited automatically.

Run with ASKODOX_AUDIT_MATRIX=<path> to also write the PASS / FAIL matrix."""
import dataclasses
import json
import os
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import governance as gov
from app.services import platform_schema as ps

# Values a schema field alone cannot express (cross-field / range rules).
OVERRIDES = {
    "smart_links": {"slug": "audit-link", "web_url": "https://example.in/audit"},
    "platform_settings": {"key": "video_study.max_seconds", "value": 30},
}
RESULTS: dict = {}


def _sample(f):
    if f.kind in ("text", "longtext"):
        return f"Audit {f.name}"
    if f.kind == "url":
        return "https://example.in/audit"
    if f.kind == "deeplink":
        return "askodox://audit"
    if f.kind in ("number", "int"):
        v = f.min if f.min is not None else 1
        return int(v) if f.kind == "int" else v
    if f.kind == "bool":
        return True
    if f.kind == "date":
        return "2026-12-31"
    if f.kind == "enum":
        return f.options[0]
    if f.kind == "list":
        return [f.options[0]] if f.options else ["audit"]
    if f.kind == "json":
        return {}
    return None


@pytest.fixture(scope="module")
def api(tmp_path_factory):
    from server import app, container

    db = str(tmp_path_factory.mktemp("audit") / "audit.db")
    key = "owner-audit-" + uuid.uuid4().hex[:6]
    saved = (container.settings, getattr(container, "command_center_repository", None))
    container.settings = dataclasses.replace(container.settings, admin_seed_key=key, database_path=db)
    container.command_center_repository = CommandCenterRepository(db)
    client = TestClient(app)
    owner = {"X-ASKODOX-Admin-Key": key}
    staff = client.post("/admin/cc/staff", headers=owner, json={"name": "support", "role": "support_agent"})
    assert staff.status_code == 200, staff.text
    yield client, owner, {"X-ASKODOX-Staff-Token": staff.json()["token"]}, set(staff.json()["permissions"])
    container.settings, container.command_center_repository = saved
    path = os.environ.get("ASKODOX_AUDIT_MATRIX")
    if path:
        with open(path, "w", encoding="utf-8") as out:
            json.dump(RESULTS, out, indent=1)


def _create(client, owner, name, made):
    res = ps.resource(name)
    data = {}
    for f in res.fields:
        if not f.required:
            continue
        if f.kind == "ref":
            if f.ref in ps.RESOURCES:
                data[f.name] = made.get(f.ref) or _create(client, owner, f.ref, made)["id"]
            continue
        data[f.name] = _sample(f)
    if res.field(res.name_field) and res.name_field not in data:
        data[res.name_field] = _sample(res.field(res.name_field))
    data.update(OVERRIDES.get(name, {}))
    r = client.post(f"/admin/cc/platform/r/{name}", headers=owner, json={"data": data})
    assert r.status_code == 200, f"create {name}: {r.text}"
    made[name] = r.json()["id"]
    return r.json()


@pytest.mark.parametrize("name", sorted(ps.RESOURCES))
def test_module_lifecycle(api, name):
    client, owner, support, support_perms = api
    res = ps.resource(name)
    row = RESULTS.setdefault(name, {"label": res.label})
    base = f"/admin/cc/platform/r/{name}"

    created = _create(client, owner, name, {})
    rid = created["id"]
    row["create"] = row["save"] = "PASS"

    back = client.get(f"{base}/{rid}", headers=owner)
    assert back.status_code == 200 and back.json()["data"] == created["data"]
    assert any(i["id"] == rid for i in client.get(base, headers=owner).json()["items"])
    row["persist"] = "PASS"

    field = res.name_field if res.field(res.name_field) and res.field(res.name_field).kind in (
        "text", "longtext") else next((f.name for f in res.fields if f.kind in ("text", "longtext")), None)
    if field:
        edited = client.patch(f"{base}/{rid}", headers=owner,
                              json={"data": {field: "Audit edited"}, "version": back.json()["version"]})
        assert edited.status_code == 200, edited.text
        assert edited.json()["data"][field] == "Audit edited" and edited.json()["version"] > back.json()["version"]
        stale = client.patch(f"{base}/{rid}", headers=owner,
                             json={"data": {field: "lost update"}, "version": back.json()["version"]})
        assert stale.status_code in (409, 400), "a stale version must not overwrite a newer edit"
        row["edit"] = "PASS"
    else:
        row["edit"] = "N/A (no free-text field)"

    status = client.get(f"{base}/{rid}", headers=owner).json()["status"]
    names = {a.name: a for a in res.actions}
    stopped = None
    for step in ("approve", "enable", "pause", "disable"):
        spec = names.get(step)
        if not spec or (spec.from_status and status not in spec.from_status):
            continue
        r = client.post(f"{base}/{rid}/actions/{step}", headers=owner, json={"confirm": True})
        assert r.status_code == 200, f"{name} {step}: {r.text}"
        status = r.json()["status"]
        if step in ("pause", "disable"):
            stopped = step
            break
    row["pause_disable"] = f"PASS ({stopped} -> {status})" if stopped else "N/A (no pause / disable action)"

    archived = client.post(f"{base}/{rid}/actions/archive", headers=owner, json={"confirm": True})
    assert archived.status_code == 200 and archived.json()["archived"] is True
    assert all(i["id"] != rid for i in client.get(base, headers=owner).json()["items"]), "archived hidden"
    assert any(i["id"] == rid for i in client.get(f"{base}?archived=true", headers=owner).json()["items"])
    restored = client.post(f"{base}/{rid}/actions/restore", headers=owner, json={})
    assert restored.status_code == 200 and restored.json()["archived"] is False
    row["archive"] = "PASS"

    history = client.get(f"{base}/{rid}/history", headers=owner).json()["items"]
    assert len(history) >= 3, history
    row["history"] = f"PASS ({len(history)} entries)"

    can_manage = gov.has_permission(support_perms, f"{res.permission}:manage")
    denied = client.post(base, headers=support, json={"data": created["data"]})
    if can_manage:
        assert denied.status_code in (200, 400, 409)
        row["permissions"] = "PASS (support_agent may manage)"
    else:
        assert denied.status_code == 403, denied.text
        row["permissions"] = "PASS (support_agent denied 403)"
    assert client.post(base, json={"data": created["data"]}).status_code == 401
    row["result"] = "PASS"
