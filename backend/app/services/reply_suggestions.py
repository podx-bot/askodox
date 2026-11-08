"""Smart Answer chips (owner 2026-11-08): short tap-able next steps under a reply.

Today's users skim and tap rather than type, so the ONE brain may return 2-5 short
``suggestions`` -- each a complete thing the user could say next, in the user's own
language. The app draws them as chips under the latest reply; a tap sends exactly
that text as the user's next message. Nothing here runs an action by itself.

Only app builds that send the ``suggestions`` capability get the prompt block and the
field; older builds see no change. Cleaning is deterministic and universal (no
category lists): short, distinct, no links, no contact details, never a copy of
the reply, never a claim that something was done.
"""
from __future__ import annotations

import re
from typing import Any

CAPABILITY = "suggestions"
MIN_CHIPS = 2
MAX_CHIPS = 5
MAX_CHARS = 40
MAX_WORDS = 6

PROMPT_BLOCK = (
    "Smart answer style (the app draws chips; any domain, any language): the user skims and taps rather than "
    "types. When this reply ends with a question, start with the answer in one short line, then ask the ONE "
    "question. When you recommend one option over others, give the reason in ONE short line ('X, because ...') "
    "using only facts the user gave, the conversation, or LIVE WEB EVIDENCE -- never invented specs or prices. "
    "Add at most ONE extra tip the user did not ask for, and only when LIVE WEB EVIDENCE below supports it; "
    "otherwise no tip. Also return key suggestions = a JSON array of 2-5 short next things the user could tap "
    "to say (2-4 words each, in the user's language or language mix, each complete on its own): the likely "
    "answers to your ONE question when you asked one (e.g. budget bands, sizes, yes / no), otherwise the most "
    "useful next steps for THIS conversation (compare, nearby, cheaper option, details). Never a link, phone "
    "number or price you were not given; never claim something was booked, ordered or sent; return [] when no "
    "chip would genuinely help (greetings, thanks, a finished answer). "
)

_LINK = re.compile(r"(https?://|www\.|\.com\b|\.in\b|@)", re.IGNORECASE)
# Seven or more digits in one run (spaces / hyphens allowed between them) is a phone
# or account number; a budget band such as "₹10,000-20,000" never forms such a run.
_NUMBER_RUN = re.compile(r"(?:\d[\s-]?){7,}")
_DONE_CLAIM = re.compile(
    r"\b(booked|ordered|sent|paid|confirmed|done)\b|బుక్ చేశా|ఆర్డర్ చేశా|పంపా", re.IGNORECASE)
_SPACES = re.compile(r"\s+")


def wanted(capabilities: Any) -> bool:
    """True when this app build renders suggestion chips."""
    return CAPABILITY in (capabilities or ())


def prompt_block(capabilities: Any) -> str:
    return PROMPT_BLOCK if wanted(capabilities) else ""


def _chip(value: Any) -> str:
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        return ""
    text = _SPACES.sub(" ", str(value)).strip().strip("\"'`*-•·").strip()
    if not text or len(text) > MAX_CHARS or len(text.split(" ")) > MAX_WORDS:
        return ""
    if _LINK.search(text) or _DONE_CLAIM.search(text):
        return ""
    if _NUMBER_RUN.search(text):
        return ""
    return text


def clean(raw: Any, *, reply: str = "") -> list[str]:
    """2-5 short, distinct, safe chips -- or [] when fewer than two survive."""
    if not isinstance(raw, list):
        return []
    reply_key = _SPACES.sub(" ", str(reply or "")).strip().casefold()
    seen: set[str] = set()
    chips: list[str] = []
    for value in raw[:12]:
        chip = _chip(value)
        key = chip.casefold()
        if not chip or key in seen or (reply_key and key == reply_key):
            continue
        seen.add(key)
        chips.append(chip)
        if len(chips) == MAX_CHIPS:
            break
    return chips if len(chips) >= MIN_CHIPS else []
