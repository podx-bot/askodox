"""Universal category hierarchy: deepest match, inherited capabilities, the
provider side of the same category, and staff-configurable nodes."""
from fastapi.testclient import TestClient

from app.services.taxonomy import DEFAULT_NODES, Taxonomy

T = Taxonomy(DEFAULT_NODES)


def test_delivery_subcategories_inherit_the_delivery_actions():
    food = T.resolve("Can you deliver food?")
    assert food["key"] == "food_delivery" and [p["key"] for p in food["path"]] == ["delivery", "food_delivery"]
    assert food["mobility_kind"] == "food" and "request_delivery" in food["actions"]
    docs = T.resolve("documents delivery to the court")
    assert [p["key"] for p in docs["path"]] == ["delivery", "parcel", "documents"], "deeper level inherits"
    assert docs["mobility_kind"] == "documents" and "request_delivery" in docs["actions"]
    parcel = T.resolve("నాకు పార్సెల్ పంపాలి")
    assert parcel["key"] == "parcel" and "request_delivery" in parcel["actions"]


def test_provider_side_of_the_same_category():
    partner = T.resolve("I can work as a delivery partner")
    assert partner["role"] == "provider" and partner["actions"] == ["join_as_partner"]
    driver = T.resolve("I want to become a taxi driver")
    assert driver["role"] == "provider" and "join_as_partner" in driver["actions"]
    assert T.resolve("need a taxi to the bus stand")["actions"] == ["request_ride", "contact_after_accept"]


def test_overrides_and_unrelated_domains():
    carpool = T.resolve("carpool to Hyderabad")
    assert "carpool" in carpool["actions"] and "request_ride" not in carpool["actions"], "a child may remove"
    loan = T.resolve("need a personal loan")
    assert loan["high_stakes"] is True and "advice" in loan["actions"]
    assert T.resolve("automatic washing machine").get("key") != "ride_auto", "whole words only"
    assert T.resolve("xyz")["matched"] is False


def test_api_reads_the_configurable_store(monkeypatch, tmp_path):
    import dataclasses

    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                     database_path=str(tmp_path / "tx.db")))
    client = TestClient(app)
    body = client.get("/api/taxonomy/resolve", params={"q": "grocery delivery please"}).json()
    assert body["key"] == "grocery_delivery" and body["mobility_kind"] == "grocery"
    from app.api.routes.platform import platform

    pf = platform(container)
    pf.resources.create("taxonomy_nodes", {"key": "medicine_delivery", "label": "Medicine delivery",
                                           "parent": "delivery", "aliases": ["medicine delivery", "మందులు"],
                                           "mobility_kind": "local_delivery"}, actor="staff:test", status="ACTIVE")
    med = client.get("/api/taxonomy/resolve", params={"q": "medicine delivery to my home"}).json()
    assert med["key"] == "medicine_delivery" and "request_delivery" in med["actions"], "a staff-added node inherits"
    tree = client.get("/api/taxonomy/tree").json()["items"]
    assert any(n["key"] == "medicine_delivery" and n["parent"] == "delivery" for n in tree)
