"""AI usage metering: provider-reported counts through the one httpx hook, cost estimate, suggested rate."""
import io
import json
import wave

import httpx

import pytest

from app.services import ai_usage_meter as meter


@pytest.fixture(autouse=True)
def _keep_meter_target():
    before = meter._state.get("db")
    yield
    meter._state["db"] = before


def _wav(seconds: float) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\0\0" * int(16000 * seconds))
    return buf.getvalue()


def _handler(request: httpx.Request) -> httpx.Response:
    host, path = request.url.host, request.url.path
    if host == "generativelanguage.googleapis.com":
        return httpx.Response(200, json={"usageMetadata": {"promptTokenCount": 4000, "candidatesTokenCount": 400,
                                                           "thoughtsTokenCount": 100}})
    if host == "api.openai.com":
        return httpx.Response(200, json={"usage": {"input_tokens": 1000, "output_tokens": 200}})
    if host == "api.sarvam.ai":
        return httpx.Response(200, json={"transcript": "x"} if "speech-to-text" in path else {"audios": []})
    if host == "api.search.brave.com":
        return httpx.Response(200, json={"web": {"results": []}})
    return httpx.Response(404)


def test_every_provider_is_counted_without_content(tmp_path):
    db = str(tmp_path / "m.db")
    meter.install(db)
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
    client.post(url, json={"contents": [{"parts": [{"text": "chicken 1 kg"}]}]})
    client.post(url, json={"contents": [{"parts": [{"inline_data": {"mime_type": "image/jpeg", "data": "AAA"}}]}]})
    client.post("https://api.openai.com/v1/responses", json={"model": "gpt-5", "input": "hi"})
    client.post("https://api.sarvam.ai/speech-to-text", files={"file": ("a.wav", _wav(15.0), "audio/wav")})
    client.post("https://api.sarvam.ai/text-to-speech/stream", json={"text": "x" * 400, "model": "bulbul:v3"})
    client.get("https://api.search.brave.com/res/v1/web/search", params={"q": "ac shop"})
    client.get("https://example.com/")  # not a provider: ignored
    out = meter.report(db, days=1)
    feats = {f["feature"]: f for f in out["features"]}
    assert set(feats) == {"chat", "image", "voice_in", "voice_out", "web_search"}
    rows = {(r["feature"], r["provider"]): r for r in out["rows"]}
    gem = rows[("chat", "gemini")]
    assert gem["input_tokens"] == 4000 and gem["output_tokens"] == 500 and gem["model"] == "gemini-3.6-flash"
    assert rows[("voice_in", "sarvam")]["seconds"] == 15.0
    assert rows[("voice_out", "sarvam")]["chars"] == 400
    # Gemini chat: (4000*0.75 + 500*3.75)/1e6 USD * 88 * 1.18 GST = ~0.506 INR
    assert abs(gem["cost_inr"] - 0.51) < 0.01
    assert abs(rows[("voice_out", "sarvam")]["cost_inr"] - 1.2) < 0.001
    assert out["markup"] == 2.06
    assert feats["voice_out"]["suggested_rate_paise"] == 248
    with __import__("sqlite3").connect(db) as conn:
        dump = json.dumps(conn.execute("SELECT * FROM ai_usage_daily").fetchall())
    assert "chicken" not in dump and "ac shop" not in dump, "only counts are stored"


def test_prices_are_editable_and_validated(tmp_path):
    db = str(tmp_path / "p.db")
    p = meter.save_prices(db, {"usd_inr": 90, "tokens_usd_per_million": {"claude-haiku-5-5": [0.1, 0.5]}}, actor="s:1")
    assert p["usd_inr"] == 90 and p["tokens_usd_per_million"]["default"] == [1.0, 5.0] and p["updated_by"] == "s:1"
    for bad in ({"nope": 1}, {"usd_inr": -1}, {"tokens_usd_per_million": {"x": [5000, 1]}}):
        try:
            meter.save_prices(db, bad, actor="s:1")
            raise AssertionError(bad)
        except ValueError:
            pass


def test_admin_cost_route_needs_staff():
    from fastapi.testclient import TestClient

    from server import app

    client = TestClient(app)
    assert client.get("/admin/cc/ai-credits/costs").status_code in (401, 403)
    assert client.put("/admin/cc/ai-credits/prices", json={"usd_inr": 1}).status_code in (401, 403)


