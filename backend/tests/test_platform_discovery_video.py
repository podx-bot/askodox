"""Platform layer inside the ONE discovery pipeline + the video journey.

SEARCH -> relevant reviewed videos -> watch (official embed or app/web
fallback) -> "Ask ASKODOX" about the video (honest when it was not
analyzed, Telugu too) -> related product/service -> local/online options
(same /deals/discover) -> affiliate conversion -> attribution events.
Every video, creator and merchant here is a test fixture.
"""
import dataclasses
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.repositories.sponsored_repository import SponsoredRepository
from app.services import external_call_budget, rate_limit
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-pv-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
BASE = "/admin/cc/platform"


@pytest.fixture(autouse=True)
def _fresh():
    external_call_budget.reset_for_tests()
    rate_limit.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "pv.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "sponsored_repository", SponsoredRepository(str(tmp_path / "sp.db")),
                        raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    yield TestClient(app, follow_redirects=False), container
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None


def create(client, resource, data):
    response = client.post(f"{BASE}/r/{resource}", headers=OWNER, json={"data": data})
    assert response.status_code == 200, response.text
    return response.json()


def approve(client, resource, record_id):
    response = client.post(f"{BASE}/r/{resource}/{record_id}/actions/approve", headers=OWNER,
                           json={"confirm": True})
    assert response.status_code == 200, response.text
    return response.json()


def video(client, title, keywords, *, categories=(), relationship="organic", url=None, platform="youtube",
          **extra):
    record = create(client, "videos", {
        "title": title, "platform": platform, "relationship": relationship,
        "url": url or f"https://www.youtube.com/watch?v={uuid.uuid4().hex[:11]}",
        "keywords": list(keywords), "categories": list(categories), **extra})
    assert record["status"] == "PENDING_REVIEW", "videos are reviewed before customers see them"
    return approve(client, "videos", record["id"])


def discover(client, text, subject=None, category="product", **extra):
    body = {"user_id": "", "raw_text": text, "intent": "buy", "subject": subject or text, "category": category,
            "quantity": None, "unit": None, "price": None,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
            "dynamic_fields": {}, "trace": {"language": "en"}, **extra}
    response = client.post("/deals/discover", json=body)
    assert response.status_code == 200, response.text
    return response.json()


CATEGORIES = [
    # (category label, video title, keywords, customer search)
    ("product", "Redmi Note 13 camera review", ["redmi note 13", "phone"], "redmi note 13 review"),
    ("service", "AC gas refill and repair explained", ["ac repair", "ac gas refill"], "ac repair video"),
    ("local business", "Inside Sri Lakshmi bakery Vijayawada", ["bakery", "cakes"], "bakery cakes video"),
    ("electronics", "Samsung 43 inch smart TV unboxing", ["samsung tv", "43 inch tv", "smart tv"],
     "samsung 43 inch tv unboxing"),
    ("food", "Best chicken biryani in Guntur", ["chicken biryani", "biryani"], "chicken biryani review"),
    ("travel", "Araku valley trip guide", ["araku", "araku trip", "travel"], "araku trip video"),
    ("vehicle", "Tata Nexon EV long-term review", ["tata nexon", "nexon ev"], "tata nexon review"),
    ("home service", "How a plumber fixes a leaking tap", ["plumber", "tap leak"], "plumber tap leak video"),
    ("used item", "Buying a used Royal Enfield Classic 350", ["used royal enfield", "classic 350"],
     "used royal enfield classic 350 review"),
    ("deal", "iPhone 15 festival offer comparison", ["iphone 15 offer", "iphone 15"],
     "iphone 15 offer comparison"),
]


def test_relevant_videos_for_every_category_and_nothing_unrelated(api):
    client, _ = api
    ids = {}
    for label, title, keywords, _ in CATEGORIES:
        ids[label] = video(client, title, keywords)["id"]
    for label, _, _, query in CATEGORIES:
        items = client.get("/api/videos/search", params={"q": query}).json()["items"]
        assert items, f"{label}: no video for '{query}'"
        assert items[0]["video_id"] == ids[label], f"{label}: wrong top video {items[0]['title']}"
        others = {i["video_id"] for i in items} - {ids[label]}
        assert not others, f"{label}: unrelated videos {others}"
    empty = client.get("/api/videos/search", params={"q": "wedding photographer"}).json()
    assert empty["items"] == [] and empty["empty_reason"], "an honest empty state, never filler"


