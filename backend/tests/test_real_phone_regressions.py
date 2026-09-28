"""Real-phone regressions fixed at the universal pipeline (not per category).

* AC installation with no/foreign location  -> never Home Depot USA / a
  country-wide "in India" guess; nearby needs a real place.
* 43-inch TV -> a Manhattan/Karrot page or a YouTube review is never a
  purchasable option; videos appear only when the customer asks for them.
* Computer job ₹20-30k -> real job openings (salary only when stated), not
  "Matching is unavailable".
* Car Maruti -> Tata: the chosen brand drives the search; the old model goes.
* Admin trace: what location was searched + what happened after results.
Fixture rows below are test data, not production results.
"""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.api.routes.universal_deals import _subject_with_brand
from app.repositories.command_center_repository import CommandCenterRepository
from app.services.active_deal_context_resolver import ActiveDealContextResolver
from app.services.universal_external_result_service import (
    PAGE_INFO,
    PAGE_JOB,
    PAGE_STORE,
    classify_page,
    place_region_mismatch,
    region_mismatch,
)
from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService


class _Maps:
    enabled = True
    last_error = False

    def __init__(self, places):
        self.places = places
        self.queries = []

    def search_places(self, query, **kwargs):
        self.queries.append((query, kwargs))
        return self.places


class _Web:
    configured = True
    last_error = False

    def __init__(self, rows):
        self.rows = rows
        self.queries = []

    def __call__(self, query, limit):
        self.queries.append(query)
        return self.rows


HOME_DEPOT = {"place_id": "hd", "name": "The Home Depot", "address": "40 W 23rd St, New York, NY 10010, USA",
              "latitude": 40.74, "longitude": -73.99, "maps_url": "https://maps.google.com/?cid=hd"}
LOCAL_AC = {"place_id": "ac", "name": "Sai AC Services", "address": "Benz Circle, Vijayawada, Andhra Pradesh 520010",
            "latitude": 16.50, "longitude": 80.64, "rating": 4.5, "rating_count": 40,
            "maps_url": "https://maps.google.com/?cid=ac"}


def test_nearby_without_any_location_is_not_a_country_wide_guess():
    maps = _Maps([HOME_DEPOT])
    service = UniversalMultiSourceResultService(maps=maps)

    rows = service.collect({"subject": "AC installation", "domain": "SERVICES", "constraints": {}})

    assert maps.queries == [], "no Places call without a place"
    assert rows == []
    assert service.source_status()["nearby"] == "needs_location"


def test_foreign_places_are_dropped_and_local_ones_kept_with_distance():
    maps = _Maps([HOME_DEPOT, LOCAL_AC])
    service = UniversalMultiSourceResultService(maps=maps)

    rows = service.collect({"subject": "AC installation", "domain": "SERVICES", "latitude": 16.5,
                            "longitude": 80.6, "location_text": "Vijayawada", "constraints": {}})

    assert [row["title"] for row in rows] == ["Sai AC Services"]
    assert rows[0]["distance_km"] is not None
    assert "wrong_region" in service.filtered_counts()
    assert maps.queries[0][0] == "AC installation service near Vijayawada"
    assert place_region_mismatch("Shop 4, MG Road, Vijayawada 520010") is False
    assert place_region_mismatch("Toronto, ON, Canada") is True


def test_foreign_marketplace_and_non_shop_pages_are_not_options():
    karrot = "https://www.karrotmarket.com/us/buy-sell/manhattan-ny/43-inch-tv"
    assert region_mismatch(karrot, "43 inch TV", "Nice TV, India shipping") is True
    assert region_mismatch("https://example.com/new-york/tv", "43 inch TV", "₹20,000") is True
    assert region_mismatch("https://www.croma.com/tv", "43 inch TV", "₹24,990") is False
    assert classify_page("https://www.youtube.com/watch?v=1", "43 inch TV review") == "video"
    assert classify_page("https://blog.example/tv-thoughts", "My thoughts on 43 inch TVs", "") == PAGE_INFO
    assert classify_page("https://tvshop.example/tv", "43 inch TV", "Buy now ₹22,999") == PAGE_STORE
    assert classify_page("https://www.naukri.com/computer-operator-jobs", "Computer operator jobs") == PAGE_JOB


def test_job_seeker_gets_real_openings_with_salary_only_when_stated():
    web = _Web([
        {"title": "Computer Operator Jobs in Vijayawada", "url": "https://www.naukri.com/computer-operator-jobs-in-vijayawada",
         "snippet": "Computer operator vacancies. Salary ₹20,000 - ₹30,000 per month."},
        {"title": "Data entry computer job", "url": "https://www.apna.co/jobs/data-entry-computer",
         "snippet": "Apply for computer data entry roles near you."},
        {"title": "Best computer for gaming", "url": "https://shop.example/pc", "snippet": "Buy computer ₹45,000"},
        {"title": "Computer jobs Manhattan", "url": "https://www.indeed.com/q-computer-l-new-york-jobs.html",
         "snippet": "Computer jobs in New York, $25/hour"},
    ])
    service = UniversalMultiSourceResultService(web_search=web)

    rows = service.collect({"subject": "computer job", "domain": "WORK", "side": "OFFER",
                            "location_text": "Vijayawada", "constraints": {}})

    assert [row["segment"] for row in rows] == ["jobs", "jobs"]
    assert rows[0]["salary_text"].startswith("₹20,000")
    assert rows[1]["salary_text"] is None, "salary never invented"
    assert all(row["page_type"] == PAGE_JOB and row["price"] is None for row in rows)
    assert web.queries == ["computer jobs in Vijayawada"]
    assert service.source_status()["jobs"] == "ok"


