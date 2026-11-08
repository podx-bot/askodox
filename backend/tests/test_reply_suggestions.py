"""Smart Answer chips (owner 2026-11-08): the ONE brain returns 2-5 short tap-able
next things to say; only app builds sending the ``suggestions`` capability get
them, and cleaning is universal (no category lists)."""
import json
from types import SimpleNamespace

from app.services import reply_suggestions as rs
from app.services import universal_ai_assistant_service as svc


class _Models:
    def __init__(self, body):
        self.prompts = []
        self.body = body

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        return SimpleNamespace(text=json.dumps(self.body, ensure_ascii=False))


def _brain(**extra):
    body = {"reply": "ఏ budget లో చూడాలి?", "domain": "PRODUCT", "transactional": False,
            "action": "ask_detail", "confidence": 0.9, "entities": {"subject": "phone"},
            "suggestions": ["₹10k లోపు", "₹15–20k", "₹25k+", "Camera best"]}
    body.update(extra)
    models = _Models(body)
    return svc.UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=models)), models


# ---------------------------------------------------------------- cleaning --
def test_clean_keeps_short_distinct_chips_in_order():
    assert rs.clean(["Compare top 2", "compare top 2", " Nearby shop ", "Review video"]) == [
        "Compare top 2", "Nearby shop", "Review video"]


def test_clean_caps_at_five_and_needs_two():
    many = [f"Option {c}" for c in "ABCDEFG"]
    assert rs.clean(many) == many[:5]
    assert rs.clean(["Only one"]) == []
    assert rs.clean("not a list") == []
    assert rs.clean(None) == []


def test_clean_drops_links_numbers_long_text_and_done_claims():
    out = rs.clean([
        "Open https://x.example", "Call 98765 43210", "Order booked", "a" * 41,
        "one two three four five six seven", "", 7, True, {"a": 1},
        "₹10,000-20,000", "Battery best", "బుక్ చేశాను",
    ])
    assert out == ["7", "₹10,000-20,000", "Battery best"]


def test_clean_never_repeats_the_reply_itself():
    assert rs.clean(["Yes", "No", "Show me"], reply="show me") == ["Yes", "No"]


def test_works_for_any_category_and_language():
    for chips in (["Under ₹500", "Same day"], ["1 BHK", "2 BHK", "Near metro"],
                  ["రేపు ఉదయం", "ఈ రోజు సాయంత్రం"], ["कल सुबह", "आज शाम"]):
        assert rs.clean(chips) == chips


# ------------------------------------------------------------------ brain --
def test_old_apps_get_no_prompt_block_and_no_field():
    brain, models = _brain()
    out = brain.decide("phone kavali", capabilities=["meaning_tags"])
    assert "suggestions" not in out
    assert "Smart answer style" not in models.prompts[-1]


def test_new_apps_get_the_rules_and_clean_chips():
    brain, models = _brain()
    out = brain.decide("phone kavali", capabilities=["meaning_tags", rs.CAPABILITY])
    assert out["suggestions"] == ["₹10k లోపు", "₹15–20k", "₹25k+", "Camera best"]
    prompt = models.prompts[-1]
    assert "Smart answer style" in prompt and "key suggestions" in prompt
    assert "only when LIVE WEB EVIDENCE" in prompt  # the tip needs evidence


def test_missing_or_bad_chips_add_nothing():
    brain, _ = _brain(suggestions=None)
    assert "suggestions" not in brain.decide("phone kavali", capabilities=[rs.CAPABILITY])
    brain, _ = _brain(suggestions=["https://spam.example", "ok"])
    assert "suggestions" not in brain.decide("phone kavali", capabilities=[rs.CAPABILITY])


def test_clarify_need_keeps_its_own_options_not_chips():
    brain, _ = _brain(action="clarify_need",
                      entities={"subject": "tablet", "clarify_options": ["Tablet device", "Medicine tablet"]})
    assert "suggestions" not in brain.decide("tablet kavali", capabilities=[rs.CAPABILITY])


def test_fixed_reply_paths_drop_chips_written_for_another_reply():
    brain, _ = _brain(reply="Sure.")
    out = brain.decide("phone review videos chupinchu", capabilities=[rs.CAPABILITY])
    assert out["action"] == "search_videos"
    assert "suggestions" not in out


# ------------------------------------------------------------------ route --
def test_route_carries_suggestions_and_defaults_to_empty(monkeypatch):
    from fastapi.testclient import TestClient

    from server import app, container

    calls = []

    def decide(message, **kwargs):
        calls.append(kwargs.get("capabilities"))
        base = {"reply": "ok", "domain": "GENERAL", "transactional": False, "action": "chat",
                "confidence": 0.9, "entities": {}, "mode": "chat"}
        if rs.CAPABILITY in (kwargs.get("capabilities") or ()):
            base["suggestions"] = ["Yes", "No"]
        return base

    monkeypatch.setattr(container.universal_ai_assistant_service, "decide", decide, raising=False)
    client = TestClient(app)
    new = client.post("/api/in-app/assistant", json={"message": "hi", "capabilities": [rs.CAPABILITY]}).json()
    old = client.post("/api/in-app/assistant", json={"message": "hi"}).json()
    assert calls[0] == [rs.CAPABILITY]
    assert new["suggestions"] == ["Yes", "No"]
    assert old["suggestions"] == []
