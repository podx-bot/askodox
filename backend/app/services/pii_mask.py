"""Contact details never reach customers from extracted content: phone /
WhatsApp numbers and e-mail addresses are masked (the existing request ->
acceptance -> contact-release consent flow is the only way to share them).
One helper, used by admin traces, video studies and attachment facts."""
from __future__ import annotations

import re
from typing import Any

PHONE = re.compile(r"(?<!\d)(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)|(?<!\d)\+?\d[\d\s-]{8,13}\d(?!\d)")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
CONTACT_KEY = re.compile(r"phone|mobile|whatsapp|e_?mail|contact|call_?number|telephone", re.IGNORECASE)
MASK_PHONE, MASK_EMAIL = "[contact hidden]", "[email hidden]"


def mask(text: Any) -> str:
    value = str(text or "")
    return PHONE.sub(MASK_PHONE, EMAIL.sub(MASK_EMAIL, value))


def has_contact(text: Any) -> bool:
    value = str(text or "")
    return bool(PHONE.search(value) or EMAIL.search(value))


# Sensitive credentials (feedback / diagnostics): never stored readable.
CARD = re.compile(r"(?<!\d)(?:\d[ -]?){13,19}(?!\d)")
AADHAAR = re.compile(r"(?<!\d)\d{4}[ -]?\d{4}[ -]?\d{4}(?!\d)")
PAN = re.compile(r"\b[A-Z]{5}\d{4}[A-Z]\b", re.IGNORECASE)
OTP = re.compile(r"(?i)\b(otp|pin|cvv|passcode|password|code)\b\W{0,3}\w*\W{0,3}\d{3,8}")


def mask_sensitive(text: Any) -> str:
    """Contacts plus card / Aadhaar / PAN / OTP-like secrets."""
    value = str(text or "")
    value = OTP.sub(lambda m: m.group(1) + " [hidden]", value)
    value = CARD.sub("[number hidden]", value)
    value = AADHAAR.sub("[number hidden]", value)
    value = PAN.sub("[id hidden]", value)
    return mask(value)
