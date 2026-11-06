"""OpenAI image edit / generation (fallback provider).

Truth rules:
* Calls OpenAI's Images API only when an API key is configured; without a key
  it returns None and never fabricates an image.
* The caller supplies the images and the prompt. Nothing here invents facts.
* Failures return None (plus a reason) so the caller can say "not available".
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
from typing import Any, Sequence

import httpx

IMAGES_EDIT_URL = "https://api.openai.com/v1/images/edits"
IMAGES_GENERATE_URL = "https://api.openai.com/v1/images/generations"
DEFAULT_MODEL = "gpt-image-2.5"
ALLOWED_SIZES = ("1024x1024", "1024x1536", "1536x1024")


@dataclass(frozen=True)
class ImageResult:
    data: bytes
    mime_type: str
    model: str


class OpenAIImageService:
    def __init__(self, api_key: str = "", model: str = DEFAULT_MODEL,
                 http_client: Any | None = None, timeout: float = 90.0) -> None:
        self.api_key = str(api_key or "").strip()
        self.model = str(model or DEFAULT_MODEL).strip() or DEFAULT_MODEL
        self.http = http_client or httpx.Client(timeout=timeout)

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    def edit(self, images: Sequence[tuple[bytes, str]], prompt: str,
             size: str = "1024x1024") -> tuple[ImageResult | None, str]:
        """Edit using 1..n reference images. Returns (result, reason)."""
        clean = [(data, str(mime or "image/jpeg").lower()) for data, mime in images if data]
        if not self.configured:
            return None, "OPENAI_API_KEY is not set"
        if not clean or not str(prompt or "").strip():
            return None, "an image and a prompt are required"
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
            return None, f"{type(error).__name__}"

    def generate(self, prompt: str, size: str = "1024x1024") -> tuple[ImageResult | None, str]:
        """Text-to-image. Returns (result, reason)."""
        if not self.configured:
            return None, "OPENAI_API_KEY is not set"
        if not str(prompt or "").strip():
            return None, "a prompt is required"
        try:
            response = self.http.post(
                IMAGES_GENERATE_URL,
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                json={"model": self.model, "prompt": str(prompt).strip(), "size": _size(size), "n": 1},
            )
            response.raise_for_status()
            return self._first_image(response.json())
        except Exception as error:
            return None, f"{type(error).__name__}"

    def _first_image(self, body: dict[str, Any]) -> tuple[ImageResult | None, str]:
        items = body.get("data") or []
        encoded = str(items[0].get("b64_json") or "") if items and isinstance(items[0], dict) else ""
        if not encoded:
            return None, "no image in the provider answer"
        return ImageResult(data=base64.b64decode(encoded), mime_type="image/png", model=self.model), ""


def _size(size: str) -> str:
    return size if size in ALLOWED_SIZES else "1024x1024"


def _ext(mime: str) -> str:
    return {"image/png": "png", "image/webp": "webp"}.get(mime, "jpg")
