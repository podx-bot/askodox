from app.services.active_deal_context_resolver import ActiveDealContextResolver


def test_same_context_accepts_same_side_domain_subject_across_case_and_punctuation():
    active = {"side": "NEED", "domain": "PRODUCT", "subject": "Chicken Boneless"}
    incoming = {"side": "need", "domain": "product", "subject": " chicken boneless! "}
    assert ActiveDealContextResolver.same_context(active, incoming) is True


def test_same_context_rejects_different_subject():
    active = {"side": "NEED", "domain": "PRODUCT", "subject": "chicken"}
    incoming = {"side": "NEED", "domain": "PRODUCT", "subject": "mutton"}
    assert ActiveDealContextResolver.same_context(active, incoming) is False


def test_same_context_rejects_side_or_domain_change():
    active = {"side": "NEED", "domain": "PRODUCT", "subject": "chicken"}
    assert ActiveDealContextResolver.same_context(
        active, {"side": "OFFER", "domain": "PRODUCT", "subject": "chicken"}
    ) is False
    assert ActiveDealContextResolver.same_context(
        active, {"side": "NEED", "domain": "SERVICE", "subject": "chicken"}
    ) is False


def test_merge_fields_preserves_known_values_and_merges_constraints():
    active = {
        "quantity": 10,
        "unit": "kg",
        "location_text": "Vijayawada",
        "constraints": {"quality": "fresh", "variant": "with bone"},
    }
    incoming = {
        "quantity": 12,
        "unit": "kg",
        "location_text": "",
        "constraints": {"variant": "boneless"},
        "source": "image",
        "media_ref": "img-1",
    }
    merged = ActiveDealContextResolver.merge_fields(active, incoming)
    assert merged["quantity"] == 12
    assert "location_text" not in merged
    assert merged["constraints"] == {"quality": "fresh", "variant": "boneless"}
    assert merged["source"] == "image"
    assert merged["media_ref"] == "img-1"
