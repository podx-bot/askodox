import json

from google.genai import errors as genai_errors

from app.services.universal_ai_assistant_service import UniversalAIAssistantService


class _FakeResponse:
    def __init__(self, text: str) -> None:
        self.text = text


class _FakeModels:
    def __init__(self, reply_json: dict) -> None:
        self._reply_json = reply_json
        self.calls: list[str] = []

    def generate_content(self, *, model, contents, config):
        self.calls.append(contents)
        return _FakeResponse(json.dumps(self._reply_json))


class _FlakyThenSuccessModels:
    """Raises a Gemini 503 ServerError a fixed number of times, then succeeds.

    Mirrors what production logs actually showed: 'This model is currently
    experiencing high demand ... usually temporary' followed shortly after
    by a normal successful response for the same kind of request.
    """

    def __init__(self, reply_json: dict, *, fail_times: int) -> None:
        self._reply_json = reply_json
        self._fail_times = fail_times
        self.call_count = 0

    def generate_content(self, *, model, contents, config):
        self.call_count += 1
        if self.call_count <= self._fail_times:
            raise genai_errors.ServerError(
                503, {"error": {"code": 503, "status": "UNAVAILABLE"}}
            )
        return _FakeResponse(json.dumps(self._reply_json))


class _FakeGenaiClient:
    def __init__(self, reply_json: dict) -> None:
        self.models = _FakeModels(reply_json)


def _service(reply_json: dict) -> tuple[UniversalAIAssistantService, _FakeGenaiClient]:
    client = _FakeGenaiClient(reply_json)
    service = UniversalAIAssistantService(
        delegate=None,
        api_key="test-key",
        model="gemini-test",
        client=client,
    )
    return service, client


def _flaky_service(reply_json: dict, *, fail_times: int):
    client = type("Client", (), {})()
    client.models = _FlakyThenSuccessModels(reply_json, fail_times=fail_times)
    service = UniversalAIAssistantService(
        delegate=None,
        api_key="test-key",
        model="gemini-test",
        client=client,
    )
    return service, client


def test_transient_503_is_retried_and_succeeds(monkeypatch):
    # Production logs showed Gemini returning a 503 "high demand" ServerError
    # that cleared a moment later. The service must retry instead of
    # immediately falling back to the generic reply on the first 503.
    monkeypatch.setattr(
        "app.services.universal_ai_assistant_service.time.sleep", lambda _seconds: None
    )
    service, client = _flaky_service(
        {
            "reply": "Sure, checking chicken sellers nearby.",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.9,
            "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
        },
        fail_times=2,
    )

    decision = service.decide("నాకు 5 కిలోల చికెన్ కావాలి", history=[], locale="te", location="")

    assert decision is not None
    assert decision["reply"] == "Sure, checking chicken sellers nearby."
    assert client.models.call_count == 3


def test_persistent_503_exhausts_retries_and_falls_back(monkeypatch):
    # If Gemini stays unavailable for all retry attempts, decide() must still
    # degrade to None (the app's safe fallback path) rather than raising.
    monkeypatch.setattr(
        "app.services.universal_ai_assistant_service.time.sleep", lambda _seconds: None
    )
    service, client = _flaky_service({"reply": "unused"}, fail_times=99)

    decision = service.decide("నాకు 5 కిలోల చికెన్ కావాలి", history=[], locale="te", location="")

    assert decision is None
    assert client.models.call_count == 3


def test_known_location_is_not_asked_for_again_and_is_filled_into_entities():
    # The model "forgets" to echo location back — the service must still
    # guarantee it lands in entities so the app never re-asks for it.
    service, client = _service(
        {
            "reply": "5 kg chicken order lo, meeku skinless kavala normal kavala cheppandi.",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.95,
            "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
        }
    )

    decision = service.decide(
        "నాకు 5 కిలోల చికెన్ కావాలి",
        history=[],
        locale="te",
        location="Vijayawada",
    )

    assert decision is not None
    assert decision["entities"]["location"] == "Vijayawada"

    prompt_sent = client.models.calls[0]
    assert "Known user location: Vijayawada" in prompt_sent
    assert "Do NOT ask the user for their" in prompt_sent