def test_videos_appear_in_discovery_only_when_asked_and_sponsored_last(api):
    client, _ = api
    organic = video(client, "Samsung 43 inch TV review", ["samsung tv", "43 inch tv"])
    campaign = client.post("/admin/cc/sponsored/advertisers", headers=OWNER,
                           json={"name": "Example Brand", "kind": "brand"}).json()
    paid = video(client, "Example 43 inch TV launch", ["43 inch tv"], relationship="sponsored",
                 campaign_id=str(campaign["id"]))
    plain = discover(client, "samsung 43 inch tv")
    assert not [m for m in plain["matches"] if m.get("match_source") == "video"], "videos only when asked"
    asked = discover(client, "samsung 43 inch tv review videos", subject="samsung 43 inch tv")
    rows = asked["matches"]
    video_ids = [m.get("video_id") for m in rows if m.get("match_source") == "video"]
    assert organic["id"] in video_ids and paid["id"] in video_ids
    paid_index = next(i for i, m in enumerate(rows) if m.get("video_id") == paid["id"])
    assert rows[paid_index]["sponsored"] and rows[paid_index]["sponsored_label"] == "Sponsored"
    assert all(m.get("sponsored") for m in rows[paid_index:]), "paid placements never sit above organic rows"
    events = client.get(f"{BASE}/events?event=video_impression", headers=OWNER).json()["items"]
    assert {e["video_id"] for e in events} >= {organic["id"], paid["id"]}


def test_watch_embed_or_fallback_and_disclosures(api):
    client, _ = api
    yt = video(client, "Nexon EV review", ["tata nexon"], url="https://youtu.be/dQw4w9WgXcQ")
    insta = video(client, "Nexon EV reel", ["tata nexon"], platform="instagram",
                  url="https://www.instagram.com/reel/Cexample/")
    creator = create(client, "creators", {"name": "Example Auto Reviews", "platform": "youtube",
                                          "relationship": "affiliate"})
    approve(client, "creators", creator["id"])
    items = {i["video_id"]: i for i in client.get("/api/videos/search", params={"q": "tata nexon"}).json()["items"]}
    assert items[yt["id"]]["embed_url"] == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0"
    assert items[insta["id"]]["embed_url"] is None, "no official embed -> open in its app / web"
    assert items[insta["id"]]["destination_url"] == "https://www.instagram.com/reel/Cexample/"
    assert items[yt["id"]]["disclosure"] is None, "organic videos carry no label"


def test_ask_about_a_video_is_honest_and_leads_to_local_and_online_options(api):
    client, _ = api
    bare = video(client, "Tata Nexon EV review", ["tata nexon"], products=["Tata Nexon EV"],
                 description="Owner review after one year")
    answer = client.post(f"/api/videos/{bare['id']}/explain", json={"question": "Is the range good?"}).json()
    assert answer["analyzed"] is False and "haven't analyzed" in answer["answer"], "never invents content"
    assert answer["from_source"] == ["Tata Nexon EV review", "Owner review after one year"]
    telugu = client.post(f"/api/videos/{bare['id']}/explain", json={"question": "range?", "language": "te"}).json()
    assert "విశ్లేషించలేదు" in telugu["answer"] and telugu["next"][0]["label"] == "దగ్గరలో కనుగొనండి"
    transcribed = video(
        client, "AC service explained", ["ac repair"], services=["AC repair"], relationship="merchant",
        transcript=("Regular cleaning keeps the cooling strong. The biggest problem is a gas leak in old pipes. "
                    "A good technician checks the pressure first. Service costs depend on the city."))
    explained = client.post(f"/api/videos/{transcribed['id']}/explain",
                            json={"question": "What are the problems?"}).json()
    assert explained["analyzed"] and any("gas leak" in s for s in explained["from_source"])
    assert explained["relationship_label"] == "From the business", "merchant claims are labelled"
    actions = {a["action"]: a["ask"] for a in explained["next"]}
    assert actions["local_service"] == "AC repair service near me"
    # The suggested follow-up goes through the SAME discovery pipeline.
    follow = discover(client, actions["find_local"], category="service")
    assert "matches" in follow and follow["trace_key"].startswith("browse:")
    asks = client.get(f"{BASE}/events?event=video_ask", headers=OWNER).json()["items"]
    assert len(asks) == 3 and {a["video_id"] for a in asks} == {bare["id"], transcribed["id"]}
    assert client.post("/api/videos/vid_missing/explain", json={}).status_code == 404


