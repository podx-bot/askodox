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
        assert a["kind"] in {"text", "choice", "number"}


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


def test_inheritance_conditions_and_ranges():
    from app.services import catalogue_templates as ct

    keys = [a["key"] for a in ct.attributes("vehicles_parts")]
    assert {"mrp", "moq", "negotiable", "returns"} <= set(keys), "product_base attributes are inherited"
    kept, missing = ct.clean_attributes("vehicles_parts", {
        "brand": "Honda", "condition": "Used", "km_driven": "12,000", "year": "1800",
        "delivery": ["Pickup", "Courier", "Teleport"], "wholesale": "No", "moq": "5"})
    assert kept["km_driven"] == "12000" and "year" not in kept, "out-of-range number dropped"
    assert kept["delivery"] == "Pickup, Courier", "multi-select keeps only listed options"
    assert "moq" not in kept, "a dependent attribute is kept only when its condition holds"
    assert missing == []
    assert ct.clean_attributes("vehicles_parts", {"condition": "New", "km_driven": "50"}) == (
        {"condition": "New"}, ["brand"])
    assert ct.template("product_base") is None, "abstract parents are never offered to sellers"


def test_admin_edits_replace_add_and_disable_templates(api):
    from app.api.routes.platform import platform
    from app.services import catalogue_templates as ct

    client, container = api
    store = platform(container).resources
    rows = {r["data"]["key"]: r for r in store.repo.list("catalog_templates")}
    assert {"grocery", "product_base", "vehicles_parts"} <= set(rows), "seeded once into the Command Center"
    store.create("catalog_templates", {
        "key": "bakery", "label_en": "Bakery", "parent": "product_base", "category_tag": "bakery",
        "attributes": {"eggless": {"label": {"en": "Eggless", "te": "గుడ్డు లేని", "hi": "बिना अंडे"},
                                   "kind": "choice", "options": ["Yes", "No"], "required": True, "filterable": True}},
        "categories": {"cakes": {"name": {"en": "Cakes"},
                                 "items": [{"key": "cakes.plum", "name": {"en": "Plum cake", "te": "ప్లమ్ కేక్",
                                                                          "hi": "प्लम केक"},
                                            "unit": "piece", "sizes": ["500 g"]}]}},
    }, actor="test", status="ACTIVE")
    body = client.get("/api/catalog/templates/bakery").json()
    assert {a["key"] for a in body["attributes"]} >= {"eggless", "mrp"}, "new business type, no app change"
    assert "bakery" in {t["key"] for t in client.get("/api/catalog/templates").json()["items"]}
    assert ct.template("bakery")["items"] == 1


def test_filters_come_from_real_listings_and_search_uses_them(api):
    client, container = api
    headers = _auth(container)
    body = {"business_name": "Ravi Pickles", "business_address": "Main road, Vuyyuru", "items": [
        {"item_key": "veg_pickles.avakaya", "size": "500 g", "price": 220,
         "attributes": {"ingredients": "Mango, chilli, mustard", "spice": "Hot", "delivery": ["Pickup", "Courier"]}},
        {"item_key": "veg_pickles.gongura", "size": "500 g", "price": 200,
         "attributes": {"ingredients": "Gongura, chilli", "spice": "Medium"}},
    ]}
    response = client.post("/api/catalog/templates/pickles/publish", json=body, headers=headers)
    assert response.status_code == 200, response.text
    published = response.json()["published"]
    assert len(published) == 2
    filters = client.get("/api/catalog/filters/pickles").json()
    spice = next(f for f in filters["filters"] if f["key"] == "spice")
    assert {v["value"] for v in spice["values"]} >= {"Hot", "Medium"}
    assert not any(v["value"] == "Mild" for v in spice["values"]), "only values real listings carry"
    assert filters["price"]["min"] <= 200 and filters["price"]["count"] >= 2
    hot = client.get("/api/products/search", params={"q": "pickle", "attr": ["spice:Hot"]}).json()["items"]
    assert hot and all("Mango" in i["title"] for i in hot)
    mine = client.get("/api/products/mine", headers=headers).json()["items"]
    row = next(r for r in mine if r["id"] == published[0]["product_id"])
    assert row["attributes"]["delivery"] == ["Courier", "Pickup"]


def test_free_text_attributes_never_carry_contact_details():
    from app.services import catalogue_templates as ct

    for leak in ("call 98765 43210", "+91 9876543210", "see https://x.example", "www.shop.in", "mail a@b.com",
                 "wa.me/919876543210"):
        kept, _ = ct.clean_attributes("services", {"scope": leak})
        assert "scope" not in kept, leak
    kept, _ = ct.clean_attributes("services", {"scope": "Pipe fitting, tap repair, 2 hours"})
    assert kept["scope"] == "Pipe fitting, tap repair, 2 hours"
