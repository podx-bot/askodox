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
import unicodedata
from dataclasses import dataclass
from typing import Any, Iterable

from app.services.comparison_entities import named_comparison_entities

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


def _raw_tokens(text: str) -> list[str]:
    """Unicode-aware words: letters, digits AND combining marks (Telugu /
    Devanagari vowel signs and viramas stay inside their word)."""
    tokens, current = [], []

    def flush():
        if current:
            tokens.append("".join(current))
            current.clear()

    for ch in unicodedata.normalize("NFC", text or ""):
        if unicodedata.category(ch)[0] in {"L", "N", "M"} or ch in {"₹", "$", "€", "£", "'", "-"}:
            current.append(ch)
        else:
            flush()
    flush()
    return [t.casefold().strip("'-") for t in tokens if t.strip("'-")]


def _stem(token: str) -> str:
    """Plural-insensitive Latin tokens ("phones" == "phone"). Other scripts
    are left as they are."""
    if token.isascii() and token.isalpha() and len(token) > 3:
        if token.endswith("ies") and len(token) > 4:
            return token[:-3] + "y"
        if token.endswith(("ses", "xes", "ches", "shes")):
            return token[:-2]
        if token.endswith("s") and not token.endswith("ss"):
            return token[:-1]
    return token


def _tokens(text: str) -> set[str]:
    return {t for t in _raw_tokens(text) if len(t) > 1 and t not in _STOP}


