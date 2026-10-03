"""Command Center governance: granular RBAC, GREEN/ORANGE/RED risk, approvals
(no self-approval, RED = Owner/Super Admin only), Permission Safety Advisor,
custom roles, append-only redacted audit."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import governance as gov

OWNER_KEY = "owner-gov-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def cc(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "gov.db"))
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    repo = CommandCenterRepository(str(tmp_path / "gov.db"))
    monkeypatch.setattr(container, "command_center_repository", repo, raising=False)
    yield TestClient(app), container, repo
    for key in FEATURE_FLAGS:
        repo.set_flag(key, True, "test")


def _staff(client, role, **extra):
    r = client.post("/admin/cc/staff", headers=OWNER, json={"name": f"{role} {uuid.uuid4().hex[:4]}", "role": role,
                                                             **extra})
    assert r.status_code == 200, r.text
    return r.json(), {"X-ASKODOX-Staff-Token": r.json()["token"]}


def test_manage_implies_create_edit_approve_delete_but_not_export():
    held = {"content:manage", "content:view"}
    for verb in ("create", "edit", "approve", "delete"):
        assert gov.has_permission(held, f"content:{verb}")
    assert not gov.has_permission(held, "content:export")
    assert not gov.has_permission(held, "finance:view")


def test_forbidden_message_is_the_standard_one(cc):
    client, _, _ = cc
    _, analyst = _staff(client, "analyst")
    r = client.get("/admin/cc/staff", headers=analyst)
    assert r.status_code == 403
    assert r.json()["detail"].startswith("You do not have permission for this action. Owner/Admin approval is required.")


def test_orange_flag_by_staff_needs_a_second_person_and_no_self_approval(cc):
    client, _, repo = cc
    ops, ops_h = _staff(client, "integrations_manager", permissions=[
        "config:view", "config:manage", "approvals:approve", "approvals:view"])
    r = client.put("/admin/cc/config/rewards", headers=ops_h, json={"enabled": False, "confirm": True,
                                                                   "reason": "abuse spike"})
    assert r.status_code == 200 and r.json()["approval_required"] is True
    approval = r.json()["approval"]
    assert approval["risk"] == "ORANGE" and repo.is_enabled("rewards") is True  # not applied yet
    own = client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=ops_h, json={})
    assert own.status_code == 403 and "own request" in own.json()["detail"]
    # A different approver who also holds config:manage applies it.
    _, other_h = _staff(client, "integrations_manager", permissions=["config:view", "config:manage",
                                                                     "approvals:approve"])
    done = client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=other_h, json={"note": "ok"})
    assert done.status_code == 200 and done.json()["status"] == "EXECUTED"
    assert repo.is_enabled("rewards") is False
    again = client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=other_h, json={})
    assert again.status_code == 409  # never executed twice


def test_red_flag_needs_owner_approval(cc):
    client, _, repo = cc
    _, ops_h = _staff(client, "integrations_manager", permissions=["config:view", "config:manage",
                                                                   "approvals:approve"])
    assert client.put("/admin/cc/config/payments.online", headers=ops_h, json={"enabled": True}).status_code == 409
    r = client.put("/admin/cc/config/payments.online", headers=ops_h, json={"enabled": False, "confirm": True})
    approval = r.json()["approval"]
    assert approval["risk"] == "RED"
    _, other_h = _staff(client, "integrations_manager", permissions=["config:view", "config:manage",
                                                                     "approvals:approve"])
    denied = client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=other_h, json={"confirm": True})
    assert denied.status_code == 403 and "Owner" in denied.json()["detail"]
    assert client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=OWNER, json={}).status_code == 409
    ok = client.post(f"/admin/cc/approvals/{approval['id']}/approve", headers=OWNER, json={"confirm": True})
    assert ok.json()["status"] == "EXECUTED" and repo.is_enabled("payments.online") is False
    # The Owner applies RED directly (with confirmation), audited as RED.
    assert client.put("/admin/cc/config/payments.online", headers=OWNER,
                      json={"enabled": True, "confirm": True}).status_code == 200
    rows = client.get("/admin/cc/audit?risk=RED", headers=OWNER).json()["items"]
    assert any(r["entity_id"] == "payments.online" and r["actor_role"] == "super_admin" for r in rows)


def test_green_flag_by_staff_applies_directly(cc):
    client, _, repo = cc
    _, h = _staff(client, "integrations_manager")
    r = client.put("/admin/cc/config/results.videos", headers=h, json={"enabled": False, "confirm": True})
    assert r.status_code == 200 and r.json()["enabled"] is False


def test_red_grants_by_staff_manager_are_held_for_owner_approval(cc):
    client, _, repo = cc
    mgr, mgr_h = _staff(client, "operations_manager", permissions=[
        "staff:manage", "payments:view", "payments:manage", "support:view"])
    target, _ = _staff(client, "support_agent")
    r = client.patch(f"/admin/cc/staff/{target['id']}", headers=mgr_h, json={"grant": ["payments:manage"]})
    assert r.status_code == 200
    body = r.json()
    assert "payments:manage" not in body["permissions"] and body["approval"]["approval_required"]
    assert any(w["level"] == "RED" for w in body["advice"]["warnings"])
    # Self-escalation is refused outright.
    me = client.patch(f"/admin/cc/staff/{mgr['id']}", headers=mgr_h, json={"grant": ["support:manage"]})
    assert me.status_code == 403
    # A staff manager cannot create a Super Admin.
    assert client.post("/admin/cc/staff", headers=mgr_h, json={"name": "x", "role": "super_admin"}).status_code == 403
    approval_id = body["approval"]["approval"]["id"]
    done = client.post(f"/admin/cc/approvals/{approval_id}/approve", headers=OWNER, json={"confirm": True}).json()
    assert done["status"] == "EXECUTED"
    staff = {s["id"]: s for s in client.get("/admin/cc/staff", headers=OWNER).json()["items"]}
    assert "payments:manage" in staff[target["id"]]["permissions"]


def test_permission_safety_advisor_flags_toxic_combinations(cc):
    client, _, _ = cc
    advice = client.post("/admin/cc/staff/advise", headers=OWNER,
                         json={"role": "finance", "grant": ["payments:manage"]}).json()
    assert advice["risk"] == "RED"
    assert any("Separation of duties" in w["message"] for w in advice["warnings"])
    calm = client.post("/admin/cc/staff/advise", headers=OWNER, json={"permissions": ["overview:view"]}).json()
    assert calm["risk"] == "GREEN" and calm["warnings"] == []


def test_custom_roles_are_owner_only_and_audited(cc):
    client, _, _ = cc
    _, mgr_h = _staff(client, "operations_manager", permissions=["staff:manage"])
    body = {"label": "Night desk", "permissions": ["overview:view", "support:view", "support:edit"]}
    assert client.put("/admin/cc/roles/night_desk", headers=mgr_h, json=body).status_code == 403
    saved = client.put("/admin/cc/roles/night_desk", headers=OWNER, json=body).json()
    assert saved["permissions"] == sorted(body["permissions"])
    assert client.put("/admin/cc/roles/super_admin", headers=OWNER, json=body).status_code == 422
    created = client.post("/admin/cc/staff", headers=OWNER, json={"name": "n", "role": "night_desk"}).json()
    assert set(created["permissions"]) == set(body["permissions"])
    assert client.delete("/admin/cc/roles/night_desk", headers=OWNER).status_code == 409
    assert client.delete("/admin/cc/roles/night_desk?confirm=true", headers=OWNER).status_code == 200


def test_audit_is_append_only_and_redacts_secrets(cc):
    client, _, repo = cc
    repo.audit("owner", "integration_saved", "integration", "razorpay",
               {"key_secret": "should-not-appear"}, {"note": "token Bearer abcdefghijklmnopqrstu"})
    text = client.get("/admin/cc/audit", headers=OWNER).text
    assert "should-not-appear" not in text and "abcdefghijklmnopqrstu" not in text
    for method in ("put", "patch", "delete"):
        assert getattr(client, method)("/admin/cc/audit", headers=OWNER).status_code in (404, 405)
    _, analyst = _staff(client, "finance")  # has audit:view, not audit:export
    assert client.get("/admin/cc/audit", headers=analyst).status_code == 200
    assert client.get("/admin/cc/audit/export.csv", headers=analyst).status_code == 403
    csv_text = client.get("/admin/cc/audit/export.csv", headers=OWNER).text
    assert csv_text.startswith("id,created_at,actor,actor_role")


def test_redact_helper():
    out = gov.redact({"api_key": "x", "nested": [{"password": "p"}], "ok": "rzp_live_ABCDEFGH12",
                      "enabled": True, "pincode": "521165"})
    assert out["api_key"] == gov.REDACTED and out["nested"][0]["password"] == gov.REDACTED
    assert gov.REDACTED in out["ok"] and out["enabled"] is True and out["pincode"] == "521165"
