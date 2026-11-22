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
    # Odd / playful questions (owner's own list) and "the sum behind it".
    ("odd", "మొదటి భాష తయారు చేసినవాడు వేరేవాళ్ళకి ఏ భాషలో చెప్పాడు?"),
    ("odd", "పుట్టుకతో వినపడని వాళ్ళు ఏ భాషలో ఆలోచిస్తారు?"),
    ("odd", "దయ్యాలకు తెల్ల బట్టలు కొనిచ్చింది ఎవరు?"),
    ("odd", "ఏడిస్తే కన్నీళ్ళు రాలతాయి, నవ్వితే పళ్ళు ఎందుకు రాలవు?"),
    ("odd", "why is the phone camera round but the photo a rectangle?"),
    ("sum_behind", "బంగారం రేటు తగ్గినా పెరిగినా జ్యువెలరీ షాప్ వాళ్ళు ఎందుకు టెన్షన్ పడరు?"),
    ("sum_behind", "how does a free app make money?"),
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
                 "never name these methods to the user",
                 "Odd or playful questions", "never mock it", "three sentences at most",
                 "Never invent a fact to be funny", "stay respectful and say that traditions differ",
                 "The sum behind it", "what most people assume", "one small worked example",
                 "the one thing the person can do with it"):
        assert must in rule, must


def test_rule_is_not_a_script_for_one_product():
    lowered = svc.FRIEND_REASONING_RULES.lower()
    for banned in ("stove", "burner", "saree", "fridge", "phone", "meesho", "amazon", "gold", "jewel", "ghost"):
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


def _mode_prompt(capabilities):
    brain, models = _brain()
    brain.decide("బియ్యం 5 kg 60 రూపాయలు", history=[], capabilities=capabilities)
    return models.prompts[0]


def test_the_buy_sell_switch_tells_the_brain_which_side_the_person_is_on():
    buyer, seller = svc._MODE_RULES[svc.BUYER_MODE_CAPABILITY], svc._MODE_RULES[svc.SELLER_MODE_CAPABILITY]
    assert seller in _mode_prompt(["seller_mode"]) and buyer not in _mode_prompt(["seller_mode"])
    assert buyer in _mode_prompt(["buyer_mode"]) and seller not in _mode_prompt(["buyer_mode"])
    plain = _mode_prompt([])  # older builds have no switch: no mode line at all
    assert buyer not in plain and seller not in plain
    for rule in (buyer, seller):
        assert "never claim the mode was switched" in rule
    assert "never as something to buy" in seller


def test_a_one_tap_switch_is_offered_only_to_the_other_side():
    offer = svc.switch_mode_offer
    assert offer("seller", ["buyer_mode"]) == "seller"
    assert offer(" Seller ", ["buyer_mode"]) == "seller"
    assert offer("buyer", ["seller_mode", "shopping_tools"]) == "buyer"
    assert offer("seller", ["seller_mode"]) is None, "already on that side"
    assert offer("buyer", ["buyer_mode"]) is None
    assert offer("seller", []) is None, "older builds have no switch"
    assert offer("anything", ["buyer_mode"]) is None and offer(None, ["buyer_mode"]) is None
    assert 'switch_mode = "seller"' in svc._MODE_RULES[svc.BUYER_MODE_CAPABILITY]
    assert 'switch_mode = "buyer"' in svc._MODE_RULES[svc.SELLER_MODE_CAPABILITY]


def test_switch_offer_reaches_the_app_and_is_declared_on_the_response_model():
    from app.api.routes.in_app_assistant import AssistantDecision

    assert "switch_mode" in AssistantDecision.model_fields, "an undeclared field is dropped from every response"

    class _Switching(_Models):
        def generate_content(self, *, model, contents, config):
            self.prompts.append(contents)
            return SimpleNamespace(text=json.dumps({
                "reply": "Shop tools open in Seller mode.", "domain": "GENERAL", "transactional": False,
                "action": "answer", "confidence": 0.9, "entities": {}, "switch_mode": "seller",
                "state": {"goal": "", "facts": {}, "flexible": [], "unknown_critical": []},
                "search_ready": False, "search_subject": "", "next_question": None}))

    def decide(capabilities):
        brain = svc.UniversalAIAssistantService(None, api_key="g", model="m", client=SimpleNamespace(models=_Switching()))
        return brain.decide("నా షాప్ లో బిల్ వేయి", history=[], capabilities=capabilities) or {}

    assert decide(["buyer_mode"]).get("switch_mode") == "seller"
    assert "switch_mode" not in decide(["seller_mode"]), "never an offer to the side the app is already on"
    assert "switch_mode" not in decide([])


def test_results_stay_in_the_result_cards():
    brain, models = _brain()
    brain.decide("కాటన్ చీర 800 లోపు కావాలి", history=[])
    assert svc.RESULT_CARD_RULES in models.prompts[0]
    assert "never a list of shop names, items or prices in the reply text" in svc.RESULT_CARD_RULES


def test_a_how_to_answer_carries_the_friends_logic_inside_its_own_shape():
    rule = svc.GUIDE_FRIEND_RULES
    for must in ("the length limits above still hold", "the route that fits THEM", "never stop at 'not possible'",
                 "order the steps backwards from that result", "never named, never a lecture"):
        assert must in rule, must
    brain, models = _brain()
    brain.decide("how do I apply for Udyam registration? I run a small tiffin stall alone", history=[])
    guides = [p for p in models.prompts if svc.GUIDE_ANSWER_RULES in p]
    assert guides, "a how-to question gets the guide answer"
    assert all(svc.GUIDE_FRIEND_RULES in p for p in guides)
    assert all(svc.FRIEND_REASONING_RULES not in p for p in guides), "the long advisory rules stay out of a short guide"
