"""Photo edit / create for every signed-in customer (chat "+" photos + words).

ONE provider service (``container.openai_image_service``). Truth rules:
* No key, a provider failure or an empty answer -> ``ok: false`` with a code and
  a reason. Never a made-up or placeholder picture.
* Whether a message asks for an edit is decided by the photo-analysis model from
  the customer's own words (``image_request`` in /api/attachments/analyze), never
  by keyword lists here or in the app.
Cost guards: per-client rate limit and one AI Credits ``image`` use per picture
(given back when no picture comes out). Pay as you go: once staff turn AI Credits
charging ON with an ``image`` rate, a customer makes as many pictures as their
credits pay for (``free_per_day`` free ones first). While charging is OFF the
pictures are free, so a per-user daily cap applies (platform setting
``image_edit.daily_per_user``, counted from this table). That setting at 0 turns
the feature off in both modes.
"""
from __future__ import annotations

import base64
import binascii
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
import logging
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

router = APIRouter(prefix="/api/images", tags=["image-studio"])
_LOG = logging.getLogger("askodox.image_studio")

MAX_IMAGES = 4
MAX_BYTES = 8 * 1024 * 1024
_MAGIC = ((b"\xff\xd8\xff", "image/jpeg"), (b"\x89PNG", "image/png"), (b"RIFF", "image/webp"))


class ImageIn(BaseModel):
    data_base64: str = Field(min_length=8, max_length=12_000_000)


class StudioRequest(BaseModel):
    prompt: str = Field(min_length=3, max_length=1000)
    images: list[ImageIn] = Field(default_factory=list, max_length=MAX_IMAGES)
    language: str = Field(default="en", max_length=12)


