from types import SimpleNamespace
from unittest.mock import patch

from app.services.audio_codec_service import AudioCodecService


def test_empty_audio_is_rejected():
    assert AudioCodecService().audio_to_wav(b"")["status"] == "EMPTY_AUDIO"


def _fake_ffmpeg(payload: bytes):
    fake = SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

    def fake_run(*args, **kwargs):
        with open(args[0][-1], "wb") as handle:  # ffmpeg's output file
            handle.write(payload)
        return fake
    return fake_run


def _header_only_wav() -> bytes:
    """The production case: a valid 16 kHz mono WAV header with zero audio
    frames (the fallback logged wav_bytes=78)."""
    import io
    import wave
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16000)
        out.writeframes(b"")
    data = buffer.getvalue()
    return data + b"\x00" * (78 - len(data))  # pad like ffmpeg's LIST chunk


def test_header_only_wav_is_not_success():
    with patch("subprocess.run", side_effect=_fake_ffmpeg(_header_only_wav())):
        result = AudioCodecService().audio_to_wav(b"not-empty")
    assert result["success"] is False
    assert result["status"] == "EMPTY_WAV"


def test_unparseable_wav_output_is_not_success():
    with patch("subprocess.run", side_effect=_fake_ffmpeg(b"RIFF" + b"garbage" * 40)):
        result = AudioCodecService().audio_to_wav(b"not-empty")
    assert result["success"] is False and result["status"] in {"INVALID_WAV", "EMPTY_WAV"}
