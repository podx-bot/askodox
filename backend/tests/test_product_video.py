"""AI product video (owner 2026-11-20): staff give the link, photos, price and review screenshots; the 30-second video
makes itself and waits for Approve. Truth rules: no first-person use claims by an AI person, review scenes only from
real reviews, children never speak, a missing voice is honest (captions only)."""
import io
import time

import pytest
from PIL import Image

from app.services import product_video as pv
from app.services import video_watermark as wm
from test_sources_workspace_early_access import OWNER, api  # noqa: F401  (fixture)

REVIEWS = {"rating": 3.9, "ratings_count": 272, "reviews_count": 86,
           "stars": {"5": 125, "4": 72, "3": 33, "2": 12, "1": 30},
           "good": ["colour same as photo", "quality good"], "bad": ["size runs small"]}


def _jpeg(color, size=(600, 800)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "JPEG")
    return buf.getvalue()


def test_reviews_keep_only_visible_numbers_and_short_points():
    got = pv.clean_reviews({"rating": "3.9", "ratings_count": "272", "stars": {"5": 125, "4": 72, "3": 33, "2": 12,
                                                                                "1": 30},
                            "good": ["colour same as photo", 7, ""], "bad": "Priya said bad", "extra": "x"})
    assert got["rating"] == 3.9 and got["ratings_count"] == 272 and got["stars"]["1"] == 30
    assert got["good"] == ["colour same as photo"] and "bad" not in got and "extra" not in got
    assert pv.clean_reviews({"rating": 9}) == {} and pv.clean_reviews("junk") == {}
    assert pv.low_share(got) == (42, 272)


def test_script_drops_false_first_person_lines_and_review_scenes_without_reviews():
    raw = {"style": "presenter", "presenter": "girl_7", "lines": [
        {"caption": "నమస్తే! ASKODOX నుంచి.", "scene": "photo"},
        {"caption": "నేను వాడాను, చాలా బాగుంది", "scene": "photo"},
        {"caption": "I used it daily", "scene": "photo"},
        {"caption": "ఇది కాటన్ నైట్ డ్రెస్.", "scene": "photo"},
        {"caption": "రేటింగ్ 4.5", "scene": "rating"},
        {"caption": "రంగు బాగుంది", "scene": "photo"},
        {"caption": "లింక్ కిందే ఉంది.", "scene": "photo"}]}
    got = pv.clean_script(raw, reviews={})
    captions = [l["caption"] for l in got["lines"]]
    assert "నేను వాడాను, చాలా బాగుంది" not in captions and "I used it daily" not in captions
    assert all(l["scene"] != "rating" for l in got["lines"]), "no reviews -> no rating scene"
    assert got["lines"][-1]["scene"] == "end"
    assert got["presenter"] == pv.DEFAULT_PRESENTER, "children are never the voice"


def test_script_keeps_review_points_only_with_real_reviews():
    raw = {"presenter": "man_42", "lines": [{"caption": f"line {i}", "scene": "photo"} for i in range(4)],
           "points": {"good": ["రంగు ఫోటోలో లాగే"], "bad": ["సైజు చిన్నది"]}}
    assert pv.clean_script(raw, reviews=REVIEWS)["points"]["good"] == ["రంగు ఫోటోలో లాగే"]
    assert pv.clean_script(raw, reviews={})["points"] == {}
    assert pv.clean_script(raw, reviews={})["presenter"] == "man_42"


def test_no_model_answer_gives_a_plain_script_from_the_record():
    script = pv.write_script(lambda _: "not json", {"title": "Steel bottle"}, REVIEWS, "Meesho", "₹499")
    assert script.get("fallback") and script["lines"][-1]["scene"] == "end"
    assert any("3.9" in l["caption"] for l in script["lines"]) and any("₹499" in l["caption"] for l in script["lines"])
    assert pv.write_script(None, {"title": "x"}, {}, "Meesho", "")["presenter"] in pv.PRESENTERS


def test_prompt_carries_only_record_facts_and_the_unhappy_share():
    text = pv.script_prompt({"title": "Kurti", "price": 349, "seller_phone": "9999"}, REVIEWS, "Meesho", "te")
    assert "Kurti" in text and "9999" not in text and "42 of 272" in text and "Telugu" in text


