"""When the assistant must look things up live, how deep, and how honestly.

Owner report 2026-10-29: asked about a phone that launched days earlier
("Oppo Find X10"), the assistant called it fake / not released -- even after a
photo and an explicit "check the official website" -- because the live check
only ran for a fixed list of time words ("latest", "today", "news" ...). The
model's training memory is always behind new products, so this module decides
from the USER's own words (any category, any language):

* ``quick`` -- one live search: a product / model name (a letters+digits token
  such as X10, S25, 5070 Ti; or a capitalised name followed by a number such as
  "iPhone 17"), or an explicit "search / check online / official website" ask,
  or the older time-sensitive markers (``needs_live_verification``).
* ``deep`` -- several angles (launch / price / leaks / official): rumours,
  leaks, "coming soon", insider news, "is it real / released?" about a named
  model, or an explicit "deep search / research" ask.

Every source is labelled official / news / rumor / web so the reply can keep
confirmed facts and unconfirmed reports apart. Deterministic guards remove a
"fake / does not exist / not released" verdict or a claim of having searched
that no live evidence backs -- never a category rule, never per-brand text.
"""
from __future__ import annotations

import re
from typing import Any
from urllib.parse import urlparse

from app.services.runtime_time_context import needs_live_verification

# --------------------------------------------------------------- detection --

# Unit-like suffixes: "5kg", "2bhk", "10am" are quantities, not model names.
_UNIT_TOKEN = re.compile(
    r"^\d+(?:\.\d+)?(?:kg|kgs|g|gm|gms|mg|ml|l|ltr|ltrs|km|kms|m|cm|mm|ft|am|pm|hr|hrs|bhk|rs|k|st|nd|rd|th|"
    r"gb|tb|mb|mah|w|kw|v|hp|cc|in|inch|x|pcs|pc|yrs|yr|min|mins|sec|lakh|lakhs|cr|g)$",
    re.IGNORECASE)
# Letters and digits in ONE token (X10, S25, A55s, 5070Ti, M4) -- the usual
# shape of a model name in every category (phones, bikes, laptops, TVs, cars).
_MIXED_TOKEN = re.compile(r"(?<![\w-])(?=[A-Za-z]*\d)(?=\d*[A-Za-z])[A-Za-z0-9]{2,12}(?![\w-])")
# A capitalised name (or camelCase like iPhone) followed by a 1-4 digit number:
# "iPhone 17", "Pixel 11", "Note 15", "Activa 7".
_NAME_NUMBER = re.compile(r"\b((?:[A-Z][A-Za-z]+|[a-z]+[A-Z][A-Za-z]*))\s+(\d{1,4})\b(?!\s*(?:kg|g|gm|ml|l|ltr|km|"
                          r"rs|₹|members?|people|persons?|days?|hours?|hrs?|mins?|minutes?|years?|yrs?|months?|"
                          r"pieces?|pcs|items?|units?|am|pm|lakhs?|k|percent|%)\b)")
_COMMON_CAPITALS = {"I", "The", "A", "An", "My", "Is", "Are", "What", "When", "Where", "Which", "How", "Why",
                    "Please", "Show", "Find", "Need", "Want", "Give", "Tell", "Can", "Do", "Does", "Rs", "Top",
                    "Best", "Under", "Below", "Above", "Only", "Size", "Salary", "Price", "Budget", "Room",
                    "Flat", "Plot", "Day", "Week", "Month", "Year", "Class", "Page", "Step", "Point", "Option"}

