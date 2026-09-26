from __future__ import annotations

import io
import time
import wave
from array import array
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

import httpx

from app.services.files_fallback_voice_assistant_service import FilesFallbackVoiceAssistantService
from app.services.normalized_voice_assistant_service import _voice_diag


class SarvamPrimaryVoiceAssistantService(FilesFallbackVoiceAssistantService):
    """Use Sarvam Saaras v3 as fast India-first STT, then fall back to Gemini."""

    SARVAM_STT_URL = "https://api.sarvam.ai/speech-to-text"
    SARVAM_CONNECT_TIMEOUT_SECONDS = 2.5
    SARVAM_WRITE_TIMEOUT_SECONDS = 3.0
    SARVAM_POOL_TIMEOUT_SECONDS = 2.0
    TRANSCRIPT_LOG_PREVIEW_CHARS = 160
    # Sarvam's synchronous REST STT only accepts audio shorter than 30 s
    # (longer needs the Batch API). Recordings above SINGLE_REQUEST_MAX_SECONDS
    # are split into ~SEGMENT_TARGET_SECONDS pieces at the quietest point near
    # each boundary, transcribed in order and joined -- nothing is dropped.
    SINGLE_REQUEST_MAX_SECONDS = 28.0
    SEGMENT_TARGET_SECONDS = 25.0
    SEGMENT_SEARCH_SECONDS = 5.0
    SEGMENT_WINDOW_SECONDS = 0.2
    SEGMENT_PARALLELISM = 4
    PCM_SAMPLE_RATE = 16000

    def __init__(
        self,
        *args,
        sarvam_api_key: str = "",
        sarvam_model: str = "saaras:v3",
        sarvam_timeout_seconds: float = 8.0,
        **kwargs,
    ) -> None:
        super().__init__(*args, **kwargs)
        self.sarvam_api_key = str(sarvam_api_key or "").strip()
        self.sarvam_model = str(sarvam_model or "saaras:v3").strip()
        self.sarvam_timeout_seconds = max(float(sarvam_timeout_seconds or 8.0), 1.0)
        self._sarvam_timeout = httpx.Timeout(
            connect=self.SARVAM_CONNECT_TIMEOUT_SECONDS,
            read=self.sarvam_timeout_seconds,
            write=self.SARVAM_WRITE_TIMEOUT_SECONDS,
            pool=self.SARVAM_POOL_TIMEOUT_SECONDS,
        )
        self._sarvam_http_client = httpx.Client(
            timeout=self._sarvam_timeout,
            limits=httpx.Limits(
                max_connections=10,
                max_keepalive_connections=5,
                keepalive_expiry=30.0,
            ),
        )

    def transcribe(self, audio_bytes: bytes, mime_type: Optional[str]) -> dict[str, Any]:
        sarvam_result = self._transcribe_sarvam_complete(audio_bytes=audio_bytes, mime_type=mime_type)
        if sarvam_result.get("success"):
            return sarvam_result

        _voice_diag(
            "stage=sarvam_primary_fallback "
            f"status={sarvam_result.get('status')} "
            f"error_type={sarvam_result.get('error_type')} "
            f"request_ms={sarvam_result.get('request_ms')}"
        )
        fallback = super().transcribe(audio_bytes=audio_bytes, mime_type=mime_type)
        fallback["sarvam_status"] = sarvam_result.get("status")
        fallback["sarvam_error_type"] = sarvam_result.get("error_type")
        fallback["sarvam_request_ms"] = sarvam_result.get("request_ms")
        return fallback

    def _transcribe_sarvam_complete(self, audio_bytes: bytes, mime_type: Optional[str]) -> dict[str, Any]:
        """Whole-recording Sarvam transcription: one request for short audio
        (unchanged behaviour), ordered segments for anything longer."""
        if not self.sarvam_api_key or not audio_bytes:
            return self._transcribe_sarvam(audio_bytes=audio_bytes, mime_type=mime_type)
        codec = getattr(self, "audio_codec_service", None)
        decode = getattr(codec, "audio_to_pcm16", None)
        decoded = decode(audio_bytes, self.PCM_SAMPLE_RATE) if callable(decode) else {}
        pcm = decoded.get("pcm") if decoded.get("success") else None
        if not pcm:
            _voice_diag(f"stage=sarvam_duration unknown decode_status={decoded.get('status')} bytes={len(audio_bytes)}")
            return self._transcribe_sarvam(audio_bytes=audio_bytes, mime_type=mime_type)
        duration = len(pcm) / (2 * self.PCM_SAMPLE_RATE)
        if duration <= self.SINGLE_REQUEST_MAX_SECONDS:
            result = self._transcribe_sarvam(audio_bytes=audio_bytes, mime_type=mime_type)
            result["audio_seconds"] = round(duration, 2)
            result["segments"] = 1
            return result
        return self._transcribe_sarvam_segments(pcm, duration, len(audio_bytes))

    def _transcribe_sarvam_segments(self, pcm: bytes, duration: float, upload_bytes: int) -> dict[str, Any]:
        segments = self.split_pcm_segments(pcm)
        wavs = [self._wav_bytes(segment) for segment in segments]
        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=self.SEGMENT_PARALLELISM) as pool:
            results = list(pool.map(lambda wav: self._transcribe_sarvam(audio_bytes=wav, mime_type="audio/wav"), wavs))
        request_ms = round((time.perf_counter() - started) * 1000)
        parts: list[str] = []
        for index, result in enumerate(results):
            if result.get("success"):
                parts.append(str(result.get("transcript") or ""))
            elif result.get("status") == "SARVAM_EMPTY_TRANSCRIPT":
                continue  # a silent stretch between sentences
            else:
                _voice_diag(f"stage=sarvam_segments failed_segment={index + 1}/{len(segments)} status={result.get('status')}")
                return {**result, "status": result.get("status") or "SARVAM_SEGMENT_FAILED",
                        "segments": len(segments), "audio_seconds": round(duration, 2), "request_ms": request_ms}
        transcript = " ".join(part for part in parts if part).strip()
        if not transcript:
            return {"success": False, "status": "SARVAM_EMPTY_TRANSCRIPT", "segments": len(segments),
                    "audio_seconds": round(duration, 2), "request_ms": request_ms}
        languages = [r.get("language_code") for r in results if r.get("language_code")]
        _voice_diag(
            "stage=sarvam_segments success=True "
            f"audio_seconds={duration:.1f} upload_bytes={upload_bytes} segments={len(segments)} "
            f"segment_seconds={[round(len(s) / (2 * self.PCM_SAMPLE_RATE), 1) for s in segments]} "
            f"request_ms={request_ms} transcript_chars={len(transcript)} transcript_words={len(transcript.split())}"
        )
        return {
            "success": True,
            "status": "TRANSCRIBED_SARVAM",
            "transcript": transcript,
            "mime_type": "audio/wav",
            "model": self.sarvam_model,
            "language_code": languages[0] if languages else None,
            "transcription_path": "sarvam_primary_segmented",
            "segments": len(segments),
            "audio_seconds": round(duration, 2),
            "request_ms": request_ms,
            "transcript_chars": len(transcript),
        }

    @classmethod
    def split_pcm_segments(cls, pcm: bytes) -> list[bytes]:
        """Split 16-bit mono PCM into consecutive segments no longer than the
        REST limit, cutting at the quietest short window near each target
        boundary (a natural pause) so words are not cut. Segments are
        contiguous: concatenated they equal the input exactly."""
        rate = cls.PCM_SAMPLE_RATE
        samples = array("h")
        samples.frombytes(pcm[: len(pcm) - (len(pcm) % 2)])
        total = len(samples)
        target = int(cls.SEGMENT_TARGET_SECONDS * rate)
        search = int(cls.SEGMENT_SEARCH_SECONDS * rate)
        window = max(1, int(cls.SEGMENT_WINDOW_SECONDS * rate))
        cuts: list[int] = []
        start = 0
        while total - start > int(cls.SINGLE_REQUEST_MAX_SECONDS * rate):
            best, best_energy = start + target, None
            for window_start in range(start + target - search, start + target - window + 1, window // 2):
                energy = sum(abs(v) for v in samples[window_start:window_start + window])
                if best_energy is None or energy < best_energy:
                    best, best_energy = window_start + window // 2, energy
            cuts.append(best)
            start = best
        bounds = [0, *cuts, total]
        return [samples[a:b].tobytes() for a, b in zip(bounds, bounds[1:]) if b > a]

    @classmethod
    def _wav_bytes(cls, pcm: bytes) -> bytes:
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(cls.PCM_SAMPLE_RATE)
            out.writeframes(pcm)
        return buffer.getvalue()

    def _transcribe_sarvam(self, audio_bytes: bytes, mime_type: Optional[str]) -> dict[str, Any]:
        if not self.sarvam_api_key:
            return {"success": False, "status": "SARVAM_NOT_CONFIGURED", "request_ms": 0}
        if not audio_bytes:
            return {"success": False, "status": "SARVAM_EMPTY_AUDIO", "request_ms": 0}

        effective_mime = self._normalize_mime_type(mime_type)
        filename = "podx_voice" + self._suffix_for_mime(effective_mime)
        headers = {"api-subscription-key": self.sarvam_api_key}
        files = {"file": (filename, audio_bytes, effective_mime)}
        data = {
            "model": self.sarvam_model,
            "mode": "transcribe",
            "language_code": "unknown",
        }

        started = time.perf_counter()
        try:
            response = self._sarvam_http_client.post(
                self.SARVAM_STT_URL,
                headers=headers,
                files=files,
                data=data,
                timeout=self._sarvam_timeout,
            )
            request_ms = round((time.perf_counter() - started) * 1000)
            if response.status_code != 200:
                return {
                    "success": False,
                    "status": f"SARVAM_HTTP_{response.status_code}",
                    "error_type": "HTTPStatusError",
                    "error": response.text[:500],
                    "request_ms": request_ms,
                }

            payload = response.json()
            transcript = self._clean_transcript(str(payload.get("transcript") or ""))
            if not transcript:
                return {
                    "success": False,
                    "status": "SARVAM_EMPTY_TRANSCRIPT",
                    "language_code": payload.get("language_code"),
                    "language_probability": payload.get("language_probability"),
                    "request_ms": request_ms,
                }

            transcript_preview = self._transcript_log_preview(transcript)
            result = {
                "success": True,
                "status": "TRANSCRIBED_SARVAM",
                "transcript": transcript,
                "mime_type": effective_mime,
                "model": self.sarvam_model,
                "language_code": payload.get("language_code"),
                "language_probability": payload.get("language_probability"),
                "transcription_path": "sarvam_primary",
                "request_ms": request_ms,
                "transcript_chars": len(transcript),
            }
            _voice_diag(
                "stage=sarvam_primary success=True "
                f"language={result.get('language_code')} "
                f"language_probability={result.get('language_probability')} "
                f"bytes={len(audio_bytes)} mime={effective_mime} "
                f"request_ms={request_ms} transcript_chars={len(transcript)} "
                f"transcript_preview={transcript_preview!r}"
            )
            return result
        except httpx.TimeoutException as error:
            return {
                "success": False,
                "status": "SARVAM_TIMEOUT",
                "error_type": type(error).__name__,
                "request_ms": round((time.perf_counter() - started) * 1000),
            }
        except Exception as error:
            return {
                "success": False,
                "status": "SARVAM_TRANSCRIPTION_ERROR",
                "error_type": type(error).__name__,
                "error": str(error)[:500],
                "request_ms": round((time.perf_counter() - started) * 1000),
            }

    @classmethod
    def _transcript_log_preview(cls, transcript: str) -> str:
        compact = " ".join(str(transcript or "").split())
        return compact[: cls.TRANSCRIPT_LOG_PREVIEW_CHARS]
