"""Paid AUTOMATIC sending for a shop (owner 2026-11-27): bills and baaki reminders that ASKODOX sends by itself.

Two ways only, for a bill and for a baaki reminder alike:

* MANUAL -- the owner sends it himself (his own WhatsApp, one tap, or "send" in the app). Free for ever, no credits.
* AUTOMATIC -- the owner switched "send by itself" on for his shop; ASKODOX sends it and one ``shop_message`` use is
  taken from the SHOP OWNER's AI Credits per message. One price per message (staff set it; the shop never sees a split).

When the owner has too few credits the message is NOT sent and nothing is lost: the bill / reminder stays in the
owner's own manual list. A message the provider refuses is given back (``give_back``). Everything here is idempotent per
``ref`` (``AiCredits.reserve`` never charges one ref twice).

Charging is OFF in production until staff turn it on with rates, so until then an automatic message is free.
"""
from __future__ import annotations

from typing import Any

from app.services.ai_credits import CreditsError

FEATURE = "shop_message"


def price(credits: Any) -> int:
    """Paise for ONE automatic message right now (0 while charging is off or no credits are wired)."""
    if credits is None:
        return 0
    try:
        return int(credits.price(FEATURE))
    except Exception:
        return 0


def charge(credits: Any, owner: str, ref: str) -> bool:
    """True when the message may go out (charged, or free). False when the owner has too few credits.

    Any other fault also answers False: a billing problem must never send an unpaid message or stop the job."""
    if credits is None or not owner:
        return True
    try:
        credits.reserve(owner, FEATURE, ref)
        return True
    except CreditsError as error:
        if error.code != "insufficient":
            print(f"ASKODOX SHOP MESSAGE credits error={error.code} ref={ref[:60]}", flush=True)
        return False
    except Exception as problem:
        print(f"ASKODOX SHOP MESSAGE credits fault={type(problem).__name__} ref={ref[:60]}", flush=True)
        return False


def give_back(credits: Any, owner: str, ref: str) -> None:
    """The provider did not take the message: the charge comes back (once)."""
    if credits is None or not owner:
        return
    try:
        credits.release(owner, ref)
    except Exception as problem:
        print(f"ASKODOX SHOP MESSAGE release fault={type(problem).__name__} ref={ref[:60]}", flush=True)