def test_model_supplied_location_is_kept_over_the_known_default():
    # If the user explicitly gives a different location in this message, the
    # model's own entity (not the stale known-default) must win.
    service, _ = _service(
        {
            "reply": "Sure, checking Guntur for you.",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.95,
            "entities": {"subject": "chicken", "location": "Guntur"},
        }
    )

    decision = service.decide(
        "chicken kావాలి, this time deliver to Guntur",
        history=[],
        locale="te",
        location="Vijayawada",
    )

    assert decision is not None
    assert decision["entities"]["location"] == "Guntur"


def test_location_question_is_stripped_even_if_model_still_asks():
    # Live testing showed the model doesn't always follow the "don't ask for
    # location" instruction -- the same known-location input sometimes still
    # produced a location question. The deterministic safety net must remove
    # any residual location question regardless of what the model returns.
    service, _ = _service(
        {
            "reply": "5 kilos chicken kavali ante, mee location ekkada cheppagalara?",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.9,
            "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
        }
    )

    decision = service.decide(
        "నాకు 5 కిలోల చికెన్ కావాలి",
        history=[],
        locale="te",
        location="Vijayawada",
    )

    assert decision is not None
    assert "location" not in decision["reply"].lower()
    assert "ekkada" not in decision["reply"].lower()
    assert decision["entities"]["location"] == "Vijayawada"


def test_location_question_stripped_but_other_sentence_kept():
    # Only the offending sentence should be removed -- a genuine follow-up
    # question about something else (like product variant) must survive.
    service, _ = _service(
        {
            "reply": "Meeku skinless kavala tho patu vastundi. Mee exact location cheppagalara?",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.9,
            "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
        }
    )

    decision = service.decide(
        "నాకు 5 కిలోల చికెన్ కావాలి",
        history=[],
        locale="te",
        location="Vijayawada",
    )

    assert decision is not None
    assert "skinless" in decision["reply"].lower()
    assert "location" not in decision["reply"].lower()


def test_no_known_location_leaves_prompt_and_entities_unaffected():
    service, client = _service(
        {
            "reply": "Sure, tell me the delivery location.",
            "domain": "FOOD",
            "transactional": True,
            "action": "buy",
            "confidence": 0.9,
            "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
        }
    )

    decision = service.decide(
        "నాకు 5 కిలోల చికెన్ కావాలి",
        history=[],
        locale="te",
        location="",
    )

    assert decision is not None
    assert "location" not in decision["entities"]

    prompt_sent = client.models.calls[0]
    assert "Known user location: none" in prompt_sent


class _AlwaysFailingModels:
    def __init__(self) -> None:
        self.call_count = 0

    def generate_content(self, *, model, contents, config):
        self.call_count += 1
        raise genai_errors.ServerError(503, {"error": {"code": 503, "status": "UNAVAILABLE"}})


class _FakeModelsCapturingConfig:
    def __init__(self, reply_json: dict) -> None:
        self._reply_json = reply_json
        self.configs: list = []

    def generate_content(self, *, model, contents, config):
        self.configs.append(config)
        return _FakeResponse(json.dumps(self._reply_json))


class _FakeOpenAIHttpResponse:
    def __init__(self, output_text: str, *, status_code: int = 200) -> None:
        self._output_text = output_text
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise RuntimeError(f"openai http error {self.status_code}")

    def json(self) -> dict:
        return {"output_text": self._output_text}


