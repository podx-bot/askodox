"""Approved Feature Registry (docs/approved_features.json) -- the regression lock.

``validate()`` checks every approved feature against the REAL code:
  * its API routes are mounted on the production app (``server.app``),
  * response models still carry the contracted keys,
  * its Flutter widget keys / symbols still exist in lib/,
  * its feature flags exist and keep their approved default (a default-off
    change can never silently remove a feature),
  * its acceptance tests exist (and, for "file::name", still contain that test),
  * a deprecated feature carries an owner approval + migration,
  * (against the base branch) no approved feature was deleted.

``runtime()`` gives the Command Center a live state per feature:
WORKING / DEGRADED / DISABLED / FAILED / UNVERIFIED -- never "working"
without a real health signal.
"""

from __future__ import annotations

import importlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[3]
REGISTRY = ROOT / "docs" / "approved_features.json"
REQUIRED = ("id", "name", "purpose", "expected_behavior", "roles", "domains", "tests", "status", "history")


def load(path: Path | str = REGISTRY) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _routes(app: Any) -> set[tuple[str, str]]:
    found: set[tuple[str, str]] = set()
    for route in getattr(app, "routes", []):
        for method in getattr(route, "methods", None) or ():
            found.add((method.upper(), str(getattr(route, "path", ""))))
    return found


def _lib_text(root: Path) -> str:
    return "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in (root / "lib").rglob("*.dart"))


def _app_flag_defaults(root: Path) -> dict[str, bool]:
    path = root / "lib" / "core" / "flags" / "askodox_remote_flags.dart"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    return {k: v == "true" for k, v in re.findall(r"'([a-z0-9_.]+)':\s*(true|false)", text)}


def validate(registry: dict[str, Any] | None = None, *, root: Path = ROOT, app: Any = None,
             base: dict[str, Any] | None = None) -> list[str]:
    """Every problem found (empty = the release keeps every approved feature)."""
    from app.repositories.command_center_repository import FEATURE_FLAGS, FLAG_DEFAULTS

    registry = registry or load(root / "docs" / "approved_features.json")
    problems: list[str] = []
    features = registry.get("features") or []
    ids = [f.get("id") for f in features]
    if len(ids) != len(set(ids)):
        problems.append("duplicate feature ids")
    if app is None:
        from server import app as server_app
        app = server_app
    routes = _routes(app)
    lib = _lib_text(root)
    app_defaults = _app_flag_defaults(root)
    for feature in features:
        fid = feature.get("id") or "?"
        for key in REQUIRED:
            if key not in feature:
                problems.append(f"{fid}: missing '{key}'")
        if feature.get("status") == "deprecated":
            dep = feature.get("deprecation") or {}
            if not all(dep.get(k) for k in ("approved_by", "date", "migration")):
                problems.append(f"{fid}: deprecated without owner approval, date and migration")
            continue
        for api in feature.get("api") or []:
            if (api["method"].upper(), api["path"]) not in routes:
                problems.append(f"{fid}: route {api['method']} {api['path']} is not mounted")
            if api.get("response_model"):
                module, _, name = api["response_model"].partition(":")
                fields = set(getattr(getattr(importlib.import_module(module), name), "model_fields", {}) or {})
                missing = [k for k in api.get("response_keys") or [] if k not in fields]
                if missing:
                    problems.append(f"{fid}: {api['response_model']} lost {missing}")
        ui = feature.get("ui") or {}
        for key in ui.get("keys") or []:
            if f"'{key}'" not in lib and f'"{key}"' not in lib:
                problems.append(f"{fid}: widget key {key} no longer exists in lib/")
        for symbol in ui.get("symbols") or []:
            if not re.search(rf"\b{re.escape(symbol)}\b", lib):
                problems.append(f"{fid}: symbol {symbol} no longer exists in lib/")
        for key, default in (feature.get("flags") or {}).items():
            if key not in FEATURE_FLAGS:
                problems.append(f"{fid}: flag {key} was removed")
            elif bool(FLAG_DEFAULTS.get(key, True)) != bool(default):
                problems.append(f"{fid}: flag {key} default changed (approved {default})")
            if key in app_defaults and app_defaults[key] != bool(default):
                problems.append(f"{fid}: app default for {key} changed (approved {default})")
        for side, base_dir in (("backend", root / "backend"), ("flutter", root)):
            for ref in (feature.get("tests") or {}).get(side) or []:
                file, _, name = ref.partition("::")
                path = base_dir / file
                if not path.exists():
                    problems.append(f"{fid}: acceptance test {file} is missing")
                elif name and name not in path.read_text(encoding="utf-8", errors="ignore"):
                    problems.append(f"{fid}: acceptance test '{name}' is missing from {file}")
    if base is not None:
        removed = sorted({f.get("id") for f in base.get("features") or []} - set(ids))
        for fid in removed:
            problems.append(f"{fid}: approved feature deleted from the registry (deprecate it with owner approval)")
    return problems


def runtime(container: Any, health: Iterable[dict[str, Any]] = ()) -> list[dict[str, Any]]:
    """Live state per approved feature for the Command Center."""
    from app.api.routes.command_center import command_center

    flags = command_center(container).flags()
    signals = {str(c.get("name")): str(c.get("status")) for c in health}
    rows = []
    for feature in load().get("features") or []:
        if feature.get("status") == "deprecated":
            state, why = "DISABLED", "deprecated"
        else:
            off = [k for k in feature.get("flags") or {} if not (flags.get(k) or {}).get("enabled", True)]
            signal = signals.get(str(feature.get("health") or ""))
            if off:
                state, why = "DISABLED", "flag off: " + ", ".join(off)
            elif signal == "ok":
                state, why = "WORKING", f"health signal {feature['health']} is ok"
            elif signal == "degraded":
                state, why = "DEGRADED", f"health signal {feature['health']} is degraded"
            elif signal == "error":
                state, why = "FAILED", f"health signal {feature['health']} is failing"
            else:
                state, why = "UNVERIFIED", "no live health signal yet -- code and tests only, not a phone check"
        rows.append({"id": feature["id"], "name": feature["name"], "state": state, "why": why,
                     "flags": feature.get("flags") or {}, "status": feature.get("status"),
                     "expected_behavior": feature.get("expected_behavior")})
    return rows
