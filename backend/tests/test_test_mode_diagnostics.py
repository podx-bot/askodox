"""Test Mode Diagnostics (owner request 2026-10-29): a staff phone can record
what happened while testing so Claude reads it instead of asking for
screenshots. Customers can never turn it on; nothing is stored while it is
off; text is masked; it expires by itself; readers need qa:view."""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import rate_limit
from app.services import test_diagnostics as td
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-tm-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "tm.db"))
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    monkeypatch.setattr(container, "test_diagnostics_store", None, raising=False)
    yield TestClient(app), container


def bearer(container, phone):
    return {"Authorization": "Bearer " + issue_token(f"app-phone-{phone}", container.settings.session_token_secret)}


def staff(client, role, phone):
    made = client.post("/admin/cc/staff", headers=OWNER, json={"name": f"{role} person", "role": role}).json()
    assert client.patch(f"/admin/cc/staff/{made['id']}", headers=OWNER, json={"phone": phone}).status_code == 200
    return made


EVENTS = [
    {"kind": "screen", "screen": "/", "at": "2026-10-29T09:30:00+05:30"},
    {"kind": "send", "screen": "/", "detail": {"input": "typed", "text": "Oppo Find X10 call me 9876543210"}},
    {"kind": "reply", "screen": "/", "detail": {"grounding_verified": False, "honesty": ["unbacked_nonexistence"]}},
    {"kind": "voice", "screen": "/", "detail": {"engine": "device_fallback", "reason": "mp3 not played"}},
    {"kind": "guide", "screen": "/pos", "detail": {"shown": "Item name", "spoken": "Enter price"}},
    {"kind": "error", "screen": "/pos", "detail": {"error": "StateError: bad state"}},
    {"kind": "bogus", "detail": {}},
]


def test_customer_cannot_turn_it_on_and_nothing_is_stored_while_off(api):
    client, container = api
    customer = bearer(container, "919800000001")
    assert client.get("/api/me/test-mode", headers=customer).json() == {"enabled": False, "expires_at": None,
                                                                        "allowed": False}
    assert client.put("/api/me/test-mode", headers=customer, json={"enabled": True}).status_code == 403
    stored = client.post("/api/diagnostics/test-events", headers=customer, json={"events": EVENTS}).json()
    assert stored == {"stored": 0, "enabled": False}
    assert client.post("/api/diagnostics/test-events", json={"events": EVENTS}).status_code == 401


def test_staff_test_mode_records_masked_events_and_readers_get_a_summary(api):
    client, container = api
    staff(client, "qa_staff", "919812345678")
    me = bearer(container, "9812345678")
    on = client.put("/api/me/test-mode", headers=me, json={"enabled": True}).json()
    assert on["enabled"] is True and on["allowed"] is True and on["expires_at"]
    stored = client.post("/api/diagnostics/test-events", headers=me,
                         json={"events": EVENTS, "session": "s1", "app_version": "1394"}).json()
    assert stored == {"stored": 6, "enabled": True}, "unknown kinds are dropped"
    assert client.get("/admin/cc/test-mode/events").status_code == 401
    got = client.get("/admin/cc/test-mode/events", headers=OWNER).json()
    texts = [str(item["detail"]) for item in got["items"]]
    assert not any("9876543210" in t for t in texts), "phone numbers are masked"
    summary = got["summary"]
    assert summary["by_kind"]["voice"] == 1 and summary["voice_engines"] == {"device_fallback": 1}
    assert summary["honesty_guard_hits"] == 1 and summary["unverified_live_answers"] == 1
    assert summary["guide_shown_vs_spoken_mismatch"] == 1
    assert summary["errors"] == ["StateError: bad state"]
    assert client.get("/admin/cc/test-mode/testers", headers=OWNER).json()["items"][0]["enabled"] is True
    off = client.put("/api/me/test-mode", headers=me, json={"enabled": False}).json()
    assert off["enabled"] is False
    assert client.post("/api/diagnostics/test-events", headers=me, json={"events": EVENTS}).json()["stored"] == 0


def test_test_mode_expires_and_old_events_are_deleted(tmp_path):
    store = td.TestDiagnosticsStore(str(tmp_path / "x.db"))
    start = datetime(2026, 10, 29, tzinfo=timezone.utc)
    store.set_enabled("app-phone-919812345678", True, at=start)
    assert store.record("app-phone-919812345678", EVENTS, at=start)["stored"] == 6
    later = start + timedelta(hours=td.TEST_MODE_HOURS + 1)
    assert store.status("app-phone-919812345678", later)["enabled"] is False
    much_later = later + timedelta(days=td.RETENTION_DAYS + 1)
    store.set_enabled("app-phone-919812345678", True, at=much_later)
    store.record("app-phone-919812345678", EVENTS[:1], at=much_later)
    assert len(store.events(since_minutes=60 * 24 * 60, at=much_later)) == 1, "the 6 old events were deleted"
