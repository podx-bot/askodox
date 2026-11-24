"""ElevenLabs reply voice -- human-sounding speech in the language of the text.

The owner found Sarvam Bulbul "sounds like a computer" (2026-10-28) and asked
for the voices most people actually use on ElevenLabs, per Indian language,
with fallbacks where ElevenLabs has no voice.

* ONE APP VOICE (owner 2026-11-23): every app reply and payment voice, in every
  language, is `APP_VOICE` ("Chaitra G" -- lively, expressive Telugu female; the
  multilingual model speaks the other languages with the same voice). The
  Profile Automatic / Male / Female choice and the payment-alert "2 male,
  2 female" picker are gone; old apps still send those words and the reply /
  payment route ignores them (`voice="automatic"`). A language that sounds
  wrong can get its own id with `ELEVENLABS_APP_VOICE_<LANG>` (or all with
  `ELEVENLABS_APP_VOICE`) without a code change.
* The gendered table (`VOICES` / `SECOND_VOICES`) stays ONLY for callers that
  name a gender on purpose (AI product videos: the presenter's gender) and as
  the list of languages ElevenLabs speaks. Staff override any of those ids with
  `ELEVENLABS_VOICE_<LANG>_<GENDER>` (e.g. `ELEVENLABS_VOICE_TE_MALE`).
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
import hashlib
import time
from collections import OrderedDict
from typing import Any, Dict, Optional

import httpx

API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
# Owner 2026-11-22 (30-40 s before the voice): eleven_v3 took 5-13 s per reply part in production (VOICE SPEAK ms).
# Eleven v4 Turbo is ElevenLabs' real-time model (~100 ms median, 90+ languages incl. Telugu); Flash v2.5 does not
# speak Telugu. Override with ELEVENLABS_TTS_MODEL. When the account refuses the fast model (400 / 404 / 422) the
# same text is made once with FALLBACK_MODEL and the fast model rests for MODEL_REST_SECONDS -- never no voice.
DEFAULT_MODEL = "eleven_v4_turbo"
FALLBACK_MODEL = "eleven_v3"
MODEL_REST_SECONDS = 1800.0
OUTPUT_FORMAT = "mp3_44100_64"
MAX_CHARS = 2500
MAX_AUDIO_BYTES = 3 * 1024 * 1024
CACHE_SIZE = 256
DISK_MAX_CHARS = 160

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

# A second (female, male) choice per language for the payment-alert voice picker (owner 2026-11-13: "2 male,
# 2 female"). Picked from the ElevenLabs library (Telugu / Hindi conversational voices, most used); a language
# missing here speaks the first pair. Staff override: ELEVENLABS_VOICE_<LANG>_FEMALE2 / _MALE2.
SECOND_VOICES: Dict[str, tuple[str, str]] = {
    "te": ("0UUTSkblTNnmKT570N79", "byBvnAtc0165IHbm4c7a"),  # Vijaya (clear, confident), Maddy (natural)
    "hi": ("broqrJkktxd1CclKTudW", "iWNf11sz1GrUE4ppxTOL"),  # Anika, Viraj
    "en": ("broqrJkktxd1CclKTudW", "iWNf11sz1GrUE4ppxTOL"),  # Anika, Viraj (Indian English)
}
VOICE_CHOICES = ("female", "male", "female2", "male2")

# Owner 2026-11-23 ("this female voice for all languages, remove the Automatic / Male / Female options"): the ONE
# voice the app speaks with, every language. ElevenLabs library voice "Chaitra G - Expressive & Lively Girl".
APP_VOICE = "oyjIr5XAhIyRjfNq6spl"


def app_voice_for(language: str) -> Optional[str]:
    """The app's one voice for a language ElevenLabs speaks (``None`` -> the caller falls back)."""
    if language not in VOICES:
        return None
    for name in (f"ELEVENLABS_APP_VOICE_{language.upper()}", "ELEVENLABS_APP_VOICE"):
        override = os.environ.get(name, "").strip()
        if override:
            return override
    return APP_VOICE

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
    """Voice id for a language. "automatic" (and anything that is not a gender) = the app's one voice; an explicit
    gender (male | female | male2 | female2) is only for callers that need one on purpose (product video presenter)."""
    pair = VOICES.get(language)
    if not pair:
        return None
    choice = (voice or "").strip().lower()
    if choice not in VOICE_CHOICES:
        return app_voice_for(language)
    override = os.environ.get(f"ELEVENLABS_VOICE_{language.upper()}_{choice.upper()}", "").strip()
    if override:
        return override
    second = choice.endswith("2")
    source = SECOND_VOICES.get(language, pair) if second else pair
    return source[0] if choice.startswith("female") else source[1]


