"""The shop tools that stay FREE FOR EVER (owner 2026-11-23, "1 + 4 do").

The everyday tools a shop runs on -- hearing a payment, making a bill, the dues (baaki) book, the day / month sales
report -- are never charged and never put behind a plan, however ASKODOX earns later (AI Credits, paid extras).
ASKODOX earns only where it brings the shop something extra; the counter itself is never rented back to the shop.

ONE list (``FREE_FOREVER``). What keeps the promise:

* AI Credits can never carry a rate for these keys: ``AiCredits.update_settings`` refuses one (``free_forever``) and
  ``AiCredits.reserve`` always answers free for them;
* ``tests/test_shop_free_core.py`` reads the handler of every route in ``routes`` and fails when it reserves credits,
  answers 402 or checks a plan -- so a later round cannot quietly put a price on them;
* the Command Center AI Credits page shows the list as locked.

Adding a tool = one more row here (the owner's decision). Taking one out needs the owner's own word: the registry
entry ``shop_core_free_forever`` locks the keys.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

# ``label`` / ``what`` = ONE mixed Telugu-English text each (Command Center rule, owner 2026-10-27).
# ``routes`` = the API paths (as FastAPI registers them) that ARE the tool.
FREE_FOREVER: Tuple[Dict[str, Any], ...] = (
    {
        "key": "payment_voice",
        "label": "Payment వాయిస్",
        "what": "డబ్బు వచ్చినప్పుడు phone / staff phones లో వినిపించే voice, దాని history, settings.",
        "routes": (
            r"^/api/pos/businesses/\{business_id\}/payment-alerts(/|$)",
            r"^/api/pos/me/payment-alerts(/|$)",
            # the phone fetches the spoken parts of a payment here: if reply voice is ever charged, payment voice
            # must be let through free FIRST (it is the same route).
            r"^/api/in-app/voice/speak$",
        ),
    },
    {
        "key": "quick_bill",
        "label": "Quick బిల్",
        "what": "బిల్ చేయడం, save, print / WhatsApp పంపడం, పాత బిల్లులు చూడడం.",
        "routes": (
            r"^/api/pos/businesses/\{business_id\}/(invoices|drafts|bills)(/|$)",
            r"^/api/pos/me/bills(/|$)",
        ),
    },
    {
        "key": "dues",
        "label": "బాకీ లెక్క",
        "what": "ఎవరు ఎంత బాకీ, ఎప్పుడు ఇస్తామన్నారు, వసూలు నమోదు, reminders.",
        "routes": (
            r"^/api/pos/businesses/\{business_id\}/dues(/|$)",
            r"^/api/pos/businesses/\{business_id\}/customers/\{customer_id\}/(payments|statement)$",
        ),
    },
    {
        "key": "sales_reports",
        "label": "Sales రిపోర్ట్‌లు",
        "what": "రోజు / నెల అమ్మకాల లెక్క, day close, GST register.",
        "routes": (
            r"^/api/pos/businesses/\{business_id\}/reports/(day|range|gst|register\.csv|settings)$",
            r"^/api/pos/businesses/\{business_id\}/(sales|day-close|day/\{local_date\})$",
        ),
    },
)

# Words that mean "this costs the shop something": none may appear in the handler of a free-forever route.
CHARGE_MARKERS: Tuple[str, ...] = (
    "_reserve_credits", "ai_credits", ".reserve(", "AI_CREDITS_LOW", "status_code=402", "entitlement",
    "PAYMENT_REQUIRED", "plan_required",
)


def keys() -> Tuple[str, ...]:
    return tuple(row["key"] for row in FREE_FOREVER)


def is_free(feature: str) -> bool:
    return str(feature or "") in keys()


def public() -> List[Dict[str, str]]:
    """The list as the Command Center (and later the app / website) shows it: no route patterns."""
    return [{"key": row["key"], "label": row["label"], "what": row["what"]} for row in FREE_FOREVER]


def key_for_path(path: str) -> Optional[str]:
    """The free-forever tool a registered route path belongs to (None = not one of them)."""
    for row in FREE_FOREVER:
        if any(re.search(pattern, path) for pattern in row["routes"]):
            return row["key"]
    return None


def charge_marks(source: str) -> List[str]:
    """Which charge words a piece of handler source carries (empty = it charges nothing)."""
    return [marker for marker in CHARGE_MARKERS if marker in source]
