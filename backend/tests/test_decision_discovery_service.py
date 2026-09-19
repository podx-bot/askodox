from app.services.decision_discovery_service import DecisionDiscoveryService


def test_ready_to_act_request_does_not_enter_decision_discovery():
    service = DecisionDiscoveryService()
    assert service.question_for("₹15000 Samsung mobile near me") is None


def test_uncertain_request_gets_one_category_relevant_question():
    service = DecisionDiscoveryService()
    question = service.question_for("Which mobile should I buy?")
    assert question is not None
    assert "price" in question.lower()
    assert "service provider" not in question.lower()