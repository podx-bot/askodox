"""Owner report 2026-10-29: "Oppo Find X10" (launched days earlier) was called
fake / not released -- even after a photo and "check the official website" --
because the live check ran only for a fixed list of time words. These tests
pin the universal fix (live_lookup.py): any product / model name or explicit
lookup ask gets live evidence, leaks / "is it released" go deep, sources are
labelled, and an unbacked "fake" or "I searched" never reaches the user.
Cross-category: phones, bikes, laptops, GPUs, festivals, local commerce.
"""
import json
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.services import live_lookup
from app.services.oasat_deep_research_service import OASATDeepResearchService
from app.services.universal_ai_assistant_service import UniversalAIAssistantService


class FakeModels:
    def __init__(self, reply):
        self.reply = reply
        self.prompts = []

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        return SimpleNamespace(text=json.dumps({
            "reply": self.reply, "domain": "GENERAL", "transactional": False,
            "action": "answer", "confidence": 0.9, "entities": {},
        }))


class FakeResearch:
    def __init__(self, sources):
        self.sources = sources
        self.queries = []

    def research(self, query, **kwargs):
        self.queries.append(query)
        return {"sources": [dict(s) for s in self.sources], "source_count": len(self.sources)}


LAUNCH = [
    {"title": "OPPO Find X10 series launching in India on October 22", "url": "https://www.91mobiles.com/x10",
     "snippet": "Launch offers live.", "published_at": "2026-10-20T00:00:00+00:00", "domain": "www.91mobiles.com"},
    {"title": "OPPO Find X10", "url": "https://www.oppo.com/in/smartphones/find-x10/", "snippet": "Official page.",
     "domain": "www.oppo.com"},
    {"title": "Find X10 Ultra tipped to arrive later", "url": "https://leaks.example.com/x10u",
     "snippet": "A tipster claims the Ultra is expected to launch next year.", "domain": "leaks.example.com"},
]


def clock():
    return datetime(2026, 10, 29, 4, 0, tzinfo=timezone.utc)


def make(reply="ok", research=None, deep=None):
    models = FakeModels(reply)
    service = UniversalAIAssistantService(
        delegate=None, api_key="test", model="m", client=SimpleNamespace(models=models),
        research_service=research, deep_research_service=deep, clock=clock,
    )
    return service, models


@pytest.mark.parametrize("text, kind, phrase", [
    ("Oppo Find X10 గురించి చెప్పండి", "quick", "Oppo Find X10"),
    ("Oppo Find X10 కావాలి", "quick", "Oppo Find X10"),
    ("is Oppo Find X10 released", "deep", "Oppo Find X10"),
    ("Oppo Find X10 వచ్చిందా", "deep", "Oppo Find X10"),
    ("iPhone 17 Pro price", "quick", "iPhone 17 Pro"),
    ("Samsung Galaxy S26 Ultra leaks", "deep", "Samsung Galaxy S26 Ultra"),
    ("Activa 7 కొత్త model ఎప్పుడు వస్తుంది", "deep", "Activa 7"),
    ("RTX 5070 Ti laptop", "quick", "RTX 5070 Ti"),
    ("Royal Enfield Bullet 350 on road price", "quick", "Royal Enfield Bullet 350"),
    ("search the official website", "quick", ""),
    ("ఈ సంవత్సరం దీపావళి ఎప్పుడు?", "quick", ""),
    ("deep గా వెతుకు", "deep", ""),
    ("నాకు 5 కిలోల చికెన్ కావాలి", None, ""),
    ("5kg chicken kavali", None, ""),
    ("salary 800 estha", None, ""),
    ("10 members kavali repu 11 am", None, ""),
    ("2bhk flat rent", None, ""),
    ("washing machine under 20000", None, ""),
    ("Room 2 cleaning", None, ""),
])
def test_lookup_kind_and_model_phrase_any_category(text, kind, phrase):
    assert live_lookup.lookup_kind(text) == kind
    assert live_lookup.model_phrase(text) == phrase


def test_new_phone_gets_live_evidence_labelled_sources_and_no_fake_verdict():
    research = FakeResearch(LAUNCH)
    service, models = make(reply="Oppo Find X10 India లో October 22న launch అయింది [S1].", research=research)
    decision = service.decide("Oppo Find X10 గురించి చెప్పండి", locale="te")
    assert research.queries == ["Oppo Find X10"]
    assert "LIVE WEB EVIDENCE" in models.prompts[0]
    assert "(official) OPPO Find X10" in models.prompts[0]
    assert "Never call a product, model, event or claim fake" in models.prompts[0]
    labels = {s["url"]: s["label"] for s in decision["grounding"]["sources"]}
    assert labels["https://www.oppo.com/in/smartphones/find-x10/"] == "official"
    assert labels["https://www.91mobiles.com/x10"] == "news"
    assert labels["https://leaks.example.com/x10u"] == "rumor"
    assert "ఆధారాలు (Sources)" in decision["reply"]
    assert "[oppo.com](https://www.oppo.com/in/smartphones/find-x10/)" in decision["reply"]
    assert "🔮 Leak / Rumor" in decision["reply"]


