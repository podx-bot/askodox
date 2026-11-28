"""A real PowerPoint file for "make a presentation / PPT" asks (owner phone 2026-11-28: the chat gave only a slide
OUTLINE, never the file). The model writes the slides as JSON (one extra call, only when the person asked for a
presentation), python-pptx draws them, the file is kept 24 h under an unguessable token and the answer card gets a
download button. Nothing is stored about the person."""
from __future__ import annotations

import io
import json
import os
import re
import secrets
import time
from typing import Any

_ASK = re.compile(r"\b(ppt|pptx|power\s?point|presentation|slides?|slide\s?deck)\b|స్లైడ్|ప్రెజెంటేషన్|प्रेजेंटेशन|स्लाइड",
                  re.IGNORECASE)
_TOKEN = re.compile(r"^[0-9a-f]{32}$")
KEEP_SECONDS = 24 * 3600
MAX_SLIDES = 15
MAX_POINTS = 6

_PROMPT = """Write the slides of a presentation the person asked for. Return ONLY one JSON object, no markdown fence:
{"title": "deck title", "slides": [{"title": "short slide title", "points": ["short point", ...], "notes": "what to say"}]}
Rules: same language as the USER MESSAGE; 5 to 10 slides (the number the person asked for, if any); first slide =
title / intro, last slide = summary or next steps; 3 to 5 short points per slide (under 14 words each); notes = 2 to 3
sentences the speaker can say. Use real, correct content for the topic; never invent statistics, quotes or sources.

USER MESSAGE:
%(user)s

ANSWER ALREADY GIVEN (may be an outline; reuse its slides if it has them):
%(reply)s
"""


def wanted(user_text: str) -> bool:
    return bool(_ASK.search(str(user_text or "")))


def _parse(raw: str) -> dict[str, Any] | None:
    text = str(raw or "")
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        data = json.loads(text[start:end + 1], strict=False)
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def clean_slides(data: dict[str, Any] | None) -> tuple[str, list[dict[str, Any]]]:
    if not data:
        return "", []
    title = str(data.get("title") or "").strip()[:120]
    out: list[dict[str, Any]] = []
    for raw in (data.get("slides") or [])[:MAX_SLIDES]:
        if not isinstance(raw, dict):
            continue
        slide_title = str(raw.get("title") or "").strip()[:100]
        points = [str(p).strip()[:200] for p in (raw.get("points") or []) if isinstance(p, (str, int, float)) and str(p).strip()]
        if not slide_title and not points:
            continue
        out.append({"title": slide_title, "points": points[:MAX_POINTS], "notes": str(raw.get("notes") or "").strip()[:1200]})
    return title or (out[0]["title"] if out else ""), out


def slides_from_model(writer: Any, user_text: str, reply: str) -> tuple[str, list[dict[str, Any]]]:
    if writer is None:
        return "", []
    try:
        raw = writer(_PROMPT % {"user": str(user_text or "")[:1500], "reply": str(reply or "")[:4000]})
    except Exception:
        return "", []
    return clean_slides(_parse(raw))


def build_pptx(title: str, slides: list[dict[str, Any]]) -> bytes:
    from pptx import Presentation
    from pptx.util import Inches, Pt

    deck = Presentation()
    deck.slide_width, deck.slide_height = Inches(13.333), Inches(7.5)
    for index, slide in enumerate(slides):
        if index == 0:
            page = deck.slides.add_slide(deck.slide_layouts[0])
            page.shapes.title.text = slide["title"] or title
            if len(page.placeholders) > 1:
                page.placeholders[1].text = "\n".join(slide["points"][:2])
        else:
            page = deck.slides.add_slide(deck.slide_layouts[1])
            page.shapes.title.text = slide["title"]
            body = page.placeholders[1]
            body.left, body.top, body.width, body.height = Inches(0.9), Inches(1.7), Inches(11.5), Inches(5.2)
            frame = body.text_frame
            frame.clear()
            for n, point in enumerate(slide["points"]):
                para = frame.paragraphs[0] if n == 0 else frame.add_paragraph()
                para.text = point
                para.font.size = Pt(26)
        if slide["notes"]:
            page.notes_slide.notes_text_frame.text = slide["notes"]
    buffer = io.BytesIO()
    deck.save(buffer)
    return buffer.getvalue()


def folder(database_path: str) -> str:
    path = os.path.join(os.path.dirname(os.path.abspath(database_path)), "ppt_files")
    os.makedirs(path, exist_ok=True)
    return path


def store(database_path: str, data: bytes) -> str:
    base = folder(database_path)
    now = time.time()
    for name in os.listdir(base):  # forget old files
        full = os.path.join(base, name)
        try:
            if now - os.path.getmtime(full) > KEEP_SECONDS:
                os.remove(full)
        except OSError:
            pass
    token = secrets.token_hex(16)
    with open(os.path.join(base, token + ".pptx"), "wb") as handle:
        handle.write(data)
    return token


def read(database_path: str, token: str) -> bytes | None:
    if not _TOKEN.match(str(token or "")):
        return None
    full = os.path.join(folder(database_path), token + ".pptx")
    try:
        if time.time() - os.path.getmtime(full) > KEEP_SECONDS:
            return None
        with open(full, "rb") as handle:
            return handle.read()
    except OSError:
        return None


def make_download(writer: Any, database_path: str, base_url: str, user_text: str, reply: str,
                  *, telugu: bool = False) -> dict[str, str] | None:
    """A card action {kind, label, value} that downloads the deck, or None when the slides could not be made."""
    title, slides = slides_from_model(writer, user_text, reply)
    if len(slides) < 2:
        return None
    try:
        data = build_pptx(title, slides)
    except Exception:
        return None
    token = store(database_path, data)
    base = str(base_url or "").rstrip("/")
    if base.startswith("http://") and "localhost" not in base and "127.0.0.1" not in base:
        base = "https://" + base[len("http://"):]
    return {"kind": "open_url", "label": "PPT డౌన్‌లోడ్" if telugu else "Download PPT",
            "value": f"{base}/api/in-app/files/ppt/{token}"}
