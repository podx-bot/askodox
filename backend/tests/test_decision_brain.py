"""Decision brain: advice questions get reasoning (no cards); follow-ups
about options already shown are answered, never turned into a canned video
search by words in the app's own context; commerce stays commerce."""
import json

from app.services.universal_ai_assistant_service import UniversalAIAssistantService

SHOWN = ("Compare the best 3\nOptions already shown to the user:\n1. Voltas 1.5 ton | price: ₹38,990 | "
         "rating: not provided | reviews: not provided\nAnswer ONLY from the facts listed for each option. If a fact "
         "(price, rating, reviews, condition, stock) is \"not provided\", say it is not provided by the source")


class _Resp:
    def __init__(self, text):
        self.text = text


class _Models:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def generate_content(self, *, model, contents, config):
        self.calls.append(contents)
        return _Resp(self.replies.pop(0) if len(self.replies) > 1 else self.replies[0])


class _Client:
    def __init__(self, replies):
        self.models = _Models(replies)


def _svc(*replies):
    client = _Client(list(replies))
    return UniversalAIAssistantService(delegate=None, api_key="k", model="m", client=client), client


def _decision(reply, **extra):
    return json.dumps({"reply": reply, "domain": extra.pop("domain", "PRODUCT"),
                       "transactional": extra.pop("transactional", True), "action": extra.pop("action", "search_products"),
                       "confidence": 0.9, "entities": extra.pop("entities", {"subject": "AC"})})


def test_follow_up_about_shown_options_is_answered_not_a_canned_video_search():
    svc, _ = _svc(_decision("Voltas is ₹38,990; rating and reviews are Not verified.", transactional=False,
                            domain="GENERAL", action="chat"))
    out = svc.decide(SHOWN, locale="en")
    assert out["mode"] == "follow_up" and out["transactional"] is False
    assert out["action"] == "answer_about_options"
    assert "videos and reviews" not in out["reply"] and "Not verified" in out["reply"]


def test_context_words_never_trigger_overrides_but_users_own_words_do():
    user, context, about = UniversalAIAssistantService.split_app_context(SHOWN)
    assert user == "Compare the best 3" and about and "reviews" in context
    svc, _ = _svc(_decision("ok"))
    out = svc.decide("Samsung TV review videos", locale="en")
    assert out["action"] == "search_videos" and out["mode"] == "commerce"


def test_advice_question_gets_full_reasoning_and_no_search():
    advice = ("Your goal: decide if a car-finance business is viable.\nRisks: defaults, RBI NBFC rules...\n"
              "My recommendation: start as a DSA tie-up first, because...")
    svc, client = _svc(_decision("short", domain="GENERAL", transactional=True, action="search"), advice)
    out = svc.decide("Should I start a car finance business in Vijayawada? What are the risks?", locale="en")
    assert out["mode"] == "advice" and out["transactional"] is False and out["action"] == "advise"
    assert out["reply"] == advice
    assert len(client.models.calls) == 2 and "decision advisor" in client.models.calls[1]


def test_telugu_advice_and_capacity_question_are_advice():
    for text in ("కార్ ఫైనాన్స్ బిజినెస్ చేయాలా? రిస్క్ ఏమిటి?", "What AC capacity do I need for a 150 sq ft room?",
                 "Which loan is suitable for me, home loan or LAP?"):
        assert UniversalAIAssistantService.wants_advice(text), text


def test_commerce_requests_stay_commerce_even_with_advice_words():
    for text in ("Show AC shops near me under 40000", "Is it worth buying, and where can I get it here?",
                 "I want to buy an AC", "Find size 9 shoes under 2000"):
        assert not UniversalAIAssistantService.wants_advice(text), text
    svc, _ = _svc(_decision("Let me check.", entities={"subject": "AC", "budget": "40000"}))
    out = svc.decide("Show me AC options near me under 40000", locale="en",
                     history=[{"role": "user", "text": "What AC capacity do I need for 150 sq ft?"}])
    assert out["mode"] == "commerce" and out["transactional"] is True


def test_advice_falls_back_to_the_routing_reply_when_the_advisor_call_fails():
    class _Boom(_Models):
        def generate_content(self, *, model, contents, config):
            self.calls.append(contents)
            if len(self.calls) > 1:
                raise RuntimeError("down")
            return _Resp(_decision("Here is a quick view of the risks.", transactional=False, domain="GENERAL"))
    client = _Client([])
    client.models = _Boom([])
    svc = UniversalAIAssistantService(delegate=None, api_key="k", model="m", client=client)
    out = svc.decide("Is it a good idea to start a cloud kitchen?", locale="en")
    assert out["mode"] == "advice" and out["reply"] == "Here is a quick view of the risks."


