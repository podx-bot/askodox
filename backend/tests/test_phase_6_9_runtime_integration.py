from app.services.phase_6_9_assistant_service import (
    AffiliateProviderConfig,
    BuyerDecisionAssistantService,
    PartyAIAssistantOrchestrator,
    ServiceDecisionAssistantService,
)
from app.services.universal_aware_conversation_service import UniversalAwareConversationService


class EmptyResponseCommands:
    def process_text(self, sender_mobile, message):
        return None


class EmptyProductRuntime:
    def process(self, sender_mobile, message):
        return None


class Catalog:
    def search_active(self, query, limit=10):
        assert query == "washing machine"
        return [
            {
                "subject": "Washing machine",
                "seller_name": "Vijayawada Appliance Store",
                "price": 22000,
                "delivery_available": 1,
                "variant": "7kg front load",
                "id_verification_status": "VERIFIED",
            }
        ]


class EmptyCatalog:
    def search_active(self, query, limit=10):
        return []


class BaseConversation:
    def process(self, sender_mobile, message):
        return "fallback"


def service(request, *, profile_source=None, catalog_repository=None, affiliates=None):
    config = AffiliateProviderConfig()
    for provider_id, metadata in affiliates or []:
        config.register(provider_id, **metadata)
    return UniversalAwareConversationService(
        response_commands=EmptyResponseCommands(),
        base_conversation=BaseConversation(),
        product_runtime=EmptyProductRuntime(),
        service_decision_assistant=ServiceDecisionAssistantService(),
        buyer_decision_assistant=BuyerDecisionAssistantService(),
        affiliate_provider_config=config,
        party_ai_orchestrator=PartyAIAssistantOrchestrator(),
        profile_source=profile_source,
        catalog_repository=catalog_repository,
    )


def test_service_request_uses_registered_provider_and_requires_party_confirmation():
    conversation = service(
        "service",
        profile_source=lambda: [
            {
                "user_id": "provider-1",
                "name": "Vijayawada Plumbing Co",
                "role": "SERVICE_PROVIDER",
                "category": "plumbing",
                "location": "Vijayawada",
                "available": True,
                "rating": 4.9,
            }
        ],
    )

    reply = conversation.process("buyer-1", "Need a plumber near Vijayawada")

    assert "Vijayawada Plumbing Co" in reply
    assert "Both parties confirm before contact sharing" in reply
    assert "Local service provider" not in reply


def test_buyer_request_uses_real_catalog_listing_and_party_confirmation():
    conversation = service("buyer", catalog_repository=Catalog())

    reply = conversation.process("buyer-1", "Compare the best washing machine")

    assert "Vijayawada Appliance Store" in reply
    assert "Both parties confirm before contact sharing" in reply
    assert "Local stock option" not in reply


def test_affiliate_registry_is_carried_into_orchestration_without_replacing_local_choice():
    conversation = service(
        "buyer",
        catalog_repository=Catalog(),
        affiliates=[("amazon", {"category": "washing machine", "route": "affiliate"})],
    )

    reply = conversation.process("buyer-1", "Compare the best washing machine")

    assert "verified external options" in reply
    assert "Vijayawada Appliance Store" in reply


def test_buyer_no_local_match_uses_affiliate_fallback_with_consent_gate():
    conversation = service(
        "buyer",
        catalog_repository=EmptyCatalog(),
        affiliates=[("amazon", {"category": "washing machine", "route": "affiliate"})],
    )

    reply = conversation.process("buyer-1", "Compare the best washing machine")

    assert "No confirmed local match" in reply
    assert "amazon" in reply
    assert "both parties confirm" in reply


def test_universal_ai_connect_route_returns_flutter_decision_contract():
    from fastapi.testclient import TestClient
    from server import app, container

    class FakeUniversalAI:
        def decide(self, message, *, history, locale, location):
            return {
                "reply": "I understand your local buying request.",
                "domain": "PRODUCT",
                "transactional": True,
                "action": "buy_product",
                "confidence": 0.95,
                "entities": {"subject": "washing machine", "location": location},
            }

    previous = container.universal_ai_assistant_service
    container.universal_ai_assistant_service = FakeUniversalAI()
    try:
        client = TestClient(app)
        response = client.post(
            "/api/in-app/assistant",
            json={
                "message": "I need a washing machine nearby",
                "locale": "en",
                "location": "Vijayawada",
                "history": [],
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["source"] == "universal_ai"
        assert body["domain"] == "PRODUCT"
        assert body["transactional"] is True
        assert body["entities"]["subject"] == "washing machine"
    finally:
        container.universal_ai_assistant_service = previous
