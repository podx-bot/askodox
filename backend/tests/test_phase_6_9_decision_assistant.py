from app.services.phase_6_9_assistant_service import (
    AffiliateProviderConfig,
    BuyerDecisionAssistantService,
    PartyAIAssistantOrchestrator,
    ServiceDecisionAssistantService,
)


SERVICE_PROVIDERS = [
    {
        "name": "Vijayawada Plumbing Co",
        "category": "plumbing",
        "service_type": "repair",
        "location": "Vijayawada",
        "distance_km": 3.0,
        "price": 1200,
        "budget_ok": True,
        "verified": True,
        "rating": 4.9,
        "available": True,
        "specialist": "water heater",
    },
    {
        "name": "City Fixers",
        "category": "plumbing",
        "service_type": "repair",
        "location": "Guntur",
        "distance_km": 28.0,
        "price": 1400,
        "budget_ok": True,
        "verified": False,
        "rating": 4.4,
        "available": True,
        "specialist": "pipeline",
    },
]

BUYING_OPTIONS = [
    {
        "name": "Local appliance store",
        "category": "washing machine",
        "channel": "local",
        "price": 22000,
        "verified": True,
        "delivery_minutes": 60,
        "warranty": True,
        "returns": True,
        "exact_variant": True,
        "service_available": True,
    },
    {
        "name": "Metro online retailer",
        "category": "washing machine",
        "channel": "online",
        "price": 21500,
        "verified": True,
        "delivery_minutes": 240,
        "warranty": True,
        "returns": True,
        "exact_variant": True,
        "service_available": False,
    },
]


def test_service_decision_assistant_prioritizes_local_matching_provider():
    service = ServiceDecisionAssistantService()

    decision = service.decide(
        {
            "request": "Need a plumber for water heater repair near Vijayawada",
            "category": "plumbing",
            "budget": 2000,
            "location": "Vijayawada",
            "urgency": "urgent",
        },
        SERVICE_PROVIDERS,
    )

    assert decision["best"]["name"] == "Vijayawada Plumbing Co"
    assert "near Vijayawada" in decision["best"]["why"]
    assert decision["best"]["match_score"] >= 0.7


def test_buyer_decision_assistant_prefers_local_fit_over_online_price_only():
    service = BuyerDecisionAssistantService()

    decision = service.decide(
        {
            "category": "washing machine",
            "budget": 25000,
            "location": "Vijayawada",
            "urgency": "urgent",
            "must_have": ["warranty", "delivery"],
        },
        BUYING_OPTIONS,
    )

    assert decision["best"]["name"] == "Local appliance store"
    assert decision["best"]["channel"] == "local"
    assert "warranty" in decision["reasoning"][0].lower()


def test_affiliate_provider_registry_supports_multiple_providers_and_empty_slots():
    registry = AffiliateProviderConfig()
    registry.register("amazon", category="washing machine", route="affiliate")
    registry.register("flipkart", category="washing machine", route="affiliate")
    registry.register("local-market", category="plumbing", route="local")

    providers = registry.active_for_category("washing machine")
    assert len(providers) == 2
    assert registry.empty_slot("electronics") is True
    assert registry.empty_slot("washing machine") is False


def test_party_ai_orchestrator_builds_local_then_fallback_steps():
    orchestrator = PartyAIAssistantOrchestrator()
    flow = orchestrator.orchestrate(
        {
            "intent": "buy",
            "category": "washing machine",
            "location": "Vijayawada",
            "local_matches": [{"name": "Local appliance store"}],
            "affiliate_matches": [{"name": "Amazon"}],
        }
    )

    assert flow["primary_path"] == "local_first"
    assert flow["steps"][0]["kind"] == "match_local"
    assert any(step["kind"] == "affiliate_fallback" for step in flow["steps"])
