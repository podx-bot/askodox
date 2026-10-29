""""Tell me when it is available" (owner request 2026-10-29): a buyer whose
search found nothing gets ONE push when a matching listing appears later.
Strict matching (every content word), only items newer than the watch, one push
per watch, de-duplicated, signed-in only, removed with the account."""
import dataclasses
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import availability_watch as aw
from app.services import rate_limit
from app.services.session_tokens import issue_token

T0 = datetime(2026, 10, 29, 4, 0, tzinfo=timezone.utc)


def test_title_matching_is_strict_and_category_free():
    assert aw.title_matches("Oppo Find X10", "OPPO Find X10 5G (16GB, Black)")
    assert aw.title_matches("washing machine", "LG 8kg front load washing machine")
    assert aw.title_matches("country chicken", "Fresh country chicken 1 kg")
    assert not aw.title_matches("Oppo Find X10", "Oppo Find X9 Pro")
    assert not aw.title_matches("washing machine", "washing powder")
    assert not aw.title_matches("", "anything")


def test_one_push_per_watch_only_for_newer_matching_items(tmp_path):
    store = aw.AvailabilityWatches(str(tmp_path / "w.db"))
    first = store.create("app-phone-919800000001", "Oppo Find X10", location="Vijayawada, AP", at=T0)
    again = store.create("app-phone-919800000001", "oppo find x10", at=T0)
    assert again["already"] is True and again["id"] == first["id"]
    store.create("app-phone-919800000002", "tractor rotavator", at=T0)
    listings = [
        {"subject": "Oppo Find X10", "created_at": (T0 - timedelta(days=1)).isoformat()},  # older: not "new"
        {"subject": "Oppo Find X9", "created_at": (T0 + timedelta(hours=1)).isoformat()},   # wrong model
    ]
    sent = []

    def notify(user, **kw):
        sent.append((user, kw["event_key"]))
        return 1

    sources = [("seller", lambda w: listings)]
    assert aw.run(None, store, notify=notify, sources=sources, at=T0 + timedelta(hours=2)) == {"matched": 0, "pushed": 0}
    listings.append({"brand": "OPPO", "subject": "Find X10", "created_at": (T0 + timedelta(hours=3)).isoformat()})
    assert aw.run(None, store, notify=notify, sources=sources, at=T0 + timedelta(hours=4)) == {"matched": 1, "pushed": 1}
    assert sent == [("app-phone-919800000001", f"availability:{first['id']}")]
    assert aw.run(None, store, notify=notify, sources=sources, at=T0 + timedelta(hours=5))["matched"] == 0, "once only"
    mine = store.mine("app-phone-919800000001")
    assert mine[0]["status"] == "NOTIFIED" and "app_user_id" not in mine[0]


def test_watches_expire_and_are_capped(tmp_path):
    store = aw.AvailabilityWatches(str(tmp_path / "w.db"))
    store.create("u", "solar water heater", at=T0)
    assert store.active(T0 + timedelta(days=aw.WATCH_DAYS + 1)) == []
    for i in range(aw.MAX_ACTIVE_PER_USER):
        store.create("v", f"item number {chr(97 + i)}{chr(97 + i)}", at=T0)
    with pytest.raises(ValueError):
        store.create("v", "one more thing", at=T0)


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "aw.db")))
    monkeypatch.setattr(container, "platform", None, raising=False)
    monkeypatch.setattr(container, "availability_watches", None, raising=False)
    yield TestClient(app), container


def test_routes_need_sign_in_and_account_deletion_removes_watches(api):
    client, container = api
    me = {"Authorization": "Bearer " + issue_token("app-phone-919812345678", container.settings.session_token_secret)}
    assert client.post("/api/me/availability-watches", json={"subject": "Oppo Find X10"}).status_code == 401
    made = client.post("/api/me/availability-watches", headers=me,
                       json={"subject": "Oppo Find X10", "location": "Vijayawada"}).json()["watch"]
    assert made["status"] == "ACTIVE" and made["area"] == "vijayawada"
    assert [w["id"] for w in client.get("/api/me/availability-watches", headers=me).json()["items"]] == [made["id"]]
    assert client.delete(f"/api/me/availability-watches/{made['id']}", headers=me).json() == {"ok": True}
    assert client.delete(f"/api/me/availability-watches/{made['id']}", headers=me).status_code == 404
    client.post("/api/me/availability-watches", headers=me, json={"subject": "solar heater"})
    export = client.get("/api/me/export", headers=me)
    assert export.status_code == 200, export.text
    assert "availability_watches" in str(export.json()), "the buyer's own watches are in their data export"
