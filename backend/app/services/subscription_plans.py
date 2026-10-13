"""Base subscription plans (Free / Plus / Pro), owner proposal 2026-10:
Free Rs 0, Plus Rs 499 / 30 days, Pro Rs 999 / 30 days with a 7-day trial.

Seeded ONCE into ``growth_plans`` (staff edit them in Growth -> Plans; an edit
is never overwritten). Free is active (it costs nothing); Plus and Pro are
stored INACTIVE until the Owner approves live pricing -- the app shows them as
"not available yet" and ``/api/subscriptions`` refuses inactive plans. No
payment gateway exists, so an activated paid plan without a trial still waits
in PENDING_PAYMENT (growth_repository.subscribe). Entitlements stay empty
until the Owner decides what each tier unlocks (nothing is invented)."""
from __future__ import annotations

from typing import Any, Dict, List

BASE_AUDIENCE = "base"  # its own audience: never mixed into seller / customer plan lists
BASE_PLANS: List[Dict[str, Any]] = [
    {"code": "free", "name": "Free", "price": 0, "period_days": 30, "trial_days": 0, "active": True},
    {"code": "plus", "name": "Plus", "price": 499, "period_days": 30, "trial_days": 0, "active": False},
    {"code": "pro", "name": "Pro", "price": 999, "period_days": 30, "trial_days": 7, "active": False},
]


def seed(growth: Any) -> None:
    for plan in BASE_PLANS:
        if growth.plan(plan["code"]) is None:
            growth.upsert_plan(plan["code"], name=plan["name"], audience=BASE_AUDIENCE, price=plan["price"],
                               period_days=plan["period_days"], trial_days=plan["trial_days"],
                               entitlements={}, active=plan["active"])


def catalogue(growth: Any) -> List[Dict[str, Any]]:
    """Every base plan (add-ons excluded), active or not, with ``available``."""
    return [{"code": p["code"], "name": p["name"], "price": p["price"], "period_days": p["period_days"],
             "trial_days": p["trial_days"], "available": bool(p["active"]),
             "entitlements": p.get("entitlements") or {}}
            for p in growth.plans() if p.get("audience") == BASE_AUDIENCE]
