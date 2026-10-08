"""One-time advice memory for the conversation brain.

Policy: Understand -> Reason -> Advise ONCE -> Respect the decision ->
Continue helping. Any category, any language: nothing here knows about
phones, loans or medicine -- the brain (Gemini / OpenAI fallback, the ONE
decision engine) names each concern it raises; this module only keeps the
ledger honest.

The app keeps the ledger for its conversation and sends it back each turn
(``advice_given``); the server stays stateless. A concern already in the
ledger may be raised again only when

  * materially new information changed the risk   (``new_information``),
  * the user explicitly asked for advice again      (``user_asked``), or
  * it is a serious safety / legal / financial / medical risk (``critical``)
    -- then proportionately, never suppressed.

A repeat without one of those reasons is a policy violation: it is flagged
on the returned advice and counted for the Command Center (never silent).
No user text is stored beyond the short concern summary the model wrote.
"""

from __future__ import annotations

import json
import re
from typing import Any

SEVERITIES = ("info", "caution", "critical")
REPEAT_REASONS = ("new_information", "user_asked", "critical")
MAX_LEDGER = 12
_KEY = re.compile(r"[^a-z0-9]+")
_WORD = re.compile(r"[^\W\d_]{3,}", re.UNICODE)
_STOP = {"the", "and", "for", "with", "this", "that", "you", "your", "are", "not", "but", "may", "can", "will",
         "than", "more", "less", "very", "have", "has", "from", "into", "about", "could", "would", "should"}


def normalize_key(value: Any) -> str:
    """A stable snake_case concern id ("Battery Health!" -> battery_health)."""
    return _KEY.sub("_", str(value or "").strip().lower()).strip("_")[:60]


def _words(text: str) -> set[str]:
    return {w.lower() for w in _WORD.findall(str(text or "")) if w.lower() not in _STOP}


def sanitize_entry(raw: Any) -> dict[str, Any] | None:
    """One ledger / advice entry, or None when it names no concern."""
    if not isinstance(raw, dict):
        return None
    key = normalize_key(raw.get("key") or raw.get("concern"))
    summary = " ".join(str(raw.get("summary") or "").split())[:160]
    if not key:
        return None
    severity = str(raw.get("severity") or "info").strip().lower()
    reason = str(raw.get("repeat_reason") or "").strip().lower()
    entry = {"key": key, "summary": summary, "severity": severity if severity in SEVERITIES else "info"}
    if reason in REPEAT_REASONS:
        entry["repeat_reason"] = reason
    try:
        entry["times"] = max(1, min(int(raw.get("times") or 1), 99))
    except (TypeError, ValueError):
        entry["times"] = 1
    return entry


def sanitize_ledger(raw: Any) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw if isinstance(raw, list) else []:
        entry = sanitize_entry(item)
        if entry and entry["key"] not in seen:
            seen.add(entry["key"])
            entry.pop("repeat_reason", None)
            entries.append(entry)
    return entries[-MAX_LEDGER:]


def find_previous(advice: dict[str, Any], ledger: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The ledger entry this advice repeats: the same key, or a summary that
    shares most of its content words (the model may rename the key)."""
    for entry in ledger:
        if entry["key"] == advice["key"]:
            return entry
    words = _words(advice.get("summary", ""))
    if len(words) < 3:
        return None
    for entry in ledger:
        other = _words(entry.get("summary", ""))
        if other and len(words & other) / max(1, min(len(words), len(other))) >= 0.7:
            return entry
    return None


def review(raw_advice: Any, ledger: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """Check the advice the brain gave this turn against the ledger.

    Returns (advice for the app or None, the updated ledger). The advice
    carries ``repeated`` (it was given before) and ``allowed`` (False = a
    repeat without new information, an explicit ask or a critical risk)."""
    advice = sanitize_entry(raw_advice)
    ledger = [dict(e) for e in ledger]
    if advice is None:
        return None, ledger
    previous = find_previous(advice, ledger)
    if previous is None:
        advice.update(repeated=False, allowed=True, times=1)
        ledger.append({k: advice[k] for k in ("key", "summary", "severity", "times")})
        return advice, ledger[-MAX_LEDGER:]
    reason = advice.get("repeat_reason") or ("critical" if advice["severity"] == "critical" else "")
    advice.update(key=previous["key"], repeated=True, allowed=bool(reason), times=previous.get("times", 1) + 1)
    if reason:
        advice["repeat_reason"] = reason
    previous.update(times=advice["times"], severity=advice["severity"],
                    summary=advice["summary"] if reason == "new_information" and advice["summary"]
                    else previous.get("summary", ""))
    return advice, ledger


def prompt_block(ledger: list[dict[str, Any]]) -> str:
    """Instructions + the ledger for the brain prompt (main and advisory)."""
    given = [{k: e[k] for k in ("key", "summary", "severity")} for e in ledger]
    return (
        "ONE-TIME ADVICE RULE (any topic): when you see a meaningful disadvantage, risk, unnecessary cost or a "
        "better alternative, explain it ONCE, clearly and respectfully, with a short recommendation and why. "
        "Then respect the user's decision and keep helping with the option they chose -- never lecture, never "
        "block, never repeat the same warning. Raise a concern listed under ADVICE ALREADY GIVEN again only if "
        "(a) the user gave materially new information that changes the risk (repeat_reason new_information), "
        "(b) the user explicitly asks for your opinion again (user_asked), or (c) it is a serious safety, legal, "
        "financial or medical risk (critical) -- then one proportionate line, not the full warning. "
        "Report the main concern you raised IN THIS REPLY as advice = {key: short stable snake_case id of the "
        "concern, summary: one line under 120 characters, severity: info|caution|critical, repeat_reason: '' or "
        "one of new_information|user_asked|critical}; advice = null when this reply raises no concern.\n"
        f"ADVICE ALREADY GIVEN: {json.dumps(given, ensure_ascii=False)[:1500] if given else 'none'}\n"
    )


_META = re.compile(r"\n?\s*ADVICE_META:\s*(\{.*\}|null)\s*$", re.DOTALL)


def split_meta(text: str) -> tuple[str, Any]:
    """The advisory answer ends with one machine line ``ADVICE_META: {...}``;
    return (the answer without it, the parsed advice or None)."""
    match = _META.search(str(text or ""))
    if not match:
        return str(text or ""), None
    try:
        meta = json.loads(match.group(1))
    except ValueError:
        meta = None
    return str(text)[:match.start()].rstrip(), meta
