"""Results share the keyword AND the intent (APK 1274: fresh chicken delivery
showed poultry-chick / wholesale pages)."""
from app.services.universal_external_result_service import (
    UniversalOnlineFallbackService,
    intent_conflict,
)


def test_food_request_drops_livestock_and_wholesale_pages():
    want = "fresh chicken delivery"
    assert intent_conflict(want, "MEAT", "https://farm.example.in/broiler", "Day old broiler chicks for sale",
                           "Hatchery in Krishna district") == "livestock_page"
    assert intent_conflict(want, "MEAT", "https://www.indiamart.com/x", "Frozen chicken", "") == "wholesale_page"
    assert intent_conflict(want, "MEAT", "https://x.example.in", "Chicken manufacturers & exporters", "") == \
        "wholesale_page"
    assert intent_conflict(want, "MEAT", "https://licious.in/chicken", "Fresh chicken curry cut - order online",
                           "Delivered in 90 minutes") is None


def test_explicit_wholesale_or_farming_requests_keep_those_pages():
    assert intent_conflict("broiler chicks for my poultry farm", "", "https://farm.example.in",
                           "Day old broiler chicks", "") is None
    assert intent_conflict("chicken wholesale supplier bulk", "", "https://www.indiamart.com/x",
                           "Chicken wholesalers", "") is None


def test_online_results_apply_the_intent_guard():
    rows = [
        {"url": "https://farm.example.in/chicks", "title": "Chicken chicks day old for sale price",
         "snippet": "Buy broiler chicks from our hatchery"},
        {"url": "https://www.indiamart.com/fresh-chicken", "title": "Fresh chicken price",
         "snippet": "Chicken suppliers buy online"},
        {"url": "https://shop.example.in/fresh-chicken", "title": "Fresh chicken curry cut buy online",
         "snippet": "₹240/kg, home delivery"},
    ]
    service = UniversalOnlineFallbackService(lambda query, limit: rows)
    out = service.online(category="MEAT", subject="fresh chicken", limit=4)
    assert len(out) == 1 and "shop.example.in/fresh-chicken" in str(out[0])
    assert service.filtered.get("other_intent") == 2
