"""Owner 2026-11-10: a long answer (how-to guide / advice) shows word by word while Claude
writes it, so it feels like 2-3 seconds instead of 15. The final JSON stays the real answer.
Universal: the same stream for every domain and language; old app builds keep /assistant."""
import json
import json as json_module

from tests.test_guide_mode_claude_brain import SCREENSHOT, _brain, _decision
from app.services import universal_ai_assistant_service as svc


def _sse(*texts, stop="end_turn", error=None):
    lines = ['event: message_start', 'data: {"type":"message_start"}']
    for t in texts:
        lines.append("data: " + json.dumps({"type": "content_block_delta",
                                             "delta": {"type": "text_delta", "text": t}}))
    if error:
        lines.append("data: " + json.dumps({"type": "error", "error": {"type": error, "message": "busy"}}))
    lines.append("data: " + json.dumps({"type": "message_delta", "delta": {"stop_reason": stop}}))
    lines.append('data: {"type":"message_stop"}')
    return lines


class _StreamResp:
    def __init__(self, lines, status=200):
        self.lines, self.status_code = lines, status

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return b""

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")

    def iter_lines(self):
        yield from self.lines


def _on_screen(pieces):
    """What the app shows at the end: the text after the last reset."""
    last = max((i for i, p in enumerate(pieces) if p is None), default=-1)
    return "".join(p for p in pieces[last + 1:] if p)


def _streaming(brain, http, lines, status=200):
    sent = []

    def stream(method, url, *, headers=None, json=None, timeout=None):
        sent.append(json)
        http.calls.append({"url": url, "model": (json or {}).get("model"),
                           "prompt": svc.UniversalAIAssistantService.content_text((json or {}).get("messages", [{}])[0].get("content", ""))})
        prompt = http.calls[-1]["prompt"]
        if "Return ONLY the JSON object" in prompt:  # the routing decision streams as JSON (owner 2026-11-18)
            return _StreamResp(_sse(json_module.dumps(http.decision)), 200)
        return _StreamResp(lines, status)

    http.stream = stream
    return sent


def test_a_how_to_answer_streams_piece_by_piece_and_the_final_matches():
    brain, _, http = _brain(claude=True)
    sent = _streaming(brain, http, _sse("1. Open ", "udyamregistration.gov.in", "\n2. Login"))
    pieces = []
    out = brain.decide("Udyam registration ela cheyali?", locale="te", on_text=pieces.append)
    assert "".join(p for p in pieces if p) == "1. Open udyamregistration.gov.in\n2. Login"
    assert out["reply"] == "1. Open udyamregistration.gov.in\n2. Login"
    assert out["action"] == "explain_steps"
    assert sent[0]["stream"] is True and "temperature" not in sent[0]


def test_the_machine_advice_line_is_never_streamed():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=False, action="advise", domain="GENERAL"))
    _streaming(brain, http, _sse("Renting is safer ", "for now.\nADVICE", '_META: {"key": "emi_load"}'))
    pieces = []
    out = brain.decide("should I take a home loan or keep renting, I earn 80k", locale="en", on_text=pieces.append)
    shown = _on_screen(pieces)
    assert "ADVICE_META" not in shown and "emi_load" not in shown
    assert shown.startswith("Renting is safer for now")
    assert "ADVICE_META" not in out["reply"]


def test_a_broken_stream_is_withdrawn_and_the_fallback_answer_follows():
    brain, gemini, http = _brain(claude=True)
    _streaming(brain, http, _sse("1. Open the ", error="overloaded_error"))
    pieces = []
    out = brain.decide("Udyam registration ela cheyali?", locale="te", on_text=pieces.append)
    reset = pieces.index(None)
    assert "1. Open the ".startswith("".join(pieces[:reset]))  # what was shown before the break
    assert pieces[-1] == "GEMINI GUIDE"  # the fallback arrives whole after the reset
    assert out["reply"] == "GEMINI GUIDE"


def test_a_refused_stream_falls_back_without_showing_anything():
    brain, gemini, http = _brain(claude=True)
    _streaming(brain, http, [], status=529)
    pieces = []
    out = brain.decide(SCREENSHOT, locale="te", on_text=pieces.append)
    assert pieces == ["GEMINI GUIDE"]
    assert out["reply"] == "GEMINI GUIDE"


def test_without_a_listener_nothing_streams():
    brain, _, http = _brain(claude=True)
    http.stream = lambda *a, **k: (_ for _ in ()).throw(AssertionError("must not stream"))
    out = brain.decide("Udyam registration ela cheyali?", locale="te")
    assert out["reply"] == "CLAUDE GUIDE"


