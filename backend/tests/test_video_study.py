"""ASKODOX Video Study: hard length cap, grounded facts, cached Q&A without
re-analysis, hallucination guard, languages, market vs video separation,
uploads through the existing attachment path, Shorts."""
from __future__ import annotations

import base64
import json
import struct

import pytest
from fastapi.testclient import TestClient

from app.services import video_study as vs

CAR_STUDY = {
    "content_accessible": True, "category": "vehicle", "subject": "Toyota Innova Crysta",
    "summary": "A seller shows a white 2016 Innova Crysta and walks around it.",
    "spoken_language": "te",
    "facts": [
        {"key": "make", "label": "Make", "value": "Toyota", "basis": "shown", "timestamp": "0:03",
         "evidence": "Toyota badge on the grille"},
        {"key": "model", "label": "Model", "value": "Innova Crysta", "basis": "said", "timestamp": "0:05",
         "evidence": "ఇది ఇన్నోవా క్రిస్టా"},
        {"key": "variant", "label": "Variant", "value": "2.8 ZX Automatic", "basis": "said", "timestamp": "0:12",
         "evidence": "2.8 ZX automatic"},
        {"key": "year", "label": "Year", "value": "2016", "basis": "said", "timestamp": "0:20",
         "evidence": "2016 model"},
        {"key": "asking_price", "label": "Asking price", "value": "₹12.5 lakh", "basis": "said",
         "timestamp": "1:42", "evidence": "పన్నెండున్నర లక్షలు"},
        {"key": "kilometres", "label": "Kilometres", "value": "", "basis": "said", "timestamp": "0:30",
         "evidence": "not said"},  # empty value -> dropped
        {"key": "colour", "label": "Colour", "value": "white", "basis": "shown", "timestamp": "0:02",
         "evidence": ""},  # no evidence -> dropped
    ],
    "transcript": [{"t": "0:05", "text": "ఇది ఇన్నోవా క్రిస్టా"}, {"t": "1:42", "text": "పన్నెండున్నర లక్షలు"}],
    "visible_text": [{"t": "0:03", "text": "TOYOTA"}],
    "missing": ["kilometres", "ownership", "insurance"],
    "suggested_questions": ["What is the asking price?", "What year is it?"],
}


class _Resp:
    def __init__(self, text: str) -> None:
        self.text = text


class FakeGenai:
    """Stands in for the Gemini client: a video part -> the study; a text
    prompt -> whatever answer the test scripted."""

    def __init__(self, study=None, answer=None) -> None:
        self.study = study if study is not None else CAR_STUDY
        self.answer = answer
        self.video_calls = 0
        self.text_calls = 0
        self.models = self

    def generate_content(self, model, contents, config=None):
        if isinstance(contents[0], str):
            self.text_calls += 1
            if self.answer is None:
                raise RuntimeError("no answer scripted")
            return _Resp(json.dumps(self.answer, ensure_ascii=False))
        self.video_calls += 1
        return _Resp(json.dumps(self.study, ensure_ascii=False))


def mp4(seconds: float, version: int = 0) -> bytes:
    """Smallest ISO-BMFF header with an mvhd box of this duration."""
    timescale = 1000
    if version == 1:
        body = bytes([1, 0, 0, 0]) + b"\0" * 16 + struct.pack(">IQ", timescale, int(seconds * timescale))
    else:
        body = bytes([0, 0, 0, 0]) + b"\0" * 8 + struct.pack(">II", timescale, int(seconds * timescale))
    box = struct.pack(">I", 8 + len(body)) + b"mvhd" + body
    return b"\0\0\0\x18ftypmp42\0\0\0\0mp42isom" + struct.pack(">I", 8 + len(box)) + b"moov" + box + b"\0" * 64


@pytest.mark.parametrize("seconds,eligible", [(30, True), (60, True), (120, True), (180, True), (181, False),
                                               (600, False)])
