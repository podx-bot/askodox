"""Business-name change rule (15 days free, then 30, then 60 days) and open / paused / closed status."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services import name_change_policy as policy
from app.services.pos_online import PosOnline
from app.services.pos_selfshop import PosSelfShop
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000101"
CASHIER = "app-phone-9400000102"
T0 = datetime(2026, 11, 1, 6, 0, tzinfo=timezone.utc)


def days(n):
    return T0 + timedelta(days=n)


def test_policy_free_window_then_30_then_60():
    state = policy.after_change({}, T0, had_name=False)
    assert policy.evaluate(state, days(10))["free_window"] and policy.evaluate(state, days(10))["can_change"]
    # a correction inside 15 days costs nothing, however many
    state = policy.after_change(state, days(3), True)
    state = policy.after_change(state, days(9), True)
    assert state["edits"] == 0
    # day 16: first real change -> locked 30 days
    assert policy.evaluate(state, days(16))["can_change"]
    state = policy.after_change(state, days(16), True)
    assert state["edits"] == 1
    blocked = policy.evaluate(state, days(40))
    assert not blocked["can_change"]
    assert blocked["next_allowed_at"].startswith((days(46)).date().isoformat())
    # after 30 days: second change -> locked 60 days
    assert policy.evaluate(state, days(47))["can_change"]
    state = policy.after_change(state, days(47), True)
    assert state["edits"] == 2
    assert not policy.evaluate(state, days(47 + 59))["can_change"]
    assert policy.evaluate(state, days(47 + 61))["can_change"]
    # every later change stays 60 days
    state = policy.after_change(state, days(47 + 61), True)
    assert state["edits"] == 3
    assert not policy.evaluate(state, days(47 + 61 + 59))["can_change"]


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    biz = store.create_business(OWNER, {"name": "Lakshmi Kirana", "template": "kirana", "invoice_prefix": "LK",
                                         "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000102", "manager")
    return store, biz, now


def test_pos_rename_follows_the_rule(env):
    store, biz, now = env
    assert store.business(biz, OWNER)["name_change"]["free_window"]
    store.update_settings(biz, OWNER, {"name": "Lakshmi Super Market"})  # free correction
    assert store.business(biz, OWNER)["name"] == "Lakshmi Super Market"
    now[0] = days(20)
    store.update_settings(biz, OWNER, {"name": "Lakshmi Mart"})  # first real change -> 30 day lock
    now[0] = days(30)
    with pytest.raises(PosError) as e:
        store.update_settings(biz, OWNER, {"name": "Another"})
    assert e.value.status == 409 and e.value.extra["next_allowed_at"]
    assert store.business(biz, OWNER)["name"] == "Lakshmi Mart"
    # the same name again is never a change; address edits are never blocked
    store.update_settings(biz, OWNER, {"name": "Lakshmi Mart", "address": "Main road"})
    now[0] = days(51)
    store.update_settings(biz, OWNER, {"name": "Lakshmi Bazaar"})
    now[0] = days(51 + 59)
    with pytest.raises(PosError):
        store.update_settings(biz, OWNER, {"name": "Lakshmi Bazaar 2"})


def test_status_owner_only_and_gates_new_orders(env):
    store, biz, now = env
    with pytest.raises(PosError) as e:
        store.set_status(biz, CASHIER, "closed")
    assert e.value.status == 403
    assert store.business(biz, OWNER)["status"] == "open" and store.is_open(biz)
    out = store.set_status(biz, OWNER, "paused", "festival break")
    assert out["status"] == "paused" and out["status_note"] == "festival break" and not store.is_open(biz)
    listed = store.my_businesses(OWNER)[0]
    assert listed["status"] == "paused"
    # self-shopping refuses a paused shop
    shop = PosSelfShop(store)
    shop.update_settings(biz, OWNER, {"enabled": True})
    code = shop.settings(biz, OWNER)["code"]
    with pytest.raises(PosError) as e:
        shop.join("app-phone-9876543210", code)
    assert e.value.status == 409
    store.set_status(biz, OWNER, "open")
    assert shop.join("app-phone-9876543210", code)["status"] == "OPEN"
    with pytest.raises(PosError):
        store.set_status(biz, OWNER, "gone")


def test_online_listings_hide_while_paused(env):
    store, biz, now = env
    online = PosOnline(store)
    online.set_default(biz, OWNER, "both")
    item = store.add_product(biz, OWNER, {"name": "Rice 1kg", "unit": "pcs", "price_paise": 6000})["id"]
    assert online.sync(biz, [item])["live"] == 1
    store.set_status(biz, OWNER, "closed")
    assert online.sync(biz).get("hidden", 0) == 1
    store.set_status(biz, OWNER, "open")
    assert online.sync(biz)["live"] == 1


def test_profile_business_name_rule(monkeypatch, tmp_path):
    """PUT /api/me/profile applies the same rule to the "My business" name."""
    import types

    from fastapi import HTTPException

    from app.api.routes import profile as profile_routes
    from app.repositories.user_profile_repository import UserProfileRepository

    repo = UserProfileRepository(str(tmp_path / "p.db"))
    container = types.SimpleNamespace(user_profile_repository=repo, settings=types.SimpleNamespace(
        database_path=str(tmp_path / "p.db")))
    request = types.SimpleNamespace(app=types.SimpleNamespace(state=types.SimpleNamespace(container=container)))
    monkeypatch.setattr(profile_routes, "_authenticated_app_user", lambda r: OWNER)
    monkeypatch.setattr(profile_routes, "_verification", lambda c, u: {})
    monkeypatch.setattr(profile_routes, "_role_verifications", lambda c, u: {})

    def put(**fields):
        return profile_routes.update_my_profile(profile_routes.ProfileUpdate(**fields), request)

    out = put(business_name="Murali Chicken")
    assert out["business_name"] == "Murali Chicken" and out["business_name_change"]["free_window"]
    assert put(business_name="Murali Mutton Chicken")["business_name"] == "Murali Mutton Chicken"  # free correction
    # push the window into the past: the next change is real and locks 30 days
    state = repo.name_policy_state(OWNER)
    state["set_at"] = (datetime.now(timezone.utc) - timedelta(days=20)).isoformat()
    repo.set_name_policy_state(OWNER, state)
    out = put(business_name="Murali Shop")
    assert out["business_name_change"]["can_change"] is False
    with pytest.raises(HTTPException) as e:
        put(business_name="Another Name")
    assert e.value.status_code == 409 and "తర్వాత" in e.value.detail
    assert put(business_name="Murali Shop", business_category="Meat")["business_category"] == "Meat"
