"""ASKODOX-native video: upload -> review -> publish -> feed; owner pause /
remove; reports pause for review; native DM answered only from the
business's approved FAQ, otherwise handed to the owner."""
import dataclasses
import uuid

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-vid-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64 + uuid.uuid4().bytes


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                                                  database_path=str(tmp_path / "native_video.db")))
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "v.db")),
                        raising=False)
    return TestClient(app), container


def _user(container):
    uid = "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _upload(client, headers, *, data=MP4, submit=True, title="Rice cooker demo"):
    return client.post("/api/videos/upload", headers=headers, data={
        "title": title, "caption": "How our 1.8 L cooker works. Call 9876543210", "category": "Kitchen",
        "products": "rice cooker", "as_business": "true", "submit": "true" if submit else "false"},
        files={"file": ("v.mp4", data, "video/mp4")})


def test_upload_review_publish_feed_and_media_access(env):
    client, container = env
    seller_id, seller = _user(container)
    _, viewer = _user(container)
    assert client.post("/api/videos/upload", data={"title": "x"},
                       files={"file": ("v.mp4", MP4, "video/mp4")}).status_code == 401
    bad = _upload(client, seller, data=b"not a video at all" * 10)
    assert bad.status_code == 415
    up = _upload(client, seller)
    assert up.status_code == 200, up.text
    video = up.json()
    assert video["status"] == "PENDING_REVIEW" and video["label"] == "From the business"
    assert "9876543210" not in video["caption"], "contact details in captions are masked"
    name = video["url"].rsplit("/", 1)[1]
    assert client.get(f"/media/videos/{name}").status_code == 404, "not public before review"
    assert client.get(f"/media/videos/{name}", headers=seller).status_code == 200, "the owner can preview"
    assert video["id"] not in [v["id"] for v in client.get("/api/videos/feed").json()["items"]]

    assert client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER,
                       json={}).status_code == 200
    feed = client.get("/api/videos/feed?category=kitchen").json()["items"]
    assert [v["id"] for v in feed][:1] == [video["id"]]
    media = client.get(f"/media/videos/{name}", headers={"Range": "bytes=0-9"})
    assert media.status_code == 206 and media.content == MP4[:10]

    # owner pause -> gone from the feed; resume goes back to review
    assert client.post(f"/api/videos/mine/{video['id']}/pause", headers=viewer).status_code == 404
    assert client.post(f"/api/videos/mine/{video['id']}/pause", headers=seller).json()["status"] == "PAUSED"
    assert video["id"] not in [v["id"] for v in client.get("/api/videos/feed").json()["items"]]
    assert client.post(f"/api/videos/mine/{video['id']}/resume", headers=seller).json()["status"] == \
        "PENDING_REVIEW"
    assert client.post(f"/api/videos/mine/{video['id']}/remove", headers=seller).status_code == 200
    assert client.post(f"/api/videos/{video['id']}/report", headers=viewer,
                       json={"reason": "spam"}).status_code == 404


def test_drafts_submit_and_reports_pause_for_review(env):
    client, container = env
    _, seller = _user(container)
    draft = _upload(client, seller, submit=False, data=MP4 + b"draft").json()
    assert draft["status"] == "DRAFT"
    assert client.post(f"/api/videos/mine/{draft['id']}/submit", headers=seller).json()["status"] == "PENDING_REVIEW"
    client.post(f"/admin/cc/platform/r/videos/{draft['id']}/actions/approve", headers=OWNER, json={})
    for i in range(3):
        _, reporter = _user(container)
        r = client.post(f"/api/videos/{draft['id']}/report", headers=reporter, json={"reason": "misleading"}).json()
    assert r["reports"] == 3 and r["paused_for_review"] is True
    reports = client.get("/admin/cc/videos/reports", headers=OWNER).json()["items"]
    assert any(x["video_id"] == draft["id"] and x["reports"] == 3 for x in reports)


