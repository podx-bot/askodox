"""Follow a shop. Any signed-in person can follow a shop, shop owners included (they can follow other shops).

One row per (shop, person) in ``shop_follows``. Follower identities are never returned: a shop sees only a count.
A shop cannot be followed by its own owner. Following never sends anything by itself: the shop's posts reach the
people who follow it through the Updates feed (a later step).
"""

from __future__ import annotations

import base64
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List

from app.services.pos_store import PosError

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS shop_follows (business_id TEXT NOT NULL, app_user_id TEXT NOT NULL,"
    " created_at TEXT NOT NULL, PRIMARY KEY (business_id, app_user_id))",
    "CREATE INDEX IF NOT EXISTS shop_follows_user ON shop_follows (app_user_id, created_at)",
    # One branded picture per shop per day (the owner's), kept on the server so followers can open it later.
    "CREATE TABLE IF NOT EXISTS shop_posts (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, caption TEXT NOT NULL,"
    " day TEXT NOT NULL, created_at TEXT NOT NULL, image BLOB NOT NULL)",
    "CREATE INDEX IF NOT EXISTS shop_posts_business ON shop_posts (business_id, created_at)",
)
MAX_IMAGE_BYTES = 900_000
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
MAX_CAPTION = 300


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class ShopFollows:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    def _shop(self, conn: sqlite3.Connection, business_id: str) -> sqlite3.Row:
        row = conn.execute(
            "SELECT id, owner_user_id, name, address, template FROM pos_businesses WHERE id = ?",
            (business_id,)).fetchone()
        if row is None:
            raise PosError(404, "shop_not_found", "Shop not found.")
        return row

    def _state(self, conn: sqlite3.Connection, shop: sqlite3.Row, user: str) -> Dict[str, Any]:
        following = conn.execute(
            "SELECT 1 FROM shop_follows WHERE business_id = ? AND app_user_id = ?",
            (shop["id"], user)).fetchone() is not None
        followers = conn.execute(
            "SELECT COUNT(*) AS n FROM shop_follows WHERE business_id = ?", (shop["id"],)).fetchone()["n"]
        return {
            "business_id": shop["id"],
            "name": shop["name"],
            "address": shop["address"],
            "category": shop["template"],
            "followers": int(followers),
            "following": following,
            "is_owner": shop["owner_user_id"] == user,
        }

    def get(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            return self._state(conn, self._shop(conn, business_id), user)

    def follow(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            if shop["owner_user_id"] == user:
                raise PosError(409, "own_shop", "A shop cannot be followed by its own owner.")
            conn.execute(
                "INSERT OR IGNORE INTO shop_follows (business_id, app_user_id, created_at) VALUES (?, ?, ?)",
                (business_id, user, _now()))
            return self._state(conn, shop, user)

    def unfollow(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            conn.execute("DELETE FROM shop_follows WHERE business_id = ? AND app_user_id = ?", (business_id, user))
            return self._state(conn, shop, user)

    def my_follows(self, user: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT b.id, b.name, b.address, b.template, f.created_at FROM shop_follows f"
                " JOIN pos_businesses b ON b.id = f.business_id WHERE f.app_user_id = ?"
                " ORDER BY f.created_at DESC LIMIT 200", (user,)).fetchall()
        return [{"business_id": r["id"], "name": r["name"], "address": r["address"],
                 "category": r["template"], "followed_at": r["created_at"]} for r in rows]

    # ---- the owner's daily picture (the picture is made on the phone, with the shop name and ASKODOX brand burned in)

    def post(self, business_id: str, user: str, caption: str, image: bytes) -> Dict[str, Any]:
        caption = (caption or "").strip()
        if not caption or len(caption) > MAX_CAPTION:
            raise PosError(400, "caption", "Caption is required (up to 300 characters).")
        if not image.startswith(PNG_MAGIC) or len(image) > MAX_IMAGE_BYTES:
            raise PosError(400, "image", "Send a PNG picture up to 900 KB.")
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            if shop["owner_user_id"] != user:
                raise PosError(403, "not_owner", "Only the shop owner can post for this shop.")
            now = datetime.now(timezone.utc)
            day = now.strftime("%Y-%m-%d")
            if conn.execute("SELECT 1 FROM shop_posts WHERE business_id = ? AND day = ?",
                            (business_id, day)).fetchone():
                raise PosError(409, "already_posted_today", "This shop already posted today. Try tomorrow.")
            post_id = f"spost_{uuid.uuid4().hex[:20]}"
            conn.execute("INSERT INTO shop_posts (id, business_id, caption, day, created_at, image)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (post_id, business_id, caption, day, now.isoformat(),
                                                        sqlite3.Binary(image)))
            return {"id": post_id, "business_id": business_id, "caption": caption, "day": day,
                    "created_at": now.isoformat()}

    def feed(self, user: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Pictures from the shops this person follows, newest first (never the followers themselves).
        The picture comes as base64 so the app needs no second request (at most 10 at a time)."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT p.id, p.caption, p.created_at, p.image, b.id AS business_id, b.name FROM shop_posts p"
                " JOIN shop_follows f ON f.business_id = p.business_id AND f.app_user_id = ?"
                " JOIN pos_businesses b ON b.id = p.business_id"
                " ORDER BY p.created_at DESC LIMIT ?", (user, max(1, min(int(limit), 10)))).fetchall()
        return [{"id": r["id"], "caption": r["caption"], "created_at": r["created_at"],
                 "business_id": r["business_id"], "shop_name": r["name"],
                 "credit": f"Created by {r['name']} · ASKODOX",
                 "image_base64": base64.b64encode(bytes(r["image"])).decode("ascii")} for r in rows]

    def image(self, post_id: str, user: str) -> bytes:
        """The picture. Only the owner and people who follow the shop can open it."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT p.image, p.business_id, b.owner_user_id FROM shop_posts p"
                " JOIN pos_businesses b ON b.id = p.business_id WHERE p.id = ?", (post_id,)).fetchone()
            if row is None:
                raise PosError(404, "post_not_found", "Post not found.")
            allowed = row["owner_user_id"] == user or conn.execute(
                "SELECT 1 FROM shop_follows WHERE business_id = ? AND app_user_id = ?",
                (row["business_id"], user)).fetchone() is not None
            if not allowed:
                raise PosError(403, "not_follower", "Follow this shop to open its picture.")
            return bytes(row["image"])
