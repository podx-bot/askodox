"""Owner 2026-11-10: ASKODOX must answer like Claude does in chat -- a
screenshot or a "how do I register / fill this" question gets a step-by-step
guide, never a seller search; Claude (when ANTHROPIC_API_KEY is set) is the
primary brain with Gemini / OpenAI as fallbacks. Universal: the cases span
government portals, app settings, banking, education and plain commerce."""
import json
from types import SimpleNamespace

import pytest

from app.services import universal_ai_assistant_service as svc

# The exact text installed APKs send in place of words for a wordless attachment.
APP_ATTACHMENT_ASK = (
    "The customer sent this attachment without a question. Say what it is and help with the likely need "
    "(where to get it nearby or online, a service for it, or what the document means)."
)


def _decision(**over):
    base = {"reply": "Sure.", "domain": "SERVICE", "transactional": True, "action": "find_local",
            "confidence": 0.8, "entities": {"subject": "registration"},
            "state": {"goal": "", "facts": {}, "flexible": [], "unknown_critical": []},
            "search_ready": True, "search_subject": "registration", "next_question": None}
    base.update(over)
    return base


class _Gemini:
    def __init__(self, decision=None, text="GEMINI GUIDE"):
        self.prompts = []
        self.decision = decision or _decision()
        self.text = text

    def generate_content(self, *, model, contents, config):
        self.prompts.append(contents)
        if getattr(config, "response_mime_type", None) == "application/json":
            return SimpleNamespace(text=json.dumps(self.decision))
        return SimpleNamespace(text=self.text)


class _Resp:
    def __init__(self, payload, status=200):
        self.payload, self.status_code = payload, status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")

    def json(self):
        return self.payload


class _Http:
    """Fake Anthropic Messages API: JSON for routing calls, text for full answers."""

    def __init__(self, decision=None, answer="CLAUDE GUIDE", fail=False):
        self.calls = []
        self.decision = decision or _decision()
        self.answer = answer
        self.fail = fail

    def post(self, url, *, headers=None, json=None, timeout=None):
        self.calls.append({"url": url, "model": (json or {}).get("model"), "prompt": (json or {}).get("messages", [{}])[0].get("content", ""),
                           "max_tokens": (json or {}).get("max_tokens")})
        if self.fail:
            return _Resp({}, 529)
        prompt = self.calls[-1]["prompt"]
        text = __import__("json").dumps(self.decision) if "Return ONLY the JSON object" in prompt else self.answer
        return _Resp({"content": [{"type": "text", "text": text}]})


def _brain(*, claude=False, decision=None, http_fail=False):
    gemini = _Gemini(decision)
    http = _Http(decision, fail=http_fail)
    brain = svc.UniversalAIAssistantService(
        None, api_key="g", model="m", client=SimpleNamespace(models=gemini), http_client=http,
        anthropic_api_key="sk-ant" if claude else "", anthropic_model="claude-haiku-5-5",
        anthropic_reasoning_model="claude-sonnet-5-5")
    return brain, gemini, http


SCREENSHOT = (APP_ATTACHMENT_ASK + "\nAttachment facts: Shows: Udyam update form\nType: SCREEN\n"
              "Visible text: Update UDYAM Detail Along with Investment & Turnover for FY 2023-24; "
              "Do you have GSTIN? Yes No Exempted")


def test_wordless_screenshot_is_a_guide_not_a_shop_search():
    brain, gemini, _ = _brain()
    out = brain.decide(SCREENSHOT, locale="te")
    assert out["transactional"] is False
    assert out["action"] == "explain_steps"
    assert out["mode"] == "advice"  # installed APKs: reply only, no cards
    assert out["search_ready"] is False
    assert "షాపులు" not in out["reply"]
    assert out["reply"] == "GEMINI GUIDE"
    guide_prompt = gemini.prompts[-1]
    assert "Do you have GSTIN? Yes No Exempted" in guide_prompt  # it reads the screen
    assert "NOT a request for shops or sellers" in guide_prompt


