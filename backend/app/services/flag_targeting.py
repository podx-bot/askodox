"""Targeted feature flags: the global flag is the master switch; ACTIVE
``flag_rollouts`` records narrow it by category / sub-category / role /
platform / location / percentage. One evaluator for every caller (results,
advisor, demand alerts, auto-responses, the app and the web chat).
"""
from __future__ import annotations

import hashlib
from typing import Any, Dict, Iterable, List, Optional, Tuple

CONTEXT_KEYS = ("category", "subcategory", "role", "platform", "location", "subject")


def make_context(**values: Any) -> Dict[str, str]:
    return {k: " ".join(str(values.get(k) or "").split()).casefold()[:120] for k in CONTEXT_KEYS}


def bucket(flag: str, subject: str) -> int:
    """Stable 0..99 bucket for a person and flag."""
    digest = hashlib.sha256(f"{flag}:{subject}".encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % 100


def _norm(values: Iterable[Any]) -> List[str]:
    return [" ".join(str(v).split()).casefold() for v in values or [] if str(v).strip()]


def _list_match(wanted: List[str], have: str, *, contains: bool = False) -> bool:
    if not wanted:
        return True
    if not have:
        return False
    if contains:
        return any(w == have or w in have.split() or w in have for w in wanted)
    return have in wanted


def rule_matches(rule: Dict[str, Any], ctx: Dict[str, str]) -> Tuple[bool, str]:
    checks = (
        ("categories", "category", True), ("subcategories", "subcategory", True), ("roles", "role", False),
        ("platforms", "platform", False), ("locations", "location", True),
    )
    for field, key, contains in checks:
        if not _list_match(_norm(rule.get(field)), ctx.get(key, ""), contains=contains):
            return False, f"{key} '{ctx.get(key) or '-'}' not in {field}"
    pct = rule.get("percentage")
    if pct is not None and str(pct) != "" and int(pct) < 100:
        if not ctx.get("subject"):
            return False, f"{pct}% rollout needs a person id"
        b = bucket(str(rule.get("flag") or ""), ctx["subject"])
        if b >= int(pct):
            return False, f"outside the {pct}% rollout (bucket {b})"
    return True, "matches"


def decide(flag: str, global_enabled: bool, rules: Iterable[Dict[str, Any]], ctx: Dict[str, str]
           ) -> Tuple[bool, str]:
    if not global_enabled:
        return False, "global flag is OFF"
    mine = [r for r in rules if str(r.get("flag")) == flag]
    for rule in (r for r in mine if r.get("effect") == "never_for"):
        hit, _ = rule_matches(rule, ctx)
        if hit:
            return False, f"'{rule.get('name')}' switches it off here"
    only = [r for r in mine if r.get("effect") == "only_for"]
    if not only:
        return True, "global flag is ON"
    reasons = []
    for rule in only:
        hit, why = rule_matches(rule, ctx)
        if hit:
            return True, f"'{rule.get('name')}' targets this"
        reasons.append(f"'{rule.get('name')}': {why}")
    return False, "not targeted -- " + "; ".join(reasons)


def active_rules(container: Any) -> List[Dict[str, Any]]:
    try:
        from app.api.routes.platform import platform

        return [dict(r.get("data") or {}, _id=r.get("id"))
                for r in platform(container).repo.list("flag_rollouts", status="ACTIVE")]
    except Exception:
        return []


def effective(container: Any, ctx: Optional[Dict[str, str]] = None, *, explain: bool = False) -> Dict[str, Any]:
    """Every flag for one context (global map with targeting applied)."""
    from app.api.routes.command_center import command_center

    base = command_center(container).flags_map()
    rules = active_rules(container)
    ctx = ctx or make_context()
    out: Dict[str, Any] = {}
    for key, enabled in base.items():
        value, why = decide(key, enabled, rules, ctx) if rules else (enabled, "global flag")
        out[key] = {"enabled": value, "reason": why} if explain else value
    return out


def enabled(container: Any, key: str, ctx: Optional[Dict[str, str]] = None) -> bool:
    """One flag for one context; never raises (falls back to the global flag)."""
    from app.api.routes.command_center import feature_enabled

    base = feature_enabled(container, key)
    if not base:
        return False
    rules = active_rules(container)
    if not rules:
        return True
    return decide(key, True, rules, ctx or make_context())[0]


def context_for_demand(demand: Dict[str, Any], *, platform: str = "", subject: str = "", role: str = ""
                       ) -> Dict[str, str]:
    from app.services import category_signal

    constraints = demand.get("constraints") or {}
    trace = demand.get("trace") or {}
    category, sub = category_signal.for_demand(demand)
    return make_context(category=category, subcategory=sub or "",
                        role=role or constraints.get("context_role") or constraints.get("role") or "",
                        platform=platform or trace.get("platform") or "",
                        location=demand.get("location_text") or constraints.get("location") or "",
                        subject=subject or demand.get("user_id") or trace.get("device_id") or "")
