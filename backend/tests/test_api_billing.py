"""API Health & Billing: real balances only from the provider, labelled
estimates from a budget, UNKNOWN otherwise; failure types; deduplicated
20/10/5/0 alerts, spikes and repeated failures; ack / resolve; no secrets,
never a recharge."""
import dataclasses
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.services import api_billing as billing
from app.services import provider_health

NOW = datetime(2026, 10, 8, 12, 0, tzinfo=timezone.utc)


class _Brave:
    def __init__(self, state="ok", remaining=1500, limit=2000, code=200):
        self.snap = {"state": state, "http_status": code, "at": "2026-10-08T11:59:00+00:00",
                     "last_ok_at": "2026-10-08T11:00:00+00:00",
                     "rate": {"limit": [20, limit], "remaining": [19, remaining], "reset": [1, 86400 * 3]}}

    def health_snapshot(self):
        return dict(self.snap)


def _container(brave):
    return SimpleNamespace(brave_web_search_provider=brave, web_search_chain=None)


def _rows(**calls_by_day):
    return [{"day": day.replace("_", "-"), "provider": "brave", "calls": calls, "cache_hits": 0, "errors": errors}
            for day, (calls, errors) in calls_by_day.items()]


def test_brave_balance_is_provider_reported_others_unknown(tmp_path):
    provider_health.reset()
    data = billing.overview(_container(_Brave(remaining=300, limit=2000)), str(tmp_path / "b.db"), now=NOW,
                            usage_rows=_rows(**{"2026_10_08": (40, 0)}))
    rows = {r["provider"]: r for r in data["providers"]}
    brave = rows["brave"]
    assert brave["state"] == "LIVE" and brave["credits"]["source"] == "provider"
    assert brave["credits"]["remaining_pct"] == 15.0 and brave["credits"]["reset_at"].startswith("2026-10-11")
    assert brave["usage"]["daily"]["calls"] == 40
    assert brave["cost"]["estimated_inr"]["label"].startswith("estimate")
    assert brave["cost"]["actual_inr"] is None and "UNKNOWN" in brave["cost"]["actual_label"]
    assert rows["openai"]["credits"]["source"] == "unknown" and rows["openai"]["credits"]["remaining_pct"] is None
    assert "never recharges" in data["recharge_policy"]
    assert "key" not in str(data).lower().replace("monkey", "")


def test_failure_types_are_distinguished(tmp_path):
    provider_health.reset()
    provider_health.record("sarvam_tts", status_code=402, reason="payment required")
    provider_health.record("openai", status_code=401, reason="AuthenticationError")
    provider_health.record("gemini", status_code=429, reason="TooManyRequests")
    data = billing.overview(_container(_Brave(state="error", code=503)), str(tmp_path / "b.db"), now=NOW,
                            usage_rows=[])
    kinds = {r["provider"]: r["failure_type"] for r in data["providers"]}
    assert kinds["sarvam"] == "billing_quota"
    assert kinds["openai"] == "credential"
    assert kinds["gemini"] == "rate_limit"
    assert kinds["brave"] == "downtime"
    provider_health.reset()


def test_budget_gives_a_labelled_estimate_and_alerts_dedupe(tmp_path):
    provider_health.reset()
    db = str(tmp_path / "b.db")
    billing.save_settings(db, "brave", actor="owner", monthly_budget_inr=100, reset_day=1)
    brave = _Brave()
    brave.snap["rate"] = {}  # no headers: fall back to the budget estimate
    usage = _rows(**{"2026_10_08": (200, 0)})  # 200 x 0.42 = 84 of 100 -> 16% left
    data = billing.overview(_container(brave), db, now=NOW, usage_rows=usage)
    credits = {r["provider"]: r for r in data["providers"]}["brave"]["credits"]
    assert credits["source"] == "estimate" and "ESTIMATE" in credits["label"]
    assert credits["remaining_pct"] == 16.0

    first = billing.scan(_container(brave), db, now=NOW, usage_rows=usage)
    assert "brave:remaining:20" in first["created"]
    assert "brave:spike" in first["created"], "200 calls today vs nothing before"
    again = billing.scan(_container(brave), db, now=NOW, usage_rows=usage)
    assert again["created"] == [], "each alert once per period"
    alert = next(a for a in again["alerts"] if a["kind"] == "low_balance")
    assert "estimate" in alert["message"] and "never recharges" in alert["message"]

    assert billing.act(db, alert["id"], "acknowledge", actor="owner")["status"] == "ACKNOWLEDGED"
    assert billing.act(db, alert["id"], "resolve", actor="owner")["status"] == "RESOLVED"
    assert all(a["id"] != alert["id"] for a in billing.alerts(db))

    worse = _rows(**{"2026_10_08": (238, 0)})  # 0.4% left -> the 0% band is a NEW alert
    assert "brave:remaining:0" in billing.scan(_container(brave), db, now=NOW, usage_rows=worse)["created"]


def test_repeated_failures_alert(tmp_path):
    provider_health.reset()
    usage = _rows(**{"2026_10_08": (8, 6)})
    out = billing.scan(_container(_Brave()), str(tmp_path / "b.db"), now=NOW, usage_rows=usage)
    assert "brave:failures" in out["created"]


def test_admin_api_permissions_and_no_recharge(monkeypatch):
    from server import app, container

    key = "owner-bill-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    client = TestClient(app)
    assert client.get("/admin/cc/api-billing").status_code == 401
    body = client.get("/admin/cc/api-billing", headers={"X-ASKODOX-Admin-Key": key}).json()
    assert {r["provider"] for r in body["providers"]} >= {"brave", "gemini", "openai", "sarvam", "google_maps"}
    assert all("_history" not in r for r in body["providers"])
    assert client.put("/admin/cc/api-billing/brave", headers={"X-ASKODOX-Admin-Key": key},
                      json={"dashboard_url": "http://x"}).status_code == 422
    assert client.put("/admin/cc/api-billing/nope", headers={"X-ASKODOX-Admin-Key": key},
                      json={}).status_code == 404
    assert client.post("/admin/cc/api-billing/scan", headers={"X-ASKODOX-Admin-Key": key}).status_code == 200
    routes = {getattr(r, "path", "") for r in app.routes}
    assert not any("recharge" in p or "topup" in p for p in routes), "no automatic recharge endpoint exists"
