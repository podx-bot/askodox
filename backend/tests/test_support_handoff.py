"""Support handoff package: summary, request, category, previous actions,
status -- masked, built from the conversation only."""
from app.services import support_handoff


def test_handoff_summarises_without_contacts():
    h = support_handoff.build(issue="Seller not responding, call me 9876543210", category="ORDER", context={
        "conversation": [{"role": "user", "text": "need running shoes under 2000"},
                         {"role": "assistant", "text": "Here are options"},
                         {"role": "user", "text": "seller accepted but not replying, mail me a@b.com"}],
        "requirement": {"subject": "running shoes", "category": "footwear"},
        "deal_id": "42", "status": "ACCEPTED", "actions_tried": ["sent request", "messaged seller"],
        "ai_attempted": True, "active_role": "buyer", "locale": "te"})
    assert h["request"] == "running shoes" and h["request_category"] == "footwear"
    assert h["previous_actions"] == ["sent request", "messaged seller"] and h["status"] == "ACCEPTED"
    assert "9876543210" not in str(h) and "a@b.com" not in str(h)
    assert "running shoes" in h["summary"] and "deal/order 42" in h["summary"]
    assert h["suggested_next_step"].startswith("Check the deal") and h["language"] == "te"


def test_handoff_falls_back_to_first_message():
    h = support_handoff.build(issue="help", category="GENERAL",
                              context={"conversation": [{"role": "user", "text": "plumber today"}]})
    assert h["request"] == "plumber today" and h["previous_actions"] == []
