from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import meta_oauth


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(meta_oauth.router)
    return TestClient(app)


def test_start_redirects_to_facebook_with_state(monkeypatch):
    monkeypatch.setenv("META_APP_ID", "123")
    client = _client()
    response = client.get("/meta/oauth/start", follow_redirects=False)
    assert response.status_code == 302
    location = response.headers["location"]
    assert location.startswith("https://www.facebook.com/")
    assert "client_id=123" in location
    assert "pages_manage_posts" in location
    assert "ads_management" not in location
    assert meta_oauth.STATE_COOKIE in response.headers["set-cookie"]


def test_start_requires_app_id(monkeypatch):
    monkeypatch.delenv("META_APP_ID", raising=False)
    response = _client().get("/meta/oauth/start", follow_redirects=False)
    assert response.status_code == 503


def test_callback_rejects_missing_state_cookie():
    response = _client().get("/meta/oauth/callback?code=abc&state=xyz")
    assert response.status_code == 400
    assert "Invalid or expired" in response.text


def test_callback_rejects_mismatched_state(monkeypatch):
    monkeypatch.setenv("META_APP_ID", "123")
    monkeypatch.setenv("META_APP_SECRET", "secret")
    client = _client()
    client.cookies.set(meta_oauth.STATE_COOKIE, "expected")
    response = client.get("/meta/oauth/callback?code=abc&state=other")
    assert response.status_code == 400


def test_callback_lists_pages_and_escapes_names(monkeypatch):
    monkeypatch.setenv("META_APP_ID", "123")
    monkeypatch.setenv("META_APP_SECRET", "secret")
    monkeypatch.setattr(meta_oauth, "_exchange_code", lambda code: "user-token")
    monkeypatch.setattr(meta_oauth, "_list_pages", lambda token: [{"id": "1", "name": "<b>Askodox AI</b>"}])
    client = _client()
    client.cookies.set(meta_oauth.STATE_COOKIE, "good")
    response = client.get("/meta/oauth/callback?code=abc&state=good")
    assert response.status_code == 200
    assert "Pages found: 1" in response.text
    assert "&lt;b&gt;Askodox AI&lt;/b&gt;" in response.text
    assert "user-token" not in response.text


def test_callback_handles_user_cancel():
    response = _client().get("/meta/oauth/callback?error=access_denied")
    assert response.status_code == 400
    assert "cancelled" in response.text