_EXPLICIT_LOOKUP = (
    r"\bsearch\b", r"\bgoogle\b", r"\blook (?:it )?up\b", r"\bcheck (?:it )?online\b", r"\bcheck the (?:official )?"
    r"(?:website|site)\b", r"\bofficial (?:website|site|page|announcement)\b", r"\bwebsite\b", r"\bonline lo\b",
    r"\bvethuk", r"\bvetak", r"\bsearch chey", "వెతుకు", "వెతకండి", "వెతికి", "వెతకు", "సెర్చ్", "వెబ్సైట్",
    "వెబ్‌సైట్", "అఫీషియల్", "ఆన్‌లైన్‌లో చూడ", "ఆన్లైన్లో చూడ", "చెక్ చేయ", "చెక్ చేసి",
)
_DEEP_ASK = (
    r"\bdeep(?:ly)?\b", r"\bresearch\b", r"\bin detail\b", r"\bfull details\b", r"\ball details\b",
    "డీప్", "రీసెర్చ్", "పూర్తిగా వెతుకు", "పూర్తి వివరాలు", "లోతుగా",
)
_RUMOR = (
    r"\bleaks?\b", r"\bleaked\b", r"\brumou?rs?\b", r"\binsider\b", r"\btipped\b", r"\bupcoming\b",
    r"\bcoming soon\b", r"\blaunch date\b", r"\bwhen (?:will|does) .{0,40}\b(?:launch|release|come)\b",
    r"\bexpected\b", r"\bunannounced\b", r"\bteased?\b",
    "లీక్", "రూమర్", "పుకార్", "ఇన్సైడ్", "ఇన్సైడర్", "త్వరలో", "రాబోయే", "రాబోతున్న", "విడుదల ఎప్పుడు",
    "లాంచ్ ఎప్పుడు", "ఎప్పుడు వస్తుంది", "ఎప్పుడు రిలీజ్",
)
# A question about whether a named thing is real / out yet.
_EXISTENCE = (
    r"\breleased?\b", r"\blaunch(?:ed)?\b", r"\bis (?:it|this) real\b", r"\bfake\b", r"\bexists?\b",
    r"\bavailable in india\b", r"\bout yet\b",
    "రిలీజ్", "లాంచ్", "విడుదల", "నిజమా", "నిజంగా ఉందా", "ఫేక్", "వచ్చిందా", "ఉందా",
)


def _any(patterns: tuple[str, ...], text: str) -> bool:
    return any(re.search(p, text) for p in patterns)


def model_phrase(text: str) -> str:
    """The product / model name the user wrote ("Oppo Find X10"), or ''.

    Up to three Latin-script words before the model token and one after it
    (a variant such as Pro / Ultra / Max), taken from the user's own words."""
    raw = str(text or "")
    hits: list[tuple[int, int]] = []
    for match in _MIXED_TOKEN.finditer(raw):
        if not _UNIT_TOKEN.match(match.group(0)):
            hits.append(match.span())
    for match in _NAME_NUMBER.finditer(raw):
        if match.group(1) not in _COMMON_CAPITALS:
            hits.append(match.span())
    if not hits:
        return ""
    start, end = min(hits)
    before = re.findall(r"[A-Za-z][A-Za-z0-9+.-]*", raw[:start])[-3:]
    # Keep only the name run directly before the token (stop at a lower-case
    # filler word such as "about" / "the").
    run: list[str] = []
    for word in reversed(before):
        if word[0].isupper() or any(c.isdigit() for c in word) or word.casefold() in {"iphone", "ipad", "macbook"}:
            run.insert(0, word)
        else:
            break
    after = re.match(r"\s+(Pro\+?|Ultra|Max|Plus|Mini|Lite|Neo|Fold|Flip|Edge|Prime|FE|Ti|5G)\b", raw[end:], re.IGNORECASE)
    phrase = " ".join([*run, raw[start:end].strip()] + ([after.group(1)] if after else []))
    return " ".join(phrase.split())[:80]


def lookup_kind(user_text: str) -> str | None:
    """'deep', 'quick' or None for this message (the user's words only)."""
    text = str(user_text or "")
    lowered = text.casefold()
    if not lowered.strip() or text.startswith("OASAT "):
        return None
    phrase = model_phrase(text)
    if _any(_DEEP_ASK, lowered) or _any(_RUMOR, lowered):
        return "deep"
    if phrase and _any(_EXISTENCE, lowered):
        return "deep"
    if phrase or _any(_EXPLICIT_LOOKUP, lowered):
        return "quick"
    if needs_live_verification(text):
        return "quick"
    return None


def wants_official(user_text: str) -> bool:
    return bool(re.search(r"official|అఫీషియల్|అధికారిక", str(user_text or ""), re.IGNORECASE))


def deep_queries(base: str, *, official: bool = False) -> list[str]:
    """Bounded angles for one subject (max 4 queries; the deep service may add
    one follow-up when the evidence is thin)."""
    clean = " ".join(str(base or "").split())
    if not clean:
        return []
    angles = [clean, f"{clean} launch date price India", f"{clean} leak rumor", f"{clean} official"]
    if official:
        angles = [clean, f"{clean} official", f"{clean} launch date price India", f"{clean} leak rumor"]
    return angles


# ------------------------------------------------------------------ labels --

