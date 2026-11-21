"""Friend reasoning (owner 2026-11-21): every answer carries its logic the way
a practical friend's advice does. Five category-free ways of thinking and one
answer shape, in the ONE brain and in the advisory answer -- never a script
for one product."""
import json
from types import SimpleNamespace

import pytest

from app.services import universal_ai_assistant_service as svc

# The owner's own examples first, then one per way of thinking and domain.
CASES = [
    ("fit", "4 పొయ్యల గ్యాస్ స్టవ్ కొనాలా? ఇంట్లో ముగ్గురం, గట్టు చిన్నది, బండి మీద తీసుకెళ్ళాలి"),
    ("fit", "ఇద్దరికే ఇల్లు, 300 లీటర్ల ఫ్రిజ్ తీసుకోవాలా?"),
    ("fit", "should I buy a 1.5 ton AC for a 100 sq ft room?"),
    ("backward", "నెలకు 20000 సంపాదించాలి, టిఫిన్ బండి పెడితే రోజుకు ఎంత అమ్మాలి?"),
    ("backward", "help me plan: daughter's wedding in 8 months, budget 5 lakh"),
    ("another_way", "కాటన్ చీర 800 లోపు దొరకడం లేదు, 950 పెట్టి తీసుకోవాలా?"),
    ("another_way", "should I wait if a bank loan is rejected, or is there another way to start the shop?"),
    ("who_pays", "వ్యాపారం నష్టంలో నడుస్తోంది, మూసేస్తే జనం నవ్వుతారు. should I close it?"),
    ("who_pays", "is it wise to spend 3 lakh on a function only because relatives expect it?"),
    ("turn_around", "should I buy a second-hand bike now or wait 6 months?"),
    ("turn_around", "is it worth leaving my job to run the shop full time?"),
]


class _Models:
    def __init__(self):
        self.prompts = []

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        return SimpleNamespace(text=json.dumps({
            "reply": "3 burners are enough for you.", "domain": "GENERAL", "transactional": False,
            "action": "answer", "confidence": 0.9, "entities": {},
            "state": {"goal": "", "facts": {}, "flexible": [], "unknown_critical": []},
            "search_ready": False, "search_subject": "", "next_question": None}))


def _brain():
    models = _Models()
    return svc.UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=models)), models


def test_rule_has_the_five_ways_and_the_answer_shape():
    rule = svc.FRIEND_REASONING_RULES
    for must in ("every domain, every language", "Fit to their life", "Work backwards", "Another way",
                 "Who really pays", "Turn it around", "the verdict first", "use a fact THEY gave",
                 "never stop at 'not available'", "asks about their situation, not about specifications",
                 "The choice stays theirs", "never tilted toward a costlier option, a listing or a partner link",
                 "never name these methods to the user"):
        assert must in rule, must


def test_rule_is_not_a_script_for_one_product():
    lowered = svc.FRIEND_REASONING_RULES.lower()
    for banned in ("stove", "burner", "saree", "fridge", "phone", "meesho", "amazon"):
        assert banned not in lowered, banned


@pytest.mark.parametrize("way,message", CASES)
def test_every_turn_reasons_like_a_friend(way, message):
    brain, models = _brain()
    brain.decide(message, history=[])
    assert models.prompts, way
    assert svc.DECISION_GUIDANCE_RULES + svc.FRIEND_REASONING_RULES in models.prompts[0], way
    for prompt in models.prompts[1:]:  # a how-to guide keeps its own shape; an advisory answer reasons the same way
        if "decision advisor for people in India" in prompt:
            assert svc.FRIEND_REASONING_RULES in prompt, way


def test_advisory_answer_puts_the_verdict_before_the_working():
    brain, models = _brain()
    brain.decide("should I close my loss-making business? people will laugh", history=[])
    advisory = [p for p in models.prompts if "decision advisor for people in India" in p]
    assert advisory, "an advice question gets the advisory answer"
    assert "the verdict sentence comes before heading 1" in advisory[0]


def test_how_to_guides_keep_their_own_shape():
    assert "Friend reasoning" not in svc.GUIDE_ANSWER_RULES
