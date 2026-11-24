"""One-screen answer cards (owner 2026-11-24, design artifact WfPV8AhvZsPFqmwzYpfvap "OneScreen" + "Best - v2").

Every chat answer must fit ONE phone screen (360 px and up, every language): a big short answer line with a voice
button on top, up to 4 big icon tabs in the middle (tap = the content changes inside the same card, sideways swipe
cards for more), one big action button + mic at the bottom, quick replies as buttons whose follow-up shows INSIDE the
card. Photo / SMS checks add a risk meter, "what I saw in the SMS" with money / sender / link coloured, one button
that opens the person's UPI / bank app, 3 don'ts as icon tiles, "send to family" and feedback.

How it works (only for app builds that send the ``answer_card`` capability; older builds see no change):

1. The brain writes the reply in two parts: the short spoken part, a line ``[[more]]``, then the details.
   The app shows / speaks only the part before the mark (``spoken_part``).
2. After the answer, ``build`` turns reply + the person's words + what the photo showed into a CARD (one fast model
   call, JSON). ``clean`` validates every field: sizes, enums, at most 4 tabs / 3 don'ts / 4 replies, and every
   action is checked against what is safe (helplines, numbers and https links that are in the answer or the
   attachment, never invented).
3. No model / bad JSON -> ``from_text`` builds a smaller card from the reply itself (headline, sections as tabs,
   numbered steps, [risk] lines as don'ts, "(a) ... (b) ..." choices as quick replies). The plain ``reply`` always
   stays in the decision as the fallback for old apps.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

CAPABILITY = "answer_card"
MARK = "[[more]]"
VERSION = 1

MAX_TABS = 4
MAX_ITEMS = 6
MAX_DONTS = 3
MAX_REPLIES = 4
MAX_ACTIONS = 2

KINDS = ("answer", "check")
RISKS = ("safe", "careful", "danger")
TAB_STYLES = ("cards", "grid", "checklist", "steps", "text")
TAB_ICONS = ("money", "types", "who", "papers", "steps", "info", "warning", "time", "place", "phone", "compare",
             "tips", "rules", "list", "chart", "shop", "food", "health", "travel", "legal")
DONT_ICONS = ("link", "otp", "reply", "pin", "money", "call", "app", "share", "card", "screen")
TONES = ("ok", "warn", "danger", "neutral")
MARK_KINDS = ("money", "sender", "link", "date", "number")
ACTION_KINDS = ("call", "open_url", "open_upi", "sms", "ask", "bank_help", "block_help", "share")

# Numbers that are safe to dial / text without being in the answer (India helplines).
SAFE_CALLS = {"1930": "Cyber crime helpline", "112": "Emergency", "100": "Police", "101": "Fire", "108": "Ambulance",
              "102": "Ambulance", "181": "Women helpline", "1098": "Child helpline", "14567": "Elder helpline",
              "1915": "Consumer helpline", "14404": "Consumer helpline", "155260": "Cyber fraud",
              "1800114000": "National consumer helpline", "14416": "Tele-MANAS"}
SAFE_SMS = {"1909": "TRAI spam report", "7726": "Spam report (SPAM)"}
SAFE_URL_HOSTS = ("cybercrime.gov.in", "sancharsaathi.gov.in", "www.sancharsaathi.gov.in", "www.cybercrime.gov.in",
                  "rbi.org.in", "www.rbi.org.in", "cms.rbi.org.in", "consumerhelpline.gov.in", "www.mudra.org.in",
                  "mudra.org.in", "udyamregistration.gov.in", "www.udyamregistration.gov.in", "npci.org.in",
                  "www.npci.org.in", "incometax.gov.in", "www.incometax.gov.in", "gst.gov.in", "www.gst.gov.in",
                  "uidai.gov.in", "myaadhaar.uidai.gov.in", "www.india.gov.in", "pmkisan.gov.in", "jansamarth.in",
                  "www.jansamarth.in", "sachet.rbi.org.in", "tafcop.sancharsaathi.gov.in")

PROMPT_RULES = (
    "One-screen answer (this app draws the answer as ONE phone-screen card): write the reply in two parts. "
    "PART 1 (shown big and read aloud): the direct answer in ONE short line (at most 15 words), then at most one more "
    "short sentence. No headings, no lists, no question lists in part 1. Then a line that is exactly [[more]] . "
    "PART 2 (drawn as tabs, swipe cards, steps and buttons, never read aloud): the details as 2-4 short sections, "
    "each a '## ' heading of 1-2 words (e.g. Types / Who / Papers / How, in the user's language) with short points, "
    "numbered steps where order matters, [risk] lines for things not to do, and when you need the user to choose, "
    "a last section '## Choose' with 2-4 short options as '- ' points (never '(a) (b) (c) type'). "
    "Keep every point under 12 words. Part 2 may be empty for a short chat reply (then no [[more]] line). "
)

_CARD_PROMPT = """You turn an assistant answer into ONE phone-screen answer card for the ASKODOX app (India).
Return ONLY one JSON object, no markdown fence. Every text in the SAME language as the ANSWER (keep English words the
answer itself uses). Use ONLY facts in the ANSWER, the USER MESSAGE or the ATTACHMENT -- never add a fact, price,
number, link or bank name that is not there.

