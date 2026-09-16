"""Round 9 (roadmap Phase 1): the buying guide must appear only for a real
buyer, never for a seller, and only once the AI has actually extracted a
subject to anchor it to.

See app/services/buyer_guide_gate.py's docstring for the finding this
guards against: BuyerIntelligenceService was fully built and tested but
never reachable from the in-app assistant path real users use.

Kept as individual test functions (no @pytest.mark.parametrize) so this file
runs unchanged under this project's minimal pytest-shim as well as under
real pytest -- see docs/ASKODOX_EXECUTION_TRACKER.md's testing notes on
round 8, where a parametrized file could not be run through the shim.
"""
from app.services.buyer_guide_gate import wants_buying_guide


def test_buy_side_product_with_subject_wants_guide():
    assert wants_buying_guide(
        domain="PRODUCT", action="buy_product", message="i want to buy a car", subject="car"
    ) is True


def test_buy_side_food_with_subject_wants_guide():
    assert wants_buying_guide(
        domain="FOOD", action="", message="i need mango pickle", subject="mango pickle"
    ) is True


def test_selling_message_never_gets_buying_guide_even_with_subject():
    assert wants_buying_guide(
        domain="PRODUCT",
        action="",
        message="i want to sell my maruti 800 for 50000",
        subject="maruti 800",
    ) is False


def test_offering_action_hint_blocks_guide_regardless_of_wording():
    assert wants_buying_guide(
        domain="PRODUCT", action="create_listing", message="maruti 800 50000", subject="maruti 800"
    ) is False


def test_requesting_action_hint_allows_guide():
    assert wants_buying_guide(
        domain="PRODUCT", action="buy_product", message="maruti 800 under 50000", subject="maruti 800"
    ) is True


def test_no_subject_means_no_guide_yet():
    assert wants_buying_guide(
        domain="PRODUCT", action="", message="i want to buy a car", subject=None
    ) is False
    assert wants_buying_guide(
        domain="PRODUCT", action="", message="i want to buy a car", subject="  "
    ) is False


def test_non_buying_domain_never_gets_a_buying_guide():
    assert wants_buying_guide(
        domain="STAFFING", action="", message="delivery boy kavali", subject="delivery boy"
    ) is False
    assert wants_buying_guide(
        domain="SERVICE", action="", message="need a plumber", subject="plumber"
    ) is False
    assert wants_buying_guide(
        domain="GENERAL", action="", message="hi", subject=None
    ) is False


def test_telugu_selling_phrase_blocks_guide():
    assert wants_buying_guide(
        domain="PRODUCT", action="", message="naa car ni అమ్మాలి", subject="car"
    ) is False


def test_domain_is_case_insensitive():
    assert wants_buying_guide(
        domain="product", action="", message="i want to buy a car", subject="car"
    ) is True
