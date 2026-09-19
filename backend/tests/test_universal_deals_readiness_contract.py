import os
import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


def test_deals_response_exposes_canonical_readiness_contract_and_same_followup(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "readiness.db"))
    monkeypatch.setenv("GEMINI_API_KEY", "")
    monkeypatch.setenv("OPENAI_API_KEY", "")
    from server import app, container

    class FakeExtractor:
        def extract(self, message):
            text = str(message).casefold()
            return {
                "success": True,
                "request": {
                    "side": "NEED",
                    "domain": "PRODUCT",
                    "subject": "rice",
                    "quantity": 2.0 if "2kg" in text else None,
                    "unit": "kg" if "2kg" in text else None,
                    "location_text": "Vijayawada",
                    "location_required": False,
                    "confidence": 0.95,
                    "constraints": [],
                },
            }

    previous_extract = container.universal_request_extractor.extract
    container.universal_request_extractor.extract = FakeExtractor().extract
    user_id = f"app-readiness-user-{uuid.uuid4().hex}"
    headers = {"Authorization": f"Bearer {issue_token(user_id, container.settings.session_token_secret)}"}
    try:
        client = TestClient(app)
        first = client.post(
            "/deals",
            json={"user_id": user_id, "raw_text": "I need rice near Vijayawada"},
            headers=headers,
        )
        assert first.status_code == 200, first.text
        first_body = first.json()
        assert first_body["readiness"]["canonical"]["subject"] == "rice"
        first_id = first_body["deal_id"]

        followup = client.post(
            "/deals",
            json={"user_id": user_id, "raw_text": "2kg"},
            headers=headers,
        )
        assert followup.status_code == 200, followup.text
        body = followup.json()
        assert body["deal_id"] == first_id
        assert body["readiness"]["canonical"]["quantity"] == 2.0
        assert body["readiness"]["canonical"]["location"] == "Vijayawada"
    finally:
        container.universal_request_extractor.extract = previous_extract