def test_hard_three_minute_cap(seconds, eligible):
    gate = vs.eligibility(seconds, "en")
    assert gate["eligible"] is eligible
    if not eligible:
        assert gate["reason"] == "too_long"
        assert gate["message"] == "ASKODOX Video Study is currently available for videos up to 3 minutes."
    assert vs.eligibility(None)["reason"] == "unknown_duration"


def test_cap_is_configuration(monkeypatch):
    monkeypatch.setenv("ASKODOX_VIDEO_STUDY_MAX_SECONDS", "240")
    assert vs.eligibility(200)["eligible"] and not vs.eligibility(241)["eligible"]
    assert "4 minutes" in vs.too_long_message("en")


def test_durations_and_mp4_header():
    assert [vs.duration_seconds(t) for t in ("0:15", "05:52", "3:00", "1:02:03", "PT2M10S", "95", "", None)] == \
        [15, 352, 180, 3723, 130, 95, None, None]
    assert vs.mp4_duration_seconds(mp4(150)) == 150
    assert vs.mp4_duration_seconds(mp4(181.5, version=1)) == 181.5
    assert vs.mp4_duration_seconds(b"not a video") is None


def test_shorts_are_recognised_without_dropping_normal_videos():
    assert vs.is_short("https://www.youtube.com/shorts/abc123def45")
    assert vs.is_short("https://www.youtube.com/watch?v=x", 45, "Biryani #shorts")
    assert not vs.is_short("https://www.youtube.com/watch?v=x", 45, "Biryani review")  # not confidently a Short
    assert not vs.is_short("https://www.youtube.com/watch?v=x", 400, "#shorts")


def test_study_keeps_only_evidenced_facts_with_basis():
    study = vs.normalize_study(CAR_STUDY, ref="yt_x", source="youtube", duration=150)
    keys = {f["key"]: f for f in study["facts"]}
    assert set(keys) == {"make", "model", "variant", "year", "asking_price"}, "no value / no evidence -> dropped"
    assert keys["make"]["basis"] == vs.BASIS_CONFIRMED and keys["asking_price"]["basis"] == vs.BASIS_CLAIM
    assert keys["asking_price"]["timestamp"] == "1:42"
    unavailable = vs.normalize_study({"content_accessible": False}, ref="yt_y", source="youtube", duration=60)
    assert unavailable["status"] == "unavailable"
    assert unavailable["message"] == "Video content analysis unavailable."
    assert vs.normalize_study({"facts": [], "transcript": []}, ref="yt_z", source="youtube",
                              duration=60)["status"] == "unavailable", "captions/speech unavailable -> honest"


def test_study_is_cached_and_long_videos_never_reach_the_model(tmp_path):
    client = FakeGenai()
    service = vs.VideoStudyService(vs.VideoStudyStore(str(tmp_path / "s.db")), client=client)
    first = service.study_youtube("yt_abc", "https://www.youtube.com/watch?v=abc", 150)
    second = service.study_youtube("yt_abc", "https://www.youtube.com/watch?v=abc", 150)
    assert first["status"] == "ready" and not first["cached"] and second["cached"]
    assert client.video_calls == 1, "the same video is never studied twice"
    blocked = service.study_youtube("yt_long", "https://www.youtube.com/watch?v=long", 181)
    assert blocked["status"] == "not_eligible" and client.video_calls == 1


@pytest.mark.parametrize("language,question,expect", [
    ("en", "What price did he say?", "₹12.5 lakh"),
    ("te", "ధర ఎంత చెప్పారు?", "₹12.5 lakh"),
    ("hi", "कितने में बेच रहे हैं, कीमत?", "₹12.5 lakh"),
    ("te", "what year? ఏ సంవత్సరం", "2016"),
])
def test_grounded_answers_without_a_reasoning_model(tmp_path, language, question, expect):
    service = vs.VideoStudyService(vs.VideoStudyStore(str(tmp_path / "s.db")), client=None)
    study = vs.normalize_study(CAR_STUDY, ref="yt_x", source="youtube", duration=150)
    answer = service.answer(study, question, language)
    assert answer["found"] and expect in answer["answer"]
    assert answer["timestamps"], "the timestamp where it was said"


