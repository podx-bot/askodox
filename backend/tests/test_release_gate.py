"""The strict release gate: code conditions PASS in CI; READY is impossible
without PHONE VERIFIED device checks; a red incident means NOT_READY."""
import dataclasses
import uuid

from fastapi.testclient import TestClient

from app.services import release_gate as gate


def test_static_conditions_pass_on_this_code():
    from server import app

    results = {c["id"]: c for c in gate.static_conditions(app)}
    for cid in ("approved_features_intact", "home_screen_unchanged_no_business_tile", "no_auto_recharge",
                "no_unbacked_generation_claims"):
        assert results[cid]["status"] == "PASS", results[cid]


def test_never_ready_without_phone_verification_and_red_blocks():
    from server import app

    ok_incidents = {"release_readiness": {"state": "NEEDS_DEVICE_VERIFICATION", "blocking": []}}
    pending = gate.evaluate(app, incidents=ok_incidents, qa_checks=[{"status": "CODE READY"}])
    assert pending["overall"] == "BLOCKED_ON_DEVICE_VERIFICATION"
    none = gate.evaluate(app, incidents=ok_incidents, qa_checks=[])
    assert none["overall"] == "BLOCKED_ON_DEVICE_VERIFICATION", "no checks recorded is not a pass"
    red = gate.evaluate(app, incidents={"release_readiness": {"state": "NOT_READY", "blocking": ["provider:x"]}},
                        qa_checks=[{"status": "PHONE VERIFIED"}])
    assert red["overall"] == "NOT_READY"
    ready = gate.evaluate(app, incidents=ok_incidents, qa_checks=[{"status": "PHONE VERIFIED"}])
    assert ready["overall"] == "READY"


def test_new_flows_are_in_the_phone_checklist_as_code_ready():
    from app.services.owner_os import ACCEPTANCE_CHECKS

    titles = " | ".join(t for t, _, _ in ACCEPTANCE_CHECKS)
    for flow in ("Result Board", "pause / resume", "copy / select / share", "meaning colours", "Profile memory",
                 "My Roles", "Conversations & automation", "My Creations"):
        assert flow in titles, flow


def test_admin_release_gate_route(monkeypatch):
    from server import app, container

    key = "owner-gate-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    client = TestClient(app)
    assert client.get("/admin/cc/release-gate").status_code == 401
    body = client.get("/admin/cc/release-gate", headers={"X-ASKODOX-Admin-Key": key}).json()
    assert body["overall"] in ("NOT_READY", "BLOCKED_ON_DEVICE_VERIFICATION"), "never READY in tests"
    assert any(c["id"] == "real_phone_acceptance" for c in body["conditions"])
