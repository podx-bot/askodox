"""Main Chat voice upload reaches the Sarvam-first service with a real audio type."""
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes.in_app_assistant import _audio_mime_type, router


class _FakeVoice:
    def __init__(self, transcript="నాకు చికెన్ కావాలి"):
        self.transcript = transcript
        self.calls = []

    def transcribe(self, audio_bytes, mime_type):
        self.calls.append((audio_bytes, mime_type))
        return {"transcript": self.transcript, "provider": "sarvam"}


def _client(voice):
    app = FastAPI()
    app.include_router(router)
    app.state.container = type("C", (), {"voice_assistant_service": voice})()
    return TestClient(app)


def test_octet_stream_m4a_upload_is_sent_to_sarvam_as_audio_mp4():
    voice = _FakeVoice()
    response = _client(voice).post(
        "/api/in-app/voice/transcribe",
        files={"audio": ("askodox_voice.m4a", b"\x00\x01", "application/octet-stream")},
        data={"locale": "te"},
    )

    assert response.status_code == 200
    assert response.json()["transcript"] == "నాకు చికెన్ కావాలి"
    assert response.json()["locale"] == "te"
    assert voice.calls == [(b"\x00\x01", "audio/mp4")]


def test_empty_transcript_is_an_error_not_a_silent_success():
    response = _client(_FakeVoice(transcript="")).post(
        "/api/in-app/voice/transcribe",
        files={"audio": ("askodox_voice.m4a", b"\x00", "audio/mp4")},
    )
    assert response.status_code == 422


def test_audio_mime_inference():
    assert _audio_mime_type("audio/ogg; codecs=opus", "x.bin") == "audio/ogg"
    assert _audio_mime_type("application/octet-stream", "v.WAV") == "audio/wav"
    assert _audio_mime_type(None, None) == "audio/mp4"


class _FakeTTS:
    def __init__(self, result):
        self.result = result
        self.texts = []

    def synthesize(self, text):
        self.texts.append(text)
        return self.result


def test_speak_returns_sarvam_bulbul_v3_audio():
    tts = _FakeTTS({"success": True, "content": b"OggS...", "mime_type": "audio/ogg", "model": "bulbul:v3",
                    "tts_path": "sarvam_bulbul_v3_http_stream_opus", "language_code": "te-IN"})
    response = _client(tts).post("/api/in-app/voice/speak", json={"text": "సరే, ఎంత చికెన్?", "locale": "te"})

    assert response.status_code == 200
    assert response.content == b"OggS..."
    assert response.headers["content-type"].startswith("audio/ogg")
    assert response.headers["x-askodox-tts-model"] == "bulbul:v3"
    assert response.headers["x-askodox-tts-path"].startswith("sarvam")
    assert tts.texts == ["సరే, ఎంత చికెన్?"]


def test_speak_refuses_non_sarvam_paths_so_the_app_can_say_device_tts():
    gemini = _FakeTTS({"success": True, "content": b"RIFF", "tts_path": "gemini_compatibility_fallback"})
    failed = _FakeTTS({"success": False, "status": "SARVAM_TTS_NOT_CONFIGURED"})
    assert _client(gemini).post("/api/in-app/voice/speak", json={"text": "hi"}).status_code == 503
    response = _client(failed).post("/api/in-app/voice/speak", json={"text": "hi"})
    assert response.status_code == 503
    assert response.json()["detail"] == "SARVAM_TTS_NOT_CONFIGURED"
