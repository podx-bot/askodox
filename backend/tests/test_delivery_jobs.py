"""Delivery foundation: request -> offer to approved partners -> accept ->
pickup -> transit -> delivered -> customer confirms. Never a fake partner."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-dl-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
PICKUP = {"label": "Shop, Vuyyuru", "latitude": 16.364, "longitude": 80.844}
DROP = {"label": "Home, Vuyyuru", "latitude": 16.372, "longitude": 80.851}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "d.db")),
                        raising=False)
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _partner(client, container, user_id, *, approve=True, services=("parcel",), at=(16.365, 80.845)):
    from app.api.routes.platform import user_ref

    r = client.post("/admin/cc/platform/r/delivery_partners", headers=OWNER, json={"data": {
        "name": "Test rider", "kind": "independent", "user_ref": user_ref(user_id), "services": list(services),
        "available": True, "latitude": at[0], "longitude": at[1], "radius_km": 5}})
    assert r.status_code == 200, r.text
    if approve:
        assert client.post(f"/admin/cc/platform/r/delivery_partners/{r.json()['id']}/actions/approve",
                           headers=OWNER, json={}).status_code == 200
    return r.json()["id"]


def test_matching_off_or_no_partner_is_reported_honestly(env):
    client, container = env
    _, customer = _user(container)
    job = client.post("/api/delivery/jobs", headers=customer, json={"kind": "parcel", "pickup": PICKUP, "drop": DROP})
    assert job.status_code == 200 and job.json()["status"] == "NEEDS_CONFIGURATION"
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    job = client.post("/api/delivery/jobs", headers=customer, json={"kind": "parcel", "pickup": PICKUP, "drop": DROP})
    assert job.json()["status"] == "NEEDS_PARTNER" and job.json()["offered"] == []
    assert client.post("/api/delivery/jobs", json={"kind": "parcel", "pickup": PICKUP, "drop": DROP}).status_code == 401


def test_full_lifecycle_with_an_approved_partner(env):
    client, container = env
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    cust_id, customer = _user(container)
    rider_id, rider = _user(container)
    _, stranger = _user(container)
    pending_id, pending = _user(container)
    _partner(client, container, pending_id, approve=False)  # not approved: never offered
    partner_id = _partner(client, container, rider_id)

    job = client.post("/api/delivery/jobs", headers=customer,
                      json={"kind": "parcel", "pickup": PICKUP, "drop": DROP, "order_id": "42"}).json()
    assert job["status"] == "PARTNER_SEARCH" and [o["partner_id"] for o in job["offered"]] == [partner_id]
    assert 0 < job["distance_km"] < 2

    offers = client.get("/api/delivery/offers", headers=rider).json()
    assert offers["partner"] is True and [j["id"] for j in offers["items"]] == [job["id"]]
    assert "requester" not in offers["items"][0], "the partner never sees the customer's id"
    assert client.get("/api/delivery/offers", headers=pending).json() == {"partner": False, "items": []}
    assert client.post(f"/api/delivery/jobs/{job['id']}/accept", headers=stranger).status_code == 403
    assert client.get(f"/api/delivery/jobs/{job['id']}", headers=stranger).status_code == 404

    assert client.post(f"/api/delivery/jobs/{job['id']}/accept", headers=rider).json()["status"] == "PARTNER_ACCEPTED"
    # wrong order / wrong actor refused
    assert client.post(f"/api/delivery/jobs/{job['id']}/status", headers=rider,
                       json={"status": "DELIVERED"}).status_code == 409
    assert client.post(f"/api/delivery/jobs/{job['id']}/status", headers=customer,
                       json={"status": "PICKED_UP"}).status_code == 403
    for step in ("PICKED_UP", "IN_TRANSIT", "DELIVERED"):
        assert client.post(f"/api/delivery/jobs/{job['id']}/status", headers=rider,
                           json={"status": step}).json()["status"] == step
    assert client.post(f"/api/delivery/jobs/{job['id']}/cancel", headers=customer, json={}).status_code == 409
    assert client.post(f"/api/delivery/jobs/{job['id']}/confirm", headers=rider).status_code == 403
    done = client.post(f"/api/delivery/jobs/{job['id']}/confirm", headers=customer).json()
    assert done["status"] == "CONFIRMED"
    assert [h["status"] for h in done["history"]] == ["REQUESTED", "PARTNER_SEARCH", "PARTNER_ACCEPTED", "PICKED_UP",
                                                       "IN_TRANSIT", "DELIVERED", "CONFIRMED"]


def test_service_type_and_cancel_rules(env):
    client, container = env
    container.command_center_repository.set_flag("delivery.matching", True, "test")
    _, customer = _user(container)
    rider_id, _ = _user(container)
    # Its own town, so partners created by other tests are out of range.
    here = {"label": "Shop, Guntur", "latitude": 16.30, "longitude": 80.44}
    there = {"label": "Home, Guntur", "latitude": 16.31, "longitude": 80.45}
    _partner(client, container, rider_id, services=("food",), at=(16.301, 80.441))
    parcel = client.post("/api/delivery/jobs", headers=customer,
                         json={"kind": "parcel", "pickup": here, "drop": there}).json()
    assert parcel["status"] == "NEEDS_PARTNER", "a food-only rider is not offered a parcel"
    food = client.post("/api/delivery/jobs", headers=customer,
                       json={"kind": "food", "pickup": here, "drop": there}).json()
    assert food["status"] == "PARTNER_SEARCH"
    assert client.post(f"/api/delivery/jobs/{food['id']}/cancel", headers=customer,
                       json={"reason": "changed mind"}).json()["status"] == "CANCELLED"
    assert client.post("/api/delivery/jobs", headers=customer,
                       json={"kind": "rocket", "pickup": PICKUP, "drop": DROP}).status_code == 422
