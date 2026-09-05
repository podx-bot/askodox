"""Domain-specific reasoning contracts for the universal ASKODOX OASAT core.

The common OASAT core chooses a domain. This layer describes what that domain
must reason about and which actions are allowed; it intentionally avoids one
answer/question template for every category.
"""
from __future__ import annotations

from typing import Any


class OASATDomainReasoningService:
    CONTRACTS: dict[str, dict[str, Any]] = {
        "DOCUMENTS": {
            "questions": ("document_goal",),
            "reason_about": ("file_content", "requested_output", "evidence"),
            "actions": ("explain", "extract", "summarize", "compare_document_data"),
            "never_force": ("seller_matching", "price_comparison"),
        },
        "JOBS": {
            "questions": ("skills", "experience", "location", "work_preference"),
            "reason_about": ("role_fit", "eligibility", "distance", "salary_or_terms"),
            "actions": ("match_jobs", "compare_roles", "prepare_application", "request_approval"),
        },
        "APPOINTMENTS": {
            "questions": ("specialty_or_need", "urgency", "location", "availability"),
            "reason_about": ("appropriate_provider", "urgency", "distance", "available_slots"),
            "actions": ("match_provider", "compare_slots", "book_after_approval"),
        },
        "RIDES": {
            "questions": ("pickup", "drop", "time", "passengers_or_load"),
            "reason_about": ("route", "availability", "fit", "price_or_terms"),
            "actions": ("match_ride", "compare_options", "confirm_ride"),
        },
        "FOOD": {
            "questions": ("people_or_quantity", "meal_timing", "preferences", "budget_if_relevant"),
            "reason_about": ("quantity", "menu_or_item_fit", "freshness", "price", "distance", "delivery"),
            "actions": ("suggest_food_plan", "compare_sources", "match_provider", "order_after_approval"),
        },
        "SERVICES": {
            "questions": ("problem", "location", "timing", "constraints"),
            "reason_about": ("service_skill_fit", "urgency", "distance", "trust", "quote"),
            "actions": ("match_service_provider", "compare_quotes", "book_after_approval"),
        },
        "COMMERCE": {
            "questions": ("item", "quantity", "variant_or_quality", "budget_if_relevant", "timing"),
            "reason_about": ("exact_item_fit", "price", "quality", "seller_trust", "distance", "delivery"),
            "actions": ("compare_offers", "match_seller", "buy_after_approval"),
        },
        "RESEARCH": {
            "questions": ("topic", "scope", "freshness_need"),
            "reason_about": ("source_quality", "evidence", "conflicts", "freshness"),
            "actions": ("research", "compare_evidence", "synthesize"),
            "never_force": ("seller_matching",),
        },
        "REMINDERS": {
            "questions": ("task", "timing_or_condition"),
            "reason_about": ("schedule", "condition", "notification_need"),
            "actions": ("schedule_after_approval", "monitor_condition"),
        },
        "GENERAL": {
            "questions": ("goal",),
            "reason_about": ("user_goal", "context", "safe_next_step"),
            "actions": ("answer", "clarify", "suggest_next_step"),
        },
    }

    def build(self, plan: dict[str, Any], context: dict[str, Any] | None = None) -> dict[str, Any]:
        domain = str(plan.get("domain") or "GENERAL").upper()
        contract = self.CONTRACTS.get(domain, self.CONTRACTS["GENERAL"])
        known = context or {}
        return {
            "domain": domain,
            "adapter": plan.get("adapter", "general"),
            "questions": list(contract.get("questions", ())),
            "reason_about": list(contract.get("reason_about", ())),
            "allowed_actions": list(contract.get("actions", ())),
            "never_force": list(contract.get("never_force", ())),
            "known_context_keys": sorted(k for k, v in known.items() if v not in (None, "", [], {})),
            "rule": "Reason and act according to this domain contract; do not reuse another domain's answer/action shape.",
        }
