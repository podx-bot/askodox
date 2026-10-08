"""Assistant feature health from REAL user-facing outcomes (per process).

Provider readiness (``provider_health``) says whether an API answered; this
says whether the FEATURE did its job for real users since the last deploy:

  conversation_intelligence  the brain answered a chat turn (vs. fell back)
  media_analysis             an attachment was understood (vs. refused / failed)
  advice_policy              one-time advice rule violations (repeats)

Only outcome names, counts, a short machine reason and timestamps are kept
-- never user text, attachment content, prompts or credentials. No traffic
since the deploy is reported as such, never as LIVE.
"""

from __future__ import annotations

import threading
from collections import deque
from datetime import datetime, timezone
from typing import Any

WINDOW = 50  # recent outcomes per component used for the state
_lock = threading.Lock()
_recent: dict[str, deque] = {}
_counters: dict[str, int] = {}


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def observe(component: str, ok: bool, reason: str = "") -> None:
    """One real outcome of a user-facing feature. Never raises."""
    try:
        with _lock:
            _recent.setdefault(component, deque(maxlen=WINDOW)).append(
                {"ok": bool(ok), "reason": str(reason or "")[:60], "at": _now()})
    except Exception:
        pass


def record(event: str) -> None:
    """Count a policy event (e.g. ``advice_repeat_violation``)."""
    with _lock:
        _counters[event] = _counters.get(event, 0) + 1


def component_state(component: str) -> dict[str, Any]:
    with _lock:
        rows = list(_recent.get(component) or [])
    if not rows:
        return {"status": "unknown", "detail": "no real traffic since the last deploy", "samples": 0}
    failed = [r for r in rows if not r["ok"]]
    ratio = len(failed) / len(rows)
    last_failure = failed[-1] if failed else None
    if not failed:
        status = "ok"
    elif ratio >= 0.5:
        status = "error"
    else:
        status = "degraded"
    detail = f"{len(rows) - len(failed)}/{len(rows)} recent turns succeeded"
    if last_failure:
        detail += f"; last failure: {last_failure['reason'] or 'unknown'} at {last_failure['at']}"
    return {"status": status, "detail": detail, "samples": len(rows),
            "last_at": rows[-1]["at"]}


def components() -> list[dict[str, Any]]:
    """Rows for /admin/cc/health (same status words as the other components)."""
    rows = [
        {"name": "conversation_intelligence", **component_state("conversation_intelligence")},
        {"name": "media_analysis", **component_state("media_analysis")},
    ]
    with _lock:
        repeats = _counters.get("advice_repeat_violation", 0)
    turns = rows[0]["samples"]
    rows.append({"name": "advice_policy",
                 "status": "degraded" if repeats else ("ok" if turns else "unknown"),
                 "detail": (f"{repeats} repeated warning(s) without new information since the last deploy"
                            if repeats else ("no repeated warnings observed since the last deploy" if turns
                                             else "no real traffic since the last deploy")),
                 "samples": repeats})
    for row in rows:
        row["detail"] += " (feature outcome, not proof every flow works on a phone)"
    return rows


def reset() -> None:
    """Tests only."""
    with _lock:
        _recent.clear()
        _counters.clear()