# Grammar of a conversation, never category vocabulary. Each set is the same
# idea in English, romanized Telugu / Hindi and the native scripts.
_DISPLAY_AND_FILLER = {
    "show", "see", "display", "dikhao", "dikhaiye", "dikha", "dikhana", "batao", "bataiye", "chupinchu",
    "chupinchandi", "chupinchali", "chupistava", "chudali", "kuda", "kooda", "bhi", "ga", "aur", "inka",
    "inkaa", "also", "some", "any", "more", "other", "others", "please", "pls", "plz", "go", "come", "get",
    "got", "can", "could", "would", "will", "should", "do", "does", "did", "have", "has", "had", "there",
    "here", "what", "how", "so", "too", "very", "just", "really", "much", "many", "all", "us", "him", "her",
    "chupinchandi", "cheppu", "cheppandi", "kosam", "andi", "ra", "le", "na", "naku", "nenu", "maaku", "ma",
    "mujhe", "hame", "humein", "mera", "meri", "hai", "hain", "ka", "ki", "ke", "ko", "se", "mein", "me",
    "avvala", "avvali", "avuthunda", "avtunda", "undha", "unda", "untaya", "untundi", "cheyali", "cheyyali",
    "ela", "enduku", "emiti", "enti", "kya", "kaise", "kyun", "hoga", "hogi", "sakte", "sakta", "chalega",
    "play", "work", "works", "possible", "also",
    "ఇంకా", "చూపించు", "చూపించండి", "చూపించాలి", "కూడా", "ఉన్నవి", "ఉన్న", "నాకు", "మాకు", "మా", "నా",
    "ఒక", "ఇతర", "ఇంకొన్ని", "ఇవ్వండి", "ఇవ్వు", "చెప్పు", "చెప్పండి", "అండి", "దయచేసి", "मुझे", "दिखाओ", "दिखाइए", "भी", "और",
    "है", "हैं", "का", "की", "के", "को", "से", "में",
}
_NEED_MARKERS = {
    "want", "need", "needs", "buy", "purchase", "looking", "require", "required", "kavali", "kaavali",
    "kaavaali", "kavalenu", "chahiye", "chaiye", "chahie", "venum", "beku", "konali", "kanali",
    "kavala", "kaavala", "కావాలా", "కావాలి", "కావాల", "కొనాలి", "కొనుక్కోవాలి", "चाहिए", "खरीदना",
}
# Words that only qualify / constrain the current need.
_GENERIC = {
    "online", "offline", "local", "nearby", "used", "new", "second-hand", "secondhand", "refurbished",
    "today", "tomorrow", "now", "tonight", "morning", "evening", "weekend",
    "cheap", "cheaper", "cheapest", "low", "lower", "lowest", "high", "higher", "costly", "expensive",
    "premium", "budget", "affordable", "best", "better", "good", "nice", "top", "quality", "only", "just",
    "pickup", "delivery", "deliver", "cash", "cod", "emi", "exchange", "installation", "warranty",
    "use", "usage", "purpose", "brand", "brands", "make", "model", "type", "kind", "variety", "size", "colour", "color", "multi", "multipurpose", "under", "below", "above", "over", "within",
    "upto", "less", "than", "around", "about", "range", "price", "rate", "cost", "rs", "rupees", "inr",
    "kg", "kgs", "km", "kms", "gm", "grams", "litre", "liter", "pcs", "pieces", "piece", "thousand", "lakh",
    "lakhs", "crore", "hazaar", "hazar", "sasta", "saste", "sasti", "sastha", "chowka", "chauka", "takkuva",
    "ekkuva", "mehenga", "mahanga", "accha", "achha", "behtar", "wala", "wali", "vala", "vali", "valu",
    "matrame", "maatrame", "maatram", "sirf", "bas", "lo", "lone", "daggara", "deggara", "ivva", "ivvu",
    "lopu", "kinda", "paina", "pai", "thakkuva", "manchi", "manchidi",
    "చౌక", "చౌకగా", "తక్కువ", "తక్కువలో", "ఎక్కువ", "మంచి", "మాత్రమే", "లోపు", "లోపల", "పైన", "వేలు", "వేల",
    "లక్ష", "లక్షలు", "బ్రాండ్", "బ్రాండ్లు", "సైజు", "రంగు", "రూపాయలు", "కిలో", "కేజీ", "డెలివరీ", "ఇంటికి", "ఆన్లైన్", "లోకల్", "కొత్త", "పాత",
    "सस्ता", "सस्ते", "सस्ती", "महंगा", "अच्छा", "बेहतर", "वाला", "वाली", "सिर्फ", "हज़ार", "हजार", "लाख",
}
_ACKS = {
    "ok", "okay", "okk", "k", "kk", "yes", "yeah", "yep", "sure", "haan", "ha", "han", "avunu", "sare",
    "sari", "thanks", "thank", "thx", "fine", "great", "theek", "thik", "hmm", "alright", "done", "cool",
    "సరే", "అవును", "ఓకే", "హా", "ధన్యవాదాలు", "థాంక్స్", "ठीक", "हाँ", "हां", "धन्यवाद",
}
_CHOICE = {
    "which", "edi", "yedi", "ediki", "kaunsa", "konsa", "kaun", "better", "behtar", "best", "recommend",
    "suggest", "ఏది", "ఏదీ", "ఏదైతే", "బెటర్", "कौनसा", "कौन", "बेहतर",
}
_RETURN_MARKERS = {
    "back", "again", "previous", "earlier", "before", "old", "malli", "wapas", "phir", "fir", "return",
    "మళ్ళీ", "మళ్లీ", "ముందు", "వాపస్", "फिर", "वापस",
}
_REF_WORDS = {
    "first", "second", "third", "fourth", "options", "results", "1st", "2nd", "3rd", "4th", "one", "ones", "option", "result",
    "this", "that", "these", "those", "it", "them", "they", "their", "same", "above", "shown",
    "modati", "rendava", "moodava", "idi", "adhi", "avi", "veetilo", "daanilo", "vatilo", "vaati", "daani",
    "ఇది", "అది", "అవి", "దాని", "వాటి", "మొదటి", "రెండో", "రెండవ", "మూడో",
}
_ACTION_WORDS = {
    "open", "call", "contact", "direction", "directions", "route", "book", "order", "save", "share",
    "detail", "details", "review", "reviews", "rating", "ratings", "address", "website", "link", "watch",
    "select", "choose", "connect", "apply", "register", "checkout", "number", "chey", "cheyi", "cheyandi",
}
_NON_CONTENT = (_DISPLAY_AND_FILLER | _NEED_MARKERS | _GENERIC | _ACKS | _CHOICE | _RETURN_MARKERS
                | _REF_WORDS | _ACTION_WORDS)


