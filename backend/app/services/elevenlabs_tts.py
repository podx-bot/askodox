"""ElevenLabs reply voice -- human-sounding speech in the language of the text.

The owner found Sarvam Bulbul "sounds like a computer" (2026-10-28) and asked
for the voices most people actually use on ElevenLabs, per Indian language,
with fallbacks where ElevenLabs has no voice.

* ONE voice table (`VOICES`): per language a female and a male voice, picked
  from the ElevenLabs voice library sorted by one-year usage, conversational /
  assistant voices preferred over audiobook or loan-recovery voices.
  Staff can override any id with `ELEVENLABS_VOICE_<LANG>_<GENDER>` (e.g.
  `ELEVENLABS_VOICE_TE_MALE`) without a code change.
* The language comes from the text's own script (same rule as Sarvam), so the
  voice always speaks the language that is on the screen.
* Languages ElevenLabs cannot speak (Bodo, Dogri, Kashmiri, Konkani,
  Maithili, Manipuri, Sanskrit, Santali) are never sent here; the caller falls
  back to Sarvam, then the phone's own voice.
* Never raises: every failure is a result with ``success=False`` and a status,
  so the route can fall back. The key is never logged or returned.
"""

from __future__ import annotations

import os
import threading
import time
from collections import OrderedDict
from typing import Any, Dict, Optional

import httpx

API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
# eleven_v3 is the ElevenLabs model that speaks Telugu and the other Indian
# languages (Flash v2.5 does not speak Telugu). Override with ELEVENLABS_TTS_MODEL.
DEFAULT_MODEL = "eleven_v3"
OUTPUT_FORMAT = "mp3_44100_64"
MAX_CHARS = 2500
MAX_AUDIO_BYTES = 3 * 1024 * 1024
CACHE_SIZE = 256

# (female, male) voice ids per ISO 639-1 language.
VOICES: Dict[str, tuple[str, str]] = {
    "te": ("4XvBGCPMXWyVQa75dbZg", "VFbICGvBSvKmHwlI9rzA"),  # Madhavi, Jayesh M
    "hi": ("KYiVPerWcenyBTIvWbfY", "ibbx9zDYGvLgtYzRbqqG"),  # Sia, Bunty (Smart Friendly Assistant)
    "en": ("KYiVPerWcenyBTIvWbfY", "nwj0s2LU9bDWRKND5yzA"),  # Sia, Bunty (Indian English)
    "ta": ("gCr8TeSJgJaeaIoV4RWH", "gJvkwI7wGFW2czmyfJhp"),  # Meera, Muthu
    "kn": ("2SDH0owxS12R2YMgMNoG", "K9wMnqOxfnDmtKBIH8oT"),  # Asiri, Srivatsa
    "ml": ("OPggdAvz9vtogYnK5Ge4", "ZDJM0nlhLoAeknyir3H0"),  # Samitha, Manikandan
    "bn": ("VixjjTLMa0rgjbAS8LTX", "FhOnCtjmaAIRIS1Dg2bk"),  # Madhusmita, Biju S
    "mr": ("ObcUVfo3RbQv9i2RBbAe", "rXW8MF4nX2gHMvBmCDnr"),  # Sayali, Vinayak
    "gu": ("1wX3DrX9Q7x2fkeiljyg", "v9ZPGDUUXnWEDCiJUQkk"),  # Hetalben, Jayesh Bhai
    "pa": ("KYiVPerWcenyBTIvWbfY", "ttyKbP9zTIRyRCN6b2Ye"),  # Sia (no Punjabi female listed), Yatin
    "or": ("Zcdoxp4Mfxbmk4fIwInk", "foG6Z7LGrkqvUz7pYqJy"),  # Barsha, Manohar
    "ur": ("o85TqPN3F4P7dWae2paA", "zT03pEAEi0VHKciJODfn"),  # Reva, Raju
    "as": ("VixjjTLMa0rgjbAS8LTX", "FhOnCtjmaAIRIS1Dg2bk"),  # closest: Bengali voices
    "ne": ("KYiVPerWcenyBTIvWbfY", "ibbx9zDYGvLgtYzRbqqG"),  # closest: Hindi voices
    "sd": ("o85TqPN3F4P7dWae2paA", "zT03pEAEi0VHKciJODfn"),  # closest: Urdu voices
}

# Indian scheduled languages ElevenLabs has no model for (fall back to Sarvam / device).
UNSUPPORTED = ("brx", "doi", "ks", "kok", "mai", "mni", "sa", "sat")

# Unicode script blocks -> language (first letter in a known script wins).
_SCRIPTS = (
    (0x0980, 0x09FF, "bn"),
    (0x0A00, 0x0A7F, "pa"),
    (0x0A80, 0x0AFF, "gu"),
    (0x0B00, 0x0B7F, "or"),
    (0x0B80, 0x0BFF, "ta"),
    (0x0C00, 0x0C7F, "te"),
    (0x0C80, 0x0CFF, "kn"),
    (0x0D00, 0x0D7F, "ml"),
    (0x0900, 0x097F, "hi"),
    (0x0600, 0x06FF, "ur"),
)

# Locale hints that change the language of a shared script (Devanagari, Bengali, Arabic).
_LOCALE_OVERRIDES = {"hi": {"mr", "ne"}, "bn": {"as"}, "ur": {"sd"}}


