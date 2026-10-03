"""Feature-flag targeting (category / role / platform / location / %) and
configuration import / export with preview, validation, conflicts, audit
and rollback -- never secrets."""
import dataclasses
import json
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import flag_targeting as ft


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from app.api.routes.platform import platform
    from server import app, container

    key = "owner-cfg-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    pf = platform(container)
    created = []
    yield TestClient(app), container, {"X-ASKODOX-Admin-Key": key}, pf, created
    for rid in created:  # the platform DB is shared by the run
        if pf.repo.get(rid):
            pf.repo.delete(rid, actor="test")


def _rule(**data):
    return {"name": "r", "flag": "advisor.enabled", "effect": "only_for", **data}


def test_decide_targets_category_role_platform_location_and_percent():
    ctx = ft.make_context(category="footwear", role="buyer", platform="android", location="Vijayawada",
                         subject="user-1")
    assert ft.decide("advisor.enabled", False, [], ctx)[0] is False  # global OFF is a kill switch
    assert ft.decide("advisor.enabled", True, [], ctx)[0] is True
    assert ft.decide("advisor.enabled", True, [_rule(categories=["footwear"])], ctx)[0] is True
    assert ft.decide("advisor.enabled", True, [_rule(categories=["hotel"])], ctx)[0] is False
    assert ft.decide("advisor.enabled", True, [_rule(platforms=["web"])], ctx)[0] is False
    assert ft.decide("advisor.enabled", True, [_rule(roles=["buyer"], locations=["vijayawada"])], ctx)[0] is True
    never = dict(_rule(platforms=["android"]), effect="never_for", name="no android")
    on, why = ft.decide("advisor.enabled", True, [never], ctx)
    assert on is False and "no android" in why
    # Percentage: stable per person, roughly the share asked for.
    rule = _rule(percentage=30)
    hits = sum(ft.decide("advisor.enabled", True, [rule], ft.make_context(subject=f"u{i}"))[0] for i in range(1000))
    assert 230 < hits < 370
    assert ft.decide("advisor.enabled", True, [rule], ctx) == ft.decide("advisor.enabled", True, [rule], ctx)
    assert ft.decide("advisor.enabled", True, [rule], ft.make_context())[0] is False  # no id -> not in a partial rollout


def test_targeting_reaches_advisor_and_public_flags(api):
    client, container, owner, pf, created = api
    r = client.post("/admin/cc/platform/r/flag_rollouts", headers=owner, json={"data": {
        "name": "advisor only for footwear", "flag": "advisor.enabled", "effect": "only_for",
        "categories": ["footwear"]}})
    assert r.status_code == 200, r.text
    rid = r.json()["id"] if "id" in r.json() else r.json()["item"]["id"]
    created.append(rid)
    assert client.post(f"/admin/cc/platform/r/flag_rollouts/{rid}/actions/enable", headers=owner,
                       json={"params": {}, "confirm": True}).status_code == 200
    shoes = client.post("/api/advisor/next", json={"raw_text": "shoes", "category": "footwear"}).json()
    assert shoes["questions"] and not shoes.get("switched_off")
    tv = client.post("/api/advisor/next", json={"raw_text": "tv", "category": "electronics"}).json()
    assert tv.get("switched_off") is True
    assert client.get("/api/flags", params={"category": "footwear"}).json()["flags"]["advisor.enabled"] is True
    assert client.get("/api/flags", params={"category": "hotel"}).json()["flags"]["advisor.enabled"] is False
    ev = client.post("/admin/cc/flags/evaluate", headers=owner, json={"category": "hotel"}).json()
    assert ev["flags"]["advisor.enabled"]["enabled"] is False and "not targeted" in ev["flags"]["advisor.enabled"]["reason"]


