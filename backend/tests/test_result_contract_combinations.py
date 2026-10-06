"""The ONE canonical result contract: 20 combination regressions.

Every relevant result type ADDS a section -- a new source never replaces an
unrelated one, a failing source only empties its own section, explicit
constraints survive turns unchanged, and the answer never claims results
that are not there. End-to-end cases go through ``server.py`` (the app the
phone talks to) with fake web / maps sources; the rest exercise
``result_orchestrator.build`` with the row shapes the pipeline produces.
"""
import uuid

import pytest
from fastapi.testclient import TestClient

from app.services import result_orchestrator as ro
from app.services.session_tokens import issue_token


# ----------------------------------------------------------------- fakes --
class _Brave:
    configured = True

    def __init__(self, rows=None, videos=None, error=None, video_error=None):
        self.rows, self.video_rows = rows or [], videos or []
        self.error, self.video_error = error, video_error
        self.last_error = None

    def __call__(self, query, limit):
        if self.error:
            raise self.error
        return self.rows

    def videos(self, query, limit):
        if self.video_error:
            raise self.video_error
        return self.video_rows


class _Maps:
    enabled = True
    last_error = None

    def __init__(self, places):
        self.places = places

    def search_places(self, query, **kwargs):
        return self.places


SHOES_ONLINE = [{"title": "Walking shoes for men size 9", "url": "https://shop.example/walking-shoes",
                 "snippet": "Walking shoes Rs. 1,899 free delivery", "host": "shop.example"}]
SHOES_VIDEOS = [{"title": "Best walking shoes review", "url": "https://www.youtube.com/watch?v=walk1",
                 "creator": "Shoe Telugu", "duration": "09:12"}]
SHOES_PLACES = [{"place_id": "p1", "name": "Bata Shoe Store", "address": "MG Road", "latitude": 16.51,
                 "longitude": 80.61, "maps_url": "https://maps.google.com/?cid=1", "rating": 4.2},
                {"place_id": "p2", "name": "Metro Shoes", "address": "Bandar Road", "latitude": 16.53,
                 "longitude": 80.65, "maps_url": "https://maps.google.com/?cid=2", "rating": 4.0}]


@pytest.fixture()
def app_env(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "contract.db"))
    from server import app, container

    monkeypatch.setattr(container, "brave_web_search_provider", None)
    monkeypatch.setattr(container, "google_maps_service", _Maps([]))
    return app, container, TestClient(app)


def _body(text="walking shoes", *, groups_text=None, size=None, dynamic=None, located=True):
    return {
        "user_id": "guest", "raw_text": groups_text or text, "subject": text, "intent": "buy", "category": "PRODUCT",
        "size": size, "dynamic_fields": dict(dynamic or {}),
        "location": {"latitude": 16.5, "longitude": 80.6, "label": "Vijayawada", "radius_km": 5} if located else None,
        "trace": {"query": groups_text or text, "language": "en"},
    }


def _discover(client, **kw):
    response = client.post("/deals/discover", json=_body(**kw))
    assert response.status_code == 200, response.text
    return response.json()


def _kinds(body):
    return [s["kind"] for s in body["sections"] if s["count"]]


def _ids(body):
    return {row["id"]: row for row in body["matches"]}


def _assert_contract(body):
    """Every row is in exactly one section; every section id is a real row."""
    assert body["result_contract_version"] == ro.CONTRACT_VERSION
    rows = _ids(body)
    listed = [i for s in body["sections"] for i in s["item_ids"]]
    assert len(listed) == len(set(listed)), "an item appears in two sections"
    assert set(listed) <= set(rows)
    assert set(rows) <= set(listed), "a returned row is in no section"
    assert body["answer"]["may_claim_results"] == bool(rows)


# ------------------------------------------------------- row factories --
def _local(i, km=1.0):
    return {"id": f"reg-{i}", "match_source": "registered", "segment": "registered", "title": f"Shop {i}",
            "distance_km": km}


def _nearby(i, km=2.0):
    return {"id": f"near-{i}", "match_source": "external", "segment": "nearby_external", "title": f"Store {i}",
            "distance_km": km}


def _online(i):
    return {"id": f"web-{i}", "match_source": "online", "segment": "online", "title": f"Page {i}",
            "destination_url": f"https://shop.example/{i}"}


def _affiliate(i):
    return {"id": f"aff-{i}", "match_source": "online", "affiliate": True, "routing": "affiliate",
            "title": f"Affiliate {i}", "destination_url": f"https://amzn.example/{i}"}


