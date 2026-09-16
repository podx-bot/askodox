"""Round 8: contact details must not be shared before both parties accept.

See app/services/order_contact_visibility.py's docstring and
docs/ASKODOX_EXECUTION_TRACKER.md's round-8 entry for the finding this
guards against: buyer_user_id/seller_user_id are literally the other
party's phone number ("app-phone-<digits>"), and every order response used
to return both regardless of status, before either side had agreed to
anything.

Tests `mask_contact_for_viewer` directly. It's deliberately kept in its own
dependency-free module (no FastAPI/pydantic import) precisely so it can be
unit-tested like this without needing those installed -- see
ASKODOX_EXECUTION_TRACKER.md's testing notes on prior rounds for that
constraint in this environment.
"""
import pytest

from app.services.order_contact_visibility import mask_contact_for_viewer


def _row(status: str) -> dict:
    return {
        "id": 1,
        "buyer_user_id": "app-phone-919876543210",
        "seller_user_id": "app-phone-919000000000",
        "product_id": 42,
        "product_title": "Maruti 800",
        "quantity": None,
        "unit": None,
        "price": 50000,
        "currency": "INR",
        "total_amount": 50000,
        "status": status,
        "buyer_note": None,
        "seller_note": None,
        "created_at": "2026-09-16T00:00:00",
        "updated_at": "2026-09-16T00:00:00",
    }


@pytest.mark.parametrize("status", ["PLACED", "REJECTED", "CANCELLED"])
def test_seller_contact_hidden_from_buyer_before_acceptance(status):
    masked = mask_contact_for_viewer(_row(status), viewer="buyer")
    assert masked["seller_user_id"] == ""
    assert masked["buyer_user_id"] == "app-phone-919876543210"


@pytest.mark.parametrize("status", ["PLACED", "REJECTED", "CANCELLED"])
def test_buyer_contact_hidden_from_seller_before_acceptance(status):
    masked = mask_contact_for_viewer(_row(status), viewer="seller")
    assert masked["buyer_user_id"] == ""
    assert masked["seller_user_id"] == "app-phone-919000000000"


@pytest.mark.parametrize("status", ["ACCEPTED", "FULFILLED"])
def test_seller_contact_revealed_to_buyer_once_accepted(status):
    masked = mask_contact_for_viewer(_row(status), viewer="buyer")
    assert masked["seller_user_id"] == "app-phone-919000000000"
    assert masked["buyer_user_id"] == "app-phone-919876543210"


@pytest.mark.parametrize("status", ["ACCEPTED", "FULFILLED"])
def test_buyer_contact_revealed_to_seller_once_accepted(status):
    masked = mask_contact_for_viewer(_row(status), viewer="seller")
    assert masked["buyer_user_id"] == "app-phone-919876543210"
    assert masked["seller_user_id"] == "app-phone-919000000000"


def test_status_is_case_insensitive_for_visibility():
    masked = mask_contact_for_viewer(_row("accepted"), viewer="buyer")
    assert masked["seller_user_id"] == "app-phone-919000000000"


def test_original_row_is_not_mutated():
    row = _row("PLACED")
    mask_contact_for_viewer(row, viewer="buyer")
    assert row["seller_user_id"] == "app-phone-919000000000"
