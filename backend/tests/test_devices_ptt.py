"""Round 3: device registry / compatibility and internet push-to-talk.

Everything that touches a person's devices or voice is token-proven, scoped
to the caller, and deleted with the account; the compatibility catalog never
claims a protocol works that ASKODOX has not built."""
import base64

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit
from app.services.device_registry import COMPATIBILITY, match_services
from app.services.session_tokens import issue_token


@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "device_registry", None, raising=False)
    monkeypatch.setattr(container, "push_to_talk", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    return TestClient(app), auth


A, B, C = "app-9000000001", "app-9000000002", "app-9000000003"


def test_catalog_is_honest():
    statuses = {row["id"]: row["status"] for row in COMPATIBILITY}
    assert statuses["ble_weight_scale"] == "standard_profile_untested"
    assert all(s != "tested" for s in statuses.values()), "nothing is 'tested' without a real device"
    for unsupported in ("zigbee", "zwave", "uhf_rfid", "lora", "walkie_offline"):
        assert statuses[unsupported] in {"needs_hub", "unsupported_on_phone"}
    for row in COMPATIBILITY:
        assert row["limitations"] is not None


def test_service_matching_16_and_128_bit():
    assert [r["id"] for r in match_services(["181D"])] == ["ble_weight_scale"]
    assert [r["id"] for r in match_services(["0000181a-0000-1000-8000-00805f9b34fb", "0x180F"])] == \
        ["ble_environment", "ble_battery"]
    assert match_services(["feedface-0000-0000-0000-000000000000"]) == []


def test_device_registry_requires_sign_in_and_is_per_user(api):
    client, auth = api
    assert client.get("/api/devices").status_code == 401
    body = {"name": "Kitchen scale", "identifier": "AA:BB:CC:DD:EE:FF", "service_uuids": ["181d", "180f"]}
    added = client.post("/api/devices", json=body, headers=auth(A)).json()["device"]
    assert added["category"] == "weighing_scale" and added["capabilities"] == ["read_battery", "read_weight"]
    assert "AA:BB" not in str(added), "the raw Bluetooth address is never stored or returned"
    again = client.post("/api/devices", json={**body, "name": "Scale 2"}, headers=auth(A)).json()["device"]
    assert again["id"] == added["id"] and again["name"] == "Scale 2", "same device updates, no duplicate"
    assert client.get("/api/devices", headers=auth(B)).json()["devices"] == []
    assert client.delete(f"/api/devices/{added['id']}", headers=auth(B)).status_code == 404
    status = client.patch(f"/api/devices/{added['id']}", json={"status": "connected"}, headers=auth(A)).json()
    assert status["device"]["status"] == "connected" and status["device"]["last_seen"]
    assert client.delete(f"/api/devices/{added['id']}", headers=auth(A)).json()["removed"] is True
    assert client.get("/api/devices", headers=auth(A)).json()["devices"] == []


def test_unknown_device_kept_as_unknown_with_no_capabilities(api):
    client, auth = api
    device = client.post("/api/devices", json={"name": "Mystery", "identifier": "11:22:33:44:55:66",
                                               "service_uuids": ["fff0"]}, headers=auth(A)).json()["device"]
    assert device["category"] == "unknown" and device["capabilities"] == []


def test_ptt_group_flow_members_only(api):
    client, auth = api
    channel = client.post("/api/ptt/channels", json={"name": "Farm team", "display_name": "Ravi"},
                          headers=auth(A)).json()["channel"]
    code = channel["code"]
    assert len(code) == 6 and channel["members"] == 1
    clip = base64.b64encode(b"\x00\x00\x00\x18ftypM4A " + b"x" * 500).decode()
    # B is not a member yet
    assert client.post(f"/api/ptt/channels/{channel['id']}/clips", json={"audio_base64": clip},
                       headers=auth(B)).status_code == 403
    joined = client.post("/api/ptt/join", json={"code": code.lower(), "display_name": "Sita"}, headers=auth(B)).json()
    assert joined["channel"]["members"] == 2
    sent = client.post(f"/api/ptt/channels/{channel['id']}/clips",
                       json={"audio_base64": clip, "mime_type": "audio/mp4", "duration_ms": 3000}, headers=auth(B)).json()
    listed = client.get(f"/api/ptt/channels/{channel['id']}/clips", headers=auth(A)).json()["clips"]
    assert [c["sender_name"] for c in listed] == ["Sita"] and listed[0]["mine"] is False
    audio = client.get(f"/api/ptt/clips/{sent['clip']['id']}/audio", headers=auth(A))
    assert audio.status_code == 200 and audio.headers["content-type"].startswith("audio/mp4")
    assert client.get(f"/api/ptt/clips/{sent['clip']['id']}/audio", headers=auth(C)).status_code == 403
    after = client.get(f"/api/ptt/channels/{channel['id']}/clips", params={"after": listed[0]["created_at"]},
                       headers=auth(A)).json()["clips"]
    assert after == []


def test_ptt_rejects_bad_clips_and_unknown_codes(api):
    client, auth = api
    channel = client.post("/api/ptt/channels", json={}, headers=auth(A)).json()["channel"]
    url = f"/api/ptt/channels/{channel['id']}/clips"
    assert client.post(url, json={"audio_base64": "aGVsbG8=", "mime_type": "video/mp4"}, headers=auth(A)).status_code == 415
    assert client.post(url, json={"audio_base64": "!!!notbase64", "mime_type": "audio/mp4"},
                       headers=auth(A)).status_code == 400
    assert client.post(url, json={"audio_base64": "aGVsbG8=", "duration_ms": 90000}, headers=auth(A)).status_code == 422
    assert client.post("/api/ptt/join", json={"code": "ZZZZZZ"}, headers=auth(B)).status_code == 404
    assert client.post("/api/ptt/channels", json={}).status_code == 401


def test_last_member_leaving_deletes_group_and_clips(api):
    client, auth = api
    D = "app-9000000044"
    channel = client.post("/api/ptt/channels", json={"name": "x"}, headers=auth(D)).json()["channel"]
    client.post(f"/api/ptt/channels/{channel['id']}/clips",
                json={"audio_base64": base64.b64encode(b"a" * 100).decode()}, headers=auth(D))
    assert client.post(f"/api/ptt/channels/{channel['id']}/leave", headers=auth(D)).json()["left"] is True
    assert client.get("/api/ptt/channels", headers=auth(D)).json()["channels"] == []
    assert client.post("/api/ptt/join", json={"code": channel["code"]}, headers=auth(B)).status_code == 404


def test_account_deletion_removes_devices_and_group_memberships(api):
    client, auth = api
    client.post("/api/devices", json={"name": "s", "identifier": "01:02:03:04:05:06", "service_uuids": ["181d"]},
                headers=auth(C))
    client.post("/api/ptt/channels", json={"name": "g"}, headers=auth(C))
    assert client.delete("/api/me", params={"confirm": "DELETE"}, headers=auth(C)).status_code == 200
    from server import container
    import sqlite3

    with sqlite3.connect(container.settings.database_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM user_devices WHERE app_user_id=?", (C,)).fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM ptt_members WHERE app_user_id=?", (C,)).fetchone()[0] == 0
