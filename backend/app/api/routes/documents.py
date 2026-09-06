from __future__ import annotations

import base64
import binascii

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services.universal_document_service import UniversalDocumentService

router = APIRouter(prefix="/documents", tags=["Documents"])


class DocumentAnalyzeRequest(BaseModel):
    file_base64: str = Field(min_length=1)
    filename: str = Field(min_length=1, max_length=255)
    mime_type: str = "application/octet-stream"


@router.post("/analyze")
def analyze_document(payload: DocumentAnalyzeRequest, request: Request) -> dict:
    try:
        file_bytes = base64.b64decode(payload.file_base64, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail="Invalid base64 file data") from error

    if not file_bytes:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(file_bytes) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="File too large")

    service = getattr(request.app.state.container, "universal_document_service", None)
    if service is None:
        service = UniversalDocumentService()
    try:
        analysis = service.analyze(
            file_bytes=file_bytes,
            filename=payload.filename,
            mime_type=payload.mime_type,
        )
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="Document analysis failed") from error

    return {"status": "success", "analysis": analysis}
