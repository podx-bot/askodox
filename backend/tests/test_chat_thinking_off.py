"""Owner 2026-11-26 ("chat speed"): the 5.5 models think by default (deploy log: Haiku's first word after 5-7 s).
Chat calls turn up-front thinking off -- Haiku "disabled", Sonnet "between_tools", the strongest model untouched --
and a model that refuses the setting is asked again without it (chat never breaks). Short plain replies get no card."""

from app.services import answer_card
from app.services import universal_ai_assistant_service as svc


class _Resp:
    def __init__(self, body, status=200, text=""):
        self._body, self.status_code, self.text = body, status, text

    def json(self):
        return self._body

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(self.status_code)


class _Http:
    def __init__(self, refuse=False):
        self.sent = []
        self.refuse = refuse

    def post(self, url, *, headers=None, json=None, timeout=None):
        self.sent.append(dict(json or {}))
        if self.refuse and "thinking" in (json or {}):
            return _Resp({}, status=400, text='{"error":{"type":"invalid_request_error","message":"thinking.type: not supported"}}')
        return _Resp({"content": [{"type": "text", "text": "ok"}]})


def _brain(http):
    svc.UniversalAIAssistantService._THINKING_REFUSED.clear()
    return svc.UniversalAIAssistantService(
        delegate=None, api_key="", model="", http_client=http, anthropic_api_key="sk-ant",
        anthropic_model="claude-haiku-5-5", anthropic_reasoning_model="claude-sonnet-5-5")


def test_quick_thinking_per_model():
    svc.UniversalAIAssistantService._THINKING_REFUSED.clear()
    q = svc.UniversalAIAssistantService._quick_thinking
    assert q("claude-haiku-5-5") == {"thinking": {"type": "disabled"}}
    assert q("claude-sonnet-5-5") == {"thinking": {"type": "between_tools"}}
    assert q("claude-opus-5-5") == {}


def test_calls_send_the_setting_and_retry_without_it_when_refused():
    http = _Http()
    assert _brain(http)._call_claude("hi", model="claude-haiku-5-5") == "ok"
    assert http.sent[-1]["thinking"] == {"type": "disabled"}
    refusing = _Http(refuse=True)
    brain = _brain(refusing)
    assert brain._call_claude("hi", model="claude-haiku-5-5") == "ok"
    assert "thinking" in refusing.sent[0] and "thinking" not in refusing.sent[1]
    assert brain._call_claude("again", model="claude-haiku-5-5") == "ok"
    assert "thinking" not in refusing.sent[-1], "a refusal is remembered"
    svc.UniversalAIAssistantService._THINKING_REFUSED.clear()


def test_short_plain_reply_is_a_bubble_not_a_card():
    assert answer_card.build(None, reply="హలో!", user_text="Hello") is None
    assert answer_card.build(None, reply="Hi! How can I help?", user_text="hi") is None


def test_fixed_instructions_cached_for_one_hour_and_fallback():
    """Owner 2026-11-26: the first question after a pause re-read ~8k tokens (5-minute cache)."""
    S = svc.UniversalAIAssistantService
    S._TTL_REFUSED = False
    content = S._content("FIXED RULES" * 10 + "question", cache_upto=110)
    assert content[0]["cache_control"] == {"type": "ephemeral", "ttl": "1h"}
    refusing = _Http()
    refusing.post = lambda url, **kw: (refusing.sent.append(kw["json"]) or (
        _Resp({}, status=400, text='{"error":{"message":"cache_control.ttl: unknown"}}')
        if "ttl" in str(kw["json"]) else _Resp({"content": [{"type": "text", "text": "ok"}]})))
    assert _brain(refusing)._call_claude("FIXED" * 50 + "q", model="claude-haiku-5-5", cache_upto=250) == "ok"
    assert S._TTL_REFUSED and "ttl" not in str(refusing.sent[-1])
    S._TTL_REFUSED = False
