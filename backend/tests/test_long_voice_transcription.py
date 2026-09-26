"""Long Main Chat voice (30-120 s Telugu) must reach Sarvam complete.

Root cause this guards: Sarvam's synchronous REST STT only accepts audio
under 30 s. A 35 s recording was rejected, fell back to Gemini with a
256-token cap and thinking on, and came back as ~one word.

Test speech is amplitude-coded: word k is a 1.5 s square wave of amplitude
600 + 250*k followed by a short pause. The fake Sarvam decodes which words
it received, so order, loss and duplication are all observable.
"""
import io
import shutil
import subprocess
import wave
from array import array

import pytest

from app.services.audio_codec_service import AudioCodecService
from app.services.normalized_voice_assistant_service import transcription_config
from app.services.sarvam_tts_voice_assistant_service import SarvamTTSVoiceAssistantService

RATE = 16000
WORD_S, PAUSE_S = 1.5, 0.35


def speech_pcm(words: int, pause_s: float = PAUSE_S) -> bytes:
    samples = array("h")
    for k in range(words):
        amp = 600 + 250 * k
        samples.extend([amp if i % 2 else -amp for i in range(int(WORD_S * RATE))])
        samples.extend([0] * int(pause_s * RATE))
    return samples.tobytes()


def decode_words(pcm: bytes) -> list[str]:
    samples = array("h")
    samples.frombytes(pcm)
    words, run = [], []
    for value in list(samples) + [0]:
        if abs(value) > 200:
            run.append(abs(value))
            continue
        if len(run) >= int(0.25 * RATE):
            words.append(f"w{round((sum(run) / len(run) - 600) / 250)}")
        run = []
    return words


class FakeSarvam:
    """Mimics Sarvam REST STT, including its <30 s limit."""

    def __init__(self, fail_segment: int | None = None):
        self.requests = []
        self.fail_segment = fail_segment

    def post(self, url, headers=None, files=None, data=None, timeout=None):
        name, body, mime = files["file"]
        self.requests.append({"mime": mime, "bytes": len(body)})
        if mime != "audio/wav":
            return _Resp(200, {"transcript": "short-clip-original-bytes", "language_code": "te-IN"})
        with wave.open(io.BytesIO(body)) as wav:
            assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, RATE)
            pcm = wav.readframes(wav.getnframes())
            seconds = wav.getnframes() / RATE
        if seconds >= 30:
            return _Resp(400, {"error": "Audio duration exceeds 30 seconds"})
        if self.fail_segment is not None and len(self.requests) == self.fail_segment:
            return _Resp(500, {"error": "boom"})
        return _Resp(200, {"transcript": " ".join(decode_words(pcm)), "language_code": "te-IN"})


class _Resp:
    def __init__(self, status, payload):
        self.status_code, self._payload = status, payload
        self.text = str(payload)

    def json(self):
        return self._payload


class PcmCodec:
    """Returns the test PCM as if ffmpeg had decoded the upload."""

    def __init__(self, pcm):
        self.pcm = pcm

    def audio_to_pcm16(self, audio_bytes, sample_rate=16000):
        return {"success": True, "pcm": self.pcm, "sample_rate": sample_rate}

    def audio_to_wav(self, audio_bytes):
        return {"success": False, "status": "UNUSED"}


def service(pcm=None, sarvam=None, codec=None):
    svc = SarvamTTSVoiceAssistantService(
        sarvam_api_key="test-sarvam", api_key="", audio_codec_service=codec or PcmCodec(pcm),
    )
    svc._sarvam_http_client = sarvam or FakeSarvam()
    return svc


def expected(words):
    return " ".join(f"w{k}" for k in range(words))


@pytest.mark.parametrize("words,min_segments", [(19, 2), (32, 3), (64, 5)])  # ~35 s, ~60 s, ~118 s
def test_long_continuous_speech_reaches_stt_complete_and_in_order(words, min_segments):
    pcm = speech_pcm(words)
    sarvam = FakeSarvam()
    result = service(pcm, sarvam).transcribe(b"m4a-bytes", "audio/mp4")
    assert result["success"] is True
    assert result["transcript"] == expected(words), "no lost, reordered or duplicated words"
    assert result["segments"] >= min_segments and len(sarvam.requests) == result["segments"]
    assert result["audio_seconds"] == pytest.approx(len(pcm) / (2 * RATE), abs=0.01)


