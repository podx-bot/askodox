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


def test_one_app_voice_for_every_language(monkeypatch):
    """Owner 2026-11-23: one female voice (Chaitra G) for every language; no Automatic / Male / Female choice."""
    from app.services.elevenlabs_tts import APP_VOICE

    for name in ("ELEVENLABS_APP_VOICE", "ELEVENLABS_APP_VOICE_TA", "ASKODOX_TTS_DEFAULT_GENDER"):
        monkeypatch.delenv(name, raising=False)
    assert APP_VOICE == "oyjIr5XAhIyRjfNq6spl"
    for language in VOICES:
        assert voice_for(language, "automatic") == APP_VOICE
        assert voice_for(language, "") == APP_VOICE
    monkeypatch.setenv("ASKODOX_TTS_DEFAULT_GENDER", "male")  # the old default switch no longer changes anything
    assert voice_for("te", "automatic") == APP_VOICE
    monkeypatch.setenv("ELEVENLABS_APP_VOICE_TA", "tamil-only")  # one language that sounds wrong gets its own id
    assert voice_for("ta", "automatic") == "tamil-only" and voice_for("te", "automatic") == APP_VOICE
    monkeypatch.setenv("ELEVENLABS_APP_VOICE", "everyone")
    assert voice_for("te", "automatic") == "everyone" and voice_for("ta", "automatic") == "tamil-only"
    assert voice_for("sat", "automatic") is None  # Santali: no ElevenLabs voice -> caller falls back


def test_explicit_gender_stays_for_product_video_presenters(monkeypatch):
    female, male = VOICES["te"]
    monkeypatch.delenv("ELEVENLABS_VOICE_TE_MALE", raising=False)
    assert voice_for("te", "female") == female
    assert voice_for("te", "male") == male
    monkeypatch.setenv("ELEVENLABS_VOICE_TE_MALE", "custom123")
    assert voice_for("te", "male") == "custom123"
    assert voice_for("sat", "male") is None  # Santali: no ElevenLabs voice -> caller falls back


def test_second_voices_for_the_payment_alert_picker(monkeypatch):
    from app.services.elevenlabs_tts import SECOND_VOICES

    monkeypatch.delenv("ELEVENLABS_VOICE_TE_FEMALE2", raising=False)
    assert voice_for("te", "female2") == SECOND_VOICES["te"][0]
    assert voice_for("te", "male2") == SECOND_VOICES["te"][1]
    assert len({voice_for("te", v) for v in ("female", "male", "female2", "male2")}) == 4
    assert voice_for("ta", "male2") == VOICES["ta"][1]  # no second voice: the first pair speaks
    monkeypatch.setenv("ELEVENLABS_VOICE_TE_FEMALE2", "staff-picked")
    assert voice_for("te", "female2") == "staff-picked"


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


def test_default_model_is_the_real_time_one(monkeypatch):
    # Owner 2026-11-22: eleven_v3 took 5-13 s per reply part; the real-time model speaks Telugu too.
    monkeypatch.delenv("ELEVENLABS_TTS_MODEL", raising=False)
    client = _Client()
    tts = ElevenLabsTTS("k", client=client)
    result = tts.synthesize("నమస్కారం")
    assert elevenlabs_tts.DEFAULT_MODEL == "eleven_v4_turbo"
    assert client.calls[0][1]["json"]["model_id"] == "eleven_v4_turbo"
    assert result["model"] == "eleven_v4_turbo"


def test_a_refused_fast_model_falls_back_once_and_rests(monkeypatch):
    class Refuses:
        def __init__(self):
            self.calls = []

        def post(self, url, **kwargs):
            self.calls.append(kwargs["json"]["model_id"])
            if kwargs["json"]["model_id"] == "eleven_v4_turbo":
                return httpx.Response(400, content=b'{"detail": "model not available"}')
            return httpx.Response(200, content=b"ID3v3")

    monkeypatch.delenv("ELEVENLABS_TTS_MODEL", raising=False)
    client = Refuses()
    tts = ElevenLabsTTS("k", client=client)
    first = tts.synthesize("నమస్కారం")
    assert first["success"] and first["model"] == "eleven_v3"
    assert client.calls == ["eleven_v4_turbo", "eleven_v3"]
    second = tts.synthesize("ధన్యవాదాలు")  # the fast model rests: straight to the one that works
    assert second["success"] and client.calls[-1] == "eleven_v3" and len(client.calls) == 3
    # Quota / auth problems are not a model problem: no second model call.
    quota = ElevenLabsTTS("k", client=_Client(402))
    assert quota.synthesize("hi")["status"] == "ELEVENLABS_QUOTA_EXHAUSTED" and len(quota._client.calls) == 1


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


