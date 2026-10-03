"""Seller Opportunities lifecycle (accept / decline + reason / expiry /
fulfil, privacy-safe) and the unified inbox for users and staff."""
import dataclasses
import sqlite3
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import demand_insights as di
from app.services.session_tokens import issue_token


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-in-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    log = di.DemandAlertLog(container.settings.database_path)  # the log the routes use
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}, log


def _user(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def _alert(log, recipient, subject="running shoes", hours=72, key=None):
    opp = {"key": key or uuid.uuid4().hex, "subject": subject, "area": "vijayawada", "searches": 9,
           "budget_band": "₹1,000-2,000", "category": "footwear"}
    return log.record(opportunity=opp, recipient=recipient, rule_id="dar_x", actor="test", reasons=["area"],
                      score=1.0, channel="in_app", status="sent", expiry_hours=hours)


def test_accept_decline_expire_fulfil(api):
    client, container, owner, log = api
    seller = "app-seller-" + uuid.uuid4().hex[:6]
    h = _user(container, seller)
    a, b, c = _alert(log, seller), _alert(log, seller, "tv"), _alert(log, seller, "sofa")
    with sqlite3.connect(log.db_path) as conn:  # c expired yesterday
        conn.execute("UPDATE demand_alerts SET expires_at='2000-01-01T00:00:00+00:00' WHERE id=?", (c,))
    data = client.get("/api/opportunities", headers=h).json()
    by_id = {i["id"]: i for i in data["items"]}
    assert by_id[a]["status"] == "new" and by_id[a]["can_respond"] and by_id[a]["expires_at"]
    assert by_id[a]["category"] == "footwear" and by_id[a]["area"] == "vijayawada"
    assert by_id[c]["status"] == "expired" and not by_id[c]["can_respond"]
    assert "never shared" in data["privacy"]
    assert "app-" not in str([{k: v for k, v in i.items() if k != "id"} for i in data["items"]])
    # Accept / decline (with reason) / expired cannot be answered.
    r = client.post(f"/api/opportunities/{a}/accept", headers=h)
    assert r.status_code == 200 and r.json()["item"]["status"] == "accepted" and r.json()["item"]["can_fulfil"]
    r = client.post(f"/api/opportunities/{b}/decline", headers=h, json={"response": "declined", "reason": "out of stock"})
    assert r.json()["item"]["status"] == "declined"
    assert client.post(f"/api/opportunities/{c}/accept", headers=h).status_code == 409
    # Only accepted demand can be fulfilled.
    assert client.post(f"/api/opportunities/{b}/fulfil", headers=h).status_code == 409
    assert client.post(f"/api/opportunities/{a}/fulfil", headers=h).json()["item"]["status"] == "fulfilled"
    # Another seller can't touch it.
    assert client.post(f"/api/opportunities/{a}/accept", headers=_user(container, "someone-else")).status_code == 404
    # Admin visibility: outcome counts + decline reasons.
    summary = client.get("/admin/cc/demand/alerts", headers=owner).json()["summary"]
    assert summary["by_status"]["fulfilled"] >= 1 and summary["by_status"]["declined"] >= 1
    assert summary["by_status"]["expired"] >= 1
    assert any(r["reason"] == "out of stock" for r in summary["decline_reasons"])


def test_user_inbox_merges_sources_and_marks_push_external(api):
    client, container, owner, log = api
    seller = "app-seller-" + uuid.uuid4().hex[:6]
    _alert(log, seller)
    data = client.get("/api/me/inbox", headers=_user(container, seller)).json()
    assert data["counts"].get("opportunity") == 1 and data["needs_action"] >= 1
    assert data["items"][0]["route"] == "/opportunities"
    assert data["sources"]["opportunities"] == "ok" and data["sources"]["orders"] == "ok"
    assert data["push"]["status"] in ("EXTERNAL_SETUP_REQUIRED", "CONFIGURED")
    assert client.get("/api/me/inbox").status_code == 401


def test_staff_inbox_respects_permissions(api):
    client, container, owner, log = api
    data = client.get("/admin/cc/inbox", headers=owner).json()
    assert {"notifications", "work", "approvals", "total", "push"} <= set(data)
    staff = client.post("/admin/cc/staff", headers=owner, json={"name": "s", "role": "support_agent"}).json()
    if "token" in staff:
        mine = client.get("/admin/cc/inbox", headers={"X-ASKODOX-Staff-Token": staff["token"]})
        assert mine.status_code == 200
    assert client.get("/admin/cc/inbox").status_code in (401, 403)