class _FakeOpenAIHttpClient:
    def __init__(self, output_text: str, *, status_code: int = 200) -> None:
        self._output_text = output_text
        self._status_code = status_code
        self.calls: list[dict] = []

    def post(self, url, *, headers, json):
        self.calls.append({"url": url, "headers": headers, "json": json})
        return _FakeOpenAIHttpResponse(self._output_text, status_code=self._status_code)


def test_openai_is_used_when_gemini_not_configured():
    http = _FakeOpenAIHttpClient(json.dumps({
        "reply": "Sure, checking chicken sellers nearby.",
        "domain": "FOOD",
        "transactional": True,
        "action": "buy",
        "confidence": 0.9,
        "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
    }))
    service = UniversalAIAssistantService(
        delegate=None,
        api_key="",
        model="gemini-test",
        client=None,
        openai_api_key="test-openai-key",
        openai_model="gpt-5",
        http_client=http,
    )

    decision = service.decide("నాకు 5 కిలోల చికెన్ కావాలి", history=[], locale="te", location="")

    assert decision is not None
    assert decision["reply"] == "Sure, checking chicken sellers nearby."
    assert len(http.calls) == 1
    assert http.calls[0]["headers"]["Authorization"] == "Bearer test-openai-key"


def test_openai_fallback_used_when_gemini_exhausts_retries(monkeypatch):
    monkeypatch.setattr(
        "app.services.universal_ai_assistant_service.time.sleep", lambda _seconds: None
    )
    client = type("Client", (), {})()
    client.models = _AlwaysFailingModels()
    http = _FakeOpenAIHttpClient(json.dumps({
        "reply": "Sure, checking chicken sellers nearby.",
        "domain": "FOOD",
        "transactional": True,
        "action": "buy",
        "confidence": 0.9,
        "entities": {"subject": "chicken", "quantity": 5, "unit": "kg"},
    }))
    service = UniversalAIAssistantService(
        delegate=None,
        api_key="test-key",
        model="gemini-test",
        client=client,
        openai_api_key="test-openai-key",
        http_client=http,
    )

    decision = service.decide("నాకు 5 కిలోల చికెన్ కావాలి", history=[], locale="te", location="")

    assert decision is not None
    assert client.models.call_count == 3
    assert len(http.calls) == 1


def test_gemini_config_disables_thinking_with_a_generous_output_budget():
    client = type("Client", (), {})()
    client.models = _FakeModelsCapturingConfig({
        "reply": "Sure, planning that for you.",
        "domain": "FOOD",
        "transactional": True,
        "action": "buy",
        "confidence": 0.9,
        "entities": {"subject": "chicken biryani", "headcount": 10},
    })
    service = UniversalAIAssistantService(
        delegate=None, api_key="test-key", model="gemini-test", client=client,
    )

    decision = service.decide(
        "repu maa intiki 10 member lunch ki vasthu naru valaki chicken birayni chayali",
        history=[],
        locale="te",
        location="",
    )

    assert decision is not None
    config = client.models.configs[0]
    assert config.thinking_config.thinking_budget == 0
    assert config.max_output_tokens >= 2048


def test_truncated_gemini_json_falls_back_to_openai():
    client = type("Client", (), {})()
    client.models = type("Models", (), {
        "generate_content": lambda self, **kwargs: _FakeResponse('{"reply": "'),
    })()
    http = _FakeOpenAIHttpClient(json.dumps({
        "reply": "Sure, planning that for you.",
        "domain": "GENERAL",
        "transactional": False,
        "action": "chat",
        "confidence": 0.9,
        "entities": {},
    }))
    service = UniversalAIAssistantService(
        delegate=None,
        api_key="test-key",
        model="gemini-test",
        client=client,
        openai_api_key="test-openai-key",
        http_client=http,
    )

    decision = service.decide(
        "repu maa intiki 10 member lunch ki vasthu naru valaki chicken birayni chayali",
        history=[],
        locale="te",
        location="",
    )

    assert decision is not None
    assert decision["reply"] == "Sure, planning that for you."
    assert len(http.calls) == 1
