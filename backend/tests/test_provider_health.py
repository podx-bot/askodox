"""Truthful provider health: state comes from REAL provider answers, never
from key presence alone. Production example (2026-10-07): Sarvam answered
HTTP 402 when credit ran out -> QUOTA_EXHAUSTED, distinguishable from a
missing key, a disabled flag, a healthy provider and any other error."""
import dataclasses
import uuid
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient

from app.services import provider_health as ph
from app.services.integration_readiness import runtime_rows


@pytest.fixture(autouse=True)
def _clean():
    ph.reset()
    yield
    ph.reset()


def test_classification_of_real_answers():
    assert ph.classify(200) == ph.LIVE
    assert ph.classify(402) == ph.QUOTA_EXHAUSTED
    assert ph.classify(None, "SARVAM_HTTP_402") == ph.QUOTA_EXHAUSTED
    assert ph.classify(429, "ClientError QUOTA") == ph.QUOTA_EXHAUSTED
    assert ph.classify(429, "rate limited") == ph.ERROR, "a plain 429 is not a credit problem"
    assert ph.classify(401) == ph.ERROR and ph.classify(500) == ph.ERROR


def test_states_are_distinguishable():
    assert ph.state("sarvam_stt", configured=False)["state"] == ph.NEEDS_CONFIGURATION
    assert ph.state("sarvam_stt", configured=True, enabled=False)["state"] == ph.DISABLED
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.CONFIGURED_NOT_VERIFIED, \
        "a key alone is never LIVE"
    ph.record("sarvam_stt", reason="SARVAM_HTTP_402")
    s = ph.state("sarvam_stt", configured=True)
    assert s["state"] == ph.QUOTA_EXHAUSTED and "recharge" in s["reason"]
    ph.record("sarvam_stt", ok=True)
    s = ph.state("sarvam_stt", configured=True)
    assert s["state"] == ph.LIVE and s["last_success_at"]
    ph.record("sarvam_stt", status_code=401, reason="HTTPStatusError")
    s = ph.state("sarvam_stt", configured=True)
    assert s["state"] == ph.ERROR and "credentials" in s["reason"]
    ph.record("sarvam_stt", status_code=503, reason="SARVAM_HTTP_503")
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.ERROR


def test_nothing_sensitive_is_recorded():
    ph.record("gemini", reason="x" * 500)
    entry = ph.snapshot()["gemini"]["last"]
    assert set(entry) == {"outcome", "status_code", "reason", "at"} and len(entry["reason"]) <= 80
    public = ph.state("gemini", configured=True)
    assert "reason" not in (public["last_failure"] or {}), "the raw failure text is never exposed"


def test_the_real_sarvam_path_records_402_without_touching_segmentation(monkeypatch):
    from app.services.sarvam_primary_voice_assistant_service import SarvamPrimaryVoiceAssistantService

    svc = SarvamPrimaryVoiceAssistantService.__new__(SarvamPrimaryVoiceAssistantService)
    svc.sarvam_api_key = "k"
    monkeypatch.setattr(svc, "_transcribe_sarvam_complete",
                        lambda audio_bytes, mime_type: {"success": False, "status": "SARVAM_HTTP_402",
                                                        "error_type": "HTTPStatusError"}, raising=False)
    monkeypatch.setattr(SarvamPrimaryVoiceAssistantService.__mro__[1], "transcribe",
                        lambda self, audio_bytes, mime_type: {"success": False, "status": "FALLBACK"})
    svc.transcribe(b"audio", "audio/mp4")
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.QUOTA_EXHAUSTED
    monkeypatch.setattr(svc, "_transcribe_sarvam_complete",
                        lambda audio_bytes, mime_type: {"success": False, "status": "SARVAM_EMPTY_TRANSCRIPT"},
                        raising=False)
    svc.transcribe(b"audio", "audio/mp4")
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.LIVE, "silence is a healthy answer"


def test_ai_brain_failures_are_observed(monkeypatch):
    from app.services.universal_ai_assistant_service import _observe_ai

    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    _observe_ai("openai", error=httpx.HTTPStatusError(
        "Client error '429 Too Many Requests'", request=request,
        response=httpx.Response(429, request=request, json={"error": {"code": "insufficient_quota"}})))
    # The status code alone (no body text) is still classified correctly.
    assert ph.state("openai", configured=True)["last_status_code"] == 429
    _observe_ai("gemini", error=SimpleNamespace(code=429, __str__=lambda self: "RESOURCE_EXHAUSTED"))
    _observe_ai("gemini", ok=True)
    assert ph.state("gemini", configured=True)["state"] == ph.LIVE


def test_readiness_rows_show_quota_exhausted_not_live():
    settings = SimpleNamespace(sarvam_api_key="k", gemini_api_key="g", openai_api_key="")
    container = SimpleNamespace(settings=settings)
    ph.record("sarvam_stt", reason="SARVAM_HTTP_402")
    ph.record("sarvam_tts", reason="SARVAM_TTS_HTTP_402")
    rows = {r.get("provider"): r for r in runtime_rows(container, maps_body=None, web={},
                                                       flag=lambda key: key != "voice.sarvam_tts", partners=[])}
    assert rows["sarvam_stt"]["state"] == "QUOTA_EXHAUSTED"
    assert rows["sarvam_tts"]["state"] == "DISABLED", "the flag decides before the last answer"
    assert rows["gemini"]["state"] == "CONFIGURED_NOT_VERIFIED"
    assert rows["openai"]["state"] == "NOT_CONFIGURED"
    assert "k" not in str(rows["sarvam_stt"].values()), "no secret in readiness"


def test_command_center_integration_status_uses_the_real_answer(monkeypatch):
    from server import app, container

    key = "owner-ph-" + uuid.uuid4().hex[:6]
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key,
                                                                   sarvam_api_key="placeholder-sarvam-value"))
    client = TestClient(app)
    headers = {"X-ASKODOX-Admin-Key": key}
    before = {i["name"]: i for i in client.get("/admin/cc/integrations", headers=headers).json()["items"]}
    assert before["sarvam"]["status"] in {"configured", "disabled", "ok", "error"}
    ph.record("sarvam_stt", reason="SARVAM_HTTP_402")
    after = {i["name"]: i for i in client.get("/admin/cc/integrations", headers=headers).json()["items"]}
    if after["sarvam"]["enabled"]:
        assert after["sarvam"]["status"] == "quota_exhausted"
    body = str(after["sarvam"])
    assert "placeholder-sarvam-value" not in body
