"""Conversation relation, Meta/video routing and comparison-entity safety.

Generic grammar signals only: every case below is a SHAPE (thin refinement,
stated new need, return to an older need, choice question, option action,
cross-script follow-up), exercised with several unrelated categories so no
single example phrase can be special-cased.
"""
import json

import pytest

from app.services.comparison_entities import comparison_candidates, is_entity_label, named_comparison_entities
from app.services.conversation_relation import ConversationRelation, ConversationRelationEngine
from app.services.universal_ai_assistant_service import UniversalAIAssistantService

engine = ConversationRelationEngine()


def rel(text, subject, history=(), aliases=(), places=()):
    return engine.classify(user_text=text, active_subject=subject, active_facts={"subject": subject},
                           recent_user_turns=list(history) + [text], subject_aliases=aliases,
                           location_labels=places)


# ------------------------------------------------------------------ relation --

@pytest.mark.parametrize("subject", ["refurbished mobile phones", "wedding gift", "home nursing service",
                                     "second hand tractor", "office chair"])
@pytest.mark.parametrize("text", ["sasta wala dikhao", "cheaper ones", "under 15000", "multi use",
                                  "ఇంకా చౌకగా ఉన్నవి చూపించు", "30-40 వేలు", "online me under 5000 chahiye",
                                  "local lo under ₹3000 kavali", "మా ఇంటికి delivery కావాలి"])
def test_thin_refinement_keeps_the_active_need(subject, text):
    r = rel(text, subject)
    assert r.relation == "refinement", (subject, text, r)
    assert not r.subject_replaced and r.resolve_new_need(True) is False


@pytest.mark.parametrize("text", ["ok", "OK", "yes", "okay", "సరే", "అవును", "haan", "thanks"])
def test_acknowledgement_after_results_is_the_same_need(text):
    r = rel(text, "refurbished mobile phones")
    assert r.relation == "same_topic" and not r.subject_replaced and r.resolve_new_need(True) is False


@pytest.mark.parametrize("subject,text", [
    ("refurbished mobile phones", "buy rice 25 kg"),
    ("violin classes", "I want to buy a laptop"),
    ("wedding gift", "need a plumber tomorrow morning"),
    ("aquarium filter", "insurance for my car"),
])
def test_a_different_subject_is_a_new_topic_signal(subject, text):
    r = rel(text, subject)
    assert r.relation == "new_topic" and r.subject_replaced


def test_option_action_needs_an_option_reference_not_just_a_verb():
    assert rel("call the second one", "office chair").relation == "result_action"
    assert rel("directions", "office chair").relation == "result_action"
    # "buy" alone is no longer an option action when a NEW thing is named.
    assert rel("buy rice 25 kg", "office chair").relation == "new_topic"


@pytest.mark.parametrize("subject,old,back", [
    ("rice 25 kg", "refurbished phone under 20000", "back to the phones"),
    ("home nursing", "violin classes for my son", "violin classes again"),
    ("aquarium filter", "wedding gift ideas", "malli wedding gift"),
])
def test_return_to_previous_topic(subject, old, back):
    r = rel(back, subject, history=[old, "something else", subject])
    assert r.relation == "return_to_previous" and r.subject_replaced


def test_generic_constraint_does_not_hijack_a_better_history_match():
    # The constraint words are generic, the content names an older need.
    r = rel("phone under 20000 local lo", "rice 25 kg", history=["refurbished phone under 20000", "buy rice 25 kg"])
    assert r.relation == "return_to_previous"
    # A pure constraint never matches history through the generic words.
    r = rel("under 15000", "refurbished mobile phones", history=["I need a refurbished phone under 20000"])
    assert r.relation == "refinement"


def test_cross_script_follow_up_is_never_new_only_because_overlap_is_zero():
    for text in ["ఏది మంచిది?", "దీని ధర ఎంత?", "రెండో దాని వివరాలు", "Godrej okay, ఇతర మంచి బ్రాండ్లు కూడా okay"]:
        r = rel(text, "large 2 door iron almirah")
        assert not (r.relation == "new_topic" and r.confidence >= 0.7), (text, r)
    # Telugu need against the customer's own Telugu wording of the active need.
    r = rel("నాకు బియ్యం 25 కేజీలు కావాలి", "large 2 door iron almirah", aliases=["నాకు ఒక ఐరన్ బీరువా కావాలి"])
    assert r.relation == "new_topic" and r.subject_replaced


def test_choice_question_compares_the_options_on_screen():
    for text in ["which one is better", "ఏది మంచిది?", "kaunsa better hai"]:
        r = rel(text, "refurbished mobile phones")
        assert r.relation == "comparison" and not r.subject_replaced, (text, r)


# ---------------------------------------------- reconcile with the model -----

def _r(relation, conf, replaced=False):
    return ConversationRelation(relation, conf, True, subject_replaced=replaced)


def test_weak_new_topic_counts_only_when_the_model_agrees():
    weak = _r("new_topic", 0.6, True)
    brain = {"state": {"goal": "Samsung phone"}, "search_subject": None}
    assert UniversalAIAssistantService.reconcile_relation(weak, False, brain, "mobile phones") == ("unknown", False)
    assert UniversalAIAssistantService.reconcile_relation(weak, True, brain, "mobile phones") == ("new_topic", True)


