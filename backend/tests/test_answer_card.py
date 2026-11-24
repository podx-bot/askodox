"""One-screen answer cards (owner 2026-11-24, design WfPV8AhvZsPFqmwzYpfvap): structured blocks for the app, the plain
reply kept for old apps, every action checked (never an invented number or link)."""
import json

from fastapi.testclient import TestClient

from app.services import answer_card as ac

SMS_FACTS = ("SMS text: Rs 8,551 received for NSE trade bills bit.ly/3xK9 -INNOVATESECURITIES 6:20 PM. "
             "Sender: JK-INNOVT-S")
SMS_REPLY = ("ఈ SMS ఇంకా నమ్మకండి. ముందు ఒక్కసారి check చేయండి.\n[[more]]\n## చేయకూడనివి\n- [risk] Link నొక్కకండి\n"
             "- [risk] OTP చెప్పకండి\n## Choose\n- ఖాతా ఉంది\n- వీళ్ళెవరో తెలియదు\n- డబ్బు పోయింది")

MODEL_CARD = {
    "kind": "check", "label": "SMS check", "headline": "ఈ SMS ఇంకా నమ్మకండి. ముందు check చేయండి.",
    "speak": "ఈ SMS ఇంకా నమ్మకండి.", "risk": "careful", "risk_label": "జాగ్రత్త",
    "seen": {"title": "SMS లో నేను చూసినవి", "text": "Rs 8,551 received for NSE trade bills bit.ly/3xK9 -INNOVATESECURITIES",
             "marks": [{"text": "8,551", "kind": "money"}, {"text": "bit.ly/3xK9", "kind": "link"},
                       {"text": "INNOVATESECURITIES", "kind": "sender"}, {"text": "NOT IN TEXT", "kind": "money"}]},
    "tabs": [],
    "donts": [{"icon": "link", "text": "Link నొక్కకండి"}, {"icon": "otp", "text": "OTP చెప్పకండి"},
              {"icon": "reply", "text": "Reply ఇవ్వకండి"}, {"icon": "pin", "text": "four is too many"}],
    "replies": [
        {"label": "ఖాతా ఉంది", "tone": "ok", "text": "మామూలు alert అయ్యుండొచ్చు.", "actions": []},
        {"label": "తెలియదు", "tone": "warn", "text": "Scam అవ్వొచ్చు.",
         "actions": [{"kind": "sms", "label": "Spam report", "value": "1909"},
                     {"kind": "block_help", "label": "Number block", "value": ""}]},
        {"label": "డబ్బు పోయింది", "tone": "danger", "text": "వెంటనే call చేయండి.",
         "actions": [{"kind": "call", "label": "1930 call", "value": "1930"},
                     {"kind": "bank_help", "label": "Bank కి call", "value": ""},
                     {"kind": "call", "label": "fake", "value": "8551"}]},
    ],
    "primary": {"kind": "open_upi", "label": "Bank చూడండి", "value": ""},
    "actions": [{"kind": "open_url", "label": "Evil", "value": "https://evil.example/x"},
                {"kind": "open_url", "label": "Report", "value": "https://cybercrime.gov.in"}],
    "share": True,
}


def test_clean_keeps_safe_card_and_drops_unsafe_bits():
    card = ac.clean(MODEL_CARD, reply=SMS_REPLY, user_text="e sms akadi unchi vachidhi", facts=SMS_FACTS)
    assert card["kind"] == "check" and card["risk"] == "careful" and card["share"] is True
    assert [m["kind"] for m in card["seen"]["marks"]] == ["money", "link", "sender"]  # mark not in text dropped
    assert len(card["donts"]) == 3
    money_lost = card["replies"][2]
    assert [a["kind"] for a in money_lost["actions"]] == ["call", "bank_help"]  # 8551 (an amount) never dialled
    assert card["replies"][1]["actions"][0] == {"kind": "sms", "label": "Spam report", "value": "1909"}
    assert card["primary"]["kind"] == "open_upi"
    assert card["actions"] == [{"kind": "open_url", "label": "Report", "value": "https://cybercrime.gov.in"}]


def test_clean_needs_a_headline_and_caps_tabs():
    assert ac.clean({"tabs": []}, reply="x") is None
    assert ac.clean("nope", reply="x") is None
    tabs = [{"id": "a", "label": f"T{i}", "icon": "money", "style": "cards",
             "items": [{"title": "Shishu", "value": "₹50,000", "sub": "up to", "body": "new shop"}]} for i in range(6)]
    card = ac.clean({"headline": "₹20 lakh వరకు loan.", "tabs": tabs}, reply="r")
    assert len(card["tabs"]) == 4 and len({t["id"] for t in card["tabs"]}) == 4
    assert card["kind"] == "answer" and card["risk"] is None and card["share"] is False


def test_call_numbers_only_helplines_or_full_numbers_in_the_text():
    src = "Call the bank on 1800 425 3800 or 1930."
    ok = ac._action({"kind": "call", "label": "Bank", "value": "1800 425 3800"}, src, set())
    assert ok == {"kind": "call", "label": "Bank", "value": "18004253800"}
    assert ac._action({"kind": "call", "label": "x", "value": "9999999999"}, src, set()) is None
    assert ac._action({"kind": "sms", "label": "x", "value": "5555"}, src, set()) is None
    assert ac._action({"kind": "launch_rocket", "label": "x"}, src, set()) is None


