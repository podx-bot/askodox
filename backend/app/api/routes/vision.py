from __future__ import annotations

import base64
import binascii

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

router = APIRouter(prefix="/vision", tags=["Vision"])


class VisionAnalyzeRequest(BaseModel):
    image_base64: str = Field(min_length=1)
    mime_type: str = Field(default="image/jpeg", min_length=1, max_length=100)
    user_text: str = Field(default="", max_length=4000)
    language: str = Field(default="en", min_length=1, max_length=32)


@router.post("/analyze")
def analyze_vision(payload: VisionAnalyzeRequest, request: Request) -> dict:
    """Analyze an app camera/gallery image with the production multimodal brain.

    This endpoint intentionally returns structured analysis only. The Flutter app
    merges that evidence into the same ASKODOX deal/OASAT flow it already started
    for the user's text request.
    """
    mime_type = payload.mime_type.strip().lower()
    if not mime_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="image mime_type required")

    try:
        image_bytes = base64.b64decode(payload.image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=400, detail="invalid image_base64")
    if not image_bytes:
        raise HTTPException(status_code=400, detail="empty image")
    if len(image_bytes) > 12 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="image too large")

    container = request.app.state.container
    image_service = getattr(container, "universal_image_service", None)
    if image_service is None:
        raise HTTPException(status_code=503, detail="vision service unavailable")

    try:
        analysis = image_service.analyze(
            image_bytes=image_bytes,
            mime_type=mime_type,
            caption=payload.user_text.strip() or None,
        )
    except Exception:
        raise HTTPException(status_code=502, detail="vision analysis failed")

    if not analysis:
        raise HTTPException(status_code=422, detail="image could not be understood")

    return {
        "status": "success",
        "analysis": analysis,
        "language": payload.language.strip(),
    }
