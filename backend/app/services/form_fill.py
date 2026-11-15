"""Speak-to-fill (owner 2026-11-16: ONE mic at the bottom of a page; what is said fills the page's boxes).

The phone sends the page's boxes (key, label, kind) and the words the person said. This returns {key: value} for the
boxes the words actually state. Nothing is invented: a box the words do not mention is absent, and every value is
checked against its box (numbers only digits / decimal point, phone = 10 digits, choice = one of its options). The
model only maps words onto boxes; without a model a rule-based pass still fills phone numbers, one number box, and
"name <words>" style statements.
"""
from __future__ import annotations

import json
import re
from typing import Any, Callable, Dict, List, Optional

KINDS = ("text", "number", "phone", "choice")
_DIGIT_WORDS = {"zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
                "eight": "8", "nine": "9", "సున్నా": "0", "ఒకటి": "1", "రెండు": "2", "మూడు": "3", "నాలుగు": "4",
                "ఐదు": "5", "ఆరు": "6", "ఏడు": "7", "ఎనిమిది": "8", "తొమ్మిది": "9"}
_TE_DIGITS = str.maketrans("౦౧౨౩౪౫౬౭౮౯", "0123456789")


def _clean_fields(fields: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for raw in fields[:40]:
        key = str(raw.get("key") or "")[:60]
        if not key:
            continue
        kind = str(raw.get("kind") or "text")
        out.append({"key": key, "label": str(raw.get("label") or key)[:80], "kind": kind if kind in KINDS else "text",
                    "options": [str(o)[:40] for o in (raw.get("options") or [])][:20]})
    return out


def _digits(text: str) -> str:
    text = text.translate(_TE_DIGITS)
    spoken = " ".join(_DIGIT_WORDS.get(w, w) for w in re.split(r"\s+", text.lower()))
    return re.sub(r"[^0-9]", "", spoken)


def _number(value: Any) -> Optional[str]:
    text = str(value).translate(_TE_DIGITS).replace(",", "").strip()
    match = re.search(r"\d+(?:\.\d+)?", text)
    return match.group(0) if match else None


def _validate(fields: List[Dict[str, Any]], values: Dict[str, Any]) -> Dict[str, str]:
    by_key = {f["key"]: f for f in fields}
    out: Dict[str, str] = {}
    for key, value in values.items():
        field = by_key.get(key)
        if field is None or value is None or str(value).strip() == "":
            continue
        if field["kind"] == "number":
            number = _number(value)
            if number:
                out[key] = number
        elif field["kind"] == "phone":
            digits = _digits(str(value))
            if len(digits) >= 10:
                out[key] = digits[-10:]
        elif field["kind"] == "choice":
            wanted = str(value).strip().lower()
            for option in field["options"]:
                if option.lower() == wanted:
                    out[key] = option
                    break
        else:
            out[key] = str(value).strip()[:200]
    return out


def _rules(fields: List[Dict[str, Any]], text: str) -> Dict[str, Any]:
    values: Dict[str, Any] = {}
    phones = [f for f in fields if f["kind"] == "phone"]
    match = re.search(r"(?<!\d)(?:\d[\s-]?){10,12}(?!\d)", text.translate(_TE_DIGITS))
    if phones and match:
        values[phones[0]["key"]] = match.group(0)
    numbers = [f for f in fields if f["kind"] == "number"]
    if len(numbers) == 1:
        rest = re.sub(r"(?:\d[\s-]?){10,12}", " ", text.translate(_TE_DIGITS))
        found = _number(rest)
        if found:
            values[numbers[0]["key"]] = found
    texts = [f for f in fields if f["kind"] == "text"]
    if len(texts) == 1 and not values:
        values[texts[0]["key"]] = text
    return values


def fill(fields: List[Dict[str, Any]], text: str, *, locale: str = "te",
         phrase: Optional[Callable[[str], str]] = None) -> Dict[str, Any]:
    """-> {"values": {key: value}, "used_ai": bool}."""
    clean = _clean_fields(fields)
    said = str(text or "").strip()[:600]
    if not clean or not said:
        return {"values": {}, "used_ai": False}
    values: Dict[str, Any] = {}
    used_ai = False
    if phrase is not None:
        listing = "\n".join(f'- key "{f["key"]}": {f["label"]} ({f["kind"]}'
                            + (f'; one of: {", ".join(f["options"])}' if f["options"] else "") + ")" for f in clean)
        prompt = ("A person spoke to fill a form (language may be Telugu, English or mixed). Map ONLY what they actually "
                  "said onto these boxes. Never invent a value. Numbers as digits only. Phone as 10 digits. Names and "
                  "items as written by the person (Latin letters are fine). Answer with ONE JSON object {key: value} "
                  "and nothing else; leave out boxes they did not mention.\n"
                  f"Boxes:\n{listing}\nThey said: {said}")
        try:
            raw = phrase(prompt) or ""
            match = re.search(r"\{.*\}", raw, re.DOTALL)
            parsed = json.loads(match.group(0)) if match else {}
            if isinstance(parsed, dict):
                values, used_ai = parsed, True
        except Exception:
            values = {}
    checked = _validate(clean, values)
    if not checked and not used_ai:
        checked = _validate(clean, _rules(clean, said))
    return {"values": checked, "used_ai": used_ai}
