"""Conversations & Automation: platform status is real (never claimed),
ON/OFF, approved answers, handover and out-of-hours preview."""
import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


def _auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def test_platform_status_is_real_and_never_claimed_connected():
    from server import app, container

    client = TestClient(app)
    seller = _auth(container, "app-phone-91" + str(uuid.uuid4().int)[:10])
    view = client.get("/api/business/auto-response", headers=seller).json()
    platforms = view["platforms"]
    assert platforms["askodox_chat"]["status"] == "LIVE"
    assert platforms["snapchat"]["status"] == "NOT_AVAILABLE"
    for social in ("facebook", "instagram", "whatsapp"):
        assert platforms[social]["status"] != "LIVE", "no verified platform connection in tests"
        assert platforms[social]["reason"]


def test_on_off_handover_and_out_of_hours():
    from server import app, container

    client = TestClient(app)
    seller = _auth(container, "app-phone-91" + str(uuid.uuid4().int)[:10])
    saved = client.put("/api/business/auto-response", headers=seller, json={
        "enabled": True, "faq": {"delivery": "Free delivery within 5 km."}, "handoff_words": ["complaint"]}).json()
    assert saved["item"]["status"] == "ACTIVE"
    assert client.post("/api/business/auto-response/preview", headers=seller,
                       json={"message": "I have a complaint"}).json()["status"] == "handoff"
    off = client.put("/api/business/auto-response", headers=seller, json={"enabled": False}).json()
    assert off["item"]["status"] == "DISABLED"
    bad = client.put("/api/business/auto-response", headers=seller, json={"enabled": True, "business_hours": "9am-9pm"})
    assert bad.status_code == 400
