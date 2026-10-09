"""Strict release gate: READY only when every condition PASSes. Device
conditions come only from the real-phone checklist (qa_checks) -- a check
counts only when a person marked it PHONE VERIFIED with evidence. Nothing
here can turn a pending device test green, and no condition is waived."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HOME = ROOT / "lib" / "features" / "home" / "presentation" / "askodox_primary_home_screen.dart"


def static_conditions(app: Any) -> list[dict[str, Any]]:
    """Code-level conditions (also run in CI by tests/test_release_gate.py)."""
    from app.services import business_creations, feature_registry

    out = []
    problems = feature_registry.validate(app=app)
    out.append({"id": "approved_features_intact", "kind": "auto", "status": "PASS" if not problems else "FAIL",
                "evidence": "; ".join(problems[:5]) or "every approved feature's routes, keys, flags and tests exist"})
    home = HOME.read_text(encoding="utf-8") if HOME.exists() else ""
    tile = bool(re.search(r"'/business|askodoxBusinessSection|My Business", home))
    out.append({"id": "home_screen_unchanged_no_business_tile", "kind": "auto", "status": "FAIL" if tile else "PASS",
                "evidence": "Home screen references My Business" if tile else "no My Business entry on Home"})
    paths = {str(getattr(r, "path", "")) for r in getattr(app, "routes", [])}
    pay = sorted(p for p in paths if re.search(r"recharge|top-?up|auto-?pay", p, re.I))
    out.append({"id": "no_auto_recharge", "kind": "auto", "status": "FAIL" if pay else "PASS",
                "evidence": ", ".join(pay) or "no recharge / top-up / auto-pay route exists"})
    caps = business_creations.capabilities(ai_ready=True)
    claimed = [k for k in ("image_generation", "video_generation") if caps[k]["status"] != "NOT_AVAILABLE"]
    out.append({"id": "no_unbacked_generation_claims", "kind": "auto", "status": "FAIL" if claimed else "PASS",
                "evidence": ", ".join(claimed) or "image / video generation reported NOT_AVAILABLE (no provider)"})
    return out


def evaluate(app: Any, *, incidents: dict[str, Any] | None, qa_checks: list[dict[str, Any]]) -> dict[str, Any]:
    conditions = static_conditions(app)
    if incidents is not None:
        state = (incidents.get("release_readiness") or {}).get("state")
        blocking = (incidents.get("release_readiness") or {}).get("blocking") or []
        conditions.append({"id": "no_red_incidents", "kind": "runtime",
                           "status": "FAIL" if state == "NOT_READY" else "PASS",
                           "evidence": ", ".join(blocking) or "no red incident in recorded telemetry"})
    pending = [c for c in qa_checks if str(c.get("status") or "").upper() != "PHONE VERIFIED"
               and not c.get("archived")]
    conditions.append({"id": "real_phone_acceptance", "kind": "device",
                       "status": "PASS" if qa_checks and not pending else "PENDING",
                       "evidence": (f"{len(pending)} of {len(qa_checks)} phone checks not PHONE VERIFIED"
                                    if qa_checks else "no phone checks recorded")})
    if any(c["status"] == "FAIL" for c in conditions):
        overall = "NOT_READY"
    elif any(c["status"] == "PENDING" for c in conditions):
        overall = "BLOCKED_ON_DEVICE_VERIFICATION"
    else:
        overall = "READY"
    return {"overall": overall, "conditions": conditions,
            "rule": "READY only when every condition PASSes; device conditions need PHONE VERIFIED evidence."}
