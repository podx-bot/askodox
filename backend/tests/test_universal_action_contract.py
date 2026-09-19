from app.services.universal_action_contract import actions_for, build_action_result, normalize_lifecycle_result
from app.services.universal_category_schema import UniversalCategorySchemaRegistry


def test_category_aliases_normalize_to_shared_schema():
    assert UniversalCategorySchemaRegistry.resolve("PRODUCT").category == "COMMERCE"
    assert UniversalCategorySchemaRegistry.resolve("SERVICE").category == "SERVICES"
    assert UniversalCategorySchemaRegistry.resolve("JOB").category == "JOBS"
    assert UniversalCategorySchemaRegistry.resolve("RIDE").category == "MOBILITY"


def test_action_result_preserves_raw_status_and_category_actions():
    result = build_action_result(
        raw_status="IN_APP_WAITING_SELLER_CONFIRM",
        request_id=42,
        category="SERVICE",
        side="NEED",
        channel="in_app",
        consent={"required": True, "state": "PENDING"},
    )
    data = result.to_dict()
    assert data["raw_status"] == "IN_APP_WAITING_SELLER_CONFIRM"
    assert data["category"] == "SERVICES"
    assert data["result_kind"] == "service"
    assert data["next_actions"][0]["requires_consent"] is True


def test_completed_and_unknown_states_do_not_expose_unsafe_actions():
    assert actions_for("PRODUCT", "NEED", "CONVERTED") == ()
    result = build_action_result(raw_status="UNKNOWN", category="future_category")
    assert result.result_kind == "general"


def test_category_action_catalog_is_specific_for_each_supported_family():
    expected = {
        "COMMERCE": "ask_seller",
        "SERVICES": "request_quote",
        "JOBS": "apply",
        "DELIVERY": "request_delivery",
        "APPOINTMENT": "request_slot",
        "PROPERTY": "schedule_viewing",
        "FOOD": "place_food_request",
        "MOBILITY": "request_ride",
    }
    for category, action_id in expected.items():
        actions = actions_for(category, "NEED", "ACTIVE")
        assert actions[0].id == action_id


def test_lifecycle_adapter_preserves_legacy_status_and_adds_envelope():
    normalized = normalize_lifecycle_result(
        {"id": 9, "domain": "SERVICE", "side": "NEED"},
        {"status": "IN_APP_WAITING_SELLER_CONFIRM", "request_id": 9, "channel": "in_app"},
    )
    assert normalized["status"] == "IN_APP_WAITING_SELLER_CONFIRM"
    assert normalized["action_result"]["result_kind"] == "service"
    assert normalized["action_result"]["raw_status"] == "IN_APP_WAITING_SELLER_CONFIRM"