def test_affiliate_video_to_conversion_is_attributed_end_to_end(api):
    client, container = api
    program = create(client, "affiliate_programs", {"name": "Example Network", "commission_type": "percent",
                                                    "commission_percent": 4})
    approve(client, "affiliate_programs", program["id"])
    link = create(client, "affiliate_links", {"title": "Samsung 43 inch smart TV", "program_id": program["id"],
                                              "link_type": "product",
                                              "affiliate_url": "https://shop.example/samsung-43?aff=x",
                                              "keywords": ["samsung tv", "43 inch tv"]})
    approve(client, "affiliate_links", link["id"])
    unlinked = client.post(f"{BASE}/r/videos", headers=OWNER, json={"data": {
        "title": "TV deal", "platform": "youtube", "url": "https://youtu.be/abcdefghijk",
        "relationship": "affiliate"}})
    assert unlinked.status_code == 400, "an affiliate video must name its affiliate link"
    tv = video(client, "Samsung 43 inch TV unboxing", ["samsung tv"], relationship="affiliate",
               affiliate_link_id=link["id"], products=["Samsung 43 inch TV"])
    card = client.get("/api/videos/search", params={"q": "samsung tv"}).json()["items"][0]
    assert card["affiliate"] and "commission" in card["disclosure"]
    headers = {"Authorization": f"Bearer {issue_token('app-video-buyer', container.settings.session_token_secret)}"}
    for event in ("video_open", "video_watch_start", "video_product_click"):
        assert client.post("/api/track", headers=headers,
                           json={"event": event, "ids": {"video_id": tv["id"]}}).json()["recorded"]
    rows = discover(client, "samsung 43 inch tv")["matches"]
    affiliate = [m for m in rows if m.get("affiliate_link_id") == link["id"]]
    assert len(affiliate) == 1 and affiliate[0]["disclosure"] and affiliate[0]["segment"] == "partner"
    organic_positions = [i for i, m in enumerate(rows) if m.get("match_source") in ("registered", "external")]
    assert all(i < rows.index(affiliate[0]) for i in organic_positions), "local results stay first"
    click = affiliate[0]["click_id"]
    assert client.get(f"/go/af/{click}").headers["location"] == "https://shop.example/samsung-43?aff=x"
    conv = client.post(f"{BASE}/affiliate/conversions", headers=OWNER,
                       json={"click_id": click, "external_ref": "NET-77", "order_value": 25000,
                             "status": "pending"}).json()
    assert conv["ledger"]["amount"] == 1000.0 and conv["ledger"]["state"] == "PENDING"
    funnel = {s["step"]: s["count"] for s in client.get(f"{BASE}/analytics", headers=OWNER).json()["funnel"]}
    assert funnel["search"] >= 1 and funnel["click"] == 1 and funnel["conversion"] == 1
    video_funnel = {s["step"]: s["count"] for s in
                    client.get(f"{BASE}/analytics", headers=OWNER).json()["video_funnel"]}
    assert video_funnel["video_open"] == 1 and video_funnel["video_product_click"] == 1


def test_affiliate_links_never_for_service_needs_and_flag_off(api):
    client, container = api
    program = create(client, "affiliate_programs", {"name": "Example", "commission_type": "none"})
    approve(client, "affiliate_programs", program["id"])
    link = create(client, "affiliate_links", {"title": "AC installation kit", "program_id": program["id"],
                                              "link_type": "product", "affiliate_url": "https://shop.example/ac",
                                              "keywords": ["ac installation", "ac"]})
    approve(client, "affiliate_links", link["id"])
    service = discover(client, "AC installation in Vuyyuru", subject="AC installation", category="service",
                       intent="service")
    assert not [m for m in service["matches"] if m.get("affiliate_link_id")], "a service need wants providers"
    container.command_center_repository.set_flag("results.affiliate", False, "test")
    product = discover(client, "ac installation kit")
    assert not [m for m in product["matches"] if m.get("affiliate_link_id")]


