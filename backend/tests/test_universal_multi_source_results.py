"""Multi-source discovery: registered, external, used, individual, surplus, deals."""
import uuid

from fastapi.testclient import TestClient

from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services.google_maps_service import GoogleMapsService
from app.services.product_match_ranking_service import ProductMatchRankingService
from app.services.session_tokens import issue_token
from app.services.universal_multi_source_result_service import (
    UniversalMultiSourceResultService,
    listing_segment,
    wanted_condition,
)


class _Maps:
    enabled = True

    def __init__(self, places):
        self.places = places
        self.queries = []

    def search_places(self, query, **kwargs):
        self.queries.append((query, kwargs))
        return self.places


class _Web:
    configured = True

    def __init__(self, rows_by_word):
        self.rows_by_word = rows_by_word
        self.queries = []

    def __call__(self, query, limit):
        self.queries.append(query)
        for word, rows in self.rows_by_word.items():
            if query.startswith(word):
                return rows
        return []


class _Tiers:
    def __init__(self, tiers):
        self.tiers = tiers

    def get(self, seller):
        return {"tier": self.tiers.get(seller, "business")}


def _catalog(tmp_path):
    repo = ProductCatalogRepository(str(tmp_path / "catalog.db"))
    repo.upsert_product("app-phone-911", "43 inch TV", brand="Sony", price=28000, stock_status="in_stock", location_label="Vijayawada")
    repo.upsert_product("app-phone-912", "43 inch TV", variant="used, 2 years old", price=14000)
    repo.upsert_product("app-phone-913", "43 inch TV", variant="open box display piece", price=22000)
    repo.upsert_product("app-phone-914", "43 inch TV", brand="LG", price=26500)
    repo.upsert_product("app-phone-915", "43 inch TV", brand="Onida", price=90000)
    return repo


def _demand(**extra):
    return {"subject": "43 inch TV", "domain": "PRODUCT", "price": 30000, "latitude": 16.5, "longitude": 80.6,
            "location_text": "Vijayawada", "constraints": {}, **extra}


def test_registered_seller_does_not_stop_discovery_and_segments_are_labelled(tmp_path):
    maps = _Maps([
        {"place_id": "p1", "name": "Sri Electronics", "address": "MG Road", "latitude": 16.51, "longitude": 80.61,
         "rating": 4.4, "rating_count": 120, "maps_url": "https://maps.google.com/?cid=1", "open_now": True},
        {"place_id": "p2", "name": "Far Electronics", "latitude": 16.62, "longitude": 80.6, "maps_url": "https://maps.google.com/?cid=2"},
        {"place_id": "p3", "name": "Other City TVs", "latitude": 17.4, "longitude": 78.5, "maps_url": "https://maps.google.com/?cid=3"},
    ])
    web = _Web({
        "used": [{"title": "Used 43 inch TV for sale Vijayawada", "url": "https://olx.example/tv", "snippet": "second hand 43 inch TV"},
                 {"title": "Cooking tips", "url": "https://food.example", "snippet": "used oil"}],
        "open box": [{"title": "Open box 43 inch TV clearance", "url": "https://outlet.example/tv", "snippet": "surplus TV stock"}],
        "43 inch TV offers": [{"title": "43 inch TV festival offers", "url": "https://shop.example/tv", "snippet": "10% off TV deal"}],
    })
    service = UniversalMultiSourceResultService(
        catalog=_catalog(tmp_path), ranking=ProductMatchRankingService(),
        seller_profiles=_Tiers({"app-phone-914": "casual"}), maps=maps, web_search=web,
    )

    rows = service.collect(_demand())
    by_segment = {}
    for row in rows:
        by_segment.setdefault(row["segment"], []).append(row)

    assert {"registered", "individual", "used", "surplus", "deals", "nearby_external", "wider_local"} <= set(by_segment)
    assert all(row["provider_id"] == "" for row in rows if row["source"] == "local"), "no seller phone before acceptance"
    assert not any("Onida" in row["title"] for row in rows), "far over budget is not relevant"
    assert [row["title"] for row in by_segment["nearby_external"]] == ["Sri Electronics"]
    assert [row["title"] for row in by_segment["wider_local"]] == ["Far Electronics"]
    assert "Other City TVs" not in [row["title"] for row in rows]
    assert not any("Cooking" in row["title"] for row in rows), "irrelevant web rows never fill a section"
    assert by_segment["used"][0]["source"] in {"local", "online"}
    assert maps.queries[0][0] == "43 inch TV shop near Vijayawada"


