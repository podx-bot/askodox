"""The ONE stored profile of an app user (name, photo, address, language,
roles and -- for sellers / service providers -- business details).

The mobile number is never stored from client input: it is derived from the
signed session identity (``app-phone-91XXXXXXXXXX``). Verification status is
read from the seller profile / catalog, never set by the user.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Dict, Optional

EDITABLE = (
    "name", "address", "latitude", "longitude", "language", "roles",
    "business_name", "business_address", "business_category", "gstin", "upi_id",
)


class UserProfileRepository:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with closing(self._connect()) as conn:
            conn.execute(
                """CREATE TABLE IF NOT EXISTS user_profiles (
                    user_id TEXT PRIMARY KEY, name TEXT, address TEXT, latitude REAL, longitude REAL,
                    language TEXT, roles_json TEXT, business_name TEXT, business_address TEXT,
                    business_category TEXT, gstin TEXT, photo_jpeg BLOB, photo_updated_at TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL)"""
            )
            columns = {row[1] for row in conn.execute("PRAGMA table_info(user_profiles)")}
            if "upi_id" not in columns:  # the seller's own UPI ID (VPA) for direct payments
                conn.execute("ALTER TABLE user_profiles ADD COLUMN upi_id TEXT")
            conn.commit()

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def mobile_for(user_id: str) -> Optional[str]:
        digits = "".join(ch for ch in str(user_id or "") if ch.isdigit())
        if len(digits) < 10:
            return None
        return f"+{digits}" if len(digits) > 10 else f"+91{digits}"

    def get(self, user_id: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM user_profiles WHERE user_id=?", (user_id,)).fetchone()
        data: Dict[str, Any] = {k: None for k in EDITABLE}
        data["roles"] = []
        data["has_photo"] = False
        data["photo_updated_at"] = None
        if row:
            for key in EDITABLE:
                if key == "roles":
                    try:
                        data["roles"] = [str(r) for r in json.loads(row["roles_json"] or "[]")][:20]
                    except (TypeError, ValueError):
                        data["roles"] = []
                else:
                    data[key] = row[key]
            data["has_photo"] = row["photo_jpeg"] is not None
            data["photo_updated_at"] = row["photo_updated_at"]
        data["user_id"] = user_id
        data["mobile"] = self.mobile_for(user_id)
        return data

    def update(self, user_id: str, fields: Dict[str, Any]) -> Dict[str, Any]:
        values = {k: v for k, v in fields.items() if k in EDITABLE}
        now = self._now()
        with closing(self._connect()) as conn:
            conn.execute(
                "INSERT OR IGNORE INTO user_profiles(user_id, created_at, updated_at) VALUES(?,?,?)",
                (user_id, now, now),
            )
            for key, value in values.items():
                column = "roles_json" if key == "roles" else key
                stored = json.dumps(list(value or [])) if key == "roles" else value
                conn.execute(f'UPDATE user_profiles SET "{column}"=?, updated_at=? WHERE user_id=?',
                             (stored, now, user_id))
            conn.commit()
        return self.get(user_id)

    def set_photo(self, user_id: str, jpeg: bytes | None) -> Dict[str, Any]:
        now = self._now()
        with closing(self._connect()) as conn:
            conn.execute(
                "INSERT OR IGNORE INTO user_profiles(user_id, created_at, updated_at) VALUES(?,?,?)",
                (user_id, now, now),
            )
            conn.execute("UPDATE user_profiles SET photo_jpeg=?, photo_updated_at=?, updated_at=? WHERE user_id=?",
                         (jpeg, now if jpeg else None, now, user_id))
            conn.commit()
        return self.get(user_id)

    def photo(self, user_id: str) -> Optional[bytes]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT photo_jpeg FROM user_profiles WHERE user_id=?", (user_id,)).fetchone()
        return bytes(row["photo_jpeg"]) if row and row["photo_jpeg"] is not None else None

    def delete(self, user_id: str) -> None:
        with closing(self._connect()) as conn:
            conn.execute("DELETE FROM user_profiles WHERE user_id=?", (user_id,))
            conn.commit()