def test_visible_text_holds_back_a_split_marker():
    got = []
    gate = svc._VisibleText(got.append)
    for piece in ["Step one.", " Done.\nADV", "ICE_META: {}"]:
        gate(piece)
    assert "".join(got) == "Step one. Done."


# --- the route -------------------------------------------------------------------------

def _client(monkeypatch, service):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "universal_ai_assistant_service", service, raising=False)
    return TestClient(app)


class _Speaker:
    def decide(self, message, *, history=None, locale="", location="", on_text=None, **_):
        for piece in ["1. Open the portal", "\n2. Login with OTP"]:
            if on_text is not None:  # the plain /assistant route passes none
                on_text(piece)
        return {"reply": "1. Open the portal\n2. Login with OTP", "domain": "GENERAL", "transactional": False,
                "action": "explain_steps", "confidence": 0.9, "mode": "advice"}


class _OldBrain:
    """An older decide() without on_text keeps working on the stream route."""

    def decide(self, message, *, history=None, locale="", location="", **_kw):
        if "on_text" in _kw:
            raise AssertionError("on_text must not be passed to a brain that does not take it")
        return {"reply": "Sure.", "domain": "PRODUCT", "transactional": True, "action": "find_local"}


def _lines(response):
    return [json.loads(line) for line in response.text.splitlines() if line.strip()]


def test_stream_route_sends_pieces_then_the_same_final_json(monkeypatch):
    client = _client(monkeypatch, _Speaker())
    body = {"message": "Udyam registration ela cheyali?", "locale": "te"}
    r = client.post("/api/in-app/assistant/stream", json=body)
    assert r.status_code == 200 and r.headers["content-type"].startswith("application/x-ndjson")
    events = _lines(r)
    assert [e["type"] for e in events] == ["delta", "delta", "final"]
    assert events[-1]["decision"]["reply"] == "1. Open the portal\n2. Login with OTP"
    plain = client.post("/api/in-app/assistant", json=body).json()
    assert events[-1]["decision"] == plain  # one answer, two ways to receive it


def test_stream_route_works_with_a_brain_that_cannot_stream(monkeypatch):
    client = _client(monkeypatch, _OldBrain())
    events = _lines(client.post("/api/in-app/assistant/stream", json={"message": "buy AC", "locale": "en"}))
    assert [e["type"] for e in events] == ["final"]
    assert events[0]["decision"]["action"] == "find_local"


def test_the_routing_reply_streams_word_by_word_from_the_json():
    """Owner 2026-11-18 (answers in 1-2 s): the routing JSON's "reply" shows while the rest is still being written."""
    got = []
    feed = svc._ReplyStream(got.append)
    for piece in ['{"dom', 'ain": "FOOD", "re', 'ply": "బిర్యానీ ', 'ఎక్కడ \\"best\\"', '\\nకావాలి?", "action": "x"}']:
        feed(piece)
    assert "".join(got) == 'బిర్యానీ ఎక్కడ "best"\nకావాలి?'
    assert feed.shown and feed.done
    out = []
    split = svc._ReplyStream(out.append)
    for ch in '{"reply": "caf\\u00e9 ok"}':  # one character at a time, escapes cut in the middle
        split(ch)
    assert "".join(out) == "café ok"


def test_fixed_instructions_are_sent_as_a_cached_block():
    blocks = svc.UniversalAIAssistantService._content("FIXEDpart-then-dynamic", cache_upto=5)
    assert blocks[0] == {"type": "text", "text": "FIXED", "cache_control": {"type": "ephemeral"}}
    assert blocks[1]["text"] == "part-then-dynamic"
    assert svc.UniversalAIAssistantService.content_text(blocks) == "FIXEDpart-then-dynamic"
    assert svc.UniversalAIAssistantService._content("short", cache_upto=0) == "short"


def test_a_routed_answer_is_shown_from_the_routing_stream():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=True, action="search_food", domain="FOOD"))
    sent = _streaming(brain, http, _sse("unused"))
    pieces = []
    out = brain.decide("biryani kavali", locale="te", on_text=pieces.append)
    assert _on_screen(pieces) and out["reply"].startswith(_on_screen(pieces)[:10])
    routing = [s for s in sent if "Return ONLY the JSON object" in svc.UniversalAIAssistantService.content_text(
        s["messages"][0]["content"])]
    assert routing and routing[0]["messages"][0]["content"][0].get("cache_control"), "the fixed part is cached"
    assert routing[0]["model"] == "claude-haiku-5-5"