def test_brand_change_drives_the_search_and_drops_the_old_model():
    constraints = {"brand": "Tata", "model": "Maruti 800"}
    assert _subject_with_brand("Maruti 800 car", constraints) == "Tata car"
    assert "model" not in constraints
    assert _subject_with_brand("car", {"brand": "any"}) == "car"
    assert _subject_with_brand("Tata Nexon", {"brand": "Tata"}) == "Tata Nexon"

    merged = ActiveDealContextResolver.merge_fields(
        {"constraints": {"brand": "Maruti", "model": "Maruti 800", "budget_max": 1000000}},
        {"constraints": {"brand": "Tata"}},
    )
    assert merged["constraints"] == {"brand": "Tata", "budget_max": 1000000}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-rp-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "rp.db")), raising=False)
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}


class _Brave(_Web):
    def videos(self, query, limit):
        self.queries.append("VIDEOS:" + query)
        return [{"title": "43 inch TV review", "url": "https://www.youtube.com/watch?v=tv", "creator": "Tech"}]


def _trace(client, admin, key):
    rows = client.get("/admin/cc/traces?limit=200", headers=admin).json()["items"]
    trace_id = next(row["id"] for row in rows if row.get("trace_key") == key)
    return client.get(f"/admin/cc/traces/{trace_id}", headers=admin).json()


def _body(raw, **extra):
    return {"user_id": "", "raw_text": raw, "intent": "buy", "subject": "43 inch TV", "category": "product",
            "price": 30000, "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6},
            "dynamic_fields": {}, **extra}


def test_videos_only_when_asked_and_admin_trace_records_location_and_actions(api, monkeypatch):
    client, container, admin = api
    monkeypatch.setattr(container, "brave_web_search_provider", _Brave([
        {"title": "43 inch TV at Croma", "url": "https://www.croma.com/tv/p/1", "snippet": "43 inch TV ₹24,990"},
    ]))

    plain = client.post("/deals/discover", json=_body("43 inch TV 20k to 30k show me")).json()
    assert not any(row["match_source"] == "video" for row in plain["matches"])
    assert plain["source_status"]["videos"] == "not_applicable"

    asked = client.post("/deals/discover", json=_body("43 inch TV reviews and videos")).json()
    assert any(row["match_source"] == "video" for row in asked["matches"])

    key = plain["trace_key"]
    r = client.post("/deals/trace-event", json={"trace_key": key, "event": "result_selected",
                                                "detail": {"title": "43 inch TV at Croma", "phone": "999"}})
    assert r.json() == {"recorded": True}
    client.post("/deals/trace-event", json={"trace_key": key, "event": "action_result",
                                            "detail": {"action": "send_request", "ok": False, "reason": "sign_in"}})
    assert client.post("/deals/trace-event", json={"trace_key": "browse:nope", "event": "result_selected"}).json() == {
        "recorded": False}
    assert client.post("/deals/trace-event", json={"trace_key": key, "event": "drop_tables"}).status_code == 422

    trace = _trace(client, admin, key)
    text = str(trace)
    assert "location_searched" in text and "Vijayawada" in text
    assert "result_selected" in text and "action_result" in text
    assert "999" not in text, "sensitive keys are never stored"


def test_discover_without_location_reports_the_location_failure(api, monkeypatch):
    client, container, admin = api
    monkeypatch.setattr(container, "brave_web_search_provider", None)
    body = _body("AC installation near me", subject="AC installation", category="service", intent="needservice",
                 location=None)
    data = client.post("/deals/discover", json=body).json()
    assert data["source_status"]["nearby"] in {"needs_location", "unavailable"}
    trace = _trace(client, admin, data["trace_key"])
    assert "location_searched" in str(trace)


class _Resp:
    def __init__(self, data):
        self.data = data

    def raise_for_status(self):
        return None

    def json(self):
        return self.data


class _GeoClient:
    """Geocoding API denied on the key (as on the real phone); Places works."""

    def get(self, url, **kwargs):
        return _Resp({"status": "REQUEST_DENIED", "results": []})

    def post(self, url, **kwargs):
        assert url.endswith("searchNearby")
        return _Resp({"places": [{"displayName": {"text": "Vuyyuru"}, "addressComponents": [
            {"longText": "Andhra Pradesh", "types": ["administrative_area_level_1"]}]}]})


def test_current_location_is_named_even_when_geocoding_is_denied():
    from app.services import external_call_budget
    from app.services.google_maps_service import GoogleMapsService

    external_call_budget.reset_for_tests()
    maps = GoogleMapsService(api_key="test-key", client=_GeoClient())
    place = maps.reverse_geocode(16.365, 80.844)
    assert place["city"] == "Vuyyuru"
    assert place["label"] == "Vuyyuru, Andhra Pradesh"
