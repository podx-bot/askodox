from app.services.party_conversation_answer_service import PartyConversationAnswerService


def test_answers_from_trusted_party_b_data_without_guessing():
    service = PartyConversationAnswerService()

    result = service.answer(
        "Final price entha?",
        trusted_party_b_data={"price": 296},
        trusted_deal_data={"price": 310},
    )

    assert result.status == "ANSWERED_FROM_TRUSTED_DATA"
    assert result.field == "price"
    assert result.answer == "296"
    assert result.requires_party_b_confirmation is False


def test_missing_known_fact_requires_party_b_confirmation():
    service = PartyConversationAnswerService()

    result = service.answer(
        "Warranty unda?",
        trusted_party_b_data={"price": 296},
    )

    assert result.status == "PARTY_B_CONFIRMATION_REQUIRED"
    assert result.field == "warranty"
    assert result.answer is None
    assert result.requires_party_b_confirmation is True


def test_open_natural_question_is_not_restricted_to_canned_list():
    service = PartyConversationAnswerService()

    result = service.answer(
        "Can you make this in a custom finish for my shop?",
        trusted_party_b_data={"dynamic_fields": {"customization": "Custom finish available"}},
    )

    assert result.status == "ANSWERED_FROM_TRUSTED_DATA"
    assert result.field == "customization"
    assert result.answer == "Custom finish available"


def test_unknown_open_question_routes_to_party_b_instead_of_inventing_answer():
    service = PartyConversationAnswerService()

    result = service.answer(
        "Can this be prepared without the ingredient I mentioned?",
        trusted_party_b_data={},
        trusted_deal_data={},
    )

    assert result.status == "PARTY_B_CONFIRMATION_REQUIRED"
    assert result.answer is None
    assert result.requires_party_b_confirmation is True


def test_service_has_no_buyer_seller_role_requirement():
    service = PartyConversationAnswerService()

    result = service.answer(
        "What time can you arrive?",
        trusted_party_b_data={"timing": "6 PM"},
    )

    assert result.status == "ANSWERED_FROM_TRUSTED_DATA"
    assert result.field == "timing"
    assert result.answer == "6 PM"
