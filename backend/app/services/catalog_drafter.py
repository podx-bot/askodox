"""AI catalog assistant: seller text + photo/video analysis -> listing draft.

Reuses what already exists -- ``SellerListingAssistant.draft`` for the
seller's words and the structured output of ``/analyze`` (image) and
``/analyze-video`` -- and only ASSEMBLES facts that were actually present.
Nothing is invented: a field no source provided is listed in ``missing``
for the seller to fill before publishing.
"""
from __future__ import annotations

import re
from typing import Any

# Fields a seller should confirm before a listing is useful to buyers.
REVIEW_FIELDS = ("subject", "price", "stock_status", "location_label")


def _text(value: Any) -> str | None:
    text = " ".join(str(value or "").split())
    return text or None


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def build_draft(*, text: str = "", image_analysis: dict[str, Any] | None = None,
                video_analysis: dict[str, Any] | None = None, assistant=None,
                media_refs: list[str] | None = None) -> tuple[dict[str, Any], list[str], str]:
    """Returns (draft, missing_fields, source)."""
    image = dict(image_analysis or {})
    video = dict(video_analysis or {})
    spoken = _text(video.get("spoken_transcript"))
    words = " ".join(filter(None, [_text(text), spoken]))
    from_words: dict[str, Any] = {}
    if words and assistant is not None:
        try:
            from_words = assistant.draft(words)
        except ValueError:
            from_words = {}

    visual = image or {k: v for k, v in video.items() if k not in {"spoken_transcript"}}
    subject = _text(from_words.get("subject")) or _text(visual.get("subject"))
    brand, model = _text(visual.get("brand")), _text(visual.get("model"))
    title = " ".join(dict.fromkeys(p for p in (brand, subject, model) if p)) if subject else None
    summary = _text(visual.get("visual_summary") or visual.get("summary"))
    attributes = {k: v for k, v in {
        "brand": brand, "model": model,
        "quantity": _number(visual.get("quantity")), "unit": _text(from_words.get("unit") or visual.get("unit")),
    }.items() if v is not None}
    for item in visual.get("constraints") or []:
        key, _, value = str(item).partition(":")
        if value and key in {"color", "colour", "size", "material", "condition"}:
            attributes[key] = value.strip()
    keywords = sorted({w for w in re.findall(r"[a-z0-9]+", (title or "").lower()) if len(w) > 2})
    draft = {
        "subject": subject,
        "title": title,
        "description": summary,          # only the analysis' own description
        "category_tag": from_words.get("category_tag") or (_text(visual.get("domain")) or "").upper() or None,
        "price": _number(from_words.get("price")) or _number(visual.get("price")),
        "unit": attributes.get("unit"),
        "attributes": attributes,
        "keywords": keywords,
        "hashtags": [f"#{w}" for w in keywords[:6]],
        "media_refs": [m for m in (media_refs or []) if m],
        "stock_status": None,
        "location_label": None,
    }
    missing = [f for f in REVIEW_FIELDS if not draft.get(f)]
    source = "+".join(s for s, present in (("text", bool(_text(text))), ("photo", bool(image)),
                                            ("video", bool(video))) if present) or "text"
    return draft, missing, source