Keys:
- kind: "check" when the user shared a photo / screenshot / SMS / message and the answer judges it (scam, genuine,
  what it means); else "answer".
- label: 2-6 words naming the topic (e.g. "Mudra loan - for your shop").
- headline: the answer in at most 15 words (big line on top).
- speak: what the voice says, at most 2 short sentences.
- risk: only for kind "check": "safe" (looks genuine) | "careful" (not sure, check first) | "danger" (scam / do
  not act); else null. risk_label: 1-2 words for it.
- seen: only for kind "check" when the attachment has text: {"title": short "what I saw in the SMS" in the answer's
  language, "text": the important part of the message copied EXACTLY from the ATTACHMENT (at most 220 chars),
  "marks": [{"text": an exact substring of seen.text, "kind": "money"|"sender"|"link"|"date"|"number"}]}; else null.
- tabs: 0-4 tabs {"id": short ascii id, "label": 1-2 words, "icon": one of %(icons)s, "style": "cards" (swipe
  cards: items with title + big value + sub + body) | "grid" (short tiles: items with title only) | "checklist"
  (things to have: items with title) | "steps" (ordered: items with title + body) | "text" (one short note in
  "note"), "title": optional short heading inside the tab, "items": at most 6, "note": optional 1 sentence}.
  Only tabs the answer has content for. Each item: {"title", "value", "sub", "body"} -- short strings, "" if none.
