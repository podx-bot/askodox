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


# --- Command Center "Check now": one real call per provider -----------------

class _GenaiModels:
    def __init__(self, error=None):
        self.error, self.calls = error, 0

    def generate_content(self, **_):
        self.calls += 1
        if self.error:
            raise self.error
        return SimpleNamespace(text="OK")


class _Http:
    def __init__(self, status=200, body=None):
        self.status, self.body, self.calls = status, body or {"output_text": "OK"}, 0

    def post(self, url, **_):
        self.calls += 1
        return httpx.Response(self.status, json=self.body, request=httpx.Request("POST", url))


class _QuotaError(Exception):
    code = 429

    def __str__(self):
        return "429 RESOURCE_EXHAUSTED"


SECRETS = {"gemini_api_key": "gm-SECRET-gem", "openai_api_key": "oa-SECRET-oai",
           "sarvam_api_key": "sv-SECRET-sar", "brave_search_api_key": "br-SECRET-brv"}


@pytest.fixture
def cc_client(monkeypatch):
    from server import app, container

    key = "owner-chk-" + uuid.uuid4().hex[:6]
    from app.api.routes.command_center import command_center

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=key, **SECRETS))
    yield TestClient(app), container, {"X-ASKODOX-Admin-Key": key}
    # Check results persist in the shared per-run DB: leave none behind.
    with command_center(container)._connect() as conn:
        conn.execute("DELETE FROM integration_checks WHERE name IN "
                     "('gemini','openai','sarvam','brave_search','mobility')")


def _brain(models=None, http=None, *, gemini="gm-SECRET-gem", openai="oa-SECRET-oai"):
    from app.services.universal_ai_assistant_service import UniversalAIAssistantService

    return UniversalAIAssistantService(None, api_key=gemini, model="gemini-test",
                                       client=SimpleNamespace(models=models or _GenaiModels()) if gemini else None,
                                       openai_api_key=openai, http_client=http or _Http())


def _check(client, headers, name):
    response = client.post(f"/admin/cc/integrations/{name}/check", headers=headers)
    assert response.status_code == 200, response.text
    for secret in SECRETS.values():
        assert secret not in response.text, "no credential in a check response"
    return response.json()


def test_blank_or_whitespace_keys_are_not_configured():
    assert not ph.has_key("") and not ph.has_key("   ") and not ph.has_key(None)
    assert ph.has_key("k")


def test_gemini_check_is_live_only_when_gemini_answers(cc_client, monkeypatch):
    client, container, headers = cc_client
    http = _Http()
    monkeypatch.setattr(container, "universal_ai_assistant_service", _brain(_GenaiModels(), http))
    body = _check(client, headers, "gemini")
    assert body["result"]["state"] == "LIVE" and body["result"]["ok"] is True
    if body["item"]["enabled"]:
        assert body["item"]["status"] == "ok"
    assert http.calls == 0, "a Gemini check never calls OpenAI"
    assert ph.state("gemini", configured=True)["state"] == ph.LIVE

    # Gemini failing must not be rescued by the OpenAI fallback.
    monkeypatch.setattr(container, "universal_ai_assistant_service",
                        _brain(_GenaiModels(RuntimeError("boom")), http))
    body = _check(client, headers, "gemini")
    assert body["result"]["state"] == "ERROR" and http.calls == 0
    assert "boom" not in str(body)


def test_gemini_quota_is_quota_exhausted(cc_client, monkeypatch):
    client, container, headers = cc_client
    monkeypatch.setattr(container, "universal_ai_assistant_service", _brain(_GenaiModels(_QuotaError())))
    body = _check(client, headers, "gemini")
    assert body["result"]["state"] == "QUOTA_EXHAUSTED"
    if body["item"]["enabled"]:
        assert body["item"]["status"] == "quota_exhausted"


@pytest.mark.parametrize("status,body,expected", [
    (200, {"output_text": "OK"}, "LIVE"),
    (429, {"error": {"code": "insufficient_quota", "message": "secret-ish text"}}, "QUOTA_EXHAUSTED"),
    (401, {"error": {"code": "invalid_api_key"}}, "ERROR"),
])
def test_openai_check_reports_its_own_answer(cc_client, monkeypatch, status, body, expected):
    client, container, headers = cc_client
    models = _GenaiModels()
    monkeypatch.setattr(container, "universal_ai_assistant_service", _brain(models, _Http(status, body)))
    result = _check(client, headers, "openai")["result"]
    assert result["state"] == expected and models.calls == 0
    assert "secret-ish" not in str(result), "no provider response body"
    if status == 401:
        assert "credentials" in result["detail"]


def test_a_new_failed_check_is_never_shown_as_the_old_success(cc_client, monkeypatch):
    client, container, headers = cc_client
    monkeypatch.setattr(container, "universal_ai_assistant_service", _brain(http=_Http(200)))
    assert _check(client, headers, "openai")["result"]["state"] == "LIVE"
    monkeypatch.setattr(container, "universal_ai_assistant_service", _brain(http=_Http(503, {"error": {}})))
    body = _check(client, headers, "openai")
    assert body["result"]["state"] == "ERROR" and body["result"]["ok"] is False
    assert body["item"]["status"] == "error", "the old LIVE never covers a newer failed check"
    items = {i["name"]: i for i in client.get("/admin/cc/integrations", headers=headers).json()["items"]}
    assert items["openai"]["status"] == "error"


