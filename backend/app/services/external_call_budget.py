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


# Optional durable sink (set at app start): record(provider, calls, cache_hits,
# errors) -> persisted per day so usage survives deploys and is shared by
# every server instance. Failures in the sink never affect the caller.
_sink: Callable[..., None] | None = None


def set_sink(sink: Callable[..., None] | None) -> None:
    global _sink
    _sink = sink


def _bump(provider: str, key: str) -> None:
    """Count one event. Call WITHOUT holding the lock (the durable sink
    writes to the database)."""
    with _lock:
        stats = _usage.setdefault(provider, {"calls": 0, "cache_hits": 0, "errors": 0})
        stats[key] = stats.get(key, 0) + 1
    if _sink is not None:
        try:
            _sink(provider, **{key: 1})
        except Exception:
            pass


# Estimated cost per real call in ₹ (list prices, configurable with the env
# var ASKODOX_API_COST_INR='{"brave": 0.42, ...}'). An estimate, labelled as
# such in Admin -- the provider's bill is the source of truth.
DEFAULT_COST_INR = {
    "brave": 0.42,           # Brave Search API ~ $5 / 1000
    "google_places": 2.70,   # Places Text Search ~ $32 / 1000
    "google_geocode": 0.42,  # Geocoding ~ $5 / 1000
    "llm_extract": 0.05,     # small LLM extraction call (varies by model/tokens)
}


def cost_table() -> dict[str, float]:
    import json
    import os

    table = dict(DEFAULT_COST_INR)
    try:
        table.update({k: float(v) for k, v in json.loads(os.getenv("ASKODOX_API_COST_INR", "") or "{}").items()})
    except (TypeError, ValueError):
        pass
    return table


def cached_call(provider: str, key: tuple, fetch: Callable[[], Any], *, ttl: int = DEFAULT_TTL_SECONDS) -> Any:
    """Return a cached result for (provider, key) or call ``fetch`` once."""
    full_key = (provider, *key)
    now = time.monotonic()
    with _lock:
        hit = _cache.get(full_key)
        if hit is not None and hit[0] > now:
            _cache.move_to_end(full_key)
            cached = True
        else:
            cached = False
    if cached:
        _bump(provider, "cache_hits")
        return hit[1]
    try:
        value = fetch()
    except Exception:
        _bump(provider, "calls")
        _bump(provider, "errors")
        raise
    _bump(provider, "calls")
    if value:
        with _lock:
            _cache[full_key] = (now + ttl, value)
            while len(_cache) > MAX_ENTRIES:
                _cache.popitem(last=False)
    return value


def record_error(provider: str) -> None:
    _bump(provider, "errors")


def usage_snapshot() -> dict[str, dict[str, int]]:
    with _lock:
        return {name: dict(stats) for name, stats in _usage.items()}


def reset_for_tests() -> None:
    with _lock:
        _cache.clear()
        _usage.clear()
