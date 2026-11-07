import base64

import httpx

from app.services.openai_image_service import OpenAIImageService


PNG_1PX = base64.b64encode(b"\x89PNG-fake").decode()


def _client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_without_key_returns_no_image_and_never_calls_provider():
    calls = []
    service = OpenAIImageService(api_key="", http_client=_client(lambda r: calls.append(r) or httpx.Response(500)))
    result, reason = service.edit([(b"img", "image/jpeg")], "make it blue")
    assert result is None and "OPENAI_API_KEY" in reason
    assert calls == []


def test_edit_sends_all_images_and_returns_decoded_png():
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["auth"] = request.headers.get("authorization")
        seen["body"] = request.read()
        return httpx.Response(200, json={"data": [{"b64_json": PNG_1PX}]})

    service = OpenAIImageService(api_key="sk-test", model="gpt-image-2.5", http_client=_client(handler))
    result, reason = service.edit([(b"one", "image/jpeg"), (b"two", "image/png")], "wig on second photo")
    assert reason == "" and result is not None
    assert result.data == b"\x89PNG-fake" and result.mime_type == "image/png"
    assert seen["url"].endswith("/v1/images/edits")
    assert seen["auth"] == "Bearer sk-test"
    assert seen["body"].count(b'name="image[]"') == 2
    assert b"wig on second photo" in seen["body"]


def test_provider_error_is_an_honest_no_result():
    service = OpenAIImageService(api_key="sk-test",
                                 http_client=_client(lambda r: httpx.Response(429, json={"error": "limit"})))
    result, reason = service.generate("a poster")
    assert result is None and reason


def test_unknown_size_falls_back_to_auto_and_empty_answer_is_no_result():
    seen = {}

    def handler(request):
        seen["body"] = request.read()
        return httpx.Response(200, json={"data": []})

    service = OpenAIImageService(api_key="sk-test", http_client=_client(handler))
    result, reason = service.generate("a poster", size="999x999")
    assert result is None and "no image" in reason
    assert b'"size":"auto"' in seen["body"]


def test_default_model_is_a_real_openai_id_and_errors_carry_openais_reason():
    from app.services.openai_image_service import DEFAULT_MODEL

    assert DEFAULT_MODEL == "gpt-image-2.5-sunburst"
    service = OpenAIImageService(api_key="sk-test", http_client=_client(lambda r: httpx.Response(
        400, json={"error": {"code": "invalid_value", "message": "Invalid value: 'gpt-image-2.5'."}})))
    result, reason = service.edit([(b"one", "image/jpeg")], "wig")
    assert result is None
    assert reason.startswith("HTTP 400 invalid_value") and "sk-test" not in reason
