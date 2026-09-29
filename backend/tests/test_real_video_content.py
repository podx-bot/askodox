"""Web videos in the one discovery pipeline: stable references, official
YouTube embeds only where YouTube allows them (oEmbed), removed videos
dropped, creator-opinion / paid-promotion disclosure, linking to the
customer's product or service, honest Ask ASKODOX (English / Telugu), the
optional YouTube Data API source and attribution events.

The network is replaced by test doubles here; the real-content proof runs
against live sources in .github/workflows/video-real-content-proof.yml.
"""
import dataclasses
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import FEATURE_FLAGS, CommandCenterRepository
from app.services import external_call_budget, rate_limit
from app.services.video_content import PAID_DISCLOSURE, WEB_DISCLOSURE, _iso_duration, video_ref, youtube_id

OWNER_KEY = "owner-rv-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
BASE = "/admin/cc/platform"
TV = "https://www.youtube.com/watch?v=AbCdEfGhIj1"
TV2 = "https://youtu.be/ZyXwVuTsRq2"
GONE = "https://www.youtube.com/watch?v=Removed0000"
NOEMBED = "https://www.youtube.com/shorts/NoEmbed0001"
REEL = "https://www.instagram.com/reel/Cexample/"


class Brave:
    configured = True

    def __init__(self, videos):
        self.video_rows = videos
        self.queries = []

    def __call__(self, query, limit):
        return []

    def videos(self, query, limit):
        self.queries.append(query)
        return self.video_rows


class Net:
    """oEmbed / YouTube Data API double: records every call."""

    def __init__(self, youtube=None):
        self.calls = []
        self.youtube = youtube or {}

    def __call__(self, url, params):
        self.calls.append((url, dict(params)))
        if "oembed" in url:
            target = params["url"]
            if "Removed" in target:
                return 404, None
            if "NoEmbed" in target:
                return 401, None
            return 200, {"title": "t", "author_name": "Channel", "thumbnail_url": "https://i.ytimg.com/x.jpg"}
        if url.endswith("/search"):
            return 200, {"items": [{"id": {"videoId": v}, "snippet": {"title": s["title"]}}
                                   for v, s in self.youtube.items()]}
        if url.endswith("/videos"):
            return 200, {"items": [{"id": v, "snippet": {"title": s["title"], "description": s.get("d", ""),
                                                         "channelTitle": s["ch"], "thumbnails": {
                                                             "high": {"url": f"https://i.ytimg.com/vi/{v}/hq.jpg"}}},
                                    "contentDetails": {"duration": s.get("dur", "PT8M12S")},
                                    "status": {"embeddable": s.get("embed", True)},
                                    "paidProductPlacementDetails": {"hasPaidProductPlacement": s.get("paid", False)}}
                                   for v, s in self.youtube.items()]}
        return 404, None


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
                                   database_path=str(tmp_path / "rv.db"),
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", cc, raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    net = Net()
    monkeypatch.setattr(container, "video_fetcher", net, raising=False)
    monkeypatch.setattr(container, "brave_web_search_provider", Brave([
        {"title": "Samsung 43 inch Crystal 4K TV review after 6 months", "url": TV,
         "snippet": "Picture quality is good. Sound is weak. Smart features are fast.", "creator": "Tech Telugu",
         "duration": "9:41", "thumbnail": "https://imgs.search.brave.com/tv.jpg"},
        {"title": "Samsung 43 inch TV unboxing", "url": TV2, "creator": "Gadgets"},
        {"title": "Samsung 43 inch TV reel review", "url": REEL, "creator": "reels"},
        {"title": "Samsung 43 inch TV old review", "url": GONE},
        {"title": "Samsung 43 inch TV short review", "url": NOEMBED},
    ]), raising=False)
    yield TestClient(app), container, net
    for key in FEATURE_FLAGS:
        cc.set_flag(key, True, "test")
    container.platform = None


