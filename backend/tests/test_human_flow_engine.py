"""Universal human-flow engine: real-phone regressions A-H as backend tests.

Fixture sellers/listings/pages here are test data, not production results.
"""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services import external_call_budget
from app.services.brave_web_search_provider import BraveWebSearchProvider
from app.services.google_maps_service import GoogleMapsService
from app.services.session_tokens import issue_token
from app.services.universal_external_result_service import (
    UniversalOnlineFallbackService,
    classify_page,
    region_mismatch,
)
from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService


@pytest.fixture(autouse=True)
def _fresh_budget():
    external_call_budget.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


# ------------------------------------------------------------- web search --

class _Resp:
    def __init__(self, payload, status=200):
        self._payload, self.status_code = payload, status

    def raise_for_status(self):
        if self.status_code >= 400:
            import httpx
            raise httpx.HTTPStatusError("boom", request=httpx.Request("GET", "https://x"), response=None)

    def json(self):
        return self._payload


class _HttpClient:
    def __init__(self, payload, status=200):
        self.payload, self.status, self.calls = payload, status, []

    def get(self, url, headers=None, params=None, **_):
        self.calls.append((url, dict(params or {})))
        return _Resp(self.payload, self.status)

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append((url, dict(json or {})))
        return _Resp(self.payload, self.status)


_BRAVE_ROWS = {"web": {"results": [
    {"url": "https://www.croma.com/samsung-43-tv/p/1", "title": "Samsung 43 inch TV", "description": "₹27,990 Samsung 43 inch TV"},
]}}


def test_brave_is_india_first_and_identical_searches_are_paid_once():
    client = _HttpClient(_BRAVE_ROWS)
    brave = BraveWebSearchProvider("key", client=client)
    first = brave("43 inch TV price", 5)
    second = brave("43 inch TV price", 5)
    assert first == second and len(first) == 1
    assert len(client.calls) == 1, "same query within the TTL is served from cache"
    params = client.calls[0][1]
    assert params["country"] == "IN" and params["search_lang"] == "en"
    usage = external_call_budget.usage_snapshot()["brave"]
    assert usage["calls"] == 1 and usage["cache_hits"] == 1


def test_brave_failure_is_an_error_not_no_results():
    brave = BraveWebSearchProvider("key", client=_HttpClient({}, status=401))
    fallback = UniversalOnlineFallbackService(brave)
    assert fallback.online(category="SERVICES", subject="AC repair", location_text="Vijayawada") == []
    # A failure, never "no results" -- and named: a 401 is a key problem.
    assert fallback.status["online"] == "auth_failed"
    assert fallback.status["online"] != "no_results"


def test_pages_are_classified_and_only_buyable_pages_are_options():
    assert classify_page("https://www.amazon.in/dp/B0ABC", "Samsung 43 inch TV") == "product_page"
    assert classify_page("https://www.olx.in/item/used-car-iid-1", "Used Swift") == "listing"
    assert classify_page("https://www.91mobiles.com/tv", "Samsung TV") == "review"
    assert classify_page("https://www.tripadvisor.in/Restaurant-Hyderabad", "Best biryani") == "review"
    assert classify_page("https://blog.example/best-tv", "Best 43 inch TVs to buy in 2026") == "article"
    assert classify_page("https://www.youtube.com/watch?v=1", "TV review") == "video"
    assert classify_page("https://www.justdial.com/Vijayawada/AC-Repair", "AC repair") == "directory"


def test_section5_electric_scooter_and_insurance_pages_are_never_invented_products():
    """Universal page rules (no category patch) for the round's retest list."""
    # Electric scooter: comparison/news pages are content, a shop page is an option.
    assert classify_page("https://www.zigwheels.com/news/best-scooters", "Best electric scooters in 2026") == "review"
    assert classify_page("https://ev.example.in/blog/ola-vs-ather", "Ola S1 vs Ather 450X comparison") == "article"
    assert classify_page("https://www.flipkart.com/p/electric-scooter", "Electric scooter 2 kW") == "product_page"
    assert classify_page("https://www.youtube.com/watch?v=ev", "Electric scooter review") == "video"
    # Insurance: guides/explainers are information, never a purchasable policy.
    assert classify_page("https://ins.example.in/guide", "What is term insurance? Explained") == "article"
    assert classify_page("https://ins.example.in/two-wheeler", "Two wheeler insurance",
                         "Learn how cover works") == "info"
    assert classify_page("https://ins.example.in/buy", "Buy two wheeler insurance online",
                         "Get a quote and buy in minutes") == "store"
    assert classify_page("https://www.quora.com/which-insurance", "Which insurance is best?") == "forum"


