"""Story reels (owner 2026-11-04): a script from the item's own facts + real
review snippets, voiced per scene, translated -- never a bare slideshow."""
import io
import json
import struct
import subprocess
import wave

import pytest
from PIL import Image

from app.services import reel_story as rs
from app.services import video_watermark as wm


def _scenes(n, word="నమస్తే"):
    return json.dumps({"scenes": [{"say": f"{word} {i}.", "caption": f"c{i}"} for i in range(n)]})


def test_script_uses_only_given_facts_and_real_reviews():
    seen = []
    item = {"title": "Steel bottle", "price": 499, "currency": "INR", "brand": "Acme"}
    reviews = [{"title": "t", "snippet": "Keeps water cold.", "host": "reviews.example", "url": "https://reviews.example/a"}]
    got = rs.write_script(lambda p: seen.append(p) or _scenes(4), item, reviews=reviews)
    assert got["ok"] and len(got["scenes"]) == 4 and got["sources"] == ["https://reviews.example/a"]
    assert "Keeps water cold." in seen[0] and "reviews.example" in seen[0] and "₹499" in seen[0]
    none = []
    rs.write_script(lambda p: none.append(p) or _scenes(4), item)
    assert "NO REVIEWS FOUND" in none[0]


def test_a_bad_or_short_script_fails_honestly():
    assert rs.write_script(lambda p: "not json", {"title": "x"})["ok"] is False
    assert rs.write_script(lambda p: _scenes(2), {"title": "x"})["ok"] is False


def test_review_search_keeps_title_snippet_host():
    rows = rs.gather_reviews(lambda q, limit=8: [{"title": "R", "url": "https://www.site.example/r",
                                                  "description": "Good grip."}], "Steel bottle")
    assert rows and rows[0]["host"] == "site.example" and rows[0]["snippet"] == "Good grip."
    assert rs.gather_reviews(None, "x") == []


def test_translation_keeps_the_scene_count():
    base = {"ok": True, "scenes": json.loads(_scenes(3))["scenes"], "language": "te", "sources": []}
    assert rs.translate_script(lambda p: _scenes(3, "Hi"), base, "en")["scenes"][0]["say"] == "Hi 0."
    assert rs.translate_script(lambda p: _scenes(2, "Hi"), base, "en")["ok"] is False


def test_custom_narration_is_one_scene_per_sentence():
    got = rs.custom_script("మంచి bottle. చల్లగా ఉంచుతుంది! ASKODOX లో చూడండి.", "te")
    assert got["ok"] and len(got["scenes"]) == 3 and got["custom"]


def _wav(seconds=1.0):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", 0) for _ in range(int(22050 * seconds))))
    return buf.getvalue()


def test_real_story_render_is_vertical_with_voice(tmp_path):
    exe = wm.ffmpeg_exe()
    if not exe:
        pytest.skip("no ffmpeg")
    photos = []
    for i, c in enumerate([(30, 120, 200), (200, 120, 30)]):
        p = tmp_path / f"{i}.jpg"
        Image.new("RGB", (600, 800), c).save(p, "JPEG")
        photos.append(str(p))
    script = {"ok": True, "scenes": json.loads(_scenes(3))["scenes"]}
    out = str(tmp_path / "story.mp4")
    got = rs.render(photos, script, "Steel bottle", "₹499", out, voice=lambda t: _wav())
    assert got["ok"] and got["voiced_scenes"] == 3, got
    probe = subprocess.run([exe, "-hide_banner", "-i", out], capture_output=True, text=True).stderr
    assert "720x1280" in probe and "Audio" in probe
