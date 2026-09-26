"""Authoritative runtime date/time context for ASKODOX AI prompts.

Models only know their training-time "now". Anything relative ("today",
"this year", "ఈ సంవత్సరం", "రేపు", "latest", "current") must be resolved
against the server clock in the user's timezone -- never a hardcoded year.
"""
from __future__ import annotations

import os
import re
from datetime import datetime, timedelta, timezone
from typing import Callable

DEFAULT_TIMEZONE = "Asia/Kolkata"  # ASKODOX users are in India; override via ASKODOX_TIMEZONE.

Clock = Callable[[], datetime]


def _tz(name: str | None = None):
    tz_name = (name or os.getenv("ASKODOX_TIMEZONE", "") or DEFAULT_TIMEZONE).strip()
    try:
        from zoneinfo import ZoneInfo

        return tz_name, ZoneInfo(tz_name)
    except Exception:  # no tzdata on this host: IST has no DST, so a fixed offset is exact
        return DEFAULT_TIMEZONE, timezone(timedelta(hours=5, minutes=30), "IST")


def runtime_now(clock: Clock | None = None, tz_name: str | None = None) -> tuple[datetime, str]:
    """Current local time and the timezone name it is expressed in."""
    name, tz = _tz(tz_name)
    now = (clock or (lambda: datetime.now(timezone.utc)))()
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(tz), name


# (pattern, key) -- English and Telugu (script + common romanised forms).
_RELATIVE = (
    (r"\btoday\b|\btoday's\b|ఈరోజు|ఈ రోజు|ఇవాళ|ఇవ్వాళ|\baaj\b|\bivala\b|\beeroju\b", "today"),
    (r"\btomorrow\b|రేపు|\brepu\b", "tomorrow"),
    (r"\byesterday\b|నిన్న|\bninna\b", "yesterday"),
    (r"\bthis year\b|\bcurrent year\b|ఈ సంవత్సరం|ఈ ఏడాది|ఈ యేడాది|ఈసంవత్సరం|\bee samvatsaram\b", "this_year"),
    (r"\bnext year\b|వచ్చే సంవత్సరం|వచ్చే ఏడాది", "next_year"),
    (r"\blast year\b|గత సంవత్సరం|పోయిన సంవత్సరం|పోయిన ఏడాది", "last_year"),
    (r"\bthis month\b|ఈ నెల", "this_month"),
    (r"\bnow\b|\bright now\b|\bcurrently\b|\bcurrent\b|ఇప్పుడు|ప్రస్తుతం|ప్రస్తుత|\bippudu\b", "now"),
)


def resolve_relative_time(text: str, clock: Clock | None = None, tz_name: str | None = None) -> dict[str, str]:
    """Relative expressions in ``text`` resolved against the runtime clock."""
    now, _ = runtime_now(clock, tz_name)
    lowered = str(text or "").casefold()
    values = {
        "today": now.date().isoformat(),
        "tomorrow": (now.date() + timedelta(days=1)).isoformat(),
        "yesterday": (now.date() - timedelta(days=1)).isoformat(),
        "this_year": str(now.year),
        "next_year": str(now.year + 1),
        "last_year": str(now.year - 1),
        "this_month": now.strftime("%Y-%m"),
        "now": now.strftime("%Y-%m-%d %H:%M"),
    }
    return {key: values[key] for pattern, key in _RELATIVE if re.search(pattern, lowered)}


def runtime_context_block(text: str = "", clock: Clock | None = None, tz_name: str | None = None) -> str:
    """Prompt block that makes the runtime clock authoritative."""
    now, name = runtime_now(clock, tz_name)
    resolved = resolve_relative_time(text, clock, tz_name)
    lines = [
        "AUTHORITATIVE RUNTIME CONTEXT (from the server clock; overrides your training-data sense of the date): "
        f"today={now.date().isoformat()} ({now.strftime('%A')}); current_year={now.year}; "
        f"local_time={now.strftime('%H:%M')}; timezone={name} (UTC{now.strftime('%z')[:3]}:{now.strftime('%z')[3:]}).",
        "Resolve every relative time expression (today/ఈరోజు/ఇవాళ, tomorrow/రేపు, now/ఇప్పుడు, "
        "this year/ఈ సంవత్సరం, current, latest) against this runtime context, never against training memory.",
    ]
    if resolved:
        lines.append("Resolved in this message: " + "; ".join(f"{k}={v}" for k, v in resolved.items()) + ".")
    return "\n".join(lines)


_LIVE_MARKERS = (
    r"\blatest\b", r"\bcurrent\b", r"\bcurrently\b", r"\bright now\b", r"\btoday'?s?\b", r"\bthis year\b",
    r"\bbreaking\b", r"\bnews\b", r"\bpolicy\b", r"\brules?\b", r"\bprice today\b",
    r"\brate today\b", r"\bexchange rate\b", r"\bgold (?:price|rate)\b", r"\bpetrol (?:price|rate)\b",
    r"\bholiday\b", r"\bfestival\b", r"\bcalendar\b",
    r"\bmuhurtham?\b", r"\bdiwali\b", r"\bdeepavali\b", r"\bsankranti\b", r"\bugadi\b", r"\bdasara\b",
    r"\bdussehra\b", r"\bholi\b", r"\beid\b", r"\bchristmas\b", r"\belections?\b",
    "లేటెస్ట్", "తాజా", "ప్రస్తుత", "ఈరోజు", "ఈ రోజు", "ఇవాళ", "ఈ సంవత్సరం", "ఈ ఏడాది", "వార్తలు",
    "పండుగ", "సెలవు", "ముహూర్తం", "దీపావళి", "సంక్రాంతి", "ఉగాది", "దసరా", "హోలీ",
    "ధర ఎంత", "రేటు ఎంత", "పాలసీ", "ఎన్నికలు", "ఫలితాలు",
)

# Local-commerce intent is handled by the existing discovery/matching pipeline.
_COMMERCE_MARKERS = (
    r"\bbuy\b", r"\bsell\b", r"\border\b", r"\bnearby\b", r"\bnear me\b", r"\bbook\b", r"\bdeliver",
    r"\bi want\b", r"\bi need\b", r"\bkavali\b", r"\bkaavali\b", r"\bkonali\b", r"\bshop\b", r"\bstore\b",
    "కొనాలి", "కొనుగోలు", "అమ్మాలి", "కావాలి", "దగ్గర్లో", "దగ్గరలో", "ఆర్డర్", "బుక్", "షాప్",
)


def needs_live_verification(text: str) -> bool:
    """True for time-sensitive or changeable facts that should be verified
    with live evidence; False for ordinary local-commerce requests."""
    lowered = str(text or "").casefold()
    if not lowered.strip() or any(re.search(m, lowered) for m in _COMMERCE_MARKERS):
        return False
    return any(re.search(m, lowered) for m in _LIVE_MARKERS)


def grounded_search_query(text: str, clock: Clock | None = None, tz_name: str | None = None) -> str:
    """Search query pinned to the runtime year when the user means 'now'."""
    clean = " ".join(str(text or "").split())
    resolved = resolve_relative_time(clean, clock, tz_name)
    year = resolved.get("this_year") or (runtime_now(clock, tz_name)[0].year if needs_live_verification(clean) else None)
    if year and str(year) not in clean:
        return f"{clean} {year}"
    return clean
