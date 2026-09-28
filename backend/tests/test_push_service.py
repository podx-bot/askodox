"""Background push: sends only when configured, once per event, on the
silent channel, and cleans up dead tokens. No real Firebase call here."""
import json
import uuid

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.services.push_service import PushService
from app.services.session_tokens import issue_token


class _Resp:
    def __init__(self, code, data=None, text=""):
        self.status_code, self._data, self.text = code, data or {}, text

    def json(self):
        return self._data


class _FCM:
    def __init__(self):
        self.sent = []

    def post(self, url, **kwargs):
        if url.endswith("/token"):
            assert kwargs["data"]["assertion"].count(".") == 2  # a signed JWT
            return _Resp(200, {"access_token": "access", "expires_in": 3600})
        token = kwargs["json"]["message"]["token"]
        self.sent.append(kwargs["json"]["message"])
        if token == "dead-token-000000000000":
            return _Resp(404, text='{"error": {"details": [{"errorCode": "UNREGISTERED"}]}}')
        return _Resp(200, {"name": "projects/p/messages/1"})


def _account():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    return json.dumps({"project_id": "askodox-test", "client_email": "push@askodox-test.iam", "private_key": pem})


def test_not_configured_sends_nothing(tmp_path):
    service = PushService(str(tmp_path / "p.db"), service_account_json="")
    service.register("u1", "token-aaaaaaaaaaaaaaaaaaaa")
    assert service.configured is False
    assert service.notify("u1", title="t", body="b", route="/orders/mine", event_key="e1") == 0


def test_silent_once_per_event_and_dead_tokens_removed(tmp_path):
    fcm = _FCM()
    service = PushService(str(tmp_path / "p.db"), service_account_json=_account(), client=fcm)
    service.register("u1", "live-token-000000000000")
    service.register("u1", "dead-token-000000000000")

    assert service.notify("u1", title="Chicken 5 kg", body="Accepted", route="/orders/mine", event_key="order:7:acc") == 1
    message = fcm.sent[0]
    assert message["android"]["notification"]["channel_id"] == "askodox_updates"
    assert message["data"]["route"] == "/orders/mine"
    assert service.tokens("u1") == ["live-token-000000000000"], "UNREGISTERED token is dropped"
    assert service.notify("u1", title="x", body="y", route="/", event_key="order:7:acc") == 0, "no duplicates"


def test_push_token_endpoint_needs_sign_in():
    from server import app, container

    client = TestClient(app)
    user = "app-phone-91" + str(uuid.uuid4().int)[:10]
    body = {"token": "fcm-token-" + "x" * 30}
    assert client.post("/api/me/push-token", json=body).status_code == 401
    headers = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    reply = client.post("/api/me/push-token", json=body, headers=headers).json()
    assert reply["registered"] is True and reply["push_configured"] is False