def test_every_presenter_photo_is_present():
    import os

    for meta in pv.PRESENTERS.values():
        assert os.path.exists(os.path.join(pv.PRESENTER_DIR, meta["file"])), meta
    assert not any(m["speaks"] for m in pv.PRESENTERS.values() if m["age"] < 18)


def test_store_name_from_link():
    assert pv.store_name("https://www.meesho.com/x/p/1") == "Meesho"
    assert pv.store_name("https://amzn.to/abc") == "Amazon"
    assert pv.store_name("https://wa.me/9198") == "ASKODOX"


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_render_writes_a_vertical_video(tmp_path):
    script = pv.fallback_script({"title": "Steel bottle"}, REVIEWS, "Meesho", "₹499")
    script["points"] = {}
    photos = [Image.new("RGB", (500, 700), (200, 60, 60)), Image.new("RGB", (700, 500), (60, 60, 200))]
    out = str(tmp_path / "v.mp4")
    got = pv.render(photos, script, REVIEWS, "Meesho", "₹499", None, out, exe=wm.ffmpeg_exe(), seconds_without_voice=2)
    assert got["ok"], got
    assert wm.video_size(wm.ffmpeg_exe(), out) == (pv.W, pv.H)
    assert not list(tmp_path.glob("*.part.mp4"))


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_workspace_ai_video_uses_store_photos_and_waits_for_approve(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    container.affiliate_image_fetch = lambda url: _jpeg((40, 160, 90))
    monkeypatch.setattr(pv, "SILENT_SECONDS", 2.0)
    monkeypatch.setattr(pv, "synthesize", lambda *a, **k: (None, "none"))
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Cotton women nightdress", "price": 349, "currency": "INR",
        "original_product_url": "https://www.meesho.com/nightdress/p/9101",
        "image_url": "https://images.meesho.com/a.jpg", "images": ["https://images.meesho.com/b.jpg"]}})
    assert saved.status_code == 200, saved.text
    item_id = saved.json()["item"]["id"]
    made = client.post(f"/admin/cc/workspace/items/{item_id}/ai-video", headers=OWNER, json={"reviews": REVIEWS})
    assert made.status_code == 200, made.text
    got = made.json()
    assert got["status"] == "MAKING" and got["photos"] == 2 and got["store"] == "Meesho" and got["reviews"]
    deadline = time.time() + 90
    row = None
    while time.time() < deadline:
        rows = client.get(f"/admin/cc/workspace/reels?item_id={item_id}", headers=OWNER).json()["items"]
        row = rows[0] if rows else None
        if row and row["reel_status"] != "MAKING":
            break
        time.sleep(0.5)
    assert row["reel_status"] == "READY" and row["status"] == "PENDING_REVIEW", row
    assert row["ai"] and row["script"] and row["voice_path"] == "none"
    from app.api.routes.platform import platform

    data = platform(container).resources.repo.get(row["video_id"])["data"]
    assert data["store_item_id"] == str(item_id) and "meesho.com" in data["buy_url"]
    ok = client.post(f"/admin/cc/workspace/reels/{row['video_id']}/review", headers=OWNER, json={"action": "approve"})
    assert ok.json()["status"] == "ACTIVE"


def test_ai_video_daily_limit_zero_turns_it_off(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    from app.services import platform_settings

    monkeypatch.setattr(platform_settings, "get", lambda key, default=None: 0 if key == "video_ai.daily_max" else 1)
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Kurta", "original_product_url": "https://www.meesho.com/kurta/p/9102"}}).json()
    got = client.post(f"/admin/cc/workspace/items/{saved['item']['id']}/ai-video", headers=OWNER, json={})
    assert got.status_code == 429


def test_review_screenshots_are_read_without_saving(api):  # noqa: F811
    import base64

    client, container, _ = api

    class Fake:
        def analyze_with_prompt(self, photos, prompt, **_):
            assert "reviews" in prompt
            return {"rating": 4.1, "ratings_count": 10, "good": ["fits well"], "bad": []}, 1

    container.universal_image_service = Fake()
    shot = base64.b64encode(_jpeg((250, 250, 250), (300, 300))).decode()
    got = client.post("/admin/cc/workspace/reviews/read", headers=OWNER,
                      json={"images": [{"data": shot, "mime": "image/jpeg"}]})
    assert got.status_code == 200, got.text
    assert got.json()["reviews"] == {"rating": 4.1, "ratings_count": 10, "good": ["fits well"]}
