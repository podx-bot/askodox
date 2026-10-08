"""My Creations: owner-only CRUD, AI drafts from the owner's facts only,
honest unavailability, no image / video generation claimed, never posted."""
import uuid

from fastapi.testclient import TestClient

from app.services import business_creations as creations
from app.services.session_tokens import issue_token


def _auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def _user():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def test_capabilities_never_claim_generation():
    caps = creations.capabilities(ai_ready=True)
    assert caps["image_generation"]["status"] == "NOT_AVAILABLE"
    assert caps["video_generation"]["status"] == "NOT_AVAILABLE"
    assert caps["video_upload"]["status"] == "READY"
    assert caps["publish_external"]["status"] == "MANUAL_ONLY"
    assert creations.capabilities(ai_ready=False)["text_drafts"]["status"] == "NOT_AVAILABLE"


def test_draft_prompt_forbids_invented_facts():
    prompt = creations.draft_prompt("offer_text", "Diwali sale on sarees", "te")
    assert "Telugu" in prompt and "Never invent prices" in prompt and "[placeholder]" in prompt
    assert "Diwali sale on sarees" in prompt


def test_owner_only_crud_and_drafts(monkeypatch):
    from server import app, container

    client = TestClient(app)
    alice, bob = _auth(container, _user()), _auth(container, _user())
    assert client.get("/api/business/creations").status_code == 401
    made = client.post("/api/business/creations", headers=alice,
                       json={"kind": "post", "body": "New stock of cotton sarees.", "title": "Stock"}).json()
    assert made["status"] == "draft" and made["source"] == "owner"
    assert client.post("/api/business/creations", headers=alice, json={"kind": "spam", "body": "x"}).status_code == 422
    assert client.get("/api/business/creations", headers=bob).json()["items"] == []
    assert client.patch(f"/api/business/creations/{made['id']}", headers=bob, json={"body": "x"}).status_code == 404
    saved = client.patch(f"/api/business/creations/{made['id']}", headers=alice, json={"status": "saved"}).json()
    assert saved["status"] == "saved"

    ai = container.universal_ai_assistant_service
    monkeypatch.setattr(ai, "write_text", lambda prompt, **kw: "")
    monkeypatch.setattr(type(ai), "configured", property(lambda self: True))
    down = client.post("/api/business/creations/draft", headers=alice,
                       json={"kind": "description", "about": "cotton sarees 500 rupees"})
    assert down.status_code == 503 and "not available" in down.json()["detail"]
    seen = {}

    def fake(prompt, **kw):
        seen["prompt"] = prompt
        return "Soft cotton sarees at Rs 500. [shop timings]"

    monkeypatch.setattr(ai, "write_text", fake)
    draft = client.post("/api/business/creations/draft", headers=alice,
                        json={"kind": "description", "about": "cotton sarees 500 rupees"}).json()
    assert draft["source"] == "ai" and "Nothing is posted automatically" in draft["note"]
    assert "cotton sarees 500 rupees" in seen["prompt"]
    assert len(client.get("/api/business/creations", headers=alice).json()["items"]) == 1, "a draft is not saved"
    assert client.delete(f"/api/business/creations/{made['id']}", headers=alice).json() == {"deleted": True}
