"""One-time advice rule: Understand -> Reason -> Advise ONCE -> Respect the
decision -> Continue helping. The brain is the existing decide() (one
engine); the ledger keeps it honest in any category and language."""
import dataclasses
import json
import uuid
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.services import advice_memory as am
from app.services import assistant_health


@pytest.fixture(autouse=True)
def _clean():
    assistant_health.reset()
    yield
    assistant_health.reset()


BATTERY = {"key": "Battery Health", "summary": "Used phones under 80% battery health need a replacement soon",
           "severity": "caution"}


def test_first_concern_is_recorded_once():
    advice, ledger = am.review(BATTERY, [])
    assert advice["key"] == "battery_health" and advice["repeated"] is False and advice["allowed"] is True
    assert ledger == [{"key": "battery_health", "summary": BATTERY["summary"], "severity": "caution", "times": 1}]


def test_repeating_the_same_warning_without_reason_is_flagged():
    _, ledger = am.review(BATTERY, [])
    again, ledger = am.review(dict(BATTERY), ledger)
    assert again["repeated"] is True and again["allowed"] is False
    assert ledger[0]["times"] == 2 and len(ledger) == 1


def test_renamed_key_with_the_same_concern_is_still_a_repeat():
    _, ledger = am.review(BATTERY, [])
    again, _ = am.review({"key": "battery_replacement", "summary": "Used phones under 80% battery health need "
                          "a battery replacement soon", "severity": "caution"}, ledger)
    assert again["repeated"] is True and again["key"] == "battery_health"


@pytest.mark.parametrize("reason", ["new_information", "user_asked"])
def test_a_justified_repeat_is_allowed(reason):
    _, ledger = am.review(BATTERY, [])
    again, ledger = am.review({**BATTERY, "summary": "Battery at 62% now: replace within weeks",
                               "repeat_reason": reason}, ledger)
    assert again["repeated"] is True and again["allowed"] is True and again["repeat_reason"] == reason
    if reason == "new_information":
        assert ledger[0]["summary"] == "Battery at 62% now: replace within weeks", "updated advice is remembered"


def test_critical_risks_are_never_suppressed():
    risk = {"key": "gas_leak", "summary": "Smell of gas: switch off the cylinder and ventilate", "severity": "critical"}
    _, ledger = am.review(risk, [])
    again, _ = am.review(dict(risk), ledger)
    assert again["allowed"] is True and again["repeat_reason"] == "critical"


def test_no_concern_and_garbage_are_ignored():
    assert am.review(None, []) == (None, [])
    assert am.review({"summary": "no key"}, [])[0] is None
    ledger = am.sanitize_ledger([{"key": "a", "severity": "weird"}, "x", {"key": "a"}, {"key": ""}])
    assert ledger == [{"key": "a", "summary": "", "severity": "info", "times": 1}]
    assert len(am.sanitize_ledger([{"key": f"k{i}"} for i in range(40)])) == am.MAX_LEDGER


def test_prompt_block_carries_the_rule_and_the_ledger():
    block = am.prompt_block([{"key": "battery_health", "summary": "s", "severity": "caution", "times": 1}])
    assert "ONE-TIME ADVICE RULE" in block and "battery_health" in block
    assert "respect the user's decision" in block and "critical" in block
    assert "ADVICE ALREADY GIVEN: none" in am.prompt_block([])


def test_advisory_meta_line_is_removed_before_display():
    text, meta = am.split_meta("Advice body.\nADVICE_META: {\"key\": \"emi_burden\", \"severity\": \"caution\"}")
    assert text == "Advice body." and meta["key"] == "emi_burden"
    assert am.split_meta("No meta here") == ("No meta here", None)
    assert am.split_meta("Body\nADVICE_META: null") == ("Body", None)


class _Models:
    def __init__(self, payload):
        self.payload, self.prompts = payload, []

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        return SimpleNamespace(text=json.dumps(self.payload))


