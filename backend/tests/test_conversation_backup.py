"""Chat history survives reinstall: per-account backup, older copies never win, deleted with the account,
and the brain gets the user's own earlier requests (personal answers)."""
import json

from tests.test_decision_brain import _brain, _svc


def _client(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    secret = container.settings.session_token_secret
    return TestClient(app), container, (lambda user: {"Authorization": f"Bearer {issue_token(user, secret)}"})


def _snap(cid, title, at):
    return {"id": cid, "title": title, "updatedAt": at, "status": "active", "data": {"turns": [{"text": title}]}}


def test_backup_restore_and_privacy(monkeypatch):
    client, _, auth = _client(monkeypatch)
    me, other = "app-phone-9440000701", "app-phone-9440000702"
    assert client.get("/api/me/conversations").status_code == 401
    assert client.put("/api/me/conversations/c1", headers=auth(me),
                      json={"snapshot": _snap("c1", "43 inch TV under 30k", "2026-10-20T10:00:00")}).json()["saved"]
    client.put("/api/me/conversations/c2", headers=auth(me), json={"snapshot": _snap("c2", "Chicken 1 kg", "2026-10-22T10:00:00")})
    older = client.put("/api/me/conversations/c2", headers=auth(me),
                       json={"snapshot": _snap("c2", "Chicken old", "2026-10-01T10:00:00")}).json()
    assert older == {"saved": False, "reason": "newer_copy_kept", "id": "c2"}
    assert client.put("/api/me/conversations/c3", headers=auth(me), json={"snapshot": _snap("cX", "x", "2026")}).status_code == 400
    restored = client.get("/api/me/conversations", headers=auth(me)).json()["conversations"]
    assert [c["title"] for c in restored] == ["Chicken 1 kg", "43 inch TV under 30k"], "a new phone gets it all back"
    assert client.get("/api/me/conversations", headers=auth(other)).json()["conversations"] == []
    big = _snap("c9", "big", "2026-10-23T00:00:00")
    big["data"] = {"x": "a" * 500_000}
    assert client.put("/api/me/conversations/c9", headers=auth(me), json={"snapshot": big}).status_code == 413
    assert client.delete("/api/me/conversations/c1", headers=auth(me)).json()["deleted"] == 1
    assert client.delete("/api/me?confirm=DELETE", headers=auth(other)).status_code == 200
    deleted = "app-phone-9440000703"
    client.put("/api/me/conversations/d1", headers=auth(deleted), json={"snapshot": _snap("d1", "t", "2026-10-23T00:00:00")})
    client.delete("/api/me?confirm=DELETE", headers=auth(deleted))
    from app.services import conversation_backup
    from server import container
    assert conversation_backup.list_all(container.settings.database_path, deleted) == []


def test_the_brain_gets_this_users_earlier_requests(monkeypatch):
    client, container, auth = _client(monkeypatch)
    me = "app-phone-9440000711"
    client.put("/api/me/conversations/m1", headers=auth(me),
               json={"snapshot": _snap("m1", "Samsung 43 inch TV", "2026-10-21T10:00:00")})
    svc, fake = _svc(_brain("Last time you looked at a Samsung 43 inch TV.", False))
    monkeypatch.setattr(container, "universal_ai_assistant_service", svc, raising=False)
    client.post("/api/in-app/assistant", headers=auth(me), json={"message": "suggest a TV for me", "locale": "en"})
    prompt = fake.models.calls[0]
    assert "earlier requests" in prompt and "Samsung 43 inch TV" in prompt
    svc2, fake2 = _svc(_brain("ok", False))
    monkeypatch.setattr(container, "universal_ai_assistant_service", svc2, raising=False)
    client.post("/api/in-app/assistant", json={"message": "suggest a TV for me", "locale": "en"})
    assert "Samsung 43 inch TV" not in fake2.models.calls[0], "no token = nobody's history"


def test_guide_answers_from_the_screen_help(monkeypatch):
    client, container, _ = _client(monkeypatch)

    class Writer:
        prompts = []

        def write_text(self, prompt, max_tokens=1024):
            self.prompts.append(prompt)
            return "Tap Different rates by quantity, then type 0.25 and the price."

    w = Writer()
    monkeypatch.setattr(container, "universal_ai_assistant_service", w, raising=False)
    out = client.post("/api/in-app/guide/ask", json={"question": "pav kilo rate ela pettali?", "screen": "Item details",
                                                     "steps": ["Set rates by quantity."], "guides": ["Upload a video"],
                                                     "locale": "te"}).json()
    assert out["source"] == "ai" and "0.25" in out["answer"]
    assert "Item details" in w.prompts[0] and "Telugu" in w.prompts[0] and "Never invent" in w.prompts[0]

    class Silent:
        def write_text(self, prompt, max_tokens=1024):
            return ""

    monkeypatch.setattr(container, "universal_ai_assistant_service", Silent(), raising=False)
    assert client.post("/api/in-app/guide/ask", json={"question": "?"}).json() == {"answer": "", "source": "none"}


def test_clearing_personalization_stops_earlier_chats_and_a_resync_does_not_bring_them_back(monkeypatch):
    """Owner task 2026-10-27: consent / turn-off / clear personalization must really stop it."""
    client, container, auth = _client(monkeypatch)
    me = "app-phone-9440000721"
    client.put("/api/me/conversations/p1", headers=auth(me),
               json={"snapshot": _snap("p1", "Honda Activa second hand", "2026-10-21T10:00:00")})
    state = client.get("/api/me/memory", headers=auth(me)).json()
    assert state["enabled"] is True and state["chosen"] is False, "on by default and the person has not chosen yet"

    def prompt_for(message):
        svc, fake = _svc(_brain("ok", False))
        monkeypatch.setattr(container, "universal_ai_assistant_service", svc, raising=False)
        client.post("/api/in-app/assistant", headers=auth(me), json={"message": message, "locale": "en"})
        return fake.models.calls[0]

    assert "Honda Activa" in prompt_for("suggest a scooter")
    assert client.delete("/api/me/memory?confirm=DELETE", headers=auth(me)).status_code == 200
    assert client.get("/api/me/memory", headers=auth(me)).json()["cleared_at"]
    assert "Honda Activa" not in prompt_for("suggest a scooter"), "cleared = earlier chats no longer personalize"
    # the phone re-sends the same, unchanged chat: still not used
    client.put("/api/me/conversations/p1", headers=auth(me),
               json={"snapshot": _snap("p1", "Honda Activa second hand", "2026-10-21T10:00:00")})
    assert "Honda Activa" not in prompt_for("suggest a scooter")
    # the history itself is still there for the person
    titles = [c["title"] for c in client.get("/api/me/conversations", headers=auth(me)).json()["conversations"]]
    assert "Honda Activa second hand" in titles
    # a NEW chat after clearing personalizes again; switching memory off stops everything
    client.put("/api/me/conversations/p2", headers=auth(me),
               json={"snapshot": _snap("p2", "Rain coat for kids", "2026-10-27T10:00:00")})
    assert "Rain coat" in prompt_for("suggest something")
    assert client.put("/api/me/memory/settings", headers=auth(me), json={"enabled": False}).json() == {"enabled": False}
    after = client.get("/api/me/memory", headers=auth(me)).json()
    assert after["chosen"] is True and after["cleared_at"], "turning off keeps the clear time"
    assert "Rain coat" not in prompt_for("suggest something")


def test_paid_and_affiliate_results_always_carry_a_label():
    from app.services.affiliate_catalog import result_row

    base = {"id": 7, "title": "Kettle", "platform": "amazon", "platform_name": "Amazon.in",
            "eligibility": {"routing": "affiliate", "destination_url": "https://x.example/k", "last_checked": None}}
    affiliate = result_row(base)
    assert affiliate["affiliate"] is True and affiliate["disclosure"]
    organic = result_row({**base, "eligibility": {**base["eligibility"], "routing": "organic"}})
    assert organic["affiliate"] is False and organic["disclosure"] == ""
    sponsored = result_row({**base, "sponsored": True, "eligibility": {**base["eligibility"], "routing": "organic"}})
    assert sponsored["sponsored"] is True  # the app shows its Sponsored badge from this flag
