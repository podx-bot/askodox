"""AI-first support escalation reaches the Command Center with full context; Explore feed is real."""
import dataclasses
import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


def test_escalation_carries_full_context_to_command_center(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "support.db"))
    monkeypatch.setenv("SUPPORT_WHATSAPP_NUMBER", "+91 90000 00000")
    monkeypatch.delenv("SUPPORT_PHONE_NUMBER", raising=False)
    from server import app, container

    user = "app-support-" + uuid.uuid4().hex
    headers = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    response = client.post("/api/in-app/support/escalate", headers=headers, json={
        "issue": "Money deducted but order not confirmed",
        "category": "PAYMENT",
        "critical": True,
        "conversation": [{"role": "user", "text": "I paid 500 but no order"},
                         {"role": "assistant", "text": "Please check your UPI app for a reference."}],
        "requirement": {"subject": "chicken", "quantity": 1, "unit": "kg"},
        "deal_id": "301",
        "counterpart": "Fresh Chicken Shop",
        "actions_tried": ["Checked UPI reference"],
        "status": "PAYMENT_PENDING",
        "active_role": "Buyer",
    })

    assert response.status_code == 200
    body = response.json()
    assert body["case_id"]
    assert body["channels"] == {"chat": True, "whatsapp_url": "https://wa.me/919000000000", "call_uri": None}

    hidden = client.get("/admin/support/escalations", params={"key": "wrong"})
    assert hidden.status_code == 404
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key="admin-key"))
    feed = client.get("/admin/support/escalations", params={"key": "admin-key"}).json()["items"]
    case = next(item for item in feed if item["id"] == body["case_id"])
    assert case["requester_user_id"] == user
    assert case["critical"] is True
    assert case["context"]["deal_id"] == "301"
    assert case["context"]["conversation"][0]["text"] == "I paid 500 but no order"
    assert case["context"]["actions_tried"] == ["Checked UPI reference"]
    assert case["context"]["requirement"]["subject"] == "chicken"


def test_guest_can_escalate(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "support-guest.db"))
    from server import app

    response = TestClient(app).post("/api/in-app/support/escalate", json={"issue": "App keeps crashing"})
    assert response.status_code == 200
    assert response.json()["channels"]["chat"] is True


def test_explore_feed_is_real_listings_with_chat_prompts(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "explore.db"))
    from server import app, container

    title = "Explore Fridge " + uuid.uuid4().hex[:6]
    container.product_catalog_repository.upsert_product("app-phone-919999999999", title, variant="open box", price=18000)
    body = TestClient(app).get("/api/discover/explore", params={"location": "Vijayawada"})

    assert body.status_code == 200
    item = next(row for row in body.json()["items"] if row["title"].startswith(title))
    assert item["segment"] == "surplus"
    assert item["prompt"] == f"I want to buy {item['title']} in Vijayawada"
    assert "919999999999" not in body.text
