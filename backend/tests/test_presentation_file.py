"""PPT for 'make a presentation' asks (owner phone 2026-11-28)."""
import json
import zipfile
import io

from app.services import answer_card, presentation_file

SLIDES = {"title": "Global warming", "slides": [
    {"title": "Intro", "points": ["What it is", "Why it matters"], "notes": "Welcome."},
    {"title": "Causes", "points": ["CO2", "Methane", "Deforestation"], "notes": "Say why."},
    {"title": "Actions", "points": ["Save power"], "notes": ""},
]}


def test_wanted():
    assert presentation_file.wanted("make a ppt on global warming")
    assert presentation_file.wanted("presentation alaga vundhi")
    assert not presentation_file.wanted("what is the weather")


def test_build_and_download(tmp_path):
    title, slides = presentation_file.clean_slides(SLIDES)
    data = presentation_file.build_pptx(title, slides)
    assert zipfile.ZipFile(io.BytesIO(data)).testzip() is None
    db = str(tmp_path / "x.db")
    action = presentation_file.make_download(lambda p: json.dumps(SLIDES), db, "http://example.com", "make a ppt", "outline")
    assert action["kind"] == "open_url" and action["value"].startswith("https://example.com/api/in-app/files/ppt/")
    token = action["value"].rsplit("/", 1)[1]
    assert presentation_file.read(db, token)[:2] == b"PK"
    assert presentation_file.read(db, "../../etc/passwd") is None


def test_no_file_without_model_slides(tmp_path):
    assert presentation_file.make_download(None, str(tmp_path / "x.db"), "https://a", "ppt", "x") is None
    assert presentation_file.make_download(lambda p: "nope", str(tmp_path / "x.db"), "https://a", "ppt", "x") is None


def test_presentation_ask_is_not_a_written_letter():
    long = "Slide 1 - Intro. " * 40
    assert not answer_card.is_written_document(long, "write a presentation on climate")