- donts: 0-3 {"icon": one of %(dont_icons)s, "text": 2-4 words} -- only things the answer says NOT to do.
- replies: 0-4 quick replies the user would tap next {"label": 1-4 words, "tone": "ok"|"warn"|"danger"|"neutral",
  "text": what to show inside the card when tapped (1-2 short sentences from the answer) or "" to ask the assistant,
  "actions": 0-2 actions}. When the answer asks the user to pick a situation (e.g. "(a) you have an account,
  (b) you do not know them, (c) money was deducted"), make one reply per situation with its follow-up text/actions.
- primary: the ONE most useful action for the big bottom button, or null.
- actions: 0-2 more actions.
- share: true when the answer warns about a scam / fraud worth sending to family.

Action = {"kind", "label" (2-5 words), "value"}:
  "call" value = a phone number (helplines like 1930 / 112 / 100, or a number written in the answer);
  "bank_help" = call your own bank (value ""); "open_upi" = open the user's UPI / bank app to check (value "");
  "open_url" value = an https link written in the answer (or cybercrime.gov.in / sancharsaathi.gov.in);
  "sms" value = 1909 (report spam to TRAI); "block_help" = how to block the sender (value "");
  "ask" value = the exact question to send to the assistant next (e.g. "which loan suits me?");
  "share" = send this warning to family (value "").

USER MESSAGE:
%(user)s

ATTACHMENT (what the shared photo / file shows, may be empty):
%(facts)s

ANSWER:
%(reply)s
"""

_SPACES = re.compile(r"[ \t]+")
_PHONE = re.compile(r"(?<!\d)(\d[\d\- ]{1,13}\d)(?!\d)")
_URL = re.compile(r"https?://[^\s)\]>\"']+", re.IGNORECASE)
_BARE_HOST = re.compile(r"\b((?:[a-z0-9-]+\.)+(?:gov\.in|nic\.in|org\.in|in|com|org))\b", re.IGNORECASE)


def wanted(capabilities: Any) -> bool:
    return CAPABILITY in (capabilities or ())


def prompt_block(capabilities: Any) -> str:
    return PROMPT_RULES if wanted(capabilities) else ""


def spoken_part(reply: str) -> str:
    """The part shown big and read aloud (before the mark); the whole reply when there is no mark."""
    text = str(reply or "")
    at = text.find(MARK)
    return (text[:at] if at >= 0 else text).strip()


def details_part(reply: str) -> str:
    text = str(reply or "")
    at = text.find(MARK)
    return text[at + len(MARK):].strip() if at >= 0 else ""


def without_mark(reply: str) -> str:
    """The reply as plain text for old apps / history: the mark becomes a paragraph break."""
    return re.sub(r"\n?[ \t]*\[\[more\]\][ \t]*\n?", "\n\n", str(reply or "")).strip()


def _s(value: Any, limit: int) -> str:
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        return ""
    text = _SPACES.sub(" ", str(value)).strip()
    text = re.sub(r"\[(?:ok|good|caution|warning|risk|danger)\]\s*", "", text, flags=re.IGNORECASE)
    text = text.replace("**", "").replace(MARK, "").strip(" -•*")
    return text[:limit].rstrip()


def _digits(value: str) -> str:
    return re.sub(r"\D", "", str(value or ""))


def _allowed_numbers(source: str) -> set[str]:
    """Helplines, plus full phone / toll-free numbers written in the answer or the attachment (10-13 digits).
    A short number in the text (an amount like 8551) is never dialled."""
    found = {_digits(m.group(1)) for m in _PHONE.finditer(source)}
    return {n for n in found if 10 <= len(n) <= 13} | set(SAFE_CALLS)


def _allowed_urls(source: str) -> set[str]:
    urls = {u.rstrip(".,;:") for u in _URL.findall(source)}
    return urls


def _url_ok(url: str, source_urls: set[str]) -> str:
    url = str(url or "").strip()
    if not url:
        return ""
    if not url.lower().startswith("http"):
        url = "https://" + url.lstrip("/")
    if not url.lower().startswith("https://"):
        return ""
    host = re.sub(r"^https://", "", url, flags=re.IGNORECASE).split("/")[0].split("?")[0].lower()
    if url in source_urls or host in SAFE_URL_HOSTS:
        return url[:300]
    return ""


def _action(raw: Any, source: str, source_urls: set[str]) -> dict[str, str] | None:
    if not isinstance(raw, dict):
        return None
    kind = str(raw.get("kind") or "").strip().lower()
    if kind not in ACTION_KINDS:
        return None
    label = _s(raw.get("label"), 40)
    value = _s(raw.get("value"), 300)
    if kind == "call":
        number = _digits(value)
        if number not in _allowed_numbers(source):
            return None
        value = number
        label = label or number
    elif kind == "sms":
        number = _digits(value) or "1909"
        if number not in SAFE_SMS:
            return None
        value = number
    elif kind == "open_url":
        value = _url_ok(value, source_urls)
        if not value:
            return None
    elif kind == "ask":
        if not value:
            value = label
        if not value:
            return None
        value = value[:200]
    else:
        value = ""
    if not label:
        return None
    return {"kind": kind, "label": label, "value": value}


def _choice(value: Any, allowed: tuple[str, ...], default: str | None) -> str | None:
    text = str(value or "").strip().lower()
    return text if text in allowed else default


def clean(raw: Any, *, reply: str, user_text: str = "", facts: str = "") -> dict[str, Any] | None:
    """A safe card from the model's JSON, or None when nothing usable came back."""
    if not isinstance(raw, dict):
        return None
    source = "\n".join([str(reply or ""), str(user_text or ""), str(facts or "")])
    urls = _allowed_urls(source)
    headline = _s(raw.get("headline"), 140)
    if not headline:
        return None
    kind = _choice(raw.get("kind"), KINDS, "answer") or "answer"
    card: dict[str, Any] = {
        "v": VERSION,
        "kind": kind,
        "label": _s(raw.get("label"), 60),
        "headline": headline,
        "speak": _s(raw.get("speak"), 320) or headline,
        "risk": None,
        "risk_label": "",
        "seen": None,
        "tabs": [],
        "donts": [],
        "replies": [],
        "primary": None,
        "actions": [],
        "share": bool(raw.get("share")) and kind == "check",
    }
    if kind == "check":
        card["risk"] = _choice(raw.get("risk"), RISKS, "careful")
        card["risk_label"] = _s(raw.get("risk_label"), 24)
        seen = raw.get("seen")
        if isinstance(seen, dict):
            text = _s(seen.get("text"), 260)
            if text:
                marks = []
                for m in (seen.get("marks") or [])[:8]:
                    if not isinstance(m, dict):
                        continue
                    piece = str(m.get("text") or "").strip()
                    mk = _choice(m.get("kind"), MARK_KINDS, None)
                    if piece and mk and piece in text and len(piece) <= 80:
                        marks.append({"text": piece, "kind": mk})
                card["seen"] = {"title": _s(seen.get("title"), 50), "text": text, "marks": marks}
    seen_ids: set[str] = set()
    for tab in (raw.get("tabs") or [])[:MAX_TABS + 2]:
        if not isinstance(tab, dict) or len(card["tabs"]) >= MAX_TABS:
            continue
        label = _s(tab.get("label"), 18)
        if not label:
            continue
        style = _choice(tab.get("style"), TAB_STYLES, "cards") or "cards"
        items = []
        for item in (tab.get("items") or [])[:MAX_ITEMS]:
            if isinstance(item, str):
                item = {"title": item}
            if not isinstance(item, dict):
                continue
            row = {"title": _s(item.get("title"), 60), "value": _s(item.get("value"), 24),
                   "sub": _s(item.get("sub"), 50), "body": _s(item.get("body"), 140)}
            if row["title"] or row["value"] or row["body"]:
                items.append(row)
        note = _s(tab.get("note"), 160)
        if not items and not note:
            continue
        tab_id = re.sub(r"[^a-z0-9_]", "", str(tab.get("id") or "").lower())[:16] or f"t{len(card['tabs']) + 1}"
        while tab_id in seen_ids:
            tab_id += "x"
        seen_ids.add(tab_id)
        card["tabs"].append({"id": tab_id, "label": label,
                             "icon": _choice(tab.get("icon"), TAB_ICONS, "info") or "info",
                             "style": style if items else "text", "title": _s(tab.get("title"), 50),
                             "items": items, "note": note})
    for dont in (raw.get("donts") or [])[:MAX_DONTS + 2]:
        if not isinstance(dont, dict) or len(card["donts"]) >= MAX_DONTS:
            continue
        text = _s(dont.get("text"), 32)
        if text:
            card["donts"].append({"icon": _choice(dont.get("icon"), DONT_ICONS, "link") or "link", "text": text})
    labels: set[str] = set()
    for rep in (raw.get("replies") or [])[:MAX_REPLIES + 2]:
        if not isinstance(rep, dict) or len(card["replies"]) >= MAX_REPLIES:
            continue
        label = _s(rep.get("label"), 32)
        if not label or label.casefold() in labels:
            continue
        labels.add(label.casefold())
        actions = [a for a in (_action(x, source, urls) for x in (rep.get("actions") or [])[:3]) if a][:2]
        card["replies"].append({"label": label, "tone": _choice(rep.get("tone"), TONES, "neutral") or "neutral",
                                "text": _s(rep.get("text"), 220), "actions": actions})
    card["primary"] = _action(raw.get("primary"), source, urls)
    card["actions"] = [a for a in (_action(x, source, urls) for x in (raw.get("actions") or [])[:4]) if a][:MAX_ACTIONS]
    if card["primary"] is None and card["actions"]:
        card["primary"] = card["actions"].pop(0)
    return card


def _parse_json(raw: str) -> Any:
    text = str(raw or "").strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start:end + 1], strict=False)
    except ValueError:
        return None


