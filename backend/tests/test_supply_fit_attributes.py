"""Registered listings are judged on their STRUCTURED catalogue attributes
when the conversation names one (any category: keys come from the templates)."""
from app.services import supply_fit


LISTING = {"id": 9, "subject": "Chicken curry cut 1 kg", "price": 240, "stock_status": "IN_STOCK"}


def test_conversation_detail_matches_a_listing_attribute():
    attrs = {"cut": ["Curry cut"], "freshness": ["Fresh"]}
    fit = supply_fit.evaluate(LISTING, {"dynamic_fields": {"cut": "curry cut"}}, attributes=attrs)
    assert fit["matched"] == ["cut curry cut"] and fit["status"] == "fits"
    miss = supply_fit.evaluate(LISTING, {"dynamic_fields": {"cut": "boneless"}}, attributes=attrs)
    assert miss["unmatched"] == ["cut boneless"] and miss["status"] == "mismatch"


def test_explicit_constraint_uses_structured_value_before_free_text():
    used = {"id": 3, "subject": "Honda Activa", "stock_status": "IN_STOCK"}
    fit = supply_fit.evaluate(used, {"constraints": {"condition": "new"}}, attributes={"condition": ["Used"]})
    assert fit["unmatched"] == ["condition new"]


def test_no_structured_attribute_means_no_guess():
    fit = supply_fit.evaluate(LISTING, {"dynamic_fields": {"cut": "boneless"}}, attributes={})
    assert fit["matched"] == [] and fit["unmatched"] == [], "an attribute the listing does not carry is not judged"


def test_annotate_reads_attributes_in_one_lookup():
    rows = [{"id": "9", "match_source": "registered"}, {"id": "x", "match_source": "online"}]
    calls = []

    def attrs(ids):
        calls.append(ids)
        return {9: {"cut": ["Curry cut"]}}
    supply_fit.annotate(rows, {"dynamic_fields": {"cut": "Curry cut"}}, lambda i: LISTING, attrs)
    assert calls == [[9]] and rows[0]["fit"]["status"] == "fits" and "fit" not in rows[1]
    # The seller's details travel with the row (Result Board chips); other
    # sources never get any.
    assert rows[0]["attributes"] == {"cut": "Curry cut"} and "attributes" not in rows[1]
