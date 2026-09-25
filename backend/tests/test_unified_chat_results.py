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


def test_unconfigured_search_falls_back_to_labelled_links_not_fake_products():
    service = UniversalOnlineFallbackService(None)

    online = service.online(category="PRODUCT", subject="mixer grinder")
    videos = service.videos(category="PRODUCT", subject="mixer grinder")

    assert len(online) == 1
    assert online[0]["source"] == "online"
    assert online[0]["fallback"] is True
    assert "price" not in online[0]
    assert online[0]["destination_url"].startswith("https://www.google.com/search?q=mixer+grinder")
    assert [row["source"] for row in videos] == ["video", "video"]
    assert "youtube.com/results" in videos[0]["destination_url"]
    assert "instagram.com" in videos[1]["destination_url"]


def test_configured_search_splits_real_pages_and_video_hosts():
    search = _FakeSearch(rows=[
        {"title": "Mixer at Store", "url": "https://store.example/mixer", "snippet": "₹2,999"},
        {"title": "Mixer review", "url": "https://www.youtube.com/watch?v=abc", "snippet": "Review"},
        {"title": "Reel", "url": "https://www.instagram.com/reel/xyz/", "snippet": "Reel"},
        {"title": "Bad", "url": "javascript:alert(1)", "snippet": "x"},
    ])
    service = UniversalOnlineFallbackService(search)

    online = service.online(category="PRODUCT", subject="mixer")
    videos = service.videos(category="PRODUCT", subject="mixer")

    assert [row["destination_url"] for row in online] == ["https://store.example/mixer"]
    assert [row["destination_url"] for row in videos] == [
        "https://www.youtube.com/watch?v=abc",
        "https://www.instagram.com/reel/xyz/",
    ]


def test_search_failure_and_non_video_domains_are_safe():
    service = UniversalOnlineFallbackService(_FakeSearch(error=RuntimeError("down")))

    assert service.online(category="PRODUCT", subject="rice")[0]["source"] == "online"
    assert service.videos(category="RIDE", subject="airport") == []
    assert service.online(category="PRODUCT", subject="   ") == []


def _owner_headers(container, owner):
    return {"Authorization": f"Bearer {issue_token(owner, container.settings.session_token_secret)}"}


def test_no_local_match_returns_online_fallback_and_videos_without_counting_them(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "unified.db"))
    from server import app, container

    owner = "app-unified-" + uuid.uuid4().hex
    demand_id = container.universal_demand_repository.create({
        "user_id": owner, "side": "NEED", "domain": "PRODUCT", "subject": "pressure cooker", "source": "app",
    })
    client = TestClient(app)
    response = client.get(f"/deals/{demand_id}/matches", headers=_owner_headers(container, owner))

    assert response.status_code == 200
    body = response.json()
    sources = [row["match_source"] for row in body["matches"]]
    assert "online" in sources and "video" in sources
    assert "interest" not in sources
    assert body["match_count"] == 0
    assert body["local_match_count"] == 0
    assert body["waiting_for_interest"] is True
    assert body["online_fallback_used"] is True


def test_genuine_local_match_suppresses_online_fallback_and_carries_reviews(monkeypatch, tmp_path):
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
    assert "online" not in [row["match_source"] for row in body["matches"]]
    assert body["local_match_count"] == 1
    assert body["match_count"] == 1
    assert body["waiting_for_interest"] is False
    assert body["online_fallback_used"] is False


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