# ---------------------------------------------------------------------------------------------------------------
# Deterministic card from the reply text (no model / bad JSON).

_HEADING = re.compile(r"^\s{0,3}(?:#{1,6}\s+(.+?)|\*\*(.+?)\*\*:?)\s*$")
_BULLET = re.compile(r"^\s*(?:[-*•]|\d{1,2}[.)])\s+(.+)$")
_NUMBERED = re.compile(r"^\s*\d{1,2}[.)]\s+")
_RISK_TAG = re.compile(r"^\s*(?:\[(?:risk|danger|caution|warning)\]|⚠️|❌|🚫)", re.IGNORECASE)
_CHOICES = re.compile(r"\(([a-e])\)\s*([^()]+?)(?=,?\s*(?:or\s+)?\([a-e]\)|[.?!]?\s*$)", re.IGNORECASE)
_SENTENCE = re.compile(r"(?<=[.!?।])\s+")


def _first_sentence(text: str, limit: int = 140) -> str:
    plain = re.sub(r"[#*_`>]+", "", str(text or "")).strip()
    plain = re.sub(r"\[(?:ok|good|caution|warning|risk|danger)\]\s*", "", plain, flags=re.IGNORECASE)
    first = _SENTENCE.split(plain.split("\n")[0].strip(), maxsplit=1)[0] if plain else ""
    return first[:limit].strip()


