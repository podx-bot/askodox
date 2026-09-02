"""Patch-safe registry for isolated ASKODOX domain modules.

The registry keeps domain-specific behavior behind a stable lookup boundary so
small category changes do not require edits to the Universal Deal Brain or to
unrelated domains.
"""
from __future__ import annotations

from dataclasses import dataclass
from threading import RLock
from typing import Any, Callable, Mapping


DomainHandler = Callable[[Any], Any]


class DomainModuleError(RuntimeError):
    """Base error for domain module registration and lookup failures."""


class DomainModuleNotFoundError(DomainModuleError):
    """Raised when no handler is registered for the requested domain/action."""


@dataclass(frozen=True)
class DomainModuleKey:
    domain: str
    action: str = "default"

    @classmethod
    def normalize(cls, domain: str, action: str = "default") -> "DomainModuleKey":
        normalized_domain = str(domain or "").strip().casefold()
        normalized_action = str(action or "default").strip().casefold() or "default"
        if not normalized_domain:
            raise ValueError("domain must not be empty")
        return cls(normalized_domain, normalized_action)


class DomainModuleRegistry:
    """Thread-safe registry with explicit domain/action isolation.

    A module can be replaced independently, which makes targeted patches and
    rollback possible without mutating handlers registered for other domains.
    """

    def __init__(self) -> None:
        self._handlers: dict[DomainModuleKey, DomainHandler] = {}
        self._lock = RLock()

    def register(
        self,
        domain: str,
        handler: DomainHandler,
        *,
        action: str = "default",
        replace: bool = False,
    ) -> None:
        if not callable(handler):
            raise TypeError("handler must be callable")
        key = DomainModuleKey.normalize(domain, action)
        with self._lock:
            if key in self._handlers and not replace:
                raise DomainModuleError(
                    f"module already registered for {key.domain}:{key.action}"
                )
            self._handlers[key] = handler

    def unregister(self, domain: str, *, action: str = "default") -> bool:
        key = DomainModuleKey.normalize(domain, action)
        with self._lock:
            return self._handlers.pop(key, None) is not None

    def resolve(self, domain: str, *, action: str = "default") -> DomainHandler:
        key = DomainModuleKey.normalize(domain, action)
        with self._lock:
            handler = self._handlers.get(key)
        if handler is None:
            raise DomainModuleNotFoundError(
                f"no module registered for {key.domain}:{key.action}"
            )
        return handler

    def execute(self, domain: str, payload: Any, *, action: str = "default") -> Any:
        return self.resolve(domain, action=action)(payload)

    def snapshot(self) -> Mapping[str, tuple[str, ...]]:
        """Return immutable diagnostic view without exposing handler objects."""
        with self._lock:
            grouped: dict[str, list[str]] = {}
            for key in self._handlers:
                grouped.setdefault(key.domain, []).append(key.action)
        return {
            domain: tuple(sorted(actions))
            for domain, actions in sorted(grouped.items())
        }
