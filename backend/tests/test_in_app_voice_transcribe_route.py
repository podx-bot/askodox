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
