"""Runtime date/time grounding and live-fact verification (no hardcoded year).

Clocks here are deliberately set to years other than the current one: if any
code path used training-memory or a hardcoded year, these tests would fail.
"""
import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from app.services.live_research_aware_conversation_service import LiveResearchAwareConversationService
from app.services.oasat_live_research_service import OASATLiveResearchService
from app.services.runtime_time_context import (
    needs_live_verification,
    resolve_relative_time,
    runtime_context_block,
)
from app.services.universal_ai_assistant_service import UniversalAIAssistantService

DIWALI_TE = "ఈ సంవత్సరం దీపావళి ఎప్పుడు?"


def clock_at(year, month=10, day=3, hour=6, minute=30):
    return lambda: datetime(year, month, day, hour, minute, tzinfo=timezone.utc)


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
        return {"live_research": True, "source_count": len(self.sources), "sources": self.sources}


def assistant(reply="ok", research=None, clock=None):
    models = FakeModels(reply)
    service = UniversalAIAssistantService(
        delegate=None, api_key="test", model="m", client=SimpleNamespace(models=models),
        research_service=research, clock=clock,
    )
    return service, models


def test_runtime_context_is_injected_from_the_clock_not_hardcoded():
    for year in (2031, 2047):
        block = runtime_context_block("hello", clock_at(year))
        assert f"current_year={year}" in block
        assert f"today={year}-10-03" in block
        assert "timezone=Asia/Kolkata" in block and "local_time=12:00" in block  # 06:30 UTC = 12:00 IST


def test_telugu_and_english_relative_expressions_resolve_to_runtime_date():
    clock = clock_at(2031)
    assert resolve_relative_time("ఈ సంవత్సరం దీపావళి", clock)["this_year"] == "2031"
    assert resolve_relative_time("When is Diwali this year?", clock)["this_year"] == "2031"
    for today in ("today", "ఈరోజు", "ఇవాళ"):
        assert resolve_relative_time(f"{today} rate", clock)["today"] == "2031-10-03", today
    assert resolve_relative_time("రేపు 11 am", clock)["tomorrow"] == "2031-10-04"
    assert resolve_relative_time("tomorrow", clock)["tomorrow"] == "2031-10-04"
    assert resolve_relative_time("ఇప్పుడు", clock)["now"] == "2031-10-03 12:00"
    # IST date rolls over before UTC does.
    late = lambda: datetime(2031, 12, 31, 20, 0, tzinfo=timezone.utc)
    assert resolve_relative_time("this year", late)["this_year"] == "2032"


def test_live_detection_keeps_ordinary_commerce_on_the_normal_pipeline():
    assert needs_live_verification(DIWALI_TE)
    assert needs_live_verification("latest solar policy")
    assert needs_live_verification("current gold price")
    assert not needs_live_verification("I want to buy rice nearby")
    assert not needs_live_verification("నాకు 1 kg చికెన్ కావాలి")
    assert not needs_live_verification("repu 11 am")


def test_diwali_this_year_is_grounded_in_runtime_year_and_uses_verified_evidence():
    research = FakeResearch([{
        "title": "Festival calendar", "url": "https://calendar.example.gov.in/diwali",
        "published_at": None, "snippet": "Official festival calendar entry.",
    }])
    service, models = assistant(reply="దీపావళి తేదీ [S1] ప్రకారం", research=research, clock=clock_at(2031))
    decision = service.decide(DIWALI_TE, locale="te")

    assert research.queries == [f"{DIWALI_TE} 2031"], "search is pinned to the runtime year"
    prompt = models.prompts[0]
    assert "current_year=2031" in prompt and "this_year=2031" in prompt
    assert "LIVE WEB EVIDENCE" in prompt and "[S1]" in prompt and "calendar.example.gov.in/diwali" in prompt
    assert decision["grounding"]["verified"] is True
    assert decision["grounding"]["sources"][0]["url"] == "https://calendar.example.gov.in/diwali"
    assert "ధృవీకరించలేకపోయాను" not in decision["reply"]


def test_no_live_provider_gives_an_honest_unverified_answer():
    service, models = assistant(reply="Diwali is on some date.", research=None, clock=clock_at(2031))
    decision = service.decide("When is Diwali this year?")
    assert "LIVE VERIFICATION REQUIRED BUT UNAVAILABLE" in models.prompts[0]
    assert "Do NOT claim the answer was checked" in models.prompts[0]
    assert decision["grounding"] == {"required": True, "verified": False,
                                     "query": "When is Diwali this year? 2031", "sources": []}
    assert "couldn't verify this with live sources" in decision["reply"]

    empty = FakeResearch([])
    service_te, _ = assistant(reply="దీపావళి", research=empty, clock=clock_at(2031))
    assert "ధృవీకరించలేకపోయాను" in service_te.decide(DIWALI_TE)["reply"]


def test_commerce_request_does_not_trigger_live_research_or_grounding():
    research = FakeResearch([{"title": "x", "url": "https://x.example", "snippet": "x"}])
    service, models = assistant(reply="Sure, which rice?", research=research, clock=clock_at(2031))
    decision = service.decide("I want to buy rice nearby")
    assert research.queries == []
    assert "grounding" not in decision
    assert decision["reply"] == "Sure, which rice?"
    assert "current_year=2031" in models.prompts[0], "runtime date is still authoritative"


class Delegate:
    def __init__(self):
        self.last = ""

    def process(self, sender_mobile, message):
        self.last = message
        return "ok"


def _provider(published):
    return lambda query, limit: [
        {"title": "Official", "url": "https://energy.gov.in/a", "snippet": "Official update.",
         "published_at": published, "source_type": "government"},
    ]


def test_conversation_layer_routes_live_facts_with_runtime_context():
    clock = clock_at(2031)
    fresh = (clock() - timedelta(hours=3)).isoformat()
    research = OASATLiveResearchService(_provider(fresh), clock=clock)
    delegate = Delegate()
    LiveResearchAwareConversationService(delegate, research, clock=clock).process("u", "When is Diwali this year?")
    assert "OASAT LIVE RESEARCH EVIDENCE" in delegate.last and "[S1]" in delegate.last
    assert "current_year=2031" in delegate.last

    rice = Delegate()
    LiveResearchAwareConversationService(rice, research, clock=clock).process("u", "I want to buy rice nearby")
    assert rice.last == "I want to buy rice nearby"

    machine = Delegate()
    prompt = "OASAT domain=GENERAL; Current user message: hello"
    LiveResearchAwareConversationService(machine, research, clock=clock).process("u", prompt)
    assert machine.last == prompt, "machine routing prompts keep the router-only rule"


def test_freshness_uses_the_injected_clock():
    clock = clock_at(2031)
    fresh = (clock() - timedelta(days=2)).isoformat()
    stale = (clock() - timedelta(days=20)).isoformat()
    assert OASATLiveResearchService(_provider(fresh), clock=clock).research("latest x", max_age_days=7)["source_count"] == 1
    assert OASATLiveResearchService(_provider(stale), clock=clock).research("latest x", max_age_days=7)["source_count"] == 0
