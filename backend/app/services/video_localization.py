"""Language versions of an ASKODOX video's description (one-time, then saved).

Rules (owner, 2026-11-06):
- The staff's own Telugu / Tamil text always wins over machine text.
- A machine translation is made ONCE per (video, language), saved on the
  video row (`translations`, JSON) and served to every later viewer. Repeat
  viewers cost nothing.
- Only the staff's English description is translated; it is capped at
  MAX_CHARS so one call stays small. Translation failure never hides the
  original: the viewer gets English and an honest source label.
"""
from __future__ import annotations

import json
from typing import Any, Dict, Optional, Tuple

import httpx

SARVAM_TRANSLATE_URL = "https://api.sarvam.ai/translate"
TRANSLATE_MODEL = "mayura:v1"
MAX_CHARS = 1000
TIMEOUT_SECONDS = 8.0

# App language code -> Sarvam BCP-47 target code.
LANGUAGES = {
    "te": "te-IN", "ta": "ta-IN", "hi": "hi-IN", "kn": "kn-IN", "ml": "ml-IN",
    "gu": "gu-IN", "bn": "bn-IN", "mr": "mr-IN", "pa": "pa-IN", "od": "od-IN",
}


def supported(lang: str) -> bool:
    return lang in LANGUAGES


def cached_map(data: Dict[str, Any]) -> Dict[str, str]:
    raw = data.get("translations") or ""
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
    except (TypeError, ValueError):
        return {}
    return {str(k): str(v) for k, v in parsed.items() if isinstance(v, str) and v.strip()} if isinstance(parsed, dict) else {}


def translate(api_key: str, text: str, lang: str) -> Optional[str]:
    """One Sarvam translate call. None on any failure (never raises)."""
    target = LANGUAGES.get(lang)
    source = (text or "").strip()[:MAX_CHARS]
    if not api_key or not target or not source:
        return None
    body = {"input": source, "source_language_code": "en-IN", "target_language_code": target,
            "mode": "formal", "model": TRANSLATE_MODEL, "enable_preprocessing": False}
    try:
        response = httpx.post(SARVAM_TRANSLATE_URL, json=body, timeout=TIMEOUT_SECONDS,
                              headers={"api-subscription-key": api_key})
        if response.status_code != 200:
            return None
        out = str((response.json() or {}).get("translated_text") or "").strip()
        return out or None
    except Exception:
        return None


def describe(pf: Any, record: Dict[str, Any], lang: str, api_key: str) -> Tuple[str, str]:
    """(text, source) for one language. Source: original | staff | cached | ai | unavailable."""
    data = record.get("data") or {}
    english = str(data.get("description") or "").strip()
    if lang == "en" or not supported(lang):
        return english, "original"
    staff = str(data.get(f"description_{lang}") or "").strip()
    if staff:
        return staff, "staff"
    saved = cached_map(data).get(lang)
    if saved:
        return saved, "cached"
    if not english:
        return "", "unavailable"
    text = translate(api_key, english, lang)
    if not text:
        return english, "unavailable"
    merged = {**cached_map(data), lang: text}
    try:
        pf.resources.update("videos", record["id"], {"translations": json.dumps(merged, ensure_ascii=False)},
                            actor="system:video_localization")
    except Exception:
        # Still show the fresh text; it will be translated again next time.
        pass
    return text, "ai"