def test_merchant_offer_rides_on_the_sellers_result_and_search_is_recorded(api):
    client, container = api
    from app.api.routes.platform import annotate_merchant_offers, platform

    class Catalog:
        def get(self, listing_id):
            return {"id": listing_id, "seller_user_id": "app-seller-9"} if listing_id == 7 else None

    container_catalog = container.product_catalog_repository
    try:
        container.product_catalog_repository = Catalog()
        offer = platform(container).resources.create(
            "merchant_offers", {"title": "Free installation", "offer_kind": "free_item"}, actor="test",
            owner_ref="app-seller-9", status="ACTIVE")
        rows = [{"id": "7", "match_source": "registered"}, {"id": "8", "match_source": "registered"}]
        annotate_merchant_offers(container, rows)
    finally:
        container.product_catalog_repository = container_catalog
    assert rows[0]["merchant_offer"]["id"] == offer["id"]
    assert rows[0]["merchant_offer"]["claim_path"] == f"/api/merchant-offers/{offer['id']}/claim"
    assert "merchant_offer" not in rows[1]
    discover(client, "zzqx unobtainium widget")
    events = client.get(f"{BASE}/events?event=search", headers=OWNER).json()["items"]
    assert events and events[0]["search_id"].startswith("browse:") and events[0]["user_ref"] is None


def test_reviews_are_labelled_and_independent_average_excludes_paid(api):
    client, _ = api
    for rating, relationship in ((5, "sponsored"), (4, "independent"), (2, "independent")):
        record = create(client, "reviews", {"subject_name": "Samsung 43 inch TV", "subject_type": "product",
                                            "rating": rating, "review_kind": "written", "author_type": "user",
                                            "relationship": relationship, "text": "ok",
                                            "keywords": ["samsung tv"]})
        approve(client, "reviews", record["id"])
    pending = create(client, "reviews", {"subject_name": "Samsung 43 inch TV", "subject_type": "product",
                                         "rating": 1, "review_kind": "written", "author_type": "user",
                                         "relationship": "independent", "keywords": ["samsung tv"]})
    data = client.get("/api/reviews", params={"q": "samsung tv"}).json()
    assert len(data["items"]) == 3, "unreviewed reviews are not shown"
    assert pending["id"] not in {i["id"] for i in data["items"]}
    assert data["independent_average"] == 3.0, "paid reviews never lift the independent score"
    assert any(i.get("label") == "Sponsored review" for i in data["items"])


def test_merchant_video_and_creator_application_are_reviewed_and_labelled(api):
    client, container = api
    merchant = {"Authorization": f"Bearer {issue_token('app-merchant-v', container.settings.session_token_secret)}"}
    assert client.post("/api/merchant/videos", json={"data": {}}).status_code == 401
    submitted = client.post("/api/merchant/videos", headers=merchant, json={"data": {
        "title": "Our AC service team at work", "platform": "youtube", "url": "https://youtu.be/abcdefghijk",
        "keywords": ["ac service"], "services": ["AC service"], "relationship": "sponsored", "featured": True}})
    assert submitted.status_code == 200, submitted.text
    record = submitted.json()
    assert record["status"] == "PENDING_REVIEW" and record["data"]["relationship"] == "merchant"
    assert not record["data"]["featured"], "a merchant cannot feature or relabel its own video"
    assert client.get("/api/videos/search", params={"q": "ac service"}).json()["items"] == []
    approve(client, "videos", record["id"])
    card = client.get("/api/videos/search", params={"q": "ac service"}).json()["items"][0]
    assert card["disclosure"] == "From the business"
    assert [v["id"] for v in client.get("/api/merchant/videos", headers=merchant).json()["items"]] == [record["id"]]

    creator = client.post("/api/creators/apply", headers=merchant, json={"data": {
        "name": "Example Tech Telugu", "platform": "youtube", "profile_url": "https://youtube.com/@example",
        "verified": True}})
    assert creator.status_code == 200 and creator.json()["status"] == "PENDING_REVIEW"
    assert creator.json()["data"]["verified"] is False, "verification is ASKODOX's decision"
    assert client.post("/api/creators/apply", headers=merchant,
                       json={"data": {"name": "Again", "platform": "youtube"}}).status_code == 409
    verified = client.post(f"{BASE}/r/creators/{creator.json()['id']}/actions/verify", headers=OWNER,
                           json={"confirm": True})
    assert verified.json()["data"]["verified"] is True
