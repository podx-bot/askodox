"""Patch-safe required-field policies for ASKODOX routed intents.

This module keeps per-domain/action collection requirements outside the
Universal Deal Brain so one flow can evolve without disturbing unrelated flows.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


@dataclass(frozen=True)
class FieldPolicy:
    required: tuple[str, ...]


DEFAULT_FIELD_POLICIES: Mapping[tuple[str, str], FieldPolicy] = {
    ("commerce", "buy"): FieldPolicy(("subject", "location")),
    ("commerce", "sell"): FieldPolicy(("subject", "location")),
    ("rental", "rent"): FieldPolicy(("subject", "location", "timing")),
    ("appointment", "book"): FieldPolicy(("subject", "location", "timing")),
    ("parcel", "send"): FieldPolicy(("from_location", "to_location", "timing")),
    ("assistance", "complaint"): FieldPolicy(("subject", "issue")),
    ("assistance", "application"): FieldPolicy(("subject", "applicant_context")),
    ("assistance", "doubt"): FieldPolicy(("subject", "question")),
}


class FieldPolicyNotFoundError(LookupError):
    """Raised when no required-field policy exists for a routed intent."""


def required_fields(domain: str, action: str = "default") -> tuple[str, ...]:
    key = (str(domain or "").strip().casefold(), str(action or "default").strip().casefold())
    policy = DEFAULT_FIELD_POLICIES.get(key)
    if policy is None:
        raise FieldPolicyNotFoundError(f"no field policy for {key[0]}:{key[1]}")
    return policy.required


def missing_fields(domain: str, action: str, payload: Mapping[str, Any]) -> tuple[str, ...]:
    """Return only fields still missing or blank from the current deal state."""
    missing: list[str] = []
    for field in required_fields(domain, action):
        value = payload.get(field)
        if value is None:
            missing.append(field)
            continue
        if isinstance(value, str) and not value.strip():
            missing.append(field)
    return tuple(missing)
