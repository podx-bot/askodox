"""Unified chat results: local matches, online fallback, videos, reviews, consent."""
import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token
from app.services.universal_external_result_service import UniversalOnlineFallbackService


class _FakeSearch:
    configured = True

    def __init__(self, rows=None, error=None):
        self.rows = rows or []
        self.error = error
        self.queries = []

    def __call__(self, query, limit):
        self.queries.append(query)
        if self.error:
            raise self.error
        return self.rows


def test_unconfigured_search_returns_no_placeholder_links_and_says_unavailable():
    service = UniversalOnlineFallbackService(None)

    assert service.online(category="PRODUCT", subject="mixer grinder") == []
    assert service.videos(category="PRODUCT", subject="mixer grinder") == []
    assert service.status == {"online": "unavailable", "videos": "unavailable"}


class _FakeBrave(_FakeSearch):
    def __init__(self, rows=None, videos=None, error=None):
        super().__init__(rows=rows, error=error)
        self.video_rows = videos or []

    def videos(self, query, limit):
        self.queries.append("VIDEOS:" + query)
        return self.video_rows


def test_configured_search_returns_real_pages_and_actual_videos_with_metadata():
    search = _FakeBrave(
        rows=[
            {"title": "Mixer grinder 750W at Store", "url": "https://store.example/mixer",
             "snippet": "Mixer grinder now ₹2,999 with free delivery", "thumbnail": "https://imgs.example/m.jpg",
             "host": "store.example"},
            {"title": "Mixer grinder review", "url": "https://www.youtube.com/watch?v=abc", "snippet": "Review"},
            {"title": "Cooking tips", "url": "https://food.example", "snippet": "unrelated"},
            {"title": "Bad", "url": "javascript:alert(1)", "snippet": "mixer grinder"},
        ],
        videos=[
            {"title": "Best mixer grinder 2026 review", "url": "https://www.youtube.com/watch?v=v1",
             "thumbnail": "https://i.ytimg.com/vi/v1/hq.jpg", "creator": "Tech Telugu", "duration": "08:12"},
            {"title": "Funny cats", "url": "https://www.youtube.com/watch?v=cat", "creator": "x"},
        ],
    )
    service = UniversalOnlineFallbackService(search)

    online = service.online(category="PRODUCT", subject="mixer grinder")
    videos = service.videos(category="PRODUCT", subject="mixer grinder")

    assert [row["destination_url"] for row in online] == ["https://store.example/mixer"]
    assert online[0]["price"] == 2999
    assert online[0]["image_url"] == "https://imgs.example/m.jpg"
    assert online[0]["source_name"] == "store.example"
    assert [row["destination_url"] for row in videos] == ["https://www.youtube.com/watch?v=v1"]
    assert videos[0]["image_url"] == "https://i.ytimg.com/vi/v1/hq.jpg"
    assert videos[0]["source_name"] == "Tech Telugu"
    assert videos[0]["duration"] == "08:12"
    assert service.status == {"online": "ok", "videos": "ok"}
    for row in online + videos:
        assert "Search online" not in row["title"] and "reviews on YouTube" not in row["title"]


def test_search_failure_and_non_video_domains_are_safe():
    service = UniversalOnlineFallbackService(_FakeSearch(error=RuntimeError("down")))

    assert service.online(category="PRODUCT", subject="rice") == []
    assert service.status["online"] == "no_results"
    assert service.videos(category="RIDE", subject="airport") == []
    assert service.online(category="PRODUCT", subject="   ") == []


def _owner_headers(container, owner):
    return {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}