def test_app_instruction_is_never_the_users_words():
    assert svc.UniversalAIAssistantService.own_words(SCREENSHOT) == ""
    assert svc.UniversalAIAssistantService.own_words("ela fill cheyali?\nAttachment facts: Type: SCREEN") == \
        "ela fill cheyali?"


@pytest.mark.parametrize("message", [
    "Udyam registration ela cheyali?",                      # government portal (production case)
    "ఉదయం రిజిస్ట్రేషన్ ఎలా చేయాలి",                           # Telugu
    "how to apply for a PAN card online",                     # identity document
    "how do I link Aadhaar to my bank account",               # banking
    "what should I fill in the GST registration form",        # tax form
    "steps to reset my phone's network settings",             # device settings
    "scholarship application process for B.Tech",             # education
    "पासपोर्ट के लिए कैसे अप्लाई करें",                         # Hindi
])
def test_know_how_questions_get_steps_across_domains(message):
    brain, _, _ = _brain()
    out = brain.decide(message, locale="en")
    assert out["transactional"] is False, message
    assert out["action"] == "explain_steps", message
    assert out["search_subject"] is None


def test_model_saying_explain_steps_is_respected():
    brain, _, _ = _brain(decision=_decision(transactional=False, action="explain_steps", domain="GENERAL"))
    out = brain.decide("my Razorpay KYC page asks for a utility bill, which one?", locale="en")
    assert out["action"] == "explain_steps"


@pytest.mark.parametrize("message", [
    "where can I buy a 1.5 ton AC",                 # commerce stays commerce
    "show me CA offices near me for GST filing",    # asked for a person / shop
    "need a plumber nearby today",
])
def test_buying_and_finding_people_still_search(message):
    brain, _, _ = _brain(decision=_decision(transactional=True, action="find_local", domain="SERVICE"))
    out = brain.decide(message, locale="en")
    assert out["action"] != "explain_steps", message
    assert out["transactional"] is True, message


def test_claude_is_primary_when_key_is_set():
    brain, gemini, http = _brain(claude=True)
    out = brain.decide("Udyam registration ela cheyali?", locale="te")
    assert out["reply"] == "CLAUDE GUIDE"
    assert gemini.prompts == []  # Gemini never needed
    # A plain how-to skips routing: ONE call, the reasoning model writes the guide
    # (owner 2026-11-10: quality compulsory, and faster).
    assert [c["model"] for c in http.calls] == ["claude-sonnet-5-5"]
    assert all(c["url"] == "https://api.anthropic.com/v1/messages" for c in http.calls)


def test_gemini_answers_when_claude_fails():
    brain, gemini, http = _brain(claude=True, http_fail=True)
    out = brain.decide("Udyam registration ela cheyali?", locale="te")
    assert out["reply"] == "GEMINI GUIDE"
    assert gemini.prompts  # fell back
    assert http.calls  # Claude was tried first


def test_without_anthropic_key_nothing_calls_anthropic():
    brain, _, http = _brain(claude=False)
    brain.decide("where can I buy a laptop", locale="en")
    assert not any("anthropic" in c["url"] for c in http.calls)


def test_prompt_rule_is_universal():
    rule = svc.GUIDE_ANSWER_RULES
    for must in ("NOT a request for shops or sellers", "numbered steps", "official site", "Never invent what a screenshot"):
        assert must in rule, must


def test_model_explain_steps_wins_over_a_shop_mentioned_as_context():
    # Production probe 2026-11-10: "ఇప్పటికే చికెన్ షాప్ కి ఉదయం ఉంది" blocked the guide answer.
    brain, _, _ = _brain(decision=_decision(transactional=False, action="explain_steps", domain="GENERAL"))
    out = brain.decide("ఇప్పటికే చికెన్ షాప్ కి ఉదయం ఉంది, కొత్త GST బిజినెస్ add చేయాలి", locale="te")
    assert out["mode"] == "advice" and out["action"] == "explain_steps"