def _content_tokens(text: str) -> set[str]:
    """What the message is ABOUT: words left after grammar, constraints,
    acknowledgements, option references and pure numbers are removed."""
    out = set()
    for token in _tokens(text):
        if token in _NON_CONTENT or _stem(token) in _NON_CONTENT:
            continue
        if any(ch.isdigit() for ch in token) or token in {"₹", "$", "€", "£"}:
            continue
        out.add(_stem(token))
    return out


def _script_family(ch: str) -> str:
    name = unicodedata.name(ch, "")
    for script in ("TELUGU", "DEVANAGARI", "TAMIL", "KANNADA", "MALAYALAM", "BENGALI", "LATIN"):
        if script in name:
            return script.lower()
    return "other"


def _scripts(text: str) -> set[str]:
    return {_script_family(ch) for ch in text if ch.isalpha()} - {"other"}


def _overlap(a: str, b: str) -> float:
    aa, bb = _content_tokens(a), _content_tokens(b)
    if not aa or not bb:
        return 0.0
    return len(aa & bb) / min(len(aa), len(bb))


def _source_mentioned(text: str, sources: Iterable[str]) -> bool:
    low = text.casefold()
    return any(len(str(s).strip()) >= 3 and str(s).strip().casefold() in low for s in sources)


_CHANNEL = re.compile(
    r"(?i)\b(?:on|from|via|through|at)\s+[\w.-]+|[\w.-]+\s+(?:lo|lone|se|mein|nunchi|dwara)\b|\S+(?:లో|నుంచి|ద్వారా)(?:\s|$)"
)


def _normalize_phrases(text: str) -> str:
    # "second hand" is a condition, not "the second (option)".
    return re.sub(r"(?i)\bsecond\s+hand\b", "second-hand", text)