def _connect(container: Any) -> sqlite3.Connection:
    conn = sqlite3.connect(container.settings.database_path, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("CREATE TABLE IF NOT EXISTS image_studio_uses (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, "
                 "kind TEXT NOT NULL, status TEXT NOT NULL, model TEXT, reason TEXT, images INTEGER NOT NULL, "
                 "created_at TEXT NOT NULL)")
    return conn


def _decode(images: list[ImageIn]) -> list[tuple[bytes, str]]:
    out: list[tuple[bytes, str]] = []
    for item in images:
        try:
            data = base64.b64decode(item.data_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise HTTPException(status_code=400, detail="invalid image data") from error
        if not data or len(data) > MAX_BYTES:
            raise HTTPException(status_code=413, detail="each photo must be under 8 MB")
        mime = next((m for magic, m in _MAGIC if data.startswith(magic)), "")
        if not mime:
            raise HTTPException(status_code=415, detail="photos must be JPEG, PNG or WebP")
        out.append((data, mime))
    return out


def _start(container: Any, user: str, kind: str, count: int, cap: int | None) -> tuple[str, int]:
    """Claims one of today's uses atomically (``cap`` None = no daily cap, credits
    decide). Returns (use id, used before this one); no id when the cap is reached."""
    use_id = "img_" + uuid.uuid4().hex[:20]
    now = datetime.now(timezone.utc)
    with closing(_connect(container)) as conn:
        conn.execute("BEGIN IMMEDIATE")
        used = int(conn.execute("SELECT COUNT(*) FROM image_studio_uses WHERE user_id = ? AND status IN "
                                "('pending', 'ok') AND substr(created_at, 1, 10) = ?",
                                (user, now.date().isoformat())).fetchone()[0])
        if cap is not None and used >= cap:
            conn.execute("ROLLBACK")
            return "", used
        conn.execute("INSERT INTO image_studio_uses (id, user_id, kind, status, images, created_at) VALUES "
                     "(?, ?, ?, 'pending', ?, ?)", (use_id, user, kind, count, now.isoformat()))
        conn.execute("COMMIT")
    return use_id, used


def _finish(container: Any, use_id: str, status: str, model: str = "", reason: str = "") -> None:
    with closing(_connect(container)) as conn:
        conn.execute("UPDATE image_studio_uses SET status = ?, model = ?, reason = ? WHERE id = ?",
                     (status, model, reason[:200], use_id))
        conn.commit()


def _no(code: str, reason: str, **extra: Any) -> dict:
    return {"ok": False, "code": code, "reason": reason, **extra}


@router.post("/edit")
async def edit_or_create(payload: StudioRequest, request: Request) -> dict:
    """With photos (in the order attached): edit them as the customer's words say
    -- the words name which photo changes. Without photos: make a new picture."""
    from app.api.routes.ai_credits import ai_credits
    from app.api.routes.in_app_deal import _authenticated_app_user
    from app.services import platform_settings, rate_limit
    from app.services.ai_credits import CreditsError

    user = _authenticated_app_user(request)
    rate_limit.check(request, "image_studio", limit=6)
    images = _decode(payload.images)
    container = request.app.state.container
    service = getattr(container, "openai_image_service", None)
    if service is None or not getattr(service, "configured", False):
        return _no("not_configured", "Photo editing is not switched on yet (no image provider key).")
    cap = int(platform_settings.get("image_edit.daily_per_user"))
    if cap <= 0:
        return _no("off", "Photo editing is switched off right now.")
    credits = ai_credits(container)
    pricing = credits.settings()
    pay_as_you_go = bool(pricing["charging"]) and int(pricing["rates_paise"].get("image", 0)) > 0
    daily_cap = None if pay_as_you_go else cap
    kind = "edit" if images else "create"
    use_id, used = _start(container, user, kind, len(images), daily_cap)
    if not use_id:
        return _no("daily_limit", f"Today's limit of {cap} pictures is used up. Try again tomorrow.",
                   daily_limit=cap, used_today=used)
    ref = f"image:{use_id}"
    try:
        charge = credits.reserve(user, "image", ref)
    except CreditsError as error:
        _finish(container, use_id, "refused", reason=error.code)
        if error.code == "insufficient":
            raise HTTPException(status_code=402, detail="AI_CREDITS_LOW") from None
        raise
    prompt = payload.prompt.strip()
    if images:
        result, reason = await run_in_threadpool(service.edit, images, prompt)
    else:
        result, reason = await run_in_threadpool(service.generate, prompt)
    if result is None:
        credits.release(user, ref)
        _finish(container, use_id, "failed", reason=reason)
        _LOG.warning("image_studio.failed kind=%s images=%d model=%s reason=%s", kind, len(images),
                     getattr(service, "model", ""), reason)
        return _no("provider_failed", "The picture could not be made this time. Please try again.",
                   detail=reason)
    _finish(container, use_id, "ok", model=result.model)
    return {"ok": True, "kind": kind, "mime_type": result.mime_type, "model": result.model,
            "image_base64": base64.b64encode(result.data).decode("ascii"),
            "daily_limit": daily_cap, "used_today": used + 1,
            "charged_paise": int(charge.get("paise") or 0) if charge.get("charged") else 0}


# ---- photo try-on (owner 2026-11-24): "how does this dress / chappal / frame / hairstyle look on ME", "how does this
# stove / TV / tile / paint colour look in MY home". Same provider, same cost guards and daily cap as edits above.
TRY_ON_MODES = ("on_me", "in_home")
# Items never put on a person's photo (Play policy + the owner's safe route, 2026-10-30): undress / revealing wear.
_BLOCKED_WEAR = ("innerwear", "inner wear", "lingerie", "bra ", "bra,", "bikini", "swimwear", "swimsuit", "underwear",
                 "panty", "panties", "brief", "nighty see", "transparent", "నైటీ ట్రాన్స్", "లోదుస్తు", "ఇన్నర్‌వేర్")
TRY_ON_LABEL = {"en": "AI picture — the real fit, size and colour may differ.",
                "te": "AI చిత్రం — నిజమైన ఫిట్, సైజ్, రంగు వేరుగా ఉండొచ్చు."}
_ON_ME = (
    "Image 1 is a photo of a real person. Image 2 shows a product{name}. Make ONE photorealistic picture of the SAME "
    "person from image 1 wearing / using that product. Keep the person exactly as they are: the same face and identity, "
    "expression, hair (unless the product IS a hairstyle), skin tone, body shape, age, pose, background and light. Change "
    "only where the product is worn: clothes replace that piece of clothing (modest, fully covering as in image 2), "
    "footwear on the feet, glasses / frames on the eyes, jewellery or a watch where it is worn, a hairstyle only the "
    "hair, makeup only the face's makeup. Keep the product's colour, pattern, print and design exactly as in image 2. "
    "Never make clothing more revealing, never change the body, add no text, logos or watermarks."
)
_IN_HOME = (
    "Image 1 is a photo of a real place (a room, wall, floor, table, kitchen counter, shop or vehicle). Image 2 shows a "
    "product{name}{size}. Make ONE photorealistic picture of the SAME place from image 1 with that product placed "
    "naturally where it would really go (a TV on the wall or a stand, a stove on the counter, tiles or paint on the "
    "floor / wall, furniture on the floor, a fitting where it fits) at a realistic size, matching the light, shadows "
    "and perspective. Keep everything else in image 1 unchanged. Keep the product's colour and design exactly as in "
    "image 2. Add no text, logos or watermarks."
)


class TryOnRequest(BaseModel):
    mode: str = Field(pattern="^(on_me|in_home)$")
    person_or_place: ImageIn
    item: ImageIn
    item_name: str = Field(default="", max_length=120)
    item_size: str = Field(default="", max_length=60)  # e.g. "55 inch", "3 burner, 70 cm" (the item's own details)
    consent: bool = False  # on_me: "this is my photo, or the person in it agreed"
    language: str = Field(default="te", max_length=12)


def try_on_prompt(mode: str, item_name: str = "", item_size: str = "") -> str:
    name = f" ({' '.join(item_name.split())[:120]})" if item_name.strip() else ""
    size = f", its real size: {' '.join(item_size.split())[:60]}" if item_size.strip() else ""
    return (_ON_ME if mode == "on_me" else _IN_HOME).format(name=name, size=size)


def blocked_item(item_name: str) -> bool:
    words = f" {' '.join(str(item_name or '').lower().split())} "
    return any(b in words for b in _BLOCKED_WEAR)


@router.post("/try-on")
async def try_on(payload: TryOnRequest, request: Request) -> dict:
    """Your photo (or your room's) + the item's photo -> how it looks. Never stored; labelled as an AI picture."""
    from app.api.routes.ai_credits import ai_credits
    from app.api.routes.in_app_deal import _authenticated_app_user
    from app.services import platform_settings, rate_limit
    from app.services.ai_credits import CreditsError

    user = _authenticated_app_user(request)
    rate_limit.check(request, "image_studio", limit=6)
    lang = "te" if payload.language.startswith("te") else "en"
    if payload.mode == "on_me" and not payload.consent:
        return _no("consent", "Use your own photo, or one the person in it agreed to." if lang == "en"
                   else "మీ ఫోటో, లేదా ఫోటోలో ఉన్నవాళ్ళు ఒప్పుకున్న ఫోటో మాత్రమే వాడండి.")
    if payload.mode == "on_me" and blocked_item(payload.item_name):
        return _no("blocked_item", "Try-on is not offered for this kind of item." if lang == "en"
                   else "ఈ రకం వస్తువుకి ట్రై-ఆన్ లేదు.")
    images = _decode([payload.person_or_place, payload.item])
    container = request.app.state.container
    service = getattr(container, "openai_image_service", None)
    if service is None or not getattr(service, "configured", False):
        return _no("not_configured", "Try-on is not switched on yet (no image provider key).")
    cap = int(platform_settings.get("image_edit.daily_per_user"))
    if cap <= 0:
        return _no("off", "Photo pictures are switched off right now.")
    credits = ai_credits(container)
    pricing = credits.settings()
    pay_as_you_go = bool(pricing["charging"]) and int(pricing["rates_paise"].get("image", 0)) > 0
    daily_cap = None if pay_as_you_go else cap
    use_id, used = _start(container, user, f"try_on_{payload.mode}", 2, daily_cap)
    if not use_id:
        return _no("daily_limit", f"Today's limit of {cap} pictures is used up. Try again tomorrow.",
                   daily_limit=cap, used_today=used)
    ref = f"image:{use_id}"
    try:
        charge = credits.reserve(user, "image", ref)
    except CreditsError as error:
        _finish(container, use_id, "refused", reason=error.code)
        if error.code == "insufficient":
            raise HTTPException(status_code=402, detail="AI_CREDITS_LOW") from None
        raise
    result, reason = await run_in_threadpool(service.edit, images,
                                             try_on_prompt(payload.mode, payload.item_name, payload.item_size))
    if result is None:
        credits.release(user, ref)
        _finish(container, use_id, "failed", reason=reason)
        _LOG.warning("image_studio.try_on_failed mode=%s model=%s reason=%s", payload.mode,
                     getattr(service, "model", ""), reason)
        return _no("provider_failed", "The picture could not be made this time. Please try again.", detail=reason)
    _finish(container, use_id, "ok", model=result.model)
    return {"ok": True, "kind": "try_on", "mode": payload.mode, "mime_type": result.mime_type, "model": result.model,
            "image_base64": base64.b64encode(result.data).decode("ascii"), "label": TRY_ON_LABEL[lang],
            "daily_limit": daily_cap, "used_today": used + 1,
            "charged_paise": int(charge.get("paise") or 0) if charge.get("charged") else 0}
