"""Production 2026-10-09: Gemini answered JSON with a raw newline inside a
string value; strict parsing failed, the OpenAI fallback was rate limited
(429) and the customer got no answer. Model JSON must tolerate it."""
from app.services.universal_ai_assistant_service import UniversalAIAssistantService


def test_raw_newline_and_tab_inside_strings_parse():
    raw = '{"reply": "Airtel postpaid bill:\n1. open the app\t2. pay", "mode": "chat"}'
    data = UniversalAIAssistantService._parse_json(raw)
    assert data["reply"].startswith("Airtel postpaid bill:\n1.")
    assert data["mode"] == "chat"


def test_fenced_reply_with_control_characters_parses():
    raw = '```json\n{"reply": "నమస్తే\nబిల్ ఎంత?"}\n```'
    assert UniversalAIAssistantService._parse_json(raw)["reply"] == "నమస్తే\nబిల్ ఎంత?"


def test_text_around_the_object_still_parses():
    raw = 'Here you go: {"reply": "line one\nline two"} thanks'
    assert UniversalAIAssistantService._parse_json(raw)["reply"] == "line one\nline two"
