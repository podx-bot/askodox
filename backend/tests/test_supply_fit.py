"""Own-supply matching judges each registered listing against the customer's
explicit constraints (size / budget / brand / distance) and explains why --
never a keyword match only, never an assumed value."""
import dataclasses
import uuid

from fastapi.testclient import TestClient

from app.services import supply_fit

DEMAND = {"subject": "walking shoes", "constraints": {"size": "9", "budget_max": 2000}}


def test_fits_missing_and_mismatch_are_distinct():
    a = supply_fit.evaluate({"subject": "walking shoes", "variant": "Size: 8, 9, 10", "price": 1799,
                             "stock_status": "IN_STOCK"}, DEMAND)
    assert a["status"] == "fits" and a["matched"] == ["size 9", "price ₹1,799 (under ₹2,000)"]
    b = supply_fit.evaluate({"subject": "walking shoes", "price": 1500}, DEMAND)
    assert b["status"] == "missing_data" and b["unknown"] == ["size 9"], "no size stated -> unknown, never assumed"
    c = supply_fit.evaluate({"subject": "walking shoes", "variant": "UK 9", "price": 3200}, DEMAND)
    assert c["status"] == "mismatch" and c["unmatched"] == ["price ₹3,200 (under ₹2,000)"]
    assert a["score"] > b["score"] > c["score"]
    out = supply_fit.evaluate({"subject": "walking shoes", "variant": "Size 9", "price": 900,
                               "stock_status": "OUT_OF_STOCK"}, DEMAND)
    assert "in stock" in out["unmatched"]
    assert "Not stated by the seller: size 9" in supply_fit.why_text(b)


def test_distance_and_brand_constraints():
    demand = {"constraints": {"brand": "Bata", "radius_km": 5}}
    near = supply_fit.evaluate({"subject": "shoes", "brand": "Bata"}, demand, distance_km=2.0)
    far = supply_fit.evaluate({"subject": "shoes", "brand": "Bata"}, demand, distance_km=9.5)
    assert near["status"] == "fits" and far["unmatched"] == ["9.5 km away (asked within 5 km)"]
    other = supply_fit.evaluate({"subject": "shoes", "brand": "Nike"}, demand, distance_km=1)
    assert other["unmatched"] == ["brand Bata"]


def test_discovery_annotates_and_ranks_registered_rows_and_records_seller_gaps(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(
        container.settings, database_path=str(tmp_path / "fit.db")))
    catalog = container.product_catalog_repository
    sellers = ["app-phone-91" + str(uuid.uuid4().int)[:10] for _ in range(3)]
    over = catalog.upsert_product(sellers[2], "walking shoes", variant="Size 9", price=3200, stock_status="IN_STOCK")
    unknown = catalog.upsert_product(sellers[1], "walking shoes", price=1500, stock_status="IN_STOCK")
    good = catalog.upsert_product(sellers[0], "walking shoes", variant="Size: 8, 9", price=1799, stock_status="IN_STOCK")
    matches = [{"id": str(i), "match_source": "registered", "title": "walking shoes"} for i in (over, unknown, good)]
    gaps = supply_fit.annotate(matches, DEMAND, catalog.get)
    ranked = supply_fit.rank_registered(matches)
    assert [m["id"] for m in ranked] == [str(good), str(unknown), str(over)]
    assert ranked[0]["why"].startswith("Matches size 9")
    supply_fit.record_gaps(container.settings.database_path, gaps)
    supply_fit.record_gaps(container.settings.database_path, gaps)
    seller_gaps = supply_fit.gaps_for_seller(container.settings.database_path, sellers[1])
    assert seller_gaps == [{"listing_id": unknown, "field": "size 9", "subject": "walking shoes", "hits": 2,
                            "last_seen": seller_gaps[0]["last_seen"]}]
    # The public discovery pipeline carries fit / why on registered rows.
    client = TestClient(app)
    body = {"user_id": "guest", "raw_text": "walking shoes size 9 under 2000", "subject": "walking shoes",
            "intent": "buy", "category": "PRODUCT", "size": "9",
            "dynamic_fields": {"budget_max": 2000}, "trace": {"query": "walking shoes size 9 under 2000"}}
    found = client.post("/deals/discover", json=body).json()
    registered = [m for m in found.get("matches") or [] if m.get("fit")]
    assert len(registered) == 3, "every registered row carries its fit"
    assert registered[0]["fit"]["status"] == "fits" and registered[0]["why"].startswith("Matches size 9")
    assert registered[-1]["fit"]["status"] == "mismatch", "over budget ranks last among registered rows"
