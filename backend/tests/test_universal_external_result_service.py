from app.services.universal_external_result_service import UniversalExternalResultService


def test_normal_destination_is_used_when_no_affiliate_mapping_exists():
    rows = UniversalExternalResultService.resolve(
        category="product",
        subject="laptop",
        providers=[
            {
                "provider_id": "official-store",
                "category": "product",
                "normal_url": "https://official.example/laptops",
            }
        ],
    )

    assert rows[0]["source"] == "online"
    assert rows[0]["destination_url"] == "https://official.example/laptops"
    assert rows[0]["affiliate"] is False


def test_active_affiliate_mapping_resolves_query_template_without_commission_ranking():
    rows = UniversalExternalResultService.resolve(
        category="product",
        subject="blue laptop",
        providers=[
            {
                "provider_id": "partner",
                "category": "product",
                "normal_url": "https://official.example/search",
                "affiliate_url_template": "https://partner.example/search?q={query}",
            }
        ],
    )

    assert rows[0]["destination_url"] == "https://partner.example/search?q=blue+laptop"
    assert rows[0]["affiliate"] is True
    assert rows[0]["disclosure"] == "Affiliate link"


def test_invalid_or_inactive_destinations_are_not_exposed():
    rows = UniversalExternalResultService.resolve(
        category="product",
        subject="phone",
        providers=[
            {"provider_id": "off", "category": "product", "active": False, "normal_url": "https://off.example"},
            {"provider_id": "bad", "category": "product", "normal_url": "javascript:alert(1)"},
        ],
    )

    assert rows == []


def test_mapping_order_is_preserved_for_relevance():
    rows = UniversalExternalResultService.resolve(
        category="product",
        subject="phone",
        providers=[
            {
                "provider_id": "same",
                "category": "product",
                "normal_url": "https://first.example",
            },
            {
                "provider_id": "same",
                "category": "phone",
                "normal_url": "https://duplicate.example",
            },
        ],
    )

    assert [row["destination_url"] for row in rows] == [
        "https://first.example",
        "https://duplicate.example",
    ]