# ---------------------------------------------- conversation state + readiness --

def _brain(reply, ready, question=None, subject=None, facts=None, flexible=None, unknown=None, **extra):
    data = json.loads(_decision(reply, **extra))
    data.update({"state": {"goal": "buy a steel wardrobe", "facts": facts or {}, "flexible": flexible or [],
                           "unknown_critical": unknown or []},
                 "search_ready": ready, "next_question": question, "search_subject": subject,
                 "ready_reason": "core need known" if ready else "size and budget unknown"})
    return json.dumps(data, ensure_ascii=False)


def test_prompt_carries_generic_state_rules_not_category_scripts():
    svc, client = _svc(_brain("ok", False, "Budget?"))
    svc.decide("నాకు ఒక ఐరన్ బీరువా కావాలి", locale="te")
    prompt = client.models.calls[0]
    assert "search is a TOOL" in prompt and "search_ready" in prompt and "unknown_critical" in prompt
    for script in ("AC", "wardrobe", "beeruva", "almirah"):
        assert f"if {script}" not in prompt.lower()


def test_broad_request_is_not_ready_and_the_turn_ends_with_one_question():
    svc, _ = _svc(_brain("సరే, మంచి బీరువా ఎంచుకుందాం.", False, "మీ బడ్జెట్ ఎంత?",
                         facts={"item": "iron beeruva"}, unknown=["budget", "size"],
                         entities={"subject": "iron beeruva"}))
    out = svc.decide("నాకు ఒక ఐరన్ బీరువా కావాలి", locale="te")
    assert out["search_ready"] is False and out["mode"] == "commerce"
    assert out["reply"].endswith("మీ బడ్జెట్ ఎంత?"), "the ONE next question ends the turn"
    assert out["search_subject"] is None
    assert out["state"]["facts"] == {"item": "iron beeruva"}
    assert out["state"]["unknown_critical"] == ["budget", "size"]


def test_ready_turn_carries_the_consolidated_subject_and_no_question():
    svc, _ = _svc(_brain("Got it.", True, "Anything else?", subject="large two-door steel wardrobe with locker",
                         facts={"budget": "30000-40000", "doors": "2", "brand": "Godrej"}, flexible=["brand"]))
    out = svc.decide("I need delivery to my place", locale="en",
                     history=[{"role": "user", "text": "I need an iron wardrobe"}])
    assert out["search_ready"] is True and out["next_question"] is None
    assert out["search_subject"] == "large two-door steel wardrobe with locker"
    assert out["state"]["flexible"] == ["brand"]


def test_advice_follow_up_and_chat_are_never_search_ready():
    svc, _ = _svc(_brain("Voltas is cheaper; rating Not verified.", True, subject="AC", transactional=False,
                         domain="GENERAL", action="chat"))
    out = svc.decide(SHOWN, locale="en")
    assert out["mode"] == "follow_up" and out["search_ready"] is False and out["search_subject"] is None
    svc, _ = _svc(_brain("general chat", True, transactional=False, domain="GENERAL", action="chat"))
    assert svc.decide("how are you", locale="en")["search_ready"] is False


def test_user_asking_for_videos_is_ready_and_missing_readiness_stays_unknown():
    svc, _ = _svc(_brain("ok", False, "Budget?"))
    out = svc.decide("Godrej almirah review videos", locale="en")
    assert out["action"] == "search_videos" and out["search_ready"] is True
    svc, _ = _svc(_decision("Sure."))  # an older model reply without readiness
    out = svc.decide("I want a steel almirah", locale="en")
    assert out["search_ready"] is None, "the app keeps its offline rule"


def test_api_returns_the_brain_fields(monkeypatch):
    from fastapi.testclient import TestClient
    from server import app, container

    svc, _ = _svc(_brain("ఏ సైజు కావాలి?", False, "ఏ సైజు కావాలి?", facts={"item": "beeruva", "budget": "30000-40000"}))
    monkeypatch.setattr(container, "universal_ai_assistant_service", svc, raising=False)
    body = TestClient(app).post("/api/in-app/assistant", json={"message": "30-40 వేలు", "locale": "te", "history": [
        {"role": "user", "text": "నాకు ఒక ఐరన్ బీరువా కావాలి"}, {"role": "assistant", "text": "బడ్జెట్ ఎంత?"}]}).json()
    assert body["search_ready"] is False and body["next_question"] == "ఏ సైజు కావాలి?"
    assert body["state"]["facts"]["budget"] == "30000-40000"
