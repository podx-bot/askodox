"""ASKODOX Talk (anonymous topic discussions) and town news on Radio.
No network: models, voice and web search are fakes; no real number is used."""
import base64
import dataclasses

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit, talk_moderation
from app.services.session_tokens import issue_token


class FakeCredits:
    def __init__(self):
        self.reserved, self.released = [], []

    def settings(self):
        return {"charging": False, "rates_paise": {"voice": 0, "radio": 0}, "free_per_day": {"voice": 0, "radio": 0}}

    def reserve(self, user, feature, ref):
        self.reserved.append((user, feature))
        return {"charged": False, "reason": "charging_off", "paise": 0}

    def release(self, user, ref):
        self.released.append(ref)
        return True


class FakeVoice:
    def __init__(self):
        self.spoken = []

    def synthesize(self, text, **_):
        self.spoken.append(text)
        return {"success": True, "content": b"RIFF-voice", "tts_path": "sarvam:test"}


@pytest.fixture()
def talk(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    settings = dataclasses.replace(container.settings, database_path=str(tmp_path / "talk.db"))
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "anonymous_talk", None, raising=False)
    monkeypatch.setattr(container, "travel_radio", None, raising=False)
    credits = FakeCredits()
    monkeypatch.setattr(container, "ai_credits", credits, raising=False)
    voice = FakeVoice()
    monkeypatch.setattr(container, "voice_assistant_service", voice, raising=False)
    # No model in tests: the rule checks decide (a model is an extra judge, never required).
    monkeypatch.setattr(container, "universal_ai_assistant_service", None, raising=False)
    yield TestClient(app), container, credits, voice


def _me(container, phone):
    return {"Authorization": "Bearer " + issue_token(f"app-phone-{phone}", container.settings.session_token_secret)}


def _open(client, headers, topic="Paddy prices"):
    return client.post("/api/talk/rooms", json={"topic": topic, "adult": True}, headers=headers)


def test_sign_in_and_adult_confirmation_are_required(talk):
    client, container, _, _ = talk
    assert client.get("/api/talk/rooms").status_code == 401
    me = _me(container, "919800000201")
    assert client.post("/api/talk/rooms", json={"topic": "cricket", "adult": False}, headers=me).status_code == 403


def test_same_topic_same_room_names_are_anonymous_and_stable(talk):
    client, container, _, _ = talk
    a, b = _me(container, "919800000202"), _me(container, "919800000203")
    first = _open(client, a, "Paddy prices").json()["room"]
    again = _open(client, a, "  paddy   PRICES! ").json()["room"]
    other = _open(client, b, "paddy prices").json()["room"]
    assert first["id"] == again["id"] == other["id"]
    assert first["you"] == again["you"]
    assert first["you"]["alias_en"] != other["you"]["alias_en"]
    body = client.post(f"/api/talk/rooms/{first['id']}/messages", json={"text": "hello all"}, headers=a).json()
    assert body["posted"] is True
    listing = client.get(f"/api/talk/rooms/{first['id']}/messages", headers=b).text
    assert "9800000202" not in listing and "app-phone" not in listing and "user_id" not in listing
    seen = client.get(f"/api/talk/rooms/{first['id']}/messages", headers=b).json()["messages"]
    assert seen[0]["alias_en"] == first["you"]["alias_en"] and seen[0]["mine"] is False
    assert client.get(f"/api/talk/rooms/{first['id']}/messages", headers=a).json()["messages"][0]["mine"] is True
    assert [r["id"] for r in client.get("/api/talk/rooms?q=paddy", headers=b).json()["rooms"]] == [first["id"]]


def test_rude_words_are_masked_and_contacts_hidden(talk):
    client, container, _, _ = talk
    me = _me(container, "919800000204")
    room = _open(client, me).json()["room"]["id"]
    out = client.post(f"/api/talk/rooms/{room}/messages",
                      json={"text": "this is bullshit, call me 98480 12345 or a@b.com"}, headers=me).json()
    assert out["posted"] is True and out["masked_words"] == 1 and out["contacts_hidden"] == 2
    text = client.get(f"/api/talk/rooms/{room}/messages", headers=me).json()["messages"][0]["text"]
    assert "bullshit" not in text and "98480" not in text and "a@b.com" not in text
    assert talk_moderation.MASK in text
    telugu, _ = talk_moderation.mask_words("నువ్వు లంజ")
    assert "లంజ" not in telugu


