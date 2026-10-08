"""My Business -> My Creations: posts, descriptions, offer text, catalogue
text, poster text and reel scripts the owner drafts (optionally with AI) and
keeps. Truth rules:

* AI writes only from the facts the owner gives; it never invents prices,
  discounts, certifications or claims -- a missing fact stays a [placeholder].
* Drafts are never published anywhere automatically; sharing is the owner's
  own action through the phone's share sheet.
* Image generation: NOT_AVAILABLE until an image provider is chosen and its
  cost approved (no provider / credentials are configured).
* Video: upload only (Native video). ASKODOX does not generate video.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import closing
from typing import Any

KINDS = {
    "post": "a short social media post",
    "description": "a product or service description for a listing",
    "offer_text": "the text of a promotion / offer announcement",
    "catalogue_text": "a short catalogue entry",
    "poster_text": "the words for a poster (headline, 2-3 lines, call to action)",
    "reel_script": "a 20-30 second reel / short video script (scenes + spoken lines)",
}
STATUSES = ("draft", "saved")


def capabilities(ai_ready: bool) -> dict[str, Any]:
    return {
        "text_drafts": {"status": "READY" if ai_ready else "NOT_AVAILABLE",
                        "reason": "AI writes from your facts only" if ai_ready else "no AI model is configured"},
        "image_generation": {"status": "NOT_AVAILABLE",
                             "reason": "No image-generation provider is configured. It needs a provider choice and "
                                       "an approved cost before it can be switched on."},
        "image_editing": {"status": "NOT_AVAILABLE", "reason": "needs the same image provider"},
        "video_generation": {"status": "NOT_AVAILABLE",
                             "reason": "ASKODOX does not generate video. Upload your own video instead."},
        "video_upload": {"status": "READY", "route": "/videos/native"},
        "publish_external": {"status": "MANUAL_ONLY",
                             "reason": "Share with the phone's share sheet; nothing is posted automatically."},
    }


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS business_creations (
        id INTEGER PRIMARY KEY AUTOINCREMENT, owner_user_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT,
        body TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, created_at REAL NOT NULL,
        updated_at REAL NOT NULL)""")
    return conn


def items(db_path: str, owner: str) -> list[dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        return [dict(r) for r in conn.execute(
            "SELECT * FROM business_creations WHERE owner_user_id=? ORDER BY updated_at DESC LIMIT 200",
            (owner,)).fetchall()]


def get(db_path: str, owner: str, item_id: int) -> dict[str, Any] | None:
    with closing(_connect(db_path)) as conn:
        r = conn.execute("SELECT * FROM business_creations WHERE id=? AND owner_user_id=?",
                         (item_id, owner)).fetchone()
    return dict(r) if r else None


def create(db_path: str, owner: str, *, kind: str, body: str, title: str = "", source: str = "owner",
           status: str = "draft") -> dict[str, Any]:
    if kind not in KINDS:
        raise ValueError("unknown kind")
    if status not in STATUSES:
        raise ValueError("status must be draft or saved")
    now = time.time()
    with closing(_connect(db_path)) as conn:
        cur = conn.execute("INSERT INTO business_creations(owner_user_id, kind, title, body, source, status, "
                           "created_at, updated_at) VALUES(?,?,?,?,?,?,?,?)",
                           (owner, kind, title[:120], body[:6000], source, status, now, now))
        conn.commit()
    return get(db_path, owner, int(cur.lastrowid))


def update(db_path: str, owner: str, item_id: int, **fields: Any) -> dict[str, Any] | None:
    allowed = {k: v for k, v in fields.items() if k in ("title", "body", "status") and v is not None}
    if "status" in allowed and allowed["status"] not in STATUSES:
        raise ValueError("status must be draft or saved")
    if not allowed:
        return get(db_path, owner, item_id)
    allowed["updated_at"] = time.time()
    with closing(_connect(db_path)) as conn:
        n = conn.execute(f"UPDATE business_creations SET {', '.join(f'{k}=?' for k in allowed)} "
                         "WHERE id=? AND owner_user_id=?", [*allowed.values(), item_id, owner]).rowcount
        conn.commit()
    return get(db_path, owner, item_id) if n else None


def delete(db_path: str, owner: str, item_id: int) -> bool:
    with closing(_connect(db_path)) as conn:
        n = conn.execute("DELETE FROM business_creations WHERE id=? AND owner_user_id=?", (item_id, owner)).rowcount
        conn.commit()
    return bool(n)


def draft_prompt(kind: str, about: str, language: str) -> str:
    lang = {"te": "Telugu", "hi": "Hindi"}.get(language, "English")
    return (
        f"Write {KINDS[kind]} for a small local business in India, in {lang}.\n"
        "Use ONLY the facts below. Never invent prices, discounts, offers, certifications, awards, ratings, "
        "delivery promises or contact details. If an important fact is missing, write it as a [placeholder] in "
        "square brackets instead of guessing. Plain text, no markdown headings; keep it short and natural.\n"
        f"Facts from the owner: {about}"
    )
