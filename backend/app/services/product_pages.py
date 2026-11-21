"""Public ASKODOX product pages (owner 2026-11-20: "when someone taps the link on Facebook, ASKODOX should open first,
then the store -- our branding"). ``/p/{id}`` shows the item's approved video, details, rating summary, buyers' points
and DM answers with the ASKODOX brand; "Buy" goes through ``/p/{id}/buy`` (counted per platform) to the commission
link. ``/shop`` lists every LIVE product -- the one profile link for Instagram / YouTube, where captions are not
clickable. Only LIVE items; nothing private is shown (no staff, no commission rate)."""
from __future__ import annotations

import html
import os
import re
import sqlite3
import time
from typing import Any, Dict, List, Optional

PUBLIC_BASE = "https://askodox.com"
PLAY_URL = "https://play.google.com/store/apps/details?id=com.askodox.askodox"
SOURCES = ("fb", "ig", "yt", "wa", "app", "web")


def source_of(value: str) -> str:
    value = re.sub(r"[^a-z]", "", str(value or "").lower())[:10]
    return value if value in SOURCES else "web"


def _db(container: Any) -> str:
    return os.path.abspath(container.settings.database_path)


def _ensure(conn: sqlite3.Connection) -> None:
    conn.execute("CREATE TABLE IF NOT EXISTS product_page_clicks (item_id INTEGER NOT NULL, source TEXT NOT NULL, "
                 "kind TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, "
                 "PRIMARY KEY (item_id, source, kind, day))")


def record(container: Any, item_id: int, source: str, kind: str) -> None:
    """kind = view | buy. One counter row per item / platform / kind / day; never who."""
    try:
        with sqlite3.connect(_db(container)) as conn:
            _ensure(conn)
            day = time.strftime("%Y-%m-%d", time.gmtime())
            conn.execute("INSERT INTO product_page_clicks (item_id, source, kind, day, n) VALUES (?,?,?,?,1) "
                         "ON CONFLICT(item_id, source, kind, day) DO UPDATE SET n = n + 1",
                         (int(item_id), source_of(source), kind, day))
    except Exception:
        pass


def clicks(container: Any, item_id: int) -> Dict[str, Dict[str, int]]:
    out: Dict[str, Dict[str, int]] = {}
    try:
        with sqlite3.connect(_db(container)) as conn:
            _ensure(conn)
            for source, kind, n in conn.execute("SELECT source, kind, SUM(n) FROM product_page_clicks WHERE item_id=? "
                                                "GROUP BY source, kind", (int(item_id),)):
                out.setdefault(source, {})[kind] = int(n or 0)
    except Exception:
        pass
    return out


def live(item: Optional[Dict[str, Any]]) -> bool:
    return bool(item) and not item.get("deleted_at") and str(item.get("review_status") or "LIVE") == "LIVE"


def latest_video(videos: List[Dict[str, Any]], item_id: int) -> Optional[Dict[str, Any]]:
    """The newest ACTIVE ASKODOX video made for this item (data + its reel block)."""
    best = None
    for r in videos:
        data = r.get("data") or {}
        if r.get("archived") or r.get("status") != "ACTIVE" or str(data.get("store_item_id") or "") != str(item_id):
            continue
        if best is None or str(r.get("created_at") or "") > str(best.get("created_at") or ""):
            best = r
    return best


def buy_target(item: Dict[str, Any]) -> str:
    for key in ("affiliate_url", "original_product_url"):
        url = str(item.get(key) or "")
        if url.startswith("https://"):
            return url
    return ""


_STYLE = """*{box-sizing:border-box}body{margin:0;font:16px/1.5 system-ui,-apple-system,'Noto Sans Telugu',Roboto,sans-serif;
background:#f4f5fb;color:#14161f}header{background:#141b4d;color:#fff;padding:12px 16px;display:flex;align-items:center;
gap:10px}header b{font-size:20px;letter-spacing:.5px}header span{opacity:.8;font-size:13px}main{max-width:560px;margin:0 auto;
padding:12px}.card{background:#fff;border-radius:16px;padding:14px;margin:0 0 12px;box-shadow:0 1px 3px #0001}
video,img.hero{width:100%;border-radius:14px;background:#000;display:block}h1{font-size:20px;margin:6px 0}
.price{font-size:24px;font-weight:700;color:#0f7b43}.btn{display:block;text-align:center;padding:14px;border-radius:999px;
font-weight:700;text-decoration:none;margin:10px 0}.buy{background:#f43397;color:#fff}.app{background:#fff;color:#3b4bd8;
border:2px solid #3b4bd8}.mut{color:#5f6577;font-size:13px}.ok{color:#0f7b43}.warn{color:#a05a00}
.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}.grid a{background:#fff;border-radius:14px;overflow:hidden;
text-decoration:none;color:#14161f;box-shadow:0 1px 3px #0001}.grid img{width:100%;aspect-ratio:3/4;object-fit:cover;
display:block;background:#eee}.grid div{padding:8px;font-size:14px}.ad{display:inline-block;font-size:12px;
border:1px solid #c9ccd8;border-radius:99px;padding:1px 8px;color:#5f6577}details{margin:6px 0}summary{font-weight:600}"""


