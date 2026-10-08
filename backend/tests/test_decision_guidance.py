"""Reasoning before results (APK 1311): the ONE brain must answer and guide
in every domain; result cards only support that answer. The tiles case is one
regression among unrelated categories, never a special rule."""
import json
from types import SimpleNamespace

import pytest

from app.services import universal_ai_assistant_service as svc


class _Models:
    def __init__(self):
        self.prompts = []

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        return SimpleNamespace(text=json.dumps({
            "reply": "For 100 sq ft plan about 110 sq ft (10% wastage); approx. Rs 60-150 per sq ft (estimate).",
            "domain": "PRODUCT", "transactional": True, "action": "search_products", "confidence": 0.9,
            "entities": {"subject": "vitrified tiles"}, "state": {"goal": "tiles", "facts": {}, "flexible": [],
                                                                  "unknown_critical": []},
            "search_ready": True, "search_subject": "vitrified tiles", "next_question": None}))


def _brain():
    models = _Models()
    return svc.UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=models)), models


def test_guidance_rule_is_universal_and_honest_about_estimates():
    rule = svc.DECISION_GUIDANCE_RULES
    for must in ("every domain", "THEIR numbers", "wastage", "general estimate", "never present it as a verified",
                 "at most ONE question", "Never name specific shops", "no forced guidance, no commerce"):
        assert must in rule, must
    for must in ("people and skills", "materials with quantities", "tools and equipment", "quotations",
                 "Never claim a quotation", "Never ask again for anything already said", "the app renders it",
                 "[ok]", "[caution]", "[risk]", "leave everything else untagged"):
        assert must in rule, must
    for banned in ("tile", "vitrified", "sq ft", "paint"):  # no category script hidden in the rule
        assert banned not in rule.lower()


def test_ready_turns_no_longer_ask_for_a_bare_acknowledgement():
    assert "reply = a short acknowledgement" not in svc.CONVERSATION_STATE_RULES
    assert "never a bare acknowledgement" in svc.CONVERSATION_STATE_RULES


@pytest.mark.parametrize("message", [
    "100 sq.ft. vitrified tiles, budget 10000-20000",          # product (regression case)
    "need a painter for 2BHK, budget 25000",                    # service
    "I want to start a tiffin centre with 2 lakh",              # business
    "personal loan 3 lakh for 3 years, what EMI?",              # finance
    "how should I plan my exam revision in 3 weeks?",           # personal / non-commerce
    "paint my 2BHK house, need workers and material list",      # project / manpower (regression)
    "plan a wedding for 300 guests in Guntur",                  # event
    "start drip irrigation on 2 acres",                         # agriculture
    "need 5 delivery boys for my shop for 2 weeks",             # workforce / employer
    "100 చదరపు అడుగుల విట్రిఫైడ్ టైల్స్ కావాలి",                  # Telugu
])
def test_every_domain_gets_the_guidance_rule(message):
    brain, models = _brain()
    out = brain.decide(message, history=[])
    brain_prompt = models.prompts[0]  # advice questions add a second (advisory) call
    assert svc.DECISION_GUIDANCE_RULES in brain_prompt and "ONE-TIME ADVICE RULE" in brain_prompt
    assert all("ONE-TIME ADVICE RULE" in prompt for prompt in models.prompts)
    assert out["reply"].startswith("For 100 sq ft"), "the brain's reasoning is the reply, never replaced"
