"""Missing-only durable role profile planning for PODX.

This module separates durable profile essentials from request/listing/deal fields.
It never asks users to pre-fill every possible role. Instead it exposes the next
missing durable fields for the role inferred from real intent.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RoleProfilePlan:
    capability: str
    missing_fields: tuple[str, ...]
    complete: bool


class ProgressiveRoleProfileEssentialsService:
    """Compute only durable profile fields that are actually missing.

    Buyer, seller, service-customer, service-provider and employer transaction
    details are intentionally left to their vertical request/listing flows. The
    current shared user schema has durable worker fields, so those are planned
    here without forcing re-entry when already saved.
    """

    DURABLE_FIELDS = {
        "BUYER": (),
        "SELLER": (),
        "SERVICE_CUSTOMER": (),
        "SERVICE_PROVIDER": (),
        "WORKER": ("job_category", "experience", "availability", "location"),
        "EMPLOYER": (),
        "DELIVERY_PARTNER": (),
        "DELIVERY_CUSTOMER": (),
    }

    GUIDANCE = {
        "SELLER": "Optional: add products, prices, availability and location so relevant local demand can reach you.",
        "SERVICE_PROVIDER": "Optional: add services, area, timings and quote preferences so nearby requests can reach you.",
        "WORKER": "Optional: add skills, experience, availability and location so suitable opportunities can reach you.",
        "EMPLOYER": "Optional: add the roles, location and schedule you hire for so suitable workers can find your request.",
        "DELIVERY_PARTNER": "Optional: add service area, vehicle and availability so relevant delivery requests can reach you.",
        "BUYER": "Optional: save preferences and location to improve future recommendations.",
        "SERVICE_CUSTOMER": "Optional: save location and service preferences to improve future provider matches.",
        "DELIVERY_CUSTOMER": "Optional: save common pickup/drop areas and timing preferences for faster delivery requests.",
    }

    def __init__(self, user_repository) -> None:
        self.user_repository = user_repository

    def plan_for_user(self, sender_mobile: str, capability: str) -> RoleProfilePlan:
        role = str(capability or "").upper()
        required = self.DURABLE_FIELDS.get(role, ())
        if not required:
            return RoleProfilePlan(role, (), True)

        try:
            user = self.user_repository.find_by_whatsapp_mobile(sender_mobile) or {}
        except Exception:
            user = {}

        missing = tuple(field for field in required if self._missing(user, field))
        return RoleProfilePlan(role, missing, not missing)

    @classmethod
    def guidance_for(cls, capability: str) -> str:
        return cls.GUIDANCE.get(str(capability or "").upper(), "Optional: add relevant preferences to improve future ASKODOX matches.")

    @staticmethod
    def _missing(user: dict, field: str) -> bool:
        if field == "location":
            return user.get("latitude") is None or user.get("longitude") is None
        value = user.get(field)
        if value is None:
            return True
        if isinstance(value, str) and not value.strip():
            return True
        return False