@pytest.mark.parametrize("language,message", [
    ("en", "This video does not have the information to confirm that."),
    ("te", "ఈ వీడియోలో ఆ వివరాన్ని నిర్ధారించడానికి సమాచారం లేదు."),
    ("hi", "इस वीडियो में इसकी पुष्टि करने के लिए जानकारी नहीं है।"),
])
def test_missing_information_is_never_guessed(tmp_path, language, message):
    service = vs.VideoStudyService(vs.VideoStudyStore(str(tmp_path / "s.db")), client=None)
    study = vs.normalize_study(CAR_STUDY, ref="yt_x", source="youtube", duration=150)
    answer = service.answer(study, "How many kilometres has it run?", language)
    assert not answer["found"] and answer["answer"] == message


def test_hallucination_guard_rejects_an_uncited_model_answer(tmp_path):
    study = vs.normalize_study(CAR_STUDY, ref="yt_x", source="youtube", duration=150)
    invented = FakeGenai(answer={"found": True, "answer": "It has run 45,000 km and is accident-free.",
                                 "fact_keys": ["kilometres"], "timestamps": ["9:99"]})
    service = vs.VideoStudyService(vs.VideoStudyStore(str(tmp_path / "s.db")), client=invented)
    answer = service.answer(study, "Is it accident-free?", "en")
    assert not answer["found"] and "45,000" not in answer["answer"]
    cited = FakeGenai(answer={"found": True, "answer": "The seller asks ₹12.5 lakh (at 1:42).",
                              "fact_keys": ["asking_price"], "timestamps": ["1:42"]})
    answer = vs.VideoStudyService(vs.VideoStudyStore(str(tmp_path / "t.db")), client=cited).answer(
        study, "At what time did he mention the price?", "en")
    assert answer["found"] and answer["timestamps"] == ["1:42"]
    assert answer["facts"][0]["basis"] == vs.BASIS_CLAIM


def test_market_comparison_never_mixes_external_with_video_facts():
    study = vs.normalize_study(CAR_STUDY, ref="yt_x", source="youtube", duration=150)
    rows = [{"title": f"2016 Innova Crysta ZX listing {i}", "price": p, "match_source": "online",
             "destination_url": f"https://cars.example/{i}"} for i, p in enumerate((1_150_000, 1_210_000, 1_300_000))]
    rows.append({"title": "review", "match_source": "video", "destination_url": "https://www.youtube.com/watch?v=r"})
    result = vs.market_comparison(study, rows, "en")
    assert result["video_facts"]["asking_price"]["value"] == 1_250_000
    assert result["video_facts"]["asking_price"]["basis"] == vs.BASIS_CLAIM
    market = result["market"]
    assert market["source"] == "external" and "not from the video" in market["label"]
    assert all(r["match_source"] != "video" for r in market["rows"])
    assert market["prices"] == {"count": 3, "min": 1_150_000, "median": 1_210_000, "max": 1_300_000,
                                "verified": False}
    assert market["negotiation"]["high"] == 1_250_000 and market["negotiation"]["estimate"]
    assert market["query"] == "2016 Toyota Innova Crysta 2.8 ZX Automatic"
    assert "kilometres driven" in market["factors"]
    assert vs.parse_money("Rs 1.2 crore") == 12_000_000 and vs.parse_money("12,50,000") == 1_250_000