def test_export_preview_apply_rollback(api):
    client, container, owner, pf, created = api
    made = client.post("/admin/cc/platform/r/platform_settings", headers=owner, json={"data": {
        "key": "advisor.max_questions_per_turn", "value": "1", "reason": "test"}})
    assert made.status_code == 200, made.text
    rid = made.json().get("id") or made.json()["item"]["id"]
    created.append(rid)
    bundle = client.post("/admin/cc/config-bundle/export", headers=owner,
                         json={"resources": ["platform_settings", "advisor_categories"]}).json()
    assert bundle["format"] == "askodox-config" and bundle["resources"]["advisor_categories"]
    text = json.dumps(bundle)
    assert "ASKODOX_SECRETS_KEY" not in text and "AIza" not in text
    assert "affiliate_programs" not in bundle["resources"]
    # Edit the bundle: change the setting, add a new category, flip a GREEN flag.
    row = next(r for r in bundle["resources"]["platform_settings"] if r["id"] == rid)
    row["data"]["value"] = 2
    bundle["resources"]["advisor_categories"].append({"data": {
        "key": "drones", "label": "Drones", "aliases": ["drone", "drones"], "required_fields": ["budget"]},
        "status": "ACTIVE"})
    bundle["flags"] = {"results.videos": not bundle["flags"]["results.videos"]}
    preview = client.post("/admin/cc/config-bundle/preview", headers=owner, json={"bundle": bundle}).json()
    assert preview["valid"] is True
    assert preview["summary"]["create"] == 1 and preview["summary"]["update"] == 1
    assert preview["flags"][0]["key"] == "results.videos"
    # Nothing changed by preview.
    assert pf.repo.get(rid)["data"]["value"] == 1
    assert client.post("/admin/cc/config-bundle/apply", headers=owner, json={"bundle": bundle}).status_code == 409
    applied = client.post("/admin/cc/config-bundle/apply", headers=owner,
                          json={"bundle": bundle, "confirm": True, "reason": "test import"})
    assert applied.status_code == 200, applied.text
    result = applied.json()
    created += [c["id"] for c in result["created"]]
    assert pf.repo.get(rid)["data"]["value"] == 2
    assert any(c["data"]["key"] == "drones" for c in pf.repo.list("advisor_categories"))
    nxt = client.post("/api/advisor/next", json={"raw_text": "a drone"}).json()
    assert nxt["category"]["key"] == "drones"
    # Audit + snapshots.
    snaps = client.get("/admin/cc/config-bundle/snapshots", headers=owner).json()["items"]
    assert snaps[0]["id"] == result["snapshot_id"]
    # Rollback restores the setting, archives the created category and the flag.
    before_flag = not bundle["flags"]["results.videos"]
    rb = client.post(f"/admin/cc/config-bundle/rollback/{result['snapshot_id']}", headers=owner,
                     json={"confirm": True})
    assert rb.status_code == 200, rb.text
    assert pf.repo.get(rid)["data"]["value"] == 1
    assert not any(c["data"]["key"] == "drones" for c in pf.repo.list("advisor_categories"))
    assert command_center_flag(container, "results.videos") is before_flag
    again = client.post(f"/admin/cc/config-bundle/rollback/{result['snapshot_id']}", headers=owner,
                        json={"confirm": True})
    assert again.status_code == 409


def command_center_flag(container, key):
    from app.api.routes.command_center import command_center

    return command_center(container).flags_map()[key]


def test_validation_conflicts_and_secrets_are_rejected(api):
    client, container, owner, pf, created = api
    bad = {"format": "askodox-config", "version": 1, "exported_at": "2000-01-01T00:00:00+00:00",
           "resources": {"advisor_categories": [{"data": {"label": "No key"}}],
                         "affiliate_programs": [{"data": {"name": "x"}}]},
           "flags": {"nope.flag": True}}
    p = client.post("/admin/cc/config-bundle/preview", headers=owner, json={"bundle": bad})
    assert p.status_code == 400  # affiliate programs are never importable
    bad["resources"].pop("affiliate_programs")
    plan = client.post("/admin/cc/config-bundle/preview", headers=owner, json={"bundle": bad}).json()
    assert plan["valid"] is False and any("nope.flag" in e for e in plan["errors"])
    assert plan["summary"]["invalid"] == 1
    # A record changed here after export -> conflict, refused unless allowed.
    cat = pf.repo.list("advisor_categories")[0]
    old = {"format": "askodox-config", "version": 1, "exported_at": "2000-01-01T00:00:00+00:00",
           "resources": {"advisor_categories": [{"id": cat["id"], "status": cat["status"],
                                                 "data": dict(cat["data"], label="Renamed")}]}, "flags": {}}
    plan = client.post("/admin/cc/config-bundle/preview", headers=owner, json={"bundle": old}).json()
    assert plan["conflicts"]
    r = client.post("/admin/cc/config-bundle/apply", headers=owner, json={"bundle": old, "confirm": True})
    assert r.status_code == 409 and "conflict" in r.json()["detail"]
    # A redacted secret can never be imported back.
    redacted = {"format": "askodox-config", "version": 1, "exported_at": "", "flags": {},
                "resources": {"notification_templates": [{"data": {
                    "key": "x", "channel": "email", "type": "transactional", "language": "en", "title": "t",
                    "body": "token [redacted]"}}]}}
    plan = client.post("/admin/cc/config-bundle/preview", headers=owner, json={"bundle": redacted}).json()
    assert plan["valid"] is False and "redacted" in plan["errors"][0]
    # Analysts can look but not import.
    staff = client.post("/admin/cc/staff", headers=owner, json={"name": "a", "role": "analyst"}).json()
    analyst = {"X-ASKODOX-Staff-Token": staff["token"]}
    assert client.post("/admin/cc/config-bundle/apply", headers=analyst,
                       json={"bundle": old, "confirm": True}).status_code == 403
