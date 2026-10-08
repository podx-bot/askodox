"""Conversation -> profile memory: roles, update-not-duplicate, statuses,
history, privacy, secrets never stored, user controls, per-user isolation."""
import time
import uuid

from fastapi.testclient import TestClient

from app.services import profile_memory as memory
from app.services.session_tokens import issue_token


def _user():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def _auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def test_roles_from_the_understood_request_service_taker_is_a_seeker():
    assert memory.role_of({"side": "NEED", "domain": "PRODUCT", "subject": "43 inch TV"}) == "buyer"
    assert memory.role_of({"side": "OFFER", "domain": "PRODUCT", "subject": "used bikes"}) == "seller"
    assert memory.role_of({"side": "NEED", "domain": "SERVICES", "subject": "plumber"}) == "service_taker"
    assert memory.role_of({"side": "OFFER", "domain": "SERVICES", "subject": "AC repair"}) == "service_provider"
    assert "survey_taker" not in memory.ROLES


def test_same_need_updates_with_history_and_secrets_are_never_stored(tmp_path):
    db, user = str(tmp_path / "m.db"), _user()
    first = memory.record_from_demand(db, user, {
        "id": 7, "side": "NEED", "domain": "PRODUCT", "subject": "43 inch TV", "price": 30000,
        "location_text": "Vijayawada", "said": "call me 9876543210, my otp is 482913",
        "constraints": {"brand": "Samsung", "otp": "482913", "card_number": "4111 1111 1111 1111",
                        "requested_groups": ["online"]}})
    assert first["role"] == "buyer" and first["kind"] == "need" and first["status"] == "active"
    assert first["visibility"] == "private"
    flat = str(first)
    for secret in ("482913", "4111", "9876543210", "card_number", "requested_groups"):
        assert secret not in flat, secret
    assert first["details"]["brand"] == "Samsung" and first["source"]["deal_id"] == 7

    again = memory.record_from_demand(db, user, {
        "id": 8, "side": "NEED", "domain": "PRODUCT", "subject": "43 inch TVs", "price": 25000,
        "constraints": {"brand": "Samsung"}})
    assert again["id"] == first["id"], "update, never a duplicate"
    assert again["status"] == "updated" and again["details"]["budget"] == 25000
    assert len(memory.items(db, user)) == 1
    hist = memory.history(db, user, first["id"])
    assert [h["action"] for h in hist] == ["created", "updated"]
    assert hist[1]["change"]["budget"] == {"from": 30000, "to": 25000}


def test_expiry_status_and_public_needs_consent(tmp_path):
    db, user = str(tmp_path / "m.db"), _user()
    item = memory.record_from_demand(db, user, {"side": "NEED", "domain": "SERVICES", "subject": "plumber"},
                                     now=time.time() - memory.EXPIRY_SECONDS - 10)
    assert memory.get(db, user, item["id"])["status"] == "expired"
    try:
        memory.correct(db, user, item["id"], visibility="public")
        raise AssertionError("public without consent must fail")
    except PermissionError:
        pass
    public = memory.correct(db, user, item["id"], visibility="public", consent=True)
    assert public["visibility"] == "public"
    assert "source" not in memory.public_view(public)
    done = memory.correct(db, user, item["id"], status="completed")
    assert done["status"] == "completed"


def test_disabled_memory_records_nothing(tmp_path):
    db, user = str(tmp_path / "m.db"), _user()
    memory.set_enabled(db, user, False)
    assert memory.record_from_demand(db, user, {"side": "NEED", "subject": "rice"}) is None
    assert memory.items(db, user) == []


def test_api_is_per_user_and_fully_controllable():
    from server import app, container

    client = TestClient(app)
    alice, bob = _user(), _user()
    created = client.post("/deals", headers=_auth(container, alice), json={
        "user_id": alice, "raw_text": "I want a 43 inch TV in Vijayawada", "intent": "buy",
        "subject": "43 inch TV", "category": "product", "price": 30000,
        "trace": {"query": "43 inch TV under 30000 my otp 552211"}})
    assert created.status_code == 200, created.text

    assert client.get("/api/me/memory").status_code == 401
    mine = client.get("/api/me/memory", headers=_auth(container, alice)).json()
    assert mine["enabled"] is True and len(mine["items"]) == 1
    item = mine["items"][0]
    assert item["role"] == "buyer" and item["subject"].lower().startswith("43 inch tv")
    assert "552211" not in str(item)
    assert client.get("/api/me/memory", headers=_auth(container, bob)).json()["items"] == [], "strict isolation"
    assert client.patch(f"/api/me/memory/{item['id']}", headers=_auth(container, bob),
                        json={"status": "cancelled"}).status_code == 404
    assert client.delete(f"/api/me/memory/{item['id']}", headers=_auth(container, bob)).status_code == 404

    fixed = client.patch(f"/api/me/memory/{item['id']}", headers=_auth(container, alice),
                         json={"details": {"budget": 28000}}).json()
    assert fixed["details"]["budget"] == 28000
    assert client.patch(f"/api/me/memory/{item['id']}", headers=_auth(container, alice),
                        json={"visibility": "public"}).status_code == 403
    assert client.patch(f"/api/me/memory/{item['id']}", headers=_auth(container, alice),
                        json={"status": "expired"}).status_code == 422
    hist = client.get(f"/api/me/memory/{item['id']}/history", headers=_auth(container, alice)).json()["history"]
    assert hist[-1]["action"] == "corrected_by_user"

    assert client.put("/api/me/memory/settings", headers=_auth(container, alice),
                      json={"enabled": False}).json() == {"enabled": False}
    client.post("/deals", headers=_auth(container, alice), json={
        "user_id": alice, "raw_text": "need a plumber", "intent": "service", "subject": "plumber",
        "category": "services"})
    assert len(client.get("/api/me/memory", headers=_auth(container, alice)).json()["items"]) == 1, "disabled"

    assert client.delete("/api/me/memory", headers=_auth(container, alice)).status_code == 422
    assert client.delete("/api/me/memory?confirm=DELETE", headers=_auth(container, alice)).json()["deleted"] == 1
    assert client.get("/api/me/memory", headers=_auth(container, alice)).json()["items"] == []


def test_account_deletion_removes_memory():
    from server import app, container

    client = TestClient(app)
    user = _user()
    memory.record_from_demand(container.settings.database_path, user, {"side": "NEED", "subject": "rice bag"})
    assert client.delete("/api/me?confirm=DELETE", headers=_auth(container, user)).json()["deleted"] is True
    assert memory.items(container.settings.database_path, user) == []
