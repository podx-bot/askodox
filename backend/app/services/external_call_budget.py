"""Shared cost control for paid external APIs (Brave, Google Places...).

* A small in-process TTL cache so the same query is not paid for twice in a
  few minutes (a follow-up "show me" or a re-render repeats the search).
* Per-provider usage counters (calls, cache hits, errors) for Admin
  analytics. Counters are process-local and reset on deploy -- they report
  real calls made by this process, never estimates.

Only successful, non-empty responses are cached, so a transient provider
failure is retried next time instead of being remembered.
"""
from __future__ import annotations

import threading
import time
from collections import OrderedDict
from typing import Any, Callable

DEFAULT_TTL_SECONDS = 600
MAX_ENTRIES = 512

_lock = threading.Lock()
_cache: "OrderedDict[tuple, tuple[float, Any]]" = OrderedDict()
_usage: dict[str, dict[str, int]] = {}


def _bump(provider: str, key: str) -> None:
    stats = _usage.setdefault(provider, {"calls": 0, "cache_hits": 0, "errors": 0})
    stats[key] = stats.get(key, 0) + 1


def cached_call(provider: str, key: tuple, fetch: Callable[[], Any], *, ttl: int = DEFAULT_TTL_SECONDS) -> Any:
    """Return a cached result for (provider, key) or call ``fetch`` once."""
    full_key = (provider, *key)
    now = time.monotonic()
    with _lock:
        hit = _cache.get(full_key)
        if hit is not None and hit[0] > now:
            _cache.move_to_end(full_key)
            _bump(provider, "cache_hits")
            return hit[1]
    try:
        value = fetch()
    except Exception:
        with _lock:
            _bump(provider, "calls")
            _bump(provider, "errors")
        raise
    with _lock:
        _bump(provider, "calls")
        if value:
            _cache[full_key] = (now + ttl, value)
            while len(_cache) > MAX_ENTRIES:
                _cache.popitem(last=False)
    return value


def record_error(provider: str) -> None:
    with _lock:
        _bump(provider, "errors")


def usage_snapshot() -> dict[str, dict[str, int]]:
    with _lock:
        return {name: dict(stats) for name, stats in _usage.items()}


def reset_for_tests() -> None:
    with _lock:
        _cache.clear()
        _usage.clear()