_RUMOR_TEXT = re.compile(
    r"\b(leak(?:s|ed)?|rumou?r(?:s|ed)?|tipped|tipster|reportedly|alleged(?:ly)?|could (?:launch|arrive|come)|"
    r"may (?:launch|arrive|come)|is expected|are expected|expected to|unconfirmed|insider|speculat\w*)\b",
    re.IGNORECASE)
_NEWS_HOST = re.compile(r"(news|times|today|express|hindu|mint|ndtv|reuters|bbc|cnn|verge|gsmarena|91mobiles|"
                        r"smartprix|techradar|engadget|androidauthority|businesstoday|moneycontrol|livemint|"
                        r"techadvisor|tbreak|telecomtalk|indianexpress|hindustantimes|firstpost|zeenews|"
                        r"economictimes|deccan|thequint|news18|india)", re.IGNORECASE)


def _brand_words(phrase: str) -> list[str]:
    words = re.findall(r"[A-Za-z]{3,}", str(phrase or ""))
    return [w.casefold() for w in words[:2]]


def label_source(source: dict[str, Any], phrase: str = "") -> str:
    """official / rumor / news / web -- from the source's own host and text."""
    url = str(source.get("url") or "")
    host = (urlparse(url).hostname or str(source.get("domain") or "")).casefold()
    host = host[4:] if host.startswith("www.") else host
    text = f"{source.get('title') or ''} {source.get('snippet') or ''}"
    stype = str(source.get("source_type") or "").casefold()
    registrable = host.split(".")[-2] if host.count(".") >= 1 else host
    if stype in {"government", "official", "primary", "documentation"}:
        return "official"
    if any(word and registrable.startswith(word) for word in _brand_words(phrase)):
        return "official"
    if _RUMOR_TEXT.search(text):
        return "rumor"
    if stype == "news" or _NEWS_HOST.search(host) or source.get("published_at"):
        return "news"
    return "web"


LABEL_TEXT = {
    "official": {"en": "✅ Official", "te": "✅ Official"},
    "news": {"en": "📰 News", "te": "📰 News"},
    "rumor": {"en": "🔮 Leak / Rumor (not confirmed)", "te": "🔮 Leak / Rumor (confirm కాలేదు)"},
    "web": {"en": "🌐 Web", "te": "🌐 Web"},
}


def evidence_block(sources: list[dict[str, Any]], *, deep: bool) -> str:
    lines = [
        f"[S{i}] ({src.get('label')}) {src.get('title')} | {src.get('url')} | published={src.get('published_at')} | "
        f"{src.get('snippet')}"
        for i, src in enumerate(sources, start=1)
    ]
    return (
        ("DEEP " if deep else "")
        + "LIVE WEB EVIDENCE (retrieved now for this question; each source is labelled official / news / rumor / web). "
        "Answer current, new-product and date-specific facts ONLY from this evidence, for the runtime year above, and "
        "cite source ids like [S1]. Keep labels apart: state OFFICIAL facts plainly; say NEWS facts are reported by that "
        "source; give a RUMOR / LEAK only as unconfirmed, naming the source and its date. If the evidence does not settle "
        "it, say so instead of guessing -- and never call the thing fake or non-existent because a source is missing.\n"
        + "\n".join(lines) + "\n"
    )


def sources_footer(sources: list[dict[str, Any]], locale: str, telugu: bool, limit: int = 4) -> str:
    """A short, tappable sources list under the reply (links render in the app;
    speech drops this block)."""
    if not sources:
        return ""
    lang = "te" if telugu else "en"
    rows = []
    order = {"official": 0, "news": 1, "rumor": 2, "web": 3}
    for src in sorted(sources, key=lambda s: order.get(str(s.get("label")), 9))[:limit]:
        url = str(src.get("url") or "")
        host = (urlparse(url).hostname or "").removeprefix("www.")
        if not url or not host:
            continue
        date = str(src.get("published_at") or "")[:10]
        label = LABEL_TEXT.get(str(src.get("label")), LABEL_TEXT["web"])[lang]
        rows.append(f"- {label} · [{host}]({url})" + (f" · {date}" if date else ""))
    if not rows:
        return ""
    heading = "**ఆధారాలు (Sources):**" if telugu else "**Sources:**"
    return "\n\n" + heading + "\n" + "\n".join(rows)


# ------------------------------------------------------------ honesty guard --

