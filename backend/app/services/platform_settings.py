"""Bounded platform settings edited in the Command Center (``platform_settings``
schema resource). A setting applies while its record is ACTIVE; disabled,
missing or out-of-range values fall back to the built-in default, so a bad
row can never take a feature outside its safe range."""
from __future__ import annotations

import time
from typing import Any, Callable, Dict, Optional

from app.services.platform_schema import SETTING_BOUNDS

_SOURCE: Optional[Callable[[], list]] = None
_SOURCE_KEY: Optional[str] = None
_CACHE: Dict[str, Any] = {"at": 0.0, "values": {}}
TTL_SECONDS = 30


def set_source(reader: Callable[[], list], key: Optional[str] = None) -> None:
    """``reader`` returns the platform_settings records (the platform repo);
    ``key`` identifies the database, so a re-bind is cheap and exact."""
    global _SOURCE, _SOURCE_KEY
    if key is not None and key == _SOURCE_KEY and _SOURCE is not None:
        return
    _SOURCE, _SOURCE_KEY = reader, key
    _CACHE["at"] = 0.0


def invalidate() -> None:
    _CACHE["at"] = 0.0


def _values() -> Dict[str, float]:
    if _SOURCE is None:
        return {}
    if time.monotonic() - _CACHE["at"] < TTL_SECONDS:
        return _CACHE["values"]
    values: Dict[str, float] = {}
    try:
        for record in _SOURCE() or []:
            if record.get("status") != "ACTIVE" or record.get("archived"):
                continue
            data = record.get("data") or {}
            key, value = data.get("key"), data.get("value")
            if key in SETTING_BOUNDS and value is not None:
                values[key] = float(value)
    except Exception:
        values = {}
    _CACHE.update(at=time.monotonic(), values=values)
    return values


def get(key: str, default: float | None = None) -> float:
    low, high, built_in = SETTING_BOUNDS.get(key, (float("-inf"), float("inf"), default))
    value = _values().get(key)
    if value is None or not low <= value <= high:
        return built_in if default is None else default
    return value


def describe() -> Dict[str, Dict[str, Any]]:
    """Every setting with its effective value and where it came from."""
    values = _values()
    return {key: {"min": low, "max": high, "default": d, "value": values.get(key, d),
                  "source": "command_center" if key in values else "default"}
            for key, (low, high, d) in SETTING_BOUNDS.items()}