def test_condition_intent_filters_and_ranks(tmp_path):
    service = UniversalMultiSourceResultService(catalog=_catalog(tmp_path), ranking=ProductMatchRankingService())
    new_only = service.collect(_demand(subject="43 inch TV", constraints={"note": "brand new"}))
    assert all(row["segment"] not in {"used", "surplus"} for row in new_only)
    assert wanted_condition("second hand tv") == "used"
    assert listing_segment({"subject": "TV", "variant": "refurbished"}) == "used"
    assert listing_segment({"subject": "TV"}, "casual") == "individual"


def test_disabled_sources_degrade_to_registered_only(tmp_path):
    service = UniversalMultiSourceResultService(
        catalog=_catalog(tmp_path), ranking=ProductMatchRankingService(),
        maps=GoogleMapsService(api_key=""), web_search=None,
    )
    rows = service.collect(_demand())
    assert rows and all(row["source"] == "local" for row in rows)
    assert service.collect({"subject": ""}) == []


def test_places_search_parses_and_skips_closed(monkeypatch):
    class _Resp:
        def raise_for_status(self):
            return None

        def json(self):
            return {"places": [
                {"id": "a", "displayName": {"text": "Open Shop"}, "location": {"latitude": 1, "longitude": 2},
                 "googleMapsUri": "https://maps/a", "rating": 4.1, "userRatingCount": 9},
                {"id": "b", "displayName": {"text": "Closed Shop"}, "businessStatus": "CLOSED_PERMANENTLY"},
            ]}

    class _Client:
        def post(self, url, json, headers, timeout):
            assert headers["X-Goog-Api-Key"] == "k"
            assert json["locationBias"]["circle"]["center"] == {"latitude": 16.5, "longitude": 80.6}
            return _Resp()

    maps = GoogleMapsService(api_key="k", client=_Client())
    places = maps.search_places("tv shop", latitude=16.5, longitude=80.6)
    assert [p["name"] for p in places] == ["Open Shop"]
    assert GoogleMapsService(api_key="").search_places("tv") == []


def test_matches_endpoint_returns_registered_listing_with_online_and_videos(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "multi.db"))
    from server import app, container

    subject = "Multi TV " + uuid.uuid4().hex[:6]
    container.product_catalog_repository.upsert_product("app-phone-919000000001", subject, price=25000)
    owner = "app-multi-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create({
        "user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": subject, "price": 30000, "source": "app",
    })
    headers = {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}
    body = TestClient(app).get(f"/deals/{demand_id}/matches", headers=headers).json()

    sources = [row["match_source"] for row in body["matches"]]
    assert "registered" in sources
    assert body["source_status"]["askodox"] == "ok"
    assert body["local_match_count"] >= 1
    assert body["waiting_for_interest"] is True, "discovery rows are not consent matches"
    assert "919000000001" not in str(body)


def test_brave_video_search_returns_actual_video_metadata():
    from app.services.brave_web_search_provider import BraveWebSearchProvider

    class _Resp:
        def raise_for_status(self):
            return None

        def json(self):
            return {"results": [
                {"title": "Battery TV review", "url": "https://www.youtube.com/watch?v=a1",
                 "description": "Portable TV test", "thumbnail": {"src": "https://imgs.search.brave.com/t.jpg"},
                 "video": {"creator": "Gadgets Telugu", "duration": "06:40"},
                 "meta_url": {"hostname": "www.youtube.com"}},
                {"title": "", "url": "https://x"},
            ]}

    class _Client:
        def get(self, url, headers, params):
            assert url == BraveWebSearchProvider.VIDEO_URL
            assert params["q"] == "battery tv review"
            return _Resp()

    videos = BraveWebSearchProvider("key", client=_Client()).videos("battery tv review", 5)
    assert videos == [{
        "title": "Battery TV review", "url": "https://www.youtube.com/watch?v=a1", "snippet": "Portable TV test",
        "thumbnail": "https://imgs.search.brave.com/t.jpg", "creator": "Gadgets Telugu", "publisher": None,
        "duration": "06:40", "host": "www.youtube.com",
    }]
    assert BraveWebSearchProvider("").videos("tv", 5) == []