def test_no_local_match_reports_real_online_and_videos_without_counting_them(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "unified.db"))
    from server import app, container

    owner = "app-unified-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create({
        "user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": "pressure cooker", "source": "app",
    })
    client = TestClient(app)

    # Search unavailable: no placeholder rows, honest status.
    monkeypatch.setattr(container, "brave_web_search_provider", None)
    body = client.get(f"/deals/{demand_id}/matches", headers=_owner_headers(container, owner)).json()
    assert [row for row in body["matches"] if row["match_source"] in {"online", "video"}] == []
    assert body["source_status"]["online"] == "unavailable"
    assert body["source_status"]["videos"] == "unavailable"
    assert body["source_status"]["askodox"] == "no_results"

    # Search configured: real rows only.
    monkeypatch.setattr(container, "brave_web_search_provider", _FakeBrave(
        rows=[{"title": "Pressure cooker 5L", "url": "https://shop.example/pc", "snippet": "Pressure cooker Rs. 1,899"}],
        videos=[{"title": "Pressure cooker review", "url": "https://www.youtube.com/watch?v=pc", "creator": "Kitchen"}],
    ))
    body = client.get(f"/deals/{demand_id}/matches", headers=_owner_headers(container, owner)).json()
    sources = [row["match_source"] for row in body["matches"]]
    assert "online" in sources and "video" in sources
    assert "interest" not in sources
    assert body["match_count"] == 0
    assert body["local_match_count"] == 0
    assert body["waiting_for_interest"] is True
    assert body["online_fallback_used"] is True
    assert body["source_status"]["online"] == "ok"


def test_genuine_local_match_keeps_discovering_online_and_carries_reviews(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "unified-local.db"))
    from server import app, container

    owner = "app-unified-" + uuid.uuid4().hex
    seller = "app-seller-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create({
        "user_id": owner, "side": "NEED", "domain": "SERVICES", "subject": "ac repair", "source": "app",
    })
    container.universal_notification_repository.record_interest(demand_id, owner, seller)
    container.universal_review_repository.create(9_999_001, "app-someone", seller, "SERVICES", 4, "ok")
    container.universal_review_repository.create(9_999_002, "app-someone", seller, "SERVICES", 5, "great")

    client = TestClient(app)
    response = client.get(f"/deals/{demand_id}/matches", headers=_owner_headers(container, owner))
    stranger = client.get(
        f"/deals/{demand_id}/matches",
        headers=_owner_headers(container, "app-stranger-" + uuid.uuid4().hex),
    )

    assert stranger.status_code == 403
    body = response.json()
    local = [row for row in body["matches"] if row["match_source"] == "interest"]
    assert len(local) == 1
    assert local[0]["rating_average"] == 4.5
    assert local[0]["review_count"] == 2
    # Finding a local party must not stop discovery (sprint 2026-09-26):
    # every other source is still consulted and reported.
    assert {"online", "videos", "nearby", "askodox"} <= set(body["source_status"])
    assert body["local_match_count"] == 1
    assert body["match_count"] == 1
    assert body["waiting_for_interest"] is False


def test_public_product_search_never_exposes_seller_contact(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "search.db"))
    from server import app, container

    subject = "Unified Test Kettle " + uuid.uuid4().hex[:8]
    container.product_catalog_repository.upsert_product("app-phone-919876543210", subject, price=999)
    response = TestClient(app).get("/api/products/search", params={"q": subject})

    assert response.status_code == 200
    items = response.json()["items"]
    assert items, "the seeded listing should be searchable"
    assert all(item["provider_id"] == "" for item in items)
    assert "919876543210" not in response.text


def test_ready_app_deal_is_published_even_when_conversation_pipeline_saves_nothing(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "publish.db"))
    from server import app, container

    owner = "app-publish-" + uuid.uuid4().hex
    headers = _owner_headers(container, owner)
    # Simulate the Build 1236 failure: the conversation pipeline misreads the
    # buy request and saves no demand; live capture saves nothing either.
    monkeypatch.setattr(container.conversation_service, "process", lambda **_: "seller onboarding")
    monkeypatch.setattr(container.universal_live_capture_service, "process_text", lambda *_: None)
    client = TestClient(app)
    body = {
        "user_id": owner,
        "raw_text": "I want to buy chicken in Vijayawada",
        "intent": "buy",
        "subject": "chicken",
        "category": "food",
        "quantity": 1,
        "unit": "kg",
        "fulfilment": "delivery",
        "dynamic_fields": {"cut": "curry cut", "chickenPreference": "skinless"},
        "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
    }

    created = client.post("/deals", json=body, headers=headers)

    assert created.status_code == 200, created.text
    demand = container.universal_demand_repository.get(created.json()["id"])
    assert demand["side"] == "NEED"
    assert demand["domain"] == "PRODUCT"
    assert demand["subject"] == "chicken"
    matches = client.get(f"/deals/{created.json()['id']}/matches", headers=headers).json()
    assert {"online", "videos"} <= set(matches["source_status"])

    incomplete = client.post("/deals", json={**body, "subject": None}, headers=headers)
    assert incomplete.status_code == 422