def test_threats_are_held_and_three_strikes_mute_for_a_day(talk):
    client, container, _, _ = talk
    me, other = _me(container, "919800000205"), _me(container, "919800000206")
    room = _open(client, me).json()["room"]["id"]
    for _ in range(2):
        held = client.post(f"/api/talk/rooms/{room}/messages", json={"text": "I will kill you"}, headers=me).json()
        assert held["posted"] is False and held["category"] == "threat"
    assert client.get(f"/api/talk/rooms/{room}/messages", headers=other).json()["messages"] == []
    third = client.post(f"/api/talk/rooms/{room}/messages", json={"text": "send money first bro"}, headers=me).json()
    assert third["posted"] is False and third["muted_until"]
    assert client.post(f"/api/talk/rooms/{room}/messages", json={"text": "hi"}, headers=me).status_code == 403


def test_self_harm_is_not_posted_and_the_writer_gets_support(talk):
    client, container, _, _ = talk
    me = _me(container, "919800000207")
    room = _open(client, me).json()["room"]["id"]
    out = client.post(f"/api/talk/rooms/{room}/messages", json={"text": "I want to end my life", "lang": "en"},
                      headers=me).json()
    assert out["posted"] is False and out["category"] == "self_harm"
    assert "14416" in out["support"] and "muted_until" in out and out["muted_until"] is None


def test_block_hides_an_author_and_three_reports_hide_a_message(talk):
    client, container, _, _ = talk
    author = _me(container, "919800000208")
    readers = [_me(container, f"91980000021{i}") for i in range(3)]
    room = _open(client, author).json()["room"]["id"]
    msg = client.post(f"/api/talk/rooms/{room}/messages", json={"text": "my opinion"}, headers=author).json()["id"]
    assert client.post(f"/api/talk/messages/{msg}/report", json={}, headers=author).status_code == 400
    assert client.post(f"/api/talk/messages/{msg}/block", headers=readers[0]).json()["blocked"] is True
    assert client.get(f"/api/talk/rooms/{room}/messages", headers=readers[0]).json()["messages"] == []
    assert len(client.get(f"/api/talk/rooms/{room}/messages", headers=readers[1]).json()["messages"]) == 1
    for reader in readers:
        last = client.post(f"/api/talk/messages/{msg}/report", json={"reason": "abuse"}, headers=reader).json()
    assert last["hidden"] is True
    assert client.get(f"/api/talk/rooms/{room}/messages", headers=readers[1]).json()["messages"] == []


def test_topics_with_rude_words_or_contacts_are_refused(talk):
    client, container, _, _ = talk
    me = _me(container, "919800000220")
    assert _open(client, me, "bullshit club").status_code == 400
    assert _open(client, me, "call 9848012345").status_code == 400


def test_speak_reads_the_masked_text_with_beeps_in_the_askodox_voice(talk):
    client, container, credits, voice = talk
    me = _me(container, "919800000221")
    room = _open(client, me).json()["room"]["id"]
    msg = client.post(f"/api/talk/rooms/{room}/messages", json={"text": "total bullshit price"}, headers=me).json()["id"]
    out = client.post(f"/api/talk/messages/{msg}/speak", json={"lang": "en"}, headers=me).json()
    assert out["text"] == "total beep price" and voice.spoken == ["total beep price"]
    assert base64.b64decode(out["audio_b64"]) == b"RIFF-voice"
    assert credits.reserved == [("app-phone-919800000221", "voice")]


def test_town_news_reads_only_real_headlines(talk, monkeypatch):
    client, container, credits, voice = talk
    from app.api.routes import radio, universal_deals

    radio._TOWN_CACHE.clear()
    monkeypatch.setattr(radio, "_enabled", lambda c: True)
    calls = []

    def search(query, limit):
        calls.append(query)
        return [{"title": "Vuyyuru sugar factory starts crushing season", "url": "https://news.example.in/a"},
                {"title": "Vuyyuru sugar factory starts crushing season", "url": "https://other.example.in/b"},
                {"title": "Road works near Vuyyuru bus stand", "url": "https://www.paper.example.com/c"}]

    monkeypatch.setattr(universal_deals, "_web_search", lambda c: search)
    me = _me(container, "919800000222")
    out = client.post("/api/radio/town", json={"place": "Vuyyuru", "lang": "en"}, headers=me).json()
    assert out["status"] == "ok" and len(out["headlines"]) == 2
    assert out["text"].startswith("Latest news from Vuyyuru. 1. Vuyyuru sugar factory")
    assert out["headlines"][1]["source"] == "paper.example.com"
    assert credits.reserved == [("app-phone-919800000222", "radio")]
    again = client.post("/api/radio/town", json={"place": "vuyyuru", "lang": "en"}, headers=me).json()
    assert again["status"] == "ok" and calls == ["Vuyyuru latest news"]  # cached: no second search

    monkeypatch.setattr(universal_deals, "_web_search", lambda c: (lambda q, n: []))
    none = client.post("/api/radio/town", json={"place": "Nowhere Town", "lang": "en"}, headers=me).json()
    assert none["status"] == "nothing_found" and len(credits.reserved) == 2  # nothing played, nothing charged