def test_missing_credentials_need_configuration(cc_client, monkeypatch):
    client, container, headers = cc_client
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, gemini_api_key="   "))
    body = _check(client, headers, "gemini")
    assert body["result"]["state"] == "NEEDS_CONFIGURATION" and body["item"]["status"] == "not_configured"


class _Voice:
    def __init__(self, tts, stt):
        self.tts, self.stt, self.fallback_calls, self.stt_audio = tts, stt, 0, None

    def _synthesize_sarvam(self, text, voice=""):
        return dict(self.tts)

    def _transcribe_sarvam_complete(self, audio_bytes, mime_type):
        self.stt_audio = (audio_bytes, mime_type)
        return dict(self.stt)

    def transcribe(self, audio_bytes, mime_type):  # the Gemini fallback path
        self.fallback_calls += 1
        return {"success": True, "transcript": "fallback"}


def test_sarvam_check_uses_real_tts_content_and_direct_stt(cc_client, monkeypatch):
    client, container, headers = cc_client
    voice = _Voice({"success": True, "status": "SYNTHESIZED_SARVAM_STREAM", "content": b"OggS-audio",
                    "mime_type": "audio/ogg"}, {"success": True, "transcript": "askodox check"})
    monkeypatch.setattr(container, "voice_assistant_service", voice)
    result = _check(client, headers, "sarvam")["result"]
    assert result["state"] == "LIVE" and result["detail"] == "TTS: LIVE; STT: LIVE"
    assert voice.stt_audio == (b"OggS-audio", "audio/ogg"), "the synthesized `content` bytes are transcribed"
    assert voice.fallback_calls == 0, "STT is verified on Sarvam itself, never via the Gemini fallback"
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.LIVE
    assert ph.state("sarvam_tts", configured=True)["state"] == ph.LIVE


def test_sarvam_402_is_quota_exhausted_and_stt_still_called(cc_client, monkeypatch):
    client, container, headers = cc_client
    voice = _Voice({"success": False, "status": "SARVAM_TTS_HTTP_402"},
                   {"success": False, "status": "SARVAM_HTTP_402"})
    monkeypatch.setattr(container, "voice_assistant_service", voice)
    body = _check(client, headers, "sarvam")
    assert body["result"]["state"] == "QUOTA_EXHAUSTED"
    assert voice.stt_audio and voice.stt_audio[1] == "audio/wav", "STT probed with real (silent) audio"
    assert ph.state("sarvam_stt", configured=True)["state"] == ph.QUOTA_EXHAUSTED
    if body["item"]["enabled"]:
        assert body["item"]["status"] == "quota_exhausted"


def test_brave_last_good_copy_is_not_a_live_success(cc_client, monkeypatch):
    client, container, headers = cc_client

    class _Brave:
        last_stale_at = "2026-10-01T00:00:00+00:00"
        last_error = True

        def __call__(self, query, limit):
            return [{"title": "stored", "url": "https://x.example"}]

        def health_snapshot(self):
            return {"state": "quota_exhausted", "http_status": 402}

    monkeypatch.setattr(container, "brave_web_search_provider", _Brave(), raising=False)
    result = _check(client, headers, "brave_search")["result"]
    assert result["state"] == "QUOTA_EXHAUSTED" and result["ok"] is False


@pytest.mark.parametrize("enabled,partners,status", [
    (False, [], "disabled"),
    (True, [], "not_configured"),
    (True, [{"status": "ACTIVE", "data": {"available": False}}], "degraded"),
    (True, [{"status": "ACTIVE", "data": {"available": True}}, {"status": "PENDING_REVIEW"}], "ok"),
])
def test_mobility_readiness_needs_flag_and_an_approved_online_partner(monkeypatch, enabled, partners, status):
    import app.api.routes.platform as platform_routes
    from app.api.routes.command_center import _mobility_readiness

    monkeypatch.setattr(platform_routes, "platform", lambda container: SimpleNamespace(
        resources=SimpleNamespace(repo=SimpleNamespace(list=lambda resource: partners))))
    assert _mobility_readiness(None, {"delivery.matching": {"enabled": enabled}})["status"] == status


def test_mobility_check_is_a_known_integration(cc_client):
    client, _, headers = cc_client
    result = _check(client, headers, "mobility")["result"]
    assert result["state"] in {"LIVE", "DISABLED", "NEEDS_CONFIGURATION", "DEGRADED"}


def test_cc_health_maps_quota_exhausted_without_error(cc_client, monkeypatch):
    client, container, headers = cc_client
    ph.record("sarvam_stt", reason="SARVAM_HTTP_402")
    response = client.get("/admin/cc/health", headers=headers)
    assert response.status_code == 200
