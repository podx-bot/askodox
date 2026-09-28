"""Grounded results: nothing invented (availability, reviews, distance),
AI clarification for any category, and no built-in city in probes."""
from app.services.google_maps_service import GoogleMapsService
from app.services.local_live_lead_service import LocalLiveLeadService
from app.services.universal_ai_assistant_service import UniversalAIAssistantService
from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService


def test_seller_reply_availability_is_what_the_seller_said_never_invented():
    said = {
        "Samsung 43, ₹25000, in stock": "in stock (seller said)",
        "₹25,000 available": "in stock (seller said)",
        "స్టాక్ ఉంది": "in stock (seller said)",
        "no stock": "out of stock (seller said)",
        "Out of stock sir": "out of stock (seller said)",
        "stock ledu": "out of stock (seller said)",
        "స్టాక్ లేదు": "out of stock (seller said)",
        "स्टॉक नहीं है": "out of stock (seller said)",
        "LG 43 inch ₹30000": None,  # said nothing about stock -> no claim
    }
    for text, expected in said.items():
        assert LocalLiveLeadService._parse_response(text)["availability"] == expected, text
    assert LocalLiveLeadService._parse_response("LG 43 inch ₹30000")["price"] == 30000


def test_places_rows_never_invent_reviews_or_distance():
    service = UniversalMultiSourceResultService()
    rows = service._places_to_rows(
        [
            {"place_id": "a", "name": "Rated shop", "address": "Main Road, Town, India", "latitude": 16.51,
             "longitude": 80.61, "rating": 4.2, "rating_count": 37},
            {"place_id": "b", "name": "Unrated shop", "address": "Market, Town, India", "latitude": None,
             "longitude": None},
        ],
        16.5, 80.6, 5, 5,
    )
    by_title = {r["title"]: r for r in rows}
    assert by_title["Rated shop"]["review_count"] == 37
    assert by_title["Unrated shop"]["review_count"] is None, "unknown stays unknown, not '0 reviews'"
    assert by_title["Unrated shop"]["rating_average"] is None
    assert by_title["Unrated shop"]["distance_km"] is None, "no coordinates -> no distance claimed"
    assert by_title["Unrated shop"]["availability"] is None, "open/available only when Google says so"
    assert all(r.get("price") in (None, "") for r in rows), "a place row never carries an invented price"


def test_ai_clarification_options_survive_for_any_category():
    cleaned = UniversalAIAssistantService._clean_entities(
        {"subject": "amplifier", "clarify_options": ["guitar amplifier", "car audio amplifier"], "made_up": "x"}
    )
    assert cleaned["clarify_options"] == ["guitar amplifier", "car audio amplifier"]
    assert "made_up" not in cleaned


def test_maps_status_probe_assumes_no_city():
    import inspect

    defaults = inspect.signature(GoogleMapsService.api_status).parameters
    assert (defaults["latitude"].default, defaults["longitude"].default) != (16.5062, 80.6480)