def test_suggested_questions_follow_the_category_not_a_fixed_list():
    car = vs.suggested_questions(vs.normalize_study(CAR_STUDY, ref="a", source="youtube", duration=60), "en")
    service = vs.suggested_questions(vs.normalize_study({
        "category": "service", "subject": "AC servicing",
        "facts": [{"key": "quoted_price", "label": "Quoted price", "value": "₹499", "basis": "said",
                   "timestamp": "0:10", "evidence": "only 499 rupees"}],
        "transcript": [{"t": "0:10", "text": "only 499 rupees"}]}, ref="b", source="upload", duration=40), "te")
    assert "What is the asking price?" in car
    assert any("Quoted price" in q for q in service) and not any("year" in q.lower() for q in service)


# -- routes -----------------------------------------------------------------

@pytest.fixture()
def api(tmp_path):
    from app.api.routes.platform import platform
    from server import app, container

    pf = platform(container)
    client = FakeGenai(answer={"found": True, "answer": "The seller asks ₹12.5 lakh.",
                               "fact_keys": ["asking_price"], "timestamps": ["1:42"]})
    pf._video_study = vs.VideoStudyService(vs.VideoStudyStore(container.settings.database_path), client=client)
    for ref, duration in (("yt_shortcar0001", "2:30"), ("yt_longcar00001", "12:04")):
        pf.web_videos.save({"ref": ref, "url": f"https://www.youtube.com/watch?v={ref[3:]}", "platform": "youtube",
                            "title": "Innova Crysta for sale", "snippet": "", "creator": "Car Seller",
                            "thumbnail": None, "duration": duration, "source": "youtube_data", "products": [],
                            "services": [], "category": "", "embeddable": True, "paid_promotion": False})
    for ref in ("yt_shortcar0001", "yt_longcar00001", "yt_explaincar1"):
        _register_video(pf, ref)
    yield TestClient(app), container, client
    pf._video_study = None


def _register_video(pf, ref):
    """A registered seller's video (Command Center record linked to the web ref)."""
    record = pf.resources.create("videos", {
        "title": "Innova Crysta for sale", "platform": "youtube", "url": f"https://www.youtube.com/watch?v={ref[3:]}",
        "relationship": "merchant", "merchant_ref": "app-seller-1", "source_ref": ref}, actor="test")
    pf.resources.action("videos", record["id"], "approve", actor="owner")
    return record


def test_youtube_study_then_cached_questions_never_re_analyse(api):
    http, _, client = api
    status = http.get("/api/videos/yt_shortcar0001/study").json()
    assert status["eligible"] and status["status"] == "none" and client.video_calls == 0, "status is free"
    study = http.post("/api/videos/yt_shortcar0001/study", json={"language": "en"}).json()
    assert study["status"] == "ready" and study["facts"] and study["suggested_questions"]
    for _ in range(3):
        answer = http.post("/api/videos/yt_shortcar0001/ask", json={"question": "price?", "language": "en"}).json()
        assert answer["found"] and answer["timestamps"] == ["1:42"]
    again = http.post("/api/videos/yt_shortcar0001/study", json={"language": "te"}).json()
    assert again["cached"] and client.video_calls == 1, "one study per video, reused"
    long_status = http.get("/api/videos/yt_longcar00001/study").json()
    assert not long_status["eligible"] and long_status["reason"] == "too_long"
    long_run = http.post("/api/videos/yt_longcar00001/study", json={"language": "en"}).json()
    assert long_run["status"] == "not_eligible" and client.video_calls == 1
    assert http.post("/api/videos/yt_longcar00001/ask",
                     json={"question": "price?"}).json()["status"] == "not_studied"
    assert http.get("/api/videos/yt_unknown/study").status_code == 404


