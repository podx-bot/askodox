"""Universal ready-made catalogue: every template carries its OWN category
attributes (data-driven, one engine), required details gate publishing,
nothing is invented."""
import pytest
from fastapi.testclient import TestClient

from app.services import catalogue_templates, rate_limit
from app.services.session_tokens import issue_token

SELLER = "app-phone-91" + "8" * 10


@pytest.fixture()
def api():
    from server import app, container

    rate_limit.reset_for_tests()
    return TestClient(app), container


def _auth(container):
    return {"Authorization": f"Bearer {issue_token(SELLER, container.settings.session_token_secret)}"}


@pytest.mark.parametrize("key, expected", [
    ("meat_poultry", {"cut", "freshness", "delivery"}),
    ("pickles", {"spice", "ingredients", "packaging", "shelf_life"}),
    ("tiles_marble", {"material", "color", "thickness", "finish"}),
    ("fashion", {"color", "fabric", "fit"}),
    ("electronics", {"brand", "model", "storage", "warranty", "condition"}),
    ("services", {"scope", "duration", "availability", "service_area"}),
])
def test_each_category_has_its_own_attributes(api, key, expected):
    client, _ = api
    body = client.get(f"/api/catalog/templates/{key}").json()
    keys = {a["key"] for a in body["attributes"]}
    assert expected <= keys
    assert body["items"] > 0
    for a in body["attributes"]:
        assert a["label"]["te"] and a["label"]["hi"], "every label in en / te / hi"
        assert a["kind"] in {"text", "choice"}


def test_every_template_is_listed_and_no_value_is_prefilled():
    for summary in catalogue_templates.summaries():
        for a in catalogue_templates.attributes(summary["key"]):
            assert "value" not in a and "default" not in a, "the seller fills facts; nothing is pre-filled"


def test_required_detail_missing_keeps_a_draft_and_details_reach_the_listing(api):
    client, container = api
    headers = _auth(container)
    body = {"business_name": "Ravi Chicken Centre", "business_address": "Bus stand road, Vuyyuru", "items": [
        {"item_key": "chicken.curry_cut", "size": "1 kg", "price": 240,
         "attributes": {"freshness": "Fresh", "cut": "Curry cut", "skin": "Skinless", "secret": "x"}},
        {"item_key": "chicken.boneless", "size": "500 g", "price": 180, "attributes": {"cut": "Boneless"}},
        {"item_key": "chicken.whole", "size": "1 kg", "price": 200, "attributes": {"freshness": "Rotten"}},
    ]}
    result = client.post("/api/catalog/templates/meat_poultry/publish", json=body, headers=headers).json()
    assert [p["subject"] for p in result["published"]] == ["Chicken curry cut 1 kg"]
    assert {d["item_key"] for d in result["drafts"]} == {"chicken.boneless", "chicken.whole"}, \
        "required 'Fresh / frozen' missing (or not a listed option) -> draft, never published"
    mine = client.get("/api/products/mine", headers=headers).json()["items"]
    row = next(r for r in mine if r["id"] == result["published"][0]["product_id"])
    assert "Cut: Curry cut" in row["variant"] and "Fresh / frozen: Fresh" in row["variant"]
    assert "secret" not in row["variant"], "unknown keys are dropped"
