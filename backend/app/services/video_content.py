"""Real video content for the video journey.

Sources, in order of preference, all permitted and real:

* YouTube Data API v3 (only when an API key is configured: Command Center ->
  Integrations -> YouTube Data API, or YOUTUBE_API_KEY). Gives the channel,
  duration, whether embedding is allowed and YouTube's own "includes paid
  promotion" declaration.
* Web video search results already used by discovery (Brave video search in
  production): real title, URL, thumbnail, creator, duration.
* YouTube oEmbed (public, keyless) to confirm a YouTube video exists and may
  be embedded -- "in-app playback where supported" is decided by YouTube,
  not guessed.

Every web video shown gets a stable reference (``yt_<id>`` for YouTube,
``wv_<hash>`` otherwise) so Ask ASKODOX, the viewer and attribution events
all talk about the same video. Nothing here downloads or analyzes the
video itself: explanations are honest about only knowing the title,
description and channel.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional
from urllib.parse import urlparse

_YT = re.compile(r"(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})")

PLATFORM_HOSTS = {
    "youtube.com": "youtube", "youtu.be": "youtube", "m.youtube.com": "youtube",
    "instagram.com": "instagram", "facebook.com": "facebook", "fb.watch": "facebook",
    "dailymotion.com": "dailymotion", "vimeo.com": "vimeo", "x.com": "x", "twitter.com": "x",
    "sharechat.com": "sharechat", "mojapp.in": "moj", "joshapp.in": "josh",
}

WEB_DISCLOSURE = "Creator's opinion -- not verified by ASKODOX"
PAID_DISCLOSURE = "Includes paid promotion (declared on YouTube)"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def youtube_id(url: str) -> Optional[str]:
    match = _YT.search(str(url or ""))
    return match.group(1) if match else None


def platform_of(url: str) -> str:
    host = (urlparse(str(url or "")).hostname or "").lower().removeprefix("www.")
    for known, name in PLATFORM_HOSTS.items():
        if host == known or host.endswith("." + known):
            return name
    return "web"


def video_ref(url: str) -> str:
    yt = youtube_id(url)
    if yt:
        return f"yt_{yt}"
    return "wv_" + hashlib.sha256(str(url or "").strip().lower().encode()).hexdigest()[:16]


def youtube_embed(video_id: str) -> str:
    return f"https://www.youtube-nocookie.com/embed/{video_id}?playsinline=1&rel=0"


def _iso_duration(text: str) -> Optional[str]:
    """PT1H2M3S -> 1:02:03, PT8M12S -> 8:12."""
    match = re.fullmatch(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", str(text or ""))
    if not match:
        return None
    d, h, m, s = (int(x or 0) for x in match.groups())
    h += d * 24
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


class WebVideoStore:
    """Every real web video ASKODOX has shown, by stable reference."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute(
                """CREATE TABLE IF NOT EXISTS pf_web_videos (
                    ref TEXT PRIMARY KEY, url TEXT NOT NULL, platform TEXT NOT NULL, title TEXT NOT NULL,
                    snippet TEXT, creator TEXT, thumbnail TEXT, duration TEXT, source TEXT NOT NULL,
                    products_json TEXT NOT NULL DEFAULT '[]', services_json TEXT NOT NULL DEFAULT '[]',
                    category TEXT, embeddable INTEGER, paid_promotion INTEGER,
                    first_seen TEXT NOT NULL, last_seen TEXT NOT NULL
                )""")

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def save(self, item: Dict[str, Any]) -> None:
        now = now_iso()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO pf_web_videos (ref, url, platform, title, snippet, creator, thumbnail, duration, source, "
                "products_json, services_json, category, embeddable, paid_promotion, first_seen, last_seen) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(ref) DO UPDATE SET title=excluded.title, "
                "snippet=excluded.snippet, creator=excluded.creator, thumbnail=excluded.thumbnail, "
                "duration=excluded.duration, products_json=excluded.products_json, services_json="
                "excluded.services_json, category=excluded.category, embeddable=COALESCE(excluded.embeddable, "
                "pf_web_videos.embeddable), paid_promotion=COALESCE(excluded.paid_promotion, "
                "pf_web_videos.paid_promotion), last_seen=excluded.last_seen",
                (item["ref"], item["url"], item["platform"], item["title"][:300], (item.get("snippet") or "")[:2000],
                 item.get("creator"), item.get("thumbnail"), item.get("duration"), item.get("source") or "web",
                 json.dumps(item.get("products") or []), json.dumps(item.get("services") or []),
                 item.get("category"), None if item.get("embeddable") is None else int(bool(item["embeddable"])),
                 None if item.get("paid_promotion") is None else int(bool(item["paid_promotion"])), now, now))

    def get(self, ref: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM pf_web_videos WHERE ref=?", (str(ref)[:40],)).fetchone()
        if not row:
            return None
        item = dict(row)
        item["products"] = json.loads(item.pop("products_json") or "[]")
        item["services"] = json.loads(item.pop("services_json") or "[]")
        for key in ("embeddable", "paid_promotion"):
            item[key] = None if item[key] is None else bool(item[key])
        return item

    def recent(self, limit: int = 200) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            refs = [r["ref"] for r in conn.execute("SELECT ref FROM pf_web_videos ORDER BY last_seen DESC LIMIT ?",
                                                    (limit,)).fetchall()]
        return [v for v in (self.get(r) for r in refs) if v]


class YouTubeOEmbed:
    """Public, keyless YouTube oEmbed: 200 = exists and embeddable, 401/403 =
    embedding disabled by the owner, 404 = removed / private."""

    URL = "https://www.youtube.com/oembed"

    def __init__(self, fetch: Callable[[str, Dict[str, str]], tuple[int, Any]]) -> None:
        self.fetch = fetch

    def check(self, video_url: str) -> Dict[str, Any]:
        try:
            status, body = self.fetch(self.URL, {"url": video_url, "format": "json"})
        except Exception as error:  # network: unknown, never guessed
            return {"checked": False, "error": type(error).__name__}
        if status == 200 and isinstance(body, dict):
            return {"checked": True, "exists": True, "embeddable": True, "title": body.get("title"),
                    "author_name": body.get("author_name"), "thumbnail_url": body.get("thumbnail_url")}
        if status in (401, 403):
            return {"checked": True, "exists": True, "embeddable": False}
        if status == 404:
            return {"checked": True, "exists": False, "embeddable": False}
        return {"checked": False, "status": status}


class YouTubeDataSource:
    """YouTube Data API v3 search (needs an API key; unused without one)."""

    SEARCH = "https://www.googleapis.com/youtube/v3/search"
    VIDEOS = "https://www.googleapis.com/youtube/v3/videos"

    def __init__(self, api_key: str, fetch: Callable[[str, Dict[str, str]], tuple[int, Any]], *,
                 region: str = "IN") -> None:
        self.api_key = api_key
        self.fetch = fetch
        self.region = region

    def search(self, query: str, *, limit: int = 6, language: str = "") -> List[Dict[str, Any]]:
        if not self.api_key or not query.strip():
            return []
        params = {"part": "snippet", "type": "video", "q": query, "maxResults": str(max(1, min(limit, 15))),
                  "regionCode": self.region, "safeSearch": "moderate", "key": self.api_key}
        if language:
            params["relevanceLanguage"] = language
        status, body = self.fetch(self.SEARCH, params)
        if status != 200 or not isinstance(body, dict):
            raise RuntimeError(f"youtube search {status}")
        ids = [i["id"]["videoId"] for i in body.get("items") or [] if (i.get("id") or {}).get("videoId")]
        if not ids:
            return []
        status, details = self.fetch(self.VIDEOS, {"part": "snippet,contentDetails,status,paidProductPlacementDetails",
                                                   "id": ",".join(ids), "key": self.api_key})
        info = {v["id"]: v for v in (details or {}).get("items") or []} if status == 200 else {}
        rows = []
        for vid in ids:
            v = info.get(vid) or {}
            sn = v.get("snippet") or next((i["snippet"] for i in body["items"]
                                           if (i.get("id") or {}).get("videoId") == vid), {})
            thumbs = sn.get("thumbnails") or {}
            rows.append({
                "title": sn.get("title") or "", "url": f"https://www.youtube.com/watch?v={vid}",
                "snippet": sn.get("description") or "", "creator": sn.get("channelTitle"),
                "thumbnail": ((thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {})
                              .get("url")),
                "duration": _iso_duration((v.get("contentDetails") or {}).get("duration") or ""),
                "embeddable": (v.get("status") or {}).get("embeddable"),
                "paid_promotion": (v.get("paidProductPlacementDetails") or {}).get("hasPaidProductPlacement"),
                "source": "youtube_data",
            })
        return rows


def link_subject(demand: Dict[str, Any]) -> tuple[List[str], List[str]]:
    """What the video is about, from the customer's own need: products for
    buying needs, services for service needs."""
    from app.services.universal_multi_source_result_service import NEED_SERVICE, need_kind

    subject = str(demand.get("subject") or "").strip()
    if not subject:
        return [], []
    return ([], [subject]) if need_kind(demand) == NEED_SERVICE else ([subject], [])


def enrich_rows(rows: Iterable[Dict[str, Any]], demand: Dict[str, Any], *, store: WebVideoStore,
                oembed: Optional[YouTubeOEmbed] = None, category: str = "") -> List[Dict[str, Any]]:
    """Web video result rows -> trackable, linkable, honestly labelled rows."""
    rows = [r for r in rows if isinstance(r, dict) and r.get("destination_url")]
    products, services = link_subject(demand)
    checks: Dict[str, Dict[str, Any]] = {}
    if oembed is not None:
        urls = [r["destination_url"] for r in rows if youtube_id(r["destination_url"])
                and r.get("embeddable") is None]
        if urls:
            with ThreadPoolExecutor(max_workers=4) as pool:
                for url, result in zip(urls, pool.map(oembed.check, urls)):
                    checks[url] = result
    out = []
    for row in rows:
        url = row["destination_url"]
        ref = video_ref(url)
        yt = youtube_id(url)
        check = checks.get(url) or {}
        if check.get("checked") and check.get("exists") is False:
            continue  # removed / private on YouTube: never shown
        embeddable = row.get("embeddable")
        if embeddable is None and check.get("checked"):
            embeddable = check.get("embeddable")
        paid = row.get("paid_promotion")
        item = dict(row)
        item.update({
            "video_id": ref, "platform": platform_of(url),
            "embed_url": youtube_embed(yt) if yt and embeddable is not False else None,
            "embeddable": embeddable, "relationship": "creator",
            "sponsored": bool(paid), "sponsored_label": "Paid promotion" if paid else None,
            "disclosure": PAID_DISCLOSURE if paid else WEB_DISCLOSURE,
            "products": products, "services": services, "analyzed": False,
            "image_url": row.get("image_url") or check.get("thumbnail_url")
            or (f"https://i.ytimg.com/vi/{yt}/hqdefault.jpg" if yt else None),
            "source_name": row.get("source_name") or check.get("author_name"),
        })
        store.save({"ref": ref, "url": url, "platform": item["platform"], "title": str(item.get("title") or ""),
                    "snippet": item.get("subtitle") or item.get("snippet"), "creator": item.get("source_name"),
                    "thumbnail": item.get("image_url"), "duration": item.get("duration"),
                    "source": row.get("video_source") or "web_search", "products": products, "services": services,
                    "category": category, "embeddable": embeddable, "paid_promotion": paid})
        out.append(item)
    return out


def youtube_rows_as_results(rows: List[Dict[str, Any]], subject: str) -> List[Dict[str, Any]]:
    """YouTube Data rows in the discovery result shape (relevance-gated)."""
    from app.services.universal_external_result_service import relevant_to

    out = []
    for index, row in enumerate(rows):
        if not row.get("title") or not relevant_to(subject, row.get("title"), row.get("snippet")):
            continue
        out.append({
            "id": f"video-yt-{index}-{youtube_id(row['url'])}", "match_id": f"video-yt-{index}",
            "provider_id": "youtube.com", "title": str(row["title"])[:160], "subtitle": str(row.get("snippet") or "")[:280],
            "score": None, "match_source": "video", "source": "video", "destination_url": row["url"],
            "affiliate": False, "disclosure": "", "fallback": True, "demo": False, "page_type": "video",
            "image_url": row.get("thumbnail"), "source_name": row.get("creator"), "duration": row.get("duration"),
            "embeddable": row.get("embeddable"), "paid_promotion": row.get("paid_promotion"),
            "video_source": "youtube_data",
        })
    return out


def explain_web(video: Dict[str, Any], question: str, *, language: str = "en") -> Dict[str, Any]:
    """Honest Q&A basis for a web video: ASKODOX has not watched it; it only
    knows the title, the description the creator wrote and the channel."""
    te = language == "te"
    lines = [video["title"]]
    snippet = str(video.get("snippet") or "").strip()
    if snippet:
        sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+|\n+", snippet) if len(s.strip()) > 10][:4]
        lines += sentences
    subject = (video.get("services") or video.get("products") or [video["title"]])[0]
    service = bool(video.get("services"))
    actions = [("find_local", "దగ్గరలో కనుగొనండి" if te else "Find near me", f"{subject} near me"),
               ("deals", "డీల్స్ చూపించండి" if te else "Show deals", f"{subject} offers"),
               ("compare", "పోల్చండి" if te else "Compare", f"Compare {subject} with alternatives"),
               ("reviews", "రివ్యూలు" if te else "More reviews", f"{subject} reviews")]
    if service:
        service_ask = subject if str(subject).lower().rstrip().endswith("service") else f"{subject} service"
        actions.insert(1, ("local_service", "స్థానిక సేవ" if te else "Book a local service",
                           f"{service_ask} near me"))
    else:
        actions.insert(2, ("used", "వాడినది / తక్కువ ధర" if te else "Used / cheaper", f"used {subject}"))
    label = PAID_DISCLOSURE if video.get("paid_promotion") else WEB_DISCLOSURE
    return {
        "video_id": video["ref"], "analyzed": False,
        "answer": ("ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు."
                   if te else "I haven't watched or analyzed this video. I only know its title, the description "
                              "the creator wrote and the channel."),
        "from_source": lines, "relationship": "creator", "relationship_label": label,
        "creator": video.get("creator"), "platform": video.get("platform"), "url": video.get("url"),
        "question": question[:300], "next": [{"action": a, "label": lab, "ask": ask} for a, lab, ask in actions],
    }
