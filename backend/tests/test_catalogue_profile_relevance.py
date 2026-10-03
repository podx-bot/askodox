"""Seller catalogue templates, the one user profile, and category relevance."""
import base64

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit
from app.services.session_tokens import issue_token
from app.services.universal_external_result_service import category_conflict

JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 64 + b"\xff\xd9"


@pytest.fixture()
def api():
    from server import app, container

    rate_limit.reset_for_tests()
    return TestClient(app), container


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


SELLER = "app-phone-91" + "9" * 10


def test_ready_made_grocery_catalogue_exists_in_three_languages(api):
    client, _ = api
    listed = {t["key"]: t for t in client.get("/api/catalog/templates").json()["items"]}
    assert {"grocery", "fruits_vegetables", "fashion"} <= set(listed)
    grocery = client.get("/api/catalog/templates/grocery").json()
    assert grocery["items"] >= 40 and len(grocery["categories"]) >= 8
    first = grocery["categories"][0]["items"][0]
    assert first["name"]["te"] and first["name"]["hi"] and first["sizes"], "names in te/hi and sizes"
    assert "price" not in str(grocery).lower() or all("price" not in i for c in grocery["categories"] for i in c["items"])
    assert client.get("/api/catalog/templates/used-cars").status_code == 404, "no pretend template"


def test_seller_publishes_selected_items_with_own_prices_photo_and_shop(api):
    client, container = api
    headers = auth(container, SELLER)
    body = {"items": [{"item_key": "dals.toor", "size": "1 kg", "price": 160, "stock_status": "in_stock",
                       "photo_base64": base64.b64encode(JPEG).decode()},
                      {"item_key": "oils_ghee.ghee", "size": "500 ml"},
                      {"item_key": "nope.nothing", "price": 5}]}
    assert client.post("/api/catalog/templates/grocery/publish", json=body).status_code == 401
    missing_shop = client.post("/api/catalog/templates/grocery/publish", json=body, headers=headers)
    assert missing_shop.status_code == 422, "shop name and address are asked first"
    body.update(business_name="Sri Lakshmi Kirana", business_address="Main Road, Vuyyuru")
    result = client.post("/api/catalog/templates/grocery/publish", json=body, headers=headers).json()
    assert [p["subject"] for p in result["published"]] == ["Toor dal 1 kg"]
    assert result["drafts"][0]["item_key"] == "oils_ghee.ghee", "no price -> draft, never an invented price"
    assert result["skipped"][0]["item_key"] == "nope.nothing"
    product_id = result["published"][0]["product_id"]
    photo = client.get(f"/api/catalog/photos/{product_id}")
    assert photo.status_code == 200 and photo.content == JPEG
    mine = client.get("/api/products/mine", headers=headers).json()["items"]
    row = next(r for r in mine if r["id"] == product_id)
    assert row["price"] == 160 and row["seller_name"] == "Sri Lakshmi Kirana" and row["category_tag"] == "grocery"
    profile = client.get("/api/me/profile", headers=headers).json()
    assert profile["business_name"] == "Sri Lakshmi Kirana" and profile["business_category"] == "grocery"


def test_profile_is_the_users_own_stored_data(api):
    client, container = api
    user = "app-phone-91" + "7" * 10
    headers = auth(container, user)
    assert client.get("/api/me/profile").status_code == 401
    empty = client.get("/api/me/profile", headers=headers).json()
    assert empty["name"] is None and empty["mobile"] == "+917777777777", "mobile from the session, nothing invented"
    saved = client.put("/api/me/profile", headers=headers, json={
        "name": "Ravi", "address": "Vijayawada", "language": "te", "roles": ["buyer", "seller"],
        "business_name": "Ravi Textiles"}).json()
    assert saved["name"] == "Ravi" and saved["roles"] == ["buyer", "seller"] and saved["language"] == "te"
    assert client.put("/api/me/profile", headers=headers, json={"gstin": "BAD"}).status_code == 422
    assert client.put("/api/me/profile/photo", headers=headers,
                      json={"photo_base64": base64.b64encode(b"not an image").decode()}).status_code == 415
    with_photo = client.put("/api/me/profile/photo", headers=headers,
                            json={"photo_base64": base64.b64encode(JPEG).decode()}).json()
    assert with_photo["has_photo"] and with_photo["photo_url"] == "/api/me/profile/photo"
    assert client.get("/api/me/profile/photo", headers=headers).content == JPEG
    other = auth(container, "app-phone-91" + "6" * 10)
    assert client.get("/api/me/profile", headers=other).json()["name"] is None, "never another user's profile"
    export = client.get("/api/me/export", headers=headers).json()["data"]
    assert export["user_profiles"][0]["name"] == "Ravi" and "photo_jpeg" not in export["user_profiles"][0]
    assert client.delete("/api/me?confirm=DELETE", headers=headers).json()["deleted"] is True


@pytest.mark.parametrize("url,title,reason", [
    ("https://www.cars24.com/buy-used-cars-vijayawada/", "Used Cars in Vijayawada", "vehicle_page"),
    ("https://www.olx.in/vijayawada/q-grocery", "Grocery store items for sale - OLX", "classifieds_page"),
    ("https://example.in/kitchen-appliances", "Home & Kitchen Appliances store - fresh deals", "other_category"),
    ("https://www.magicbricks.com/shop-for-sale", "Grocery shop for sale", "property_page"),
])
def test_grocery_conversation_drops_other_category_pages(url, title, reason):
    assert category_conflict("grocery catalogue", "PRODUCT grocery", url, title, "") == reason


def test_matching_category_pages_are_kept():
    assert category_conflict("sona masoori rice 25 kg", "PRODUCT grocery",
                             "https://www.jiomart.com/p/rice", "Sona Masoori Rice 25 kg", "₹1,450") is None
    assert category_conflict("used car", "PRODUCT", "https://www.cars24.com/x", "Used Maruti Swift", "") is None
    assert category_conflict("second hand bike", "PRODUCT", "https://www.olx.in/item/bike", "Honda bike", "") is None
    assert category_conflict("mixer grinder", "PRODUCT", "https://example.in/p/mixer", "Mixer grinder 750W", "") is None


def test_seller_side_demand_runs_no_buyer_web_searches():
    from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService

    queries = []

    def web(query, count):
        queries.append(query)
        return [{"url": "https://www.cars24.com/used", "title": "Used cars grocery", "snippet": "used"}]

    service = UniversalMultiSourceResultService(catalog=None, web_search=web)
    service.collect({"side": "OFFER", "domain": "PRODUCT", "subject": "grocery items",
                     "constraints": {"aiCategory": "grocery"}})
    assert service.online_and_videos(category="PRODUCT", subject="grocery items", include_online=True,
                                     include_videos=False) == []
    assert not any(q.startswith(("used second hand", "open box")) for q in queries), queries


def test_result_rows_carry_the_sellers_own_photo_and_real_coordinates():
    from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService, _public_image

    assert _public_image("catalog-photo:77") == "/api/catalog/photos/77"
    assert _public_image("catalog-photo:../etc") is None and _public_image("http://x") is None
    service = UniversalMultiSourceResultService(catalog=None, web_search=None)
    rows = service._places_to_rows([{"name": "Sri Rama Kirana", "address": "Main Road, Vuyyuru", "latitude": 16.365,
                                     "longitude": 80.845, "place_id": "p1"}], 16.36, 80.84, 5, 5)
    assert rows[0]["latitude"] == 16.365 and rows[0]["longitude"] == 80.845
