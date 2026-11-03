"""Chat actions: open any ASKODOX feature by talking (owner vision 2026-10-30:
"any option buried in Profile should open from the main chat").

ONE catalog of app destinations. The brain picks at most one by MEANING (no
keyword rules -- the model reads the catalog), and only when the user asks to
DO or OPEN one of these things. The app shows a button under the reply; the
user taps it to open the real screen (never an automatic jump), so nothing
happens without the user's tap and every save still goes through that
screen's own API and checks.

Old APKs never see this: the catalog goes into the prompt only when the app
sends the ``app_actions`` capability.

A destination is added HERE (one row) -- never as per-screen chat code.
"""
from __future__ import annotations

import re
from typing import Any, Optional

CAPABILITY = "app_actions"

# key, app route, English label, Telugu-English label, what it is for (for the brain)
CATALOG: tuple[tuple[str, str, str, str, str], ...] = (
    ("pos_bill", "/pos", "Billing / POS", "Bill వేయండి (POS)",
     "make a bill / invoice for a shop customer, open the shop counter, stock, GST bills, KOT for a restaurant"),
    ("pos_payment_alerts", "/pos", "Payment voice alerts", "Payment voice alerts",
     "UPI payment sound alerts for the shop (soundbox on the phone)"),
    ("crm", "/crm", "Customers & leads (CRM)", "Customers & Leads (CRM)",
     "business customers, leads, follow-ups, quotations, complaints"),
    ("my_listings", "/listings/mine", "My listings", "నా Listings",
     "the user's own items / products / property / vehicles they are selling or renting out"),
    ("orders_mine", "/orders/mine", "My orders", "నా Orders",
     "requests / orders the user sent as a buyer"),
    ("orders_incoming", "/orders/incoming", "Incoming orders", "వచ్చిన Orders",
     "orders / requests customers sent to the user as a seller or provider"),
    ("rides_parcels", "/mobility", "Rides & parcels", "Rides & Parcels",
     "book a ride, send a parcel or courier, goods transport (mini truck, tempo, lorry, packers and movers), "
     "or register / work as a driver or delivery partner"),
    ("upload_video", "/videos/native", "ASKODOX videos", "ASKODOX Videos",
     "post / upload a video to ASKODOX, watch ASKODOX videos, manage the user's own videos"),
    ("business_creations", "/business/creations", "My Creations", "నా Creations",
     "write a social post, offer text, product description, poster text or reel script for the business"),
    ("business_promotions", "/business/promotions", "Promotions", "Promotions",
     "run an offer / promotion / discount campaign for the business"),
    ("business_hub", "/business", "My Business", "నా Business",
     "the user's business dashboard, analytics, business settings"),
    ("ai_credits", "/me/ai-credits", "AI Credits", "AI Credits",
     "AI credit balance, recharge, usage history"),
    ("payment_methods", "/me/payment-methods", "My payment methods", "నా Payment methods",
     "add or change the user's own UPI ID / QR / bank details to receive money"),
    ("finance", "/me/finance", "Tax & money tools", "Tax & Money tools",
     "income tax / GST calculators, personal money tools"),
    ("roles", "/profile/roles", "My roles", "నా Roles",
     "become or change role: seller, service provider, job seeker, employer, buyer"),
    ("verification", "/verification", "Verification (KYC)", "Verification (KYC)",
     "verify identity / business documents, KYC, GST / PAN verification"),
    ("opportunities", "/opportunities", "Opportunities", "Opportunities",
     "demand near the user that their business could serve, leads for sellers"),
    ("profile_memory", "/profile/memory", "What ASKODOX remembers", "ASKODOX గుర్తుంచుకున్నవి",
     "see or delete what the assistant remembers about the user, personalization"),
    ("notification_settings", "/settings/notifications", "Notification settings", "Notification settings",
     "turn notifications / alerts on or off"),
    ("privacy", "/privacy", "Privacy & data", "Privacy & Data",
     "export or delete the user's data or account"),
    ("watchlist", "/watchlist", "Watchlist", "Watchlist",
     "items the user is watching / waiting for price drop or availability"),
    ("updates", "/updates", "Updates", "Updates",
     "status of the user's requests, notifications inbox"),
    ("profile", "/profile", "Profile", "Profile",
     "the user's profile, addresses, phone numbers, staff workspace, settings"),
)

_BY_KEY = {row[0]: row for row in CATALOG}
_KEY = re.compile(r"^[a-z_]{2,40}$")


def prompt_block() -> str:
    lines = "\n".join(f"- {key}: {about}" for key, _route, _en, _te, about in CATALOG)
    return (
        "APP ACTIONS: if (and only if) the user asks to DO, OPEN, MANAGE or SET UP one of these ASKODOX features "
        "(not just to find or buy something -- searches stay searches), also return app_action = "
        '{"key": "<one key below>"} and keep the reply to one short line saying what they can do there. '
        "Pick by meaning in any language; if none fits clearly, omit app_action. Never claim the screen was "
        "opened or that anything was saved -- the user taps a button to open it.\n" + lines + "\n"
    )


def resolve(raw: Any, telugu: bool = False) -> Optional[dict[str, str]]:
    """The model's ``app_action`` -> a known destination, or None."""
    key = raw.get("key") if isinstance(raw, dict) else raw
    key = str(key or "").strip().lower()
    if not _KEY.fullmatch(key) or key not in _BY_KEY:
        return None
    _key, route, en, te, _about = _BY_KEY[key]
    return {"key": key, "route": route, "label": te if telugu else en}


def routes() -> list[str]:
    return sorted({row[1] for row in CATALOG})
