"""Viewer ask flow after the stored study (owner decision 2026-11-27): answered -> product -> ask the
uploader in-app. The uploader is pushed once per waiting question (generic wording, never the question
or a phone number); the viewer is pushed once when the uploader replies."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import video_ask_flow as flow
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-askflow-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64 + uuid.uuid4().bytes


class _RecordingPush:
    def __init__(self, sent):
        self.sent = sent

    def notify_async(self, user_id, **kwargs):
        self.sent.append({"user": user_id, **kwargs})
        return 1


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                                                  database_path=str(tmp_path / "askflow.db")))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "v.db")),
                        raising=False)
    sent = []
    # The container's push service is replaced for this test only (another test leaves a fake behind).
    monkeypatch.setattr(container, "push_service", _RecordingPush(sent), raising=False)
    return TestClient(app), container, sent


def _user(container):
    uid = "app-phone-92" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _upload(client, headers, data=MP4):
    return client.post("/api/videos/upload", headers=headers, data={
        "title": "Rice cooker demo", "caption": "How our 1.8 L cooker works.", "category": "Kitchen",
        "products": "rice cooker", "as_business": "true", "submit": "true"},
        files={"file": ("v.mp4", data, "video/mp4")}).json()


# ---- pure rules -------------------------------------------------------------------------------------------

@pytest.mark.parametrize("found,has_product,reachable,expected", [
    (True, False, False, "answered"),
    (True, True, True, "answered"),
    (False, True, True, "product"),
    (False, True, False, "product"),
    (False, False, True, "ask_uploader"),
    (False, False, False, "none"),
])
def test_next_step_order(found, has_product, reachable, expected):
    assert flow.next_step(found, has_product, reachable) == expected


def test_uploader_is_reachable_only_for_a_live_video_that_someone_else_watches():
    live = {"owner_ref": "app-phone-9100000001", "status": "ACTIVE"}
    assert flow.uploader_reachable(live, "app-phone-9100000002")
    assert not flow.uploader_reachable(live, "app-phone-9100000001"), "the uploader never asks themself"
    assert not flow.uploader_reachable({**live, "status": "PAUSED"}, "app-phone-9100000002")
    assert not flow.uploader_reachable({"owner_ref": "", "status": "ACTIVE"}, "app-phone-9100000002")
    assert not flow.uploader_reachable(None, "app-phone-9100000002")


def test_offer_uploader_only_when_the_study_did_not_answer():
    assert flow.offer_uploader(False, True)
    assert not flow.offer_uploader(True, True)
    assert not flow.offer_uploader(False, False)


@pytest.mark.parametrize("language", ["en", "te", "hi", ""])
def test_push_wording_never_carries_a_question_or_contact(language):
    for text in (flow.uploader_push_text(language), flow.sender_push_text(language)):
        assert set(text) == {"title", "body"} and text["body"]
        assert not any(ch.isdigit() for ch in text["body"]), "no numbers (a phone or an amount) in a push"
        assert "@" not in text["body"] and "http" not in text["body"]


# ---- routes -----------------------------------------------------------------------------------------------

def test_a_waiting_question_pushes_the_uploader_once_and_the_reply_pushes_the_viewer(env):
    client, container, sent = env
    seller_id, seller = _user(container)
    buyer_id, buyer = _user(container)
    video = _upload(client, seller)
    client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER, json={})
    question = "What colours are there, call 9876543210?"
    waiting = client.post(f"/api/videos/{video['id']}/message", headers=buyer, json={"text": question}).json()
    assert waiting["status"] == "WAITING_FOR_OWNER"
    pushes = [p for p in sent if p["user"] == seller_id]
    assert len(pushes) == 1, sent
    assert pushes[0]["event_key"] == f"video_msg:{waiting['id']}"
    assert "9876543210" not in str(pushes[0]) and "colours" not in str(pushes[0]), "push never carries the question"
    assert pushes[0]["route"] == "/videos/native"
    client.post(f"/api/videos/messages/{waiting['id']}/reply", headers=seller,
                json={"text": "Red and black. Call 9876543210"})
    to_viewer = [p for p in sent if p["user"] == buyer_id]
    assert len(to_viewer) == 1 and to_viewer[0]["event_key"] == f"video_reply:{waiting['id']}"
    assert "Red" not in str(to_viewer[0]), "the reply text is not pushed"


def test_an_auto_answered_question_does_not_push_the_uploader(env):
    client, container, sent = env
    seller_id, seller = _user(container)
    _, buyer = _user(container)
    video = _upload(client, seller, data=MP4 + b"auto")
    client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER, json={})
    rule = client.post("/admin/cc/platform/r/auto_response_rules", headers=OWNER, json={"data": {
        "name": "Cooker FAQ", "business_ref": seller_id, "trigger_type": "video", "channels": ["askodox_chat"],
        "faq": {"warranty": "1 year warranty."}}})
    client.post(f"/admin/cc/platform/r/auto_response_rules/{rule.json()['id']}/actions/enable", headers=OWNER,
                json={})
    answered = client.post(f"/api/videos/{video['id']}/message", headers=buyer,
                           json={"text": "Is there a warranty?"}).json()
    assert answered["status"] == "AUTO_ANSWERED"
    assert not [p for p in sent if p["user"] == seller_id], "the uploader is pushed only for a waiting question"


def test_ask_route_says_what_comes_next_for_a_viewer_and_not_for_the_uploader(env):
    client, container, _ = env
    seller_id, seller = _user(container)
    _, viewer = _user(container)
    video = _upload(client, seller, data=MP4 + b"ask")
    client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER, json={})
    ask = {"question": "What is the warranty period?", "language": "en"}
    as_viewer = client.post(f"/api/videos/native/{video['id']}/ask", headers=viewer, json=ask)
    assert as_viewer.status_code == 200, as_viewer.text
    body = as_viewer.json()
    assert body["found"] is False
    assert body["next_step"] == "ask_uploader" and body["ask_uploader"] is True
    as_owner = client.post(f"/api/videos/native/{video['id']}/ask", headers=seller, json=ask).json()
    assert as_owner["next_step"] == "none" and as_owner["ask_uploader"] is False
