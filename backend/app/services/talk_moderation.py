"""Moderation for ASKODOX Talk (anonymous topic discussions, owner 2026-11-08).

Every message passes three checks before anyone sees it:

1. ``hide_contacts`` -- phone numbers, e-mails, links and @handles are
   replaced: Talk is anonymous, so nobody may pull someone out of it.
2. ``mask_words`` -- rude / unparliamentary words in English, Telugu (script
   and Latin spelling) and Hindi (Latin spelling) become ``****``; when the
   message is read aloud the app says "beep" in their place.
3. ``classify`` -- a model judges the WHOLE message for what a word list cannot
   catch (threats, hate against a group, sexual talk, scams / money requests,
   self-harm). Severe messages are held (not posted). No model -> a small
   severe-phrase fallback; nothing is ever posted unchecked.

The word lists are deliberately short and editable; the model is the real
judge. Nothing here stores who said what -- that is ``anonymous_talk``.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Callable, List, Optional

MASK = "****"

# Rude words. Latin entries match whole words after leetspeak is undone
# (0->o, 1->i, 3->e, 4->a, 5->s, @->a, $->s); script entries match anywhere.
_LATIN_WORDS = {
    # English
    "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "bitch", "bastard", "asshole", "dick",
    "pussy", "cunt", "slut", "whore", "wanker", "prick",
    # Hindi (Latin spelling)
    "chutiya", "chutiye", "madarchod", "behenchod", "bhenchod", "bhosdike", "bhosdi", "gandu", "harami",
    "randi", "lauda", "lavda", "lund", "gaand",
    # Telugu (Latin spelling)
    "lanja", "lanjakoduka", "dengu", "dengey", "dengutha", "puku", "modda", "gudda", "kojja", "sulli",
    "nakodaka", "nee amma", "nee yamma", "bewarse", "bevarse",
}
_SCRIPT_WORDS = (
    # Telugu script
    "లంజ", "దెంగ", "పూకు", "మొడ్డ", "గుద్ద", "కొజ్జ", "నీ అమ్మ", "బేవార్స్",
    # Hindi script
    "चूतिया", "मादरचोद", "बहनचोद", "भोसड़ी", "गांडू", "हरामी", "रंडी", "लौड़ा",
)

_LEET = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "@": "a", "$": "s"})

_PHONE = re.compile(r"(?<!\d)(?:\+?\d[\d\s\-().]{7,}\d)(?!\d)")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_LINK = re.compile(r"(?:https?://|www\.)\S+|\b[\w-]+\.(?:com|in|net|org|me|io|co|ly|link|app)\b(?:/\S*)?", re.I)
_HANDLE = re.compile(r"(?<![\w.])@[A-Za-z0-9_.]{3,}")

CATEGORIES = ("none", "threat", "hate", "sexual", "scam", "self_harm", "personal_info")
SEVERE = {"threat", "hate", "sexual", "scam", "personal_info"}

# Fallback when no model answers: only clear severe phrases (never a guess).
_SEVERE_FALLBACK = {
    "threat": ("i will kill", "kill you", "champutha", "champestha", "చంపేస్తా", "చంపుతా", "maar dunga",
               "jaan se maar"),
    "self_harm": ("kill myself", "end my life", "suicide", "chachipotha", "చచ్చిపోతా", "ఆత్మహత్య",
                  "आत्महत्या", "marna chahta"),
    "scam": ("send money", "pay first", "otp share", "share otp", "upi pin"),
}


@dataclass
class Verdict:
    text: str  # what others will see (masked, contacts hidden)
    visible: bool  # False = held, nobody else sees it
    category: str = "none"
    masked_words: int = 0
    contacts_hidden: int = 0
    checked_by: str = "rules"  # "model" when a model judged it
    notes: List[str] = field(default_factory=list)


def hide_contacts(text: str) -> tuple[str, int]:
    count = 0

    def sub(pattern: re.Pattern, value: str, label: str) -> str:
        nonlocal count

        def one(match: re.Match) -> str:
            nonlocal count
            # A phone number has at least 10 digits; years and prices stay.
            if pattern is _PHONE and sum(ch.isdigit() for ch in match.group(0)) < 10:
                return match.group(0)
            count += 1
            return label

        return pattern.sub(one, value)

    text = sub(_EMAIL, text, "[contact hidden]")
    text = sub(_LINK, text, "[link hidden]")
    text = sub(_PHONE, text, "[number hidden]")
    text = sub(_HANDLE, text, "[contact hidden]")
    return text, count


def mask_words(text: str) -> tuple[str, int]:
    hits = 0
    out = text
    for word in _SCRIPT_WORDS:
        if word in out:
            hits += out.count(word)
            out = out.replace(word, MASK)
    # Multi-word Latin entries first, then single words (whole-word, leetspeak undone).
    for phrase in sorted((w for w in _LATIN_WORDS if " " in w), key=len, reverse=True):
        pattern = re.compile(r"(?<![a-z])" + re.escape(phrase) + r"(?![a-z])", re.I)
        out, n = pattern.subn(MASK, out)
        hits += n

    def word_sub(match: re.Match) -> str:
        nonlocal hits
        raw = match.group(0)
        word = raw.lower().translate(_LEET)
        if word.strip("*") in _LATIN_WORDS:
            hits += 1
            return MASK
        if "*" in word and len(word) >= 3 and len(word.replace("*", "")) >= 2:
            # "f*ck", "sh**": stars standing in for letters of a listed word.
            shape = re.compile(re.escape(word).replace(r"\*", "."))
            if any(" " not in w and len(w) == len(word) and shape.fullmatch(w) for w in _LATIN_WORDS):
                hits += 1
                return MASK
        return raw

    out = re.sub(r"[A-Za-z0-9@$*]+", word_sub, out)
    return out, hits


_PROMPT = """You check one message in an anonymous public discussion app in India (Telugu, Hindi, English or mixed).
Reply with ONLY a JSON object: {{"category": "<one of: none, threat, hate, sexual, scam, self_harm, personal_info>"}}.
- threat: threatens violence or harm to someone.
- hate: attacks people for caste, religion, gender, region, disability or similar.
- sexual: sexual content or sexual advances.
- scam: asks for money, OTP, PIN, payments, or pushes a suspicious deal.
- self_harm: the writer talks about hurting or killing themselves.
- personal_info: shares or asks for someone's phone, address, real name, or tries to meet / contact outside the app.
- none: anything else, including disagreement, strong opinions and mild rudeness.
Message: {message}"""


def _model_category(text: str, write_text: Optional[Callable[..., str]]) -> Optional[str]:
    if not callable(write_text):
        return None
    try:
        raw = write_text(_PROMPT.format(message=json.dumps(text, ensure_ascii=False)), max_tokens=40) or ""
    except Exception:
        return None
    match = re.search(r"\{.*\}", raw, re.S)
    if not match:
        return None
    try:
        category = str(json.loads(match.group(0)).get("category") or "").strip().lower()
    except (ValueError, AttributeError):
        return None
    return category if category in CATEGORIES else None


def _fallback_category(text: str) -> str:
    low = text.lower()
    for category, phrases in _SEVERE_FALLBACK.items():
        if any(p in low for p in phrases):
            return category
    return "none"


def check(text: str, write_text: Optional[Callable[..., str]] = None) -> Verdict:
    """The full check for one message (see the module doc)."""
    clean = re.sub(r"\s+", " ", (text or "")).strip()
    shown, contacts = hide_contacts(clean)
    shown, masked = mask_words(shown)
    category = _model_category(clean, write_text)
    checked_by = "model"
    if category is None:
        category, checked_by = _fallback_category(clean), "rules"
    # A rule-matched severe phrase is never overruled by a model saying "none".
    if checked_by == "model" and category == "none":
        fallback = _fallback_category(clean)
        if fallback != "none":
            category = fallback
    visible = category not in SEVERE and category != "self_harm"
    return Verdict(text=shown, visible=visible, category=category, masked_words=masked,
                   contacts_hidden=contacts, checked_by=checked_by)


def spoken(text: str, te: bool) -> str:
    """The masked text as it is read aloud: every mask says "beep"."""
    return text.replace(MASK, " బీప్ " if te else " beep ").replace("  ", " ").strip()
