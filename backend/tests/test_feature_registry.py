"""Feature Registry gate: every approved feature still exists in the code
(routes, response keys, widget keys, symbols, flag defaults, acceptance
tests) and no approved feature is deleted without an approved deprecation."""
import copy
import dataclasses
import json
import os
import uuid

from fastapi.testclient import TestClient

from app.services import feature_registry as fr


def test_every_approved_feature_is_still_present():
    problems = fr.validate()
    assert problems == [], "\n".join(problems)


def test_no_approved_feature_was_deleted_against_the_base_branch():
    base_path = os.environ.get("FEATURE_REGISTRY_BASE")
    if not base_path or not os.path.exists(base_path):
        return  # CI sets it to the base branch copy; locally there is nothing to compare
    base = json.loads(open(base_path, encoding="utf-8").read())
    problems = [p for p in fr.validate(base=base) if "deleted from the registry" in p]
    assert problems == [], "\n".join(problems)


def test_the_gate_catches_each_kind_of_regression():
    registry = fr.load()
    broken = copy.deepcopy(registry)
    board = next(f for f in broken["features"] if f["id"] == "result_board")
    board["ui"]["keys"].append("askodoxGoneWidget")
    brain = next(f for f in broken["features"] if f["id"] == "decision_brain")
    brain["api"][0]["response_keys"].append("vanished_key")
    brain["flags"]["ai.assistant"] = False  # approved default changed
    voice = next(f for f in broken["features"] if f["id"] == "voice")
    voice["tests"]["flutter"].append("test/does_not_exist_test.dart")
    voice["api"].append({"method": "POST", "path": "/api/gone"})
    problems = "\n".join(fr.validate(broken))
    for expected in ("askodoxGoneWidget", "vanished_key", "ai.assistant default changed",
                     "does_not_exist_test.dart", "/api/gone"):
        assert expected in problems, expected
    trimmed = copy.deepcopy(registry)
    trimmed["features"] = [f for f in trimmed["features"] if f["id"] != "rich_replies"]
    assert any("rich_replies: approved feature deleted" in p for p in fr.validate(trimmed, base=registry))
    dep = copy.deepcopy(registry)
    next(f for f in dep["features"] if f["id"] == "rich_replies")["status"] = "deprecated"
    assert any("deprecated without owner approval" in p for p in fr.validate(dep))


def test_admin_registry_view_never_claims_working_without_a_signal(monkeypatch):
    from app.services import assistant_health
    from server import app, container

    assistant_health.reset()
    key = "owner-fr-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    body = TestClient(app).get("/admin/cc/feature-registry", headers={"X-ASKODOX-Admin-Key": key}).json()
    states = {row["id"]: row["state"] for row in body["items"]}
    assert set(states) == {f["id"] for f in fr.load()["features"]}
    assert states["rich_replies"] == "UNVERIFIED", "code + tests are not proof of a working phone flow"
    assert set(states.values()) <= {"WORKING", "DEGRADED", "DISABLED", "FAILED", "UNVERIFIED"}
