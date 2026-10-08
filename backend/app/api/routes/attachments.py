"""ONE chat attachment endpoint for Camera / Photos / Video / Files.

POST /api/attachments/analyze
  {file_base64, filename, mime_type, user_text, language, conversation_id}
  -> {status, attachment: {id, kind, mime_type, size, filename, sha256},
      analysis, facts, language}

The MIME type decides the processor: image/* -> image brain, video/* ->
video brain, documents -> document reader. Unsupported types are refused
with 415 and a clear reason; a processor that is not available returns 503
-- never a pretend analysis. The raw bytes are NOT stored: only a metadata
record (hash, type, size, language, the analysis) that the chat keeps as the
attachment reference for history and admin traces.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.services.attachment_facts import attachment_facts

router = APIRouter(prefix="/api/attachments", tags=["attachments"])

LIMITS = {"image": 12 * 1024 * 1024, "video": 50 * 1024 * 1024, "document": 20 * 1024 * 1024}
DOCUMENT_TYPES = {
    "application/pdf", "text/plain", "text/csv", "application/json",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}
_EXTENSIONS = {
    "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp", "heic": "image/heic",
    "heif": "image/heif", "gif": "image/gif", "mp4": "video/mp4", "mov": "video/quicktime", "m4v": "video/mp4",
    "webm": "video/webm", "3gp": "video/3gpp", "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv",
    "json": "application/json",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}


def resolve_kind(filename: str, mime_type: str) -> tuple[str, str]:
    """(kind, mime) from the declared MIME, falling back to the extension
    (pickers often report application/octet-stream)."""
    mime = str(mime_type or "").strip().lower()
    if not mime or mime == "application/octet-stream":
        mime = _EXTENSIONS.get(str(filename or "").rsplit(".", 1)[-1].casefold(), mime or "application/octet-stream")
    if mime.startswith("image/"):
        return "image", mime
    if mime.startswith("video/"):
        return "video", mime
    if mime in DOCUMENT_TYPES:
        return "document", mime
    return "unsupported", mime


class AttachmentRequest(BaseModel):
    file_base64: str = Field(min_length=1)
    filename: str = Field(default="attachment", max_length=255)
    mime_type: str = Field(default="application/octet-stream", max_length=120)
    user_text: str = Field(default="", max_length=4000)
    language: str = Field(default="en", max_length=12)
    conversation_id: str = Field(default="", max_length=80)


def _store(container: Any) -> str:
    path = container.settings.database_path
    with sqlite3.connect(path) as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS chat_attachments (
                id TEXT PRIMARY KEY, sha256 TEXT NOT NULL, kind TEXT NOT NULL, mime_type TEXT NOT NULL,
                size INTEGER NOT NULL, filename TEXT, language TEXT, conversation_id TEXT,
                analysis_json TEXT NOT NULL, facts TEXT, created_at TEXT NOT NULL)"""
        )
    return path


@router.post("/analyze")
def analyze_attachment(payload: AttachmentRequest, request: Request) -> dict:
    """Records the real outcome for the Command Center (media_analysis):
    understood, or the processor failed / was unavailable. A refused file
    (unsupported type, too large, bad data) is the user's input, not a
    feature failure."""
    from app.services import assistant_health

    try:
        result = _analyze_attachment(payload, request)
    except HTTPException as error:
        if error.status_code in (422, 502, 503):
            assistant_health.observe("media_analysis", False,
                                     f"{resolve_kind(payload.filename, payload.mime_type)[0]}_http_{error.status_code}")
        raise
    assistant_health.observe("media_analysis", True)
    return result