def test_segments_are_contiguous_under_limit_and_cut_in_pauses():
    pcm = speech_pcm(40)
    segments = SarvamTTSVoiceAssistantService.split_pcm_segments(pcm)
    assert b"".join(segments) == pcm, "every sample kept, in order"
    assert all(len(s) / (2 * RATE) < 30 for s in segments)
    offset = 0
    for segment in segments[:-1]:
        offset += len(segment) // 2
        window = array("h")
        window.frombytes(pcm[(offset - 80) * 2:(offset + 80) * 2])
        assert max(abs(v) for v in window) == 0, "cut falls inside a natural pause"


def test_speech_with_no_pauses_is_still_split_losslessly():
    pcm = array("h", [3000 if i % 2 else -3000 for i in range(70 * RATE)]).tobytes()
    segments = SarvamTTSVoiceAssistantService.split_pcm_segments(pcm)
    assert b"".join(segments) == pcm and all(len(s) / (2 * RATE) <= 28 for s in segments)


def test_short_telugu_or_english_clip_keeps_the_single_original_request():
    sarvam = FakeSarvam()
    result = service(speech_pcm(3), sarvam).transcribe(b"original-m4a", "audio/mp4")
    assert result["transcript"] == "short-clip-original-bytes"
    assert sarvam.requests == [{"mime": "audio/mp4", "bytes": len(b"original-m4a")}]
    assert result["segments"] == 1


def test_a_silent_stretch_between_sentences_is_not_a_failure():
    pcm = speech_pcm(10) + bytes(2 * RATE * 26) + speech_pcm(4)
    result = service(pcm).transcribe(b"x", "audio/mp4")
    assert result["success"] is True
    assert result["transcript"] == expected(10) + " " + expected(4)


def test_a_failed_segment_never_returns_a_partial_transcript():
    svc = service(speech_pcm(32), FakeSarvam(fail_segment=2))
    result = svc.transcribe(b"x", "audio/mp4")
    # Gemini fallback is not configured in this test, so the whole call fails
    # honestly instead of returning only the segments that succeeded.
    assert result["success"] is False
    assert "w0" not in str(result.get("transcript") or "")


def test_gemini_fallback_has_a_real_output_budget_and_no_thinking():
    config = transcription_config()
    assert config.max_output_tokens >= 2048
    assert config.thinking_config.thinking_budget == 0


@pytest.mark.skipif(shutil.which("ffmpeg") is None and not AudioCodecService._ffmpeg_exe(), reason="ffmpeg missing")
@pytest.mark.parametrize("seconds", [35, 60])
def test_real_android_style_m4a_decodes_to_its_full_duration(tmp_path, seconds):
    out = tmp_path / "rec.m4a"  # AAC in MP4 with the index at the end, like MediaRecorder
    subprocess.run([AudioCodecService._ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                    "-i", f"sine=frequency=300:sample_rate=16000:duration={seconds}", "-ac", "1", "-ar", "16000",
                    "-c:a", "aac", "-b:a", "64k", str(out)], check=True)
    decoded = AudioCodecService().audio_to_pcm16(out.read_bytes())
    assert decoded["success"] is True
    assert len(decoded["pcm"]) / (2 * RATE) == pytest.approx(seconds, abs=0.2)
    segments = SarvamTTSVoiceAssistantService.split_pcm_segments(decoded["pcm"])
    assert len(segments) >= 2 and all(len(s) / (2 * RATE) < 30 for s in segments)
    assert b"".join(segments) == decoded["pcm"]


def test_transcribe_endpoint_reports_safe_diagnostics(monkeypatch, tmp_path):
    from fastapi.testclient import TestClient

    from server import app, container

    pcm = speech_pcm(19)
    svc = service(pcm)
    monkeypatch.setattr(container, "voice_assistant_service", svc)
    body = TestClient(app).post("/api/in-app/voice/transcribe", data={"locale": "te"},
                                files={"audio": ("askodox_voice.m4a", b"fake-m4a", "audio/mp4")}).json()
    assert body["transcript"] == expected(19)
    diag = body["diagnostics"]
    assert diag["segments"] >= 2 and diag["transcript_words"] == 19 and diag["upload_bytes"] == len(b"fake-m4a")
    assert diag["path"] == "sarvam_primary_segmented"
    assert "w0" not in str(diag), "diagnostics carry counts only, never transcript text"
