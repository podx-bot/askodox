"""Command Center governance: granular permissions, GREEN / ORANGE / RED risk,
the Permission Safety Advisor and secret redaction.

* Permissions are ``<module>:<verb>``. ``<module>:manage`` implies create /
  edit / approve / delete on that module (backward compatible with the
  original view/manage pairs). ``export`` is never implied: exporting data is
  granted explicitly.
* Risk: GREEN = routine, applied directly; ORANGE = needs a second person
  (an approver) unless the actor is Owner / Super Admin; RED = only Owner /
  Super Admin may apply or approve it, never automated.
* Nothing here executes arbitrary code, SQL or shell -- approvals run only
  the named executors registered by the Command Center routes.
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Set

VERBS = ("view", "create", "edit", "approve", "delete", "export", "manage")
IMPLIED_BY_MANAGE = ("create", "edit", "approve", "delete")

FORBIDDEN = "You do not have permission for this action. Owner/Admin approval is required."

GREEN, ORANGE, RED = "GREEN", "ORANGE", "RED"
RISKS = (GREEN, ORANGE, RED)

# Permissions whose holder can move money, change live integrations,
# change who can do what, or take personal data out of ASKODOX.
RED_PERMISSIONS = {
    "staff:manage", "integrations:manage", "payments:manage", "finance:manage", "config:manage",
    "audit:export", "users:export", "approvals:approve", "selfheal:manage", "security:manage",
}
ORANGE_PERMISSIONS = {
    "users:manage", "revenue:manage", "rewards:manage", "sponsored:manage", "notifications:manage",
    "notifications:approve", "partners:manage", "affiliate:manage", "analytics:export", "support:manage",
    "content:manage", "offers:manage", "growth:manage", "links:manage", "companion:manage", "catalog:manage",
    "requests:manage",
}

# Combinations that remove a separation of duties.
TOXIC_COMBINATIONS: tuple[tuple[frozenset, str], ...] = (
    (frozenset({"payments:manage", "finance:manage"}), "can both take payments and reconcile / pay out the ledger"),
    (frozenset({"affiliate:manage", "finance:manage"}), "can create affiliate links and also record their payouts"),
    (frozenset({"rewards:manage", "finance:manage"}), "can both grant rewards and mark them paid"),
    (frozenset({"sponsored:manage", "revenue:manage"}), "can run ad campaigns and also edit the revenue they report"),
    (frozenset({"integrations:manage", "config:manage"}), "can switch live integrations and every feature flag"),
    (frozenset({"staff:manage", "approvals:approve"}), "can create staff and approve their own staff's requests"),
    (frozenset({"notifications:manage", "users:export"}), "can message users and export their contact data"),
)

# Feature flags: what switching them risks.
FLAG_RISK: Dict[str, str] = {
    "payments.online": RED,
    "payments.subscriptions": RED,
    "rewards": ORANGE,
    "coupons": ORANGE,
    "referrals": ORANGE,
    "offers.merchant": ORANGE,
    "results.sponsored": ORANGE,
    "results.affiliate": ORANGE,
    "support.whatsapp": ORANGE,
    "notifications.push": ORANGE,
    "notifications.email": ORANGE,
    "notifications.sms": ORANGE,
    "notifications.whatsapp": ORANGE,
    "notifications.promotions": ORANGE,
    "ai.assistant": ORANGE,
    "support.escalation": ORANGE,
    "companion.screen_guide": ORANGE,
    "companion.enabled": ORANGE,
    "companion.floating_bubble": ORANGE,
    "companion.accessibility": ORANGE,
    "companion.privacy_shield": RED,
    "selfheal.enabled": ORANGE,
    "selfheal.green_auto": ORANGE,
}


def flag_risk(key: str) -> str:
    return FLAG_RISK.get(key, GREEN)


def all_permissions(legacy: Iterable[str], modules: Iterable[str]) -> tuple[str, ...]:
    """Legacy permissions first (stable order), then every module:verb."""
    out: List[str] = list(dict.fromkeys(legacy))
    for module in modules:
        for verb in VERBS:
            p = f"{module}:{verb}"
            if p not in out:
                out.append(p)
    return tuple(out)


def has_permission(held: Iterable[str], permission: str) -> bool:
    held = set(held)
    if permission in held:
        return True
    module, _, verb = permission.partition(":")
    return verb in IMPLIED_BY_MANAGE and f"{module}:manage" in held


def is_super(principal: Dict[str, Any]) -> bool:
    return principal.get("role") == "super_admin" or principal.get("id") == "owner"


def permission_risk(permission: str) -> str:
    if permission in RED_PERMISSIONS:
        return RED
    if permission in ORANGE_PERMISSIONS:
        return ORANGE
    return GREEN


def advise(before: Iterable[str], after: Iterable[str], *, role: str = "") -> Dict[str, Any]:
    """Permission Safety Advisor: warnings for a proposed permission set."""
    before, after = set(before), set(after)
    added = sorted(after - before)
    warnings: List[Dict[str, str]] = []
    red = [p for p in added if permission_risk(p) == RED]
    orange = [p for p in added if permission_risk(p) == ORANGE]
    for p in red:
        warnings.append({"level": RED, "permission": p,
                         "message": f"{p} is high-risk: only the Owner / Super Admin should grant it."})
    for p in orange:
        warnings.append({"level": ORANGE, "permission": p,
                         "message": f"{p} changes live customer-facing data; grant only to staff who need it."})
    for combo, why in TOXIC_COMBINATIONS:
        if combo <= after and not combo <= before:
            warnings.append({"level": RED, "permission": " + ".join(sorted(combo)),
                             "message": f"Separation of duties: one person {why}."})
    exports = [p for p in added if p.endswith(":export")]
    if exports:
        warnings.append({"level": ORANGE, "permission": ", ".join(exports),
                         "message": "Export takes data out of ASKODOX; personal data stays masked, but the file can "
                                    "be shared. Grant it only for a reason."})
    if role and role != "super_admin" and len(after) > 60:
        warnings.append({"level": ORANGE, "permission": "*",
                         "message": f"{len(after)} permissions is close to full access for a '{role}' role."})
    level = RED if any(w["level"] == RED for w in warnings) else ORANGE if warnings else GREEN
    return {"risk": level, "added": added, "removed": sorted(before - after), "warnings": warnings}


# ------------------------------------------------------------- redaction --

_SECRET_KEY = re.compile(r"(secret|password|passwd|token|api_?key|private|credential|authorization|otp|cvv|"
                         r"upi_?pin|mpin|signature|cookie)", re.IGNORECASE)
_SECRET_VALUE = re.compile(r"(stf_[A-Za-z0-9_\-]{8,}|sk_(live|test)_[A-Za-z0-9]{8,}|rzp_(live|test)_[A-Za-z0-9]{6,}|"
                           r"AIza[0-9A-Za-z_\-]{20,}|Bearer\s+[A-Za-z0-9._\-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)")
REDACTED = "[redacted]"


def redact(value: Any, _depth: int = 0) -> Any:
    """Recursively hide secret-looking keys and values (audit, approvals,
    self-healing logs never store a secret)."""
    if _depth > 8:
        return REDACTED
    if isinstance(value, dict):
        return {k: (REDACTED if isinstance(k, str) and _SECRET_KEY.search(k) and v not in (None, "", [], {})
                    and not isinstance(v, bool) else redact(v, _depth + 1)) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [redact(v, _depth + 1) for v in value]
    if isinstance(value, str):
        return _SECRET_VALUE.sub(REDACTED, value)
    return value


def modules_of(permissions: Iterable[str]) -> Set[str]:
    return {p.split(":", 1)[0] for p in permissions}