def test_india_request_never_ranks_us_results():
    assert region_mismatch("https://www.homedepot.com/services/ac-repair", "AC repair service", "$89 AC tune-up")
    assert region_mismatch("https://acfix.example.com", "AC repair Manhattan", "Book in Manhattan today")
    assert region_mismatch("https://shop.example.co.uk/tv", "43 inch TV", "£299")
    assert not region_mismatch("https://www.croma.com/tv", "43 inch TV", "₹27,990")
    assert not region_mismatch("https://acfix.example.com", "AC repair Vijayawada", "Book AC service ₹499")


class _Web:
    configured = True
    last_error = False

    def __init__(self, rows):
        self.rows, self.queries = rows, []

    def __call__(self, query, limit):
        self.queries.append(query)
        return self.rows

    def videos(self, query, limit):
        return []


def test_online_options_filter_reviews_and_wrong_region_and_never_verify_snippet_prices():
    web = _Web([
        {"url": "https://www.homedepot.com/s/ac-repair", "title": "AC repair service", "snippet": "$99 AC repair"},
        {"url": "https://www.91mobiles.com/ac", "title": "AC repair service review", "snippet": "AC repair tips"},
        {"url": "https://www.urbancompany.com/vijayawada-ac-repair", "title": "AC repair service Vijayawada",
         "snippet": "AC repair service from ₹499"},
    ])
    fallback = UniversalOnlineFallbackService(web)
    rows = fallback.online(category="SERVICES", subject="AC repair service", location_text="Vijayawada")
    assert [r["destination_url"] for r in rows] == ["https://www.urbancompany.com/vijayawada-ac-repair"]
    assert rows[0]["price"] == 499 and rows[0]["price_verified"] is False and rows[0]["price_source"] == "page_text"
    assert fallback.filtered == {"wrong_region": 1, "not_purchasable": 1}
    assert "India" in web.queries[0] or "Vijayawada" in web.queries[0]


# ------------------------------------------------------------------- maps --

def test_places_is_india_region_and_errors_are_reported():
    ok = GoogleMapsService(api_key="k", client=_HttpClient({"places": []}))
    ok.search_places("used car near Vijayawada", latitude=16.5, longitude=80.6)
    assert ok.client.calls[0][1]["regionCode"] == "IN"
    failing = GoogleMapsService(api_key="k", client=_HttpClient({}, status=403))
    assert failing.search_places("AC repair", latitude=16.5, longitude=80.6) == [] and failing.last_error is True


class _LadderMaps:
    enabled = True
    last_error = False

    def __init__(self, found_at_radius_m, place_lat=16.68):
        self.found_at, self.calls, self.place_lat = found_at_radius_m, [], place_lat

    def search_places(self, query, latitude=None, longitude=None, radius_m=0, limit=10, **_):
        self.calls.append((query, radius_m))
        if radius_m >= self.found_at:
            return [{"place_id": "p", "name": "Krishna Car Dealers", "latitude": self.place_lat, "longitude": 80.6,
                     "maps_url": "https://maps.google.com/?cid=9"}]
        return []


def test_geography_expands_only_when_needed_and_says_so():
    maps = _LadderMaps(found_at_radius_m=25_000)
    svc = UniversalMultiSourceResultService(maps=maps)
    rows = svc.collect({"subject": "used car", "domain": "PRODUCT", "latitude": 16.5, "longitude": 80.6,
                        "location_text": "Vijayawada", "constraints": {}})
    assert [q for q, _ in maps.calls] == ["used car near Vijayawada"] * 2, "no 'shop' noun; widened once"
    assert rows and rows[0]["title"] == "Krishna Car Dealers" and rows[0]["price"] is None
    assert svc.scope["level"] == "city" and svc.scope["expanded"]
    assert "expanding" in svc.scope["message"]

    near = _LadderMaps(found_at_radius_m=0, place_lat=16.52)
    svc2 = UniversalMultiSourceResultService(maps=near)
    svc2.collect({"subject": "TV", "domain": "PRODUCT", "latitude": 16.5, "longitude": 80.6,
                  "location_text": "Vijayawada", "constraints": {}})
    assert len(near.calls) == 1 and svc2.scope["expanded"] is False


