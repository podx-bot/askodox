"""ASKODOX knows its own name and what it does (owner 2026-11-20).

Voice turned "ASKODOX, what does it do, how is it easy for me?" into "class codex ..." and the
assistant answered about OpenAI Codex from the web; the user's correction ("not codex, ఆక్సోడెక్స్")
then got "I have no verified information about it". Two fixes, one place:

* ``fix_spoken_name`` -- any word that SOUNDS like ASKODOX (Latin, Telugu or Hindi script, one word
  or split in two) is written "ASKODOX" before anything else reads the message. Matching is by
  sound shape (a / s / k / o / d / x skeleton), not a fixed word list, so new mis-hearings fit too.
* ``prompt_block`` -- the brain's own facts about ASKODOX, built from the REAL app actions catalogue
  (``chat_actions.CATALOG``), so a new feature shows up in the answer by itself. Questions about
  ASKODOX are answered from these facts, never from a web search (``is_about_askodox``).
"""
from __future__ import annotations

import re

NAME = "ASKODOX"

# Latin: a-s-k-o-d-o-x skeleton ("askodox", "ascodox", "axodex", "aksodex", "askodocs", "askodoks").
_LATIN = re.compile(r"^(?:a|e|aa|ay)?(?:s|x|ks|ss|ks?s)(?:k|c|kh|q)?o+(?:d|dd|t)(?:o|a|e|aa|oo)(?:x|ks|cs|kz|kx|kss)s?$")
# Telugu / Hindi: starts like "aa / a / ya / e", has an S sound before a D sound and ends in a KS sound.
_TELUGU = re.compile(r"^(?:ఆ|అ|యా|ఏ|ఎ)[^\s]{0,4}స[^\s]{0,5}డ[^\s]{0,3}క్స్?$")
_HINDI = re.compile(r"^(?:आ|अ|ऐ|ए)[^\s]{0,4}स[^\s]{0,5}ड[^\s]{0,3}क्स्?$")
# Two words: a short S-ending word + "codex / kodex / docs" ("ask codex", "class codex", "ఆస్ కోడెక్స్").
_SECOND = re.compile(r"^(?:codex|kodex|kodax|codax|codocs|kodox|codox|dox|docs|కోడెక్స్|కోడాక్స్|కొడెక్స్|డాక్స్|कोडेक्स|डॉक्स)$")
_FIRST_LATIN = re.compile(r"^[a-z]{1,5}s$")
_FIRST_INDIC = re.compile(r"^[^\sa-zA-Z0-9]{1,6}(?:స్|स्)$")
_WORD = re.compile(r"[^\s,.!?;:()\"'“”]+")


def _plain(word: str) -> str:
    return re.sub(r"[^a-z]", "", word.lower())


def _sounds_like(word: str) -> bool:
    if word.upper() == NAME:
        return True
    latin = _plain(word)
    if latin and latin == word.lower().strip("-") and 6 <= len(latin) <= 10 and _LATIN.match(latin):
        return True
    return bool(_TELUGU.match(word) or _HINDI.match(word))


def fix_spoken_name(text: str) -> str:
    """The message with every sound-alike of ASKODOX written as "ASKODOX" (other words untouched)."""
    raw = str(text or "")
    if not raw.strip():
        return raw
    spans = [(m.start(), m.end(), m.group(0)) for m in _WORD.finditer(raw)]
    out: list[str] = []
    last = 0
    i = 0
    while i < len(spans):
        start, end, word = spans[i]
        # "ask o dox" / "as ko docs": up to three short Latin words that together sound like ASKODOX
        if i + 2 < len(spans) and all(raw[spans[j][1]:spans[j + 1][0]].strip() == "" for j in (i, i + 1)):
            parts = [spans[j][2] for j in (i, i + 1, i + 2)]
            if all(_plain(p) == p.lower() and 1 <= len(p) <= 5 for p in parts):
                joined = "".join(p.lower() for p in parts)
                if 6 <= len(joined) <= 10 and _LATIN.match(joined):
                    out.append(raw[last:start] + NAME)
                    last = spans[i + 2][1]
                    i += 3
                    continue
        nxt = spans[i + 1] if i + 1 < len(spans) else None
        if nxt is not None and raw[end:nxt[0]].strip() == "":
            first = word.lower()
            second = nxt[2].lower()
            joined = _plain(word + nxt[2])
            if (_SECOND.match(second) and (_FIRST_LATIN.match(first) or _FIRST_INDIC.match(word))) or (
                    joined and 6 <= len(joined) <= 10 and _LATIN.match(joined) and _plain(word) == first and _plain(nxt[2]) == second):
                out.append(raw[last:start] + NAME)
                last = nxt[1]
                i += 2
                continue
        if _sounds_like(word) and word != NAME:
            out.append(raw[last:start] + NAME)
            last = end
        i += 1
    out.append(raw[last:])
    return "".join(out)


def is_about_askodox(text: str) -> bool:
    """The (already fixed) message talks about ASKODOX itself -- answered from the app's own facts, no web search."""
    return bool(re.search(r"\bASKODOX\b", str(text or ""), re.IGNORECASE))


def prompt_block() -> str:
    from app.services import chat_actions

    features = "; ".join(f"{en} ({te})" for _key, _route, en, te, _about in chat_actions.CATALOG)
    return (
        "ABOUT ASKODOX (this app -- you ARE ASKODOX): an Indian AI assistant app where anyone asks by voice or text "
        "in their own language (Telugu, Hindi, English and more). For customers: find and buy products and services "
        "nearby or online with real prices, compare, order from local shops and restaurants (menu, table, parcel, "
        "delivery), rides and parcels, bills sent by shops, phone payment voice alerts. For shop owners and their "
        "staff: billing (POS) by voice or item number, GST bills, stock and expiry, staff attendance and salary, "
        "payment voice alerts on every staff phone, credit (baaki) reminders, table QR orders and reservations, "
        "supplier bill photo to stock, offers and combos, AI agents. The app's real screens: " + features + ". "
        "Voice input often mis-hears the name ASKODOX (e.g. 'ask codex', 'class codex', 'axodex', 'ఆక్సోడెక్స్'); "
        "when a word sounds like it and the user asks what this app does / how it helps them, it means ASKODOX. "
        "Questions about ASKODOX itself are answered ONLY from these facts (never from the web, never 'I have no "
        "information'): say in 2-4 short points what it does FOR THIS USER (customer, shop owner or staff -- "
        "from the conversation) and offer to open the most useful screen.\n"
    )
