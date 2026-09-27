"""Universal real results without a sign-in wall + a real Admin flow trace.

* /deals/discover browses the same universal pipeline with no token.
* Every request/results/order/dispute step is written to the trace that
  Admin Web shows (/admin/cc/traces) -- actual events, no dummy data.
* Admin traces need staff permission; they never carry tokens or raw ids.
Fixture listings here are test data, not production results.
"""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-trace-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    repo = CommandCenterRepository(str(tmp_path / "trace.db"))
    monkeypatch.setattr(container, "command_center_repository", repo, raising=False)
    return TestClient(app), container, repo


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def phone():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def body(subject, **extra):
    return {
        "user_id": "", "raw_text": f"{subject} show me", "intent": "buy", "subject": subject,
        "category": "product", "quantity": None, "unit": None, "price": 30000,
        "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
        "dynamic_fields": {"budget_min": 20000, "budget_max": 30000}, **extra,
    }


def test_guest_browses_real_results_without_sign_in_and_admin_sees_the_trace(api):
    client, container, _ = api
    seller = phone()
    listed = client.post("/api/products/mine", headers=auth(container, seller),
                         json={"seller_user_id": seller, "subject": "43 inch smart TV", "price": 25000})
    assert listed.status_code == 200, listed.text

    trace = {"query": "నాకు 43-inch TV ₹20,000–₹30,000 లో కావాలి — show me", "intent": "buy",
             "questions": ["What size?"], "answers": ["43 inch"], "auth_gate": "guest: results shown without sign-in"}
    r = client.post("/deals/discover", json=body("43 inch TV", trace=trace))
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["deal_id"] is None
    assert set(data["requires_sign_in_for"]) == {"send_request", "contact_seller"}
    assert "source_status" in data and isinstance(data["matches"], list)
    assert seller[-10:] not in r.text, "seller contact never exposed while browsing"

    assert client.post("/deals/discover", json=body("")).status_code == 422

    assert client.get("/admin/cc/traces").status_code == 401
    rows = client.get("/admin/cc/traces", headers=OWNER).json()
    row = next(item for item in rows["items"] if item["query"] == trace["query"])
    assert row["user"] == "guest"
    assert row["stage"] in {"results_sent", "no_results"}
    assert "guest" in row["auth_gate"]
    full = client.get(f"/admin/cc/traces/{row['id']}", headers=OWNER).json()
    for key in ("sources", "source_counts", "filtered", "fallback", "latency_ms", "timeline", "slots"):
        assert key in full, key
    assert full["questions"] == ["What size?"] and full["answers"] == ["43 inch"]
    assert full["slots"].get("budget_max") == 30000
    assert isinstance(full["master_web"], bool) and isinstance(full["local_search"], bool)
    assert [step["stage"] for step in full["timeline"]][:2] == ["request_received", full["stage"]]


def test_signed_in_deal_trace_follows_request_accept_dispute(api):
    client, container, _ = api
    seller = phone()
    pid = client.post("/api/products/mine", headers=auth(container, seller),
                      json={"seller_user_id": seller, "subject": "AC installation service", "price": 1500,
                            "unit": "per visit"}).json()["id"]
    buyer = phone()
    created = client.post("/deals", headers=auth(container, buyer),
                          json=body("AC installation", user_id=buyer, category="service", intent="needService",
                                    trace={"query": "I need AC installation", "questions": [], "answers": []}))
    assert created.status_code == 200, created.text
    deal_id = created.json()["id"]
    assert client.get(f"/deals/{deal_id}/matches", headers=auth(container, buyer)).status_code == 200

    order = client.post("/api/orders", headers=auth(container, buyer),
                        json={"buyer_user_id": buyer, "product_id": pid, "quantity": 1,
                              "request_context": {"subject": "AC installation", "deal_id": str(deal_id)}})
    assert order.status_code == 200, order.text
    oid = order.json()["id"]
    assert client.post(f"/api/orders/{oid}/status", headers=auth(container, seller),
                       json={"seller_user_id": seller, "status": "ACCEPTED"}).status_code == 200
    problem = client.post(f"/api/orders/{oid}/problem", headers=auth(container, buyer),
                          json={"issue": "Water leaking", "category": "SERVICE"})
    assert problem.status_code == 200, problem.text

    rows = client.get("/admin/cc/traces", headers=OWNER).json()["items"]
    row = next(item for item in rows if item["query"] == "I need AC installation")
    full = client.get(f"/admin/cc/traces/{row['id']}", headers=OWNER).json()
    stages = [step["stage"] for step in full["timeline"]]
    assert stages[0] == "request_received"
    assert "request_sent" in stages and "seller_accepted" in stages and stages[-1] == "disputed"
    assert full["seller_request"]["order_id"] == oid
    assert full["escalation"]["status"] == "OPEN" and full["escalation"]["case_id"]
    text = str(full)
    assert buyer not in text and seller not in text, "trace carries masked ids only"
    assert "Bearer" not in text and container.settings.session_token_secret not in text


def test_trace_requires_staff_permission(api):
    client, _, _ = api

    def staff(role):
        token = client.post("/admin/cc/staff", headers=OWNER, json={"name": role, "role": role}).json()["token"]
        return {"X-ASKODOX-Staff-Token": token}

    assert client.get("/admin/cc/traces", headers=staff("analyst")).status_code == 403
    assert client.get("/admin/cc/traces/1", headers=staff("analyst")).status_code == 403
    assert client.get("/admin/cc/traces", headers=staff("support_agent")).status_code == 200
    assert client.get("/admin/cc/traces", headers={"X-ASKODOX-Staff-Token": "stf_forged"}).status_code == 401
