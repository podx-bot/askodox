"""ONE rule for "is this signed-in account a staff-chosen tester?" (billing
testers and Travel Radio testers).

The app account id is "app-phone-<digits exactly as typed at sign-in>", so the
same number can appear as 9876543210 or 919876543210. Testers are matched by
the last 10 digits. The public demo account (onboarding_auth._DEMO_MOBILE,
fixed OTP, anyone can sign in) is never a tester: access must belong to one
person the staff explicitly chose.
"""
from __future__ import annotations

DEMO_PHONE_KEY = "9999999999"  # last 10 digits of onboarding_auth._DEMO_MOBILE


def phone_key(user_id: str) -> str:
    """Last 10 digits of a phone-based id ("" when there are fewer)."""
    digits = "".join(ch for ch in str(user_id or "") if ch.isdigit())
    return digits[-10:] if len(digits) >= 10 else ""


def is_demo_account(user_id: str) -> bool:
    return phone_key(user_id) == DEMO_PHONE_KEY


def tester_user_id(raw: str) -> str:
    """Staff may type a phone number: 10 digits / +91... -> "app-phone-91XXXXXXXXXX".
    Anything else is kept as typed."""
    text = str(raw or "").strip()
    if text.lower().startswith("app-"):
        return text
    digits = "".join(ch for ch in text if ch.isdigit())
    if len(digits) == 10:
        return "app-phone-91" + digits
    if len(digits) == 12 and digits.startswith("91"):
        return "app-phone-" + digits
    return text


def matches(stored_ids, user_id: str) -> bool:
    """True when user_id is one of stored_ids, exactly or by phone number.
    The demo account never matches."""
    if is_demo_account(user_id):
        return False
    key = phone_key(user_id)
    for sid in stored_ids:
        if sid == user_id or (key and phone_key(sid) == key):
            return True
    return False


def same_person(stored_ids, user_id: str) -> list:
    """Every stored id for the same account (to revoke all spellings)."""
    key = phone_key(user_id)
    return [sid for sid in stored_ids if sid == user_id or (key and phone_key(sid) == key)]
