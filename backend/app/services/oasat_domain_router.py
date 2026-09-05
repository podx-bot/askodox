"""Universal OASAT domain routing without forcing one answer/action shape."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class OASATDomainPlan:
    domain: str
    intent: str
    stages: tuple[str, ...]
    adapter: str
    required_context: tuple[str, ...]
    skip_stages: tuple[str, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        return {
            "domain": self.domain,
            "intent": self.intent,
            "stages": list(self.stages),
            "adapter": self.adapter,
            "required_context": list(self.required_context),
            "skip_stages": list(self.skip_stages),
        }


class OASATDomainRouter:
    """Deterministic routing shell for the common OASAT reasoning core.

    This router selects a domain-specific adapter and stage plan. It deliberately
    does not generate a single global answer template. A semantic/model router can
    later sit behind the same interface while retaining these guardrails.
    """

    DOMAIN_MARKERS = {
        "DOCUMENTS": ("pdf", "document", "invoice", "bill", "excel", "csv", "file", "డాక్యుమెంట్", "బిల్"),
        "JOBS": ("job", "vacancy", "employer", "resume", "cv", "ఉద్యోగ", "జాబ్"),
        "APPOINTMENTS": ("doctor", "appointment", "clinic", "hospital", "డాక్టర్", "అపాయింట్మెంట్"),
        "RIDES": ("ride", "taxi", "cab", "driver", "pickup", "drop", "రైడ్", "డ్రైవర్"),
        "FOOD": ("restaurant", "food", "meal", "chicken", "mutton", "groceries", "rice", "ఫుడ్", "చికెన్", "మటన్"),
        "RESEARCH": ("research", "compare information", "latest", "web", "news", "రీసెర్చ్", "లేటెస్ట్"),
        "REMINDERS": ("remind", "reminder", "notify me", "alert me", "రిమైండ్", "గుర్తు చేయ"),
        "SERVICES": ("repair", "service provider", "plumber", "electrician", "mechanic", "రిపేర్", "సర్వీస్"),
        "COMMERCE": ("buy", "seller", "shop", "price", "rate", "కొనాలి", "సెల్లర్", "ధర", "రేట్"),
    }

    PLANS = {
        "DOCUMENTS": OASATDomainPlan("DOCUMENTS", "UNDERSTAND_FILE", ("SITUATION", "REASONING", "ANSWER"), "documents", ("file_content",), ("MATCHING", "SELLER_COMPARISON")),
        "JOBS": OASATDomainPlan("JOBS", "MATCH_JOB", ("SITUATION", "REQUIREMENTS", "REASONING", "MATCHING", "APPROVAL", "ACTION"), "jobs", ("skills", "experience", "location")),
        "APPOINTMENTS": OASATDomainPlan("APPOINTMENTS", "BOOK_APPOINTMENT", ("SITUATION", "REQUIREMENTS", "REASONING", "MATCHING", "APPROVAL", "ACTION"), "appointments", ("specialty", "urgency", "location", "availability")),
        "RIDES": OASATDomainPlan("RIDES", "MATCH_RIDE", ("SITUATION", "REQUIREMENTS", "MATCHING", "APPROVAL", "ACTION"), "rides", ("pickup", "drop", "time")),
        "FOOD": OASATDomainPlan("FOOD", "SOLVE_FOOD_NEED", ("SITUATION", "REQUIREMENTS", "REASONING", "SUGGESTIONS", "COMPARISON", "APPROVAL", "ACTION"), "food", ("quantity_or_people", "timing", "preferences")),
        "RESEARCH": OASATDomainPlan("RESEARCH", "RESEARCH_AND_SYNTHESIZE", ("SITUATION", "REQUIREMENTS", "REASONING", "RESEARCH", "ANSWER"), "research", ("topic", "scope"), ("SELLER_COMPARISON",)),
        "REMINDERS": OASATDomainPlan("REMINDERS", "SCHEDULE_OR_MONITOR", ("SITUATION", "REQUIREMENTS", "APPROVAL", "ACTION"), "reminders", ("task", "timing")),
        "SERVICES": OASATDomainPlan("SERVICES", "MATCH_SERVICE", ("SITUATION", "REQUIREMENTS", "REASONING", "MATCHING", "COMPARISON", "APPROVAL", "ACTION"), "services", ("problem", "location", "timing")),
        "COMMERCE": OASATDomainPlan("COMMERCE", "BUY_OR_COMPARE", ("SITUATION", "REQUIREMENTS", "REASONING", "SUGGESTIONS", "COMPARISON", "MATCHING", "APPROVAL", "ACTION"), "commerce", ("item", "quantity", "budget_or_price")),
        "GENERAL": OASATDomainPlan("GENERAL", "ASSIST", ("SITUATION", "REASONING", "ANSWER"), "general", ("goal",)),
    }

    def route(self, message: str, context: dict[str, Any] | None = None) -> dict[str, Any]:
        text = " ".join(str(message or "").strip().split()).casefold()
        context = context or {}
        explicit_domain = str(context.get("domain") or "").strip().upper()
        if explicit_domain in self.PLANS:
            plan = self.PLANS[explicit_domain]
        else:
            plan = self.PLANS[self._detect_domain(text)]
        result = plan.as_dict()
        result["rule"] = "Use the common OASAT core, but ask/recommend/act only according to this domain plan."
        return result

    def _detect_domain(self, text: str) -> str:
        for domain, markers in self.DOMAIN_MARKERS.items():
            if any(marker in text for marker in markers):
                return domain
        return "GENERAL"
