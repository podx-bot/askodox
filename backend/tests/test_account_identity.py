"""One account per phone number: the first id issued for a number is reused
however the number is typed later; existing profiles are adopted; an older app
that still sends its own spelling of the same number is not locked out, a
different number still is."""
import dataclasses
import uuid

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.services import account_identity


@pytest.fixture()
def client(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "id.db")))
    monkeypatch.delenv("RAILWAY_ENVIRONMENT_NAME", raising=False)
    monkeypatch.setenv("ASKODOX_TEST_OTP_MODE", "yes")
    from app.api.routes import onboarding_auth

    onboarding_auth._otps.clear()
    return TestClient(app), monkeypatch


def _sign_in(client, monkeypatch, typed):
    from app.api.routes import onboarding_auth

    digits = "".join(c for c in typed if c.isdigit())
    monkeypatch.setenv("ASKODOX_TEST_OTP_MOBILES", digits)
    onboarding_auth._otps.clear()
    assert client.post("/onboarding/otp/send", json={"mobile": typed}).json()["channel"] == "test"
    return client.post("/onboarding/otp/verify", json={"mobile": typed, "otp": "123456"}).json()


def test_same_number_typed_differently_is_one_account(client):
    c, mp = client
    n = str(uuid.uuid4().int)[:9]
    first = _sign_in(c, mp, "9" + n)
    second = _sign_in(c, mp, "+91 9" + n)
    assert first["app_user_id"] == second["app_user_id"] == "app-phone-9" + n
    other = _sign_in(c, mp, "8" + n)
    assert other["app_user_id"] != first["app_user_id"]


def test_existing_profile_is_adopted(client, tmp_path):
    c, mp = client
    from server import container
    from app.repositories.user_profile_repository import UserProfileRepository

    n = "9" + str(uuid.uuid4().int)[:9]
    UserProfileRepository(container.settings.database_path).update("app-phone-91" + n, {"name": "Old Profile"})
    assert _sign_in(c, mp, n)["app_user_id"] == "app-phone-91" + n, "the account they already use"


def test_old_app_spelling_of_the_same_number_is_accepted_but_not_another_number():
    from app.api.routes.in_app_deal import _matching_app_user

    assert _matching_app_user("app-phone-9876543210", "app-phone-919876543210") == "app-phone-919876543210"
    with pytest.raises(HTTPException):
        _matching_app_user("app-phone-9876543211", "app-phone-919876543210")
    assert not account_identity.same_number("app-guest-1", "app-guest-1")
