import os
from app.services.social_video_api_service import SocialVideoApiService

def test_status_never_exposes_credentials(monkeypatch):
    monkeypatch.setenv("YOUTUBE_DATA_API_KEY","secret-youtube")
    monkeypatch.setenv("META_GRAPH_ACCESS_TOKEN","secret-meta")
    status=SocialVideoApiService().status()
    assert all(x["configured"] for x in status)
    assert "secret-youtube" not in repr(status)
    assert "secret-meta" not in repr(status)

def test_unconfigured_youtube_fails_closed(monkeypatch):
    monkeypatch.delenv("YOUTUBE_DATA_API_KEY",raising=False)
    assert SocialVideoApiService().youtube_search("kurti") == []

def test_youtube_rows_are_normalized(monkeypatch):
    monkeypatch.setenv("YOUTUBE_DATA_API_KEY","configured")
    svc=SocialVideoApiService()
    svc._json=lambda url: {"items":[{"id":{"videoId":"abc123"},"snippet":{"title":"Review","channelTitle":"Creator","thumbnails":{"default":{"url":"https://img.example/a.jpg"}}}}]}
    rows=svc.youtube_search("review")
    assert rows[0]["canonical_url"]=="https://www.youtube.com/watch?v=abc123"
    assert rows[0]["creator"]=="Creator"
