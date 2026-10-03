"""Business Auto-Response: a registered seller / provider's automatic
answers to common customer questions inside ASKODOX deal chats.

Only APPROVED knowledge is used (the owner's FAQ answers in their
``auto_response_rules`` record). A question the FAQ does not cover, a
handoff word ("call me", "complaint", "refund"...) or an out-of-hours
message goes to the human owner -- nothing is guessed. Contact details in
an answer are masked: contact is shared only through the existing
request -> acceptance consent flow. External channels (Facebook /
Instagram / WhatsApp) are NOT messaged from here; they need the owner's
authorised platform API.
"""
from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from app.services.pii_mask import mask

DEFAULT_HANDOFF = ("call me", "complaint", "refund", "cancel", "problem", "manager", "human", "person",
                   "ఫిర్యాదు", "రీఫండ్", "शिकायत", "रिफंड")
_WORD = re.compile(r"[^\W_]+", re.UNICODE)


def _words(text: Any) -> set:
    return {w for w in _WORD.findall(str(text or "").casefold()) if len(w) > 2}


def _same_word(a: str, b: str) -> bool:
    if a == b:
        return True
    n = min(len(a), len(b), 6)
    return n >= 4 and a[:n] == b[:n]


def in_hours(spec: Any, at: Optional[datetime] = None) -> bool:
    if not spec:
        return True
    try:
        start, end = (int(x) for x in str(spec).split("-"))
    except ValueError:
        return True
    hour = ((at or datetime.now(timezone.utc)) + timedelta(hours=5, minutes=30)).hour  # India time
    return start <= hour < end if start <= end else hour >= start or hour < end


def answer(message: str, rule: Dict[str, Any], *, at: Optional[datetime] = None) -> Dict[str, Any]:
    """One customer message -> answered / handoff / out_of_hours / unknown."""
    text = str(message or "").casefold()
    handoff = [str(w).casefold() for w in (rule.get("handoff_words") or [])] or list(DEFAULT_HANDOFF)
    if any(w and w in text for w in handoff):
        return {"status": "handoff", "text": None, "source": "handoff_word"}
    if not in_hours(rule.get("business_hours"), at):
        reply = str(rule.get("out_of_hours_reply") or "").strip()
        return {"status": "out_of_hours", "text": mask(reply) if reply else None, "source": "business_hours"}
    faq = rule.get("faq") if isinstance(rule.get("faq"), dict) else {}
    asked = _words(message)
    best, best_score = None, 0
    for key, value in faq.items():
        key_words = _words(str(key).replace("_", " "))
        # "deliver" answers "delivery", "returned" answers "returns".
        score = sum(1 for k in key_words if any(_same_word(k, a) for a in asked))
        if score > best_score and str(value or "").strip():
            best, best_score = key, score
    if best is None:
        return {"status": "unknown", "text": None, "source": None}
    return {"status": "answered", "text": mask(str(faq[best]).strip()), "source": f"faq:{best}"}


def rule_for(records, business_ref: str) -> Optional[Dict[str, Any]]:
    for record in records or []:
        if record.get("status") != "ACTIVE" or record.get("archived"):
            continue
        data = record.get("data") or {}
        if str(data.get("business_ref") or record.get("owner_ref") or "") == business_ref:
            return {**data, "_id": record.get("id")}
    return None
