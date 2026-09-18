from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable


@dataclass
class AffiliateProviderConfig:
    """Extensible affiliate registry supporting multiple providers and empty slots."""

    providers: dict[str, dict[str, Any]] = field(default_factory=dict)

    def register(self, provider_id: str, **metadata: Any) -> None:
        payload = {
            "provider_id": provider_id,
            "category": str(metadata.get("category") or "general").strip().lower(),
            "route": str(metadata.get("route") or "affiliate").strip().lower(),
            "active": bool(metadata.get("active", True)),
        }
        payload.update(metadata)
        self.providers[provider_id] = payload

    def active_for_category(self, category: str) -> list[dict[str, Any]]:
        wanted = str(category or "").strip().lower()
        matches = []
        for provider in self.providers.values():
            if not provider.get("active", True):
                continue
            if wanted and str(provider.get("category") or "").strip().lower() == wanted:
                matches.append(provider)
        return matches

    def empty_slot(self, category: str) -> bool:
        return not bool(self.active_for_category(category))


class ServiceDecisionAssistantService:
    """Service decision assistant for Phase 6."""

    def decide(self, request: dict[str, Any], candidates: Iterable[dict[str, Any]]) -> dict[str, Any]:
        location = str(request.get("location") or "").strip()
        budget = float(request.get("budget") or 0)
        urgency = str(request.get("urgency") or "normal").lower()
        category = str(request.get("category") or "service").lower()

        ranked = []
        for candidate in candidates:
            distance = float(candidate.get("distance_km") or 1000.0)
            price = float(candidate.get("price") or 0)
            score = 0.0
            score += 0.45 if candidate.get("available") else 0.0
            score += 0.20 if candidate.get("verified") else 0.0
            score += 0.15 if distance <= 10 else 0.05
            score += 0.10 if price <= budget or budget == 0 else 0.0
            score += 0.10 if candidate.get("rating", 0) >= 4.5 else 0.02
            if urgency == "urgent":
                score += 0.10 if candidate.get("available") else 0.0
            reason_bits = []
            if candidate.get("location") == location:
                reason_bits.append(f"near {location}")
            if candidate.get("verified"):
                reason_bits.append("verified provider")
            if candidate.get("available"):
                reason_bits.append("available now")
            if price and budget and price <= budget:
                reason_bits.append("fits budget")
            ranked.append({
                "name": str(candidate.get("name") or "Provider"),
                "category": category,
                "price": price,
                "distance_km": distance,
                "match_score": round(min(1.0, max(0.0, score)), 3),
                "why": ", ".join(reason_bits) or "matches the requested service type",
                "verified": bool(candidate.get("verified")),
                "available": bool(candidate.get("available")),
            })

        ranked.sort(key=lambda item: item["match_score"], reverse=True)
        best = ranked[0] if ranked else {"name": "No local service found", "match_score": 0.0, "why": "No suitable provider matched"}
        return {"best": best, "alternatives": ranked[1:4], "decision": "local_best" if best.get("match_score", 0) > 0 else "fallback_required"}


class BuyerDecisionAssistantService:
    """Buyer-side decision assistant for Phase 7."""

    def decide(self, request: dict[str, Any], options: Iterable[dict[str, Any]]) -> dict[str, Any]:
        budget = float(request.get("budget") or 0)
        urgency = str(request.get("urgency") or "normal").lower()
        must_have = {str(item).lower() for item in request.get("must_have") or []}

        ranked = []
        for option in options:
            price = float(option.get("price") or 0)
            score = 0.0
            score += 0.30 if option.get("verified") else 0.0
            score += 0.20 if option.get("warranty") else 0.0
            score += 0.20 if option.get("returns") else 0.0
            score += 0.15 if option.get("exact_variant") else 0.0
            score += 0.10 if option.get("service_available") else 0.0
            score += 0.10 if option.get("channel") == "local" else 0.0
            if urgency == "urgent":
                score += 0.10 if float(option.get("delivery_minutes") or 100000) <= 120 else 0.0
            if budget and price <= budget:
                score += 0.15
            reason_bits = []
            for key in ("warranty", "returns", "verified", "exact_variant", "service_available"):
                if option.get(key):
                    reason_bits.append(key)
            if option.get("channel") == "local":
                reason_bits.append("local availability")
            ranked.append({
                "name": str(option.get("name") or "Option"),
                "channel": str(option.get("channel") or "local"),
                "price": price,
                "decision_score": round(min(1.0, max(0.0, score)), 3),
                "reasoning": reason_bits or ["best fit for requested category"],
            })

        ranked.sort(key=lambda item: item["decision_score"], reverse=True)
        best = ranked[0] if ranked else {"name": "No match", "decision_score": 0.0, "reasoning": ["no suitable match"]}
        return {"best": best, "alternatives": ranked[1:4], "reasoning": best["reasoning"]}


class PartyAIAssistantOrchestrator:
    """Phase 8 unified orchestration flow for local-first AI assisted transactions."""

    def orchestrate(self, request: dict[str, Any]) -> dict[str, Any]:
        local_matches = request.get("local_matches") or []
        affiliate_matches = request.get("affiliate_matches") or []
        primary = "local_first" if local_matches else "affiliate_fallback"
        steps = [{"kind": "match_local", "summary": "Rank nearby party matches"}] if local_matches else []
        if affiliate_matches:
            steps.append({"kind": "affiliate_fallback", "summary": "Offer online or affiliate alternatives when local fit is insufficient"})
        steps.append({"kind": "confirm_acceptance", "summary": "Ask Party A and Party B to confirm the selected option"})
        return {
            "primary_path": primary,
            "steps": steps,
            "status": "ready_for_party_confirmation",
        }
