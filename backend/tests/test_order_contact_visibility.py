import pytest

from app.services.order_contact_visibility import mask_contact_for_viewer


@pytest.fixture()
def order_row():
    return {
        "id": 42,
        "buyer_user_id": "app-phone-919876543210",
        "seller_user_id": "app-phone-919000000000",
        "status": "PLACED",
    }


def test_mask_contact_for_viewer_hides_counterpart_until_acceptance(order_row):
    buyer_view = mask_contact_for_viewer(order_row, "app-phone-919876543210")
    seller_view = mask_contact_for_viewer(order_row, "app-phone-919000000000")

    assert buyer_view["buyer_user_id"] == "app-phone-919876543210"
    assert buyer_view["seller_user_id"] == ""
    assert seller_view["buyer_user_id"] == ""
    assert seller_view["seller_user_id"] == "app-phone-919000000000"


def test_mask_contact_for_viewer_keeps_counterparty_visible_after_acceptance(order_row):
    order_row["status"] = "ACCEPTED"

    buyer_view = mask_contact_for_viewer(order_row, "app-phone-919876543210")
    seller_view = mask_contact_for_viewer(order_row, "app-phone-919000000000")

    assert buyer_view["seller_user_id"] == "app-phone-919000000000"
    assert seller_view["buyer_user_id"] == "app-phone-919876543210"


def test_mask_contact_for_viewer_hides_everything_for_untrusted_viewer(order_row):
    masked = mask_contact_for_viewer(order_row, "app-guest-zzz")

    assert masked["buyer_user_id"] == ""
    assert masked["seller_user_id"] == ""
