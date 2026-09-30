"""Self-Healing stays inside its risk bounds (GREEN auto only when enabled and
reversible, ORANGE via approval, RED alert-only) + Command Center security:
sign-in lockout, security headers, no arbitrary execution endpoints."""
import dataclasses
import sqlite3
import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository

OWNER_KEY = "owner-heal-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    db = str(tmp_path / "heal.db")
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY, database_path=db)
    monkeypatch.setattr(container, "settings", settings)
    repo = CommandCenterRepository(db)
    monkeypatch.setattr(container, "command_center_repository", repo, raising=False)
    monkeypatch.setattr(container, "self_healing_engine", None, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    yield TestClient(app), container, repo, db
    for key in FEATURE_FLAGS:
        repo.set_flag(key, key not in ("companion.screen_guide", "selfheal.green_auto"), "test")


def _errors(db, source, n, ok=0):
    now = datetime.now(timezone.utc).isoformat()
    with sqlite3.connect(db) as conn:
        base = int(uuid.uuid4().int % 10_000_000)
        for i in range(n):
            conn.execute("INSERT INTO discovery_events(demand_id,source,status,created_at) VALUES(?,?,?,?)",
                         (base + i, source, "error", now))
        for i in range(ok):
            conn.execute("INSERT INTO discovery_events(demand_id,source,status,created_at) VALUES(?,?,?,?)",
                         (base + n + i, source, "ok", now))


def test_green_bypass_is_proposed_until_auto_is_on_and_is_reversible(env):
    client, container, repo, db = env
    _errors(db, "nearby", 6, ok=1)
    first = client.post("/admin/cc/selfheal/scan", headers=OWNER).json()
    item = first["issues"][0]
    assert item["risk"] == "GREEN" and item["status"] == "PROPOSED"  # auto is OFF by default
    assert client.get("/admin/cc/selfheal", headers=OWNER).json()["bypassed_sources"] == []
    applied = client.post(f"/admin/cc/selfheal/{item['id']}/apply", headers=OWNER).json()
    assert applied["status"] == "APPLIED" and applied["expires_at"] and applied["rollback"]
    from app.api.routes.universal_deals import _multi_source_service

    assert "nearby" in _multi_source_service(container).bypassed
    rolled = client.post(f"/admin/cc/selfheal/{item['id']}/rollback", headers=OWNER).json()
    assert rolled["status"] == "ROLLED_BACK"
    assert client.get("/admin/cc/selfheal", headers=OWNER).json()["bypassed_sources"] == []
    # With GREEN auto ON, the same kind of issue is applied immediately.
    repo.set_flag("selfheal.green_auto", True, "test")
    _errors(db, "used_deals", 5)
    auto = client.post("/admin/cc/selfheal/scan", headers=OWNER).json()["issues"]
    assert [i["status"] for i in auto if i["target"] == "used_deals"] == ["APPLIED"]


def test_orange_needs_approval_and_red_is_alert_only(env):
    client, container, repo, db = env
    from app.api.routes.platform import platform

    pf = platform(container)
    campaign = pf.resources.create("promotion_campaigns", {
        "title": "t", "body": "b", "size": "compact", "channels": ["in_app"], "pricing": "free",
        "audience": "all", "schedule": "immediate"}, actor="owner", status="ACTIVE")
    for _ in range(5):
        pf.repo.record_event("notification_delivery", campaign_id=campaign["id"])
    for _ in range(9):
        pf.repo.record_event("campaign_click", campaign_id=campaign["id"])
    for i in range(6):
        p = pf.repo.create_payment(idempotency_key=f"p{i}-{uuid.uuid4().hex}", provider="sandbox_gateway",
                                   method="upi", amount=100)
        p = p[0] if isinstance(p, tuple) else p
        pf.repo.transition_payment(p["id"], "FAILED", actor="test")
    issues = client.post("/admin/cc/selfheal/scan", headers=OWNER).json()["issues"]
    orange = next(i for i in issues if i["risk"] == "ORANGE")
    red = next(i for i in issues if i["risk"] == "RED")
    assert orange["status"] == "PENDING_APPROVAL" and pf.repo.get(campaign["id"])["status"] == "ACTIVE"
    assert red["status"] == "ALERTED" and red["action"] == "alert_owner"
    assert client.post(f"/admin/cc/selfheal/{orange['id']}/apply", headers=OWNER).status_code == 403
    assert client.post(f"/admin/cc/selfheal/{red['id']}/apply", headers=OWNER).status_code == 403
    done = client.post(f"/admin/cc/approvals/{orange['approval_id']}/approve", headers=OWNER, json={}).json()
    assert done["status"] == "EXECUTED" and pf.repo.get(campaign["id"])["status"] == "PAUSED"
    assert any(n["kind"] == "selfheal_critical" for n in client.get("/admin/cc/notifications",
                                                                    headers=OWNER).json()["items"])


def test_self_healing_off_does_nothing(env):
    client, _, repo, db = env
    repo.set_flag("selfheal.enabled", False, "test")
    _errors(db, "nearby", 8)
    assert client.post("/admin/cc/selfheal/scan", headers=OWNER).json()["ran"] is False


def test_sign_in_lockout_blocks_even_the_right_key_after_repeated_failures(env):
    client, *_ = env
    for _ in range(10):
        assert client.get("/admin/cc/me", headers={"X-ASKODOX-Admin-Key": "guess"}).status_code == 401
    assert client.get("/admin/cc/me", headers={"X-ASKODOX-Admin-Key": "guess"}).status_code == 429
    assert client.get("/admin/cc/me", headers=OWNER).status_code == 429  # guessing cannot continue
    assert any(n["kind"] == "security_critical" for n in
               CommandCenterRepository(env[3]).notifications(limit=50))


def test_console_security_headers_and_no_execution_endpoints(env):
    client, *_ = env
    page = client.get("/admin/console")
    csp = page.headers.get("content-security-policy", "")
    assert "frame-ancestors 'none'" in csp and page.headers["x-frame-options"] == "DENY"
    assert page.headers["x-content-type-options"] == "nosniff"
    from server import app

    import re

    for route in app.routes:
        path = getattr(route, "path", "").lower()
        assert not re.search(r"/(sql|shell|exec|eval|query-db|run-code|command)(/|$)", path), path