def test_an_explanation_the_routing_call_already_wrote_is_not_written_twice():
    """Owner 2026-11-19 (20 s turn): when the routing call itself answered with explain_steps and the user's own words
    are not a how-to, the separate guide writer is skipped (one model call, not two)."""
    long_reply = "Your HDFC debit shows only on this phone's records; open My money to see each amount. " * 2
    brain, _, http = _brain(claude=True, decision=_decision(
        transactional=False, action="explain_steps", domain="GENERAL", reply=long_reply))
    _streaming(brain, http, _sse("SECOND CALL"))
    out = brain.decide("my account balance changed today", locale="en")
    assert out["reply"].startswith(long_reply.strip()) and "SECOND CALL" not in out["reply"]


def test_the_routing_reply_says_when_it_is_complete():
    """Owner 2026-11-22 (voice 30-40 s late): the app may speak the last sentence as soon as the reply's closing quote
    arrives -- the rest of the JSON (entities, state ...) is still being written."""
    got, finished = [], []

    def out(piece):
        got.append(piece)

    out.text_done = lambda: finished.append(True)
    feed = svc._ReplyStream(out)
    for piece in ['{"reply": "బిర్యానీ ', 'ఎక్కడ కావాలి?", "dom', 'ain": "FOOD", "entities": {"subject": "x"}}']:
        feed(piece)
    assert "".join(got) == "బిర్యానీ ఎక్కడ కావాలి?" and finished == [True]
    plain = svc._ReplyStream([].append)  # a receiver without text_done is fine
    plain('{"reply": "ok", "a": 1}')
    assert plain.done


class _RoutedSpeaker:
    def decide(self, message, *, history=None, locale="", location="", on_text=None, **_):
        feed = svc._ReplyStream(on_text)
        feed('{"reply": "Long layer cut suits you.", "domain": "GENERAL"')
        return {"reply": "Long layer cut suits you.", "domain": "GENERAL", "transactional": False,
                "action": "advise", "confidence": 0.9, "mode": "chat"}


def test_stream_route_sends_text_done_before_the_final_json(monkeypatch):
    client = _client(monkeypatch, _RoutedSpeaker())
    events = _lines(client.post("/api/in-app/assistant/stream", json={"message": "haircut for my face", "locale": "en"}))
    assert [e["type"] for e in events] == ["delta", "text_done", "final"]


# --- routing next to the planner (owner 2026-11-22: answers in 1-2 s) ------------------------------------------------

def test_held_text_waits_for_the_planner_then_passes_everything_in_order():
    got, done = [], []

    def out(piece):
        got.append(piece)

    out.text_done = lambda: done.append(True)
    held = svc._HeldText()
    held("Long layer ")
    held.text_done()
    assert got == [] and done == []  # nothing before the planner agrees
    held.release(out)
    held("cut suits you.")
    assert got == ["Long layer ", "cut suits you."] and done == [True]
    dropped = svc._HeldText()
    dropped("never shown")
    dropped.drop()
    dropped.release(out)
    dropped("still never")
    assert got == ["Long layer ", "cut suits you."]


def _planned(http, plan):
    """The planner answers `plan`; the routing still streams its JSON."""
    plain_post = http.post

    def post(url, *, headers=None, json=None, timeout=None):
        prompt = svc.UniversalAIAssistantService.content_text((json or {}).get("messages", [{}])[0].get("content", ""))
        if "You plan ONE turn of ASKODOX" in prompt:
            from tests.test_guide_mode_claude_brain import _Resp

            return _Resp({"content": [{"type": "text", "text": json_module.dumps(plan)}]})
        return plain_post(url, headers=headers, json=json, timeout=timeout)

    http.post = post


def test_a_plain_turn_routes_once_while_the_planner_runs():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=False, action="chat", domain="GENERAL"))
    _streaming(brain, http, _sse("unused"))
    _planned(http, {"search": False, "query": "", "level": "medium"})
    pieces = []
    out = brain.decide("long layer haircut suits my face?", locale="en", on_text=pieces.append)
    routing = [c for c in http.calls if "Return ONLY the JSON object" in c["prompt"]]
    assert len(routing) == 1 and routing[0]["model"] == "claude-haiku-5-5"  # one routing call, no repeat
    assert _on_screen(pieces) and out["reply"].startswith(_on_screen(pieces)[:10])


def test_a_hard_turn_never_shows_the_early_reply_and_routes_with_the_strong_model():
    brain, _, http = _brain(claude=True, decision=_decision(transactional=False, action="chat", domain="GENERAL"))
    _streaming(brain, http, _sse("unused"))
    _planned(http, {"search": False, "query": "", "level": "hard"})
    pieces = []
    out = brain.decide("should my shop register as a company or stay a proprietorship for GST?", locale="en",
                       on_text=pieces.append)
    routing = [c["model"] for c in http.calls if "Return ONLY the JSON object" in c["prompt"]]
    assert "claude-opus-5-5" in routing, routing
    assert out["reply"]
    assert None not in pieces[:1]  # the dropped early reply was never shown, so nothing had to be withdrawn first
