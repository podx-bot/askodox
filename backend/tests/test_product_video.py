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
    share = client.get(f"/admin/cc/workspace/reels/{row['video_id']}/share", headers=OWNER).json()
    assert share["public_video"] and f"/p/{item_id}?from=fb" in share["texts"]["facebook"]["text"]
    assert "#Affiliate" in share["texts"]["instagram"]["text"] and isinstance(share["faq"], list)
    page = client.get(f"/p/{item_id}")
    assert page.status_code == 200 and "<video" in page.text and "3.9/5" in page.text


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


# ---- 4-step affiliate flow, share texts, public pages (owner 2026-11-20) ----
from app.services import affiliate_publish as ap  # noqa: E402
from app.services import product_pages as ppg  # noqa: E402


def test_photo_fill_never_carries_a_price_or_promise():
    got = ap.clean_photo_fields({"title": "Women Cotton Nightdress", "colour": "maroon", "material": "cotton",
                                 "sizes": ["M", "L", "M"], "features": ["V neck", "flutter sleeves"],
                                 "description": "Best quality at ₹349 only!"})
    assert got["title"] == "Women Cotton Nightdress" and got["sizes"] == ["M", "L"]
    assert "₹" not in got["description"] and "Best" not in got["description"]
    assert "V neck" in got["description"] and "Sizes: M, L" in got["description"]
    assert ap.clean_photo_fields("x") == {}


def test_faq_drops_promises_the_store_did_not_make():
    got = ap.clean_faq({"faq": [{"q": "ధర ఎంత?", "a": "₹349"}, {"q": "COD ఉందా?", "a": "Cash on delivery ఉంది"},
                                {"q": "", "a": "x"}]})
    assert got == [{"q": "ధర ఎంత?", "a": "₹349"}]


def test_share_texts_disclose_and_send_instagram_youtube_to_the_profile():
    t = ap.share_texts({"title": "Cotton Nightdress", "price": 349,
                        "description": "Maroon floral print. Lace at the neck. Full length."},
                       REVIEWS, "Meesho", "https://askodox.com/p/7")
    assert "https://askodox.com/p/7" in t["facebook"]["text"] and "#Affiliate" in t["facebook"]["text"]
    assert ap.SHOP_URL in t["instagram"]["text"] and "#Affiliate" in t["instagram"]["text"]
    assert len(t["youtube"]["title"]) <= 100 and "#shorts" in t["youtube"]["title"]
    assert "₹349" in t["facebook"]["text"] and "3.9" in t["facebook"]["text"]


def test_workspace_fill_from_photos_reads_only_our_uploads(api):  # noqa: F811
    client, container, _ = api

    class Fake:
        def analyze_with_prompt(self, photos, prompt, **_):
            assert "NEVER a price" in prompt and len(photos) == 1
            return {"title": "Steel Bottle 1L", "features": ["screw cap"], "description": "A steel bottle."}, 1

    container.universal_image_service = Fake()
    up = client.post("/admin/cc/workspace/uploads", headers=OWNER,
                     files={"file": ("a.jpg", _jpeg((10, 90, 160)), "image/jpeg")}).json()
    got = client.post("/admin/cc/workspace/fill-from-photos", headers=OWNER,
                      json={"photos": [up["url"], "https://evil.example/x.jpg"]})
    assert got.status_code == 200, got.text
    assert got.json()["fields"]["title"] == "Steel Bottle 1L"
    none = client.post("/admin/cc/workspace/fill-from-photos", headers=OWNER, json={"photos": ["https://e.x/a.jpg"]})
    assert none.status_code == 422


def test_public_product_page_counts_and_sends_to_the_commission_link(api):  # noqa: F811
    client, container, _ = api
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Cotton nightdress", "price": 349, "original_product_url": "https://www.meesho.com/nd/p/9201",
        "affiliate_url": "https://www.meesho.com/nd/p/9201?af=manohar", "image_url": "https://images.meesho.com/a.jpg"}})
    item = saved.json()["item"]
    assert saved.json()["review_status"] == "LIVE"
    page = client.get(f"/p/{item['id']}?from=fb")
    assert page.status_code == 200 and "ASKODOX" in page.text and "Affiliate" in page.text
    assert f"/p/{item['id']}/buy?from=fb" in page.text
    buy = client.get(f"/p/{item['id']}/buy?from=fb", follow_redirects=False)
    assert buy.status_code == 302 and buy.headers["location"].endswith("?af=manohar")
    assert ppg.clicks(container, item["id"])["fb"] == {"view": 1, "buy": 1}
    shop = client.get("/shop")
    assert shop.status_code == 200 and f"/p/{item['id']}" in shop.text
    assert client.get("/p/999999").status_code == 404


def test_draft_items_have_no_public_page(api):  # noqa: F811
    client, container, _ = api
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "action": "draft",
                                                                          "fields": {"title": "Draft kurta",
                                                                                     "original_product_url": "https://www.meesho.com/k/p/9202"}})
    assert client.get(f"/p/{saved.json()['item']['id']}").status_code == 404
