"""Follow a shop. Any signed-in person can follow a shop, shop owners included (they can follow other shops).

One row per (shop, person) in ``shop_follows``. Follower identities are never returned: a shop sees only a count.
A shop cannot be followed by its own owner. Following never sends anything by itself: the shop's posts reach the
people who follow it through the Updates feed (a later step).
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List

from app.services.pos_store import PosError

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS shop_follows (business_id TEXT NOT NULL, app_user_id TEXT NOT NULL,"
    " created_at TEXT NOT NULL, PRIMARY KEY (business_id, app_user_id))",
    "CREATE INDEX IF NOT EXISTS shop_follows_user ON shop_follows (app_user_id, created_at)",
)


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
