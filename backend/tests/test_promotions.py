"""Targeted promotions: legitimate-data targeting, consent, frequency caps,
four-eyes approval, compact cards with disclosure, metrics, no real sends."""
import dataclasses
import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.promotion_engine import haversine_km, run_key
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-promo-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "p.db")),
                        raising=False)
    return TestClient(app), container


def _user(container, town, lat=None, lng=None):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    fields = {"address": f"Main road, {town}, Krishna district, Andhra Pradesh 521165"}
    if lat is not None:
        fields.update(latitude=lat, longitude=lng)
    from app.api.routes.profile import profiles

    profiles(container).update(uid, fields)
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _staff(client, perms):
    r = client.post("/admin/cc/staff", headers=OWNER, json={"name": "g", "role": "growth_manager",
                                                             "permissions": perms}).json()
    return {"X-ASKODOX-Staff-Token": r["token"]}


def _campaign(client, headers, **data):
    body = {"title": "Diwali sweets", "body": "20% off at local sweet shops", "size": "compact",
            "channels": ["in_app"], "pricing": "free", "audience": "all", "schedule": "immediate", **data}
    r = client.post("/admin/cc/platform/r/promotion_campaigns", headers=headers, json={"data": body})
    assert r.status_code == 200, r.text
    return r.json()


def _act(client, headers, cid, action, **body):
    return client.post(f"/admin/cc/platform/r/promotion_campaigns/{cid}/actions/{action}", headers=headers,
                       json=body)


def test_full_screen_cards_and_unknown_fields_are_rejected(env):
    client, _ = env
    body = {"title": "x", "body": "y", "size": "full", "channels": ["in_app"], "pricing": "free", "audience": "all",
            "schedule": "immediate"}
    assert client.post("/admin/cc/platform/r/promotion_campaigns", headers=OWNER,
                       json={"data": body}).status_code == 400
    body["size"] = "compact"
    body["status"] = "ACTIVE"  # mass assignment attempt
    assert client.post("/admin/cc/platform/r/promotion_campaigns", headers=OWNER,
                       json={"data": body}).status_code == 400


def test_targeting_consent_caps_four_eyes_and_metrics(env):
    client, container = env
    town = "Promotown" + uuid.uuid4().hex[:5]
    near, near_h = _user(container, town, 16.30, 80.60)
    far, far_h = _user(container, "Elsewhere" + uuid.uuid4().hex[:4], 17.40, 78.40)
    creator = _staff(client, ["notifications:view", "notifications:manage"])
    approver = _staff(client, ["notifications:view", "notifications:approve"])
    viewer = _staff(client, ["notifications:view"])

    c = _campaign(client, creator, town=town, channels=["in_app", "sms"], pricing="paid", price=499,
                  advertiser="Sri Sweets", cap_per_user_day=1)
    est = _act(client, viewer, c["id"], "estimate").json()["result"]
    assert est["matched"] == 1 and est["reachable"] == {"in_app": 1, "sms": 0}
    assert est["excluded_no_consent"]["sms"] == 1  # promotional SMS needs an opt-in

    assert _act(client, creator, c["id"], "submit").status_code == 200
    own = _act(client, creator, c["id"], "approve")
    assert own.status_code == 403 and "second person" in own.json()["detail"]
    assert _act(client, viewer, c["id"], "approve").status_code == 403
    assert _act(client, approver, c["id"], "approve").json()["status"] == "ACTIVE"

    assert _act(client, creator, c["id"], "send_now").status_code == 409  # confirmation required
    ran = _act(client, creator, c["id"], "send_now", confirm=True).json()["result"]
    assert ran["ran"] and ran.get("delivered") == 1
    again = _act(client, creator, c["id"], "send_now", confirm=True).json()["result"]
    assert "delivered" not in again  # capped / already sent: never twice in a window

    feed = client.get("/api/me/promotions", headers=near_h).json()["items"]
    assert len(feed) == 1 and feed[0]["size"] == "compact" and feed[0]["disclosure"] == "Sponsored"
    assert client.get("/api/me/promotions", headers=far_h).json()["items"] == []
    did = feed[0]["delivery_id"]
    assert client.post(f"/api/me/promotions/{did}/click", headers=far_h).status_code == 404  # not theirs
    assert client.post(f"/api/me/promotions/{did}/open", headers=near_h).status_code == 200
    assert client.post(f"/api/me/promotions/{did}/click", headers=near_h).status_code == 200
    m = client.get(f"/admin/cc/platform/promotions/{c['id']}/metrics", headers=viewer).json()
    assert (m["delivered"], m["opened"], m["clicked"]) == (1, 1, 1)
    assert m["revenue_expected"] == 499 and m["revenue_confirmed"] == 0  # no gateway: never "earned" by itself

    # Switching in-app promotions off wins over every campaign.
    client.put("/api/me/promotion-consent", headers=near_h, json={"in_app": False})
    assert client.post(f"/api/me/promotions/{did}/dismiss", headers=near_h).status_code == 200
    assert client.get("/api/me/promotions", headers=near_h).json()["items"] == []


def test_sms_opt_in_goes_through_messenger_without_real_send(env):
    client, container = env
    town = "Smstown" + uuid.uuid4().hex[:5]
    uid, h = _user(container, town)
    client.put("/api/me/promotion-consent", headers=h, json={"sms": True})
    c = _campaign(client, OWNER, town=town, channels=["sms"])
    _act(client, OWNER, c["id"], "submit")
    assert _act(client, OWNER, c["id"], "approve").status_code == 200  # the Owner may approve their own
    ran = _act(client, OWNER, c["id"], "send_now", confirm=True).json()["result"]
    statuses = {k for k in ran if k not in ("ran", "run_key")}
    # Staging / tests: SMS is not configured, so nothing leaves ASKODOX.
    assert statuses & {"skipped_needs_configuration", "mock_delivered", "skipped_no_contact", "skipped_switched_off"}
    assert "sent" not in statuses


def test_schedule_windows_and_radius():
    now = datetime(2026, 10, 5, 9, 30, tzinfo=timezone.utc)
    c = {"data": {"schedule": "daily", "start_at": "2026-10-01", "end_at": "2026-10-31"}}
    assert run_key(c, now) == "d20261005"
    assert run_key({"data": {"schedule": "weekly"}}, now).startswith("w2026-")
    assert run_key({"data": {"schedule": "daily", "start_at": "2026-11-01"}}, now) is None
    assert run_key({"data": {"schedule": "daily", "end_at": "2026-10-01"}}, now) is None
    assert run_key({"data": {"schedule": "custom", "interval_hours": 6, "start_at": "2026-10-05T00:00:00"}},
                   now) == "c1"
    assert 240 < haversine_km((16.5062, 80.648), (17.385, 78.4867)) < 260  # Vijayawada - Hyderabad