def test_model_new_need_with_a_disjoint_description_retires_the_old_need():
    unknown = _r("unknown", 0.35)
    brain = {"state": {"goal": "buy 25 kg rice", "facts": {"item": "rice"}}, "search_subject": "rice 25 kg"}
    assert UniversalAIAssistantService.reconcile_relation(unknown, True, brain, "iron almirah") == ("new_topic", True)
    same = {"state": {"goal": "iron almirah with locker"}, "search_subject": "iron almirah"}
    assert UniversalAIAssistantService.reconcile_relation(unknown, True, same, "iron almirah") == ("unknown", False)
    # The model did not say "new need": nothing changes.
    assert UniversalAIAssistantService.reconcile_relation(unknown, False, brain, "iron almirah") == ("unknown", False)


# ------------------------------------------------------ Meta / video routing --

class _Resp:
    def __init__(self, text):
        self.text = text


class _Models:
    def __init__(self, reply):
        self.reply = reply
        self.calls = []

    def generate_content(self, *, model, contents, config):
        self.calls.append(contents)
        return _Resp(self.reply)


class _Client:
    def __init__(self, reply):
        self.models = _Models(reply)


def _svc(**decision):
    data = {"reply": decision.pop("reply", "Sure."), "domain": decision.pop("domain", "GENERAL"),
            "transactional": decision.pop("transactional", False), "action": decision.pop("action", "chat"),
            "confidence": 0.9, "entities": decision.pop("entities", {}), **decision}
    return UniversalAIAssistantService(delegate=None, api_key="k", model="m", client=_Client(json.dumps(data)))


META_HISTORY = [
    {"role": "user", "text": "How do I connect my Instagram business account to Meta for ASKODOX?"},
    {"role": "assistant", "text": "You need a Facebook Page, a Meta app and App Review for messaging."},
]


@pytest.mark.parametrize("text", [
    "facebook and instagram videos kuda chupinchali ga",
    "instagram reels kuda app lo play avvala?",
    "Meta API setup lo videos permission kavala?",
    "can youtube videos also show in the app",
])
def test_platform_and_video_setup_talk_stays_conversation(text):
    svc = _svc(reply="Yes -- after the Meta app review the app can play them.")
    out = svc.decide(text, locale="en", history=META_HISTORY)
    assert out["mode"] == "chat" and out["transactional"] is False
    assert out["action"] != "search_videos" and out["search_ready"] is not True
    assert "looking for real videos" not in out["reply"]


@pytest.mark.parametrize("text", ["Samsung S23 review videos", "show me Godrej almirah unboxing videos",
                                  "instagram reels of the Samsung S23 camera"])
def test_a_real_video_search_still_searches(text):
    out = _svc().decide(text, locale="en")
    assert out["action"] == "search_videos" and out["transactional"] is True and out["search_ready"] is True


def test_show_videos_about_the_need_on_screen_still_searches():
    out = _svc().decide("show me videos", locale="en", searched_for={"subject": "office chair"})
    assert out["action"] == "search_videos"


# ------------------------------------------------- comparison entity safety --

@pytest.mark.parametrize("label", ["in Vuyyuru, Andhra Pradesh", "near Benz Circle", "Vijayawada లో", "under ₹20,000",
                                   "₹15,999", "Sponsored", "In stock", "Online", "the other options", "Not verified",
                                   "  ", "12345"])
def test_metadata_is_never_a_comparison_entity(label):
    assert not is_entity_label(label, location_labels=["Vuyyuru, Andhra Pradesh"])


@pytest.mark.parametrize("label", ["Samsung Galaxy S23", "Godrej Interio 2-door almirah", "Sri Sai Plumbing Works",
                                   "LIC Jeevan Anand", "Hyderabad to Goa flight", "Mutual fund"])
def test_real_things_remain_comparable(label):
    assert is_entity_label(label, location_labels=["Vuyyuru, Andhra Pradesh"])


def test_comparison_candidates_drop_location_metadata():
    text = 'Compare "in Vuyyuru, Andhra Pradesh" with the other options'
    assert comparison_candidates(text)  # it does name phrases ...
    assert named_comparison_entities(text) == []  # ... none of them is a thing
    assert named_comparison_entities("mutual fund vs FD") == ["mutual fund", "FD"]
    r = rel(text, "refurbished mobile phones", places=["Vuyyuru, Andhra Pradesh"])
    assert r.relation == "comparison" and not r.subject_replaced


def test_location_comparison_is_answered_from_shown_options_not_searched():
    svc = _svc(reply="Here is how they compare.", transactional=True, action="search", domain="PRODUCT",
               entities={"subject": "in Vuyyuru"})
    out = svc.decide('Compare "in Vuyyuru, Andhra Pradesh" with the other options', locale="en",
                     searched_for={"subject": "refurbished mobile phones", "location": "Vuyyuru, Andhra Pradesh"})
    assert out["mode"] == "follow_up" and out["search_ready"] is False and out["subject_changed"] is False
