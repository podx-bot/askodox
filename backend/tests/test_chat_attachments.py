"""Section 14: the ACTUAL attachment bytes reach the right processor and the
chat gets factual text (never "[Attachment: name]" / a placeholder)."""
import base64
import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.api.routes.attachments import resolve_kind
from app.services import rate_limit
from app.services.attachment_facts import attachment_facts

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")


class _Brain:
    """Records what it received; answers like the real image brain (no 'summary' key)."""

    client = object()

    def __init__(self, video=True):
        self.calls = []
        self.video = video

    def analyze(self, image_bytes, mime_type, caption=None):
        self.calls.append(("image", image_bytes, mime_type, caption))
        return {"side": "NEED", "domain": "PRODUCT", "subject": "pressure cooker", "brand": "Prestige",
                "model": None, "visible_text": "Prestige 5L", "constraints": ["steel"], "confidence": 0.9}

    def analyze_video(self, video_bytes, mime_type, caption=None):
        self.calls.append(("video", video_bytes, mime_type, caption))
        if not self.video:
            return None
        return {"visual_summary": "a scooter with a flat tyre", "spoken_transcript": "puncture ayindi"}


@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    brain = _Brain()
    monkeypatch.setattr(container, "universal_image_service", brain, raising=False)
    return TestClient(app), container, brain


def body(data: bytes, filename: str, mime: str, text: str = "", language: str = "te"):
    return {"file_base64": base64.b64encode(data).decode(), "filename": filename, "mime_type": mime,
            "user_text": text, "language": language, "conversation_id": "c1"}


def test_photo_bytes_reach_the_image_brain_and_come_back_as_real_facts(api):
    client, container, brain = api
    response = client.post("/api/attachments/analyze",
                           json=body(PNG, "IMG_2031.jpg", "image/jpeg", "ఇది ఏమిటి? దగ్గరలో ఎక్కడ దొరుకుతుంది?"))
    assert response.status_code == 200, response.text
    data = response.json()
    kind, received, mime, caption = brain.calls[0]
    assert kind == "image" and received == PNG and mime == "image/jpeg", "the actual bytes, not a filename"
    assert caption == "ఇది ఏమిటి? దగ్గరలో ఎక్కడ దొరుకుతుంది?", "caption + attachment processed together"
    assert "pressure cooker" in data["facts"] and "Prestige" in data["facts"] and "Prestige 5L" in data["facts"]
    assert "IMG_2031" not in data["facts"] and "[Attachment" not in data["facts"]
    assert data["attachment"]["id"].startswith("att_") and data["attachment"]["size"] == len(PNG)
    with sqlite3.connect(container.settings.database_path) as conn:
        row = conn.execute("SELECT kind, mime_type, language, facts FROM chat_attachments WHERE id = ?",
                           (data["attachment"]["id"],)).fetchone()
    assert row[0] == "image" and row[2] == "te" and "pressure cooker" in row[3]


def test_octet_stream_from_the_files_picker_is_routed_by_extension(api):
    client, _, brain = api
    assert client.post("/api/attachments/analyze", json=body(PNG, "photo.png", "application/octet-stream")
                       ).status_code == 200
    assert brain.calls[-1][2] == "image/png"
    assert resolve_kind("clip.mov", "") == ("video", "video/quicktime")
    assert resolve_kind("quote.pdf", "application/octet-stream") == ("document", "application/pdf")


def test_video_is_processed_or_honestly_refused(api, monkeypatch):
    client, container, brain = api
    ok = client.post("/api/attachments/analyze", json=body(b"\x00\x00\x00\x18ftypmp42", "clip.mp4", "video/mp4"))
    assert ok.status_code == 200 and "flat tyre" in ok.json()["facts"] and "puncture" in ok.json()["facts"]
    no_video = _Brain(video=False)
    no_video.client = None
    monkeypatch.setattr(container, "universal_image_service", no_video, raising=False)
    refused = client.post("/api/attachments/analyze", json=body(b"\x00\x00\x00\x18ftypmp42", "clip.mp4", "video/mp4"))
    assert refused.status_code == 503 and "not available" in refused.json()["detail"], "never a pretend analysis"


def test_documents_are_read_and_unsupported_files_refused_clearly(api):
    client, _, _ = api
    text = "Quotation\nSplit AC 1.5 ton installation Rs 1500\nVijayawada".encode()
    doc = client.post("/api/attachments/analyze", json=body(text, "quote.txt", "text/plain"))
    assert doc.status_code == 200, doc.text
    assert "Split AC 1.5 ton installation" in doc.json()["facts"]
    zipped = client.post("/api/attachments/analyze", json=body(b"PK\x03\x04", "archive.zip", "application/zip"))
    assert zipped.status_code == 415 and "cannot read this file type" in zipped.json()["detail"]
    assert client.post("/api/attachments/analyze", json=body(b"", "x.txt", "text/plain")).status_code in (400, 422)


def test_facts_cover_every_analysis_shape():
    assert attachment_facts("image", {"subject": "mixer grinder", "brand": None, "visible_text": "null"}) == \
        "Shows: mixer grinder"
    assert attachment_facts("image", {}) == ""
    assert "Summary: invoice" in attachment_facts("document", {"summary": "invoice", "pages": [{"text": "Total 500"}]})


