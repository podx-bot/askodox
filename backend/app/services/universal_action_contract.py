"""Stable category-aware action/result envelope over existing lifecycle services."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

from app.services.universal_category_schema import UniversalCategorySchemaRegistry


@dataclass(frozen=True)
class ActionDescriptor:
    id: str
    label: str
    role: str
    requires_consent: bool = False


@dataclass(frozen=True)
class ActionResult:
    status: str
    raw_status: str
    request_id: Any = None
    category: str = "GENERAL"
    result_kind: str = "general"
    side: str | None = None
    role: str | None = None
    lifecycle_state: str = "UNKNOWN"
    next_actions: tuple[ActionDescriptor, ...] = ()
    required_fields: tuple[str, ...] = ()
    missing_fields: tuple[str, ...] = ()
    consent: dict[str, Any] = field(default_factory=dict)
    channel: str | None = None
    result: dict[str, Any] = field(default_factory=dict)
    error: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def actions_for(category: str | None, side: str | None, lifecycle_state: str) -> tuple[ActionDescriptor, ...]:
    schema = UniversalCategorySchemaRegistry.resolve(category)
    normalized_side = str(side or "NEED").upper()
    state = str(lifecycle_state or "").upper()
    if state in {"CONVERTED", "COMPLETED", "CANCELLED", "DECLINED"}:
        return ()
    if state in {"WAITING_SELLER_CONFIRM", "IN_APP_WAITING_SELLER_CONFIRM", "INTEREST_PENDING"}:
        return (ActionDescriptor("confirm_interest", "Confirm interest", schema.provider_capability, True),)
    if normalized_side == "NEED":
        return (
            ActionDescriptor("ask_counterparty", f"Ask {schema.provider_capability.lower()}", schema.seeker_capability),
            ActionDescriptor("confirm", "Confirm", schema.seeker_capability, True),
        )
    return (ActionDescriptor("review_request", "Review request", schema.provider_capability),)


def build_action_result(*, raw_status: str, request_id: Any = None, category: str | None = None,
                        side: str | None = None, role: str | None = None, channel: str | None = None,
                        missing_fields: tuple[str, ...] = (), result: dict[str, Any] | None = None,
                        consent: dict[str, Any] | None = None) -> ActionResult:
    schema = UniversalCategorySchemaRegistry.resolve(category)
    lifecycle = str(raw_status or "UNKNOWN").upper()
    return ActionResult(
        status=lifecycle,
        raw_status=str(raw_status or "UNKNOWN"),
        request_id=request_id,
        category=schema.category,
        result_kind=schema.result_kind,
        side=side,
        role=role,
        lifecycle_state=lifecycle,
        next_actions=actions_for(schema.category, side, lifecycle),
        required_fields=schema.required_fields,
        missing_fields=missing_fields,
        consent=consent or {},
        channel=channel,
        result=result or {},
    )
