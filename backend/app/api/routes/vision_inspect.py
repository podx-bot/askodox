"""Vision Inspection API (evidence-tiered photo inspection for any domain).

POST /api/vision/inspect   1-4 photos + domain + mode -> report
GET  /api/vision/profiles  domains + capture guidance (the app keeps no copy)

Public like /api/attachments/analyze, rate-limited per client. The report
contract and the never-claim rules live in app/services/vision_inspection.py.
"""
from __future__ import annotations

import base64
import binascii
from typing import List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services import vision_inspection

router = APIRouter(prefix="/api/vision", tags=["Vision Inspection"])

MAX_IMAGE_BYTES = 12 * 1024 * 1024


class InspectImage(BaseModel):
    image_base64: str = Field(min_length=1, max_length=17_000_000)  # ~12 MB decoded
    mime_type: str = Field(default="image/jpeg", min_length=1, max_length=100)


class InspectRequest(BaseModel):
    images: List[InspectImage] = Field(min_length=1, max_length=4)
    domain: str = Field(default="general", max_length=40)
    mode: str = Field(default="quick", max_length=16)
    user_text: str = Field(default="", max_length=2000)
    language: str = Field(default="en", min_length=1, max_length=32)
    reference_object: str = Field(default="", max_length=120)


def _service(request: Request) -> vision_inspection.VisionInspectionService:
    container = request.app.state.container
    existing = getattr(container, "vision_inspection_service", None)
    if existing is not None:
        return existing
    image_service = getattr(container, "universal_image_service", None)
    if image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        raise HTTPException(status_code=503, detail="vision inspection is not available right now")
    service = vision_inspection.VisionInspectionService(image_service)
    try:
        container.vision_inspection_service = service
    except Exception:
        pass
    return service


@router.get("/profiles")
def inspection_profiles(language: str = "en") -> dict:
    return {
        "status": "success",
        "profiles": vision_inspection.profiles_for_app(language),
        "modes": [{"mode": key, "max_images": value["max_images"]} for key, value in vision_inspection.MODES.items()],
    }


@router.post("/inspect")
def inspect(payload: InspectRequest, request: Request) -> dict:
    from app.services import assistant_health, rate_limit

    rate_limit.check(request, "vision_inspect", limit=10)
    # The per-client key comes from X-Forwarded-For, which a caller can spoof:
    # a process-wide hourly cap bounds the paid model calls regardless.
    if not vision_inspection.global_budget_allows():
        raise HTTPException(status_code=429, detail="Photo inspection is busy -- please try again later")
    images = []
    for item in payload.images:
        mime = item.mime_type.strip().lower()
        if not mime.startswith("image/"):
            raise HTTPException(status_code=415, detail="only photos can be inspected")
        try:
            data = base64.b64decode(item.image_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise HTTPException(status_code=400, detail="invalid image data") from error
        if not data:
            raise HTTPException(status_code=400, detail="empty image")
        if len(data) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=413, detail="image too large (max 12 MB)")
        images.append((data, mime))
    service = _service(request)
    try:
        report = service.inspect(
            images,
            domain=payload.domain,
            mode=payload.mode,
            caption=payload.user_text.strip() or None,
            language=payload.language,
            reference_object=payload.reference_object.strip() or None,
        )
    except vision_inspection.InspectionUnavailable as error:
        assistant_health.observe("media_analysis", False)
        raise HTTPException(status_code=503 if error.model_calls == 0 else 502,
                            detail="vision inspection is not available right now") from error
    assistant_health.observe("media_analysis", True)
    return {"status": "success", "report": report, "facts": vision_inspection.report_facts(report),
            "language": payload.language}