def discover(client, text, subject, category="product", language="en", **extra):
    body = {"user_id": "", "raw_text": text, "intent": "buy", "subject": subject, "category": category,
            "quantity": None, "unit": None, "price": None,
            "location": {"label": "Vijayawada", "latitude": 16.5, "longitude": 80.6, "radius_km": 5},
            "dynamic_fields": {}, "trace": {"language": language}, **extra}
    response = client.post("/deals/discover", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def videos(result):
    return [m for m in result["matches"] if m.get("match_source") == "video"]


def test_helpers():
    assert youtube_id("https://www.youtube.com/watch?feature=share&v=AbCdEfGhIj1") == "AbCdEfGhIj1"
    assert youtube_id("https://youtu.be/AbCdEfGhIj1") == "AbCdEfGhIj1"
    assert video_ref(TV) == "yt_AbCdEfGhIj1" and video_ref(REEL).startswith("wv_")
    assert video_ref(REEL) == video_ref(REEL.upper().lower())
    assert _iso_duration("PT8M12S") == "8:12" and _iso_duration("PT1H2M3S") == "1:02:03"


def test_real_web_videos_become_trackable_playable_where_allowed_and_linked(api):
    client, _, net = api
    rows = videos(discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv"))
    by_ref = {r["video_id"]: r for r in rows}
    assert "yt_Removed0000" not in by_ref, "a removed / private YouTube video is never shown"
    tv = by_ref["yt_AbCdEfGhIj1"]
    assert tv["embed_url"] == "https://www.youtube-nocookie.com/embed/AbCdEfGhIj1?playsinline=1&rel=0"
    assert tv["platform"] == "youtube" and tv["relationship"] == "creator" and tv["disclosure"] == WEB_DISCLOSURE
    assert tv["products"] == ["samsung 43 inch tv"] and tv["services"] == []
    assert tv["image_url"] == "https://imgs.search.brave.com/tv.jpg" and tv["source_name"] == "Tech Telugu"
    from app.services.video_content import YouTubeOEmbed

    assert YouTubeOEmbed(net).check(NOEMBED) == {"checked": True, "exists": True, "embeddable": False}
    reel = next(r for r in rows if r["platform"] == "instagram")
    assert reel["embed_url"] is None and reel["video_id"].startswith("wv_")
    assert by_ref["yt_ZyXwVuTsRq2"]["image_url"] == "https://i.ytimg.com/x.jpg", "thumbnail from YouTube oEmbed"
    assert all(not r["sponsored"] for r in rows)
    oembed_calls = [c for c in net.calls if "oembed" in c[0]]
    assert len(oembed_calls) == 3, "each YouTube video shown is checked once (the reel is not YouTube)"
    discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv")
    assert len([c for c in net.calls if "oembed" in c[0]]) == 3, "oEmbed answers are cached"
    impressions = client.get(f"{BASE}/events?event=video_impression", headers=OWNER).json()["items"]
    assert {e["video_id"] for e in impressions} >= {"yt_AbCdEfGhIj1", reel["video_id"]}
    assert all(e["search_id"].startswith("browse:") for e in impressions)


def test_no_videos_unless_asked(api):
    client, _, _ = api
    assert videos(discover(client, "samsung 43 inch tv", "samsung 43 inch tv")) == []


def test_ask_about_a_web_video_is_honest_in_english_and_telugu(api):
    client, _, _ = api
    discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv")
    en = client.post("/api/videos/yt_AbCdEfGhIj1/explain", json={"question": "Is the sound good?"}).json()
    assert en["analyzed"] is False and "haven't watched" in en["answer"]
    assert en["from_source"][0] == "Samsung 43 inch Crystal 4K TV review after 6 months"
    assert "Sound is weak." in en["from_source"], "the creator's own words, quoted"
    assert en["relationship_label"] == WEB_DISCLOSURE and en["creator"] == "Tech Telugu"
    actions = {a["action"]: a["ask"] for a in en["next"]}
    assert actions["find_local"] == "samsung 43 inch tv near me" and actions["used"] == "used samsung 43 inch tv"
    te = client.post("/api/videos/yt_AbCdEfGhIj1/explain", json={"question": "సౌండ్ బాగుందా?",
                                                                  "language": "te"}).json()
    assert "చూడలేదు" in te["answer"] and te["next"][0]["label"] == "దగ్గరలో కనుగొనండి"
    assert client.post("/api/videos/yt_Unknown0000/explain", json={}).status_code == 404


def test_service_need_links_videos_to_the_service(api):
    client, container, _ = api
    container.brave_web_search_provider.video_rows = [
        {"title": "AC gas refill and service explained", "url": "https://www.youtube.com/watch?v=AcService01",
         "snippet": "What a technician checks during AC service."}]
    rows = videos(discover(client, "AC service video", "AC service", category="service", intent="service"))
    assert rows and rows[0]["services"] == ["AC service"] and rows[0]["products"] == []
    explained = client.post(f"/api/videos/{rows[0]['video_id']}/explain", json={}).json()
    assert {a["action"] for a in explained["next"]} >= {"local_service", "find_local"}


def test_youtube_data_api_leads_when_configured_and_paid_promotion_is_disclosed(api, monkeypatch):
    client, container, net = api
    from app.api.routes.platform import platform

    net.youtube = {"YtOrganic01": {"title": "Samsung 43 inch TV honest review", "ch": "Review Channel",
                                   "dur": "PT10M5S", "d": "Long term review."},
                   "YtPaidPromo": {"title": "Samsung 43 inch TV review (sponsored)", "ch": "Brand Friend",
                                   "paid": True},
                   "YtOffTopic1": {"title": "Best biryani in Guntur", "ch": "Food"}}
    monkeypatch.setitem(platform(container).registry.env, "YOUTUBE_API_KEY", "test-key-not-real")
    rows = videos(discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv"))
    refs = [r["video_id"] for r in rows]
    assert refs[0] == "yt_YtOrganic01", "YouTube's own search leads the video section"
    assert "yt_YtOffTopic1" not in refs, "relevance gate applies to YouTube results too"
    organic = rows[0]
    assert organic["duration"] == "10:05" and organic["source_name"] == "Review Channel"
    paid = next(r for r in rows if r["video_id"] == "yt_YtPaidPromo")
    assert paid["sponsored"] and paid["disclosure"] == PAID_DISCLOSURE
    assert refs.index("yt_YtPaidPromo") == len(refs) - 1, "declared paid promotion sits after organic videos"
    matches = discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv")["matches"]
    first_paid = next(i for i, m in enumerate(matches) if m.get("sponsored"))
    assert all(m.get("sponsored") for m in matches[first_paid:]), "paid never above organic"
    search_calls = [c for c in net.calls if c[0].endswith("/search")]
    assert len(search_calls) == 1 and search_calls[0][1]["regionCode"] == "IN", "cached, India-first"
    assert "test-key-not-real" not in str(rows)


def test_video_funnel_and_attribution_use_the_same_reference(api):
    client, container, _ = api
    from app.services.session_tokens import issue_token

    discover(client, "samsung 43 inch tv review video", "samsung 43 inch tv")
    headers = {"Authorization": f"Bearer {issue_token('app-rv-buyer', container.settings.session_token_secret)}"}
    for event in ("video_open", "video_watch_start", "video_ask", "video_local_search"):
        assert client.post("/api/track", headers=headers,
                           json={"event": event, "ids": {"video_id": "yt_AbCdEfGhIj1"}}).json()["recorded"]
    funnel = {s["step"]: s["count"] for s in client.get(f"{BASE}/analytics", headers=OWNER).json()["video_funnel"]}
    assert funnel["video_impression"] >= 1 and funnel["video_open"] == 1 and funnel["video_local_search"] == 1
