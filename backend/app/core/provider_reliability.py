"""Patch-safe provider failover and circuit-breaker primitive.

The executor is intentionally provider/domain agnostic. Individual AI, voice,
vision, maps, search, payment, notification, or other adapters can opt into
this layer without changing the Universal Deal Brain or unrelated domains.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from dataclasses import dataclass
from threading import Lock
from time import monotonic
from typing import Callable, Generic, Iterable, TypeVar


T = TypeVar("T")


class ProviderUnavailableError(RuntimeError):
    """Raised when every configured provider is unavailable or fails."""


@dataclass(frozen=True)
class ProviderPolicy:
    timeout_seconds: float = 8.0
    failure_threshold: int = 3
    cooldown_seconds: float = 30.0

    def __post_init__(self) -> None:
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be > 0")
        if self.failure_threshold < 1:
            raise ValueError("failure_threshold must be >= 1")
        if self.cooldown_seconds < 0:
            raise ValueError("cooldown_seconds must be >= 0")


@dataclass
class _CircuitState:
    failures: int = 0
    open_until: float = 0.0


class ProviderReliabilityExecutor(Generic[T]):
    """Run isolated provider adapters with timeout, failover and circuits.

    Providers are supplied in priority order as ``(name, callable)`` pairs.
    A failure or timeout falls through to the next provider. Repeated failures
    open only that provider's circuit, leaving other providers/domains intact.
    """

    def __init__(self, policy: ProviderPolicy | None = None) -> None:
        self.policy = policy or ProviderPolicy()
        self._states: dict[str, _CircuitState] = {}
        self._lock = Lock()

    def execute(self, providers: Iterable[tuple[str, Callable[[], T]]]) -> T:
        errors: list[str] = []
        attempted = False

        for raw_name, operation in providers:
            name = str(raw_name or "").strip()
            if not name:
                raise ValueError("provider name must not be empty")
            if not callable(operation):
                raise TypeError(f"provider {name!r} operation must be callable")
            if self._circuit_is_open(name):
                errors.append(f"{name}: circuit_open")
                continue

            attempted = True
            try:
                result = self._run_with_timeout(operation)
            except FutureTimeoutError:
                self._record_failure(name)
                errors.append(f"{name}: timeout")
                continue
            except Exception as exc:  # Provider adapters define their own errors.
                self._record_failure(name)
                errors.append(f"{name}: {type(exc).__name__}")
                continue

            self._record_success(name)
            return result

        if not attempted and errors:
            raise ProviderUnavailableError("all provider circuits are open; " + ", ".join(errors))
        if errors:
            raise ProviderUnavailableError("all providers failed; " + ", ".join(errors))
        raise ProviderUnavailableError("no providers configured")

    def circuit_open(self, provider_name: str) -> bool:
        """Public read-only circuit state useful for health/diagnostic checks."""
        return self._circuit_is_open(provider_name)

    def _run_with_timeout(self, operation: Callable[[], T]) -> T:
        executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="askodox-provider")
        future = executor.submit(operation)
        try:
            return future.result(timeout=self.policy.timeout_seconds)
        finally:
            # A timed-out blocking SDK call cannot be force-killed safely. Do not
            # make the request path wait for it; provider adapters should also set
            # their native network timeout so the worker exits promptly.
            executor.shutdown(wait=False, cancel_futures=True)

    def _circuit_is_open(self, provider_name: str) -> bool:
        now = monotonic()
        with self._lock:
            state = self._states.get(provider_name)
            if state is None or state.open_until <= 0:
                return False
            if now < state.open_until:
                return True
            # Cooldown elapsed: allow a probe request and reset the open marker.
            state.open_until = 0.0
            return False

    def _record_failure(self, provider_name: str) -> None:
        now = monotonic()
        with self._lock:
            state = self._states.setdefault(provider_name, _CircuitState())
            state.failures += 1
            if state.failures >= self.policy.failure_threshold:
                state.open_until = now + self.policy.cooldown_seconds

    def _record_success(self, provider_name: str) -> None:
        with self._lock:
            state = self._states.setdefault(provider_name, _CircuitState())
            state.failures = 0
            state.open_until = 0.0