def test_native_dm_answers_only_from_the_approved_faq_else_hands_off(env):
    client, container = env
    seller_id, seller = _user(container)
    _, buyer = _user(container)
    video = _upload(client, seller, data=MP4 + b"dm").json()
    client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER, json={})
    rule = client.post("/admin/cc/platform/r/auto_response_rules", headers=OWNER, json={"data": {
        "name": "Cooker FAQ", "business_ref": seller_id, "trigger_type": "video", "channels": ["askodox_chat"],
        "faq": {"delivery": "We deliver in Vijayawada within 2 days.", "warranty": "1 year warranty."}}})
    assert rule.status_code == 200, rule.text
    client.post(f"/admin/cc/platform/r/auto_response_rules/{rule.json()['id']}/actions/enable", headers=OWNER,
                json={})
    answered = client.post(f"/api/videos/{video['id']}/message", headers=buyer,
                           json={"text": "Do you deliver to Benz Circle?"}).json()
    assert answered["status"] == "AUTO_ANSWERED" and "2 days" in answered["reply"]
    unknown = client.post(f"/api/videos/{video['id']}/message", headers=buyer,
                          json={"text": "What colours are there?"}).json()
    assert unknown["status"] == "WAITING_FOR_OWNER" and unknown["reply"] is None, "never a guessed answer"
    inbox = client.get("/api/videos/mine/messages", headers=seller).json()["inbox"]
    assert {m["status"] for m in inbox} == {"AUTO_ANSWERED", "WAITING_FOR_OWNER"}
    assert "sender" not in inbox[0]
    waiting = next(m for m in inbox if m["status"] == "WAITING_FOR_OWNER")
    assert client.post(f"/api/videos/messages/{waiting['id']}/reply", headers=buyer,
                       json={"text": "x"}).status_code == 404
    replied = client.post(f"/api/videos/messages/{waiting['id']}/reply", headers=seller,
                          json={"text": "Red and black. Call 9876543210"}).json()
    assert replied["status"] == "ANSWERED" and "9876543210" not in replied["reply"]
    sent = client.get("/api/videos/mine/messages", headers=buyer).json()["sent"]
    assert any(m["reply"] and "Red and black" in m["reply"] for m in sent)
    assert client.post(f"/api/videos/{video['id']}/message", headers=seller,
                       json={"text": "hi"}).status_code == 422


def test_app_style_upload_sends_details_as_query_parameters(env):
    client, container = env
    _, seller = _user(container)
    up = client.post("/api/videos/upload?title=Saree%20collection&category=fashion&submit=false&as_business=1",
                     headers=seller, files={"file": ("v.mp4", MP4 + b"q", "video/mp4")})
    assert up.status_code == 200 and up.json()["status"] == "DRAFT" and up.json()["url"].startswith("https://")
    assert up.json()["label"] == "From the business"
    assert client.post("/api/videos/upload", headers=seller,
                       files={"file": ("v.mp4", MP4 + b"t", "video/mp4")}).status_code == 422
    mine = client.get("/api/merchant/videos", headers=seller).json()["items"]
    assert any(v["data"]["title"] == "Saree collection" for v in mine)


def _mp4(seconds=30):
    import struct

    mvhd = b"mvhd" + bytes([0, 0, 0, 0]) + b"\x00" * 8 + struct.pack(">II", 1000, seconds * 1000) + b"\x00" * 80
    moov = struct.pack(">I", len(mvhd) + 8 + 4) + b"moov" + struct.pack(">I", len(mvhd) + 4) + mvhd
    return b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 12 + moov + uuid.uuid4().bytes


def test_native_video_deep_study_uses_only_the_analysed_file(env, monkeypatch):
    client, container = env
    _, seller = _user(container)
    _, viewer = _user(container)
    calls = []

    class _Vision:
        client = object()

        def analyze_video(self, *, video_bytes, mime_type, caption):
            calls.append((len(video_bytes), caption))
            return {"summary": "A 1.8 L rice cooker demo", "subject": "rice cooker", "category": "product",
                    "facts": [{"key": "capacity", "label": "Capacity", "value": "1.8 L", "basis": "shown",
                               "timestamp": "0:12", "evidence": "label on the box at 0:12"},
                              {"key": "price", "label": "Price", "value": "Rs 2,499", "basis": "said",
                               "evidence": ""}],  # no evidence -> dropped
                    "missing": ["warranty"]}

    monkeypatch.setattr(container, "universal_image_service", _Vision(), raising=False)
    video = _upload(client, seller, data=_mp4(), title="Best rice cooker, 5 year warranty").json()
    assert client.post(f"/api/videos/native/{video['id']}/study", headers=viewer, json={}).status_code == 404, \
        "an unpublished video is studied only by its owner"
    own = client.post(f"/api/videos/native/{video['id']}/study", headers=seller, json={}).json()
    assert own["status"] == "ready" and own["facts_count"] == 1, "a fact without evidence is never kept"
    assert len(calls) == 1 and calls[0][1] is None, "title / caption are never sent as evidence"
    client.post(f"/admin/cc/platform/r/videos/{video['id']}/actions/approve", headers=OWNER, json={})
    again = client.post(f"/api/videos/native/{video['id']}/study", headers=viewer, json={}).json()
    assert again["cached"] is True and len(calls) == 1, "one model call per video"
    ans = client.post(f"/api/videos/{own['ref']}/ask", json={"question": "what is the capacity?"}).json()
    assert ans["found"] is True and "1.8 L" in ans["answer"]
    warranty = client.post(f"/api/videos/{own['ref']}/ask", json={"question": "what warranty is missing?"}).json()
    assert "5 year" not in warranty["answer"], "the title's claim is never presented as a video fact"