def _analyze_attachment(payload: AttachmentRequest, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "attachments", limit=20)
    container = request.app.state.container
    kind, mime = resolve_kind(payload.filename, payload.mime_type)
    if kind == "unsupported":
        raise HTTPException(status_code=415, detail=f"ASKODOX cannot read this file type yet ({mime}). "
                                                    "Send a photo, a short video, PDF, Word, Excel, CSV or text file.")
    try:
        data = base64.b64decode(payload.file_base64, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail="invalid file data") from error
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > LIMITS[kind]:
        raise HTTPException(status_code=413, detail=f"{kind} too large (max {LIMITS[kind] // (1024 * 1024)} MB)")
    caption = payload.user_text.strip() or None
    analysis: dict | None
    if kind == "document":
        from app.services.universal_document_service import UniversalDocumentService

        service = getattr(container, "universal_document_service", None) or UniversalDocumentService()
        try:
            analysis = service.analyze(file_bytes=data, filename=payload.filename, mime_type=mime)
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(status_code=502, detail="document could not be read") from error
        # A scanned PDF has no text layer: read it with the multimodal brain.
        image_service = getattr(container, "universal_image_service", None)
        if mime == "application/pdf" and not attachment_facts("document", analysis) and image_service is not None \
                and hasattr(image_service, "analyze_pdf"):
            try:
                scanned = image_service.analyze_pdf(data, caption=caption)
            except Exception:
                scanned = None
            if scanned:
                analysis = {**analysis, **scanned, "scanned": True}
    else:
        if kind == "video":
            # The hard Video Study cap is checked from the file header BEFORE
            # any model call: a longer clip stays attached, unstudied.
            from app.services.video_study import clock, eligibility, mp4_duration_seconds

            duration = mp4_duration_seconds(data)
            gate = eligibility(duration, payload.language)
            if not gate["eligible"] and gate["reason"] == "too_long":
                record = {"id": "att_" + uuid.uuid4().hex[:20], "kind": kind, "mime_type": mime, "size": len(data),
                          "filename": payload.filename[:120], "sha256": hashlib.sha256(data).hexdigest()}
                note = f"Video attached ({clock(duration)}), not studied. {gate['message']}"
                return {"status": "success", "attachment": record,
                        "analysis": {"not_studied": True, "duration_seconds": int(duration)},
                        "facts": note, "understanding": {"method": "none", "status": "too_long"},
                        "video_study": {"ref": None, **gate, "status": "not_eligible"},
                        "language": payload.language}
        image_service = getattr(container, "universal_image_service", None)
        if image_service is None:
            raise HTTPException(status_code=503, detail=f"{kind} analysis is not available right now")
        try:
            analysis = (image_service.analyze(image_bytes=data, mime_type=mime, caption=caption) if kind == "image"
                        else image_service.analyze_video(video_bytes=data, mime_type=mime, caption=caption))
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"{kind} analysis failed") from error
        if kind == "video" and not analysis and getattr(image_service, "client", None) is None:
            raise HTTPException(status_code=503, detail="video analysis is not available right now")
    facts = attachment_facts(kind, analysis)
    if not analysis or not facts:
        raise HTTPException(status_code=422, detail=f"the {kind} could not be understood")
    record = {
        "id": "att_" + uuid.uuid4().hex[:20], "kind": kind, "mime_type": mime, "size": len(data),
        "filename": payload.filename[:120], "sha256": hashlib.sha256(data).hexdigest(),
    }
    try:
        with sqlite3.connect(_store(container)) as conn:
            conn.execute(
                "INSERT INTO chat_attachments (id, sha256, kind, mime_type, size, filename, language, conversation_id, "
                "analysis_json, facts, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (record["id"], record["sha256"], kind, mime, len(data), record["filename"], payload.language[:12],
                 payload.conversation_id[:80], json.dumps(analysis, default=str)[:20000], facts,
                 datetime.now(timezone.utc).isoformat()),
            )
    except sqlite3.Error:
        pass  # the analysis is still returned; only the reference record failed
    response = {"status": "success", "attachment": record, "analysis": analysis, "facts": facts,
                "understanding": understanding(kind, analysis, container), "language": payload.language}
    if kind == "video":
        response["video_study"] = _upload_study(container, record["sha256"], analysis, data, payload.language)
    return response


def _upload_study(container: Any, sha256: str, analysis: dict, data: bytes, language: str) -> dict:
    """The uploaded clip's study, from the SAME model call (no second cost).
    Only clips within the length cap; unknown length -> not studied."""
    from app.api.routes.platform import platform
    from app.services.video_study import eligibility, mp4_duration_seconds, suggested_questions

    duration = mp4_duration_seconds(data)
    gate = eligibility(duration, language)
    ref = "up_" + sha256[:20]
    if not gate["eligible"]:
        return {"ref": None, **gate, "status": "not_eligible"}
    try:
        study = platform(container).video_study.study_from_upload(ref, analysis, duration, language)
    except Exception:
        return {"ref": None, **gate, "status": "unavailable"}
    out = {"ref": ref, **gate, "status": study["status"], "summary": study.get("summary") or "",
           "facts_count": len(study.get("facts") or [])}
    if study["status"] == "ready":
        out["suggested_questions"] = suggested_questions(study, language)
    return out


def understanding(kind: str, analysis: dict, container: Any) -> dict:
    """How the content was understood -- reported honestly to the app.
    image: vision model + its confidence (low_confidence when below the
    service threshold); video: the whole clip (sampled frames + audio) by the
    multimodal model -- never a thumbnail; document: text layer or scan read."""
    if kind == "image":
        service = getattr(container, "universal_image_service", None)
        threshold = float(getattr(service, "min_confidence", 0.65) or 0.65)
        try:
            confidence = max(0.0, min(float(analysis.get("confidence") or 0.0), 1.0))
        except (TypeError, ValueError):
            confidence = 0.0
        return {"method": "vision", "confidence": round(confidence, 2),
                "status": "ok" if confidence >= threshold else "low_confidence"}
    if kind == "video":
        return {"method": "video_frames_and_audio", "status": "ok",
                "has_speech": bool(analysis.get("spoken_transcript") or analysis.get("transcript"))}
    return {"method": "scanned_read" if analysis.get("scanned") else "text_layer", "status": "ok"}
