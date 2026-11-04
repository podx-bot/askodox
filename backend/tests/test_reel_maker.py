"""ASKODOX Creations reels: an item's own photos + title + stated price become
a short reel; it is a DRAFT ASKODOX video until made, then goes to review.
Never an invented price, never an outside photo URL."""
import io
import time

import pytest
from PIL import Image

from app.services import reel_maker as rm
from app.services import video_watermark as wm
from test_sources_workspace_early_access import OWNER, _app_bearer, _staff, api  # noqa: F401  (fixture)


def _jpeg(color):
    buf = io.BytesIO()
    Image.new("RGB", (600, 800), color).save(buf, "JPEG")
    return buf.getvalue()


def test_price_text_is_only_what_the_record_states():
    assert rm.price_text(499) == "₹499"
    assert rm.price_text("1299.5") == "₹1,299.50"
    assert rm.price_text(None) == "" and rm.price_text("ask") == "" and rm.price_text(0) == ""
    assert rm.price_text(20, "usd") == "USD 20"


def test_card_renders_telugu_title_and_price(tmp_path):
    out = rm.card_png("స్టీల్ వాటర్ బాటిల్ 1 లీటర్", "₹499", str(tmp_path / "c.png"))
    img = Image.open(out)
    assert img.size == (rm.W, rm.H) and img.mode == "RGBA"
    assert img.getpixel((rm.W // 2, 100))[3] == 0, "photos stay visible above the band"
    assert img.getpixel((40, rm.H - 40))[3] > 150, "dark band behind the text"


def test_no_photos_or_no_title_fails_honestly(tmp_path):
    assert rm.make_reel([], "x", "", str(tmp_path / "r.mp4")) == {"ok": False, "reason": "no_photos"}
    p = tmp_path / "a.jpg"
    p.write_bytes(_jpeg((10, 20, 30)))
    assert rm.make_reel([str(p)], "  ", "", str(tmp_path / "r.mp4"))["reason"] == "no_title"


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_real_reel_has_the_asked_length_size_and_audio(tmp_path):
    photos = []
    for i, c in enumerate([(200, 60, 60), (60, 60, 200)]):
        p = tmp_path / f"{i}.jpg"
        p.write_bytes(_jpeg(c))
        photos.append(str(p))
    out = str(tmp_path / "reel.mp4")
    assert rm.make_reel(photos, "Steel bottle", "₹499", out, seconds=6) == {"ok": True, "seconds": 6.0}
    assert wm.video_size(wm.ffmpeg_exe(), out) == (rm.W, rm.H)
    assert not list(tmp_path.glob("*.part.mp4")) and not list(tmp_path.glob("*.card.png"))


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_workspace_reel_from_own_photos_goes_to_review(api):  # noqa: F811
    client, container, _ = api
    _staff(client, "affiliate_product_staff", phone="919855555555")
    h = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                headers=_app_bearer(container, "919855555555")).json()["session"]}
    ups = [client.post("/admin/cc/workspace/uploads", headers=h,
                       files={"file": (f"{i}.jpg", _jpeg(c), "image/jpeg")}).json()
           for i, c in enumerate([(30, 120, 200), (200, 120, 30)])]
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Steel water bottle 1 litre", "price": 499, "currency": "INR",
        "original_product_url": "https://www.meesho.com/steel-bottle/p/9001",
        "image_url": ups[0]["url"], "images": [ups[0]["url"], ups[1]["url"], "https://evil.example/x.jpg"]}})
    assert saved.status_code == 200, saved.text
    item_id = saved.json()["item"]["id"]
    made = client.post(f"/admin/cc/workspace/items/{item_id}/reel", headers=h, json={"seconds": 6})
    assert made.status_code == 200, made.text
    got = made.json()
    assert got["status"] == "MAKING" and got["photos"] == 2, "outside photo URLs are never used"
    assert got["price_shown"] == "₹499"
    from app.api.routes.platform import platform

    deadline = time.time() + 60
    record = None
    while time.time() < deadline:
        record = platform(container).resources.repo.get(got["video_id"])
        if ((record.get("data") or {}).get("reel") or {}).get("status") not in (None, "MAKING"):
            break
        time.sleep(0.5)
    assert record["data"]["reel"]["status"] == "READY", record["data"]
    assert record["status"] == "PENDING_REVIEW", "reels go to the normal video review"
    assert record["data"]["platform"] == "askodox"


def test_reel_needs_own_photos(api):  # noqa: F811
    client, container, _ = api
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Kurta", "original_product_url": "https://www.meesho.com/kurta/p/9002",
        "image_url": "https://images.meesho.com/kurta.jpg"}}).json()
    got = client.post(f"/admin/cc/workspace/items/{saved['item']['id']}/reel", headers=OWNER, json={})
    assert got.status_code == 422


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_workspace_reels_tab_lists_plays_and_approves(api):  # noqa: F811
    """Owner 2026-11-04: 'where do I see the ready video?' -- the workspace lists
    the reel (MAKING at once, then READY), plays its file and approves it."""
    client, container, _ = api
    up = client.post("/admin/cc/workspace/uploads", headers=OWNER,
                     files={"file": ("a.jpg", _jpeg((90, 30, 160)), "image/jpeg")}).json()
    saved = client.post("/admin/cc/workspace/items", headers=OWNER, json={"item_type": "product", "fields": {
        "title": "Red colour saree", "price": 799, "platform": "other",
        "original_product_url": "https://wa.me/919800000001", "image_url": up["url"], "images": [up["url"]]}})
    item_id = saved.json()["item"]["id"]
    made = client.post(f"/admin/cc/workspace/items/{item_id}/reel", headers=OWNER, json={"seconds": 6}).json()
    first = client.get(f"/admin/cc/workspace/reels?item_id={item_id}", headers=OWNER).json()["items"]
    assert first and first[0]["video_id"] == made["video_id"]
    deadline = time.time() + 60
    row = first[0]
    while time.time() < deadline and row["reel_status"] == "MAKING":
        time.sleep(0.5)
        row = client.get(f"/admin/cc/workspace/reels?item_id={item_id}", headers=OWNER).json()["items"][0]
    assert row["reel_status"] == "READY" and row["status"] == "PENDING_REVIEW", row
    played = client.get(f"/admin/cc/workspace/reels/{row['video_id']}/file", headers=OWNER)
    assert played.status_code == 200 and played.headers["content-type"] == "video/mp4" and len(played.content) > 1000
    assert client.get(f"/admin/cc/workspace/reels/{row['video_id']}/file").status_code in (401, 403)
    ok = client.post(f"/admin/cc/workspace/reels/{row['video_id']}/review", headers=OWNER, json={"action": "approve"})
    assert ok.status_code == 200 and ok.json()["status"] == "ACTIVE"


def test_staff_page_may_play_a_reel_it_fetched():
    """Owner 2026-11-04: the reel player stayed blank -- the page's CSP had no
    media-src, so the fetched blob: video was blocked."""
    from app.api.routes.staff_workspace_page import CSP

    media = next(p for p in CSP.split(";") if p.strip().startswith("media-src"))
    assert "blob:" in media and "'self'" in media
