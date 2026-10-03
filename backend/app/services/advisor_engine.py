"""Universal Advisor core: which questions matter, what the user already
said (field by field), and guidance on trade-offs -- for every category.

One engine, configured by data (Command Center resources
``advisor_categories``, ``advisor_questions`` and ``advisor_rules``), never a
per-category code path:

* The request is matched to an advisor CATEGORY: the AI-detected category
  first, then the HEAD noun of what was asked ("car phone holder" -> holder
  -> accessories; "phone holder for car" -> the same), only then any alias
  inside the text. The category's decision fields say what to ask and which
  answers are required -- no keyword ever triggers a question by itself.

* Every field has its own state: ``known``, ``no_preference`` (the user said
  "any" for THAT field only) or ``unknown``. "Any brand" never settles budget.
* Only questions that change the decision are asked: matching category /
  keywords, field still unknown, dependencies known, at most N per turn,
  required questions first. A required question holds final recommendations
  until it is answered (or the user says "show me now").
* Guidance rules explain what matters (standing all day -> comfort, grip...)
  and never force a choice; high-stakes rules add a "no guarantees / ask a
  professional" boundary.

Defaults below are SEEDED into the Command Center the first time (so staff
can edit, disable or extend them without a release); after that only the
stored records are used.
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Optional, Tuple

from app.services import advisor_defaults

ANY_WORDS = {
    "any", "anything", "any brand", "any one", "anyone", "no preference", "doesn't matter", "does not matter",
    "dont care", "don't care", "whatever", "not sure", "no idea", "no", "none", "skip",
    "ఏదైనా", "ఏదైనా సరే", "ఏదో ఒకటి", "పర్వాలేదు", "ఏదైనా పర్వాలేదు", "తెలియదు",
    "कोई भी", "कुछ भी", "कोई फर्क नहीं", "पता नहीं",
}

# Field -> how the structured demand already carries it.
_FIELD_KEYS: Dict[str, tuple] = {
    "budget": ("budget", "budget_max", "budget_min", "price_max", "max_price"),
    "brand": ("brand", "make"),
    "usage": ("usage", "use", "purpose", "intended_use"),
    "size": ("size", "shoe_size", "screen_size"),
    "quantity": ("quantity",),
    "condition": ("condition",),
    "model": ("model",),
    "variant": ("variant",),
    "timing": ("timing", "when", "date", "time"),
    "location": ("location",),
    "quality": ("quality",),
    "material": ("material", "fabric"),
    "capacity": ("capacity",),
    "duration": ("duration",),
    "guests": ("guests", "people", "persons"),
    "travel_dates": ("travel_dates", "check_in", "dates"),
    "experience": ("experience",),
    "property_type": ("property_type", "bhk"),
    "income": ("income",),
    "coverage": ("coverage", "sum_insured"),
    "requirement": ("requirement", "speciality", "specialty", "issue", "problem", "symptom_area"),
    "goal": ("goal", "objective", "loan_purpose", "loan_amount", "course_goal"),
}

# Settled when the request itself is more specific than a broad word
# ("dentist" / "AC repair" / "home loan" vs "doctor" / "repair" / "loan").
SPECIFICITY_FIELDS = ("requirement", "goal", "property_type")

_FOOTWEAR = ["shoe", "shoes", "sneaker", "sneakers", "sandal", "sandals", "slipper", "slippers", "footwear", "boots",
             "చెప్పులు", "షూస్", "जूते"]
_HIGH_TICKET = ["tv", "television", "phone", "mobile", "laptop", "fridge", "refrigerator", "washing machine", "ac",
                "air conditioner", "bike", "scooter", "car", "sofa", "furniture", "cooler", "inverter", "tablet",
                "camera", "watch", "smartwatch", "headphones", "earbuds", "speaker", "geyser", "chimney",
                "mattress", "cycle", "bicycle", "dress", "saree", "kurti", "jeans", "shirt", "jacket"] + _FOOTWEAR

# v1 keyword defaults -- kept only so the v2 seed can archive the untouched
# copies already stored; they are never seeded again.
LEGACY_QUESTIONS: List[Dict[str, Any]] = [
    {"category": "any", "keywords": _HIGH_TICKET, "field": "budget", "required": True, "priority": 900,
     "answer_type": "money", "question_en": "What budget do you have in mind?",
     "question_te": "మీ బడ్జెట్ ఎంత అనుకుంటున్నారు?", "question_hi": "आपका बजट कितना है?",
     "choices": [], "why": "Budget changes which options are worth showing first."},
    {"category": "any", "keywords": _FOOTWEAR, "field": "usage", "required": False, "priority": 800,
     "answer_type": "choice", "question_en": "What will you mostly use them for -- running, standing all day, office or casual?",
     "question_te": "వీటిని ఎక్కువగా దేనికి వాడతారు -- పరుగు, రోజంతా నిలబడటం, ఆఫీస్ లేదా క్యాజువల్?",
     "question_hi": "इन्हें ज़्यादातर किसके लिए पहनेंगे -- दौड़, पूरे दिन खड़े रहना, ऑफिस या कैज़ुअल?",
     "choices": ["Running", "Standing all day", "Office", "Casual"],
     "why": "Comfort, cushioning and grip matter more for long standing; weight for running."},
    {"category": "any", "keywords": _FOOTWEAR, "field": "size", "required": False, "priority": 700,
     "answer_type": "text", "question_en": "Which size do you wear?", "question_te": "మీ సైజు ఎంత?",
     "question_hi": "आपका साइज़ क्या है?", "choices": [], "depends_on": ["usage"], "why": ""},
    {"category": "any", "keywords": ["tv", "television", "టీవీ"], "field": "size", "required": False,
     "priority": 800, "answer_type": "choice", "question_en": "Which screen size suits your room?",
     "question_te": "మీ గదికి ఏ స్క్రీన్ సైజు సరిపోతుంది?", "question_hi": "आपके कमरे के लिए कौन सा स्क्रीन साइज़?",
     "choices": ["32 inch", "43 inch", "55 inch"], "why": "Viewing distance decides the useful size."},
    {"category": "any", "keywords": ["car", "bike", "scooter", "vehicle", "కారు", "బైక్"], "field": "condition",
     "required": False, "priority": 850, "answer_type": "choice", "question_en": "New or used?",
     "question_te": "కొత్తదా లేక వాడినదా?", "question_hi": "नई या पुरानी?", "choices": ["New", "Used"],
     "why": "Used vehicles need inspection, papers and service history."},
    {"category": "any", "keywords": ["hotel", "room", "stay", "lodge", "హోటల్"], "field": "travel_dates",
     "required": True, "priority": 900, "answer_type": "date", "question_en": "For which dates?",
     "question_te": "ఏ తేదీలకు?", "question_hi": "किन तारीखों के लिए?", "choices": [],
     "why": "Availability and price depend on the dates."},
    {"category": "any", "keywords": ["hotel", "room", "stay", "bus", "flight", "train", "ticket"],
     "field": "guests", "required": False, "priority": 800, "answer_type": "number",
     "question_en": "For how many people?", "question_te": "ఎంతమందికి?", "question_hi": "कितने लोगों के लिए?",
     "choices": [], "why": ""},
    {"category": "any", "keywords": ["repair", "service", "plumber", "electrician", "cleaning", "installation",
                                     "రిపేర్", "సర్వీస్"], "field": "timing", "required": False, "priority": 800,
     "answer_type": "text", "question_en": "When do you need it -- today, tomorrow or later?",
     "question_te": "ఎప్పుడు కావాలి -- ఈరోజు, రేపు లేదా తర్వాత?", "question_hi": "कब चाहिए -- आज, कल या बाद में?",
     "choices": ["Today", "Tomorrow", "This week"], "why": "Urgency decides which providers can come."},
    {"category": "any", "keywords": ["job", "jobs", "vacancy", "hiring", "ఉద్యోగం", "नौकरी"], "field": "experience",
     "required": False, "priority": 700, "answer_type": "text", "question_en": "How much experience do you have?",
     "question_te": "మీకు ఎంత అనుభవం ఉంది?", "question_hi": "आपके पास कितना अनुभव है?", "choices": [], "why": ""},
    {"category": "any", "keywords": ["insurance", "policy", "బీమా", "बीमा"], "field": "coverage",
     "required": False, "priority": 800, "answer_type": "text",
     "question_en": "What should it cover, and for how many people?",
     "question_te": "ఏ కవరేజ్ కావాలి, ఎంతమందికి?", "question_hi": "किसका कवर चाहिए और कितने लोगों के लिए?",
     "choices": [], "why": "Coverage and members decide which plans are comparable."},
    {"category": "any", "keywords": ["loan", "credit card", "రుణం", "లోన్", "लोन"], "field": "income",
     "required": False, "priority": 800, "answer_type": "text",
     "question_en": "Roughly what monthly income range should I consider? (Only a range -- no documents.)",
     "question_te": "నెలవారీ ఆదాయం సుమారుగా ఏ పరిధిలో ఉంది? (పరిధి మాత్రమే, పత్రాలు వద్దు.)",
     "question_hi": "मासिक आय लगभग किस सीमा में है? (सिर्फ़ सीमा, कोई दस्तावेज़ नहीं।)",
     "choices": [], "why": "Eligibility depends on it; ASKODOX never asks for PAN/Aadhaar here."},
    {"category": "any", "keywords": ["flat", "house", "plot", "rent", "apartment", "bhk", "ఇల్లు"],
     "field": "budget", "required": True, "priority": 900, "answer_type": "money",
     "question_en": "What budget (or monthly rent) are you looking at?",
     "question_te": "మీ బడ్జెట్ (లేదా నెల అద్దె) ఎంత?", "question_hi": "बजट (या मासिक किराया) कितना है?",
     "choices": [], "why": "Budget and locality decide which listings are realistic."},
]

DEFAULT_RULES: List[Dict[str, Any]] = [
    {"title": "Standing all day", "category": "any",
     "keywords": ["standing", "stand all day", "on my feet", "నిలబడ", "खड़े"],
     "factors": ["comfort", "cushioning", "grip", "weight", "durability"],
     "advice_en": "For standing all day, comfort and cushioning usually matter more than looks; a non-slip sole "
                  "and a light, durable build help over long shifts.",
     "advice_te": "రోజంతా నిలబడే పనికి, లుక్ కంటే సౌకర్యం, కుషనింగ్ ఎక్కువ ముఖ్యం; జారని సోల్, తేలికైన మన్నికైన నిర్మాణం "
                  "పనికొస్తాయి.",
     "advice_hi": "पूरे दिन खड़े रहने के लिए दिखावट से ज़्यादा आराम और कुशनिंग मायने रखती है; फिसलन-रोधी सोल और "
                  "हल्की, टिकाऊ बनावट मदद करती है।",
     "high_stakes": False, "priority": 500},
    {"title": "Running", "category": "any", "keywords": ["running", "jogging", "రన్నింగ్", "दौड़"],
     "factors": ["cushioning", "weight", "fit", "breathability"],
     "advice_en": "For running, a light shoe with good cushioning and a snug fit matters most; try for size in the "
                  "evening when feet are larger.",
     "advice_te": "పరుగుకు తేలికైన, మంచి కుషనింగ్, సరిగ్గా సరిపోయే షూ ముఖ్యం.",
     "advice_hi": "दौड़ के लिए हल्का, अच्छी कुशनिंग वाला और सही फ़िट जूता ज़रूरी है।",
     "high_stakes": False, "priority": 400},
    {"title": "Health decisions", "category": "any",
     "keywords": ["doctor", "hospital", "medicine", "symptom", "diagnosis", "treatment", "ఆసుపత్రి", "डॉक्टर"],
     "factors": ["qualified professional", "verified provider", "emergency care"],
     "advice_en": "ASKODOX can help you find and compare providers, but it cannot diagnose. For symptoms, please "
                  "consult a qualified doctor; in an emergency call 108.",
     "advice_te": "ASKODOX ప్రొవైడర్లను కనుగొనడంలో సహాయపడుతుంది, కానీ రోగనిర్ధారణ చేయదు. లక్షణాలకు అర్హత గల వైద్యుడిని "
                  "సంప్రదించండి; అత్యవసరమైతే 108కి కాల్ చేయండి.",
     "advice_hi": "ASKODOX प्रदाता खोजने में मदद कर सकता है, पर निदान नहीं कर सकता। लक्षणों के लिए योग्य डॉक्टर से "
                  "मिलें; आपात स्थिति में 108 पर कॉल करें।",
     "high_stakes": True, "priority": 900},
    {"title": "Money decisions", "category": "any",
     "keywords": ["loan", "insurance", "invest", "mutual fund", "credit card", "లోన్", "బీమా", "लोन", "बीमा"],
     "factors": ["total cost", "terms", "regulated provider", "your eligibility"],
     "advice_en": "Compare the total cost and terms, and check the provider is regulated. No approval, eligibility "
                  "or return is guaranteed -- the provider decides after their checks.",
     "advice_te": "మొత్తం ఖర్చు, షరతులు పోల్చండి; ప్రొవైడర్ నియంత్రిత సంస్థేనా చూడండి. ఆమోదం, అర్హత లేదా రాబడి హామీ "
                  "లేదు -- వారి తనిఖీ తర్వాత ప్రొవైడర్ నిర్ణయిస్తారు.",
     "advice_hi": "कुल लागत और शर्तें तुलना करें और देखें कि प्रदाता विनियमित है। कोई मंज़ूरी, पात्रता या रिटर्न "
                  "गारंटीड नहीं है।",
     "high_stakes": True, "priority": 900},
    {"title": "Used vehicles", "category": "any", "keywords": ["used car", "used bike", "second hand car", "old car"],
     "factors": ["papers / RC", "service history", "kilometres", "inspection"],
     "advice_en": "For a used vehicle, check the RC and insurance, service history and kilometres, and get it "
                  "inspected before paying.",
     "advice_te": "వాడిన వాహనానికి RC, ఇన్సూరెన్స్, సర్వీస్ హిస్టరీ, కిలోమీటర్లు చూసి, డబ్బు ఇచ్చే ముందు తనిఖీ చేయించండి.",
     "advice_hi": "पुरानी गाड़ी के लिए RC, बीमा, सर्विस हिस्ट्री और किलोमीटर देखें और भुगतान से पहले जाँच कराएँ।",
     "high_stakes": False, "priority": 600},
]


def is_no_preference(value: Any) -> bool:
    text = re.sub(r"[.!?,]+$", "", str(value or "").strip().casefold())
    return text in ANY_WORDS


def _lang(language: str) -> str:
    code = str(language or "en").split("-")[0].lower()
    return code if code in {"en", "te", "hi"} else "en"


def _text_of(demand: Dict[str, Any]) -> str:
    constraints = demand.get("constraints") or {}
    trace = demand.get("trace") or {}
    return " ".join(str(x or "") for x in (demand.get("subject"), demand.get("raw_text"), trace.get("query"),
                                           constraints.get("usage"))).casefold()


# ------------------------------------------------------------ category --

_GENERIC = {"", "product", "products", "service", "services", "general", "unknown", "other", "commerce", "item",
            "items", "need", "offer", "none", "null", "misc", "any"}
# Words after which the rest of a phrase only qualifies the head noun.
_CUT_WORDS = {"for", "with", "under", "below", "above", "near", "in", "from", "to", "at", "within", "around",
              "upto", "between", "without", "like", "kosam", "కోసం", "కి", "లో", "के", "लिए", "में", "वाला", "वाली"}
_FILLER = {"a", "an", "the", "i", "want", "need", "needed", "buy", "get", "please", "pls", "now", "today", "nearby",
           "me", "my", "good", "best", "new", "cheap", "some", "one", "kavali", "kaavali", "కావాలి",
           "కొనాలి", "చూపించు", "ఒక", "మంచి", "chahiye", "चाहिए", "एक", "अच्छा", "अच्छी", "show", "find", "looking",
           "search", "is", "are", "of", "and", "or", "pair", "piece", "pieces", "kg", "litre", "liter", "l", "g"}


def _tokens(text: Any) -> List[str]:
    return [t for t in re.split(r"[\s,.;:!?/()\[\]{}\"'|+&-]+", str(text or "").casefold()) if t]


def _is_number(token: str) -> bool:
    return bool(re.fullmatch(r"[\d.,]+[a-z]*", token))


def _head(tokens: List[str]) -> List[str]:
    """The noun phrase that names the thing: cut at the first qualifier
    ("for / with / under ..."), then drop trailing filler and numbers."""
    out: List[str] = []
    for token in tokens:
        if token in _CUT_WORDS and out:
            break
        out.append(token)
    while out and (out[-1] in _FILLER or _is_number(out[-1])):
        out.pop()
    return out


def _tok_eq(have: str, alias: str) -> bool:
    # Indian-language nouns take suffixes (కారుకి, कार की): accept a prefix match
    # for non-ASCII aliases; English needs the exact token.
    return have == alias or (not alias.isascii() and len(alias) >= 2 and have.startswith(alias))


def _ends_with(tokens: List[str], alias: List[str]) -> bool:
    n = len(alias)
    return 0 < n <= len(tokens) and all(_tok_eq(h, a) for h, a in zip(tokens[-n:], alias))


def _contains(tokens: List[str], alias: List[str]) -> bool:
    n = len(alias)
    return any(all(_tok_eq(h, a) for h, a in zip(tokens[i:i + n], alias)) for i in range(0, len(tokens) - n + 1)) \
        if n else False


def _ai_categories(demand: Dict[str, Any]) -> List[str]:
    constraints = demand.get("constraints") or {}
    trace = demand.get("trace") or {}
    values: List[Any] = [constraints.get(k) for k in ("category_detected", "subcategory_detected", "category",
                                                      "product_category", "service_category", "product_type",
                                                      "service_type")]
    cats = trace.get("categories")
    values += list(cats) if isinstance(cats, (list, tuple)) else [cats]
    values += [trace.get("category"), demand.get("category")]
    out = []
    for value in values:
        text = " ".join(str(value or "").replace("_", " ").split())
        if text and text.casefold() not in _GENERIC and text not in out:
            out.append(text)
    return out


def _subjects(demand: Dict[str, Any]) -> List[str]:
    trace = demand.get("trace") or {}
    out = []
    for value in (demand.get("subject"), trace.get("query"), demand.get("raw_text")):
        text = str(value or "").strip()
        if text and text not in out:
            out.append(text)
    return out


def _active_categories(records: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [c for c in _active(records) if str(c.get("key") or "").strip()]


def resolve_category(demand: Dict[str, Any], category_records: Iterable[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Best advisor category for a request, with how it was matched.

    Tiers (higher wins, then the longer alias, then priority):
    4 AI category ends with an alias  ("Car accessories" -> accessories)
    3 head noun of the request        ("car phone holder" -> holder)
    2 AI category contains an alias
    1 any alias anywhere in the request text
    """
    cats = _active_categories(category_records)
    if not cats:
        return None
    subjects = [_tokens(t) for t in _subjects(demand)]
    # category_signal falls back to the subject itself when nothing better
    # was detected: that is the request's own words, not an AI category.
    ai = [_head(t) for t in (_tokens(c) for c in _ai_categories(demand)) if t and t not in subjects]
    heads = [_head(t) for t in subjects]
    best: Optional[Tuple[Tuple[int, int, int], Dict[str, Any], str, str]] = None
    for cat in cats:
        for raw_alias in cat.get("aliases") or []:
            alias = _tokens(raw_alias)
            if not alias:
                continue
            tier, how = 0, ""
            if any(_ends_with(t, alias) for t in ai):
                tier, how = 4, "ai_category"
            elif any(_ends_with(h, alias) for h in heads):
                tier, how = 3, "head_noun"
            elif any(_contains(t, alias) for t in ai):
                tier, how = 2, "ai_category_word"
            elif any(_contains(t, alias) for t in subjects):
                tier, how = 1, "mentioned"
            if not tier:
                continue
            rank = (tier, len(" ".join(alias)), int(cat.get("priority") or 0))
            if best is None or rank > best[0]:
                best = (rank, cat, how, " ".join(alias))
    if best is None:
        return None
    # The AI often names a broad group ("fashion", "electronics") while the
    # head noun names the specific kind ("shoes" -> footwear). Within the
    # same group the head noun is more specific, so it wins.
    if best[2].startswith("ai_category"):
        for cat in cats:
            if cat is best[1] or str(cat.get("group") or "") != str(best[1].get("group") or ""):
                continue
            for raw_alias in cat.get("aliases") or []:
                alias = _tokens(raw_alias)
                if alias and any(_ends_with(h, alias) for h in heads):
                    best = ((3, len(" ".join(alias)), 0), cat, "head_noun", " ".join(alias))
                    break
            if best[2] == "head_noun":
                break
    _, cat, how, alias = best
    return {"id": cat.get("_id"), "key": str(cat.get("key")), "label": cat.get("label") or cat.get("key"),
            "group": cat.get("group") or "", "matched_by": how, "alias": alias,
            "high_stakes": bool(cat.get("high_stakes")),
            "required_fields": [str(f) for f in cat.get("required_fields") or []],
            "optional_fields": [str(f) for f in cat.get("optional_fields") or []],
            "broad_aliases": [" ".join(_tokens(a)) for a in cat.get("broad_aliases") or []]}


