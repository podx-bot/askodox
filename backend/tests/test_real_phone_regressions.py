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
                                                "detail": {"title": "43 inch TV at Croma", "phone": "+91 98765 43210"}})
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
    # (A distinctive value: a bare "999" also occurs in timestamps' microseconds.)
    assert "98765 43210" not in text, "sensitive keys are never stored"


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


def test_job_cards_are_short_and_never_invent_fields():
    from app.services.universal_multi_source_result_service import job_card_title

    assert job_card_title("369 Latest Delivery Vacancies in Hyderabad 2026 - Naukri.com") == ("Delivery jobs", "Hyderabad")
    assert job_card_title("Computer Operator Jobs in Vijayawada | Indeed") == ("Computer Operator jobs", "Vijayawada")
    assert job_card_title("Data entry work from home") == ("Data entry work from home jobs", None)


def test_trace_records_the_language_the_customer_used():
    from app.api.routes.universal_deals import _query_language

    assert _query_language("నాకు 43-inch TV కావాలి") == "te+en"
    assert _query_language("मुझे फ्रिज चाहिए") == "hi"
    assert _query_language("AC installation near me") == "en"


class _StatusResp:
    def __init__(self, code, data):
        self.status_code, self._data = code, data

    def json(self):
        return self._data


class _MixedGoogle:
    """Geocoding + Routes not enabled on the key; Places enabled."""

    def get(self, url, **kwargs):
        return _StatusResp(200, {"status": "REQUEST_DENIED",
                                 "error_message": "This API project is not authorized to use this API."})

    def post(self, url, **kwargs):
        if "routes.googleapis.com" in url:
            return _StatusResp(403, {"error": {"message": "Routes API has not been used in project 123 before"}})
        return _StatusResp(200, {"places": []})


def test_admin_maps_check_names_each_api_and_never_the_key():
    from app.services.google_maps_service import GoogleMapsService

    status = GoogleMapsService(api_key="secret-key-value", client=_MixedGoogle()).api_status()
    assert status["places_text_search"] == "OK" and status["places_nearby"] == "OK"
    assert status["geocoding"].startswith("FAILED") and "not authorized" in status["geocoding"]
    assert status["routes"].startswith("FAILED (HTTP 403)")
    assert "secret-key-value" not in str(status)


def test_brand_vocabulary_is_learned_from_real_listings():
    import uuid as _uuid

    from server import app, container

    brand = "Zz" + _uuid.uuid4().hex[:6]
    container.product_catalog_repository.upsert_product("app-phone-91brand", "43 inch TV", brand=brand, price=25000)
    assert brand in TestClient(app).get("/api/products/brands").json()["brands"]


# --- Mixed result-group requests (real phone: "Vijayawada chicken biryani
# videos, restaurants, online links and offers చూపించు" returned one group).
# Production evidence: with the group words left in the subject every
# provider searched that literal phrase -> 2 rows; with the clean subject the
# same request returned registered + deals + online + 5 YouTube videos.
def test_mixed_request_searches_the_thing_and_returns_every_requested_group(api, monkeypatch):
    from app.api.routes.universal_deals import requested_result_groups

    client, container, _ = api

    class _BiryaniVideos(_Brave):
        def videos(self, query, limit):
            self.queries.append("VIDEOS:" + query)
            return [{"title": "Chicken biryani review Vijayawada", "creator": "Food Vlogs",
                     "url": "https://www.youtube.com/watch?v=abc123def45"}]

    web = _BiryaniVideos([
        {"title": "Biryani house Vijayawada | order online", "url": "https://order.example/biryani-vja",
         "snippet": "chicken biryani delivery Vijayawada"},
        {"title": "Biryani deals and offers Vijayawada", "url": "https://deals.example/biryani",
         "snippet": "chicken biryani offer 20% off Vijayawada"},
    ])
    monkeypatch.setattr(container, "brave_web_search_provider", web)
    for raw in ("Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు",
                "చికెన్ బిర్యానీ వీడియోలు, హోటల్స్, ఆన్‌లైన్ లింకులు, ఆఫర్లు చూపించు"):
        web.queries.clear()
        body = _body(raw, subject="chicken biryani videos, restaurants, online links and offers",
                     category="food", price=None)
        data = client.post("/deals/discover", json=body).json()
        assert set(data["requested_groups"]) >= {"videos", "online", "deals"}, raw
        assert all("online links" not in q and "restaurants" not in q and "," not in q for q in web.queries), web.queries
        assert any(q.startswith("VIDEOS:") and "chicken biryani" in q for q in web.queries)
        counts = data["group_counts"]
        assert counts["videos"] >= 1 and counts["online"] + counts["deals"] >= 1, counts
        assert data["source_status"]["videos"] != "not_applicable"
    assert requested_result_groups("offer letter format") == []
    assert requested_result_groups("Samsung TV deals") == ["deals"]


