import sqlite3

from app.services.partner_revenue_hub import PartnerRevenueHub


def test_partner_registry_is_persistent_and_disabled_by_default(tmp_path):
    db = tmp_path / "hub.db"
    hub = PartnerRevenueHub(str(db))
    saved = hub.upsert_partner(
        "example",
        name="Example Partner",
        sector="commerce",
        category="product",
        integration_modes=["api", "affiliate", "api"],
        commercial_model="affiliate",
        staff_fallback=True,
    )
    assert saved["active"] is False
    assert saved["integration_modes"] == ["affiliate", "api"]
    reloaded = PartnerRevenueHub(str(db)).get_partner("example")
    assert reloaded["staff_fallback"] is True
    assert reloaded["commercial_model"] == "affiliate"


def test_revenue_event_duplicate_external_reference_is_blocked(tmp_path):
    hub = PartnerRevenueHub(str(tmp_path / "hub.db"))
    hub.record_event("conversion", "example", external_reference="order-1", value=10)
    try:
        hub.record_event("conversion", "example", external_reference="order-1", value=10)
        assert False, "duplicate event must be rejected"
    except sqlite3.IntegrityError:
        pass


def test_empty_external_reference_allows_click_events(tmp_path):
    hub = PartnerRevenueHub(str(tmp_path / "hub.db"))
    first = hub.record_event("click", "example")
    second = hub.record_event("click", "example")
    assert second > first