def test_parcel_route_words_never_match_an_unrelated_listing(tmp_path):
    catalog = ProductCatalogRepository(str(tmp_path / "c.db"))
    catalog.upsert_product("app-phone-9301", "Hyderabad biryani restaurant", price=250)
    svc = UniversalMultiSourceResultService(catalog=catalog)
    rows = svc.collect({"subject": "parcel to Hyderabad", "domain": "PARCEL", "location_text": "Vijayawada",
                        "constraints": {"from": "Vijayawada", "to": "Hyderabad"}})
    assert rows == []
    assert svc.source_status()["online"] == "not_applicable"


# ---------------------------------------------------------- API + flows --

OWNER_KEY = "owner-hf-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    return TestClient(app), container


def auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def phone():
    return "app-phone-91" + str(uuid.uuid4().int)[:10]


def need(user, subject, **extra):
    return {"user_id": user, "raw_text": subject, "intent": "buy", "subject": subject, "category": "product",
            "quantity": None, "unit": None, "price": None,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
            "dynamic_fields": {}, **extra}


def test_job_seeker_with_skill_only_is_saved_and_browsable_not_matching_unavailable(api):
    client, container = api
    seeker = phone()
    body = need(seeker, None, intent="seekWork", category="work", raw_text="I need a delivery driver job",
                dynamic_fields={"skill": "delivery driver", "salary": "18000"})
    created = client.post("/deals", json=body, headers=auth(container, seeker))
    assert created.status_code == 200, created.text
    assert client.post("/deals/discover", json={**body, "user_id": ""}).status_code == 200


def test_catering_need_is_broadcast_to_registered_providers_who_can_respond(api):
    client, container = api
    provider = phone()
    listed = client.post("/api/products/mine", headers=auth(container, provider),
                         json={"seller_user_id": provider, "subject": "catering staff service", "price": 800,
                               "location_label": "Vijayawada"})
    assert listed.status_code == 200, listed.text
    elsewhere = phone()
    client.post("/api/products/mine", headers=auth(container, elsewhere),
                json={"seller_user_id": elsewhere, "subject": "catering staff service", "price": 700,
                      "location_label": "Chennai"})
    customer = phone()
    body = need(customer, "catering staff", intent="needWorker", category="service", price=800,
                quantity=10, timing="tomorrow 6 pm")
    created = client.post("/deals", json=body, headers=auth(container, customer))
    assert created.status_code == 200, created.text
    deal = created.json()
    assert deal["broadcast"]["status"] == "SENT" and deal["broadcast"]["sent"] == 1, "only the Vijayawada provider"

    leads = client.get("/deals/leads", headers=auth(container, provider)).json()["leads"]
    assert [lead["request_id"] for lead in leads] == [deal["id"]]
    assert customer not in str(leads), "requester identity never shown in a lead"
    assert client.get("/deals/leads", headers=auth(container, elsewhere)).json()["count"] == 0

    assert client.post(f"/deals/{deal['id']}/interest", headers=auth(container, elsewhere)).status_code == 403
    assert client.post(f"/deals/{deal['id']}/interest", headers=auth(container, provider)).status_code == 200
    matches = client.get(f"/deals/{deal['id']}/matches", headers=auth(container, customer)).json()["matches"]
    assert any(m.get("match_source") == "interest" for m in matches), "the provider's reply reaches the customer"


def test_text_pipeline_no_match_no_longer_crashes(api):
    _, container = api
    capture = container.universal_live_capture_service
    reply = capture._match_target_notify({"id": 999999, "user_id": "919000000000", "side": "NEED",
                                          "domain": "SERVICES", "subject": "zzz unobtainable thing"})
    assert "saved" in reply or "sent" in reply


def test_admin_sees_demand_gaps_and_api_usage(api):
    client, container = api
    cc = container.command_center_repository
    for i, place in enumerate(["Vijayawada", "vijayawada", "Guntur"]):
        cc.record_no_match({"id": 900000 + i, "subject": "catering staff", "domain": "SERVICES",
                            "location_text": place}, {"askodox": "no_results"})
    gaps = client.get("/admin/cc/demand-gaps", headers=OWNER).json()["items"]
    top = gaps[0]
    assert (top["category"], top["area"], top["requests"]) == ("SERVICES", "vijayawada", 2)
    external_call_budget.cached_call("brave", ("q",), lambda: [1])
    usage = client.get("/admin/cc/api-usage", headers=OWNER).json()["items"]
    assert usage[0]["provider"] == "brave" and usage[0]["calls"] == 1
    assert client.get("/admin/cc/api-usage").status_code == 401