def _more_specific(demand: Dict[str, Any], category: Dict[str, Any]) -> bool:
    """True when the request names more than a broad word of its category."""
    if category["alias"] not in category["broad_aliases"]:
        return True
    location = set(_tokens(demand.get("location_text")))
    alias = set(category["alias"].split())
    for text in _subjects(demand)[:2]:
        extra = [t for t in _tokens(text) if t not in alias and t not in _FILLER and t not in _CUT_WORDS
                 and t not in location and not _is_number(t) and t not in category["broad_aliases"]]
        if extra:
            return True
    return False


# --------------------------------------------------------------- state --

def field_states(demand: Dict[str, Any], category: Optional[Dict[str, Any]] = None) -> Dict[str, str]:
    """Each advisor field: known / no_preference / unknown -- independently."""
    constraints = dict(demand.get("constraints") or {})
    dynamic = dict(constraints.get("dynamic_fields") or {})
    bag = {**constraints, **dynamic}
    no_pref = {str(f) for f in (bag.get("no_preference") or [])}
    specific = bool(category) and _more_specific(demand, category)
    states: Dict[str, str] = {}
    for field, keys in _FIELD_KEYS.items():
        if field in no_pref:
            states[field] = "no_preference"
            continue
        value = next((bag.get(k) for k in keys if bag.get(k) not in (None, "", [])), None)
        if field == "budget" and value is None and demand.get("price"):
            value = demand.get("price")
        if field == "quantity" and value is None and demand.get("quantity"):
            value = demand.get("quantity")
        if field in ("timing", "travel_dates") and value is None and demand.get("when_text"):
            value = demand.get("when_text")
        if field == "location" and value is None and demand.get("location_text"):
            value = demand.get("location_text")
        if field in SPECIFICITY_FIELDS and value is None and specific:
            value = category["alias"]
        if value is None:
            states[field] = "unknown"
        elif is_no_preference(value):
            states[field] = "no_preference"
        else:
            states[field] = "known"
    return states


