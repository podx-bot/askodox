"""Extensible category schema metadata for universal ASKODOX flows."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class CategorySchema:
    category: str
    required_fields: tuple[str, ...]
    optional_fields: tuple[str, ...]
    result_kind: str
    seeker_capability: str
    provider_capability: str
    decision_focus: tuple[str, ...]


class UniversalCategorySchemaRegistry:
    """One reusable metadata contract shared by readiness and decision discovery."""

    _SCHEMAS = {
        "COMMERCE": CategorySchema(
            "COMMERCE", ("subject",), ("budget", "brand", "variant", "location", "fulfilment"),
            "product", "BUYER", "SELLER", ("price", "quality", "availability", "value"),
        ),
        "SERVICES": CategorySchema(
            "SERVICES", ("subject", "location"), ("timing", "urgency", "budget"),
            "service", "SERVICE_CUSTOMER", "SERVICE_PROVIDER", ("availability", "price", "experience"),
        ),
        "JOBS": CategorySchema(
            "JOBS", ("subject",), ("location", "experience", "availability", "salary"),
            "job", "WORKER", "EMPLOYER", ("role", "location", "schedule", "pay"),
        ),
        "DELIVERY": CategorySchema(
            "DELIVERY", ("from_location", "to_location"), ("item_type", "timing", "vehicle"),
            "delivery", "DELIVERY_CUSTOMER", "DELIVERY_PARTNER", ("speed", "price", "capacity"),
        ),
        "APPOINTMENT": CategorySchema(
            "APPOINTMENT", ("subject", "location", "timing"), ("speciality", "budget"),
            "appointment", "SERVICE_CUSTOMER", "SERVICE_PROVIDER", ("timing", "availability", "experience"),
        ),
        "PROPERTY": CategorySchema(
            "PROPERTY", ("subject", "location"), ("budget", "timing", "size"),
            "property", "BUYER", "SELLER", ("location", "price", "size"),
        ),
        "FOOD": CategorySchema(
            "FOOD", ("subject",), ("quantity", "timing", "location", "fulfilment"),
            "food", "BUYER", "SELLER", ("freshness", "price", "delivery"),
        ),
        "MOBILITY": CategorySchema(
            "MOBILITY", ("from_location", "to_location"), ("timing", "seats", "budget"),
            "mobility", "SERVICE_CUSTOMER", "SERVICE_PROVIDER", ("speed", "price", "seats"),
        ),
    }

    _ALIASES = {
        "PRODUCT": "COMMERCE",
        "PRODUCTS": "COMMERCE",
        "SERVICE": "SERVICES",
        "JOB": "JOBS",
        "WORK": "JOBS",
        "RIDE": "MOBILITY",
        "TAXI": "MOBILITY",
    }

    @classmethod
    def resolve(cls, category: str | None) -> CategorySchema:
        key = cls.normalize(category)
        return cls._SCHEMAS.get(key, CategorySchema(
            key or "GENERAL", ("subject",), ("location", "timing"),
            "general", "BUYER", "SELLER", ("fit", "availability", "value"),
        ))

    @classmethod
    def normalize(cls, category: str | None) -> str:
        key = str(category or "").strip().upper()
        return cls._ALIASES.get(key, key)

    @classmethod
    def all(cls) -> tuple[CategorySchema, ...]:
        return tuple(cls._SCHEMAS.values())

    @classmethod
    def missing(cls, category: str | None, state: dict) -> tuple[str, ...]:
        schema = cls.resolve(category)
        return tuple(field for field in schema.required_fields if not cls._present(state.get(field)))

    @staticmethod
    def _present(value) -> bool:
        if value is None:
            return False
        if isinstance(value, str):
            return bool(value.strip())
        if isinstance(value, (list, tuple, dict, set)):
            return bool(value)
        return True
