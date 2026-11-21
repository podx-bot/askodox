"""ASKODOX Studio (owner 2026-11-21): bought to shoot -> return deadline from the delivery date -> stages -> return /
keep -> reminders once per purchase and kind. Plus the staff page JavaScript still parses."""
import datetime as dt
import re
import shutil
import subprocess

import pytest

from app.services import studio_store as ss
from test_sources_workspace_early_access import OWNER, api  # noqa: F401  (fixture)

NOW = dt.datetime(2026, 11, 21, 4, 0, tzinfo=dt.timezone.utc)  # 09:30 IST


def _clock(moment=NOW):
    return lambda: moment


def test_deadline_bucket_and_warnings():
    assert ss.deadline("2026-11-20", "return", 7) == "2026-11-27"
    assert ss.deadline("2026-11-20", "exchange", 7) == "" and ss.deadline("", "return", 7) == ""
    assert [ss.bucket(x) for x in (-1, 0, 1, 2, None)] == ["today", "today", "tomorrow", "time", ""]
    assert ss.warnings({"return_option": "none", "account_label": "x", "account_whitelisted": 0}) == \
        ["keep", "not_whitelisted"]


def test_store_flow(tmp_path):
    store = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock())
    acct = store.save_account("meesho", "Wife 7227", True)
    assert acct["store"] == "Meesho" and acct["whitelisted"] == 1
    p = store.create({"title": "Silver anklets", "store": "Meesho", "account_id": acct["id"], "paid": "249",
                      "pack": "pair", "order_date": "2026-11-12", "delivery_date": "2026-11-15",
                      "return_option": "return", "return_days": 7}, actor="staff-1")
    assert p["return_deadline"] == "2026-11-22" and p["days_left"] == 1 and p["bucket"] == "tomorrow"
    assert p["stage"] == "delivered" and p["paid_paise"] == 24900 and p["pack_count"] == 2 and p["warnings"] == []
    with pytest.raises(ss.StudioError):
        store.create({"title": "x", "store": "Meesho", "order_date": "2026-11-20", "delivery_date": "2026-11-18"},
                     actor="staff-1")
    with pytest.raises(ss.StudioError):
        store.create({"title": "x", "store": "Meesho", "affiliate_link": "http://bad"}, actor="staff-1")
    p = store.set_stage(p["id"], "shot")
    with pytest.raises(ss.StudioError):
        store.set_stage(p["id"], "delivered")  # forward only
    p = store.set_stage(p["id"], "posted")
    assert p["next_action"] == "return"
    p = store.record_return(p["id"], {"return_id": "RT-1", "fee": "0", "refund_status": "sent"})
    assert p["refund_status"] == "sent" and p["next_action"] == "refund"
    p = store.record_return(p["id"], {"refund_status": "refunded"})
    assert p["stage"] == "returned" and p["days_left"] is None
    with pytest.raises(ss.StudioError):
        store.keep(p["id"], "studio")  # closed
    e = store.create({"title": "Kurti", "store": "Flipkart", "paid": 399, "return_option": "exchange"},
                     actor="staff-2")
    assert e["return_deadline"] == "" and "keep" in e["warnings"] and e["stage"] == "bought"
    store.keep(e["id"], "no_return")
    s = store.summary(store.list())
    assert s["open"] == 0 and s["spent"] == 399.0
    assert [r["id"] for r in store.list(actor="staff-2")] == [e["id"]]


def test_reminders_once_per_kind(tmp_path):
    store = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock())
    tomorrow = store.create({"title": "Anklets", "store": "Meesho", "delivery_date": "2026-11-15",
                             "return_option": "return", "return_days": 7}, actor="staff-1")
    today = store.create({"title": "Kurti", "store": "Meesho", "delivery_date": "2026-11-14",
                          "return_option": "return", "return_days": 7}, actor="staff-1")
    store.set_stage(today["id"], "posted")
    kinds = {(d["purchase"]["id"], d["kind"]) for d in store.due_reminders()}
    assert (tomorrow["id"], "d1") in kinds and (tomorrow["id"], "not_shot") in kinds
    assert (today["id"], "d0") in kinds and (today["id"], "send_return") in kinds
    assert store.mark_sent(today["id"], "d0") and not store.mark_sent(today["id"], "d0")
    early = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock(dt.datetime(2026, 11, 21, 1, 0, tzinfo=dt.timezone.utc)))
    assert all(d["kind"] != "d0" for d in early.due_reminders())  # 06:30 IST: the deadline-day push waits for 08:00
    assert ss.reminder_text(today, "d0")["title"].startswith("ఈరోజే return ఆఖరు")