def from_text(reply: str, *, suggestions: list[str] | None = None, facts: str = "") -> dict[str, Any] | None:
    """A smaller card built from the reply alone. None for an empty reply."""
    text = str(reply or "").strip()
    if not text:
        return None
    spoken = spoken_part(text)
    details = details_part(text) or (text[len(spoken):] if spoken != text else "")
    if not details:
        # No mark: the first paragraph is the answer, the rest are details.
        parts = re.split(r"\n\s*\n", text, maxsplit=1)
        spoken, details = parts[0], (parts[1] if len(parts) > 1 else "")
    headline = _first_sentence(spoken) or _first_sentence(text)
    if not headline:
        return None
    tabs: list[dict[str, Any]] = []
    donts: list[dict[str, str]] = []
    replies: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    def close() -> None:
        nonlocal current
        if current and (current["items"] or current["note"]):
            if not current["items"]:
                current["style"] = "text"
            if len(tabs) < MAX_TABS:
                tabs.append(current)
        current = None

    choose_section = False
    for raw_line in details.split("\n"):
        line = raw_line.rstrip()
        if not line.strip() or re.fullmatch(r"\s*[-*•]\s*", line):
            continue
        head = _HEADING.match(line)
        if head:
            close()
            label = _s(head.group(1) or head.group(2), 18)
            choose_section = bool(re.search(r"choose|pick|which|ఏది|ఎంచుకో|चुनें|situation|పరిస్థితి", label, re.I))
            current = None if choose_section else {
                "id": f"t{len(tabs) + 1}", "label": label, "icon": "info", "style": "cards", "title": "",
                "items": [], "note": ""}
            continue
        bullet = _BULLET.match(line)
        body = bullet.group(1) if bullet else line
        if _RISK_TAG.match(body) and len(donts) < MAX_DONTS:
            donts.append({"icon": "link", "text": _s(body, 32)})
            continue
        if choose_section and bullet:
            if len(replies) < MAX_REPLIES:
                replies.append({"label": _s(body, 32), "tone": "neutral", "text": "", "actions": []})
            continue
        if current is None:
            current = {"id": f"t{len(tabs) + 1}", "label": "", "icon": "info", "style": "cards", "title": "",
                       "items": [], "note": ""}
        if bullet:
            if _NUMBERED.match(line):
                current["style"] = "steps"
            if len(current["items"]) < MAX_ITEMS:
                title, _, rest = _s(body, 200).partition(":")
                if rest and len(title) <= 40:
                    current["items"].append({"title": title.strip(), "value": "", "sub": "", "body": rest.strip()[:140]})
                else:
                    current["items"].append({"title": _s(body, 60), "value": "", "sub": "",
                                             "body": _s(body, 140) if len(body) > 60 else ""})
        elif not current["note"]:
            current["note"] = _s(body, 160)
    close()
    for i, tab in enumerate(tabs):
        if not tab["label"]:
            tab["label"] = "More" if i else "Details"
        if tab["style"] == "cards" and all(len(it["title"]) <= 24 and not it["body"] for it in tab["items"]):
            tab["style"] = "grid"
    for match in _CHOICES.finditer(spoken + " " + details):
        if len(replies) >= MAX_REPLIES:
            break
        label = _s(match.group(2), 32)
        if label and all(r["label"] != label for r in replies):
            replies.append({"label": label, "tone": "neutral", "text": "", "actions": []})
    for chip in (suggestions or [])[:MAX_REPLIES]:
        if len(replies) >= MAX_REPLIES:
            break
        label = _s(chip, 32)
        if label and all(r["label"].casefold() != label.casefold() for r in replies):
            replies.append({"label": label, "tone": "neutral", "text": "", "actions": []})
    speak = _s(" ".join(_SENTENCE.split(re.sub(r"[#*_`]+", "", spoken).replace("\n", " "))[:2]), 320)
    return {"v": VERSION, "kind": "answer", "label": "", "headline": headline, "speak": speak or headline,
            "risk": None, "risk_label": "", "seen": None, "tabs": tabs, "donts": donts, "replies": replies,
            "primary": None, "actions": [], "share": False}


def build(writer: Any, *, reply: str, user_text: str = "", facts: str = "",
          suggestions: list[str] | None = None) -> dict[str, Any] | None:
    """The card for this answer: the model's (cleaned) card, else the one built from the text."""
    text = str(reply or "").strip()
    if not text:
        return None
    fallback = from_text(text, suggestions=suggestions, facts=facts)
    short = len(text) < 160 and MARK not in text and "\n" not in text.strip() and not facts
    if short or writer is None:
        return fallback
    prompt = _CARD_PROMPT % {"icons": "|".join(TAB_ICONS), "dont_icons": "|".join(DONT_ICONS),
                             "user": str(user_text or "")[:1200], "facts": str(facts or "")[:2500] or "(none)",
                             "reply": without_mark(text)[:6000]}
    try:
        raw = writer(prompt)
    except Exception:
        logger.exception("answer_card: card call failed")
        raw = ""
    card = clean(_parse_json(raw), reply=text, user_text=user_text, facts=facts) if raw else None
    if card is None:
        logger.info("answer_card: model card unusable -> text card (raw_len=%d)", len(raw or ""))
        return fallback
    if not card["replies"] and fallback and fallback["replies"]:
        card["replies"] = fallback["replies"]
    return card