def test_official_website_follow_up_takes_the_model_from_the_earlier_turn():
    research = FakeResearch(LAUNCH)
    service, _ = make(reply="Official page లో ఉంది [S2].", research=research)
    service.decide("Oppo official website లో వెతకండి", locale="te",
                   history=[{"role": "user", "text": "Oppo Find X10 గురించి చెప్పండి"},
                            {"role": "assistant", "text": "..."}])
    assert research.queries == ["Oppo Find X10 official"]


def test_is_it_released_runs_several_angles():
    live = FakeResearch(LAUNCH)
    deep = OASATDeepResearchService(live)
    service, models = make(reply="Launched [S1].", research=live, deep=deep)
    decision = service.decide("is Oppo Find X10 released")
    assert live.queries[:4] == ["Oppo Find X10", "Oppo Find X10 launch date price India",
                                "Oppo Find X10 leak rumor", "Oppo Find X10 official"]
    assert decision["grounding"]["mode"] == "deep"
    assert "DEEP LIVE WEB EVIDENCE" in models.prompts[0]


@pytest.mark.parametrize("reply, locale", [
    ("ఈ ఫోన్ ఫేక్ అయి ఉండొచ్చు. ఇంకా విడుదల కాలేదు. వేరే model చూడండి.", "te"),
    ("There is no such phone. It has not been released. Want another model?", "en"),
    ("I checked the official website and there is nothing about it.", "en"),
])
def test_without_evidence_a_fake_verdict_or_search_claim_never_reaches_the_user(reply, locale):
    service, _ = make(reply=reply, research=FakeResearch([]))
    decision = service.decide("Oppo Find X10 గురించి చెప్పండి", locale=locale)
    text = decision["reply"]
    for banned in ("ఫేక్", "విడుదల కాలేదు", "no such phone", "not been released", "I checked"):
        assert banned not in text
    assert decision["honesty"]
    assert decision["grounding"]["verified"] is False


def test_with_real_evidence_the_model_may_report_what_the_evidence_says():
    evidence = [{"title": "Fake Find X10 units seized", "url": "https://news.example.com/fake",
                 "snippet": "Police report counterfeit units.", "domain": "news.example.com"}]
    service, _ = make(reply="Reports say fake units were seized [S1].", research=FakeResearch(evidence))
    decision = service.decide("Oppo Find X10 fake units news")
    assert "fake units were seized" in decision["reply"]
    assert "honesty" not in decision


def test_local_commerce_and_shown_options_stay_without_lookup():
    research = FakeResearch(LAUNCH)
    service, _ = make(reply="Which cut?", research=research)
    service.decide("నాకు 5 కిలోల చికెన్ కావాలి")
    service.decide("which is cheapest?\n\nOptions already shown to the user: Oppo Find X10 at Shop A")
    assert research.queries == []


def test_attachment_facts_can_name_the_model():
    research = FakeResearch(LAUNCH)
    service, _ = make(reply="ok [S1]", research=research)
    service.decide("ఇది నిజమేనా?\n\nThe customer shared attachment: photo. Attachment facts: box reads OPPO Find X10")
    assert research.queries and "Find X10" in research.queries[0]


def test_unconfirmed_or_corrected_answers_become_knowledge_gaps_in_demand_intelligence(monkeypatch, tmp_path):
    import dataclasses

    from fastapi.testclient import TestClient
    from server import app, container

    from app.api.routes.platform import platform
    from app.services import demand_insights, rate_limit

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "kg.db")))
    monkeypatch.setattr(container, "platform", None, raising=False)

    class Brain:
        def decide(self, message, **kwargs):
            unconfirmed = "X10" in message
            return {"reply": "I could not confirm it yet.", "domain": "GENERAL", "transactional": False,
                    "action": "answer", "confidence": 0.8, "entities": {},
                    **({"grounding": {"required": True, "verified": False, "query": "Oppo Find X10", "mode": "quick",
                                      "sources": []}, "honesty": ["unbacked_nonexistence"]} if unconfirmed else {})}

    monkeypatch.setattr(container, "universal_ai_assistant_service", Brain())
    client = TestClient(app)
    first = client.post("/api/in-app/assistant", json={"message": "Oppo Find X10 గురించి చెప్పండి", "locale": "te"})
    assert first.status_code == 200 and first.json()["honesty"] == ["unbacked_nonexistence"]
    client.post("/api/in-app/assistant", json={
        "message": "అది తప్పు, రిలీజ్ అయింది", "locale": "te",
        "history": [{"role": "user", "text": "Oppo Find X10 గురించి చెప్పండి"}]})
    client.post("/api/in-app/assistant", json={"message": "hello", "locale": "en"})
    gaps = demand_insights.insights(platform(container).repo, days=1)["knowledge_gaps"]
    assert gaps == [{"subject": "Oppo Find X10", "count": 2,
                     "reasons": {"live_check_failed": 1, "guard_unbacked_nonexistence": 1, "user_correction": 1}}]
    events = platform(container).repo.events(event="knowledge_gap")
    assert all("message" not in e["detail"] and not e.get("user_ref") for e in events), "no text, no identity"
