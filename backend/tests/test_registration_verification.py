"""ONE master profile, many roles: progressive registration (draft until the
role's required details exist) and a staff verification queue that never
stores a full ID / document number."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token

OWNER_KEY = "owner-rv-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def test_progressive_registration_for_many_roles(env):
    client, container = env
    _, me = _user(container)
    assert client.get("/api/me/profile/registration").status_code == 401
    client.put("/api/me/profile", headers=me, json={"name": "Ravi", "language": "te", "address": "Vuyyuru",
                                                     "roles": ["restaurant", "cab_driver"],
                                                     "role_details": {"restaurant": {"cuisine": "Andhra meals"}}})
    reg = client.get("/api/me/profile/registration", headers=me).json()
    by = {r["role"]: r for r in reg["roles"]}
    assert by["restaurant"]["status"] == "draft" and by["restaurant"]["missing"] == ["operating_hours"]
    assert by["cab_driver"]["missing"] == ["vehicle_type", "vehicle_number", "operating_area"]
    assert reg["complete"] is False and reg["basics_missing"] == []
    client.put("/api/me/profile", headers=me, json={"role_details": {
        "restaurant": {"operating_hours": "11-23"},
        "cab_driver": {"vehicle_type": "car", "vehicle_number": "AP16AB1234", "operating_area": "Vijayawada"}}})
    reg = client.get("/api/me/profile/registration", headers=me).json()
    assert reg["complete"] is True, "the draft was kept and completed later"
    assert client.get("/api/me/profile/schema").json()["required"]["fleet_owner"] == [
        "fleet_size", "vehicle_types", "operating_area"]


def test_verification_queue_keeps_only_last4_and_staff_decides(env):
    client, container = env
    uid, me = _user(container)
    client.put("/api/me/profile", headers=me, json={"name": "Lakshmi", "roles": ["seller"]})
    assert client.post("/api/me/profile/verification", headers=me,
                       json={"role": "cab_driver"}).status_code == 422, "only a role you hold"
    asked = client.post("/api/me/profile/verification", headers=me, json={
        "role": "seller", "reference_kind": "gstin", "reference": "37ABCDE1234F1Z5", "note": "kirana"}).json()
    assert asked == {"role": "seller", "verification": "pending"}
    again = client.post("/api/me/profile/verification", headers=me, json={"role": "seller"}).json()
    assert again["verification"] == "pending", "no duplicate requests"
    from app.api.routes.platform import platform, user_ref

    rows = [r for r in platform(container).resources.repo.list("role_verifications")
            if r["data"]["user_ref"] == user_ref(uid)]
    assert len(rows) == 1 and rows[0]["data"]["reference_last4"] == "F1Z5"
    assert "37ABCDE1234F1Z5" not in str(rows[0]), "the full number is never stored"
    assert client.post(f"/admin/cc/platform/r/role_verifications/{rows[0]['id']}/actions/approve",
                       headers=OWNER, json={}).status_code == 200
    profile = client.get("/api/me/profile", headers=me).json()
    assert profile["role_verifications"] == {"seller": "verified"}
