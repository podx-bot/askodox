"""Photo edit / create for every signed-in customer (/api/images/edit).
No network: the provider is a fake; no real key or number is used."""
import base64
import dataclasses

import pytest
from fastapi.testclient import TestClient

from app.services import platform_settings, rate_limit
from app.services.ai_credits import CreditsError
from app.services.openai_image_service import ImageResult
from app.services.session_tokens import issue_token

JPEG = base64.b64encode(b"\xff\xd8\xff" + b"j" * 40).decode()
PNG = base64.b64encode(b"\x89PNG" + b"p" * 40).decode()


class FakeProvider:
    configured = True

    def __init__(self, fail=False):
        self.fail = fail
        self.calls = []

    def edit(self, images, prompt):
        self.calls.append(("edit", [m for _, m in images], prompt))
        if self.fail:
            return None, "HTTPStatusError"
        return ImageResult(data=b"\x89PNG-edited", mime_type="image/png", model="fake-image"), ""

    def generate(self, prompt):
        self.calls.append(("create", [], prompt))
        return ImageResult(data=b"\x89PNG-new", mime_type="image/png", model="fake-image"), ""


class FakeCredits:
    def __init__(self, insufficient=False):
        self.insufficient = insufficient
        self.reserved, self.released = [], []

    def reserve(self, user, feature, ref):
        if self.insufficient:
            raise CreditsError("insufficient", 402)
        self.reserved.append((user, feature, ref))
        return {"charged": False, "reason": "charging_off", "paise": 0}

    def release(self, user, ref):
        self.released.append(ref)
        return True


@pytest.fixture()
def studio(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    settings = dataclasses.replace(container.settings, database_path=str(tmp_path / "studio.db"))
    monkeypatch.setattr(container, "settings", settings)
    credits = FakeCredits()
    monkeypatch.setattr(container, "ai_credits", credits, raising=False)
    provider = FakeProvider()
    monkeypatch.setattr(container, "openai_image_service", provider, raising=False)
    monkeypatch.setattr(platform_settings, "get", lambda key, default=None: 2 if key == "image_edit.daily_per_user"
                        else default)
    yield TestClient(app), container, provider, credits


def _bearer(container, phone="919800000123"):
    return {"Authorization": "Bearer " + issue_token(f"app-phone-{phone}", container.settings.session_token_secret)}


def _body(prompt="put the wig from the second photo on the man in the first photo", images=(JPEG, PNG)):
    return {"prompt": prompt, "images": [{"data_base64": i} for i in images], "language": "te"}


def test_sign_in_is_required(studio):
    client, _, provider, _ = studio
    assert client.post("/api/images/edit", json=_body()).status_code == 401
    assert provider.calls == []


def test_edit_returns_the_providers_picture_and_counts_one_credit_use(studio):
    client, container, provider, credits = studio
    body = client.post("/api/images/edit", json=_body(), headers=_bearer(container)).json()
    assert body["ok"] is True and body["kind"] == "edit"
    assert base64.b64decode(body["image_base64"]) == b"\x89PNG-edited"
    assert body["used_today"] == 1 and body["daily_limit"] == 2
    assert provider.calls == [("edit", ["image/jpeg", "image/png"], _body()["prompt"])]
    assert [f for _, f, _ in credits.reserved] == ["image"]


def test_words_without_photos_make_a_new_picture(studio):
    client, container, provider, _ = studio
    body = client.post("/api/images/edit", json=_body("a poster for my saree shop", images=()),
                       headers=_bearer(container)).json()
    assert body["ok"] is True and body["kind"] == "create" and provider.calls[0][0] == "create"


def test_daily_cap_is_per_user_and_failures_do_not_use_it_up(studio):
    client, container, provider, credits = studio
    me = _bearer(container)
    provider.fail = True
    failed = client.post("/api/images/edit", json=_body(), headers=me).json()
    assert failed["ok"] is False and failed["code"] == "provider_failed" and "image_base64" not in failed
    assert len(credits.released) == 1, "a failed picture gives the credit back"
    provider.fail = False
    assert client.post("/api/images/edit", json=_body(), headers=me).json()["ok"] is True
    assert client.post("/api/images/edit", json=_body(), headers=me).json()["ok"] is True
    capped = client.post("/api/images/edit", json=_body(), headers=me).json()
    assert capped == {"ok": False, "code": "daily_limit", "reason": capped["reason"], "daily_limit": 2,
                      "used_today": 2}
    other = client.post("/api/images/edit", json=_body(), headers=_bearer(container, "919800000999")).json()
    assert other["ok"] is True, "another person's limit is separate"


def test_no_key_and_switched_off_say_so_honestly(studio, monkeypatch):
    client, container, provider, _ = studio
    provider.configured = False
    body = client.post("/api/images/edit", json=_body(), headers=_bearer(container)).json()
    assert body["ok"] is False and body["code"] == "not_configured" and provider.calls == []
    provider.configured = True
    monkeypatch.setattr(platform_settings, "get", lambda key, default=None: 0)
    assert client.post("/api/images/edit", json=_body(), headers=_bearer(container)).json()["code"] == "off"


def test_bad_photo_and_low_credits_are_refused_before_the_provider(studio):
    client, container, provider, credits = studio
    bad = _body(images=(base64.b64encode(b"hello world, not a photo").decode(),))
    assert client.post("/api/images/edit", json=bad, headers=_bearer(container)).status_code == 415
    credits.insufficient = True
    low = client.post("/api/images/edit", json=_body(), headers=_bearer(container))
    assert low.status_code == 402 and low.json()["detail"] == "AI_CREDITS_LOW"
    assert provider.calls == []


def test_photo_analysis_asks_the_model_for_the_edit_request_from_the_words():
    from app.services.universal_image_service import UniversalImageService

    prompt = UniversalImageService._prompt("ఈ విగ్గు నాకు పెట్టండి")
    assert '"image_request":"EDIT|CREATE|NONE"' in prompt and "in any language" in prompt
