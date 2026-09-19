import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


def test_review_requires_completion_and_prevents_duplicates(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "reviews.db"))
    from server import app, container

    owner = "app-review-" + uuid.uuid4().hex
    seller = "app-seller-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create({
        "user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": "rice", "source": "test",
    })
    headers = {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}
    container.universal_notification_repository.record_interest(demand_id, owner, seller)
    with TestClient(app) as client:
        blocked = client.post(f"/deals/{demand_id}/review", json={"reviewed_user_id": seller, "rating": 5}, headers=headers)
        assert blocked.status_code == 409
        container.universal_notification_repository.set_seller_decision(demand_id, seller, True)
        container.universal_notification_repository.mark_waiting_address(demand_id, seller)
        container.universal_notification_repository.save_delivery_address(demand_id, seller, "12 Main Street, Vijayawada")
        container.universal_notification_repository.confirm_order(demand_id, seller)
        first = client.post(f"/deals/{demand_id}/review", json={"reviewed_user_id": seller, "rating": 5, "review_text": "Good"}, headers=headers)
        second = client.post(f"/deals/{demand_id}/review", json={"reviewed_user_id": seller, "rating": 5}, headers=headers)
    assert first.status_code == 200
    assert first.json()["status"] == "RECORDED"
    assert second.status_code == 200
    assert second.json()["status"] == "ALREADY_REVIEWED"