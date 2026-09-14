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
