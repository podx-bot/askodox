"""Truthful runtime integration states (LIVE / NOT_CONFIGURED / DEGRADED /
ERROR / QUOTA_EXHAUSTED / DISABLED), never a hand-set flag, never a secret."""
from fastapi.testclient import TestClient

from app.services.integration_readiness import runtime_rows, search_state


def _rows(**kw):
    defaults = dict(maps_body={"configured": False}, web={"state": "ok", "fallbacks": {"google_cse": "not_configured"}},
                    flag=lambda k: True, partners=[])
    defaults.update(kw)
    return {r["integration"]: r for r in runtime_rows(None, **defaults)}


def test_search_states_map_the_live_provider_state():
    assert search_state({"state": "ok"}) == "LIVE"
    assert search_state({"state": "quota_exhausted"}) == "QUOTA_EXHAUSTED"
    assert search_state({"state": "auth_failed"}) == "ERROR"
    assert search_state({"state": "not_configured"}) == "NOT_CONFIGURED"
    assert search_state({}) == "CONFIGURED_NOT_VERIFIED"


def test_maps_states_per_api_and_quota():
    ok = _rows(maps_body={"configured": True, "apis": {"geocoding": "OK", "places": "OK", "routes": "OK"}})
    assert ok["Google Maps"]["state"] == "LIVE"
    part = _rows(maps_body={"configured": True, "apis": {"geocoding": "OK", "routes": "REQUEST_DENIED: not enabled"}})
    assert part["Google Maps"]["state"] == "DEGRADED" and part["Google Maps"]["apis"]["routes"] == "FAILED"
    quota = _rows(maps_body={"configured": True, "apis": {"places": "OVER_QUERY_LIMIT: quota exceeded"}})
    assert quota["Google Maps"]["state"] == "QUOTA_EXHAUSTED"
    assert _rows()["Google Maps"]["state"] == "NOT_CONFIGURED"


def test_mobility_and_fallback_states_come_from_flags_and_approved_partners():
    assert _rows(flag=lambda k: k != "delivery.matching")["Mobility (rides / delivery matching)"]["state"] == "DISABLED"
    assert _rows()["Mobility (rides / delivery matching)"]["state"] == "NOT_CONFIGURED"
    approved = [{"status": "ACTIVE", "data": {"available": False}}]
    assert _rows(partners=approved)["Mobility (rides / delivery matching)"]["state"] == "DEGRADED"
    approved[0]["data"]["available"] = True
    assert _rows(partners=approved)["Mobility (rides / delivery matching)"]["state"] == "LIVE"
    cse = "Web search fallback (Google Programmable Search)"
    assert _rows()[cse]["state"] == "NOT_CONFIGURED"
    assert _rows(web={"state": "ok", "fallbacks": {"google_cse": "error"}})[cse]["state"] == "ERROR"
    assert _rows(flag=lambda k: k != "videos.upload")["ASKODOX native video upload"]["state"] == "DISABLED"


def test_public_integrations_health_has_no_secrets(monkeypatch):
    from server import app, container

    class _NoMaps:
        enabled = False

    monkeypatch.setattr(container, "google_maps_service", _NoMaps())
    from app.api.routes import health

    health._MAPS_HEALTH.clear()
    body = TestClient(app).get("/health/integrations").json()
    names = {r["integration"]: r["state"] for r in body["items"]}
    assert names["Google Maps"] == "NOT_CONFIGURED"
    assert "Firebase push" in names and "Web search (Brave)" in names
    text = str(body).lower()
    for secret_word in ("api_key=", "secret", "private_key", "bearer"):
        assert secret_word not in text
    health._MAPS_HEALTH.clear()
