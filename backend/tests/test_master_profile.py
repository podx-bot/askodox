"""Universal Master Profile: one record, many roles, explicit active role."""
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


@pytest.fixture()
def api():
    from server import app, container

    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    auth = {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}
    return TestClient(app), auth


def test_core_fields_links_and_role_details_save_and_load(api):
    client, auth = api
    r = client.put("/api/me/profile", headers=auth, json={
        "name": "Asha Rao", "email": "asha@example.com", "language": "te", "address": "Vuyyuru",
        "roles": ["buyer", "seller", "delivery_partner"],
        "links": [{"kind": "instagram", "url": "https://instagram.com/asha"}, {"kind": "x", "url": ""}],
        "role_details": {"seller": {"business_type": "grocery", "working_hours": "8-20", "hack": "x"},
                         "delivery_partner": {"vehicle_type": "two_wheeler", "operating_area": "Vuyyuru"},
                         "survey_taker": {"interests": ["food", "travel"]}},
    })
    assert r.status_code == 200, r.text
    again = client.get("/api/me/profile", headers=auth).json()
    assert again["email"] == "asha@example.com" and again["roles"] == ["buyer", "seller", "delivery_partner"]
    assert again["links"] == [{"kind": "instagram", "url": "https://instagram.com/asha"}]
    assert again["role_details"]["seller"] == {"business_type": "grocery", "working_hours": "8-20"}, \
        "unknown fields of a known role are dropped"
    assert again["role_details"]["survey_taker"]["interests"] == ["food", "travel"]
    # partial update keeps the other roles' details
    client.put("/api/me/profile", headers=auth, json={"role_details": {"seller": {"description": "Fresh"}}})
    details = client.get("/api/me/profile", headers=auth).json()["role_details"]
    assert details["seller"]["business_type"] == "grocery" and details["seller"]["description"] == "Fresh"
    assert details["delivery_partner"]["vehicle_type"] == "two_wheeler"
    assert client.put("/api/me/profile", headers=auth, json={"email": "not-an-email"}).status_code == 422
    assert client.put("/api/me/profile", headers=auth,
                      json={"links": [{"kind": "website", "url": "javascript:alert(1)"}]}).status_code == 422


def test_active_role_switches_only_explicitly_and_only_to_held_roles(api):
    client, auth = api
    client.put("/api/me/profile", headers=auth, json={"roles": ["buyer", "seller"]})
    assert client.get("/api/me/profile", headers=auth).json()["active_role"] is None
    assert client.put("/api/me/profile", headers=auth, json={"active_role": "driver"}).status_code == 422
    assert client.put("/api/me/profile", headers=auth, json={"active_role": "seller"}).json()["active_role"] == "seller"
    # removing the active role clears it (never silently switched to another)
    after = client.put("/api/me/profile", headers=auth, json={"roles": ["buyer"]}).json()
    assert after["active_role"] is None


def test_schema_lists_roles_and_fields(api):
    client, _ = api
    schema = client.get("/api/me/profile/schema").json()
    for role in ("buyer", "seller", "service_provider", "service_seeker", "job_seeker", "delivery_partner",
                 "survey_taker"):
        assert role in schema["roles"]
    assert "vehicle_type" in schema["roles"]["delivery_partner"]
