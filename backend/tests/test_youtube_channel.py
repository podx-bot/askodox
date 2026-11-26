"""ASKODOX's own YouTube channel: one-time connect link, encrypted token, never returned; a published Studio video is
uploaded once. Google is never called in tests."""
import datetime as dt

import pytest
from cryptography.fernet import Fernet

from app.api.routes import meta_oauth
from app.services import youtube_channel as yt
from app.services.secret_box import SecretBox, SecretsNotConfigured

NOW = dt.datetime(2026, 11, 26, 14, 0, tzinfo=dt.timezone.utc)


def _store(tmp_path, moment=NOW, key=True):
    box = SecretBox(Fernet.generate_key().decode() if key else "")
    clock = {"now": moment}
    store = yt.YouTubeChannelStore(str(tmp_path / "y.db"), box, clock=lambda: clock["now"])
    return store, clock


def test_auth_url_asks_only_the_two_scopes(monkeypatch):
    monkeypatch.setenv("YOUTUBE_OAUTH_CLIENT_ID", "cid.apps.googleusercontent.com")
    monkeypatch.setenv("YOUTUBE_OAUTH_CLIENT_SECRET", "s3cret-value")
    monkeypatch.delenv("YOUTUBE_OAUTH_REDIRECT_URI", raising=False)
    assert yt.configured()
    url = yt.auth_url("st4te")
    assert url.startswith("https://accounts.google.com/o/oauth2/v2/auth?")
    assert "youtube.upload" in url and "youtube.readonly" in url and "youtube.force-ssl" not in url
    assert "access_type=offline" in url and "prompt=consent" in url and "state=st4te" in url
    assert "admin.askodox.com%2Fyoutube%2Foauth%2Fcallback" in url
    assert "s3cret-value" not in url


def test_not_configured_without_both_values(monkeypatch):
    monkeypatch.setenv("YOUTUBE_OAUTH_CLIENT_ID", "cid")
    monkeypatch.delenv("YOUTUBE_OAUTH_CLIENT_SECRET", raising=False)
    assert not yt.configured()


def test_state_is_one_time_and_expires(tmp_path):
    store, clock = _store(tmp_path)
    state = store.new_state("staff-1")
    assert store.state_open(state) and store.take_state(state) == "staff-1"
    assert not store.state_open(state) and store.take_state(state) == ""      # used once
    late = store.new_state("staff-1")
    clock["now"] = NOW + dt.timedelta(minutes=yt.STATE_MINUTES + 1)
    assert not store.state_open(late) and store.take_state(late) == ""       # too old
    assert store.take_state("made-up") == ""


def test_token_is_encrypted_and_never_in_status(tmp_path):
    store, _ = _store(tmp_path)
    store.save({"id": "UC123", "title": "ASKODOX AI"}, "1//refresh-token-value", actor="staff-1")
    import sqlite3

    raw = sqlite3.connect(store.db_path).execute("SELECT refresh_token FROM youtube_channel").fetchone()[0]
    assert "refresh-token-value" not in raw
    assert store.refresh_token() == "1//refresh-token-value"
    status = store.status()
    assert status["connected"] and status["channel_title"] == "ASKODOX AI"
    assert "refresh-token-value" not in repr(status) and "refresh_token" not in status
    assert store.disconnect() == "1//refresh-token-value"
    assert not store.status()["connected"] and store.refresh_token() == ""


def test_no_secrets_key_means_no_stored_token(tmp_path):
    store, _ = _store(tmp_path, key=False)
    with pytest.raises(SecretsNotConfigured):
        store.save({"id": "UC1", "title": "x"}, "token", actor="a")
    assert not store.status()["connected"]


def test_upload_remembered_once(tmp_path):
    store, _ = _store(tmp_path)
    assert store.uploaded("studio:7") is None
    first = store.record_upload("studio:7", "abcDEF123", "private", actor="staff-1")
    assert first["url"] == "https://www.youtube.com/watch?v=abcDEF123"
    assert store.uploaded("studio:7")["video_id"] == "abcDEF123"
    assert [u["ref"] for u in store.status()["uploads"]] == ["studio:7"]


