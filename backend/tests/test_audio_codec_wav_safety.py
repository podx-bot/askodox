from types import SimpleNamespace
from unittest.mock import patch

from app.services.audio_codec_service import AudioCodecService


def test_empty_audio_is_rejected():
    assert AudioCodecService().audio_to_wav(b"")["status"] == "EMPTY_AUDIO"


def test_header_only_wav_is_not_success():
    svc = AudioCodecService()
    fake = SimpleNamespace(returncode=0, stdout=b"", stderr=b"")
    def fake_run(*args, **kwargs):
        # ffmpeg output file exists but contains only a header-like payload.
        output_path = args[0][-1]
        with open(output_path, "wb") as handle:
            handle.write(b"RIFF" + b"\\x00" * 74)
        return fake
    with patch("subprocess.run", side_effect=fake_run):
        result = svc.audio_to_wav(b"not-empty")
    assert result["success"] is False
    assert result["status"] == "EMPTY_WAV"