# ---------------------------------------------------------------- per-user trial meter (owner 2026-11-24) --
def _gem(client: httpx.Client, media: bool = False) -> None:
    part = {"inline_data": {"mime_type": "image/jpeg", "data": "AAA"}} if media else {"text": "hi"}
    client.post("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
                json={"contents": [{"parts": [part]}]})


def test_calls_are_attributed_to_the_bound_user_across_threads(tmp_path):
    import concurrent.futures
    import sqlite3
    import threading

    db = str(tmp_path / "u.db")
    meter.install(db)
    client = httpx.Client(transport=httpx.MockTransport(_handler))
    _gem(client)  # no user bound: counted in the app total only
    token = meter.bind_user("app-phone-9000000001")
    try:
        _gem(client)
        _gem(client)  # same request, same group -> still ONE use
        t = threading.Thread(target=meter.carry(_gem), args=(client,))
        t.start()
        t.join()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            pool.submit(meter.carry(_gem), client, True).result()
            pool.submit(_gem, client).result()  # not carried: app total only
        client.get("https://api.search.brave.com/res/v1/web/search", params={"q": "x"})
    finally:
        meter.reset_user(token)
    other = meter.bind_user("app-phone-9000000002")
    try:
        _gem(client)
    finally:
        meter.reset_user(other)
    assert meter.current_user() == ""
    with sqlite3.connect(db) as conn:
        rows = {(u, f): (uses, calls) for u, f, uses, calls in
                conn.execute("SELECT user_id, feature, uses, calls FROM ai_usage_user_daily")}
    assert rows[("app-phone-9000000001", "chat")] == (1, 3), "carried thread call counted; one use per request"
    assert rows[("app-phone-9000000001", "image")] == (1, 1), "pool task carried"
    assert rows[("app-phone-9000000001", "web_search")] == (1, 1)
    assert rows[("app-phone-9000000002", "chat")] == (1, 1)
    assert len(rows) == 4, "the unbound call belongs to nobody"

    mine = meter.user_usage(db, "app-phone-9000000001")
    chat = mine["today"]["by_feature"]["chat"]
    # 3 gemini chat calls at ~0.506 INR each, shown x markup 2.06
    assert chat["uses"] == 1 and abs(chat["value_paise"] - 3 * 50.6 * 2.06) < 5
    assert mine["today"]["uses"] == 3 and mine["month"]["value_paise"] >= mine["today"]["value_paise"]
    assert meter.user_usage(db, "app-phone-nobody")["today"]["value_paise"] == 0

    rep = meter.users_report(db, days=1)
    assert rep["user_count"] == 2 and rep["users"][0]["user"] == "app-phone-9000000001"
    assert rep["totals"]["unattributed_cost_inr"] > 0, "the signed-out call shows as unattributed"
    assert abs(rep["totals"]["value_inr"] - rep["totals"]["cost_inr"] * rep["markup"]) < 0.05


def test_middleware_binds_only_a_valid_session(tmp_path):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.ai_usage_user_middleware import AiUsageUserMiddleware
    from app.services.session_tokens import issue_token

    class _Settings:
        session_token_secret = "s" * 32

    class _Container:
        settings = _Settings()

    app = FastAPI()

    @app.get("/who")
    def who() -> dict:  # sync route: runs on a worker thread, must still see the user
        return {"user": meter.current_user()}

    app.add_middleware(AiUsageUserMiddleware, container=_Container())
    client = TestClient(app)
    good = issue_token("app-phone-9000000003", _Settings.session_token_secret)
    assert client.get("/who", headers={"Authorization": f"Bearer {good}"}).json() == {"user": "app-phone-9000000003"}
    assert client.get("/who", headers={"Authorization": "Bearer forged.token"}).json() == {"user": ""}
    assert client.get("/who").json() == {"user": ""}


def test_my_credits_shows_usage_and_staff_route_is_protected(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "ai_credits", None, raising=False)
    user = "app-phone-9411100702"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    mine = client.get("/api/me/ai-credits", headers=auth).json()
    assert mine["charging"] is False
    usage = mine["usage"]
    assert usage["free_now"] is True and usage["estimate"] is True
    assert set(usage["today"]["by_feature"]) >= {"chat", "voice", "web_search", "image"}
    assert client.get("/admin/cc/ai-credits/users").status_code in (401, 403)
