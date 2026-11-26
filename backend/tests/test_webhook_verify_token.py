"""The WhatsApp webhook verify token has NO built-in value (public repo): unset = verification refused."""
from types import SimpleNamespace

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import fast_webhook, webhook
from app.core import settings as settings_module


def _client(router, token):
    app = FastAPI()
    app.include_router(router)
    app.state.container = SimpleNamespace(settings=SimpleNamespace(whatsapp_webhook_verify_token=token))
    return TestClient(app)


def _ask(client, token):
    return client.get("/webhook", params={"hub.mode": "subscribe", "hub.verify_token": token, "hub.challenge": "42"})


def test_no_default_token(monkeypatch):
    monkeypatch.delenv("WHATSAPP_WEBHOOK_VERIFY_TOKEN", raising=False)
    assert settings_module.load_settings().whatsapp_webhook_verify_token == ""


def test_unset_token_refuses_everything():
    for router in (webhook.router, fast_webhook.router):
        client = _client(router, "")
        assert _ask(client, "").status_code == 403
        assert _ask(client, "podx_verify_2026").status_code == 403


def test_right_token_verifies_wrong_one_does_not():
    for router in (webhook.router, fast_webhook.router):
        client = _client(router, "my-own-long-private-word")
        good = _ask(client, "my-own-long-private-word")
        assert good.status_code == 200 and good.text == "42"
        assert _ask(client, "something-else").status_code == 403
