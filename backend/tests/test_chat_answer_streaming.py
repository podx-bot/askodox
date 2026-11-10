"""Owner 2026-11-10: a long answer (how-to guide / advice) shows word by word while Claude
writes it, so it feels like 2-3 seconds instead of 15. The final JSON stays the real answer.
Universal: the same stream for every domain and language; old app builds keep /assistant."""
import json

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


def _streaming(brain, http, lines, status=200):
    sent = []

    def stream(method, url, *, headers=None, json=None, timeout=None):
        sent.append(json)
        http.calls.append({"url": url, "model": (json or {}).get("model"),
                           "prompt": (json or {}).get("messages", [{}])[0].get("content", "")})
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
    shown = "".join(p for p in pieces if p)
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
