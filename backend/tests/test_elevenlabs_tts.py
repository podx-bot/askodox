"""ElevenLabs reply voice: language from the text, voice per Profile choice,
fallback to Sarvam when ElevenLabs fails, never a crash."""

from __future__ import annotations

import httpx

from app.services import elevenlabs_tts
from app.services.elevenlabs_tts import VOICES, ElevenLabsTTS, language_of, voice_for


class _Client:
    def __init__(self, status: int = 200, content: bytes = b"ID3fake-mp3"):
        self.status, self.content, self.calls = status, content, []

    def post(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return httpx.Response(self.status, content=self.content)


def test_language_from_script_for_every_supported_language():
    samples = {"te": "నమస్కారం", "hi": "नमस्ते", "ta": "வணக்கம்", "kn": "ನಮಸ್ಕಾರ", "ml": "നമസ്കാരം",
               "bn": "নমস্কার", "gu": "નમસ્તે", "pa": "ਸਤ ਸ੍ਰੀ ਅਕਾਲ", "or": "ନମସ୍କାର", "ur": "السلام", "en": "Hello"}
    for code, text in samples.items():
        assert language_of(text) == code
        assert code in VOICES
    assert language_of("नमस्कार", "mr-IN") == "mr"  # shared Devanagari, locale decides
    assert language_of("১২৩ !") is None or language_of("১২৩ !") == "bn"
    assert language_of("123 !") is None


def test_voice_choice_and_override(monkeypatch):
    female, male = VOICES["te"]
    assert voice_for("te", "female") == female
    assert voice_for("te", "male") == male
    monkeypatch.setenv("ASKODOX_TTS_DEFAULT_GENDER", "male")
    assert voice_for("te", "automatic") == male
    monkeypatch.setenv("ELEVENLABS_VOICE_TE_MALE", "custom123")
    assert voice_for("te", "male") == "custom123"
    assert voice_for("sat", "male") is None  # Santali: no ElevenLabs voice -> caller falls back


def test_synthesize_sends_the_text_voice_and_model_then_caches():
    client = _Client()
    tts = ElevenLabsTTS("k", client=client, model="eleven_v3")
    first = tts.synthesize("నమస్కారం   ASKODOX", voice="male")
    assert first["success"] and first["language_code"] == "te" and first["mime_type"] == "audio/mpeg"
    url, kwargs = client.calls[0]
    assert VOICES["te"][1] in url
    assert kwargs["json"] == {"text": "నమస్కారం ASKODOX", "model_id": "eleven_v3"}
    assert kwargs["headers"]["xi-api-key"] == "k"
    again = tts.synthesize("నమస్కారం ASKODOX", voice="male")
    assert again["cache_hit"] and len(client.calls) == 1


def test_failures_are_results_not_exceptions():
    assert ElevenLabsTTS("", client=_Client()).synthesize("hi")["status"] == "ELEVENLABS_NOT_CONFIGURED"
    assert ElevenLabsTTS("k", client=_Client(402)).synthesize("hi")["status"] == "ELEVENLABS_QUOTA_EXHAUSTED"
    assert ElevenLabsTTS("k", client=_Client(401)).synthesize("hi")["status"] == "ELEVENLABS_AUTH_FAILED"
    assert ElevenLabsTTS("k", client=_Client(200, b"")).synthesize("hi")["status"] == "ELEVENLABS_EMPTY_AUDIO"

    class Boom:
        def post(self, *a, **k):
            raise httpx.ReadTimeout("slow")

    assert ElevenLabsTTS("k", client=Boom()).synthesize("hi")["status"] == "ELEVENLABS_TIMEOUT"


def test_key_comes_from_the_deployment_env(monkeypatch):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    monkeypatch.setenv("XI_API_KEY", "alias-key")
    assert elevenlabs_tts.api_key() == "alias-key"


def _speak_client(monkeypatch, eleven_result):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.routes.in_app_assistant import router

    class FakeEleven:
        configured = True

        def synthesize(self, text, voice="automatic", locale=""):
            return eleven_result

    class FakeSarvam:
        def synthesize(self, text, voice=""):
            return {"success": True, "tts_path": "sarvam_bulbul_v3_http_stream_opus", "content": b"OggS",
                    "model": "bulbul:v3", "mime_type": "audio/ogg", "language_code": "te-IN"}

    app = FastAPI()
    app.include_router(router)
    app.state.container = type("C", (), {"voice_assistant_service": FakeSarvam(), "elevenlabs_tts": FakeEleven()})()
    return TestClient(app)


def test_speak_route_uses_elevenlabs_first(monkeypatch):
    client = _speak_client(monkeypatch, {"success": True, "content": b"ID3mp3", "model": "eleven_v3",
                                         "language_code": "te", "status": "SYNTHESIZED_ELEVENLABS"})
    response = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te", "voice": "female"})
    assert response.status_code == 200
    assert response.headers["x-askodox-tts-path"] == "elevenlabs"
    assert response.headers["x-askodox-tts-model"] == "eleven_v3"
    assert response.headers["x-askodox-tts-voice"] == "female"
    assert response.content == b"ID3mp3"


def test_speak_route_falls_back_to_sarvam(monkeypatch):
    client = _speak_client(monkeypatch, {"success": False, "status": "ELEVENLABS_QUOTA_EXHAUSTED", "status_code": 402})
    response = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te"})
    assert response.status_code == 200
    assert response.headers["x-askodox-tts-model"].startswith("bulbul")
