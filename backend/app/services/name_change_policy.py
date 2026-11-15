"""Business-name change rule (owner 2026-11-15): a shop name is not for changing every week.

* A name set for the first time can be corrected freely for 15 days (any number of times).
* After that window the NEXT change is allowed once, then the name is locked for 30 days.
* The change after that locks it for 60 days, and every later change locks it for 60 days.

One pure function pair, used by the profile ("My business" name) and by every POS business, so the rule is the same
everywhere and tested once. State = {set_at, edits, locked_until} (ISO strings / int); nothing here touches a database.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

FREE_DAYS = 15
WAIT_DAYS = (30, 60)  # after the 1st, then the 2nd and every later change


def _parse(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat()


def wait_days(edits_after: int) -> int:
    """Days a name stays locked after the change that made the edit count `edits_after`."""
    return WAIT_DAYS[0] if edits_after <= 1 else WAIT_DAYS[1]


def evaluate(state: Optional[Dict[str, Any]], now: datetime) -> Dict[str, Any]:
    """Can the name be changed right now? Returns can_change, free_window, free_until, next_allowed_at."""
    state = state or {}
    set_at = _parse(state.get("set_at"))
    edits = int(state.get("edits") or 0)
    locked_until = _parse(state.get("locked_until"))
    if set_at is None:  # no name yet: the first one is always free
        return {"can_change": True, "free_window": True, "free_until": None, "next_allowed_at": None,
                "edits": edits, "next_wait_days": wait_days(edits + 1)}
    free_until = set_at + timedelta(days=FREE_DAYS)
    if edits == 0 and now < free_until:
        return {"can_change": True, "free_window": True, "free_until": _iso(free_until), "next_allowed_at": None,
                "edits": edits, "next_wait_days": wait_days(1)}
    if locked_until is not None and now < locked_until:
        return {"can_change": False, "free_window": False, "free_until": None, "next_allowed_at": _iso(locked_until),
                "edits": edits, "next_wait_days": wait_days(edits + 1)}
    return {"can_change": True, "free_window": False, "free_until": None, "next_allowed_at": None,
            "edits": edits, "next_wait_days": wait_days(edits + 1)}


def after_change(state: Optional[Dict[str, Any]], now: datetime, had_name: bool) -> Dict[str, Any]:
    """The new state once a change has been accepted (call only when `evaluate(...).can_change`)."""
    state = dict(state or {})
    if not had_name or not state.get("set_at"):
        return {"set_at": _iso(now), "edits": 0, "locked_until": None}
    info = evaluate(state, now)
    if info["free_window"]:
        return state  # a correction inside the free 15 days costs nothing
    edits = int(state.get("edits") or 0) + 1
    return {"set_at": state["set_at"], "edits": edits,
            "locked_until": _iso(now + timedelta(days=wait_days(edits)))}


def lock_message(info: Dict[str, Any]) -> str:
    """One mixed Telugu-English sentence for the 409 error (the app shows it as it is)."""
    when = _parse(info.get("next_allowed_at"))
    day = when.astimezone().strftime("%d %b %Y") if when else ""
    return (f"Business పేరు ఇప్పుడు మార్చలేరు. {day} తర్వాత మార్చవచ్చు "
            f"(Business name can be changed again after {day}).")
