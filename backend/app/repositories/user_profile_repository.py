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
    "email", "active_role", "links", "role_details",
)
# Stored as JSON text (column name -> python type).
JSON_FIELDS = {"roles": ("roles_json", list), "links": ("links_json", list), "role_details": ("role_details_json", dict)}

# Universal Master Profile: the fields each role adds to the SAME profile.
# New roles are new keys here (stored in role_details_json) -- no schema change.
ROLE_FIELDS: Dict[str, tuple] = {
    "buyer": (),
    "service_seeker": (),
    "seller": ("business_type", "description", "service_area_km", "working_hours", "catalog_note",
               "business_document"),
    "service_provider": ("services", "categories", "service_area_km", "availability", "pricing",
                         "experience", "certification"),
    "job_seeker": ("skills", "experience", "preferred_locations", "availability", "expected_pay"),
    "delivery_partner": ("service_types", "availability", "operating_area", "vehicle_type", "vehicle_number",
                         "licence_document"),
    "survey_taker": ("interests", "availability"),
}


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
            for column in ("email", "active_role", "links_json", "role_details_json"):
                if column not in columns:
                    conn.execute(f"ALTER TABLE user_profiles ADD COLUMN {column} TEXT")
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
        data["links"] = []
        data["role_details"] = {}
        data["has_photo"] = False
        data["photo_updated_at"] = None
        if row:
            for key in EDITABLE:
                if key in JSON_FIELDS:
                    column, kind = JSON_FIELDS[key]
                    try:
                        value = json.loads(row[column] or ("[]" if kind is list else "{}"))
                    except (TypeError, ValueError):
                        value = None
                    data[key] = value if isinstance(value, kind) else kind()
                    if key == "roles":
                        data[key] = [str(r) for r in data[key]][:20]
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
                if key in JSON_FIELDS:
                    column, kind = JSON_FIELDS[key]
                    stored = json.dumps(kind(value or kind()))
                else:
                    column, stored = key, value
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
