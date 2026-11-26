"""ASKODOX's OWN YouTube channel (owner 2026-11-26): a publisher connects the channel once with Google sign-in
(scopes youtube.upload + youtube.readonly), then a PUBLISHED Studio video goes to that channel in one tap.

* ONE channel for the whole platform (row id 1). No customer's / shop's YouTube account is ever connected.
* The refresh token is kept encrypted (``secret_box``; fails closed without ASKODOX_SECRETS_KEY) and is never
  returned by any API or written to a log. Access tokens live only inside one call.
* A connect link is one-time: made by a signed-in publisher, good for 10 minutes, used once.
* Uploads are remembered by ``ref`` (``studio:<purchase id>``) so a second tap never uploads the same video twice.
* Deployment values via ``commerce_finance.env_value`` (provider ``youtube_oauth``): YOUTUBE_OAUTH_CLIENT_ID,
  YOUTUBE_OAUTH_CLIENT_SECRET, optional YOUTUBE_OAUTH_REDIRECT_URI.

Google rule to remember: until the Cloud project passes YouTube's API audit, videos it uploads are locked PRIVATE
by YouTube whatever privacy is asked. The default asked privacy is therefore ``private``.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import secrets
import sqlite3
from typing import Any, Callable, Dict, Optional
from urllib.parse import urlencode

import httpx

from app.services import commerce_finance as cf
from app.services.secret_box import SecretBox

SCOPES = ("https://www.googleapis.com/auth/youtube.upload", "https://www.googleapis.com/auth/youtube.readonly")
DEFAULT_REDIRECT_URI = "https://admin.askodox.com/youtube/oauth/callback"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
REVOKE_URL = "https://oauth2.googleapis.com/revoke"
CHANNELS_URL = "https://www.googleapis.com/youtube/v3/channels"
UPLOAD_URL = "https://www.googleapis.com/upload/youtube/v3/videos"
STATE_MINUTES = 10
PRIVACY = ("private", "unlisted", "public")
MAX_TITLE, MAX_DESCRIPTION = 100, 4900


class YouTubeError(Exception):
    """A message that is safe to show staff (never a token or Google's raw body)."""


def _env(env: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    return dict(os.environ) if env is None else env


def client_id(env: Optional[Dict[str, str]] = None) -> str:
    return cf.env_value(_env(env), "youtube_oauth", "client_id")


def client_secret(env: Optional[Dict[str, str]] = None) -> str:
    return cf.env_value(_env(env), "youtube_oauth", "client_secret")


def redirect_uri(env: Optional[Dict[str, str]] = None) -> str:
    return cf.env_value(_env(env), "youtube_oauth", "redirect_uri") or DEFAULT_REDIRECT_URI


def configured(env: Optional[Dict[str, str]] = None) -> bool:
    return bool(client_id(env) and client_secret(env))


def auth_url(state: str, env: Optional[Dict[str, str]] = None) -> str:
    """Google's consent page. ``access_type=offline`` + ``prompt=consent`` so a refresh token always comes back."""
    return AUTH_URL + "?" + urlencode({
        "client_id": client_id(env), "redirect_uri": redirect_uri(env), "response_type": "code",
        "scope": " ".join(SCOPES), "access_type": "offline", "prompt": "consent",
        "include_granted_scopes": "false", "state": state})


def clean_text(value: Any, limit: int) -> str:
    """YouTube refuses '<' and '>' in titles / descriptions."""
    return str(value or "").replace("<", "").replace(">", "").strip()[:limit]


# ------------------------------------------------------------ Google calls --
def exchange_code(code: str, env: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    with httpx.Client(timeout=20) as client:
        response = client.post(TOKEN_URL, data={
            "code": code, "client_id": client_id(env), "client_secret": client_secret(env),
            "redirect_uri": redirect_uri(env), "grant_type": "authorization_code"})
    if response.status_code != 200:
        raise YouTubeError("Google ఈ sign-in ని ఒప్పుకోలేదు. మళ్లీ ప్రయత్నించండి.")
    return dict(response.json())


def access_token(refresh_token: str, env: Optional[Dict[str, str]] = None) -> str:
    with httpx.Client(timeout=20) as client:
        response = client.post(TOKEN_URL, data={
            "refresh_token": refresh_token, "client_id": client_id(env), "client_secret": client_secret(env),
            "grant_type": "refresh_token"})
    if response.status_code != 200:
        raise YouTubeError("YouTube connection గడువు అయిపోయింది. మళ్లీ Connect చేయండి.")
    return str(response.json().get("access_token") or "")


def channel_of(token: str) -> Dict[str, str]:
    with httpx.Client(timeout=20) as client:
        response = client.get(CHANNELS_URL, params={"part": "snippet", "mine": "true"},
                              headers={"Authorization": f"Bearer {token}"})
    if response.status_code != 200:
        raise YouTubeError("YouTube channel చదవలేకపోయాం.")
    items = list(response.json().get("items") or [])
    if not items:
        raise YouTubeError("ఈ Google account లో YouTube channel లేదు.")
    return {"id": str(items[0].get("id") or ""), "title": str((items[0].get("snippet") or {}).get("title") or "")}


def revoke(refresh_token: str) -> None:
    try:
        with httpx.Client(timeout=10) as client:
            client.post(REVOKE_URL, data={"token": refresh_token})
    except httpx.HTTPError:
        pass  # the row is deleted either way


def upload_file(token: str, path: str, *, title: str, description: str, privacy: str = "private") -> str:
    """Resumable upload of one file; returns the new video id."""
    if privacy not in PRIVACY:
        raise YouTubeError("Privacy: " + " / ".join(PRIVACY))
    size = os.path.getsize(path)
    meta = {"snippet": {"title": clean_text(title, MAX_TITLE) or "ASKODOX",
                        "description": clean_text(description, MAX_DESCRIPTION), "categoryId": "22"},
            "status": {"privacyStatus": privacy, "selfDeclaredMadeForKids": False}}
    with httpx.Client(timeout=httpx.Timeout(300, connect=20)) as client:
        start = client.post(UPLOAD_URL, params={"uploadType": "resumable", "part": "snippet,status"},
                            headers={"Authorization": f"Bearer {token}", "X-Upload-Content-Type": "video/mp4",
                                     "X-Upload-Content-Length": str(size),
                                     "Content-Type": "application/json; charset=UTF-8"},
                            content=json.dumps(meta).encode("utf-8"))
        target = start.headers.get("location", "")
        if start.status_code != 200 or not target:
            raise YouTubeError(_reason(start))
        with open(path, "rb") as handle:
            done = client.put(target, content=handle.read(),
                              headers={"Content-Type": "video/mp4", "Content-Length": str(size)})
    if done.status_code not in (200, 201):
        raise YouTubeError(_reason(done))
    video_id = str(done.json().get("id") or "")
    if not video_id:
        raise YouTubeError("YouTube video id ఇవ్వలేదు.")
    return video_id


def _reason(response: httpx.Response) -> str:
    """Google's own reason word only (quotaExceeded, uploadLimitExceeded, forbidden ...), never the body."""
    reason = ""
    try:
        errors = (response.json().get("error") or {}).get("errors") or []
        reason = str(errors[0].get("reason") or "") if errors else ""
    except Exception:
        reason = ""
    reason = "".join(ch for ch in reason if ch.isalnum())[:40]
    return f"YouTube upload కాలేదు (HTTP {response.status_code}{' ' + reason if reason else ''})."


# ------------------------------------------------------------------ store --
class YouTubeChannelStore:
    def __init__(self, db_path: str, box: SecretBox, *,
                 clock: Callable[[], dt.datetime] | None = None) -> None:
        self.db_path, self.box = db_path, box
        self._clock = clock or (lambda: dt.datetime.now(dt.timezone.utc))
        with self._connect() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS youtube_channel(
                    id INTEGER PRIMARY KEY CHECK (id = 1), channel_id TEXT NOT NULL, channel_title TEXT NOT NULL,
                    refresh_token TEXT NOT NULL, connected_by TEXT NOT NULL, connected_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS youtube_oauth_states(
                    state TEXT PRIMARY KEY, actor TEXT NOT NULL, created_at TEXT NOT NULL, used_at TEXT NOT NULL DEFAULT '');
                CREATE TABLE IF NOT EXISTS youtube_uploads(
                    ref TEXT PRIMARY KEY, video_id TEXT NOT NULL, privacy TEXT NOT NULL, actor TEXT NOT NULL,
                    created_at TEXT NOT NULL);
            """)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    def now(self) -> str:
        return self._clock().astimezone(dt.timezone.utc).isoformat(timespec="seconds")

    # one-time connect link ------------------------------------------------
    def new_state(self, actor: str) -> str:
        state = secrets.token_urlsafe(32)
        cutoff = (self._clock() - dt.timedelta(days=1)).astimezone(dt.timezone.utc).isoformat(timespec="seconds")
        with self._connect() as conn:
            conn.execute("DELETE FROM youtube_oauth_states WHERE created_at < ?", (cutoff,))
            conn.execute("INSERT INTO youtube_oauth_states(state,actor,created_at) VALUES(?,?,?)",
                         (state, str(actor), self.now()))
        return state

    def _fresh(self, row: Optional[sqlite3.Row]) -> bool:
        if row is None or row["used_at"]:
            return False
        made = dt.datetime.fromisoformat(row["created_at"])
        return self._clock() - made <= dt.timedelta(minutes=STATE_MINUTES)

    def state_open(self, state: str) -> bool:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM youtube_oauth_states WHERE state=?", (str(state),)).fetchone()
        return self._fresh(row)

    def take_state(self, state: str) -> str:
        """The actor of a fresh, unused state -- and it is used up. '' otherwise."""
        with self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT * FROM youtube_oauth_states WHERE state=?", (str(state),)).fetchone()
            if not self._fresh(row):
                return ""
            conn.execute("UPDATE youtube_oauth_states SET used_at=? WHERE state=?", (self.now(), str(state)))
            return str(row["actor"])

    # the channel ------------------------------------------------------------
    def save(self, channel: Dict[str, str], refresh_token: str, *, actor: str) -> None:
        stored = self.box.encrypt(refresh_token)  # raises without ASKODOX_SECRETS_KEY (fail closed)
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO youtube_channel(id,channel_id,channel_title,refresh_token,"
                         "connected_by,connected_at) VALUES(1,?,?,?,?,?)",
                         (channel["id"], channel["title"][:120], stored, str(actor), self.now()))

    def _row(self) -> Optional[sqlite3.Row]:
        with self._connect() as conn:
            return conn.execute("SELECT * FROM youtube_channel WHERE id=1").fetchone()

    def refresh_token(self) -> str:
        row = self._row()
        return self.box.decrypt(row["refresh_token"]) if row else ""

    def disconnect(self) -> str:
        """Removes the channel row; returns the refresh token so the caller can revoke it at Google."""
        token = self.refresh_token()
        with self._connect() as conn:
            conn.execute("DELETE FROM youtube_channel WHERE id=1")
        return token

    def status(self) -> Dict[str, Any]:
        """What staff may see. Never the token."""
        row = self._row()
        with self._connect() as conn:
            uploads = conn.execute("SELECT ref,video_id,privacy,created_at FROM youtube_uploads "
                                   "ORDER BY created_at DESC LIMIT 20").fetchall()
        return {"configured": configured(), "can_store": self.box.configured, "connected": bool(row),
                "channel_id": row["channel_id"] if row else "", "channel_title": row["channel_title"] if row else "",
                "connected_at": row["connected_at"] if row else "",
                "uploads": [{**dict(u), "url": video_url(u["video_id"])} for u in uploads]}

    # uploads ------------------------------------------------------------------
    def uploaded(self, ref: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM youtube_uploads WHERE ref=?", (str(ref),)).fetchone()
        return {**dict(row), "url": video_url(row["video_id"])} if row else None

    def record_upload(self, ref: str, video_id: str, privacy: str, *, actor: str) -> Dict[str, Any]:
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO youtube_uploads(ref,video_id,privacy,actor,created_at) "
                         "VALUES(?,?,?,?,?)", (str(ref), video_id, privacy, str(actor), self.now()))
        return self.uploaded(ref)  # type: ignore[return-value]


def video_url(video_id: str) -> str:
    return f"https://www.youtube.com/watch?v={video_id}"
