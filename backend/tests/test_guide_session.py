"""Guide session: adaptive questions, any time is accepted, consent / delete, reminders, feature-request inbox."""
import json

import pytest

from app.services.guide_session import FeatureRequests, GuideError, GuideSessions, TOPIC_KEYS, plan


def _svc(tmp_path, model=None):
    return GuideSessions(str(tmp_path / "g.db"), write_text=model)


def test_any_time_is_accepted_and_short_time_keeps_the_important_topics(tmp_path):
    assert plan(5) == ["who", "work", "wants", "pages"]
    assert "menu" in plan(30) and "money" not in plan(30)
    assert plan(120) == TOPIC_KEYS
    s = _svc(tmp_path)
    st = s.start("u1", 10)
    assert st["status"] == "running" and st["plan"] == ["who", "work", "wants", "pages"]
    out = s.pause("u1")
    assert out["status"] == "paused" and out["remaining"], "time up is never an error: the rest is kept for later"


def test_questions_follow_the_answer_from_the_model(tmp_path):
    seen = []

    def model(prompt):
        seen.append(prompt)
        return json.dumps({"understood": True, "facts": [{"key": "work", "value": "tailoring"}],
                           "question": "How do you tell customers their clothes are ready?", "explanation": ""})

    s = _svc(tmp_path, model)
    s.set_consent("u1", True)
    s.start("u1", 10)
    r = s.turn("u1", "I stitch clothes", "en")
    assert r["understood"] and r["topic"] == "work" and "ready" in r["question"]
    assert "I stitch clothes" in seen[0] and "Topic of the NEXT question" in seen[0]
    assert "never guessed" in seen[0] and "Never invent prices" in seen[0]
    assert s.facts("u1")[0]["value"] == "tailoring"


def test_not_understood_repeats_in_other_words_and_does_not_advance(tmp_path):
    def model(prompt):
        return json.dumps({"understood": True, "facts": [], "question": "Simpler: do you call or message them?",
                           "explanation": "I ask so I can set your pages. You can delete this any time."})

    s = _svc(tmp_path, model)
    s.start("u1", 10)
    first = s.status("u1")["current"]
    r = s.turn("u1", "what?", "en", not_understood=True)
    assert not r["understood"] and r["explanation"] and r["topic"] == first
    assert s.status("u1")["done"] == []


def test_without_a_model_a_plain_question_is_asked(tmp_path):
    s = _svc(tmp_path)
    s.start("u1", 10)
    r = s.turn("u1", "Asha", "te")
    assert r["understood"] and r["question"]
    assert s.turn("u1", "", "te", skip=True)["status"] in ("running", "finished")


def test_nothing_is_kept_without_consent_and_withdrawing_deletes(tmp_path):
    def model(prompt):
        return json.dumps({"understood": True, "facts": [{"key": "bike", "value": "Splendor"}], "question": "next", "explanation": ""})

    s = _svc(tmp_path, model)
    s.start("u1", 10)
    s.turn("u1", "I have a bike", "en")
    assert s.facts("u1") == [], "no consent, nothing kept"
    s.set_consent("u1", True)
    s.turn("u1", "I have a bike", "en")
    assert s.facts("u1")
    s.set_consent("u1", False)
    assert s.facts("u1") == []


def test_secrets_links_and_long_numbers_never_reach_facts_or_questions(tmp_path):
    def model(prompt):
        assert "1234567890123" not in prompt and "http" not in prompt
        return json.dumps({"understood": True, "facts": [{"key": "card", "value": "my card 4111111111111111 see http://x.y"}],
                           "question": "call 9876543210 or visit https://evil.example", "explanation": ""})

    s = _svc(tmp_path, model)
    s.set_consent("u1", True)
    s.start("u1", 10)
    r = s.turn("u1", "my number 1234567890123 http://a.b", "en")
    assert "http" not in r["question"] and "9876543210" not in r["question"]
    for f in s.facts("u1"):
        assert "4111111111111111" not in f["value"] and "http" not in f["value"]


def test_delete_one_topic_or_everything(tmp_path):
    def model(prompt):
        return json.dumps({"understood": True, "facts": [{"key": "k", "value": "v"}], "question": "q", "explanation": ""})

    s = _svc(tmp_path, model)
    s.set_consent("u1", True)
    s.start("u1", 60)
    s.turn("u1", "a", "en")
    s.turn("u1", "b", "en")
    assert len(s.facts("u1")) == 2
    assert s.delete_facts("u1", "who") == 1
    s.delete_all("u1")
    assert s.facts("u1") == [] and s.status("u1")["status"] == "new"


def test_reminders_name_unfinished_setup_and_a_feature_that_fits_and_respect_dismissals(tmp_path):
    def model(prompt):
        return json.dumps({"understood": True, "facts": [{"key": "need", "value": "baaki reminders"}], "question": "q", "explanation": ""})

    s = _svc(tmp_path, model)
    s.set_consent("u1", True)
    s.start("u1", 10)
    s.turn("u1", "I need baaki reminders", "en")
    s.pause("u1")
    refs = [r["ref"] for r in s.reminders("u1", "en")]
    assert "setup" in refs and "feature:dues_reminder" in refs
    s.dismiss("u1", "feature:dues_reminder", forever=True)
    assert "feature:dues_reminder" not in [r["ref"] for r in s.reminders("u1", "en")]
    assert "feature:dues_reminder" not in [r["ref"] for r in s.reminders("u1", "en", tried=["dues_reminder"])]
    # nothing said that fits -> no feature is pushed
    assert [r["ref"] for r in s.reminders("nobody", "en")] == []


def test_feature_requests_need_consent_are_nameless_and_tell_the_waiters_when_done(tmp_path):
    told = []
    inbox = FeatureRequests(str(tmp_path / "g.db"), notify=lambda user, text: told.append(user))
    with pytest.raises(GuideError) as err:
        inbox.submit("u1", "measurement book for tailors", consent=False)
    assert err.value.code == "consent_required"
    a = inbox.submit("u1", "Measurement book for tailors", consent=True, tell_me=True)
    b = inbox.submit("u2", "measurement  book for tailors!", consent=True)
    assert a["id"] == b["id"], "the same need joins one row"
    rows = inbox.list()
    assert rows[0]["count"] == 2 and rows[0]["waiting"] == 1
    assert "u1" not in json.dumps(rows) and "u2" not in json.dumps(rows), "staff never see who asked"
    inbox.set_status(a["id"], "building")
    assert told == []
    assert inbox.set_status(a["id"], "done")["told"] == 1 and told == ["u1"]
    assert inbox.set_status(a["id"], "done")["told"] == 0, "told only once"
    with pytest.raises(GuideError):
        inbox.set_status(a["id"], "nonsense")