class ElevenLabsTTS:
    """Text -> MP3 through ElevenLabs, cached per (voice, model, text)."""

    def __init__(self, key: Optional[str] = None, *, client: Optional[httpx.Client] = None,
                 model: Optional[str] = None, timeout_seconds: float = 8.0, cache_dir: Optional[str] = None) -> None:
        self._key = key
        self._client = client
        self.model = (model or os.environ.get("ELEVENLABS_TTS_MODEL", "") or DEFAULT_MODEL).strip()
        self.timeout_seconds = timeout_seconds
        self._cache: "OrderedDict[str, bytes]" = OrderedDict()
        # Owner 2026-11-21 (payment voice fell back to the phone voice): every MP3 ElevenLabs made is also kept on the
        # volume, so a name / amount spoken once is instant for every phone and after a restart (no second charge).
        self.cache_dir = cache_dir
        self._lock = threading.Lock()
        self._model_rest_until = 0.0  # monotonic time until which the configured model is skipped (it was refused)

    @property
    def configured(self) -> bool:
        return bool(self._key if self._key is not None else api_key())

    def _disk_path(self, cache_key: str) -> Optional[str]:
        if not self.cache_dir:
            return None
        digest = hashlib.sha256(cache_key.encode("utf-8")).hexdigest()[:40]
        return os.path.join(self.cache_dir, digest[:2], digest + ".mp3")

    def _disk_get(self, cache_key: str) -> Optional[bytes]:
        path = self._disk_path(cache_key)
        if not path:
            return None
        try:
            with open(path, "rb") as handle:
                data = handle.read()
            return data or None
        except OSError:
            return None

    def _disk_put(self, cache_key: str, audio: bytes) -> None:
        path = self._disk_path(cache_key)
        if not path:
            return
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = f"{path}.{os.getpid()}.part"
            with open(tmp, "wb") as handle:
                handle.write(audio)
            os.replace(tmp, path)
        except OSError:
            pass

    def synthesize(self, text: str, voice: str = "automatic", locale: str = "",
                   timeout_seconds: Optional[float] = None, keep: bool = False) -> Dict[str, Any]:
        """``keep`` = a fixed line every phone hears (a page guide, owner 2026-11-24 "record once, play to all"):
        kept on disk whatever its length, so it is made ONCE and then served from the volume."""
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
        model = self.model
        if model != FALLBACK_MODEL and time.monotonic() < self._model_rest_until:
            model = FALLBACK_MODEL
        result = self._synthesize_with(model, key, spoken, language, voice_id, timeout_seconds, keep)
        if (model != FALLBACK_MODEL and not result.get("success")
                and result.get("status_code") in (400, 404, 422)):
            # The account / voice does not take the fast model: say it with the model that always worked.
            with self._lock:
                self._model_rest_until = time.monotonic() + MODEL_REST_SECONDS
            print(f"ASKODOX VOICE MODEL refused model={model} status={result.get('status_code')} "
                  f"fallback={FALLBACK_MODEL}", flush=True)
            result = self._synthesize_with(FALLBACK_MODEL, key, spoken, language, voice_id, timeout_seconds, keep)
        return result

    def _synthesize_with(self, model: str, key: str, spoken: str, language: str, voice_id: str,
                         timeout_seconds: Optional[float], keep: bool = False) -> Dict[str, Any]:
        cache_key = f"{voice_id}:{model}:{spoken}"
        with self._lock:
            cached = self._cache.get(cache_key)
            if cached is not None:
                self._cache.move_to_end(cache_key)
        if cached is None:
            cached = self._disk_get(cache_key)
            if cached is not None:
                with self._lock:
                    self._cache[cache_key] = cached
                    while len(self._cache) > CACHE_SIZE:
                        self._cache.popitem(last=False)
        if cached is not None:
            return self._ok(cached, language, voice_id, cache_hit=True, elapsed_ms=0, model=model)
        started = time.perf_counter()
        client = self._client or httpx.Client()
        try:
            response = client.post(
                API_URL.format(voice_id=voice_id),
                params={"output_format": OUTPUT_FORMAT},
                headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
                json={"text": spoken, "model_id": model},
                timeout=httpx.Timeout(timeout_seconds or self.timeout_seconds, connect=3.0),
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
        if keep or len(spoken) <= DISK_MAX_CHARS:  # short lines repeat (payment names / amounts, guides); replies rarely do
            self._disk_put(cache_key, audio)
        return self._ok(audio, language, voice_id, cache_hit=False,
                        elapsed_ms=round((time.perf_counter() - started) * 1000), model=model)

    def _ok(self, audio: bytes, language: str, voice_id: str, *, cache_hit: bool, elapsed_ms: int,
            model: str = "") -> Dict[str, Any]:
        return {"success": True, "status": "SYNTHESIZED_ELEVENLABS_CACHE" if cache_hit else "SYNTHESIZED_ELEVENLABS",
                "content": audio, "mime_type": "audio/mpeg", "model": model or self.model, "voice_id": voice_id,
                "language_code": language, "tts_path": "elevenlabs", "cache_hit": cache_hit,
                "elapsed_ms": elapsed_ms}
