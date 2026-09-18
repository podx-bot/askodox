from app.repositories.category_intelligence_repository import CategoryIntelligenceRepository
from app.services.seller_listing_assistant import SellerListingAssistant


def assistant(tmp_path):
    return SellerListingAssistant(CategoryIntelligenceRepository(str(tmp_path / "test.db")))


def test_single_message_builds_listing_draft(tmp_path):
    draft = assistant(tmp_path).draft("I sell mango pickle ₹250/kg")
    assert draft["subject"] == "mango pickle"
    assert draft["price"] == 250
    assert draft["unit"] == "kg"
    assert draft["ready_to_confirm"] is True


def test_telugu_seller_message_is_supported(tmp_path):
    draft = assistant(tmp_path).draft("నేను rice అమ్ముతాను ₹60/kg")
    assert draft["subject"].lower() == "rice"
    assert draft["price"] == 60
    assert draft["unit"] == "kg"


def test_product_model_number_is_not_misread_as_price(tmp_path):
    draft = assistant(tmp_path).draft("I sell iPhone 15")
    assert draft["subject"] == "iPhone 15"
    assert draft["price"] is None
    assert draft["missing_fields"] == ["price"]


def test_explicit_plain_price_word_is_supported(tmp_path):
    draft = assistant(tmp_path).draft("I sell iPhone 15 price 50000")
    assert draft["subject"] == "iPhone 15"
    assert draft["price"] == 50000


def test_missing_price_is_clarification_not_blocker(tmp_path):
    draft = assistant(tmp_path).draft("I sell mobile accessories")
    assert draft["subject"] == "mobile accessories"
    assert draft["missing_fields"] == ["price"]
    assert "Price later" in assistant(tmp_path).confirmation(draft)
