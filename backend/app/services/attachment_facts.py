"""Turn ANY attachment analysis (image, video, document) into one short,
factual text the chat reasoning can use.

The image brain returns structured fields (subject, domain, brand, model,
visible_text ...), video returns visual_summary / spoken_transcript and
documents return summary / text / pages / sheets. Earlier the app only read
`summary`, which image analysis never has -- so a real photo reached the AI
as "Please inspect this attachment" with no facts. This module is the one
place that knows every shape. Only values the analysis actually produced are
used; nothing is invented.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List

_MAX = 1500


_PAGE_MARKER = re.compile(r"\[Page \d+\]")


def _text(value: Any) -> str:
    # "[Page 1]" markers alone (a PDF without a text layer) are not content.
    text = str(value or "").strip()
    if not _PAGE_MARKER.sub("", text).strip():
        return ""
    return "" if text.casefold() in {"", "null", "none", "unknown"} else " ".join(text.split())


def attachment_facts(kind: str, analysis: Dict[str, Any] | None) -> str:
    data = dict(analysis or {})
    parts: List[str] = []

    def add(label: str, value: Any) -> None:
        text = _text(value)
        if kind == "video":
            from app.services.pii_mask import mask

            text = mask(text)  # contacts in a video are shared only after consent
        if text and all(text not in p for p in parts):
            parts.append(f"{label}: {text}" if label else text)

    if kind == "image":
        add("Shows", data.get("subject"))
        add("Type", data.get("domain"))
        add("Brand", data.get("brand"))
        add("Model", data.get("model"))
        if data.get("quantity") not in (None, ""):
            add("Quantity", f"{data.get('quantity')} {_text(data.get('unit'))}".strip())
        if data.get("price") not in (None, ""):
            add("Price visible", f"{_text(data.get('currency'))} {data.get('price')}".strip())
        add("Visible text", data.get("visible_text"))
        add("Place", data.get("location_text"))
        constraints = [c for c in (data.get("constraints") or []) if _text(c)]
        if constraints:
            add("Details", ", ".join(_text(c) for c in constraints[:6]))
        side = _text(data.get("side")).upper()
        if side in {"NEED", "OFFER"}:
            add("The customer seems to", "want this" if side == "NEED" else "offer/sell this")
        add("Summary", data.get("summary"))
    elif kind == "video":
        add("Shows", data.get("subject"))
        add("Video shows", data.get("visual_summary") or data.get("summary"))
        add("Said in the video", data.get("spoken_transcript") or data.get("transcript"))
        add("Brand", data.get("brand"))
    else:
        add("Document", data.get("title") or data.get("document_type"))
        add("Summary", data.get("summary"))
        add("", _text(data.get("text")) or data.get("visible_text"))
        for page in (data.get("pages") or [])[:6]:
            if isinstance(page, dict):
                add("", page.get("text"))
        for sheet in (data.get("sheets") or [])[:3]:
            if not isinstance(sheet, dict):
                continue
            rows = [" | ".join(str(c) for c in row) for row in (sheet.get("rows") or [])[:15] if isinstance(row, list)]
            add(f"Sheet {_text(sheet.get('name'))}".strip(), "; ".join(rows))
    return "\n".join(parts)[:_MAX].strip()
