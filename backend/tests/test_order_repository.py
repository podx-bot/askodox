import pytest

from app.repositories.order_repository import OrderRepository, VALID_STATUSES


@pytest.fixture()
def repo(tmp_path):
    return OrderRepository(str(tmp_path / "orders.db"))


def test_create_order_persists_all_fields_and_defaults_to_placed(repo):
    order_id = repo.create_order(
        buyer_user_id="app-phone-919876543210",
        seller_user_id="app-phone-919000000000",
        product_id=42,
        product_title="Mango Pickle",
        quantity=2,
        unit="kg",
        price=250,
        buyer_note="Please deliver by evening",
    )

    order = repo.get(order_id)
    assert order["buyer_user_id"] == "app-phone-919876543210"
    assert order["seller_user_id"] == "app-phone-919000000000"
    assert order["product_id"] == 42
    assert order["product_title"] == "Mango Pickle"
    assert order["quantity"] == 2
    assert order["unit"] == "kg"
    assert order["price"] == 250
    assert order["currency"] == "INR"
    assert order["total_amount"] == 500
    assert order["status"] == "PLACED"
    assert order["buyer_note"] == "Please deliver by evening"
    assert order["seller_note"] is None


def test_create_order_without_quantity_leaves_total_as_unit_price(repo):
    order_id = repo.create_order(
        buyer_user_id="app-buyer-1",
        seller_user_id="app-seller-1",
        product_id=1,
        product_title="Electrician visit",
        price=300,
    )

    order = repo.get(order_id)
    assert order["quantity"] is None
    assert order["total_amount"] == 300


def test_create_order_requires_buyer_seller_and_title(repo):
    with pytest.raises(ValueError):
        repo.create_order(buyer_user_id="", seller_user_id="app-seller-1", product_id=1, product_title="X")
    with pytest.raises(ValueError):
        repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="", product_id=1, product_title="X")
    with pytest.raises(ValueError):
        repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="   ")


def test_list_for_buyer_and_seller_return_only_their_own_orders(repo):
    repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="A")
    repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-2", product_id=2, product_title="B")
    repo.create_order(buyer_user_id="app-buyer-2", seller_user_id="app-seller-1", product_id=1, product_title="A")

    buyer_orders = repo.list_for_buyer("app-buyer-1")
    seller_orders = repo.list_for_seller("app-seller-1")

    assert len(buyer_orders) == 2
    assert {o["product_title"] for o in buyer_orders} == {"A", "B"}
    assert len(seller_orders) == 2
    assert all(o["seller_user_id"] == "app-seller-1" for o in seller_orders)


def test_list_for_buyer_orders_most_recent_first(repo):
    first = repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="First")
    second = repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="Second")

    orders = repo.list_for_buyer("app-buyer-1")

    assert orders[0]["id"] == second
    assert orders[1]["id"] == first


def test_update_status_changes_status_and_records_seller_note(repo):
    order_id = repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="A")

    updated = repo.update_status(order_id, "accepted", seller_note="Will deliver tomorrow")

    assert updated is True
    order = repo.get(order_id)
    assert order["status"] == "ACCEPTED"
    assert order["seller_note"] == "Will deliver tomorrow"


def test_update_status_rejects_unknown_status(repo):
    order_id = repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="A")

    with pytest.raises(ValueError):
        repo.update_status(order_id, "SHIPPED_TO_MARS")


def test_update_status_returns_false_for_missing_order(repo):
    assert repo.update_status(99999, "ACCEPTED") is False


def test_all_valid_statuses_are_accepted(repo):
    order_id = repo.create_order(buyer_user_id="app-buyer-1", seller_user_id="app-seller-1", product_id=1, product_title="A")
    for status in VALID_STATUSES:
        assert repo.update_status(order_id, status) is True
        assert repo.get(order_id)["status"] == status