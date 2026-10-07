from app.services.conversation_relation import ConversationRelationEngine

engine = ConversationRelationEngine()

def classify(text, subject="wedding gift", **kwargs):
    return engine.classify(user_text=text, active_subject=subject, active_facts={"subject": subject}, **kwargs)

def test_constraint_refines_active_need():
    r = classify("Meesho lo ivva")
    assert r.relation == "refinement"
    assert r.resolve_new_need(True) is False

def test_budget_fragment_refines():
    assert classify("around ₹5000").relation == "refinement"

def test_option_action_is_not_new_need():
    r = classify("second one details please")
    assert r.relation == "result_action"
    assert not r.resolve_new_need(True)

def test_explicit_switch_retires_deck():
    r = classify("forget that, I need home nursing")
    assert r.relation == "new_topic"
    assert r.subject_replaced
    assert r.resolve_new_need(False)

def test_independent_subject_retires_old_deck():
    r = classify("Andhra Pradesh famous temples", subject="leather ball tennis ball videos")
    assert r.relation == "new_topic"
    assert r.subject_replaced

def test_same_subject_survives():
    r = classify("wedding gift options")
    assert r.relation == "same_topic"
    assert not r.subject_replaced

def test_comparison_current_options_survives():
    r = classify("compare these side by side", subject="leather ball tennis ball")
    assert r.relation == "comparison"
    assert not r.subject_replaced

def test_new_comparison_replaces_unrelated_deck():
    r = classify("mutual fund vs FD", subject="aquarium filter")
    assert r.relation == "comparison"
    assert r.subject_replaced

def test_source_refinement_is_generic():
    r = classify("Meesho lo ivva", shown_sources=["Meesho", "Amazon"])
    assert r.relation == "refinement"

def test_random_unseen_categories_are_not_hard_coded():
    for old, new in [
        ("violin classes", "second hand tractor"),
        ("home nursing", "aquarium filter"),
        ("mutual fund FD", "rice purchase"),
    ]:
        r = classify(new, subject=old)
        assert r.relation == "new_topic"
        assert r.subject_replaced

def test_telugu_new_topic():
    r = classify("నాకు అక్వేరియం ఫిల్టర్ కావాలి", subject="వయోలిన్ క్లాసులు")
    assert r.relation == "new_topic"
    assert r.subject_replaced

def test_mixed_language_constraint():
    r = classify("local lo under ₹3000 kavali", subject="office chair")
    assert r.relation == "refinement"

def test_hinglish_constraint():
    r = classify("online me under 5000 chahiye", subject="birthday gift")
    assert r.relation == "refinement"

def test_return_to_previous_topic():
    r = engine.classify(user_text="violin classes", active_subject="rice purchase",
        active_facts={"subject": "rice purchase"},
        recent_user_turns=["violin classes", "home nursing", "rice purchase"])
    assert r.relation == "return_to_previous"
    assert r.subject_replaced

def test_no_deck_does_not_invent_new_topic():
    r = engine.classify(user_text="aquarium filter", recent_user_turns=[])
    assert r.relation == "unknown"
    assert not r.has_active_deck
