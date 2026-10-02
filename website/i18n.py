"""Locale state shared by build.py and pages (one module instance, even when
build.py runs as __main__)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_CACHE: dict[str, dict] = {}
_CURRENT = {"code": "en"}


def load_locale(code: str) -> dict:
    if code not in _CACHE:
        path = ROOT / "locales" / f"{code}.json"
        _CACHE[code] = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    return _CACHE[code]


def set_locale(code: str) -> None:
    _CURRENT["code"] = code


def current() -> str:
    return _CURRENT["code"]


def t(key: str) -> str:
    val = load_locale(_CURRENT["code"]).get(key)
    if val is None:
        val = load_locale("en").get(key, key)
    return val
