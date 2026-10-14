"""Push readiness + staff test send: honest NOT_CONFIGURED without real
credentials, the Android client reported as not built, and a test send only
to the user's own devices with what FCM actually accepted."""
import dataclasses
import uuid

from fastapi.testclient import TestClient

from app.services.push_service import PushService
from tests.test_push_service import _FCM, _account

OWNER_KEY = "owner-push-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


def _env(monkeypatch, service):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY))
    monkeypatch.setattr(container, "push_service", service, raising=False)
    return TestClient(app)


def test_not_configured_is_said_plainly(monkeypatch, tmp_path):
    client = _env(monkeypatch, PushService(str(tmp_path / "p.db"), service_account_json=""))
    assert client.get("/admin/cc/push/readiness").status_code == 401
    ready = client.get("/admin/cc/push/readiness", headers=OWNER).json()
    assert ready["state"] == "NOT_CONFIGURED" and ready["server_credentials"] is False
    assert ready["android_client"] == "BUILT_NEEDS_FIREBASE_VALUES" and len(ready["missing"]) == 2
    sent = client.post("/admin/cc/push/test", headers=OWNER, json={"user_id": "app-phone-919000000001"})
    assert sent.status_code == 409 and sent.json()["detail"]["status"] == "NOT_CONFIGURED"


def test_configured_server_sends_only_to_registered_devices(monkeypatch, tmp_path):
    fcm = _FCM()
    service = PushService(str(tmp_path / "p.db"), service_account_json=_account(), client=fcm)
    client = _env(monkeypatch, service)
    user = "app-phone-919000000002"
    assert client.post("/admin/cc/push/test", headers=OWNER, json={"user_id": user}).json()["status"] == \
        "NO_DEVICE_TOKENS"
    service.register(user, "tok-1")
    ready = client.get("/admin/cc/push/readiness", headers=OWNER).json()
    assert ready["state"] == "READY_UNVERIFIED" and ready["device_tokens"] == 1, "never claimed as delivered"
    assert ready["android_client"] == "REGISTERING" and ready["missing"] == []
    out = client.post("/admin/cc/push/test", headers=OWNER, json={"user_id": user}).json()
    assert out == {"status": "SENT", "delivered": 1, "detail": "FCM accepted the message"}
    assert fcm.sent[-1]["token"] == "tok-1" and fcm.sent[-1]["data"]["route"] == "/updates"
    service.set_prefs(user, enabled=False, muted=[])
    off = client.post("/admin/cc/push/test", headers=OWNER, json={"user_id": user}).json()
    assert off["status"] == "NOT_DELIVERED" and off["delivered"] == 0, "the user's switch is respected"
