"""AXE executive brief: built only from the existing gate / incidents /
billing / registry / radio cost model; every line graded; recommends
catalog actions but never runs them; Telugu text; never READY in tests."""
import dataclasses
import uuid

from fastapi.testclient import TestClient

from app.services import admin_action_framework, executive_ai, travel_radio

GATE_PENDING = {"overall": "BLOCKED_ON_DEVICE_VERIFICATION", "conditions": [
    {"id": "approved_features_intact", "status": "PASS"},
    {"id": "real_phone_acceptance", "status": "PENDING", "evidence": "12 of 15 phone checks not PHONE VERIFIED"}]}
RED = {"key": "provider:brave:billing_quota", "severity": "red", "problem": "Brave: QUOTA_EXHAUSTED",
       "reason_confirmed": True, "evidence": ["state=QUOTA_EXHAUSTED, HTTP 402"],
       "ai_explanation": "Brave: QUOTA_EXHAUSTED. Confirmed: plan out of credit.",
       "proposed_action": "read:recheck:brave"}
BILLING = {"providers": [{"provider": "brave", "state": "QUOTA_EXHAUSTED",
                          "cost": {"estimated_inr": {"today": 1.0, "month": 120.5}}},
                         {"provider": "maps", "state": "LIVE", "cost": {"estimated_inr": {"month": 30}}}]}


def _brief(**kw):
    args = dict(gate=GATE_PENDING, incidents=[RED], billing=BILLING, radio_model=travel_radio.cost_model(),
                radio_plans=[{"code": "radio_1d", "active": False}], registry=[{"status": "approved"}] * 3,
                payments_configured=False, catalog=admin_action_framework.CATALOG)
    args.update(kw)
    return executive_ai.brief(**args)


def test_brief_grades_every_line_and_only_recommends_catalog_actions():
    out = _brief()
    assert out["overall"] == "BLOCKED_ON_DEVICE_VERIFICATION"
    grades = {f["grade"] for f in out["findings"]}
    assert grades <= {"CONFIRMED", "POSSIBLE", "ESTIMATE", "PENDING"}
    risk = next(f for f in out["findings"] if f["area"] == "risk")
    assert risk["grade"] == "CONFIRMED"
    assert risk["recommended_action"] == {"action": "recheck", "target": "brave", "risk": "read_only",
                                          "needs_approval": False}
    spend = next(f for f in out["findings"] if f["area"] == "spend")
    assert spend["grade"] == "ESTIMATE" and "150.5" in spend["text"]
    keys = {d["key"] for d in out["owner_decisions"]}
    assert keys == {"radio_pricing", "payment_gateway", "phone_acceptance"}
    assert any("12" in d["text"] for d in out["owner_decisions"] if d["key"] == "phone_acceptance")
    assert "never" in out["rule"]


def test_unknown_actions_are_dropped_and_quiet_state_is_said_plainly():
    odd = {**RED, "proposed_action": "change:delete_everything:1", "reason_confirmed": False}
    out = _brief(incidents=[odd], payments_configured=True, radio_plans=[{"code": "radio_1d", "active": True}])
    risk = next(f for f in out["findings"] if f["area"] == "risk")
    assert risk["recommended_action"] is None and risk["grade"] == "POSSIBLE"
    assert {d["key"] for d in out["owner_decisions"]} == {"phone_acceptance"}
    calm = _brief(incidents=[])
    assert any("No open red" in f["text"] for f in calm["findings"])


def test_radio_pricing_risk_is_reported_from_the_cost_model():
    out = _brief()
    pricing = [f for f in out["findings"] if f["area"] == "pricing"]
    assert pricing and all(f["grade"] == "ESTIMATE" for f in pricing)
    model = travel_radio.cost_model()
    losing = any(not p["covers_cost"] for r in model["profiles"] for p in r["plans"])
    assert any("does not cover" in f["text"] for f in pricing) == losing


def test_telugu_brief():
    out = _brief(lang="te")
    assert out["language"] == "te"
    assert any("రిలీజ్ గేట్" in f["text"] for f in out["findings"])


def test_admin_route_needs_staff_and_is_never_ready_in_tests(monkeypatch):
    from server import app, container

    key = "owner-axe-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    client = TestClient(app)
    assert client.get("/admin/cc/axe/brief").status_code == 401
    body = client.get("/admin/cc/axe/brief", headers={"X-ASKODOX-Admin-Key": key}).json()
    assert body["overall"] in ("NOT_READY", "BLOCKED_ON_DEVICE_VERIFICATION")
    assert body["findings"] and all("grade" in f for f in body["findings"])