def test_spoken_part_and_mark_removal():
    assert ac.spoken_part(SMS_REPLY) == "ఈ SMS ఇంకా నమ్మకండి. ముందు ఒక్కసారి check చేయండి."
    assert ac.MARK not in ac.without_mark(SMS_REPLY)
    assert ac.spoken_part("plain answer") == "plain answer"


def test_text_card_without_a_model():
    card = ac.from_text(SMS_REPLY)
    assert card["headline"].startswith("ఈ SMS")
    assert [d["text"] for d in card["donts"]] == ["Link నొక్కకండి", "OTP చెప్పకండి"]
    assert [r["label"] for r in card["replies"]] == ["ఖాతా ఉంది", "వీళ్ళెవరో తెలియదు", "డబ్బు పోయింది"]


def test_text_card_reads_sections_steps_and_abc_choices():
    reply = ("Mudra gives up to ₹20 lakh without collateral.\n[[more]]\n## Types\n- Shishu: up to ₹50,000\n"
             "- Kishor: up to ₹5 lakh\n## How\n1. Go to the bank\n2. Give papers\n3. Loan comes\n"
             "Tell me: (a) new shop, (b) running shop, or (c) big business.")
    card = ac.from_text(reply)
    assert [t["label"] for t in card["tabs"]] == ["Types", "How"]
    assert card["tabs"][0]["items"][0] == {"title": "Shishu", "value": "", "sub": "", "body": "up to ₹50,000"}
    assert card["tabs"][1]["style"] == "steps" and len(card["tabs"][1]["items"]) == 3
    assert [r["label"] for r in card["replies"]] == ["new shop", "running shop", "big business"]


def test_no_stray_dash_lines_become_content():
    card = ac.from_text("Answer.\n[[more]]\n## Watch out\n-\n- [risk] Don't tap the link\n-\n- [caution] Never share OTP")
    assert [d["text"] for d in card["donts"]] == ["Don't tap the link", "Never share OTP"]
    assert all(t["items"] or t["note"] for t in card["tabs"])


def test_build_uses_the_model_card_and_falls_back_on_bad_json():
    prompts = []

    def writer(prompt):
        prompts.append(prompt)
        return "```json\n" + json.dumps(MODEL_CARD, ensure_ascii=False) + "\n```"

    card = ac.build(writer, reply=SMS_REPLY, user_text="e sms", facts=SMS_FACTS)
    assert card["kind"] == "check" and "INNOVATESECURITIES" in prompts[0] and ac.MARK not in prompts[0]
    bad = ac.build(lambda p: "not json", reply=SMS_REPLY, facts=SMS_FACTS)
    assert bad["kind"] == "answer" and bad["donts"]
    # A short chat reply never costs a model call.
    calls = []
    ac.build(lambda p: calls.append(p) or "", reply="Hi! How can I help?")
    assert calls == []


def _route(monkeypatch, reply, caps, writer_text=""):
    from server import app, container

    seen = {}

    class _Brain:
        any_model = True

        def decide(self, message, **kwargs):
            seen.update(kwargs)
            return {"reply": reply, "domain": "GENERAL", "transactional": False, "action": "chat",
                    "confidence": 0.9, "entities": {}, "suggestions": ["Bank చూడండి", "1930"]}

        def split_app_context(self, message):
            return message, "", False

        def attachment_facts_of(self, message):
            return ""

        def write_text(self, prompt, max_tokens=1024):
            return writer_text

    monkeypatch.setattr(container, "universal_ai_assistant_service", _Brain())
    body = TestClient(app).post("/api/in-app/assistant", json={
        "message": "e sms akadi unchi vachidhi", "locale": "en", "capabilities": caps}).json()
    return body, seen


def test_route_sends_card_and_language_only_to_new_apps(monkeypatch):
    caps = ["meaning_tags", "app_actions", "shop_menu", "suggestions", "phase1_only", "talk_brief", "auto_open",
            "shopping_mode", "shopping_tools", "buyer_mode", "answer_card"]  # 11 > the old limit of 10
    body, seen = _route(monkeypatch, SMS_REPLY, caps, json.dumps(MODEL_CARD, ensure_ascii=False))
    if body["source"] != "universal_ai":  # ai.assistant flag off in this DB
        return
    assert seen["locale"] == "te" and body["reply_language"] == "te"
    assert body["card"]["kind"] in ("check", "answer") and body["card"]["headline"]
    assert ac.MARK in body["reply"]
    old, _ = _route(monkeypatch, SMS_REPLY, ["suggestions"])
    assert old["card"] is None and ac.MARK not in old["reply"]


def test_language_the_person_chose_is_kept(monkeypatch):
    body, seen = _route(monkeypatch, "Sure.", ["answer_card", "lang_lock"])
    if body["source"] == "universal_ai":
        assert seen["locale"] == "en" and body["reply_language"] == "en"
