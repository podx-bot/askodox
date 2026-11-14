"""Owner 2026-11-14: the chat decides itself whether to search, WHAT to search (the real subject from the whole
conversation / screenshot, in English) and how hard the question is (simple -> Haiku, medium -> Sonnet,
hard -> Opus). The old word lists stay only as a backup."""

import json

from app.services import universal_ai_assistant_service as svc


class _Resp:
    def __init__(self, body, status=200):
        self._body, self.status_code = body, status

    def json(self):
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(self.status_code)


class _Http:
    def __init__(self, plan):
        self.plan = plan
        self.models = []

    def post(self, url, *, headers=None, json=None, timeout=None):
        prompt = (json or {}).get("messages", [{}])[0].get("content", "")
        self.models.append(((json or {}).get("model"), "plan" if "You plan ONE turn of ASKODOX" in prompt else "answer"))
        if "You plan ONE turn of ASKODOX" in prompt:
            text = __import__("json").dumps(self.plan)
        elif "Return ONLY the JSON object" in prompt:
            text = __import__("json").dumps({"reply": "ok", "domain": "GENERAL", "transactional": False,
                                             "action": "chat", "confidence": 0.9, "entities": {}})
        else:
            text = "answer"
        return _Resp({"content": [{"type": "text", "text": text}]})


class _Research:
    def __init__(self):
        self.queries = []

    def research(self, query, limit=5):
        self.queries.append(query)
        return {"sources": [{"title": "PIB: cab aggregator guidelines", "url": "https://pib.gov.in/x",
                             "snippet": "minimum fleet reduced to 5"}]}


def _brain(plan):
    research = _Research()
    brain = svc.UniversalAIAssistantService(
        delegate=None, api_key="", model="", http_client=_Http(plan), research_service=research,
        anthropic_api_key="sk-ant", anthropic_model="claude-haiku-5-5", anthropic_reasoning_model="claude-sonnet-5-5")
    return brain, research


def test_the_planner_searches_the_real_subject_not_the_users_words():
    brain, research = _brain({"search": True, "query": "India cab aggregator minimum 5 cars licence rule official",
                              "level": "medium"})
    # Telugu "is it official? check and tell me" -- no search word the old list knew, no product name.
    brain.decide("ఇది అధికారికంగా వచ్చిందా రాలేదా ఏంటో అనేది ఒకసారి మీరు చెక్ చేసుకుని చెప్పవచ్చు కదా.",
                 history=[{"role": "user", "text": "5 కార్లుంటే చాలు క్యాబ్ వ్యాపారానికి"}], locale="te")
    assert research.queries == ["India cab aggregator minimum 5 cars licence rule official"]


def test_level_picks_the_model():
    for level, model in (("simple", "claude-haiku-5-5"), ("medium", "claude-sonnet-5-5"), ("hard", "claude-opus-5-5")):
        brain, _ = _brain({"search": False, "query": "", "level": level})
        brain.decide("razorpay ఎందుకు ఓపెన్ అవ్వట్లేదు", locale="te")
        answer_models = [m for m, kind in brain.http.models if kind == "answer"]
        assert answer_models and answer_models[0] == model, (level, brain.http.models)
        assert brain.http.models[0] == ("claude-haiku-5-5", "plan"), "the planner itself is the fast model"


def test_no_search_when_the_planner_says_so_and_no_old_word_matches():
    brain, research = _brain({"search": False, "query": "", "level": "simple"})
    brain.decide("hi", locale="en")
    assert research.queries == []


def test_planner_failure_falls_back_to_the_old_lists(monkeypatch):
    brain, research = _brain({})
    monkeypatch.setattr(brain, "_plan", lambda message, history: {})
    brain.decide("search Oppo Find X10 price", locale="en")
    assert research.queries, "the old search words still trigger a lookup"
