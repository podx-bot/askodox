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
    # Shop tools, straight to the page (the app finds the person's shop). Owner 2026-11-19.
    ("shop_new_bill", "/my-shop/sale", "Counter bill", "కౌంటర్ బిల్లు",
     "counter bill / కౌంటర్ బిల్లు / new bill / కొత్త బిల్లు / bill వేయి: start a new bill for a shop customer right now"),
    ("shop_agents", "/my-shop/agents", "AI agents", "AI Agents",
     "ai agents / my ai agents: the shop's own AI helpers (sales, stock, accounts agents) -- open them, never explain what AI agents are"),
    ("shop_items", "/my-shop/items", "Stock & barcodes", "స్టాక్ & బార్‌కోడ్",
     "my items / stock / menu / products / prices of my shop: add, edit, stock count"),
    ("shop_suppliers", "/my-shop/suppliers", "Purchases", "కొనుగోళ్లు",
     "suppliers, purchase bills, stock bought, supplier ledger"),
    ("shop_expiry", "/my-shop/expiry", "Expiry & stock value", "ఎక్స్‌పైరీ & స్టాక్ విలువ",
     "items expiring soon, stock value"),
    ("shop_customers", "/my-shop/customers", "Customer list", "కస్టమర్ల లిస్ట్",
     "my shop's customers, baaki / credit / dues, who owes me"),
    ("shop_dues", "/my-shop/dues", "Baaki reminders", "బాకీ గుర్తులు",
     "remind customers who owe me (baaki / credit due date), send baaki reminder on WhatsApp, overdue credit"),
    ("shop_bills", "/my-shop/bills", "Bills", "బిల్లులు",
     "bills / invoices my shop issued, today's bills, reprint or share a bill"),
    ("shop_day", "/my-shop/day", "Close the day", "రోజు ముగింపు", "today's sales total, cash count, close the day"),
    ("shop_gst", "/my-shop/gst", "GST report", "GST రిపోర్ట్", "my shop's GST summary / report"),
    ("shop_staff", "/my-shop/staff", "Staff & roles", "సిబ్బంది & పాత్రలు", "add or change my shop staff and their roles"),
    ("shop_printer", "/my-shop/printer", "Printer", "ప్రింటర్", "connect or test the bill printer"),
    ("shop_orders", "/my-shop/orders", "Incoming orders", "వచ్చిన ఆర్డర్లు",
     "orders customers placed at my shop (table, parcel, delivery): accept, kitchen, ready"),
    ("shop_tables", "/my-shop/tables", "Tables", "టేబుల్స్", "restaurant tables, KOT, table bills"),
    ("shop_kitchen", "/my-shop/kitchen", "Kitchen (KOT)", "వంటగది KOT", "kitchen display of running orders"),
    ("shop_collect", "/my-shop/collect", "Collect by UPI", "UPI తో కట్టించుకోండి", "show my QR / ask a customer to pay by UPI"),
    ("shop_advance", "/my-shop/advance", "Shop advance", "షాప్ అడ్వాన్స్", "customer advances kept with my shop"),
    ("shop_selfshop", "/my-shop/selfshop", "Self-shopping", "సెల్ఫ్ షాపింగ్", "customers scan and shop by themselves in my shop"),
    ("shop_payment_alerts", "/my-shop/payment-alerts", "Payment alerts", "పేమెంట్ అలర్ట్స్",
     "payment voice for the shop: who hears it, voice, quiet time"),
    ("pos_bill", "/pos", "Billing / POS", "Bill వేయండి (POS)",
     "the shop counter home (list of my shops, set up a shop): open the shop counter, stock, GST bills, KOT for a restaurant"),
    ("pos_payment_alerts", "/me/payments/phone", "Payment voice alerts", "Payment voice alerts",
     "UPI payment sound alerts for the shop (soundbox on the phone): turn payment-app / bank SMS alerts on, set up notification access"),
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
    ("my_money", "/money", "My money", "నా Money",
     "money in and out: payments received / paid, bank debit and credit alerts seen on this phone, bills paid "
     "(current / electricity bill, recharge, EMI, premium), bills that came and upcoming dues"),
    ("my_bills", "/me/bills", "My bills", "నా Bills",
     "my bill / నా బిల్లు: bills sent to the user by shops, pay or settle a bill later"),
    ("my_payments", "/me/payments", "Payments", "Payments",
     "payments hub: phone payments, own payment methods, bills"),
    ("order_with_code", "/order-desk/enter", "Order with shop code / QR", "Shop code / QR తో Order",
     "order at a table or counter by entering a shop's order code or scanning its QR"),
    ("following_shops", "/me/following", "Shops I follow", "నేను Follow చేసే Shops",
     "shops the user follows, their posts and offers"),
    ("buyer_agent", "/me/agent", "My shopping assistant", "నా Shopping assistant",
     "ask about the user's own orders, bills and spending in one place"),
    ("report_problem", "/beta-feedback", "Report a problem / feedback", "Problem report / Feedback",
     "report a bug, send feedback or an idea to the ASKODOX team"),
    ("talk_rooms", "/talk", "Talk", "Talk",
     "anonymous topic rooms to chat with other people (18+)"),
    ("work_mode", "/work", "Work Mode", "Work Mode",
     "the walking game: steps turn into a real job done in half the time"),
    ("profile", "/profile", "Profile", "Profile",
     "the user's profile, addresses, phone numbers, staff workspace, settings"),
)

