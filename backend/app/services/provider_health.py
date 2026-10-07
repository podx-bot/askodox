"""Truthful provider health from REAL calls, not from key presence.

A key being set only means CONFIGURED_NOT_VERIFIED. The state changes when
the provider actually answers:

  LIVE                      the last real call succeeded
  CONFIGURED_NOT_VERIFIED   credentials present, no real call observed yet
  NEEDS_CONFIGURATION       credentials missing
  DISABLED                  switched off by a feature flag
  QUOTA_EXHAUSTED           the provider refused for credit / quota
                            (HTTP 402, or 429 / RESOURCE_EXHAUSTED quota)
  ERROR                     any other failure of the last real call (incl. 401 /
                            403 credentials rejected -- the reason says which)

Example from production (2026-10-07): Sarvam answered HTTP 402 when the
account credit ran out -- that is QUOTA_EXHAUSTED, distinguishable from a
missing key (NEEDS_CONFIGURATION), a flag switched off (DISABLED), a healthy
provider (LIVE) and any other error (ERROR).

No secret, request body or user text is ever recorded: only the provider
name, the outcome, an HTTP status code and a short machine reason. State is
per process (resets on deploy -> CONFIGURED_NOT_VERIFIED until the next real
call), which is honest: it never reports a stale LIVE after a restart.
"""

from __future__ import annotations

import re
import threading
from datetime import datetime, timezone
from typing import Any

LIVE = "LIVE"
CONFIGURED_NOT_VERIFIED = "CONFIGURED_NOT_VERIFIED"
NEEDS_CONFIGURATION = "NEEDS_CONFIGURATION"
DISABLED = "DISABLED"
QUOTA_EXHAUSTED = "QUOTA_EXHAUSTED"
ERROR = "ERROR"
STATES = (LIVE, CONFIGURED_NOT_VERIFIED, NEEDS_CONFIGURATION, DISABLED, QUOTA_EXHAUSTED, ERROR)

_lock = threading.Lock()
_observed: dict[str, dict[str, Any]] = {}
_QUOTA_WORDS = re.compile(r"quota|credit|insufficient|resource[_ ]exhausted|billing|payment required|exceeded",
                          re.IGNORECASE)


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def classify(status_code: int | None = None, reason: str = "") -> str:
    """The outcome of one real call."""
    text = str(reason or "")
    code = int(status_code) if isinstance(status_code, int) or str(status_code or "").isdigit() else None
    if code is None:
        match = re.search(r"(?:HTTP_|\b)([1-5]\d\d)\b", text)
        code = int(match.group(1)) if match else None
    if code is not None and 200 <= code < 300:
        return LIVE
    if code == 402 or (code == 429 and _QUOTA_WORDS.search(text)) or (code is None and _QUOTA_WORDS.search(text)):
        return QUOTA_EXHAUSTED
    return ERROR


def record(provider: str, *, ok: bool = False, status_code: int | None = None, reason: str = "") -> str:
    """Record what a real call to ``provider`` returned. Never raises."""
    try:
        outcome = LIVE if ok else classify(status_code, reason)
        entry = {"outcome": outcome, "status_code": status_code, "reason": str(reason or "")[:80], "at": _now()}
        with _lock:
            row = _observed.setdefault(provider, {})
            row["last"] = entry
            if outcome == LIVE:
                row["last_success_at"] = entry["at"]
            else:
                row["last_failure"] = entry
                row["failures"] = int(row.get("failures") or 0) + 1
        return outcome
    except Exception:
        return ERROR


def state(provider: str, *, configured: bool, enabled: bool = True) -> dict[str, Any]:
    """The provider's current truthful state for dashboards / readiness."""
    with _lock:
        row = dict(_observed.get(provider) or {})
    last = row.get("last")
    if not configured:
        value, why = NEEDS_CONFIGURATION, "credentials are not set on this deployment"
    elif not enabled:
        value, why = DISABLED, "switched off by a feature flag"
    elif not last:
        value, why = CONFIGURED_NOT_VERIFIED, "credentials present; no real call observed since the last deploy"
    else:
        value = last["outcome"]
        why = {
            LIVE: "the last real call succeeded",
            QUOTA_EXHAUSTED: "the provider refused for credit / quota -- recharge or raise the quota",
            ERROR: ("the provider rejected the credentials (HTTP %s)" % last.get("status_code")
                    if last.get("status_code") in (401, 403) else "the last real call failed"),
        }.get(value, "")
    return {"provider": provider, "state": value, "reason": why, "last_checked_at": (last or {}).get("at"),
            "last_success_at": row.get("last_success_at"),
            "last_failure": {k: v for k, v in (row.get("last_failure") or {}).items() if k != "reason"} or None,
            "last_status_code": (last or {}).get("status_code")}


def snapshot() -> dict[str, dict[str, Any]]:
    with _lock:
        return {k: dict(v) for k, v in _observed.items()}


def reset() -> None:
    """Tests only."""
    with _lock:
        _observed.clear()
