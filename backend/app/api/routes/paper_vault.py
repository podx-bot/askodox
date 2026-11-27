"""Bills & warranty: POST /api/me/vault/read -- a photo of a bill / warranty card -> its facts for the person to check.

Signed in; one AI Credits ``image`` use per read (free while charging is OFF; given back when nothing could be read).
Nothing is stored: the record and the photo stay on the person's own phone.
"""
from __future__ import annotations

import base64
from typing import Any, Dict, List
import uuid

from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from app.api.routes.ai_credits import ai_credits
from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import paper_vault, rate_limit
from app.services.ai_credits import CreditsError

router = APIRouter(tags=["vault"])


class VaultReadIn(BaseModel):
    images: List[Dict[str, Any]] = Field(default_factory=list, max_length=2)


@router.post("/api/me/vault/read")
async def vault_read(body: VaultReadIn, request: Request) -> dict:
    user = _authenticated_app_user(request)
    rate_limit.check(request, "vault-read", limit=20)
    photos = []
    for entry in body.images[:paper_vault.MAX_PHOTOS]:
        raw = str(entry.get("data") or "")
        if len(raw) > 6_000_000:
            raise HTTPException(status_code=413, detail="Photo too large. Use a smaller picture.")
        try:
            data = base64.b64decode(raw, validate=False)
        except Exception:
            raise HTTPException(status_code=400, detail="Photo could not be read.") from None
        mime = str(entry.get("mime") or "image/jpeg").lower()
        if mime not in ("image/jpeg", "image/png", "image/webp"):
            raise HTTPException(status_code=400, detail="Send a JPEG or PNG photo.")
        if data:
            photos.append((data, mime))
    if not photos:
        raise HTTPException(status_code=400, detail="Send a photo of the bill or the warranty card.")
    container: Any = request.app.state.container
    credits = ai_credits(container)
    ref = f"vault:{uuid.uuid4().hex}"
    try:
        credits.reserve(user, "image", ref)
    except CreditsError as error:
        if error.code == "insufficient":
            raise HTTPException(status_code=402, detail="AI_CREDITS_LOW") from None
        raise
    out = await run_in_threadpool(paper_vault.read_paper, getattr(container, "universal_image_service", None), photos)
    if not out["read"]:
        credits.release(user, ref)
    return out
