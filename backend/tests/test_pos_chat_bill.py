"""Owner 2026-11-19: a bill made in the main chat from the shop's OWN item numbers -- no AI call, no guessed items,
unknown numbers named, only for people who sell in that shop. Universal: works for any shop type."""
from datetime import datetime, timezone

import pytest

from app.services.pos_chat_bill import PosChatBill, parse, reply_text
from app.services.pos_store import PosStore

OWNER = "app-phone-9400000401"
CASHIER = "app-phone-9400000402"
STRANGER = "app-phone-9400000499"


@pytest.mark.parametrize("text,expected", [
    ("bill 1 2, 3 1", [(1, 2), (3, 1)]),
    ("బిల్ 1 రెండు, 2", [(1, 2), (2, 1)]),
    ("#4 x3", [(4, 3)]),
    ("1x2, 3x1", [(1, 2), (3, 1)]),
    ("1 2, 3 1", [(1, 2), (3, 1)]),
    ("నంబర్ 7 మూడు ప్లేట్లు", [(7, 3)]),
    ("बिल 2 दो और 5", [(2, 2), (5, 1)]),
])
def test_parse_reads_item_numbers_and_counts(text, expected):
    assert parse(text) == expected


@pytest.mark.parametrize("text", [
    "5", "I need 2 kg rice", "price of iphone 17", "call me at 5 pm", "", "hello", "my bill is wrong",
])
def test_parse_leaves_ordinary_chat_alone(text):
    assert parse(text) == []


@pytest.fixture()
def shops(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: datetime(2026, 11, 19, 9, 0, tzinfo=timezone.utc))
    hotel = store.create_business(OWNER, {"name": "Sai Hotel", "template": "restaurant", "invoice_prefix": "SH",
                                          "state_code": "37", "registration_type": "unregistered"})["id"]
    store.add_product(hotel, OWNER, {"name": "Tea", "unit": "pcs", "price_paise": 1000})
    store.add_product(hotel, OWNER, {"name": "Chicken Biryani", "unit": "plate", "price_paise": 17000})
    store.set_member(hotel, OWNER, "9400000402", "cashier")
    return store, hotel


def test_card_uses_the_shops_own_numbers_and_names_unknown_ones(shops):
    store, hotel = shops
    card = PosChatBill(store).card(OWNER, "bill 1 2, 2 1, 9 1")
    assert card["business_id"] == hotel and card["shop_name"] == "Sai Hotel"
    assert [(l["item_no"], l["name"], l["count"], l["amount_paise"]) for l in card["lines"]] == [
        (1, "Tea", 2, 2000), (2, "Chicken Biryani", 1, 17000)]
    assert card["unknown"] == [9] and card["total_paise"] == 19000
    assert "#9" in reply_text(card, True) and "#9" in reply_text(card, False)


def test_staff_can_bill_strangers_cannot(shops):
    store, _ = shops
    assert PosChatBill(store).card(CASHIER, "1 3")["lines"][0]["count"] == 3
    assert PosChatBill(store).card(STRANGER, "bill 1 2") is None
    assert PosChatBill(store).card("", "bill 1 2") is None


def test_only_unknown_numbers_gives_no_lines_and_no_guess(shops):
    store, _ = shops
    card = PosChatBill(store).card(OWNER, "bill 55 2")
    assert card["lines"] == [] and card["unknown"] == [55] and card["total_paise"] == 0
    assert "55" in reply_text(card, True)


def test_chat_bill_route(monkeypatch):
    """HTTP: POST /api/pos/chat-bill -> the card from the caller's shop; ordinary words / no shop -> card null;
    the card's lines are exactly what the quick-bill API takes."""
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    for name in ("pos_store", "pos_frontdesk", "pos_bills"):
        monkeypatch.setattr(container, name, None, raising=False)
    client = TestClient(app)
    h = {"Authorization": f"Bearer {issue_token('app-phone-9411100081', container.settings.session_token_secret)}"}
    other = {"Authorization": f"Bearer {issue_token('app-phone-9411100089', container.settings.session_token_secret)}"}
    bid = client.post("/api/pos/businesses", headers=h, json={
        "name": "Ravi Kirana", "template": "kirana", "invoice_prefix": "RK", "state_code": "37",
        "registration_type": "unregistered"}).json()["id"]
    assert client.post(f"/api/pos/businesses/{bid}/products", headers=h,
                       json={"name": "Sugar 1kg", "unit": "pcs", "price_paise": 4500}).status_code == 200
    out = client.post("/api/pos/chat-bill", headers=h, json={"text": "బిల్ 1 2", "te": True})
    assert out.status_code == 200, out.text
    card = out.json()["card"]
    assert card["business_id"] == bid and card["total_paise"] == 9000 and card["lines"][0]["name"] == "Sugar 1kg"
    assert out.json()["reply"]
    made = client.post(f"/api/pos/businesses/{bid}/quick-bill", headers=h, json={
        "lines": [{"item_no": l["item_no"], "count": l["count"]} for l in card["lines"]],
        "advance_paise": 9000, "method": "cash", "client_txn_id": "chat-bill-0001"})
    assert made.status_code == 200 and made.json()["totals"]["grand_total_paise"] == 9000
    assert client.post("/api/pos/chat-bill", headers=h, json={"text": "price of sugar"}).json() == {"card": None}
    assert client.post("/api/pos/chat-bill", headers=other, json={"text": "bill 1 2"}).json() == {"card": None}
    assert client.post("/api/pos/chat-bill", json={"text": "bill 1 2"}).status_code == 401
