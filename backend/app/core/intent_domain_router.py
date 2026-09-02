"""Patch-safe natural-language intent routing for ASKODOX domain modules.

This layer converts common real-user search phrasing into a domain/action route
without embedding domain behavior in the Universal Deal Brain. Domain-specific
phrases live in independently registered rules, so one category can evolve
without changing unrelated categories.
"""
from __future__ import annotations

from dataclasses import dataclass
import re
from threading import RLock
from typing import Any, Iterable

from backend.app.core.domain_module_registry import DomainModuleRegistry


_WORD_RE = re.compile(r"[^\W_]+", re.UNICODE)


@dataclass(frozen=True)
class IntentRule:
    domain: str
    action: str = "default"
    phrases: tuple[str, ...] = ()
    keywords: tuple[str, ...] = ()
    exclude_keywords: tuple[str, ...] = ()
    priority: int = 0

    def __post_init__(self) -> None:
        if not str(self.domain or "").strip():
            raise ValueError("domain must not be empty")
        if not self.phrases and not self.keywords:
            raise ValueError("intent rule needs at least one phrase or keyword")


@dataclass(frozen=True)
class IntentRoute:
    domain: str
    action: str
    score: int
    matched_terms: tuple[str, ...]


class IntentRouteNotFoundError(LookupError):
    """Raised when no registered rule confidently matches the user's text."""


class RealUserIntentRouter:
    """Route natural user wording to isolated domain modules.

    Rules are registered independently. Phrase matches are stronger than loose
    keyword matches, while exclusions reduce false positives. The router does
    not own domain business logic; it only chooses the module boundary.
    """

    def __init__(self, *, minimum_score: int = 2) -> None:
        if minimum_score < 1:
            raise ValueError("minimum_score must be >= 1")
        self.minimum_score = minimum_score
        self._rules: list[IntentRule] = []
        self._lock = RLock()

    def register(self, rule: IntentRule) -> None:
        with self._lock:
            self._rules.append(rule)

    def register_many(self, rules: Iterable[IntentRule]) -> None:
        for rule in rules:
            self.register(rule)

    def route(self, text: str) -> IntentRoute:
        normalized = self._normalize(text)
        if not normalized:
            raise IntentRouteNotFoundError("empty user text")
        tokens = set(_WORD_RE.findall(normalized))

        with self._lock:
            rules = tuple(self._rules)

        candidates: list[IntentRoute] = []
        for rule in rules:
            score = rule.priority
            matched: list[str] = []

            excluded = [
                term for term in rule.exclude_keywords
                if self._normalize(term) in tokens
            ]
            if excluded:
                continue

            for phrase in rule.phrases:
                term = self._normalize(phrase)
                if term and term in normalized:
                    score += 4
                    matched.append(term)

            for keyword in rule.keywords:
                term = self._normalize(keyword)
                if term and term in tokens:
                    score += 2
                    matched.append(term)

            if score >= self.minimum_score and matched:
                candidates.append(
                    IntentRoute(
                        domain=str(rule.domain).strip().casefold(),
                        action=str(rule.action or "default").strip().casefold() or "default",
                        score=score,
                        matched_terms=tuple(dict.fromkeys(matched)),
                    )
                )

        if not candidates:
            raise IntentRouteNotFoundError("no registered intent rule matched")

        candidates.sort(
            key=lambda route: (route.score, len(route.matched_terms)),
            reverse=True,
        )
        return candidates[0]

    def dispatch(
        self,
        text: str,
        payload: Any,
        registry: DomainModuleRegistry,
    ) -> Any:
        route = self.route(text)
        return registry.execute(route.domain, payload, action=route.action)

    @staticmethod
    def _normalize(value: str) -> str:
        return " ".join(str(value or "").casefold().strip().split())
