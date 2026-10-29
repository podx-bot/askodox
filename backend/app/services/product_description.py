"""AI-written product descriptions for staff-curated items (owner request
2026-10-29: staff should not have to write every description).

Facts only: the page fields staff saw (title, brand, price, category,
variants, keywords ...) plus what the photos show (the same multimodal image
brain as chat attachments). The model may not add a price, stock, offer,
warranty, delivery promise, rating or spec that is not in the facts. Output is
a DRAFT in English and in Telugu-English mixed; staff review it before saving.
"""
from __future__ import annotations

import json
import re
from typing import Any, Callable, Iterable

FACT_FIELDS = ("title", "brand", "category", "subcategory", "price", "mrp", "variants", "keywords", "seller",
               "colour", "color", "size", "material", "model", "offer_text")
_BANNED_WHEN_ABSENT = {
    "warranty": re.compile(r"warranty|వారంటీ", re.I),
    "delivery": re.compile(r"free delivery|fast delivery|same.day|డెలివరీ", re.I),
    "rating": re.compile(r"\b\d(?:\.\d)?\s*(?:star|★)|rated|రేటింగ్", re.I),
    "stock": re.compile(r"in stock|limited stock|స్టాక్", re.I),
}


def facts_from_fields(fields: dict[str, Any]) -> dict[str, str]:
    out = {}
    for key in FACT_FIELDS:
        value = fields.get(key)
        if value in (None, "", [], {}):
            continue
        if isinstance(value, (list, tuple)):
            value = ", ".join(str(v) for v in value[:10])
        out[key] = str(value)[:300]
    return out


def prompt(facts: dict[str, str], photo_facts: Iterable[str]) -> str:
    photos = [p for p in photo_facts if p]
    return (
        "Write a short product description for an Indian shopping app listing, as JSON with keys en and te.\n"
        "en: English, 1-2 short sentences then up to 4 bullet points (\"- \").\n"
        "te: the same in natural Telugu-English mixed (product / tech words stay English).\n"
        "Use ONLY the facts below. Do NOT add or guess a price, discount, stock, offer, warranty, delivery, rating, "
        "certification or any specification that is not stated. If facts are thin, write less. No emojis, no hype "
        "words like 'best' or 'No.1'.\n"
        f"Page facts: {json.dumps(facts, ensure_ascii=False)}\n"
        + (f"What the photos show: {json.dumps(photos[:3], ensure_ascii=False)}\n" if photos else "")
    )


def _parse(text: str) -> dict[str, str]:
    raw = str(text or "").strip()
    match = re.search(r"\{.*\}", raw, re.S)
    if match:
        try:
            data = json.loads(match.group(0))
            return {"en": str(data.get("en") or "").strip(), "te": str(data.get("te") or "").strip()}
        except ValueError:
            pass
    return {"en": raw, "te": ""}


def unsupported_claims(text: str, facts: dict[str, str], photo_facts: Iterable[str]) -> list[str]:
    """Claims the text makes that no fact supports (staff see these flagged)."""
    source = " ".join([*facts.values(), *[p for p in photo_facts if p]])
    return [name for name, pattern in _BANNED_WHEN_ABSENT.items() if pattern.search(text) and not pattern.search(source)]


def describe(fields: dict[str, Any], *, write: Callable[[str], str], photo_facts: Iterable[str] = ()) -> dict[str, Any]:
    facts = facts_from_fields(fields)
    photos = list(photo_facts)
    if not facts and not photos:
        return {"ok": False, "reason": "Add a title or a photo first"}
    text = write(prompt(facts, photos))
    if not text:
        return {"ok": False, "reason": "The AI did not answer -- try again or write it yourself"}
    parsed = _parse(text)
    flags = sorted(set(unsupported_claims(parsed["en"] + " " + parsed["te"], facts, photos)))
    return {"ok": True, "description_en": parsed["en"][:1500], "description_te": parsed["te"][:1500],
            "facts_used": facts, "photo_facts": photos[:3], "unsupported_claims": flags, "needs_review": True}
