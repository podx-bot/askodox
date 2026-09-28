"""Lightweight domain adapters over the ONE universal core.

An adapter only configures: which schema (required fields) applies, the
noun used for local business search, the actions the result supports, and
domain safety notes. It never contains its own matching or conversation
logic. Detection is by what the need is about, in any wording.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from app.services.universal_category_schema import UniversalCategorySchemaRegistry


@dataclass(frozen=True)
class DomainAdapter:
    key: str
    schema: str
    search_noun: str          # appended to the need for Places ("near X")
    actions: tuple[str, ...]
    pattern: str

    def required_fields(self) -> tuple[str, ...]:
        return UniversalCategorySchemaRegistry.resolve(self.schema).required_fields


ADAPTERS = (
    DomainAdapter("healthcare", "HEALTHCARE", "", ("book_appointment", "call", "directions"),
                  r"\b(doctor|hospital|clinic|dentist|dental|tooth\w*|teeth|fever|pain|aches?|skin|eye|pregnan\w*|"
                  r"child specialist|pediatric|ortho|cardio|physician|health checkup|diagnostic|scan|lab test)\b"
                  r"|డాక్టర్|ఆసుపత్రి|హాస్పిటల్|దంత|జ్వరం"),
    DomainAdapter("hotel", "HOTEL", "hotel", ("check_availability", "book", "directions"),
                  r"\b(hotel|lodge|room for|rooms|stay|resort|guest house|homestay|check[- ]?in)\b|హోటల్|లాడ్జ్"),
    DomainAdapter("salon", "SALON", "salon", ("book_appointment", "call"),
                  r"\b(salon|haircut|hair cut|beauty parlou?r|parlou?r|facial|spa|makeup|mehendi|barber|bridal)\b"
                  r"|సెలూన్|బ్యూటీ"),
    DomainAdapter("catering", "CATERING", "catering", ("broadcast", "send_request"),
                  r"\b(catering|caterers?|serving staff|waiters?|cooks?|event staff|helpers? for (an? )?event)\b"
                  r"|క్యాటరింగ్|వంటవాళ్లు"),
    DomainAdapter("parcel", "DELIVERY", "courier", ("quote", "send_request", "track"),
                  r"\b(parcel|courier|package|pick ?up .* drop)\b|పార్సెల్|కొరియర్"),
    DomainAdapter("job", "JOBS", "", ("apply", "contact"),
                  r"\b(job|jobs|vacancy|hiring|salary)\b|ఉద్యోగం|జాబ్"),
)

_SPECIALTIES = (
    (r"tooth|teeth|dental|dentist|gum|దంత", "dentist"),
    (r"skin|rash|acne|hair fall|dermat", "dermatologist"),
    (r"\beye|vision|spectacle|cataract", "eye hospital"),
    (r"child|baby|infant|pediatric|kid", "pediatrician"),
    (r"pregnan|period|gynec|delivery due", "gynecologist"),
    (r"bone|joint|fracture|knee|back pain|ortho", "orthopedic doctor"),
    (r"chest pain|heart|cardio|bp\b|blood pressure", "cardiologist"),
    (r"ear|nose|throat|ent\b|sinus", "ENT specialist"),
    (r"scan|x-?ray|blood test|lab test|diagnostic", "diagnostic centre"),
)
_EMERGENCY = re.compile(r"chest pain|can'?t breathe|unconscious|heavy bleeding|stroke|accident|emergency|seizure",
                        re.IGNORECASE)


def detect(text: str) -> DomainAdapter | None:
    lower = str(text or "").lower()
    for adapter in ADAPTERS:
        if re.search(adapter.pattern, lower, re.IGNORECASE):
            return adapter
    return None


def health_specialty(text: str) -> str:
    """The kind of professional to see -- a routing hint, never a diagnosis."""
    lower = str(text or "").lower()
    for pattern, specialty in _SPECIALTIES:
        if re.search(pattern, lower):
            return specialty
    return "general physician"


def is_emergency(text: str) -> bool:
    return bool(_EMERGENCY.search(str(text or "")))


def search_query(subject: str, context_text: str = "") -> str:
    """Places query for a need: healthcare goes to the right specialty,
    hotels/salons get their business noun; everything else stays the need."""
    adapter = detect(f"{subject} {context_text}")
    if adapter and adapter.key == "healthcare":
        return health_specialty(f"{subject} {context_text}")
    if adapter and adapter.search_noun and adapter.search_noun not in subject.lower():
        return f"{subject} {adapter.search_noun}"
    return subject
