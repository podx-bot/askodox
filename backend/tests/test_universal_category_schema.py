from app.services.universal_category_schema import UniversalCategorySchemaRegistry


def test_all_required_cross_category_schemas_are_registered():
    categories = {schema.category for schema in UniversalCategorySchemaRegistry.all()}
    assert categories >= {
        "COMMERCE", "SERVICES", "JOBS", "DELIVERY", "APPOINTMENT",
        "PROPERTY", "FOOD", "MOBILITY",
    }


def test_category_schema_changes_required_fields_and_result_kind():
    service = UniversalCategorySchemaRegistry.resolve("SERVICES")
    job = UniversalCategorySchemaRegistry.resolve("JOBS")
    assert service.result_kind == "service"
    assert job.result_kind == "job"
    assert UniversalCategorySchemaRegistry.missing("DELIVERY", {"from_location": "A"}) == ("to_location",)