def test_clean_text_and_privacy():
    assert yt.clean_text("  <b>Saree</b> ₹499 ", 100) == "bSaree/b ₹499"
    assert len(yt.clean_text("x" * 500, yt.MAX_TITLE)) == yt.MAX_TITLE
    with pytest.raises(yt.YouTubeError):
        yt.upload_file("token", "/nonexistent", title="t", description="d", privacy="everyone")


def test_meta_messaging_scopes_only_when_asked():
    assert meta_oauth.scopes_for("") == meta_oauth.DEFAULT_SCOPES
    asked = meta_oauth.scopes_for("1")
    assert "pages_messaging" in asked and "instagram_manage_messages" in asked
    assert not any("ads" in scope for scope in asked)


from test_sources_workspace_early_access import OWNER, api  # noqa: E402,F401  (fixture)


def test_routes_connect_callback_and_upload_guards(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    assert client.get("/admin/cc/workspace/youtube").status_code in (401, 403)          # staff only
    monkeypatch.delenv("YOUTUBE_OAUTH_CLIENT_ID", raising=False)
    monkeypatch.delenv("YOUTUBE_OAUTH_CLIENT_SECRET", raising=False)
    status = client.get("/admin/cc/workspace/youtube", headers=OWNER).json()
    assert status["connected"] is False and status["configured"] is False
    assert client.post("/admin/cc/workspace/youtube/connect", headers=OWNER).status_code == 503

    monkeypatch.setenv("YOUTUBE_OAUTH_CLIENT_ID", "cid")
    monkeypatch.setenv("YOUTUBE_OAUTH_CLIENT_SECRET", "top-secret-value")
    assert client.post("/admin/cc/workspace/youtube/connect").status_code in (401, 403)  # no staff sign-in
    link = client.post("/admin/cc/workspace/youtube/connect", headers=OWNER).json()["url"]
    state = link.split("?t=", 1)[1]
    assert client.get("/youtube/oauth/start?t=nope", follow_redirects=False).status_code == 400
    go = client.get("/youtube/oauth/start?t=" + state, follow_redirects=False)
    assert go.status_code == 302 and go.headers["location"].startswith("https://accounts.google.com/")

    assert client.get("/youtube/oauth/callback?code=abc&state=forged").status_code == 400
    monkeypatch.setattr(yt, "exchange_code", lambda code: {"access_token": "acc-tok", "refresh_token": "ref-tok"})
    monkeypatch.setattr(yt, "channel_of", lambda token: {"id": "UC9", "title": "<i>ASKODOX</i>"})
    back = client.get(f"/youtube/oauth/callback?code=abc&state={state}")
    assert back.status_code == 200 and "&lt;i&gt;ASKODOX&lt;/i&gt;" in back.text
    assert "ref-tok" not in back.text and "acc-tok" not in back.text
    assert client.get(f"/youtube/oauth/callback?code=abc&state={state}").status_code == 400   # state used once
    status = client.get("/admin/cc/workspace/youtube", headers=OWNER)
    assert status.json()["connected"] and "ref-tok" not in status.text

    # a video that does not exist / is not published is never sent
    assert client.post("/admin/cc/workspace/studio/purchases/999/youtube", headers=OWNER, json={}).status_code == 404
    made = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={
        "title": "Silver anklets", "store": "Meesho", "paid": 249}).json()["purchase"]
    sent = []
    monkeypatch.setattr(yt, "upload_file", lambda *a, **k: sent.append(1) or "vid")
    assert client.post(f"/admin/cc/workspace/studio/purchases/{made['id']}/youtube", headers=OWNER,
                       json={}).status_code == 422
    assert client.post(f"/admin/cc/workspace/studio/purchases/{made['id']}/youtube", headers=OWNER,
                       json={"privacy": "everyone"}).status_code == 422
    assert sent == []

    revoked = []
    monkeypatch.setattr(yt, "revoke", lambda token: revoked.append(token))
    off = client.post("/admin/cc/workspace/youtube/disconnect", headers=OWNER)
    assert off.status_code == 200 and off.json()["connected"] is False and revoked == ["ref-tok"]