def _looks_like_constraint_fragment(text: str) -> bool:
    """True when a constraint is the message's main content, not incidental:
    at most one concrete word is left besides constraint vocabulary."""
    return len(_content_tokens(text)) <= 1


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
        subject_aliases: Iterable[str] = (),
        location_labels: Iterable[str] = (),
    ) -> ConversationRelation:
        text = _normalize_phrases(" ".join(str(user_text or "").split()))
        subject = " ".join(str(active_subject or "").split())
        # The need in every wording we know (the brain's consolidated English
        # phrase AND the customer's own words): cross-script turns compare
        # against the wording in their own script.
        subjects = [subject] + [" ".join(str(a or "").split()) for a in subject_aliases if str(a or "").strip()]
        has_deck = bool(subject or active_facts)
        if not text:
            return ConversationRelation("unknown", 0.0, has_deck, reason="empty")
        history = [str(old) for old in list(recent_user_turns)[-8:]]
        # The current message may already be the last history entry.
        if history and " ".join(history[-1].split()) == text:
            history = history[:-1]

        # Explicit conversational switch is universal and strongest.
        if _EXPLICIT_SWITCH.search(text):
            return ConversationRelation(
                "new_topic", 0.98, has_deck, subject_replaced=has_deck,
                reason="explicit_switch",
            )

        words = _tokens(text)
        content = _content_tokens(text)
        active_overlap = max((_overlap(text, s) for s in subjects if s), default=0.0)
        history_best, history_turn = 0.0, ""
        for old in history:
            ov = _overlap(text, old)
            if ov > history_best:
                history_best, history_turn = ov, old
        refers = bool({_stem(w) for w in _raw_tokens(text)} & _REF_WORDS)

        if has_deck:
            # "ok" / "yes" / "సరే" after results continues the same need.
            if words and words <= (_ACKS | _DISPLAY_AND_FILLER):
                return ConversationRelation("same_topic", 0.86, True, reason="acknowledgement")
            # An action on a shown option ("call the second one", "directions").
            if (words & _ACTION_WORDS or _ACTION.search(text)) and (refers or not content):
                return ConversationRelation("result_action", 0.93, True, reason="option_action")
            if _COMPARE.search(text) or (words & _CHOICE and len(content) <= 1 and not words & _NEED_MARKERS):
                named = named_comparison_entities(text, location_labels=location_labels)
                # Comparing what is on screen (or metadata of it, e.g. a
                # place) stays with the deck; comparing NEW named things that
                # share nothing with the active need is a new subject.
                new_things = [n for n in named if _content_tokens(n) and
                              max((_overlap(n, s) for s in subjects if s), default=0.0) == 0
                              and not (_content_tokens(n) <= {"option", "result"})]
                # A choice question without comparison syntax ("ఏది మంచిది?",
                # "which one is better") is always about what is on screen.
                same = refers or active_overlap > 0 or not new_things or not _COMPARE.search(text)
                return ConversationRelation(
                    "comparison", 0.91, True, subject_replaced=not same,
                    reason="comparison",
                )
            source_mentioned = _source_mentioned(text, shown_sources)
            if source_mentioned and history_best <= active_overlap:
                return ConversationRelation("refinement", 0.94, True, reason="shown_source")
            # Constraint-only fragments ("sasta wala dikhao", "under 15000",
            # "30-40 వేలు", "Meesho lo ivva"): same need, one dimension changes.
            if not content and words:
                return ConversationRelation("refinement", 0.91, True, reason="constraint")
            # One concrete word plus constraint words is a refinement only
            # when that word names WHERE / HOW ("Meesho lo ivva", "on Amazon")
            # or belongs to the active need; "second hand tractor" is a new
            # thing, left to the semantic judge.
            channel_or_same = bool(_CHANNEL.search(text)) or active_overlap > 0 or not content
            if (_CONSTRAINT.search(text) or words & _GENERIC) and _looks_like_constraint_fragment(text) \
                    and channel_or_same and history_best <= active_overlap \
                    and not (words & _NEED_MARKERS and content):
                return ConversationRelation("refinement", 0.91, True, reason="constraint")
            if refers and len(content) <= 2 and not (words & _NEED_MARKERS):
                return ConversationRelation("same_topic", 0.86, True, reason="anaphora")
            if active_overlap >= 0.34 and active_overlap >= history_best:
                return ConversationRelation("same_topic", 0.86, True, reason="subject_overlap")

        # Returning to something said recently is distinct from a new subject.
        if history_best >= 0.5 and history_turn:
            old_vs_active = max((_overlap(history_turn, s) for s in subjects if s), default=0.0)
            if not has_deck or old_vs_active < 0.2 or words & _RETURN_MARKERS:
                return ConversationRelation(
                    "return_to_previous", 0.75, has_deck,
                    subject_replaced=has_deck and old_vs_active < 0.2,
                    reason="history_overlap",
                )
            return ConversationRelation("same_topic", 0.8, True, reason="history_is_active_need")

        # Do not keyword-guess a new category. A substantial independent
        # utterance (two+ content words, or a stated new need) that shares
        # nothing with the active need -- in a script we can compare -- is a
        # likely topic change. A single new word after "I want" could be a
        # brand or variant of the same need: the model decides that one.
        text_scripts = _scripts(" ".join(content))
        subject_scripts = set().union(*[_scripts(s) for s in subjects if s]) if subjects else set()
        comparable_script = bool(text_scripts & subject_scripts)
        if has_deck and content and active_overlap == 0 and comparable_script:
            if len(content) >= 2:
                return ConversationRelation(
                    "new_topic", 0.74, True, subject_replaced=True,
                    reason="independent_subject",
                )
            # One new word ("Samsung only", "rice purchase") may be a brand /
            # variant of the same need or a new thing: a WEAK signal that only
            # counts when the model agrees (see resolve_new_need / decide).
            return ConversationRelation(
                "new_topic", 0.6, True, subject_replaced=True,
                reason="single_new_word",
            )

        return ConversationRelation("unknown", 0.35, has_deck, reason="ambiguous")
