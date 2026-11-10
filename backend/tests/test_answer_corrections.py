"""Self-correction loop (owner 2026-11-10): a reply marked wrong (button or the user's next message)
goes to staff review masked; once staff write the right answer and approve it, the brain gets it for
the same question; approved corrections are listed as regression cases; repeated brain failures
alert staff once per hour."""
import dataclasses
from datetime import datetime, timezone

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.platform_repository import PlatformRepository
from app.services import answer_corrections, owner_alerts


def _app(monkeypatch, tmp_path, brain):
    from fastapi.testclient import TestClient
    from server import app, container

    from app.services import rate_limit

    rate_limit.reset_for_tests()
    answer_corrections.clear_cache()
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "acr.db")))
    monkeypatch.setattr(container, "platform", None, raising=False)
    monkeypatch.setattr(container, "universal_ai_assistant_service", brain)
    return TestClient(app), container


def test_content_words_ignore_glue_words_and_keep_telugu():
    assert answer_corrections.content_words("What is the price of Activa 7G in Vijayawada?") == {"activa", "vijayawada"}
    assert "ఉల్లిపాయలు" in answer_corrections.content_words("ఉల్లిపాయలు ధర ఎంత?")


def test_wrong_answer_button_typed_correction_review_then_the_brain_learns(monkeypatch, tmp_path):
    seen = []

    class Brain:
        def decide(self, message, *, history=None, locale="", location="", lessons=None, **kwargs):
            seen.append(list(lessons or []))
            return {"reply": "Activa 7G is not released.", "domain": "GENERAL", "transactional": False,
                    "action": "answer", "confidence": 0.8, "entities": {}}

    client, container = _app(monkeypatch, tmp_path, Brain())
    from app.api.routes.platform import platform

    # 1. The "Wrong answer" button: masked, no identity.
    r = client.post("/api/in-app/answer-feedback", json={
        "question": "Activa 7G launch date? call me 9876543210", "answer": "Activa 7G is not released.",
        "reason": "outdated", "locale": "en"})
    assert r.status_code == 200 and r.json()["ok"]
    # 2. The user's next message says it was wrong.
    client.post("/api/in-app/assistant", json={"message": "that's wrong, it launched", "locale": "en", "history": [
        {"role": "user", "text": "Activa 7G launch date?"}, {"role": "assistant", "text": "Activa 7G is not released."}]})
    pf = platform(container)
    rows = pf.repo.list("answer_corrections")
    assert {r["data"]["source"] for r in rows} == {"button", "typed"}
    assert all(r["status"] == "NEW" for r in rows)
    assert not any("9876543210" in str(r) for r in rows), "phone masked"
    typed = next(r["data"] for r in rows if r["data"]["source"] == "typed")
    assert typed["question"] == "Activa 7G launch date?" and "not released" in typed["answer"]

    # Nothing is learned before staff approve (a user can be wrong too).
    client.post("/api/in-app/assistant", json={"message": "When did Activa 7G launch?", "locale": "en"})
    assert seen[-1] == []

    # 3. Staff write the right answer and approve.
    row = rows[0]
    pf.resources.update("answer_corrections", row["id"], {"corrected": "Activa 7G launched; check the Honda site."},
                        actor="staff")
    pf.resources.action("answer_corrections", row["id"], "approve", actor="staff")
    answer_corrections.clear_cache()
    client.post("/api/in-app/assistant", json={"message": "When did Activa 7G launch?", "locale": "en"})
    assert seen[-1] and "Activa 7G launched" in seen[-1][0]
    # Unrelated questions carry nothing.
    client.post("/api/in-app/assistant", json={"message": "tomato price today", "locale": "en"})
    assert seen[-1] == []
    # 4. Proof list.
    assert answer_corrections.regression_cases(pf)[0]["must_follow"].startswith("Activa 7G launched")


def test_the_lesson_reaches_the_real_prompt():
    block = answer_corrections.prompt_block(["Q: Activa 7G? -> correct answer: launched"])
    assert "STAFF-CHECKED CORRECTIONS" in block and "launched" in block
    assert answer_corrections.prompt_block([]) == ""


def test_brain_failures_alert_staff_once_an_hour(monkeypatch, tmp_path):
    class Silent:
        def decide(self, message, **kwargs):
            return None

    client, container = _app(monkeypatch, tmp_path, Silent())
    from app.api.routes.platform import platform

    for _ in range(3):
        assert client.post("/api/in-app/assistant", json={"message": "hello", "locale": "en"}).json()["source"] == "fallback"
    repo = platform(container).repo
    assert owner_alerts.brain_failures(repo) == 3
    cc = CommandCenterRepository(str(tmp_path / "cc.db"))

    class CC:
        def list_staff(self):
            return [{"app_user_id": "app-phone-919811111111", "active": True, "permissions": ["demand:view"]}]

        def notify_once(self, *a, **k):
            return cc.notify_once(*a, **k)

    sent = []
    at = datetime.now(timezone.utc)
    result = owner_alerts.run(repo, CC(), at=at, notify=lambda user, **kw: sent.append(kw["title"]) or 1)
    assert result == {"alerts": 1, "pushed": 1} and "AI" in sent[0]
    assert owner_alerts.run(repo, CC(), at=at, notify=lambda *a, **k: 1) == {"alerts": 0, "pushed": 0}


def test_below_threshold_no_brain_alert(tmp_path):
    repo = PlatformRepository(str(tmp_path / "p.db"))
    repo.record_event("brain_failure", detail={"reason": "no_answer"})
    assert owner_alerts.brain_failures(repo) == 1


def test_every_turn_leaves_a_numbers_only_trace_and_a_report_marks_it(monkeypatch, tmp_path):
    from app.services import brain_runs

    class Brain:
        def decide(self, message, **kwargs):
            # what the usage meter would report for one model call in this turn
            brain_runs.note_provider_call({"provider": "gemini", "model": "gemini-3.6-flash", "feature": "chat",
                                           "input_tokens": 3000, "output_tokens": 400, "chars": 0, "seconds": 0.0,
                                           "ok": True})
            return {"reply": "ok", "domain": "GENERAL", "transactional": False, "action": "answer",
                    "confidence": 0.9, "entities": {}, "mode": "advice"}

    client, container = _app(monkeypatch, tmp_path, Brain())
    answer = client.post("/api/in-app/assistant", json={"message": "should I buy a bike or a scooter?", "locale": "en"}).json()
    turn = answer["turn_id"]
    assert turn.startswith("t_")
    db = container.settings.database_path
    report = brain_runs.summary(db, days=1)
    assert report["turns"] == 1 and report["answered"] == 1 and report["modes"][0]["mode"] == "advice"
    assert report["modes"][0]["input_tokens"] == 3000 and report["cost_inr"] > 0
    client.post("/api/in-app/answer-feedback", json={"question": "q", "answer": "ok", "turn_id": turn})
    assert brain_runs.summary(db, days=1)["wrong_answer_reports"] == 1
    import sqlite3
    cols = [r[1] for r in sqlite3.connect(db).execute("PRAGMA table_info(brain_runs)")]
    assert not {"message", "reply", "user_id", "user_ref"} & set(cols), "numbers only"