def test_place_endpoint_names_the_point_or_says_it_could_not(api, monkeypatch):
    client, container = api
    payload = {"status": "OK", "results": [{"address_components": [
        {"long_name": "Benz Circle", "types": ["sublocality_level_1"]},
        {"long_name": "Vijayawada", "types": ["locality"]},
        {"long_name": "NTR", "types": ["administrative_area_level_3"]},
        {"long_name": "Andhra Pradesh", "types": ["administrative_area_level_1"]},
        {"long_name": "India", "short_name": "IN", "types": ["country"]},
    ]}]}
    monkeypatch.setattr(container, "google_maps_service", GoogleMapsService(api_key="k", client=_HttpClient(payload)))
    body = client.get("/api/discover/place", params={"latitude": 16.5, "longitude": 80.65}).json()
    assert body["resolved"] and body["label"] == "Benz Circle, Vijayawada, Andhra Pradesh"
    monkeypatch.setattr(container, "google_maps_service", GoogleMapsService(api_key=""))
    assert client.get("/api/discover/place", params={"latitude": 16.5, "longitude": 80.65}).json()["resolved"] is False


# ------------------------------------------------ settlement and returns --

def _listing(client, container, subject="43 inch TV", **extra):
    seller = phone()
    pid = client.post("/api/products/mine", headers=auth(container, seller),
                      json={"seller_user_id": seller, "subject": subject, "price": 25000, **extra}).json()["id"]
    return seller, pid


def _status(client, container, seller, oid, status):
    return client.post(f"/api/orders/{oid}/status", headers=auth(container, seller),
                       json={"seller_user_id": seller, "status": status})


def test_cash_on_delivery_is_tracked_until_the_seller_confirms_cash(api):
    client, container = api
    seller, pid = _listing(client, container)
    buyer = phone()
    placed = client.post("/api/orders", headers=auth(container, buyer),
                         json={"buyer_user_id": buyer, "product_id": pid, "settlement_method": "cash on delivery"})
    assert placed.status_code == 200 and placed.json()["settlement_method"] == "COD"
    oid = placed.json()["id"]
    _status(client, container, seller, oid, "ACCEPTED")
    paid = client.post(f"/api/orders/{oid}/payment", headers=auth(container, buyer), json={"action": "cash_paid"}).json()
    assert paid["payment_state"] == "PROOF_SUBMITTED", "the payer's word alone never verifies"
    assert paid["settlement"]["method"] == "COD" and paid["settlement"]["online"] is False
    done = client.post(f"/api/orders/{oid}/payment", headers=auth(container, seller),
                       json={"action": "confirm_cash_received"}).json()
    assert done["payment_state"] == "VERIFIED" and done["paid_at"]

    gateway = client.post("/api/orders", headers=auth(container, buyer),
                          json={"buyer_user_id": buyer, "product_id": pid, "settlement_method": "GATEWAY"})
    assert gateway.status_code == 422, "no fake online payment"


def test_return_and_refund_lifecycle(api):
    client, container = api
    seller, pid = _listing(client, container, "mixer grinder")
    buyer = phone()
    oid = client.post("/api/orders", headers=auth(container, buyer),
                      json={"buyer_user_id": buyer, "product_id": pid, "settlement_method": "COD"}).json()["id"]
    assert client.post(f"/api/orders/{oid}/return", headers=auth(container, buyer),
                       json={"reason": "not working"}).status_code == 409, "not delivered yet"
    _status(client, container, seller, oid, "ACCEPTED")
    client.post(f"/api/orders/{oid}/payment", headers=auth(container, seller), json={"action": "confirm_cash_received"})
    for step in ("PREPARING", "DISPATCHED", "DELIVERED"):
        assert _status(client, container, seller, oid, step).status_code == 200
    r = client.post(f"/api/orders/{oid}/return", headers=auth(container, buyer), json={"reason": "stopped working"}).json()
    assert r["status"] == "RETURN_REQUESTED" and "return_item_received" not in r["actions"]
    seller_view = client.get(f"/api/orders/{oid}", headers=auth(container, seller)).json()
    assert "return_item_received" in seller_view["actions"]
    back = client.post(f"/api/orders/{oid}/return/decision", headers=auth(container, seller),
                       json={"action": "item_received"}).json()
    assert back["status"] == "REFUND_DUE", "paid order -> refund due"
    refunded = client.post(f"/api/orders/{oid}/refund", headers=auth(container, seller),
                           json={"reference": "UTR998877"}).json()
    assert refunded["status"] == "REFUNDED" and refunded["payment_state"] == "REFUNDED"
    closed = client.post(f"/api/orders/{oid}/confirm", headers=auth(container, buyer)).json()
    assert closed["status"] == "CLOSED"