def test_reply_language_is_authoritative_even_for_short_replies():
    from app.services.universal_ai_assistant_service import _reply_language_rule

    rule = _reply_language_rule("te")
    assert "Reply language: Telugu (te)" in rule and "yes / ok / go / ?" in rule
    assert _reply_language_rule("hi-IN").startswith("Reply language: Hindi (hi)")
    assert _reply_language_rule("") == "Locale hint: auto\n"


def _blank_pdf() -> bytes:
    """A real one-page PDF with no text layer (like a scanned page)."""
    from pypdf import PdfWriter
    import io

    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def test_scanned_pdf_without_text_is_read_by_the_multimodal_brain(api):
    client, container, brain = api
    seen = []

    def analyze_pdf(pdf_bytes, caption=None):
        seen.append(pdf_bytes)
        return {"document_type": "price list", "visible_text": "Rice 5 kg 300", "summary": "grocery price list"}

    brain.analyze_pdf = analyze_pdf
    pdf = _blank_pdf()
    response = client.post("/api/attachments/analyze", json=body(pdf, "scan.pdf", "application/pdf"))
    assert response.status_code == 200, response.text
    assert seen == [pdf], "the actual PDF bytes reach the brain"
    facts = response.json()["facts"]
    assert "price list" in facts and "Rice 5 kg 300" in facts and "[Page" not in facts


def test_scanned_pdf_with_no_brain_answer_is_422_not_page_markers(api):
    client, container, brain = api
    brain.analyze_pdf = lambda pdf_bytes, caption=None: None
    response = client.post("/api/attachments/analyze", json=body(_blank_pdf(), "scan.pdf", "application/pdf"))
    assert response.status_code == 422
    assert attachment_facts("document", {"text": "[Page 1]\n\n[Page 2]\n"}) == ""


class _Files:
    def __init__(self):
        self.uploaded, self.deleted, self.polls = [], [], 0

    def upload(self, file, config):
        self.uploaded.append((file.read(), config["mime_type"]))
        return type("F", (), {"name": "files/v1", "state": type("S", (), {"name": "PROCESSING"})()})()

    def get(self, name):
        self.polls += 1
        return type("F", (), {"name": name, "state": type("S", (), {"name": "ACTIVE"})()})()

    def delete(self, name):
        self.deleted.append(name)


class _Models:
    def __init__(self):
        self.contents = []

    def generate_content(self, model, contents, config):
        self.contents.append(contents[0])
        return type("R", (), {"text": '{"visual_summary": "a leaking tap", "spoken_transcript": "fix this"}'})()


def test_large_video_goes_through_the_files_api_and_small_video_inline(monkeypatch):
    from app.services import universal_image_service as module

    monkeypatch.setattr("time.sleep", lambda s: None)
    client = type("C", (), {})()
    client.files, client.models = _Files(), _Models()
    service = module.UniversalImageService(api_key="", model="m", pending_repository=None,
                                           live_capture_service=None, client=client)
    monkeypatch.setattr(service, "INLINE_MEDIA_LIMIT", 1024)
    big = b"\x00\x00\x00\x18ftypmp42" + b"v" * 4096
    result = service.analyze_video(big, "video/mp4", caption="what is this")
    assert result["visual_summary"] == "a leaking tap" and result["spoken_transcript"] == "fix this"
    assert client.files.uploaded == [(big, "video/mp4")] and client.files.polls == 1
    assert client.files.deleted == ["files/v1"], "the uploaded clip is removed after reading"
    small = b"\x00\x00\x00\x18ftypmp42" + b"v" * 10
    service.analyze_video(small, "video/mp4")
    assert len(client.files.uploaded) == 1, "small clips stay inline"


def test_understanding_is_reported_honestly(api, monkeypatch):
    """APK 1273: uncertain vision must not be presented as fact; video is the
    whole clip (frames + audio), never a thumbnail."""
    client, container, brain = api
    sure = client.post("/api/attachments/analyze", json=body(PNG, "a.jpg", "image/jpeg")).json()
    assert sure["understanding"] == {"method": "vision", "confidence": 0.9, "status": "ok"}
    monkeypatch.setattr(brain, "analyze", lambda image_bytes, mime_type, caption=None: {
        "subject": "maybe a cooker", "confidence": 0.3})
    unsure = client.post("/api/attachments/analyze", json=body(PNG, "a.jpg", "image/jpeg")).json()
    assert unsure["understanding"]["status"] == "low_confidence"
    video = client.post("/api/attachments/analyze", json=body(b"\x00\x00\x00\x18ftypmp42", "c.mp4", "video/mp4"))
    assert video.json()["understanding"] == {"method": "video_frames_and_audio", "status": "ok", "has_speech": True}
    assert brain.calls[-1][0] == "video" and brain.calls[-1][1].startswith(b"\x00\x00\x00\x18ftyp"), \
        "the whole clip reaches the video brain"
    # the brain is configured but could not understand the clip: 422, not a pretend answer
    monkeypatch.setattr(brain, "video", False)
    failed = client.post("/api/attachments/analyze", json=body(b"\x00\x00\x00\x18ftypmp42", "c.mp4", "video/mp4"))
    assert failed.status_code == 422
    doc = client.post("/api/attachments/analyze", json=body(b"Invoice total Rs 500", "i.txt", "text/plain")).json()
    assert doc["understanding"]["method"] == "text_layer"
