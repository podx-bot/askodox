"""KYC routes (see app/services/kyc_engine.py).

Customer (signed in): GET /api/kyc/me, POST /api/kyc/consent, DELETE /api/kyc/consent,
POST /api/kyc/documents (photo / PDF / text the user chose -- read, masked, never stored raw),
GET /api/kyc/requirements/{activity}
Staff: GET /admin/cc/kyc/queue (kyc:view), POST /admin/cc/kyc/checks/{id}/review (kyc:approve, confirm)
"""
from __future__ import annotations

import base64
import binascii
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import kyc_engine

router = APIRouter(prefix="/api/kyc", tags=["kyc"])
admin_router = APIRouter(prefix="/admin/cc/kyc", tags=["command-center"])
MAX_BYTES = 12 * 1024 * 1024


def _err(error: kyc_engine.KycError) -> HTTPException:
    return HTTPException(status_code=error.status, detail=error.code)


@router.get("/me")
def my_kyc(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return kyc_engine.summary(request.app.state.container, user)


@router.get("/requirements/{activity}")
def requirement(activity: str, request: Request) -> dict:
    user = _authenticated_app_user(request)
    if activity not in kyc_engine.REQUIREMENTS:
        raise HTTPException(status_code=404, detail="Unknown activity")
    level = kyc_engine.summary(request.app.state.container, user)["level"]
    need = kyc_engine.REQUIREMENTS[activity]
    return {"activity": activity, "min_level": need, "level": level, "met": level >= need,
            "min_level_label": kyc_engine.LEVELS[need]}


class ConsentBody(BaseModel):
    accept: bool
    version: str = Field(default=kyc_engine.CONSENT_VERSION, max_length=40)


@router.post("/consent")
def give_consent(body: ConsentBody, request: Request) -> dict:
    user = _authenticated_app_user(request)
    if not body.accept or body.version != kyc_engine.CONSENT_VERSION:
        raise HTTPException(status_code=422, detail="Accept the current consent text to continue")
    if kyc_engine.phone_key(user) == kyc_engine.DEMO_KEY:
        raise HTTPException(status_code=403, detail="DEMO_ACCOUNT_NOT_ALLOWED")
    return {"consent": kyc_engine.store(request.app.state.container).grant(user)}


@router.delete("/consent")
def withdraw_consent(request: Request) -> dict:
    user = _authenticated_app_user(request)
    return {"withdrawn": True, "checks_deleted": kyc_engine.store(request.app.state.container).revoke(user)}


class DocumentBody(BaseModel):
    kind_hint: str = Field(default="", max_length=40)
    text: str = Field(default="", max_length=20000)
    file_base64: str = Field(default="", max_length=17_000_000)
    filename: str = Field(default="document", max_length=255)
    mime_type: str = Field(default="application/octet-stream", max_length=120)


def _document_text(container: Any, body: DocumentBody) -> str:
    """The same analysers as chat attachments, but nothing is stored."""
    if body.text.strip():
        return body.text
    if not body.file_base64:
        raise HTTPException(status_code=422, detail="Send a photo / PDF of the document")
    try:
        data = base64.b64decode(body.file_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=400, detail="invalid file data") from None
    if not data or len(data) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="file empty or larger than 12 MB")
    from app.api.routes.attachments import resolve_kind
    from app.services.attachment_facts import attachment_facts

    kind, mime = resolve_kind(body.filename, body.mime_type)
    try:
        if kind == "document":
            from app.services.universal_document_service import UniversalDocumentService

            service = getattr(container, "universal_document_service", None) or UniversalDocumentService()
            analysis = service.analyze(file_bytes=data, filename=body.filename, mime_type=mime)
            image_service = getattr(container, "universal_image_service", None)
            if mime == "application/pdf" and not attachment_facts("document", analysis) and image_service:
                analysis = {**analysis, **(image_service.analyze_pdf(data, caption="identity document") or {})}
        elif kind == "image":
            image_service = getattr(container, "universal_image_service", None)
            if image_service is None:
                raise HTTPException(status_code=503, detail="document reading is not available right now")
            analysis = image_service.analyze(image_bytes=data, mime_type=mime,
                                             caption="Read every printed field of this document exactly.")
        else:
            raise HTTPException(status_code=415, detail="Send a photo or a PDF")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=502, detail="the document could not be read") from None
    parts = [str((analysis or {}).get(k) or "") for k in ("text", "visible_text", "summary", "subject")]
    return "\n".join(p for p in parts if p) or attachment_facts(kind, analysis)


@router.post("/documents")
def submit_document(body: DocumentBody, request: Request) -> dict:
    from app.services import rate_limit

    user = _authenticated_app_user(request)
    rate_limit.check(request, "kyc_documents", limit=10)
    container = request.app.state.container
    if not kyc_engine.store(container).consent(user):
        raise HTTPException(status_code=428, detail="CONSENT_REQUIRED")
    text = _document_text(container, body)
    name = ""
    try:
        from app.repositories.user_profile_repository import UserProfileRepository

        name = str((UserProfileRepository(container.settings.database_path).get(user) or {}).get("name") or "")
    except Exception:
        pass
    try:
        return kyc_engine.submit(container, user, text, hint=body.kind_hint.strip(), profile_name=name)
    except kyc_engine.KycError as error:
        raise _err(error) from None


# ------------------------------------------------------------------ staff --

def _require(request: Request, permission: str) -> dict:
    from app.api.routes.command_center import _require as require

    return require(request, permission)


@admin_router.get("/queue")
def queue(request: Request) -> dict:
    """Documents waiting for staff (NEEDS_REVIEW) or for a provider. Masked values only."""
    _require(request, "kyc:view")
    kyc = kyc_engine.store(request.app.state.container)
    rows = kyc.checks(status="NEEDS_REVIEW") + kyc.checks(status="AWAITING_PROVIDER")
    for r in rows:
        r["staff_reviewable"] = kyc_engine.KINDS[r["kind"]]["staff_review"]
        r["label"] = kyc_engine.KINDS[r["kind"]]["label"]
    return {"items": rows, "providers": kyc_engine.summary(request.app.state.container, "")["providers"]}


class ReviewBody(BaseModel):
    decision: str = Field(pattern="^(approve|reject)$")
    note: str = Field(default="", max_length=300)
    confirm: bool = False


@admin_router.post("/checks/{check_id}/review")
def review_check(check_id: str, body: ReviewBody, request: Request) -> dict:
    principal = _require(request, "kyc:approve")
    if not body.confirm:
        raise HTTPException(status_code=409, detail="Confirmation required")
    try:
        check = kyc_engine.review(request.app.state.container, check_id, approve=body.decision == "approve",
                                  actor=f"staff:{principal.get('id')}", note=body.note)
    except kyc_engine.KycError as error:
        raise _err(error) from None
    try:
        from app.api.routes.command_center import command_center

        command_center(request.app.state.container).audit(principal["id"], "kyc.review", "kyc", check_id,
                                                          after={"decision": body.decision})
    except Exception:
        pass
    return {"check": check}
