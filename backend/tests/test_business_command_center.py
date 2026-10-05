"""Business Command Center (Party B) and the Admin action layer: facts are
counted from the seller's own records, insights are labelled CONFIRMED_FACT /
POSSIBLE_CAUSE / RECOMMENDATION with an action, English + Telugu, and the
staff queue explains WHAT -> WHY -> IMPACT -> ACTION with 🔴 / 🟠 / 🟢."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.order_repository import OrderRepository
from app.repositories.product_catalog_repository import ProductCatalogRepository
from app.services import admin_actions, business_command_center as bcc, demand_insights as di, supply_fit
from app.services.session_tokens import issue_token


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    key = "owner-bcc-" + uuid.uuid4().hex[:6]
    db = str(tmp_path / "bcc.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key,
                                                                   database_path=db))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(db), raising=False)
    monkeypatch.setattr(container, "product_catalog_repository", ProductCatalogRepository(db))
    monkeypatch.setattr(container, "order_repository", OrderRepository(db))
    monkeypatch.setattr(container, "demand_alert_log", di.DemandAlertLog(db), raising=False)
    return TestClient(app), container, {"X-ASKODOX-Admin-Key": key}


def _user(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def test_seller_sees_only_own_facts_with_labelled_actions(api):
    client, container, _ = api
    seller, other = "app-phone-91" + uuid.uuid4().hex[:8], "app-phone-91" + uuid.uuid4().hex[:8]
    catalog = container.product_catalog_repository
    shoe = catalog.upsert_product(seller, "walking shoes", price=1500, stock_status="IN_STOCK")
    catalog.upsert_product(seller, "school bag", stock_status="OUT_OF_STOCK")
    catalog.upsert_product(other, "sandals", price=400)
    container.order_repository.create_order(buyer_user_id="app-phone-9100", seller_user_id=seller,
                                            product_id=shoe, product_title="walking shoes", price=1500)
    container.order_repository.create_order(buyer_user_id="app-phone-9101", seller_user_id=other,
                                            product_id=shoe, product_title="sandals", price=400)
    gap = {"listing_id": shoe, "seller_user_id": seller, "missing": ["size 9"], "subject": "walking shoes"}
    for _ in range(3):
        supply_fit.record_gaps(container.settings.database_path, [gap])

    r = client.get("/api/business/command-center", headers=_user(container, seller))
    assert r.status_code == 200, r.text
    data = r.json()
    s = data["summary"]
    assert (s["listings"], s["out_of_stock"], s["without_price"], s["requests_waiting"]) == (2, 1, 1, 1)
    assert s["missing_data_hits"] == 3
    first = data["insights"][0]
    assert first["severity"] == "red" and first["kind"] == "CONFIRMED_FACT"
    assert first["action"]["route"] == "/orders/incoming"
    titles = [i["title"] for i in data["insights"]]
    assert "3 searches asked for size 9; 'walking shoes' does not say" in titles
    assert any(i["kind"] == "RECOMMENDATION" and i["title"] == "Add size 9 to 'walking shoes'"
               for i in data["insights"])
    assert all("sandals" not in t for t in titles), "never another seller's data"

    te = client.get("/api/business/command-center?language=te", headers=_user(container, seller)).json()
    assert te["insights"][0]["label"] == "నిర్ధారిత వాస్తవం" and "అభ్యర్థన" in te["insights"][0]["title"]
    assert client.get("/api/business/command-center").status_code == 401


def test_new_seller_gets_one_honest_recommendation_and_cause_is_worded_as_may():
    out = bcc.insights([], [], [], [])
    assert [i["title"] for i in out] == ["Add your first listing"]
    orders = [{"status": "REJECTED"}] * 3 + [{"status": "DELIVERED"}]
    cause = [i for i in bcc.insights([{"id": 1, "subject": "rice", "price": 50}], [], [], orders)
             if i["kind"] == "POSSIBLE_CAUSE"]
    assert cause and "may" in cause[0]["detail"]
    green = bcc.insights([{"id": 1, "subject": "rice", "price": 50, "stock_status": "IN_STOCK"}], [], [], [])
    assert green[0]["severity"] == "green"


def test_admin_queue_explains_in_english_and_telugu(api):
    client, container, owner = api
    data = client.get("/admin/cc/staff/work-queue", headers=owner).json()
    assert set(data["status"]) == {"red", "orange", "green"}
    keys = {i["key"] for i in data["items"]}
    assert {"supply_gaps", "listing_reviews", "integrations"} <= keys
    for item in data["items"]:
        assert item["icon"] in ("🔴", "🟠", "🟢")
        assert set(item["explain"]) == {"en", "te"}
        assert {"what", "why", "impact", "action", "button"} <= set(item["explain"]["te"])
        assert "check_error" not in item, item
    ranks = [{"red": 0, "orange": 1, "green": 2}[i["severity"]] for i in data["items"]]
    assert ranks == sorted(ranks)


def test_enrich_uses_real_counts_only():
    items = admin_actions.enrich([{"key": "support", "count": 2}, {"key": "demand", "count": 5},
                                  {"key": "content", "count": 0}])
    assert [i["severity"] for i in items] == ["red", "orange", "green"]
    assert items[0]["explain"]["en"]["what"] == "2 support cases are open."
    assert items[0]["explain"]["te"]["what"].startswith("2 ")
    assert items[2]["explain"]["en"]["action"] == "No action needed."