_NONEXISTENT = re.compile(
    r"(\bfake\b|\bcounterfeit\b|\bdoes(?:n'?t| not) exist\b|\bno such (?:phone|model|product|device)\b|"
    r"\bnot (?:been )?(?:yet )?(?:released|launched|announced)\b|\bhasn'?t (?:been )?(?:released|launched|announced)\b|"
    r"\bis not real\b|\bisn'?t real\b|\bnon-?existent\b|\bnot a real\b|"
    r"ఫేక్|నకిలీ|ఉనికిలో లేదు|విడుదల కాలేదు|రిలీజ్ కాలేదు|లాంచ్ కాలేదు|ఇంకా రాలేదు|అలాంటి (?:ఫోన్|మోడల్|ప్రొడక్ట్)[^.!?\n]{0,30}లేదు|"
    r"తప్పు అయి ఉండొచ్చు|నిజం కాదు)",
    re.IGNORECASE)
_CLAIMS_SEARCH = re.compile(
    r"(\bI (?:have )?(?:searched|checked|looked (?:it )?up|verified)\b|\b(?:on|in) (?:the|their) official "
    r"(?:website|site)\b[^.!?\n]{0,60}\b(?:no|not|nothing|isn'?t)\b|వెతికాను|వెతికి చూశాను|సెర్చ్ చేశాను|"
    r"చెక్ చేశాను|వెబ్‌?సైట్‌?లో (?:కూడా )?(?:లేదు|ప్రస్తావన))",
    re.IGNORECASE)
_SENTENCE = re.compile(r"[^.!?।\n]+[.!?।]?\s*")

HONEST_UNKNOWN = {
    "te": "ఈ model గురించి నా దగ్గర ఇంకా confirm అయిన సమాచారం లేదు. ఇది కొత్తగా వచ్చి ఉండొచ్చు, అందుకే fake అని చెప్పలేను. "
          "Official website లేదా నమ్మకమైన seller దగ్గర సరిచూసుకోండి.",
    "en": "I don't have confirmed information about this model yet. It may be new, so I can't say it is fake. "
          "Please check the official website or a trusted seller.",
}


def guard_reply(reply: str, *, verified: bool, telugu: bool) -> tuple[str, list[str]]:
    """Remove unbacked 'fake / not released' verdicts and unbacked claims of
    having searched. Returns (reply, reasons). With verified live evidence the
    model may report what the evidence says, so only the search claim is kept."""
    if verified:
        return reply, []
    reasons: list[str] = []
    kept: list[str] = []
    for sentence in _SENTENCE.findall(str(reply or "")):
        if _NONEXISTENT.search(sentence):
            reasons.append("unbacked_nonexistence")
            continue
        if _CLAIMS_SEARCH.search(sentence):
            reasons.append("unbacked_search_claim")
            continue
        kept.append(sentence)
    if not reasons:
        return reply, []
    text = "".join(kept).strip()
    note = HONEST_UNKNOWN["te" if telugu else "en"]
    if "unbacked_nonexistence" in reasons and note not in text:
        text = f"{text}\n\n{note}".strip()
    return text or note, sorted(set(reasons))


# ------------------------------------------------------------ knowledge gaps --

_CORRECTION = re.compile(
    r"(\b(?:that'?s|this is|you are|you're|it'?s) (?:wrong|not correct|incorrect)\b|\bwrong answer\b|"
    r"\bit (?:does|is) exist\b|\bit is real\b|\bit'?s real\b|\bit (?:has|was) (?:been )?(?:released|launched)\b|"
    r"\bnot fake\b|తప్పు|సరికాదు|అది ఉంది|ఉంది కదా|రిలీజ్ అయింది|లాంచ్ అయింది|వచ్చింది కదా|ఫేక్ కాదు|నిజమే)",
    re.IGNORECASE)


def is_user_correction(text: str) -> bool:
    """The user says the previous answer was wrong ("it IS released", "తప్పు")."""
    return bool(_CORRECTION.search(str(text or "")))


def gap_reasons(decision: dict[str, Any] | None, user_text: str) -> list[str]:
    """Why this turn is a knowledge gap worth showing to staff (no identity)."""
    reasons: list[str] = []
    if decision is None:
        reasons.append("no_answer")
        return reasons
    grounding = decision.get("grounding") or {}
    if grounding.get("required") and not grounding.get("verified"):
        reasons.append("live_check_failed")
    reasons += [f"guard_{r}" for r in decision.get("honesty") or []]
    if is_user_correction(user_text):
        reasons.append("user_correction")
    return reasons