def _category_ok(question: Dict[str, Any], demand: Dict[str, Any]) -> bool:
    wanted = str(question.get("category") or "any").strip().casefold()
    if wanted in {"", "any", "*"}:
        return True
    constraints = demand.get("constraints") or {}
    have = {str(x or "").casefold() for x in (demand.get("domain"), constraints.get("category_detected"),
                                               constraints.get("subcategory_detected"))}
    return wanted in have


def _keywords_ok(keywords: Iterable[str], text: str) -> bool:
    words = [str(k).casefold().strip() for k in keywords or [] if str(k).strip()]
    if not words:
        return True
    return any(re.search(rf"(?<!\w){re.escape(k)}(?!\w)", text) for k in words)


def _active(records: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [dict(r.get("data") or {}, _id=r.get("id")) for r in records or []
            if r.get("status") == "ACTIVE" and not r.get("archived")]


def _shape(q: Dict[str, Any], lang: str, *, field: str, required: bool) -> Dict[str, Any]:
    return {
        "id": q.get("_id"), "field": field, "required": required,
        "question": q.get(f"question_{lang}") or q.get("question_en"),
        "answer_type": q.get("answer_type") or "text", "choices": list(q.get("choices") or []),
        "why": q.get("why") or "",
    }


def _wording(field: str, category_key: str, records: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """This category's question for the field, else the generic one. A field
    whose stored questions are all disabled is not asked; the built-in
    generic wording is used only when nothing is stored for the field."""
    stored = [dict(r.get("data") or {}, _id=r.get("id"), _status=r.get("status")) for r in records
              if not r.get("archived") and (r.get("data") or {}).get("field") == field]
    own = [q for q in stored if str(q.get("category") or "").casefold() == category_key]
    generic = [q for q in stored if str(q.get("category") or "any").casefold() in {"", "any", "*"}
               and not q.get("keywords")]
    for group in (own, generic):
        live = [q for q in group if q["_status"] == "ACTIVE"]
        if live:
            return max(live, key=lambda q: int(q.get("priority") or 0))
        if group:
            return None  # staff switched this wording off
    if stored:
        return None
    return next((dict(q, _id=None) for q in advisor_defaults.DEFAULT_FIELD_QUESTIONS if q["field"] == field), None)


def _category_questions(demand, category, records, states, lang, asked_set, skip) -> List[Dict[str, Any]]:
    out = []
    fields = [(f, True) for f in category["required_fields"]]
    fields += [(f, False) for f in category["optional_fields"] if f not in category["required_fields"]]
    for field, required in fields:
        if field in skip or field in asked_set or states.get(field, "unknown") != "unknown":
            continue
        q = _wording(field, category["key"].casefold(), records)
        if q is None:
            continue
        if any(states.get(f) == "unknown" for f in q.get("depends_on") or [] if f not in skip):
            continue
        if any(states.get(f) in {"known", "no_preference"} for f in q.get("skip_if") or []):
            continue
        out.append(_shape(q, lang, field=field, required=required))
    return out


def _legacy_questions(demand, records, states, lang, asked_set, skip) -> List[Dict[str, Any]]:
    """Staff keyword questions -- only when no advisor category matched."""
    text = _text_of(demand)
    picked: Dict[str, Dict[str, Any]] = {}
    for q in _active(records):
        field = str(q.get("field") or "")
        if not q.get("keywords") or field in skip:
            continue
        if states.get(field, "unknown") != "unknown" or field in asked_set:
            continue
        if not _category_ok(q, demand) or not _keywords_ok(q.get("keywords"), text):
            continue
        if any(states.get(f) == "unknown" for f in q.get("depends_on") or []):
            continue
        if any(states.get(f) in {"known", "no_preference"} for f in q.get("skip_if") or []):
            continue
        current = picked.get(field)
        rank = (bool(q.get("required")), int(q.get("priority") or 0))
        if current is None or rank > (bool(current.get("required")), int(current.get("priority") or 0)):
            picked[field] = q
    ordered = sorted(picked.values(), key=lambda q: (not q.get("required"), -int(q.get("priority") or 0)))
    return [_shape(q, lang, field=str(q.get("field")), required=bool(q.get("required"))) for q in ordered]


def next_questions(demand: Dict[str, Any], question_records: Iterable[Dict[str, Any]], *, language: str = "en",
                   limit: int = 1, asked: Iterable[str] = (), category_records: Iterable[Dict[str, Any]] = (),
                   skip_fields: Iterable[str] = (), category: Optional[Dict[str, Any]] = None
                   ) -> List[Dict[str, Any]]:
    """The most decision-relevant unanswered questions (required first)."""
    if str(demand.get("side") or "NEED").upper() == "OFFER":
        return []  # a seller listing is not a buying decision
    records = list(question_records or [])
    if category is None:
        category = resolve_category(demand, category_records)
    states = field_states(demand, category)
    lang = _lang(language)
    asked_set = {str(a) for a in asked or []}
    skip = {str(f) for f in skip_fields or []}
    if category:
        found = _category_questions(demand, category, records, states, lang, asked_set, skip)
    else:
        found = _legacy_questions(demand, records, states, lang, asked_set, skip)
    return found[:max(0, limit)]


def guidance(demand: Dict[str, Any], rule_records: Iterable[Dict[str, Any]], *, language: str = "en",
             limit: int = 2, category: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
    text = _text_of(demand)
    lang = _lang(language)
    key = (category or {}).get("key", "").casefold()
    hits = []
    for r in _active(rule_records):
        rule_cat = str(r.get("category") or "any").strip().casefold()
        if key and rule_cat == key:
            if _keywords_ok(r.get("keywords"), text):  # no keywords = the whole category
                hits.append(r)
        elif _category_ok(r, demand) and r.get("keywords") and _keywords_ok(r.get("keywords"), text):
            hits.append(r)
    hits.sort(key=lambda r: (not r.get("high_stakes"), -int(r.get("priority") or 0)))
    out = [{"title": r.get("title"), "factors": list(r.get("factors") or []),
            "advice": r.get(f"advice_{lang}") or r.get("advice_en"), "high_stakes": bool(r.get("high_stakes"))}
           for r in hits[:limit]]
    if category and category.get("high_stakes") and not any(g["high_stakes"] for g in out):
        out.insert(0, {"title": "No guarantees", "factors": ["qualified professional", "provider's own checks"],
                       "advice": advisor_defaults.HIGH_STAKES_NOTE[lang], "high_stakes": True})
        out = out[:max(limit, 1)]
    return out


def advise(demand: Dict[str, Any], question_records, rule_records, *, language: str = "en", limit: int = 1,
           asked: Iterable[str] = (), show_now: bool = False, category_records: Iterable[Dict[str, Any]] = (),
           skip_fields: Iterable[str] = ()) -> Dict[str, Any]:
    """The advisor's view of one turn: category, questions, readiness, guidance."""
    category = resolve_category(demand, category_records)
    pending = next_questions(demand, question_records, language=language, limit=max(limit, 3), asked=asked,
                             skip_fields=skip_fields, category=category)
    # A required field the user already skipped once is not held again.
    required = [q for q in pending if q["required"]]
    public_category = None
    if category:
        public_category = {k: category[k] for k in ("key", "label", "group", "matched_by", "alias", "high_stakes")}
        public_category["required_fields"] = category["required_fields"]
        public_category["optional_fields"] = category["optional_fields"]
    return {
        "category": public_category,
        "field_states": field_states(demand, category),
        "questions": pending[:limit],
        # Final recommendations wait for a required answer unless the user
        # explicitly asked to see options now.
        "ready": show_now or not required,
        "hold_reason": None if (show_now or not required) else f"needs {required[0]['field']}",
        "guidance": guidance(demand, rule_records, language=language, category=category),
    }


SEED_ACTOR = "system"


def seed_defaults(resources, actor: str = SEED_ACTOR) -> int:
    """Store the editable defaults so the Command Center owns them.

    * ``advisor_rules``: only into an empty resource.
    * v2 (once, when ``advisor_categories`` has never held a record): store
      the categories and the per-field / per-category questions, and archive
      the v1 keyword questions that were seeded and never edited (an edited or
      staff-made question is kept and still used when no category matches).
    """
    created = 0
    repo = resources.repo
    if not repo.list("advisor_rules", include_archived=True):
        for row in DEFAULT_RULES:
            resources.create("advisor_rules", dict(row), actor=actor)
            created += 1
    if repo.list("advisor_categories", include_archived=True):
        return created
    legacy = {q["question_en"] for q in LEGACY_QUESTIONS}
    for record in repo.list("advisor_questions"):
        data = record.get("data") or {}
        if (record.get("created_by") == SEED_ACTOR and int(record.get("version") or 1) <= 1
                and data.get("keywords") and data.get("question_en") in legacy):
            repo.update(record["id"], actor="system:advisor_v2", action="archive", archived=True)
    existing = {(str((r.get("data") or {}).get("category") or "any").casefold(), (r.get("data") or {}).get("field"))
                for r in repo.list("advisor_questions") if not (r.get("data") or {}).get("keywords")}
    for row in advisor_defaults.question_records():
        if (row["category"].casefold(), row["field"]) in existing:
            continue
        resources.create("advisor_questions", row, actor=actor)
        created += 1
    for row in advisor_defaults.category_records():
        resources.create("advisor_categories", row, actor=actor)
        created += 1
    return created
