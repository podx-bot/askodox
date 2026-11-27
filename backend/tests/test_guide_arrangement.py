"""Guide session leftovers (2026-11-28): page arrangement from the kept answers, and the "guide done" push."""
import json

from app.services.guide_session import GuideSessions


def _model(facts, question="next?"):
    def model(prompt):
        return json.dumps({"understood": True, "facts": facts, "question": question, "explanation": ""})
    return model


def _svc(tmp_path, model=None, tell=None):
    return GuideSessions(str(tmp_path / "g.db"), write_text=model, tell=tell)


def test_no_consent_means_nothing_to_arrange(tmp_path):
    s = _svc(tmp_path, _model([{"key": "wants", "value": "baaki reminders and bills"}]))
    s.start("u1", 10)
    s.turn("u1", "baaki reminders and bills", "en")
    out = s.arrangement("u1")
    assert out["ready"] is False and out["buyer"] == [] and out["seller"] == []


def test_pages_follow_the_persons_own_words_most_hits_first(tmp_path):
    s = _svc(tmp_path, _model([{"key": "wants", "value": "baaki reminders, credit, and a link to share"}]))
    s.set_consent("u1", True)
    s.start("u1", 10)
    s.turn("u1", "baaki reminders, credit, and a link to share", "en")
    s.pause("u1")
    out = s.arrangement("u1")
    assert out["ready"] is True
    assert out["seller"][:2] == ["s.dues", "s.link"], "dues has 2 word hits, link has 2: the earlier hint wins a tie"
    assert out["buyer"] == ["b.dues"]
    assert all(p[:2] in ("s.", "b.") for p in out["seller"] + out["buyer"])


def test_other_words_other_pages_no_category_scripts(tmp_path):
    """Two unrelated businesses: only the words said decide, the same engine for both."""
    s = _svc(tmp_path, _model([{"key": "work", "value": "gym members and monthly fee"}]))
    s.set_consent("u1", True)
    s.start("u1", 10)
    s.turn("u1", "x", "en")
    s.pause("u1")
    assert _svc(tmp_path).arrangement("u1")["seller"] == ["s.members"]
    t = _svc(tmp_path, _model([{"key": "work", "value": "repairs and appointment booking"}]))
    t.set_consent("u2", True)
    t.start("u2", 10)
    t.turn("u2", "x", "en")
    t.pause("u2")
    assert t.arrangement("u2")["seller"] == ["s.bookings", "s.jobs"]


def test_taking_consent_back_removes_the_arrangement(tmp_path):
    s = _svc(tmp_path, _model([{"key": "wants", "value": "bills"}]))
    s.set_consent("u1", True)
    s.start("u1", 10)
    s.turn("u1", "bills", "en")
    s.pause("u1")
    assert s.arrangement("u1")["ready"] is True
    s.set_consent("u1", False)
    assert s.arrangement("u1")["ready"] is False


def test_done_push_once_per_finish_in_the_persons_language(tmp_path):
    sent = []
    s = _svc(tmp_path, None, tell=lambda *a: sent.append(a))
    s.start("u1", 5)
    for _ in range(4):
        r = s.turn("u1", "", "te", skip=True)
    assert r["finished"] is True
    assert len(sent) == 1
    user, title, body, route, key = sent[0]
    assert user == "u1" and "గైడ్" in title and route == "/money-home" and key.startswith("guide_done:u1:")
    s.turn("u1", "", "te")  # asking again after the end does not push again
    assert len(sent) == 1


def test_a_failing_push_never_breaks_the_answer(tmp_path):
    def boom(*a):
        raise RuntimeError("fcm down")

    s = _svc(tmp_path, None, tell=boom)
    s.start("u1", 5)
    for _ in range(4):
        r = s.turn("u1", "", "en", skip=True)
    assert r["finished"] is True
