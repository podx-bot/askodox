import asyncio

import pytest

from app.api.routes.in_app_assistant import (
    AssistantRequest,
    SpeakRequest,
    assistant_decision,
    speak_in_app_reply,
)
from app.services.universal_category_flow_brain import UniversalCategoryFlowBrain
from fastapi import HTTPException


class _FakeAIAssistantService:
    def __init__(self, decision):
        self._decision = decision

    def decide(self, message, *, history, locale, location):
        return self._decision


class _FakeVoiceAssistantService:
    def __init__(self, synth_result=None):
        self._synth_result = synth_result or {}

    def synthesize(self, text):
        return self._synth_result


class _Container:
    def __init__(self, decision=None, synth_result=None):
        self.universal_ai_assistant_service = _FakeAIAssistantService(decision)
        self.universal_category_flow_brain = UniversalCategoryFlowBrain()
        self.voice_assistant_service = _FakeVoiceAssistantService(synth_result)
        self.buyer_intelligence_service = None


class _State:
    def __init__(self, container):
        self.container = container


class _App:
    def __init__(self, container):
        self.state = _State(container)


class _Request:
    def __init__(self, container):
        self.app = _App(container)


def _decision(**overrides):
    base = {
        "reply": "Sure, checking that for you.",
        "domain": "PRODUCT",
        "transactional": True,
        "action": "buy",
        "confidence": 0.9,
        "entities": {},
    }
    base.update(overrides)
    return base


def test_active_role_is_seller_for_clear_sell_intent():
    container = _Container(decision=_decision())
    request = _Request(container)
    payload = AssistantRequest(message="నా TV అమ్మాలి", locale="te", history=[], location="")

    result = assistant_decision(payload, request)

    assert result.active_role == "SELLER"
    assert result.active_role_confidence >= 0.75


def test_active_role_is_buyer_for_clear_buy_intent():
    container = _Container(decision=_decision())
    request = _Request(container)
    payload = AssistantRequest(message="TV కావాలి", locale="te", history=[], location="")

    result = assistant_decision(payload, request)

    assert result.active_role == "BUYER"


def test_active_role_is_empty_for_low_confidence_general_chat():
    container = _Container(decision=_decision(domain="GENERAL", transactional=False))
    request = _Request(container)
    payload = AssistantRequest(message="hello there", locale="en", history=[], location="")

    result = assistant_decision(payload, request)

    assert result.active_role == ""


def test_active_role_switches_between_consecutive_messages():
    # Active Role must re-derive per message and must not stick to a
    # previous request's role -- see instruction 7 ("old role context must
    # not cause incorrect questions or results").
    container = _Container(decision=_decision())
    request = _Request(container)

    sell = assistant_decision(
        AssistantRequest(message="నా TV అమ్మాలి", locale="te", history=[], location=""), request
    )
    buy = assistant_decision(
        AssistantRequest(message="నాకు fridge కావాలి", locale="te", history=[], location=""), request
    )

    assert sell.active_role == "SELLER"
    assert buy.active_role == "BUYER"


def test_active_role_present_even_when_ai_decision_is_unavailable():
    container = _Container(decision=None)
    request = _Request(container)
    payload = AssistantRequest(message="నేను AC repair చేస్తాను", locale="te", history=[], location="")

    result = assistant_decision(payload, request)

    assert result.source == "fallback"
    assert result.active_role == "SERVICE_PROVIDER"


def test_voice_speak_returns_audio_bytes_on_success():
    container = _Container(
        synth_result={
            "success": True,
            "content": b"ogg-bytes",
            "mime_type": "audio/ogg",
        }
    )
    request = _Request(container)
    payload = SpeakRequest(text="Your order is confirmed.", locale="en")

    response = asyncio.run(speak_in_app_reply(payload, request))

    assert response.body == b"ogg-bytes"
    assert response.media_type == "audio/ogg"


def test_voice_speak_raises_502_when_synthesis_fails():
    container = _Container(synth_result={"success": False, "status": "SARVAM_TTS_ERROR"})
    request = _Request(container)
    payload = SpeakRequest(text="Your order is confirmed.", locale="en")

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(speak_in_app_reply(payload, request))

    assert exc_info.value.status_code == 502
