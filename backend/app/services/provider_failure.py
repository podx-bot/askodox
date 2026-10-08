"""Why a provider call failed -- so the customer and staff see "quota
exhausted" / "rate limited" / "auth failed" instead of a bare error, and a
failure is never reported as an honest empty answer."""

from __future__ import annotations

from typing import Any

# Source status values a failing provider can produce (besides "error").
FAILURE_KINDS = ("quota_exhausted", "rate_limited", "auth_failed")
FAILURE_STATES = (*FAILURE_KINDS, "error")


def failure_kind(provider: Any) -> str | None:
    """None when the provider's last call (this thread) succeeded, else the
    most specific known failure kind ("error" when the reason is unknown)."""
    if not getattr(provider, "last_error", False):
        return None
    kind = getattr(provider, "last_error_kind", None)
    return kind if kind in FAILURE_KINDS else "error"