def test_offers_on_a_service_request_still_search_deals(api, monkeypatch):
    client, container, _ = api
    monkeypatch.setattr(container, "brave_web_search_provider", _Brave([
        {"title": "AC repair offer Vijayawada", "url": "https://svc.example/ac", "snippet": "AC repair ₹299 offer"},
    ]))
    plain = client.post("/deals/discover", json=_body("AC repair", subject="AC repair", category="services",
                                                      intent="needService", price=None)).json()
    assert plain["source_status"]["used_deals"] == "not_applicable"
    offers = client.post("/deals/discover", json=_body("AC repair offers and online links", subject="AC repair",
                                                       category="services", intent="needService",
                                                       price=None)).json()
    assert offers["source_status"]["used_deals"] != "not_applicable", "offers were asked for"
    assert offers["requested_groups"] == ["online", "deals"]


def test_signed_in_phone_payload_keeps_videos_from_the_customers_own_words(api):
    """APK 1285 on a real phone: the app sends a REWRITTEN raw_text ("i want to
    buy chicken biryani in Vijayawada") to POST /deals; the customer's words
    ("videos, restaurants, online links and offers") are only in trace.query.
    Videos were never searched -> no Videos group on the phone."""
    from tests.test_flow_traces import auth, phone

    client, container, _ = api

    class _Videos(_Brave):
        def videos(self, query, limit):
            self.queries.append("VIDEOS:" + query)
            return [{"title": "Chicken biryani review Vijayawada", "creator": "Food Vlogs",
                     "url": "https://www.youtube.com/watch?v=abc123def45"}]

    web = _Videos([{"title": "Biryani house Vijayawada | order online", "url": "https://order.example/b",
                    "snippet": "chicken biryani delivery Vijayawada"}])
    container.brave_web_search_provider = web
    for said, groups in (
        ("Vijayawada chicken biryani videos, restaurants, online links and offers చూపించు",
         {"videos", "online", "deals", "local"}),
        ("Vijayawada chicken biryani YouTube videos చూపించు", set()),
    ):
        web.queries.clear()
        user = phone()
        body = _body("i want to buy chicken biryani in Vijayawada", subject="chicken biryani", category="food",
                     price=None, user_id=user, dynamic_fields={"productKind": "chicken"},
                     trace={"query": said, "language": "te", "intent": "search_videos"})
        created = client.post("/deals", headers=auth(container, user), json=body)
        assert created.status_code == 200, created.text
        data = client.get(f"/deals/{created.json()['id']}/matches", headers=auth(container, user)).json()
        assert data["source_status"]["videos"] != "not_applicable", said
        assert any(q == "VIDEOS:chicken biryani review" for q in web.queries), web.queries
        assert data["group_counts"]["videos"] >= 1, data["group_counts"]
        assert set(data["requested_groups"]) >= groups
        # The guest path (same payload) behaves the same.
        assert client.post("/deals/discover", json=body).json()["group_counts"]["videos"] >= 1


def test_public_maps_health_names_each_api_masks_project_and_is_cached(monkeypatch):
    from app.api.routes import health
    from app.services import rate_limit
    from app.services.google_maps_service import GoogleMapsService
    from server import app, container

    rate_limit.reset_for_tests()
    health._MAPS_HEALTH.clear()
    maps = GoogleMapsService(api_key="secret-key-value", client=_MixedGoogle())
    monkeypatch.setattr(container, "google_maps_service", maps, raising=False)
    calls = []
    real = maps.api_status
    monkeypatch.setattr(maps, "api_status", lambda: calls.append(1) or real())
    client = TestClient(app)
    body = client.get("/health/maps").json()
    assert body["configured"] and body["all_ok"] is False
    assert body["apis"]["places_text_search"] == "OK" and body["apis"]["routes"].startswith("FAILED (HTTP 403)")
    assert "secret-key-value" not in str(body)
    client.get("/health/maps")
    assert len(calls) == 1, "live-checked at most once per 15 minutes"
    health._MAPS_HEALTH.clear()


def test_geocoding_refusal_is_not_cached():
    from app.services import external_call_budget as b

    b.reset_for_tests()
    answers = [{"status": "REQUEST_DENIED"}, {"status": "OK", "results": []}]
    ok = lambda v: v.get("status") == "OK"
    assert b.cached_call("g", (1,), lambda: answers.pop(0), cache_if=ok)["status"] == "REQUEST_DENIED"
    assert b.cached_call("g", (1,), lambda: answers.pop(0), cache_if=ok)["status"] == "OK"
    assert b.cached_call("g", (1,), lambda: {"status": "NEW"}, cache_if=ok)["status"] == "OK"
