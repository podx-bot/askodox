"""Collection video (owner 2026-11-21): 2-5 LIVE items in one reel with the ASKODOX brand on top, a theme title,
each item's photos + name + price and an honest fixed voice; share texts for Facebook / Instagram / YouTube /
WhatsApp status (Meesho: @meeshoapp, and never a buy link on WhatsApp)."""
import io
import time

import pytest
from PIL import Image

from app.services import affiliate_publish as ap
from app.services import collection_video as cv
from app.services import product_video as pv
from app.services import video_watermark as wm
from test_sources_workspace_early_access import OWNER, api  # noqa: F401  (fixture)


def _jpeg(color, size=(600, 800)):
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "JPEG")
    return buf.getvalue()


def test_theme_and_names_in_the_picture_are_latin_only():
    assert cv.clean_theme("Top winter finds") == "TOP WINTER FINDS"
    assert cv.clean_theme("చలికాలం ఫైండ్స్") == cv.DEFAULT_THEME  # no Telugu burned into the picture
    assert cv.clean_theme("") == cv.DEFAULT_THEME and cv.clean_theme("Under ₹299") == "UNDER ₹299"
    assert cv.picture_name("Purple blouse బ్లౌజ్") == "Purple blouse"
    assert len(cv.picture_name("x" * 90)) <= 48


def test_script_says_only_name_and_price():
    items = [{"title": "Cotton Kurti"}, {"title": "Brass Glass"}]
    lines = cv.script(items, ["₹399", ""], "te")
    assert [l["kind"] for l in lines] == ["intro", "item", "item", "outro"]
    assert "Cotton Kurti" in lines[1]["spoken"] and "₹399" in lines[1]["spoken"]
    assert "Brass Glass" in lines[2]["spoken"] and "₹" not in lines[2]["spoken"]
    for lang in ("hi", "en"):
        assert len(cv.script(items, ["₹1", "₹2"], lang)) == 4


def test_collection_share_texts_meesho_rules():
    rows = [{"item": {"title": "Cotton Kurti", "price": 399}, "store": "Meesho", "page": "https://askodox.com/p/1"},
            {"item": {"title": "Steel Bottle", "price": 249}, "store": "Amazon", "page": "https://askodox.com/p/2"}]
    t = ap.collection_share_texts(rows, "TOP FINDS")
    assert "@meeshoapp" in t["facebook"]["text"] and "#Affiliate" in t["instagram"]["text"]
    assert "https://askodox.com/p/1?from=fb" in t["facebook"]["text"] and "#shorts" in t["youtube"]["title"]
    wa = t["whatsapp"]["text"]
    assert "p/1" not in wa and ap.MEESHO_WA_NOTE in wa  # Meesho: Share & Earn link only, pasted by staff
    assert "https://askodox.com/p/2?from=wa" in wa and "₹249" in wa


def test_single_share_texts_carry_whatsapp_and_meeshoapp():
    t = ap.share_texts({"title": "Kurti", "price": 399}, {}, "Meesho", "https://askodox.com/p/7")
    assert "@meeshoapp" in t["facebook"]["text"] and ap.MEESHO_WA_NOTE in t["whatsapp"]["text"]
    other = ap.share_texts({"title": "Bottle", "price": 249}, {}, "Amazon", "https://askodox.com/p/8")
    assert "@meeshoapp" not in other["facebook"]["text"] and "p/8?from=wa" in other["whatsapp"]["text"]


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_render_writes_a_vertical_collection(tmp_path):
    groups = [[Image.new("RGB", (600, 800), (120, 60, 160))], [Image.new("RGB", (800, 600), (200, 150, 40))],
              [Image.new("RGB", (600, 600), (40, 160, 90))]]
    items = [{"title": "A"}, {"title": "B"}, {"title": "C"}]
    lines = cv.script(items, ["₹1", "₹2", ""], "en")
    out = str(tmp_path / "c.mp4")
    got = cv.render(groups, items, ["₹1", "₹2", ""], "TOP", lines, None, out, exe=wm.ffmpeg_exe())
    assert got["ok"], got
    assert wm.video_size(wm.ffmpeg_exe(), out) == (cv.W, cv.H)


def _item(client, title, url, price):
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": title, "price": price, "currency": "INR", "original_product_url": url,
        "image_url": "https://images.example.com/a.jpg"}})
    assert saved.status_code == 200, saved.text
    return saved.json()["item"]["id"]


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_workspace_collection_video_waits_for_approve_and_shares(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    container.affiliate_image_fetch = lambda url: _jpeg((40, 160, 90))
    monkeypatch.setattr(pv, "synthesize", lambda *a, **k: (None, "none"))
    a = _item(client, "Cotton Kurti", "https://www.meesho.com/kurti/p/9101", 399)
    b = _item(client, "Steel Bottle", "https://www.amazon.in/dp/B0TESTX123", 249)
    one = client.post("/admin/cc/workspace/collections/ai-video", headers=OWNER, json={"item_ids": [a, a]})
    assert one.status_code == 422  # the same product twice is one product
    made = client.post("/admin/cc/workspace/collections/ai-video", headers=OWNER,
                       json={"item_ids": [a, b], "theme": "top winter finds", "voice": False})
    assert made.status_code == 200, made.text
    assert made.json()["theme"] == "TOP WINTER FINDS"
    deadline, row = time.time() + 120, None
    while time.time() < deadline:
        rows = [r for r in client.get("/admin/cc/workspace/reels", headers=OWNER).json()["items"]
                if r["video_id"] == made.json()["video_id"]]
        row = rows[0] if rows else None
        if row and row["reel_status"] != "MAKING":
            break
        time.sleep(0.5)
    assert row["reel_status"] == "READY" and row["status"] == "PENDING_REVIEW", row
    share = client.get(f"/admin/cc/workspace/reels/{row['video_id']}/share", headers=OWNER).json()
    assert share["collection"] == [a, b] and "@meeshoapp" in share["texts"]["facebook"]["text"]
    assert f"/p/{b}?from=wa" in share["texts"]["whatsapp"]["text"]


def test_collection_needs_live_items(api):  # noqa: F811
    client, _, _ = api
    draft = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "action": "draft",
                                                                         "fields": {"title": "Draft thing",
                                                                                    "original_product_url": "https://www.meesho.com/x/p/77"}})
    a = draft.json()["item"]["id"]
    b = _item(client, "Live thing", "https://www.meesho.com/y/p/78", 100)
    got = client.post("/admin/cc/workspace/collections/ai-video", headers=OWNER, json={"item_ids": [a, b]})
    assert got.status_code == 422 and "LIVE" in got.text
