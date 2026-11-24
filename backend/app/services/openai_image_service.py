"""OpenAI image edit / generation (fallback provider).

Truth rules:
* Calls OpenAI's Images API only when an API key is configured; without a key
  it returns None and never fabricates an image.
* The caller supplies the images and the prompt. Nothing here invents facts.
* Failures return None (plus a reason) so the caller can say "not available".
"""
from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from typing import Any, Sequence

import httpx

IMAGES_EDIT_URL = "https://api.openai.com/v1/images/edits"
IMAGES_GENERATE_URL = "https://api.openai.com/v1/images/generations"
DEFAULT_MODEL = "gpt-image-2.5-sunburst"  # OpenAI docs: gpt-image-1 shut down 2026-10-23
ALLOWED_SIZES = ("auto", "1024x1024", "1024x1536", "1536x1024")
# Owner 2026-11-24: the OpenAI account ran out of credits (HTTP 429 credit_balance_exhausted) and every AI picture /
# photo fallback failed. Gemini's image model (Nano Banana 2, GA 2026-05-28) is the second provider on the same
# GEMINI_API_KEY the app already uses: tried when OpenAI is not set or fails. Override with GEMINI_IMAGE_MODEL.
GEMINI_IMAGE_MODEL = "gemini-3.1-flash-image"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


@dataclass(frozen=True)
class ImageResult:
    data: bytes
    mime_type: str
    model: str


class OpenAIImageService:
    def __init__(self, api_key: str = "", model: str = DEFAULT_MODEL,
                 http_client: Any | None = None, timeout: float = 90.0, gemini_api_key: str = "",
                 gemini_model: str = "") -> None:
        self.api_key = str(api_key or "").strip()
        self.model = str(model or DEFAULT_MODEL).strip() or DEFAULT_MODEL
        self.http = http_client or httpx.Client(timeout=timeout)
        self.gemini_api_key = str(gemini_api_key or "").strip()
        self.gemini_model = str(gemini_model or os.getenv("GEMINI_IMAGE_MODEL") or GEMINI_IMAGE_MODEL).strip()

    @property
    def configured(self) -> bool:
        return bool(self.api_key or self.gemini_api_key)

    def edit(self, images: Sequence[tuple[bytes, str]], prompt: str,
             size: str = "auto") -> tuple[ImageResult | None, str]:
        """Edit using 1..n reference images: OpenAI first, Gemini when OpenAI is not set or fails."""
        clean = [(data, str(mime or "image/jpeg").lower()) for data, mime in images if data]
        if not clean or not str(prompt or "").strip():
            return None, "an image and a prompt are required"
        result, reason = self._openai_edit(clean, prompt, size)
        return (result, "") if result else self._gemini(prompt, clean, reason)

    def generate(self, prompt: str, size: str = "1024x1024") -> tuple[ImageResult | None, str]:
        """Text-to-image: OpenAI first, Gemini when OpenAI is not set or fails."""
        if not str(prompt or "").strip():
            return None, "a prompt is required"
        result, reason = self._openai_generate(prompt, size)
        return (result, "") if result else self._gemini(prompt, [], reason)

    def _gemini(self, prompt: str, images: Sequence[tuple[bytes, str]], before: str) -> tuple[ImageResult | None, str]:
        if not self.gemini_api_key:
            return None, before or "no image provider is set"
        parts: list[dict[str, Any]] = [{"text": str(prompt).strip()}]
        parts += [{"inline_data": {"mime_type": mime, "data": base64.b64encode(data).decode("ascii")}}
                  for data, mime in images]
        try:
            response = self.http.post(
                GEMINI_URL.format(model=self.gemini_model),
                headers={"x-goog-api-key": self.gemini_api_key, "Content-Type": "application/json"},
                json={"contents": [{"parts": parts}], "generationConfig": {"responseModalities": ["IMAGE"]}},
            )
            response.raise_for_status()
            for candidate in response.json().get("candidates") or []:
                for part in (candidate.get("content") or {}).get("parts") or []:
                    blob = part.get("inlineData") or part.get("inline_data") or {}
                    if blob.get("data"):
                        return ImageResult(data=base64.b64decode(blob["data"]),
                                           mime_type=str(blob.get("mimeType") or blob.get("mime_type") or "image/png"),
                                           model=self.gemini_model), ""
            return None, (before + "; " if before else "") + "gemini: no image in the answer"
        except Exception as error:
            return None, ((before + "; ") if before else "") + "gemini: " + _reason(error)

    def _openai_edit(self, clean: Sequence[tuple[bytes, str]], prompt: str, size: str) -> tuple[ImageResult | None, str]:
        if not self.api_key:
            return None, "OPENAI_API_KEY is not set"
        files = [("image[]", (f"image{i}.{_ext(mime)}", data, mime)) for i, (data, mime) in enumerate(clean)]
        try:
            response = self.http.post(
                IMAGES_EDIT_URL,
                headers={"Authorization": f"Bearer {self.api_key}"},
                data={"model": self.model, "prompt": str(prompt).strip(), "size": _size(size)},
                files=files,
            )
            response.raise_for_status()
            return self._first_image(response.json())
        except Exception as error:  # provider failure -> honest "no result"
            return None, _reason(error)

    def _openai_generate(self, prompt: str, size: str) -> tuple[ImageResult | None, str]:
        if not self.api_key:
            return None, "OPENAI_API_KEY is not set"
        try:
            response = self.http.post(
                IMAGES_GENERATE_URL,
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                json={"model": self.model, "prompt": str(prompt).strip(), "size": _size(size), "n": 1},
            )
            response.raise_for_status()
            return self._first_image(response.json())
        except Exception as error:
            return None, _reason(error)

    def _first_image(self, body: dict[str, Any]) -> tuple[ImageResult | None, str]:
        items = body.get("data") or []
        encoded = str(items[0].get("b64_json") or "") if items and isinstance(items[0], dict) else ""
        if not encoded:
            return None, "no image in the provider answer"
        return ImageResult(data=base64.b64decode(encoded), mime_type="image/png", model=self.model), ""


def _size(size: str) -> str:
    return size if size in ALLOWED_SIZES else "auto"


def _reason(error: Exception) -> str:
    """Short, secret-free reason: HTTP status + OpenAI's own error code / message."""
    response = getattr(error, "response", None)
    if response is None:
        return type(error).__name__
    detail = ""
    try:
        body = response.json().get("error") or {}
        detail = str(body.get("code") or body.get("type") or "") + ": " + str(body.get("message") or "")
    except Exception:
        detail = response.text[:200]
    return f"HTTP {response.status_code} {detail}".strip()[:300]


def _ext(mime: str) -> str:
    return {"image/png": "png", "image/webp": "webp"}.get(mime, "jpg")