def test_speak_route_speaks_the_one_app_voice_whatever_an_old_app_asks(monkeypatch):
    """Owner 2026-11-23: old apps still send male / female2 ...; the reply / payment voice is always the app voice."""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.api.routes.in_app_assistant import router

    asked = []

    class RecordingEleven:
        configured = True

        def synthesize(self, text, voice="automatic", locale=""):
            asked.append(voice)
            return {"success": True, "content": b"ID3mp3", "model": "eleven_v4_turbo", "language_code": "te"}

    app = FastAPI()
    app.include_router(router)
    app.state.container = type("C", (), {"voice_assistant_service": None, "elevenlabs_tts": RecordingEleven()})()
    client = TestClient(app)
    for old_choice in ("male", "male2", "female2", "female", "automatic"):
        response = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "voice": old_choice})
        assert response.status_code == 200
        assert response.headers["x-askodox-tts-voice"] == old_choice  # echoed: the old app keeps the audio
    assert asked == ["automatic"] * 5


def test_speak_route_falls_back_to_sarvam(monkeypatch):
    client = _speak_client(monkeypatch, {"success": False, "status": "ELEVENLABS_QUOTA_EXHAUSTED", "status_code": 402})
    response = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te"})
    assert response.status_code == 200
    assert response.headers["x-askodox-tts-model"].startswith("bulbul")


def test_locked_elevenlabs_part_never_switches_to_sarvam(monkeypatch):
    """Owner 2026-11-21 ("2 voices"): later parts of one reply keep the engine of the first part."""
    client = _speak_client(monkeypatch, {"success": False, "status": "ELEVENLABS_TIMEOUT"})
    locked = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te", "engine": "elevenlabs"})
    assert locked.status_code == 503 and "ELEVENLABS_TIMEOUT" in locked.text
    free = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te"})
    assert free.status_code == 200 and free.headers["x-askodox-tts-model"].startswith("bulbul")


def test_sarvam_lock_skips_elevenlabs(monkeypatch):
    client = _speak_client(monkeypatch, {"success": True, "content": b"ID3mp3", "model": "eleven_v3",
                                         "language_code": "te", "status": "SYNTHESIZED_ELEVENLABS"})
    response = client.post("/api/in-app/voice/speak", json={"text": "నమస్కారం", "locale": "te", "engine": "sarvam"})
    assert response.status_code == 200 and response.headers["x-askodox-tts-model"].startswith("bulbul")
    assert client.post("/api/in-app/voice/speak", json={"text": "x", "engine": "other"}).status_code == 422


def test_locked_part_waits_longer_on_elevenlabs():
    client = _Client()
    tts = ElevenLabsTTS("k", client=client)
    tts.synthesize("హలో", timeout_seconds=20.0)
    assert client.calls[0][1]["timeout"].read == 20.0
    tts.synthesize("మరొకటి")
    assert client.calls[1][1]["timeout"].read == 8.0


def test_short_parts_are_kept_on_disk_for_every_phone(tmp_path):
    """Payment names / amounts made once are instant after a restart and for every phone (no second charge)."""
    client = _Client()
    ElevenLabsTTS("k", client=client, cache_dir=str(tmp_path)).synthesize("3000 రూపాయలు జమ అయ్యాయి.")
    fresh = ElevenLabsTTS("k", client=client, cache_dir=str(tmp_path))  # a new process
    again = fresh.synthesize("3000 రూపాయలు జమ అయ్యాయి.")
    assert again["success"] and again["cache_hit"] and len(client.calls) == 1
    long_text = "అ" * 400
    ElevenLabsTTS("k", client=client, cache_dir=str(tmp_path)).synthesize(long_text)
    ElevenLabsTTS("k", client=client, cache_dir=str(tmp_path)).synthesize(long_text)
    assert len(client.calls) == 3, "long replies are not kept on disk"
