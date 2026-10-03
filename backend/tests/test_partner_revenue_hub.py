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


def test_product_desk_uses_affiliate_when_present_and_normal_url_otherwise(tmp_path):
    hub = PartnerRevenueHub(str(tmp_path / "hub.db"))
    hub.upsert_product("shop", "https://merchant.example/one", title="Blue Kurti", category="fashion")
    hub.upsert_product("shop", "https://merchant.example/two", title="Red Kurti", category="fashion",
                       affiliate_url="https://tracked.example/two")
    rows = hub.search_products("kurti", "fashion")
    assert len(rows) == 2
    destinations = {r["title"]: r["destination_url"] for r in rows}
    assert destinations["Blue Kurti"] == "https://merchant.example/one"
    assert destinations["Red Kurti"] == "https://tracked.example/two"


def test_staff_and_bfsi_configuration_persist(tmp_path):
    db = tmp_path / "hub.db"
    hub = PartnerRevenueHub(str(db))
    hub.assign_staff("staff-1", partner_id="risk", sector="insurance", category="health",
                     permissions=["verify", "publish"])
    hub.upsert_bfsi_flow("risk", "insurance", lead_enabled=True, callback_enabled=True,
                         consent_required=True, regulated_entity="Partner Broker", active=True)
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT COUNT(*) FROM partner_staff_assignments").fetchone()[0] == 1
        flow = conn.execute("SELECT lead_enabled,callback_enabled,consent_required FROM bfsi_partner_flows").fetchone()
    assert flow == (1, 1, 1)
