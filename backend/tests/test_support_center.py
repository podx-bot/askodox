"""Unified Support Center: AI first, ticket, staff alert, two-way conversation
(public replies vs internal notes), reopen / escalate, IDOR protection."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-sup-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "sup.db"))
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "sup.db")),
                        raising=False)
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _agent(client, perms=None):
    body = {"name": "agent", "role": "support_agent"}
    if perms is not None:
        body["permissions"] = perms
    r = client.post("/admin/cc/staff", headers=OWNER, json=body).json()
    return {"X-ASKODOX-Staff-Token": r["token"]}, f"staff-{r['id']}"


def test_two_way_conversation_notes_stay_internal(env):
    client, container = env
    uid, user_h = _user(container)
    case_id = client.post("/api/in-app/support/escalate", headers=user_h, json={
        "issue": "Paid but seller says not received", "category": "PAYMENT",
        "conversation": [{"role": "user", "text": "paid"}, {"role": "assistant", "text": "Let me check"}],
    }).json()["case_id"]
    agent, agent_id = _agent(client)
    ticket = client.get(f"/admin/cc/escalations/{case_id}", headers=agent).json()
    assert ticket["context"]["ai_attempted"] is True
    assert uid not in str(ticket)

    client.patch(f"/admin/cc/escalations/{case_id}", headers=agent, json={"note": "Suspect UPI delay - internal"})
    r = client.post(f"/admin/cc/escalations/{case_id}/reply", headers=agent,
                    json={"message": "Please share the UTR number from your UPI app."})
    assert r.status_code == 200 and r.json()["status"] == "WAITING_FOR_USER" and r.json()["first_response_at"]

    mine = client.get(f"/api/in-app/support/cases/{case_id}", headers=user_h).json()
    bodies = [m["body"] for m in mine["messages"]]
    assert "Please share the UTR number from your UPI app." in bodies
    assert "Suspect UPI delay - internal" not in str(mine) and agent_id not in str(mine)
    assert all("author" not in m for m in mine["messages"])

    reply = client.post(f"/api/in-app/support/cases/{case_id}/reply", headers=user_h,
                        json={"message": "UTR 123456789012", "attachments": ["att_1", "<script>"]})
    assert reply.status_code == 200 and reply.json()["status"] == "IN_PROGRESS"
    thread = client.get(f"/admin/cc/escalations/{case_id}", headers=agent).json()["thread"]
    last = [m for m in thread if m["kind"] == "message"][-1]
    assert last["from"] == "customer" and last["attachments"] == ["att_1"]
    assert any(n["kind"] == "support_reply" for n in client.get("/admin/cc/notifications", headers=OWNER).json()["items"])
    assert case_id in [c["case_id"] for c in client.get("/api/in-app/support/cases", headers=user_h).json()["items"]]


def test_other_users_cannot_read_or_reply(env):
    client, container = env
    _, owner_h = _user(container)
    _, other_h = _user(container)
    case_id = client.post("/api/in-app/support/escalate", headers=owner_h, json={"issue": "help"}).json()["case_id"]
    assert client.get(f"/api/in-app/support/cases/{case_id}", headers=other_h).status_code == 404
    assert client.post(f"/api/in-app/support/cases/{case_id}/reply", headers=other_h,
                       json={"message": "hi"}).status_code == 404
    assert client.get(f"/api/in-app/support/cases/{case_id}").status_code == 404
    assert client.get("/api/in-app/support/cases").status_code == 401
    assert case_id not in [c["case_id"] for c in client.get("/api/in-app/support/cases", headers=other_h).json()["items"]]


def test_resolve_reopen_escalate_and_permissions(env):
    client, container = env
    _, user_h = _user(container)
    case_id = client.post("/api/in-app/support/escalate", headers=user_h, json={"issue": "Order late"}).json()["case_id"]
    agent, _ = _agent(client)
    viewer, _ = _agent(client, perms=["support:view"])
    assert client.post(f"/admin/cc/escalations/{case_id}/reply", headers=viewer,
                       json={"message": "x"}).status_code == 403
    done = client.post(f"/admin/cc/escalations/{case_id}/reply", headers=agent,
                       json={"message": "Delivered today", "status": "RESOLVED"}).json()
    assert done["status"] == "RESOLVED" and done["resolution_note"] == "Delivered today"
    # The customer answering a resolved ticket reopens it.
    again = client.post(f"/api/in-app/support/cases/{case_id}/reply", headers=user_h, json={"message": "Not yet!"})
    assert again.json()["status"] == "OPEN"
    up = client.post(f"/admin/cc/escalations/{case_id}/escalate", headers=agent,
                     json={"reason": "Customer waiting 2 days", "assigned_to": "lead"}).json()
    assert up["priority"] == "HIGH" and up["assigned_to"] == "lead"
    found = client.get("/admin/cc/escalations", headers=agent, params={"q": "Order late"}).json()["items"]
    assert [i["id"] for i in found] == [case_id]
    client.patch(f"/admin/cc/escalations/{case_id}", headers=agent,
                 json={"status": "CLOSED", "confirm": True, "resolution_note": "done"})
    assert client.post(f"/api/in-app/support/cases/{case_id}/reply", headers=user_h,
                       json={"message": "?"}).status_code == 409
    assert client.post(f"/admin/cc/escalations/{case_id}/reopen", headers=agent).json()["status"] == "OPEN"


def test_guest_cases_are_not_readable_by_other_guests(env):
    client, _ = env
    case_id = client.post("/api/in-app/support/escalate", json={"issue": "guest help"}).json()["case_id"]
    assert client.get(f"/api/in-app/support/cases/{case_id}").status_code == 404
    assert client.post(f"/api/in-app/support/cases/{case_id}/reply", json={"message": "x"}).status_code == 404
