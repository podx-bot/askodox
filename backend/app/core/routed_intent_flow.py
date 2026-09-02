"""Patch-safe orchestration from user wording to domain execution.

The flow composes the intent router, required-field policy, and isolated domain
registry without moving business rules into the Universal Deal Brain.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from backend.app.core.domain_field_requirements import missing_fields
from backend.app.core.domain_module_registry import DomainModuleRegistry
from backend.app.core.intent_domain_router import IntentRoute, RealUserIntentRouter


@dataclass(frozen=True)
class RoutedIntentResult:
    route: IntentRoute
    missing: tuple[str, ...]
    ready: bool
    output: Any = None


class RoutedIntentFlow:
    """Route, collect only missing fields, then dispatch to the domain module."""

    def __init__(
        self,
        router: RealUserIntentRouter,
        registry: DomainModuleRegistry,
    ) -> None:
        self._router = router
        self._registry = registry

    def evaluate(self, text: str, payload: Mapping[str, Any]) -> RoutedIntentResult:
        route = self._router.route(text)
        missing = missing_fields(route.domain, route.action, payload)
        return RoutedIntentResult(
            route=route,
            missing=missing,
            ready=not missing,
        )

    def execute_when_ready(
        self,
        text: str,
        payload: Mapping[str, Any],
    ) -> RoutedIntentResult:
        result = self.evaluate(text, payload)
        if not result.ready:
            return result

        output = self._registry.execute(
            result.route.domain,
            dict(payload),
            action=result.route.action,
        )
        return RoutedIntentResult(
            route=result.route,
            missing=(),
            ready=True,
            output=output,
        )