def test_studio_routes_and_reminder_push(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    container.studio_store = ss.StudioStore(container.settings.database_path, clock=_clock())
    home = client.get("/admin/cc/workspace/studio", headers=OWNER)
    assert home.status_code == 200 and home.json()["summary"]["open"] == 0 and "Meesho" in home.json()["stores"]
    acct = client.post("/admin/cc/workspace/studio/accounts", headers=OWNER,
                       json={"store": "Meesho", "label": "Shop 7227", "whitelisted": False}).json()["account"]
    made = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={
        "title": "Silver anklets", "store": "Meesho", "account_id": acct["id"], "paid": 249,
        "delivery_date": "2026-11-15", "return_option": "return", "return_days": 7})
    assert made.status_code == 200, made.text
    p = made.json()["purchase"]
    assert p["bucket"] == "tomorrow" and "not_whitelisted" in p["warnings"]
    bad = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={"title": "x", "store": "Meesho",
                                                                                    "order_date": "21-11-2026"})
    assert bad.status_code == 422
    got = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/stage", headers=OWNER, json={"stage": "shot"})
    assert got.json()["purchase"]["stage"] == "shot"
    back = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/stage", headers=OWNER,
                       json={"stage": "bought"})
    assert back.status_code == 422
    sent = []
    from app.api.routes import studio as studio_routes

    class _Push:
        def notify(self, user_id, **kw):
            sent.append((user_id, kw["event_key"]))
            return 1

    monkeypatch.setattr("app.services.push_service.push_service", lambda c: _Push())
    first = studio_routes.send_reminders(container)
    again = studio_routes.send_reminders(container)
    assert first["sent"] >= 1 and again["sent"] == 0  # once per purchase and kind
    ret = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/return", headers=OWNER,
                      json={"return_id": "RT-9", "refund_status": "refunded", "fee": 0})
    assert ret.json()["purchase"]["stage"] == "returned"
    assert client.post("/admin/cc/workspace/studio/purchases/999/keep", headers=OWNER, json={}).status_code == 404


@pytest.mark.skipif(not shutil.which("node"), reason="node not available")
def test_staff_page_script_parses(api, tmp_path):  # noqa: F811
    client, _, _ = api
    html = client.get("/staff").text
    scripts = re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S)
    assert scripts and "async function studio()" in html
    path = tmp_path / "page.js"
    path.write_text("\n;\n".join(scripts))
    proc = subprocess.run(["node", "--check", str(path)], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr[-800:]


# ------------------------------------------------------------------ round 2 --
from app.services import studio_video as sv  # noqa: E402
from app.services import video_watermark as wm  # noqa: E402

needs_ffmpeg = pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")


def test_tips_tags_lines_and_captions():
    assert sv.product_kind("Silver anklets pair") == "jewellery" and sv.product_kind("cotton kurti") == "clothes"
    assert sv.product_kind("something new") == "other" and sv.shoot_tips({"title": "LED bulb"})["kind"] == "gadgets"
    pair = {"pack": "pair", "pack_count": 2, "show_price_paise": 24900, "title": "Anklets", "store": "Meesho",
            "affiliate_link": "https://wishlink.com/share/x", "share_earn_link": ""}
    assert sv.price_tag(pair) == "PAIR ₹249" and sv.product_line(pair, "te") == "జత కలిపి ₹249 మాత్రమే."
    assert sv.price_tag({**pair, "pack": "single", "pack_count": 3}) == "₹249 EACH"
    lines = sv.script(pair, {"language": "te", "line": "  చిన్న మువ్వలు ఉన్నాయి "})
    assert [l["kind"] for l in lines] == ["fixed", "own", "price", "fixed"]
    cap = sv.captions(pair)
    assert "@meeshoapp" in cap["facebook"]["text"] and "#Affiliate" in cap["instagram"]["text"]
    assert "wishlink" not in cap["whatsapp"]["text"] and "Share & Earn" in cap["whatsapp"]["text"]
    assert "LINK" in cap["instagram"]["text"]


def test_checklist_names_what_is_missing():
    row = {"store": "Meesho", "video_file": "", "show_price_paise": 0, "checks": {}, "affiliate_link": "",
           "edit_status": "", "pack": "single", "pack_count": 1}
    c = sv.checklist(row, "2026-11-21")
    assert not c["ready"] and any("సొంత వీడియో" in m for m in c["missing"])
    row.update(video_file="a.mp4", show_price_paise=100, affiliate_link="https://x", edit_status="READY",
               checks={"same_product": True, "price_checked_on": "2026-11-20"})
    assert sv.checklist(row, "2026-11-21")["missing"] == [r["label"] for r in sv.STORE_RULES["Meesho"]
                                                         if r["id"] == "price_today"]  # yesterday's tick expired
    row["checks"]["price_checked_on"] = "2026-11-21"
    assert sv.checklist(row, "2026-11-21")["ready"]


def test_voice_lines_are_never_paid_twice(tmp_path, monkeypatch):
    store = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock())
    calls = []
    monkeypatch.setattr("app.services.product_video.synthesize",
                        lambda c, text, g: (calls.append(text) or b"ID3audio", "elevenlabs"))
    row = {"pack": "pair", "pack_count": 2, "show_price_paise": 24900}
    lines = sv.script(row, {"language": "te"})
    _, first = sv.voice_files(None, store, lines, "female", str(tmp_path))
    _, again = sv.voice_files(None, store, lines, "female", str(tmp_path))
    assert first == {"cached": 0, "new": 3, "failed": 0} and again == {"cached": 3, "new": 0, "failed": 0}
    _, price = sv.voice_files(None, store, sv.script({**row, "show_price_paise": 19900}, {"language": "te"}), "female",
                              str(tmp_path))
    assert price == {"cached": 2, "new": 1, "failed": 0}  # a price change re-records only the price line
    assert len(calls) == 4