def language_of(text: str, locale: str = "") -> Optional[str]:
    """The language the text is written in (``None`` when no letters)."""
    hint = str(locale or "").strip().lower().replace("_", "-").split("-", 1)[0]
    for character in str(text or ""):
        codepoint = ord(character)
        for start, end, code in _SCRIPTS:
            if start <= codepoint <= end:
                return hint if hint in _LOCALE_OVERRIDES.get(code, ()) else code
    if any("a" <= c.lower() <= "z" for c in str(text or "")):
        return "en"
    return None


def api_key() -> str:
    try:
        from app.services.commerce_finance import env_value

        return env_value(dict(os.environ), "elevenlabs", "api_key")
    except Exception:
        return str(os.environ.get("ELEVENLABS_API_KEY", "") or "").strip()


def voice_for(language: str, voice: str = "automatic") -> Optional[str]:
    """Voice id for a language and the Profile choice (automatic | male | female)."""
    pair = VOICES.get(language)
    if not pair:
        return None
    choice = (voice or "").strip().lower()
    if choice not in ("male", "female"):
        choice = (os.environ.get("ASKODOX_TTS_DEFAULT_GENDER", "") or "female").strip().lower()
        if choice not in ("male", "female"):
            choice = "female"
    override = os.environ.get(f"ELEVENLABS_VOICE_{language.upper()}_{choice.upper()}", "").strip()
    return override or (pair[0] if choice == "female" else pair[1])


class ElevenLabsTTS:
    """Text -> MP3 through ElevenLabs, cached per (voice, model, text)."""

    def __init__(self, key: Optional[str] = None, *, client: Optional[httpx.Client] = None,
                 model: Optional[str] = None, timeout_seconds: float = 8.0) -> None:
        self._key = key
        self._client = client
        self.model = (model or os.environ.get("ELEVENLABS_TTS_MODEL", "") or DEFAULT_MODEL).strip()
        self.timeout_seconds = timeout_seconds
        self._cache: "OrderedDict[str, bytes]" = OrderedDict()
        self._lock = threading.Lock()

    @property
    def configured(self) -> bool:
        return bool(self._key if self._key is not None else api_key())

    def synthesize(self, text: str, voice: str = "automatic", locale: str = "") -> Dict[str, Any]:
        key = self._key if self._key is not None else api_key()
        if not key:
            return {"success": False, "status": "ELEVENLABS_NOT_CONFIGURED"}
        spoken = " ".join(str(text or "").split())[:MAX_CHARS]
        if not spoken:
            return {"success": False, "status": "EMPTY_TTS_TEXT"}
        language = language_of(spoken, locale)
        voice_id = voice_for(language or "", voice)
        if not language or not voice_id:
            return {"success": False, "status": "ELEVENLABS_UNSUPPORTED_LANGUAGE", "language_code": language or ""}
        cache_key = f"{voice_id}:{self.model}:{spoken}"
        with self._lock:
            cached = self._cache.get(cache_key)
            if cached is not None:
                self._cache.move_to_end(cache_key)
        if cached is not None:
            return self._ok(cached, language, voice_id, cache_hit=True, elapsed_ms=0)
        started = time.perf_counter()
        client = self._client or httpx.Client()
        try:
            response = client.post(
                API_URL.format(voice_id=voice_id),
                params={"output_format": OUTPUT_FORMAT},
                headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
                json={"text": spoken, "model_id": self.model},
                timeout=httpx.Timeout(self.timeout_seconds, connect=3.0),
            )
        except httpx.TimeoutException:
            return {"success": False, "status": "ELEVENLABS_TIMEOUT"}
        except Exception as error:  # network / DNS
            return {"success": False, "status": "ELEVENLABS_ERROR", "error_type": type(error).__name__}
        finally:
            if self._client is None:
                client.close()
        status_code = int(getattr(response, "status_code", 0) or 0)
        if status_code != 200:
            kind = {401: "AUTH_FAILED", 402: "QUOTA_EXHAUSTED", 429: "RATE_LIMITED"}.get(status_code, f"HTTP_{status_code}")
            return {"success": False, "status": f"ELEVENLABS_{kind}", "status_code": status_code}
        audio = bytes(response.content or b"")
        if not audio:
            return {"success": False, "status": "ELEVENLABS_EMPTY_AUDIO"}
        if len(audio) > MAX_AUDIO_BYTES:
            return {"success": False, "status": "ELEVENLABS_AUDIO_TOO_LARGE"}
        with self._lock:
            self._cache[cache_key] = audio
            while len(self._cache) > CACHE_SIZE:
                self._cache.popitem(last=False)
        return self._ok(audio, language, voice_id, cache_hit=False,
                        elapsed_ms=round((time.perf_counter() - started) * 1000))

    def _ok(self, audio: bytes, language: str, voice_id: str, *, cache_hit: bool, elapsed_ms: int) -> Dict[str, Any]:
        return {"success": True, "status": "SYNTHESIZED_ELEVENLABS_CACHE" if cache_hit else "SYNTHESIZED_ELEVENLABS",
                "content": audio, "mime_type": "audio/mpeg", "model": self.model, "voice_id": voice_id,
                "language_code": language, "tts_path": "elevenlabs", "cache_hit": cache_hit,
                "elapsed_ms": elapsed_ms}
