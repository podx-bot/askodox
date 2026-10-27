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