def _clip(path, size):
    subprocess.run([wm.ffmpeg_exe(), "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc=size={size}:rate=30",
                    "-f", "lavfi", "-i", "sine=frequency=300", "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-shortest", str(path)], check=True)
    return path.read_bytes()


@needs_ffmpeg
def test_shoot_edit_publish_post_flow(api, tmp_path):  # noqa: F811
    import time

    client, container, _ = api
    container.studio_store = ss.StudioStore(container.settings.database_path)
    p = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={
        "title": "Silver anklets", "store": "Meesho", "paid": 249, "pack": "pair", "return_option": "return",
        "return_days": 7, "affiliate_link": "https://wishlink.com/share/abc"}).json()["purchase"]
    url = f"/admin/cc/workspace/studio/purchases/{p['id']}"
    wide = client.post(url + "/video", headers=OWNER, files={"file": ("w.mp4", _clip(tmp_path / "w.mp4", "640x360"),
                                                                       "video/mp4")})
    assert wide.status_code == 422  # landscape refused
    up = client.post(url + "/video", headers=OWNER, files={"file": ("v.mp4", _clip(tmp_path / "v.mp4", "360x640"),
                                                                    "video/mp4")})
    assert up.status_code == 200, up.text
    d = up.json()["purchase"]
    assert d["stage"] == "shot" and d["tips"]["kind"] == "jewellery" and d["video_url"].endswith("/media/raw")
    assert client.get(d["video_url"], headers=OWNER).status_code == 200
    assert client.get(d["video_url"]).status_code in (401, 403)  # staff only
    assert client.post(url + "/edit", headers=OWNER, json={"voice": "none"}).status_code == 422  # no price yet
    client.post(url + "/checks", headers=OWNER, json={"show_price": 249, "ticks": {}})
    assert client.post(url + "/edit", headers=OWNER, json={"voice": "none", "presenter": True}).status_code == 200
    deadline = time.time() + 120
    while time.time() < deadline:
        d = client.get(url, headers=OWNER).json()["purchase"]
        if d["edit_status"] != "MAKING":
            break
        time.sleep(0.5)
    assert d["edit_status"] == "READY" and d["stage"] == "edited", d.get("edit_reason")
    blocked = client.post(url + "/publish", headers=OWNER)
    assert blocked.status_code == 422 and "ప్రోడక్ట్ = లింక్" in blocked.json()["detail"]
    assert client.post(url + "/posted", headers=OWNER, json={"platform": "instagram",
                                                             "url": "https://instagram.com/p/x"}).status_code == 422
    client.post(url + "/checks", headers=OWNER, json={"ticks": {"same_product": True}})
    pub = client.post(url + "/publish", headers=OWNER)
    assert pub.status_code == 200, pub.text
    d = pub.json()["purchase"]
    name = d["download_url"].rsplit("/", 1)[1]
    assert client.get(f"/media/studio/{name}").status_code == 200
    post = client.post(url + "/posted", headers=OWNER, json={"platform": "instagram", "url": "https://instagram.com/p/x"})
    assert post.json()["purchase"]["stage"] == "posted" and "instagram" in post.json()["purchase"]["posts"]
    client.post(url + "/checks", headers=OWNER, json={"show_price": 199})  # price changed -> make the video again
    assert client.get(url, headers=OWNER).json()["purchase"]["edit_status"] == "PRICE_CHANGED"
    assert client.get("/media/studio/" + "0" * 32 + ".mp4").status_code == 404