def _video(i, short=False):
    return {"id": f"vid-{i}", "match_source": "video", "segment": "videos", "title": f"Video {i}",
            "video_format": "short" if short else "video", "destination_url": f"https://youtu.be/v{i}"}


def _deal(i):
    return {"id": f"deal-{i}", "match_source": "online", "segment": "deals", "title": f"Deal {i}"}


DEMAND = {"subject": "walking shoes", "domain": "PRODUCT", "constraints": {}}


# ==================================================== the 20 combinations ==
def test_01_local_only(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    body = _discover(client)
    _assert_contract(body)
    assert _kinds(body) == ["local"]
    assert body["source_status"]["online"] == "unavailable"


def test_02_online_only(app_env):
    app, container, client = app_env
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    body = _discover(client, located=False)
    _assert_contract(body)
    assert "online" in _kinds(body) and "local" not in _kinds(body)


def test_03_products_with_links_keep_their_links():
    out = ro.build([_online(1), _online(2)], demand=DEMAND)
    assert [s["kind"] for s in out["sections"]] == ["online"]
    assert out["sections"][0]["item_ids"] == ["web-1", "web-2"]


def test_04_products_plus_videos_are_two_sections():
    base = ro.build([_online(1)], demand=DEMAND)
    both = ro.build([_online(1), _video(1)], demand=DEMAND)
    assert {s["kind"] for s in base["sections"]} < {s["kind"] for s in both["sections"]}
    assert {s["kind"] for s in both["sections"]} == {"online", "videos"}


def test_05_local_plus_online(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    body = _discover(client)
    _assert_contract(body)
    assert {"local", "online"} <= set(_kinds(body))


def test_06_local_plus_videos(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(videos=SHOES_VIDEOS)
    body = _discover(client, groups_text="walking shoes shops near me and review videos")
    _assert_contract(body)
    assert {"local", "videos"} <= set(_kinds(body))


def test_07_local_plus_online_plus_videos(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE, videos=SHOES_VIDEOS)
    body = _discover(client, groups_text="walking shoes shops, online links and review videos")
    _assert_contract(body)
    assert {"local", "online", "videos"} <= set(_kinds(body))
    # Adding videos removed nothing: the same local + online rows are there.
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    without = _discover(client, groups_text="walking shoes shops and online links")
    local_online = {i for s in without["sections"] if s["kind"] in ("local", "online") for i in s["item_ids"]}
    assert local_online <= set(_ids(body))


def test_08_affiliate_and_organic_both_kept():
    out = ro.build([_affiliate(1), _online(1)], demand=DEMAND)
    kinds = {s["kind"]: s["item_ids"] for s in out["sections"]}
    assert kinds == {"online": ["web-1"], "affiliate": ["aff-1"]}


def test_08b_affiliate_registry_rows_do_not_stop_the_organic_search(app_env, monkeypatch):
    """Before: an affiliate registry row counted as 'online already present'
    and the organic web search was skipped (has_online)."""
    app, container, client = app_env
    from app.api.routes import universal_deals as ud

    monkeypatch.setattr(ud.UniversalExternalResultService, "resolve", staticmethod(
        lambda **kw: [{"id": "aff-reg-1", "match_source": "online", "affiliate": True, "routing": "affiliate",
                       "title": "Walking shoes (affiliate)", "destination_url": "https://amzn.example/w"}]))

    class _Providers:
        def active_for_category(self, key):
            return [{"provider_id": "amz", "name": "amz"}]

    monkeypatch.setattr(container, "affiliate_provider_config", _Providers(), raising=False)
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    body = _discover(client, located=False)
    _assert_contract(body)
    assert {"online", "affiliate"} <= set(_kinds(body)), _kinds(body)


def test_09_deals_plus_products():
    out = ro.build([_online(1), _deal(1)], demand=DEMAND)
    assert {s["kind"] for s in out["sections"]} == {"online", "deals"}


def test_10_question_then_answer_then_cards(app_env):
    """A required advisor question first; the answer (budget) brings cards."""
    app, container, client = app_env
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    first = _discover(client, text="walking shoes", located=False)
    assert first["advisor"]["questions"], "footwear asks a decision question first"
    assert first["conversation_state"]["advisor"]["open_required"]
    second = _discover(client, text="walking shoes", located=False,
                       dynamic={"budget_max": 2000, "advisor_asked": ["budget"]})
    assert "budget" not in (second["conversation_state"]["advisor"]["open_required"] or [])
    assert second["answer"]["may_claim_results"] is True and "online" in _kinds(second)


def test_11_any_settles_only_that_field_and_the_next_required_question_follows(app_env):
    app, container, client = app_env
    body = _discover(client, located=False, dynamic={"no_preference": ["size"], "advisor_asked": ["size"]})
    states = body["advisor"].get("field_states") or {}
    assert states.get("size") == "no_preference"
    assert states.get("budget") != "no_preference", "'Any' for size never settles budget"
    assert "budget" in body["conversation_state"]["advisor"]["open_required"]


def test_12_explicit_size_and_budget_are_preserved_exactly(app_env):
    app, container, client = app_env
    body = _discover(client, size="9", located=False, dynamic={"budget_max": 2000})
    kept = body["conversation_state"]["explicit_constraints"]
    assert kept["size"] == "9", "Size 9 stays 9 -- never '8 or 9'"
    assert kept["budget_max"] == 2000


def test_13_nearby_ranking_is_nearest_first():
    out = ro.build([_local(1, km=4.2), _nearby(2, km=0.8), _local(3, km=2.0)], demand=DEMAND)
    assert out["sections"][0]["item_ids"] == ["near-2", "reg-3", "reg-1"]


def test_14_shorts_and_normal_videos_are_separate_sections():
    out = ro.build([_video(1), _video(2, short=True), _video(3)], demand=DEMAND)
    kinds = {s["kind"]: s["item_ids"] for s in out["sections"]}
    assert kinds == {"videos": ["vid-1", "vid-3"], "shorts": ["vid-2"]}


def test_15_one_source_failing_leaves_the_others_rendering(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(error=RuntimeError("web down"))
    body = _discover(client, groups_text="walking shoes shops and online links")
    _assert_contract(body)
    assert "local" in _kinds(body)
    online = next(s for s in body["sections"] if s["kind"] == "online")
    assert online["count"] == 0 and online["requested"] and online["empty_reason"]
    assert "online" in body["answer"]["unavailable"], body["source_status"]


def test_16_brave_quota_exhausted_keeps_local_and_reports_it():
    status = {"askodox": "ok", "nearby": "ok", "online": "quota_exhausted", "videos": "not_applicable"}
    out = ro.build([_local(1)], demand={**DEMAND, "constraints": {"requested_groups": ["online", "local"]}},
                   source_status=status)
    kinds = {s["kind"]: s for s in out["sections"]}
    assert kinds["local"]["count"] == 1
    assert kinds["online"]["count"] == 0 and "quota_exhausted" in kinds["online"]["empty_reason"]
    assert out["answer"]["unavailable"] == ["online"]
    assert out["answer"]["may_claim_results"] is True


def test_17_youtube_unavailable_keeps_products_and_local(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE, video_error=RuntimeError("youtube down"))
    body = _discover(client, groups_text="walking shoes shops, online links and review videos")
    _assert_contract(body)
    assert {"local", "online"} <= set(_kinds(body))
    videos = next(s for s in body["sections"] if s["kind"] == "videos")
    assert videos["count"] == 0 and videos["requested"]


def test_18_the_same_item_twice_is_shown_once_but_unrelated_items_never_merge():
    same = _online(1)
    out = ro.build([same, dict(same), _video(1), _affiliate(1)], demand=DEMAND)
    assert out["orchestration"]["duplicates_dropped"] == 1
    assert sorted(i for s in out["sections"] for i in s["item_ids"]) == ["aff-1", "vid-1", "web-1"]


def test_19_the_same_error_is_reported_once():
    out = ro.build([], demand=DEMAND, errors=["online:RuntimeError", "online:RuntimeError", "videos:X"])
    assert out["orchestration"]["errors"] == ["online:RuntimeError", "videos:X"]
    assert out["answer"]["may_claim_results"] is False


def test_20_state_survives_turns_on_the_signed_in_path(app_env):
    """POST /deals then /matches twice: the advisor (missing before) and the
    explicit size stay on the request; a refinement never drops them."""
    app, container, client = app_env
    owner = "app-contract-" + uuid.uuid4().hex
    headers = {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}
    created = client.post("/deals", json={**_body(size="9", located=False, dynamic={"budget_max": 2000}),
                                          "user_id": owner}, headers=headers)
    assert created.status_code in (200, 201), created.text
    deal_id = created.json().get("id") or created.json().get("deal_id")
    for _ in range(2):
        body = client.get(f"/deals/{deal_id}/matches", headers=headers).json()
        assert body["result_contract_version"] == ro.CONTRACT_VERSION
        assert "advisor" in body, "the signed-in path carries the advisor too (APK 1292)"
        assert body["conversation_state"]["explicit_constraints"]["size"] == "9"
        assert body["conversation_state"]["explicit_constraints"]["budget_max"] == 2000


# ------------------------------------------------ orchestration controls --
def test_command_center_order_and_limits_never_remove_a_section():
    rows = [_online(1), _online(2), _online(3), _local(1), _video(1)]
    out = ro.build(rows, demand=DEMAND, settings={"section_order": ["videos", "online"],
                                                  "section_limits": {"online": 2}})
    assert [s["kind"] for s in out["sections"]] == ["videos", "online", "local"]
    assert out["sections"][1]["item_ids"] == ["web-1", "web-2"]
    assert "online" in out["orchestration"]["suppressed"]


def test_diagnostics_record_returned_and_rendered_sections(app_env):
    app, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    body = _discover(client)
    key = body["trace_key"]
    rendered = client.post("/api/results/rendered", json={"trace_key": key, "sections": ["local"]})
    assert rendered.json() == {"ok": True}
    item = ro.diagnostics(container, trace_key=key)[0]
    assert [s["kind"] for s in item["sections_returned"] if s["count"]] == ["local"]
    assert item["sections_rendered"] == ["local"] and item["render_suppressed"] == {}
    assert item["sources_attempted"]["nearby"] == "ok"
    # decision trace: mode, raw vs kept, ranking and the card action per section
    assert item["mode"]
    assert len(item["ranking"]) == min(15, item["counts_raw_vs_kept"]["kept"])
    assert item["ranking"][0]["rank"] == 1 and item["ranking"][0]["section"] == "local"
    assert set(item["actions"]["local"]) <= {"order_request", "directions", "open_link", "none"}
    assert isinstance(item["rejected"], list) and isinstance(item["price_provenance"], dict)
    assert client.get("/admin/cc/results/diagnostics").status_code in (401, 403)


# --------------------------------------------- content + nearest junction --
def test_only_live_news_is_public_and_joins_results_as_its_own_section(app_env):
    app, container, client = app_env
    from app.api.routes.affiliate_catalog import catalog

    store = catalog(container)
    live = store.create({"title": "Walking shoes buying guide", "item_type": "news", "category": "footwear",
                         "original_product_url": "https://news.example/walking-shoes-guide",
                         "images": ["https://img.example/a.jpg", "https://img.example/b.jpg"]},
                        actor="staff:test", review_status="LIVE")
    store.create({"title": "Walking shoes draft note", "item_type": "news",
                  "original_product_url": "https://news.example/draft"}, actor="staff:test",
                 review_status="NEEDS_REVIEW")
    listed = client.get("/api/content").json()
    assert [i["title"] for i in listed["items"]] == ["Walking shoes buying guide"], "drafts never appear"
    assert listed["items"][0]["images"] == ["https://img.example/a.jpg", "https://img.example/b.jpg"]
    assert client.get("/content").status_code == 200

    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE)
    body = _discover(client, located=False)
    _assert_contract(body)
    assert {"online", "content"} <= set(_kinds(body)), "content ADDS a section, products stay"
    assert f"content-{live['id']}" in next(s for s in body["sections"] if s["kind"] == "content")["item_ids"]


def test_nearest_junction_is_real_or_honestly_unavailable(app_env):
    app, container, client = app_env

    class _Off:
        enabled = False

    container.google_maps_service = _Off()
    off = client.get("/api/discover/junction", params={"latitude": 16.5, "longitude": 80.6}).json()
    assert off == {"status": "unavailable", "junction": None}

    container.google_maps_service = _Maps([
        {"name": "Sri Lakshmi Textiles", "latitude": 16.5001, "longitude": 80.6001},  # not a junction
        {"name": "Benz Circle", "address": "Vijayawada", "latitude": 16.4995, "longitude": 80.6560},
        {"name": "Ramavarappadu Junction", "latitude": 16.5005, "longitude": 80.6010},
    ])
    near = client.get("/api/discover/junction", params={"latitude": 16.5, "longitude": 80.6}).json()
    assert near["status"] == "ok"
    assert near["junction"]["name"] == "Ramavarappadu Junction"
    assert near["junction"]["distance_m"] < 200

    container.google_maps_service = _Maps([{"name": "Some Shop", "latitude": 16.5, "longitude": 80.6}])
    none = client.get("/api/discover/junction", params={"latitude": 16.5, "longitude": 80.6}).json()
    assert none["status"] == "no_results" and none["junction"] is None, "never invents a landmark"


def test_commission_unavailable_keeps_the_organic_link_and_never_invents_price(app_env):
    app, container, client = app_env
    from app.api.routes.affiliate_catalog import catalog

    item = catalog(container).create({"title": "Walking shoes men", "item_type": "product", "platform": "amazon",
                                      "original_product_url": "https://www.amazon.in/dp/B0WALK0001",
                                      "affiliate_url": "https://amzn.to/x"}, actor="staff:test",
                                     commission_status="inactive")
    row = next(r for r in catalog(container).search("walking shoes") if r["id"] == item["id"])
    assert row["eligibility"]["routing"] != "affiliate"
    assert row["eligibility"]["destination_url"].startswith("https://www.amazon.in/")
    assert row.get("price") is None


# ---------------------------------------------------------- video ranking --
def test_shorts_first_when_asked_long_videos_first_for_reviews_both_kept():
    rows = [_video(1), _video(2, short=True), _video(3)]
    asked_shorts = ro.build(rows, demand={**DEMAND, "said": "walking shoes shorts"})
    kinds = [s["kind"] for s in asked_shorts["sections"]]
    assert kinds.index("shorts") < kinds.index("videos") and set(kinds) == {"videos", "shorts"}
    asked_review = ro.build(rows, demand={**DEMAND, "said": "walking shoes review videos"})
    kinds = [s["kind"] for s in asked_review["sections"]]
    assert kinds.index("videos") < kinds.index("shorts")


def test_videos_are_ranked_by_relevance_to_the_subject_never_dropped():
    rows = [dict(_video(1), title="Funny cats compilation"), dict(_video(2), title="Best walking shoes 2026 review"),
            dict(_video(3), title="Walking tips")]
    out = ro.build(rows, demand=DEMAND)
    ids = next(s for s in out["sections"] if s["kind"] == "videos")["item_ids"]
    assert ids == ["vid-2", "vid-3", "vid-1"]


def test_an_ordinary_search_never_gets_videos_forced_in(app_env):
    app, container, client = app_env
    container.brave_web_search_provider = _Brave(rows=SHOES_ONLINE, videos=SHOES_VIDEOS)
    body = _discover(client, text="walking shoes", located=False)
    assert "videos" not in _kinds(body) and "shorts" not in _kinds(body)
    assert not any(s["kind"] in ("videos", "shorts") and s["requested"] for s in body["sections"])


# ------------------------------------------------- typed place -> map point --
class _GeoMaps(_Maps):
    def __init__(self, places, points):
        super().__init__(places)
        self.points, self.geocoded = points, []

    def geocode(self, place, region="in"):
        self.geocoded.append(place)
        return self.points.get(place.lower())


def test_typed_location_gets_coordinates_so_nearby_ranking_works(app_env):
    app, container, client = app_env
    container.google_maps_service = _GeoMaps(SHOES_PLACES, {"benz circle, vijayawada": {
        "name": "Benz Circle, Vijayawada", "latitude": 16.4995, "longitude": 80.6560, "place_id": "p"}})
    body = _body(located=False)
    body["location"] = {"label": "Benz Circle, Vijayawada"}
    response = client.post("/deals/discover", json=body).json()
    assert container.google_maps_service.geocoded == ["Benz Circle, Vijayawada"]
    local = next(s for s in response["sections"] if s["kind"] == "local")
    assert local["count"] >= 1, "nearby now searched around the typed place"
    assert response["source_status"]["nearby"] == "ok"


def test_typed_pickup_and_drop_resolve_to_points_with_a_junction(app_env):
    app, container, client = app_env
    maps = _GeoMaps([{"name": "Benz Circle Bus Stop", "latitude": 16.4996, "longitude": 80.6561,
                      "types": ["bus_stop", "transit_station"]}],
                    {"benz circle": {"name": "Benz Circle", "latitude": 16.4995, "longitude": 80.6560},
                     "governorpet": {"name": "Governorpet", "latitude": 16.5130, "longitude": 80.6240}})
    container.google_maps_service = maps
    from app.api.routes import universal_deals as ud

    demand = {"subject": "parcel", "constraints": {"from": "Benz Circle", "to": "Governorpet"}}
    ud._resolve_typed_places(container, demand)
    c = demand["constraints"]
    assert (c["from_lat"], c["to_lat"]) == (16.4995, 16.5130)
    assert c["from_landmark"] == "Benz Circle Bus Stop"
    assert c["places_resolved"] == {"from": "geocoded", "to": "geocoded"}
    resolved = client.get("/api/discover/resolve", params={"q": "Benz Circle", "junction": True}).json()
    assert resolved["status"] == "ok" and resolved["junction"]["name"] == "Benz Circle Bus Stop"
    assert client.get("/api/discover/resolve", params={"q": "Nowhere Land"}).json()["status"] == "not_found"