TERMS_URL = "https://askodox.com/affiliate-disclosure/"

def _page(title: str, body: str) -> str:
    return (f"<!doctype html><html lang=\"te\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" "
            f"content=\"width=device-width,initial-scale=1\"><title>{html.escape(title)} | ASKODOX</title>"
            f"<meta property=\"og:title\" content=\"{html.escape(title)}\"><style>{_STYLE}</style></head><body>"
            f"<header><b>ASKODOX</b><span>Picks</span></header><main>{body}</main>"
            # Owner 2026-11-21: the disclosure lives in the Terms, linked once at the foot of every page.
            f"<p class=\"mut\" style=\"text-align:center;font-size:12px\"><a href=\"{TERMS_URL}\" rel=\"nofollow\">"
            f"నిబంధనలు</a></p></body></html>")


def product_html(item: Dict[str, Any], video: Optional[Dict[str, Any]], source: str) -> str:
    esc = html.escape
    data = (video or {}).get("data") or {}
    reel = data.get("reel") or {}
    reviews = reel.get("reviews") or {}
    store = reel.get("store") or ""
    title = str(item.get("title") or "ASKODOX Pick")
    media = (f"<video src=\"{esc(str(data.get('url')))}\" controls playsinline preload=\"metadata\"></video>"
             if data.get("url") else
             (f"<img class=\"hero\" src=\"{esc(str(item.get('image_url')))}\" alt=\"\">" if item.get("image_url") else ""))
    price = ""
    try:
        if float(item.get("price") or 0) > 0:
            price = f"<div class=\"price\">₹{float(item['price']):,.0f}</div>"
    except (TypeError, ValueError):
        pass
    rating = ""
    if reviews.get("rating"):
        n = reviews.get("ratings_count")
        rating = (f"<p>⭐ <b>{esc(str(reviews['rating']))}/5</b> {esc(store)} రేటింగ్"
                  + (f" · {esc(str(n))} మంది" if n else "") + "</p>")
    points = "".join(f"<li class=\"ok\">{esc(p)}</li>" for p in reviews.get("good") or []) + \
        "".join(f"<li class=\"warn\">{esc(p)}</li>" for p in reviews.get("bad") or [])
    faq = "".join(f"<details><summary>{esc(f['q'])}</summary><p>{esc(f['a'])}</p></details>"
                  for f in reel.get("faq") or [] if isinstance(f, dict) and f.get("q"))
    store_label = f"{store} లో కొనండి" if store and store != "ASKODOX" else "ఇక్కడ కొనండి"
    body = (f"<div class=\"card\">{media}<h1>{esc(title)}</h1>{price}{rating}"
            f"<a class=\"btn buy\" href=\"/p/{int(item['id'])}/buy?from={esc(source)}\" rel=\"nofollow sponsored\">"
            f"🛒 {esc(store_label)}</a><a class=\"btn app\" href=\"{PLAY_URL}\">ASKODOX యాప్‌లో మరిన్ని చూడండి</a>"
            f"<span class=\"mut\">కొనుగోలు, డెలివరీ, రిటర్న్ అన్నీ స్టోర్‌లోనే.</span></div>")
    if item.get("description"):
        body += f"<div class=\"card\"><b>వివరాలు</b><p>{esc(str(item['description']))}</p></div>"
    if points:
        body += f"<div class=\"card\"><b>కొన్నవాళ్లు ఏమన్నారు</b><ul>{points}</ul></div>"
    if faq:
        body += f"<div class=\"card\"><b>ప్రశ్నలు – జవాబులు</b>{faq}</div>"
    body += "<p class=\"mut\" style=\"text-align:center\"><a href=\"/shop\">ASKODOX Picks అన్నీ చూడండి →</a></p>"
    return _page(title, body)


def shop_html(items: List[Dict[str, Any]]) -> str:
    esc = html.escape
    cards = "".join(
        f"<a href=\"/p/{int(i['id'])}\"><img src=\"{esc(str(i.get('image_url') or ''))}\" alt=\"\" loading=\"lazy\">"
        f"<div>{esc(str(i.get('title') or '')[:60])}"
        + (f"<br><b>₹{float(i['price']):,.0f}</b>" if _num(i.get("price")) else "") + "</div></a>"
        for i in items)
    body = ("<p><b>ASKODOX Picks</b><br><span class=\"mut\">మేము చూసి ఎంచుకున్న "
            "ప్రోడక్ట్స్. కొనుగోలు స్టోర్‌లోనే జరుగుతుంది.</span></p>"
            + (f"<div class=\"grid\">{cards}</div>" if cards else "<p class=\"mut\">త్వరలో వస్తాయి.</p>"))
    return _page("ASKODOX Picks", body)


def _num(value: Any) -> bool:
    try:
        return float(value) > 0
    except (TypeError, ValueError):
        return False