def test_claude_failure_logs_anthropics_reason_without_the_key(caplog):
    class _Bad(_Http):
        def post(self, url, *, headers=None, json=None, timeout=None):
            import httpx
            request = httpx.Request("POST", url)
            response = httpx.Response(400, request=request, json={"type": "error", "error": {
                "type": "invalid_request_error", "message": "Your credit balance is too low"}})
            return response
    brain, _, _ = _brain(claude=True)
    brain.http = _Bad()
    with caplog.at_level("WARNING"):
        assert brain._call_claude("hi") == ""
    line = " ".join(r.getMessage() for r in caplog.records)
    assert "status=400" in line and "invalid_request_error" in line and "credit balance" in line
    assert "sk-ant" not in line


def test_claude_request_never_sends_temperature():
    """Production 2026-11-10: Anthropic answered 400 "temperature is deprecated for this
    model" to every call, so Claude never answered and Gemini did. Never send it."""
    brain, _, http = _brain(claude=True)
    seen = []

    class _Spy(_Http):
        def post(self, url, *, headers=None, json=None, timeout=None):
            seen.append(dict(json or {}))
            return super().post(url, headers=headers, json=json, timeout=timeout)

    brain.http = _Spy()
    brain.decide("Udyam registration ela cheyali?", locale="te")
    assert seen, "Claude was never called"
    assert all("temperature" not in body for body in seen)


def test_decision_json_has_room_so_claude_is_not_cut_off():
    """Production 2026-11-10: "claude JSON unreadable" -- a routing JSON cut at max_tokens
    cannot be parsed, so the call fell back to Gemini. The routing budget is larger now."""
    brain, _, http = _brain(claude=True)
    brain.decide("where can I buy a 1.5 ton AC", locale="en")
    routing = [c for c in http.calls if "Return ONLY the JSON object" in c["prompt"]]
    assert routing, "no routing call recorded"
    assert all(c["max_tokens"] >= 4096 for c in routing)


def test_guide_answer_is_short_so_it_comes_back_fast():
    """Owner 2026-11-10: Udyam guide answers took ~28 s. The guide asks for a short answer."""
    assert "900 characters" in svc.GUIDE_ANSWER_RULES
    assert "at most 5 steps" in svc.GUIDE_ANSWER_RULES


def test_advice_keeps_the_reasoning_model():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=False, action="advise", domain="GENERAL"))
    brain.decide("should I take a home loan or keep renting, I earn 80k", locale="en")
    models = [c["model"] for c in http.calls]
    assert "claude-sonnet-5-5" in models


@pytest.mark.parametrize("message", [
    "Udyam registration ela cheyali?",
    "how do I link Aadhaar to my bank account",
    SCREENSHOT,
])
def test_clear_how_to_skips_the_routing_call(message):
    """Speed without losing quality: the routing reply was discarded for guides anyway."""
    brain, _, http = _brain(claude=True)
    out = brain.decide(message, locale="te")
    assert out["action"] == "explain_steps" and out["mode"] == "advice"
    assert out["reply"] == "CLAUDE GUIDE"
    assert not any("Return ONLY the JSON object" in c["prompt"] for c in http.calls)
    assert [c["model"] for c in http.calls] == ["claude-sonnet-5-5"]


def test_buying_still_goes_through_routing():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=True, action="find_local"))
    out = brain.decide("where can I buy a 1.5 ton AC", locale="en")
    assert out["transactional"] is True
    assert any("Return ONLY the JSON object" in c["prompt"] for c in http.calls)


def test_fast_guide_falls_back_to_routing_when_no_answer():
    """Claude and Gemini both silent on the guide: the normal routed path still answers."""
    brain, gemini, http = _brain(claude=False)
    gemini.text = ""
    out = brain.decide("Udyam registration ela cheyali?", locale="te")
    assert out is not None and out["reply"]