def test_external_videos_play_but_get_no_deep_study(api):
    """Part 10: an external YouTube result (no registered seller behind it)
    is a normal result -- no study, no grounded Q&A, no market comparison."""
    from app.api.routes.platform import platform

    http, container, client = api
    platform(container).web_videos.save({
        "ref": "yt_external001", "url": "https://www.youtube.com/watch?v=external001", "platform": "youtube",
        "title": "Car review", "snippet": "", "creator": "Somebody", "thumbnail": None, "duration": "1:00",
        "source": "youtube_data", "products": [], "services": [], "category": "", "embeddable": True,
        "paid_promotion": False})
    status = http.get("/api/videos/yt_external001/study?language=te").json()
    assert status["eligible"] is False and status["reason"] == "external_video" and status["studyable"] is False
    assert "బయటి వీడియో" in status["message"]
    run = http.post("/api/videos/yt_external001/study", json={"language": "en"}).json()
    assert run["status"] == "not_eligible" and client.video_calls == 0, "no model call for external videos"
    ask = http.post("/api/videos/yt_external001/ask", json={"question": "price?", "language": "en"}).json()
    assert ask["status"] == "not_eligible" and ask["found"] is False
    assert http.post("/api/videos/yt_external001/market", json={"language": "en"}).status_code == 409


def test_study_masks_contacts_and_keeps_transcript_private(api):
    study = vs.normalize_study({
        "category": "vehicle", "subject": "Innova call 98765 43210",
        "summary": "Seller says WhatsApp 9876543210 or mail seller@example.com",
        "facts": [{"key": "phone_number", "value": "9876543210", "basis": "said", "timestamp": "0:10",
                   "evidence": "call 9876543210"},
                  {"key": "asking_price", "value": "₹12.5 lakh", "basis": "said", "timestamp": "1:42",
                   "evidence": "12.5 lakh, call +91 98765 43210"}],
        "transcript": [{"t": "0:10", "text": "my number is 98765 43210"}]},
        ref="up_x", source="upload", duration=60)
    text = str(study)
    assert "9876543210" not in text and "98765 43210" not in text and "seller@example.com" not in text
    assert [f["key"] for f in study["facts"]] == ["asking_price"], "contact facts are dropped"
    assert "[contact hidden]" in study["facts"][0]["evidence"]


def test_public_study_follows_the_requested_language(api):
    http, _, _ = api
    http.post("/api/videos/yt_shortcar0001/study", json={"language": "en"})
    te = http.get("/api/videos/yt_shortcar0001/study?language=te").json()["study"]
    assert te["suggested_questions"] and all(any("\u0c00" <= ch <= "\u0c7f" for ch in q)
                                             for q in te["suggested_questions"])
    assert "transcript" not in te, "the raw transcript never goes to the customer app"


def test_market_route_is_external_and_separate(api, monkeypatch):
    http, container, _ = api
    from tests.test_real_phone_regressions import _Brave

    container.brave_web_search_provider = _Brave([
        {"title": "2016 Toyota Innova Crysta 2.8 ZX AT for sale", "url": "https://cars.example/1",
         "snippet": "Innova Crysta 2016 ZX automatic ₹11.9 lakh"}])
    http.post("/api/videos/yt_shortcar0001/study", json={"language": "en"})
    market = http.post("/api/videos/yt_shortcar0001/market", json={"language": "en"}).json()
    assert market["market"]["source"] == "external"
    assert market["video_facts"]["asking_price"]["text"] == "₹12.5 lakh"
    assert all(r.get("match_source") != "video" for r in market["market"]["rows"])


class _UploadBrain:
    """The existing analyze_video call, now returning the study fields too."""

    def __init__(self) -> None:
        self.calls = 0
        self.client = None

    def analyze_video(self, video_bytes, mime_type, caption=None):
        self.calls += 1
        return {**CAR_STUDY, "visual_summary": CAR_STUDY["summary"],
                "spoken_transcript": "ఇది ఇన్నోవా క్రిస్టా ... పన్నెండున్నర లక్షలు"}