_BY_KEY = {row[0]: row for row in CATALOG}
_KEY = re.compile(r"^[a-z_]{2,40}$")

# Release phase (owner decision 2026-11-04). A Phase 1 app sends the capability
# PHASE1_CAPABILITY; it hides the Phase 2 screens (business tools / POS, rides,
# roles, KYC, money tools, own video uploads), so the brain is offered -- and may
# return -- only these destinations. Old APKs and Phase 2 builds get the whole catalog.
PHASE1_CAPABILITY = "phase1_only"
SHOP_TOOL_KEYS = frozenset(row[0] for row in CATALOG if row[1].startswith("/my-shop/"))
PHASE1_KEYS = SHOP_TOOL_KEYS | frozenset({
    "pos_bill", "pos_payment_alerts", "crm", "my_bills", "my_money", "my_payments",
    "ai_credits", "payment_methods", "profile_memory", "notification_settings",
    "privacy", "watchlist", "updates", "profile",
})


# ASKODOX Shopping switch ON in a Phase 1 build (owner 2026-11-19): a registered business person can ALSO open the
# shop tools (counter / new bill, payment alerts, customers, bills, money, payments) by talking. Only routes that
# exist in a Phase 1 app (POS routes ship there since 2026-11-18) -- never a button to a screen the build lacks.
SHOPPING_CAPABILITY = "shopping_tools"
SHOPPING_KEYS = PHASE1_KEYS | frozenset({
    "pos_bill", "pos_payment_alerts", "crm", "my_bills", "my_money", "my_payments",
})


def keys_for(capabilities) -> Optional[frozenset]:
    """None = the whole catalog (Phase 2 / old builds); else the keys this build may open."""
    caps = capabilities or ()
    if PHASE1_CAPABILITY not in caps:
        return None
    return SHOPPING_KEYS if SHOPPING_CAPABILITY in caps else PHASE1_KEYS


def _rows(phase1_only=False):
    allowed = PHASE1_KEYS if phase1_only is True else (phase1_only or None)
    return [row for row in CATALOG if not allowed or row[0] in allowed]


AUTO_OPEN_CAPABILITY = "auto_open"


def prompt_block(phase1_only=False, auto_open: bool = False) -> str:
    lines = "\n".join(f"- {key}: {about}" for key, _route, _en, _te, about in _rows(phase1_only))
    if auto_open:
        # Owner 2026-11-20: the app opens the named screen by itself -- the reply never asks for a tap.
        return (
            "APP ACTIONS: if (and only if) the user asks to DO, OPEN, MANAGE or SET UP one of these ASKODOX features "
            "(not just to find or buy something -- searches stay searches), also return app_action = "
            '{"key": "<one key below>"}. The app OPENS that screen by itself at once: reply with ONE short line '
            'naming it (e.g. "Opening a new bill." / "కొత్త బిల్లు తెరుస్తున్నాను."). Never tell the user to tap a '
            'button. A bare feature name or "my <feature>" (e.g. "new bill", "cash bill", "my ai agents", "stock", '
            '"staff") IS a request to open it; do not explain the general concept and do not ask which kind. '
            "Pick by meaning in any language; if none fits clearly, omit app_action. Never claim anything was saved.\n"
            + lines + "\n"
        )
    return (
        "APP ACTIONS: if (and only if) the user asks to DO, OPEN, MANAGE or SET UP one of these ASKODOX features "
        "(not just to find or buy something -- searches stay searches), also return app_action = "
        '{"key": "<one key below>"} and keep the reply to one short line saying what they can do there. '
        'A bare feature name or "my <feature>" (e.g. "new bill", "my ai agents", "stock", "staff") IS a request to '
        "open it: return the app_action; do not explain the general concept and do not ask which kind. "
        "Pick by meaning in any language; if none fits clearly, omit app_action. Never claim the screen was "
        "opened or that anything was saved -- the user taps a button to open it.\n" + lines + "\n"
    )


def resolve(raw: Any, telugu: bool = False, phase1_only=False) -> Optional[dict[str, str]]:
    """The model's ``app_action`` -> a known destination, or None."""
    key = raw.get("key") if isinstance(raw, dict) else raw
    key = str(key or "").strip().lower()
    if not _KEY.fullmatch(key) or key not in _BY_KEY:
        return None
    allowed = PHASE1_KEYS if phase1_only is True else (phase1_only or None)
    if allowed and key not in allowed:
        return None
    _key, route, en, te, _about = _BY_KEY[key]
    return {"key": key, "route": route, "label": te if telugu else en}


def routes() -> list[str]:
    return sorted({row[1] for row in CATALOG})