def _brain(payload):
    from app.services.universal_ai_assistant_service import UniversalAIAssistantService

    models = _Models(payload)
    return UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=models)), models


def _payload(advice):
    return {"reply": "Okay, a used phone can work. Check the battery health before paying.", "domain": "GENERAL",
            "transactional": False, "action": "chat", "confidence": 0.9, "entities": {}, "advice": advice}


def test_decide_sends_the_ledger_and_returns_the_review():
    brain, models = _brain(_payload(BATTERY))
    first = brain.decide("I want a used iPhone 11", history=[])
    assert first["advice"]["repeated"] is False and first["advice_ledger"][0]["key"] == "battery_health"
    second = brain.decide("I've decided, I'll take the used one", history=[],
                          advice_given=first["advice_ledger"])
    assert "battery_health" in models.prompts[-1], "the ledger reaches the brain"
    assert second["advice"]["repeated"] is True and second["advice"]["allowed"] is False
    assert assistant_health.components()[2]["status"] == "degraded", "a repeat is counted for the Command Center"


def test_decide_without_a_concern_keeps_the_ledger():
    brain, _ = _brain(_payload(None))
    ledger = [{"key": "battery_health", "summary": "s", "severity": "caution", "times": 1}]
    out = brain.decide("ok thanks", history=[], advice_given=ledger)
    assert out["advice"] is None and out["advice_ledger"] == ledger


def test_assistant_route_round_trips_the_ledger(monkeypatch):
    from server import app, container

    seen = {}

    class _Brain:
        def decide(self, message, **kwargs):
            seen.update(kwargs)
            return {"reply": "Sure.", "domain": "GENERAL", "transactional": False, "action": "chat",
                    "confidence": 0.9, "entities": {}, "advice": None,
                    "advice_ledger": kwargs.get("advice_given") or []}

    monkeypatch.setattr(container, "universal_ai_assistant_service", _Brain())
    ledger = [{"key": "battery_health", "summary": "s", "severity": "caution", "times": 1}]
    body = TestClient(app).post("/api/in-app/assistant", json={"message": "ok", "advice_given": ledger}).json()
    if body["source"] == "universal_ai":  # ai.assistant flag on in this DB
        assert seen["advice_given"] == ledger and body["advice_ledger"] == ledger
        assert assistant_health.component_state("conversation_intelligence")["status"] == "ok"


def test_cc_health_lists_assistant_components_without_fake_green(monkeypatch):
    from server import app, container

    key = "owner-adv-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key))
    client = TestClient(app)
    comps = {c["name"]: c for c in client.get("/admin/cc/health", headers={"X-ASKODOX-Admin-Key": key})
             .json()["components"]}
    for name in ("conversation_intelligence", "media_analysis", "advice_policy", "result_discovery"):
        assert name in comps
    assert comps["conversation_intelligence"]["status"] == "unknown", "no traffic is never LIVE"
    assistant_health.observe("media_analysis", False, "video_http_503")
    assistant_health.observe("media_analysis", True)
    comps = {c["name"]: c for c in client.get("/admin/cc/health", headers={"X-ASKODOX-Admin-Key": key})
             .json()["components"]}
    assert comps["media_analysis"]["status"] == "error" and "video_http_503" in comps["media_analysis"]["detail"]


def test_attachment_outcomes_are_observed(monkeypatch):
    import base64

    from server import app, container

    monkeypatch.setattr(container, "universal_image_service", None, raising=False)
    client = TestClient(app)
    body = {"file_base64": base64.b64encode(b"\x89PNGfake").decode(), "filename": "a.png", "mime_type": "image/png"}
    assert client.post("/api/attachments/analyze", json=body).status_code == 503
    state = assistant_health.component_state("media_analysis")
    assert state["status"] == "error" and state["samples"] == 1
    # A refused file type is the user's input, not a feature failure.
    client.post("/api/attachments/analyze", json={**body, "filename": "a.exe", "mime_type": "application/x-exe"})
    assert assistant_health.component_state("media_analysis")["samples"] == 1