@pytest.mark.parametrize("seconds,studied", [(30, True), (120, True), (180, True), (240, False)])
def test_uploaded_video_study_respects_the_cap_before_any_model_call(api, seconds, studied):
    http, container, _ = api
    brain = _UploadBrain()
    original = getattr(container, "universal_image_service", None)
    container.universal_image_service = brain
    try:
        body = {"file_base64": base64.b64encode(mp4(seconds) + bytes([seconds % 256])).decode(),
                "filename": "car.mp4", "mime_type": "video/mp4", "user_text": "", "language": "en"}
        data = http.post("/api/attachments/analyze", json=body).json()
    finally:
        container.universal_image_service = original
    assert data["status"] == "success" and data["facts"], "the attachment is kept either way"
    if studied:
        assert brain.calls == 1, "ONE model call: analysis + study together"
        ref = data["video_study"]["ref"]
        assert data["video_study"]["status"] == "ready" and ref.startswith("up_")
        answer = http.post(f"/api/videos/{ref}/ask", json={"question": "What year?", "language": "en"}).json()
        assert answer["found"]
    else:
        assert brain.calls == 0, "longer than the cap: never sent to the model"
        assert data["video_study"]["reason"] == "too_long"
        assert "up to 3 minutes" in data["facts"]


def test_chat_explain_uses_the_study_once_it_exists(api):
    from app.api.routes.platform import platform

    http, container, _ = api
    platform(container).web_videos.save({
        "ref": "yt_explaincar1", "url": "https://www.youtube.com/watch?v=explaincar1", "platform": "youtube",
        "title": "Innova for sale", "snippet": "", "creator": "Seller", "thumbnail": None, "duration": "1:10",
        "source": "youtube_data", "products": [], "services": [], "category": "", "embeddable": True,
        "paid_promotion": False})
    before = http.post("/api/videos/yt_explaincar1/explain", json={"question": "", "language": "en"}).json()
    assert before["analyzed"] is False, "not studied: honest about only knowing the title"
    http.post("/api/videos/yt_explaincar1/study", json={"language": "en"})
    after = http.post("/api/videos/yt_explaincar1/explain", json={"question": "", "language": "en"}).json()
    assert after["analyzed"] is True
    assert any("₹12.5 lakh (seller claim) [1:42]" in line for line in after["from_source"])


def test_market_subject_from_real_production_keys():
    """Production study of a real Short used make_model -> the query was '2019 GX'."""
    study = vs.normalize_study({
        "category": "vehicle", "subject": "Innova Crysta 2019 GX",
        "facts": [{"key": "make_model", "label": "Make & Model", "value": "Innova Crysta", "basis": "said",
                   "timestamp": "0:00", "evidence": "Innova Crysta 2019"},
                  {"key": "year", "label": "Year", "value": "2019", "basis": "said", "timestamp": "0:00",
                   "evidence": "2019 model"},
                  {"key": "variant", "label": "Variant", "value": "GX", "basis": "said", "timestamp": "0:02",
                   "evidence": "GX"}]}, ref="yt_T5jS6dKefCw", source="youtube", duration=5)
    assert vs.market_subject(study) == "2019 Innova Crysta GX"
    only_numbers = vs.normalize_study({
        "category": "vehicle", "subject": "Toyota Fortuner",
        "facts": [{"key": "year", "label": "Year", "value": "2018", "basis": "said", "timestamp": "0:01",
                   "evidence": "2018"}]}, ref="yt_n", source="youtube", duration=30)
    assert vs.market_subject(only_numbers) == "2018 Toyota Fortuner"


def test_suggested_questions_follow_the_conversation_language():
    study = vs.normalize_study({**CAR_STUDY, "suggested_questions": ["What is the asking price?", "ధర ఎంత?"]},
                               ref="a", source="youtube", duration=60)
    te = vs.suggested_questions(study, "te")
    assert "ధర ఎంత?" in te and "What is the asking price?" not in te
    en = vs.suggested_questions(study, "en")
    assert "What is the asking price?" in en and "ధర ఎంత?" not in en
