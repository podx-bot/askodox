"""Conversation-relation classifier for ASKODOX.

The model remains the primary semantic judge.  This small deterministic layer
exists for one UI-critical question that must not be probabilistic: does the
message still belong to the result deck currently on screen?

It intentionally knows no product/category names.  Signals are grammatical
and conversational (constraint fragments, pronouns, option references,
comparison syntax, explicit topic switches), so new categories need no code.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Iterable

_TOKEN = re.compile(r"[\w₹$€£'-]+", re.UNICODE)

# Function words only.  Domain nouns are deliberately absent.
_STOP = {
    "a", "an", "the", "is", "are", "was", "were", "be", "been", "to", "for",
    "of", "in", "on", "at", "by", "with", "from", "and", "or", "but", "if",
    "then", "than", "that", "this", "these", "those", "it", "its", "my", "me",
    "i", "we", "our", "you", "your", "please", "show", "find", "give", "need",
    "want", "looking", "search", "tell", "about", "around", "near", "nearby",
    "లో", "కి", "కు", "ని", "ను", "తో", "కోసం", "దగ్గర", "చూపించు",
}

# Generic refinements: a fragment made mostly of these should never create a
# new need.  Includes common transliterations, not category vocabulary.
_CONSTRAINT = re.compile(
    r"(?ix)(?:"
    r"(?:under|below|above|over|within|around|upto|up\s*to|less\s+than|more\s+than)\s*[₹$€£]?\s*\d"
    r"|[₹$€£]\s*\d|\d+\s*(?:rs|rupees?|₹|km|kms|kg|kgs|g|gm|grams?|minutes?|mins?|hours?|days?)\b"
    r"|\b(?:online|offline|local|nearby|used|new|second[ -]?hand|today|tomorrow|now|"
    r"cheap(?:er)?|premium|budget|home\s+delivery|pickup|cash|cod)\b"
    r"|\b(?:lo|lone|matrame|maatrame|kavali|kaavali|daggara|deggara|ivva|ivvu|"
    r"lopu|kinda|pain[a]?|budget|local|online)\b"
    r")"
)

_RESULT_REF = re.compile(
    r"(?ix)\b(?:first|second|third|1st|2nd|3rd|one|ones|option|options|result|results|"
    r"this|that|these|those|it|them|same|above|shown|cheapest|nearest|best|"
    r"modati|rendava|moodava|idi|adhi|avi|veetilo|daanilo|vatilo)\b"
)
_COMPARE = re.compile(
    r"(?ix)(?:\bvs\.?\b|\bversus\b|\bcompare\b|\bcomparison\b|\bdifference\b|"
    r"\bbetter\b|\bwhich\s+(?:one\s+)?(?:is\s+)?better\b|"
    r"\bside[ -]?by[ -]?side\b|\bedi\s+better\b|\btheda\b)"
)
_EXPLICIT_SWITCH = re.compile(
    r"(?ix)\b(?:instead|forget\s+(?:that|it)|leave\s+(?:that|it)|different\s+(?:thing|topic)|"
    r"new\s+(?:topic|question)|change\s+(?:topic|subject)|"
    r"adi\s+vaddu|adhi\s+vaddu|vere\s+(?:vishayam|topic)|inkoti|marokati)\b"
)
_ACTION = re.compile(
    r"(?ix)\b(?:open|call|contact|directions?|route|book|buy|order|save|share|"
    r"details?|reviews?|rating|price|address|phone|website|link|video|watch|"
    r"select|choose|connect|apply|register|checkout|"
    r"open\s+chey|call\s+chey|book\s+chey|order\s+chey|details\s+cheppu)\b"
)


def _tokens(text: str) -> set[str]:
    return {t.casefold() for t in _TOKEN.findall(text) if len(t) > 1 and t.casefold() not in _STOP}


def _overlap(a: str, b: str) -> float:
    aa, bb = _tokens(a), _tokens(b)
    if not aa or not bb:
        return 0.0
    return len(aa & bb) / min(len(aa), len(bb))


def _source_mentioned(text: str, sources: Iterable[str]) -> bool:
    low = text.casefold()
    return any(len(str(s).strip()) >= 3 and str(s).strip().casefold() in low for s in sources)


@dataclass(frozen=True)
class ConversationRelation:
    relation: str
    confidence: float
    has_active_deck: bool
    subject_replaced: bool = False
    reason: str = ""

    def resolve_new_need(self, model_new_need: bool) -> bool:
        """Correct only high-confidence UI-critical cases.

        Ambiguous language remains the model's decision; this layer does not
        replace semantic reasoning.
        """
        if self.confidence < 0.7:
            return model_new_need
        if self.relation in {"same_topic", "refinement", "result_action", "comparison"}:
            return False
        if self.relation == "new_topic":
            return True
        return model_new_need


class ConversationRelationEngine:
    """Classify a turn relative to the ACTIVE result need, category-agnostic."""

    def classify(
        self,
        *,
        user_text: str,
        active_subject: str = "",
        active_facts: dict[str, Any] | None = None,
        shown_sources: Iterable[str] = (),
        recent_user_turns: Iterable[str] = (),
    ) -> ConversationRelation:
        text = " ".join(str(user_text or "").split())
        subject = " ".join(str(active_subject or "").split())
        has_deck = bool(subject or active_facts)
        if not text:
            return ConversationRelation("unknown", 0.0, has_deck, reason="empty")

        # Explicit conversational switch is universal and strongest.
        if _EXPLICIT_SWITCH.search(text):
            return ConversationRelation(
                "new_topic", 0.98, has_deck, subject_replaced=has_deck,
                reason="explicit_switch",
            )

        if has_deck:
            if _ACTION.search(text) and (_RESULT_REF.search(text) or len(_tokens(text)) <= 5):
                return ConversationRelation("result_action", 0.93, True, reason="option_action")
            if _COMPARE.search(text):
                # If comparison names overlap the active subject, it is about
                # the current need; otherwise the comparison itself is a new
                # subject and the old deck retires.
                same = _overlap(text, subject) > 0 or bool(_RESULT_REF.search(text))
                return ConversationRelation(
                    "comparison", 0.91, True, subject_replaced=not same,
                    reason="comparison",
                )
            if _source_mentioned(text, shown_sources):
                return ConversationRelation("refinement", 0.94, True, reason="shown_source")
            if _CONSTRAINT.search(text):
                # Constraint-only fragments are the canonical "Meesho lo ivva"
                # shape: preserve the need and alter one search dimension.
                return ConversationRelation("refinement", 0.91, True, reason="constraint")
            if _RESULT_REF.search(text) and len(_tokens(text)) <= 8:
                return ConversationRelation("same_topic", 0.86, True, reason="anaphora")
            ov = _overlap(text, subject)
            if ov >= 0.34:
                return ConversationRelation("same_topic", 0.86, True, reason="subject_overlap")

        # Returning to something said recently is distinct from a new subject.
        for old in list(recent_user_turns)[-8:-1]:
            if _overlap(text, str(old)) >= 0.5:
                return ConversationRelation(
                    "return_to_previous", 0.75, has_deck,
                    subject_replaced=has_deck and _overlap(str(old), subject) < 0.2,
                    reason="history_overlap",
                )

        # Do not keyword-guess a new category.  A substantial independent
        # utterance with an active deck is a likely topic change; the model is
        # still allowed to overrule lower-confidence cases.
        meaningful = _tokens(text)
        if has_deck and len(meaningful) >= 2 and _overlap(text, subject) == 0:
            return ConversationRelation(
                "new_topic", 0.74, True, subject_replaced=True,
                reason="independent_subject",
            )

        return ConversationRelation("unknown", 0.35, has_deck, reason="ambiguous")
