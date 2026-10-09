"""Admin AI incidents (grounded, one format, en/te, honest reasons) and the
action framework (propose -> approve -> execute -> verify -> report)."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services import admin_action_framework as fw
from app.services import admin_incidents as inc

FIELDS = ("problem", "impact", "reason", "evidence", "solution", "action_status", "retest", "ai_explanation")


def _billing(state="QUOTA_EXHAUSTED", failure="billing_quota", code=402):
    return [{"provider": "sarvam", "label": "Sarvam (voice STT / TTS)", "state": state, "failure_type": failure,
             "http_status": code, "fallback": "device voice", "timestamps": {"last_success_at": None}}]


def test_incident_format_confirmed_reason_and_correlation():
    out = inc.build(components=[{"name": "conversation_intelligence", "status": "degraded", "detail": "3 fallbacks"}],
                    billing_rows=_billing(), selfheal=[], registry=[], lang="en")
    quota = next(i for i in out if i["key"].startswith("provider:sarvam"))
    for field in FIELDS:
        assert quota[field], field
    assert quota["reason_confirmed"] and "credit / quota" in quota["reason"]
    assert "never pays" in quota["solution"]
    comp = next(i for i in out if i["key"].startswith("component:"))
    assert comp["reason"] == "Root cause not confirmed" and not comp["reason_confirmed"]
    assert comp["correlation"]["label"] == "POSSIBLE_CORRELATION"
    assert out[0]["severity"] == "red", "red first"
    assert inc.release_readiness(out)["state"] == "NOT_READY"


def test_telugu_and_never_ready_without_device_proof():
    out = inc.build(components=[], billing_rows=_billing(), selfheal=[], registry=[], lang="te")
    assert out[0]["labels"]["problem"] == "సమస్య"
    assert "ఎప్పుడూ చెల్లించదు" in out[0]["solution"]
    clean = inc.build(components=[{"name": "database", "status": "ok"}], billing_rows=[], selfheal=[], registry=[])
    assert clean == []
    assert inc.release_readiness(clean)["state"] == "NEEDS_DEVICE_VERIFICATION"


def test_unconfirmed_downtime_says_so():
    out = inc.build(components=[], billing_rows=_billing("DOWN", "downtime", None), selfheal=[], registry=[])
    assert out[0]["reason"] == "Root cause not confirmed"


def test_framework_read_only_runs_and_is_rate_limited(tmp_path):
    db = str(tmp_path / "a.db")
    runners = {"recheck": lambda t: {"result": "LIVE", "verified": True}}
    for _ in range(2):
        run = fw.propose(db, "recheck", "brave", actor="owner")
        done = fw.execute(db, run["id"], actor="owner", can=lambda p: True, runners=runners)
        assert done["status"] == "REPORTED" and done["verification"] == "VERIFIED"
        assert [s["step"] for s in done["timeline"]][0].startswith("detected")
    third = fw.propose(db, "recheck", "brave", actor="owner")
    with pytest.raises(PermissionError):
        fw.execute(db, third["id"], actor="owner", can=lambda p: True, runners=runners)


def test_framework_change_needs_approval_and_blocks_after_two_failures(tmp_path):
    db = str(tmp_path / "a.db")
    failing = {"selfheal_apply": lambda t: {"result": "applied", "verified": False, "rollback": "rollback #1"}}
    run = fw.propose(db, "selfheal_apply", "1", actor="ops")
    with pytest.raises(PermissionError):
        fw.execute(db, run["id"], actor="ops", can=lambda p: True, runners=failing)
    with pytest.raises(PermissionError):
        fw.approve(db, run["id"], actor="viewer", can=lambda p: p == "health:view")
    fw.approve(db, run["id"], actor="owner", can=lambda p: True)
    done = fw.execute(db, run["id"], actor="owner", can=lambda p: True, runners=failing)
    assert done["verification"] == "NOT_RECOVERED" and done["rollback"] == "rollback #1"
    second = fw.propose(db, "selfheal_apply", "1", actor="ops")
    fw.approve(db, second["id"], actor="owner", can=lambda p: True)
    fw.execute(db, second["id"], actor="owner", can=lambda p: True, runners=failing)
    with pytest.raises(PermissionError, match="blocked"):
        fw.propose(db, "selfheal_apply", "1", actor="ops")
    with pytest.raises(ValueError):
        fw.propose(db, "drop_database", "", actor="ops")


def test_admin_routes_and_assistant_incident_mode(monkeypatch):
    from server import app, container

    key = "owner-inc-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    client = TestClient(app)
    h = {"X-ASKODOX-Admin-Key": key}
    assert client.get("/admin/cc/incidents").status_code == 401
    body = client.get("/admin/cc/incidents?language=te", headers=h).json()
    assert body["language"] == "te" and body["release_readiness"]["state"] in ("NOT_READY",
                                                                               "NEEDS_DEVICE_VERIFICATION")
    assert "POSSIBLE" in body["basis"]
    ask = client.post("/admin/cc/assistant/ask", headers=h, json={"question": "ASKODOX lo em samasya undi?",
                                                                    "mode": "incidents"}).json()
    assert ask["mode"] == "incidents" and "incidents" in ask
    run = client.post("/admin/cc/actions", headers=h, json={"action": "rescan_billing"}).json()
    done = client.post(f"/admin/cc/actions/{run['id']}/execute", headers=h).json()
    assert done["status"] == "REPORTED" and done["result"].startswith("new alerts")
    assert client.post("/admin/cc/actions", headers=h, json={"action": "pay_invoice"}).status_code == 422
    assert client.post(f"/admin/cc/actions/{run['id']}/explode", headers=h).status_code == 422
