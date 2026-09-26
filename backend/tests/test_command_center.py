"""Admin Command Center (Phases 18-23): server-side permissions, staff,
feature flags wired into live behaviour, support/no-match queues, integration
status without secrets, honest health, analytics + CSV export, masking."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository, mask_user_id
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-test-key-" + uuid.uuid4().hex[:6]


@pytest.fixture()
def cc(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "cc.db"))
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    repo = CommandCenterRepository(container.settings.database_path)
    monkeypatch.setattr(container, "command_center_repository", repo, raising=False)
    yield TestClient(app), container, repo
    for key in FEATURE_FLAGS:  # never leak a switched-off flag into other tests
        repo.set_flag(key, True, "test")


OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


def _staff(client, role, **extra):
    body = client.post("/admin/cc/staff", headers=OWNER, json={"name": f"{role} user", "role": role, **extra})
    assert body.status_code == 200, body.text
    data = body.json()
    return data, {"X-ASKODOX-Staff-Token": data["token"]}


def _user_headers(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def test_every_endpoint_needs_sign_in_and_the_right_permission(cc):
    client, _, _ = cc
    assert client.get("/admin/cc/overview").status_code == 401
    assert client.get("/admin/cc/overview", headers={"X-ASKODOX-Admin-Key": "wrong"}).status_code == 401
    assert client.get("/admin/cc/overview", headers={"X-ASKODOX-Staff-Token": "stf_forged"}).status_code == 401

    me = client.get("/admin/cc/me", headers=OWNER).json()
    assert me["role"] == "super_admin" and "staff:manage" in me["permissions"]

    _, analyst = _staff(client, "analyst")
    assert client.get("/admin/cc/analytics", headers=analyst).status_code == 200
    for method, path in [("get", "/admin/cc/staff"), ("get", "/admin/cc/escalations"), ("get", "/admin/cc/listings"),
                         ("get", "/admin/cc/integrations"), ("get", "/admin/cc/users"), ("get", "/admin/cc/audit"),
                         ("get", "/admin/cc/payments")]:
        assert getattr(client, method)(path, headers=analyst).status_code == 403, path
    denied = client.put("/admin/cc/config/results.online", headers=analyst, json={"enabled": False, "confirm": True})
    assert denied.status_code == 403


def test_staff_token_shown_once_grant_revoke_and_deactivate(cc):
    client, _, _ = cc
    created, headers = _staff(client, "support_agent")
    assert created["token"].startswith("stf_")
    listing = client.get("/admin/cc/staff", headers=OWNER).text
    assert created["token"] not in listing and "token_hash" not in listing

    assert client.get("/admin/cc/no-match", headers=headers).status_code == 403
    granted = client.patch(f"/admin/cc/staff/{created['id']}", headers=OWNER, json={"grant": ["nomatch:view"]}).json()
    assert "nomatch:view" in granted["permissions"]
    assert client.get("/admin/cc/no-match", headers=headers).status_code == 200
    client.patch(f"/admin/cc/staff/{created['id']}", headers=OWNER, json={"revoke": ["nomatch:view", "support:manage"]})
    assert client.get("/admin/cc/no-match", headers=headers).status_code == 403

    assert client.patch(f"/admin/cc/staff/{created['id']}", headers=OWNER, json={"active": False}).status_code == 409
    assert client.patch(f"/admin/cc/staff/{created['id']}", headers=OWNER,
                        json={"active": False, "confirm": True}).status_code == 200
    assert client.get("/admin/cc/me", headers=headers).status_code == 401


def test_staff_manager_cannot_grant_permissions_they_do_not_hold(cc):
    client, _, _ = cc
    manager, manager_headers = _staff(client, "support_agent", permissions=["staff:manage", "support:view"])
    escalate = client.post("/admin/cc/staff", headers=manager_headers,
                           json={"name": "x", "role": "super_admin"})
    assert escalate.status_code == 403
    self_grant = client.patch(f"/admin/cc/staff/{manager['id']}", headers=manager_headers, json={"grant": ["config:manage"]})
    assert self_grant.status_code == 403


def test_support_escalation_workflow_with_single_notification(cc):
    client, container, repo = cc
    user = "app-phone-91" + str(uuid.uuid4().int)[:10]
    case = client.post("/api/in-app/support/escalate", headers=_user_headers(container, user), json={
        "issue": "Money deducted but order not confirmed", "category": "PAYMENT", "critical": True,
        "actions_tried": ["Checked UPI reference"], "deal_id": "77",
    }).json()
    case_id = case["case_id"]
    # A second notify for the same event is ignored.
    repo.notify_once(f"escalation:{case_id}", "escalation_critical", "dup", str(case_id))
    notes = [n for n in client.get("/admin/cc/notifications", headers=OWNER).json()["items"]
             if n["event_key"] == f"escalation:{case_id}"]
    assert len(notes) == 1 and notes[0]["kind"] == "escalation_critical"

    _, agent = _staff(client, "support_agent")
    queue = client.get("/admin/cc/escalations", headers=agent, params={"status": "open"}).json()["items"]
    item = next(e for e in queue if e["id"] == case_id)
    assert user not in str(item) and item["requester"].endswith(user[-4:])
    assert item["context"]["actions_tried"] == ["Checked UPI reference"]

    moved = client.patch(f"/admin/cc/escalations/{case_id}", headers=agent,
                         json={"status": "IN_PROGRESS", "assigned_to": "Ravi"}).json()
    assert moved["status"] == "IN_PROGRESS" and moved["assigned_to"] == "Ravi"
    assert client.patch(f"/admin/cc/escalations/{case_id}", headers=agent,
                        json={"status": "RESOLVED", "resolution_note": "Refunded"}).status_code == 409
    assert client.patch(f"/admin/cc/escalations/{case_id}", headers=agent,
                        json={"status": "RESOLVED", "confirm": True}).status_code == 422
    done = client.patch(f"/admin/cc/escalations/{case_id}", headers=agent,
                        json={"status": "RESOLVED", "confirm": True, "resolution_note": "Refunded via UPI"}).json()
    assert done["status"] == "RESOLVED" and done["resolution_note"] == "Refunded via UPI"
    audit = client.get("/admin/cc/audit", headers=OWNER).json()["items"]
    assert any(a["action"] == "escalation_update" and str(a["entity_id"]) == str(case_id) for a in audit)


def test_no_match_is_queued_once_and_notified_once(cc):
    client, container, repo = cc
    owner = "app-nomatch-" + uuid.uuid4().hex
    subject = "Nomatchium gadget " + uuid.uuid4().hex[:6]
    demand_id = container.universal_demand_repository.create(
        {"user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": subject, "source": "app"})
    for _ in range(3):  # the app re-opens results; the queue must not grow
        assert client.get(f"/deals/{demand_id}/matches", headers=_user_headers(container, owner)).status_code == 200

    queue = [e for e in client.get("/admin/cc/no-match", headers=OWNER).json()["items"] if e["demand_id"] == demand_id]
    assert len(queue) == 1 and queue[0]["subject"] == subject and queue[0]["status"] == "OPEN"
    notes = [n for n in repo.notifications(limit=500) if n["event_key"] == f"no_match:{demand_id}"]
    assert len(notes) == 1

    updated = client.patch(f"/admin/cc/no-match/{queue[0]['id']}", headers=OWNER,
                           json={"status": "SOURCE_ADDED", "note": "Added a gadget wholesaler"}).json()
    assert updated["status"] == "SOURCE_ADDED"
    assert client.patch(f"/admin/cc/no-match/{queue[0]['id']}", headers=OWNER, json={"status": "BOGUS"}).status_code == 422


def test_switching_off_registered_results_does_not_create_false_no_match(cc):
    client, container, repo = cc
    subject = "Offswitch kettle " + uuid.uuid4().hex[:6]
    container.product_catalog_repository.upsert_product("app-phone-919000000088", subject, price=900)
    owner = "app-offswitch-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create(
        {"user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": subject, "source": "app"})
    assert client.put("/admin/cc/config/results.registered", headers=OWNER,
                      json={"enabled": False, "confirm": True}).status_code == 200
    body = client.get(f"/deals/{demand_id}/matches", headers=_user_headers(container, owner)).json()
    assert body["local_match_count"] == 0 and body["source_status"]["askodox"] == "disabled"

    queued = [e for e in repo.no_match_queue(limit=500) if e["demand_id"] == demand_id]
    notified = [n for n in repo.notifications(limit=500) if n["event_key"] == f"no_match:{demand_id}"]
    assert queued == [] and notified == [], "a config switch is not a supply gap"


def test_flags_switch_live_behaviour_and_need_confirmation(cc):
    client, container, _ = cc
    assert client.put("/admin/cc/config/results.registered", headers=OWNER, json={"enabled": False}).status_code == 409
    assert client.put("/admin/cc/config/unknown.flag", headers=OWNER, json={"enabled": True}).status_code == 404

    subject = "Flag TV " + uuid.uuid4().hex[:6]
    container.product_catalog_repository.upsert_product("app-phone-919000000077", subject, price=25000)
    owner = "app-flag-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create(
        {"user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": subject, "price": 30000, "source": "app"})
    headers = _user_headers(container, owner)
    before = client.get(f"/deals/{demand_id}/matches", headers=headers).json()
    assert "registered" in [m["match_source"] for m in before["matches"]]

    for key in ("results.registered", "voice.sarvam_tts", "support.escalation", "ai.assistant"):
        assert client.put(f"/admin/cc/config/{key}", headers=OWNER, json={"enabled": False, "confirm": True}).status_code == 200
    after = client.get(f"/deals/{demand_id}/matches", headers=headers).json()
    assert "registered" not in [m["match_source"] for m in after["matches"]]
    assert after["source_status"]["askodox"] == "disabled"

    speak = client.post("/api/in-app/voice/speak", json={"text": "hello"})
    assert speak.status_code == 503 and speak.json()["detail"] == "TTS_DISABLED"
    assert client.post("/api/in-app/support/escalate", json={"issue": "help"}).status_code == 503
    assistant = client.post("/api/in-app/assistant", json={"message": "I want chicken"}).json()
    assert assistant["source"] == "fallback"

    assert client.put("/admin/cc/config/support.escalation", headers=OWNER, json={"enabled": True}).status_code == 200
    assert client.post("/api/in-app/support/escalate", json={"issue": "help"}).status_code == 200


def test_integrations_and_health_never_expose_secrets_or_fake_green(cc, monkeypatch):
    client, container, _ = cc
    secrets_ = {"google_maps_api_key": "gm-SECRET-123", "brave_search_api_key": "brave-SECRET-456",
                "sarvam_api_key": "sarvam-SECRET-789", "openai_api_key": "oa-SECRET-000"}
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, **secrets_))
    for path in ("/admin/cc/integrations", "/admin/cc/config", "/admin/cc/health", "/admin/cc/payments", "/admin/cc/me"):
        text = client.get(path, headers=OWNER).text
        for value in secrets_.values():
            assert value not in text, path
        assert OWNER_KEY not in text, path

    items = {i["name"]: i for i in client.get("/admin/cc/integrations", headers=OWNER).json()["items"]}
    assert items["openai"]["status"] == "configured"  # present, never verified -> not "connected"
    assert items["payments"]["status"] == "not_configured"
    health = {c["name"]: c["status"] for c in client.get("/admin/cc/health", headers=OWNER).json()["components"]}
    assert health["openai"] == "unknown"
    assert health["database"] == "ok"

    monkeypatch.setattr(container, "brave_web_search_provider", lambda query, limit: [], raising=False)
    checked = client.post("/admin/cc/integrations/brave_search/check", headers=OWNER).json()
    assert checked["checked"] is True and checked["item"]["status"] == "error"
    health = {c["name"]: c["status"] for c in client.get("/admin/cc/health", headers=OWNER).json()["components"]}
    assert health["brave_search"] == "error"

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, openai_api_key=""))
    items = {i["name"]: i for i in client.get("/admin/cc/integrations", headers=OWNER).json()["items"]}
    assert items["openai"]["status"] == "not_configured"
    assert client.post("/admin/cc/integrations/openai/check", headers=OWNER).status_code == 409


def test_analytics_totals_and_csv_export(cc):
    client, container, _ = cc
    _, analyst = _staff(client, "analyst")
    base = client.get("/admin/cc/analytics", headers=analyst, params={"days": 7}).json()["totals"]["requests"]
    for _ in range(2):
        container.universal_demand_repository.create(
            {"user_id": "app-an-" + uuid.uuid4().hex, "side": "NEED", "domain": "PRODUCT", "subject": "rice", "source": "app"})
    data = client.get("/admin/cc/analytics", headers=analyst, params={"days": 7}).json()
    assert data["totals"]["requests"] == base + 2
    assert sum(day["requests"] for day in data["daily"]) == data["totals"]["requests"]
    csv_response = client.get("/admin/cc/analytics/export.csv", headers=analyst, params={"days": 7})
    assert csv_response.status_code == 200
    assert csv_response.headers["content-type"].startswith("text/csv")
    assert csv_response.text.splitlines()[0] == "date,requests,matches,no_match,orders,escalations,seller_joins"


def test_listing_moderation_is_confirmed_reasoned_and_masked(cc):
    client, container, _ = cc
    seller = "app-phone-919876500001"
    listing_id = container.product_catalog_repository.upsert_product(seller, "Moderated mixer " + uuid.uuid4().hex[:6], price=3000)
    _, catalog = _staff(client, "catalog_manager")
    listings = client.get("/admin/cc/listings", headers=catalog, params={"q": "moderated mixer"})
    assert "919876500001" not in listings.text
    assert client.patch(f"/admin/cc/listings/{listing_id}", headers=catalog, json={"active": False, "reason": "spam"}).status_code == 409
    assert client.patch(f"/admin/cc/listings/{listing_id}", headers=catalog, json={"active": False, "confirm": True}).status_code == 422
    ok = client.patch(f"/admin/cc/listings/{listing_id}", headers=catalog,
                      json={"active": False, "confirm": True, "reason": "Duplicate listing"})
    assert ok.status_code == 200
    row = container.database.fetchone("SELECT active FROM seller_products WHERE id=?", (listing_id,))
    assert row["active"] == 0


def test_mask_user_id_keeps_only_last_four_digits():
    masked = mask_user_id("app-phone-919000000001")
    assert "919000000001" not in masked and masked.endswith("0001") and masked.startswith("app-phone-")


def _preflight(client, origin):
    return client.options("/admin/cc/me", headers={
        "Origin": origin, "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "x-askodox-admin-key"})


def test_web_command_center_cors_is_opt_in_and_origin_restricted(monkeypatch, tmp_path):
    from app.api.app_factory import create_app

    monkeypatch.setenv("PODX_DATABASE_PATH", str(tmp_path / "cors.db"))
    monkeypatch.delenv("ADMIN_WEB_ORIGINS", raising=False)
    closed = TestClient(create_app())
    assert "access-control-allow-origin" not in _preflight(closed, "https://admin.example").headers

    monkeypatch.setenv("ADMIN_WEB_ORIGINS", "https://admin.example")
    web = TestClient(create_app())
    allowed = _preflight(web, "https://admin.example")
    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == "https://admin.example"
    assert "x-askodox-admin-key" in allowed.headers["access-control-allow-headers"].lower()
    assert "access-control-allow-origin" not in _preflight(web, "https://evil.example").headers
    # CORS never replaces server-side authorization.
    assert web.get("/admin/cc/me", headers={"Origin": "https://admin.example"}).status_code == 401
