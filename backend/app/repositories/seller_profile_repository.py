"""Per-seller-account profile, tier classification, and catalog backfill."""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from app.services.seller_tiers import compute_tier


class SellerProfileRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()
        self.backfill_from_catalog()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS seller_profiles (
                    seller_user_id TEXT PRIMARY KEY,
                    tier TEXT NOT NULL DEFAULT 'casual',
                    total_listing_count INTEGER NOT NULL DEFAULT 0,
                    has_gstin INTEGER NOT NULL DEFAULT 0,
                    is_service_provider INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            try:
                conn.execute(
                    "ALTER TABLE seller_profiles ADD COLUMN "
                    "is_service_provider INTEGER NOT NULL DEFAULT 0"
                )
            except sqlite3.OperationalError:
                pass

    def get(self, seller_user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM seller_profiles WHERE seller_user_id=?",
                (str(seller_user_id or "").strip(),),
            ).fetchone()
        return dict(row) if row else None

    def record_listing_created(
        self,
        seller_user_id: str,
        *,
        has_gstin: bool = False,
        is_service_provider: bool = False,
    ) -> Dict[str, Any]:
        seller = str(seller_user_id or "").strip()
        if not seller:
            raise ValueError("seller_user_id required")
        now = self._now()
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM seller_profiles WHERE seller_user_id=?",
                (seller,),
            ).fetchone()
            existing_count = int(row["total_listing_count"]) if row else 0
            existing_has_gstin = bool(row["has_gstin"]) if row else False
            existing_service = bool(row["is_service_provider"]) if row else False
            new_count = existing_count + 1
            new_has_gstin = existing_has_gstin or bool(has_gstin)
            new_service = existing_service or bool(is_service_provider)
            new_tier = compute_tier(new_count, new_has_gstin, new_service)
            if row:
                conn.execute(
                    """UPDATE seller_profiles
                       SET tier=?, total_listing_count=?, has_gstin=?,
                           is_service_provider=?, updated_at=?
                       WHERE seller_user_id=?""",
                    (
                        new_tier,
                        new_count,
                        1 if new_has_gstin else 0,
                        1 if new_service else 0,
                        now,
                        seller,
                    ),
                )
            else:
                conn.execute(
                    """INSERT INTO seller_profiles(
                           seller_user_id,tier,total_listing_count,has_gstin,
                           is_service_provider,created_at,updated_at
                       ) VALUES(?,?,?,?,?,?,?)""",
                    (
                        seller,
                        new_tier,
                        new_count,
                        1 if new_has_gstin else 0,
                        1 if new_service else 0,
                        now,
                        now,
                    ),
                )
        return {
            "seller_user_id": seller,
            "tier": new_tier,
            "total_listing_count": new_count,
            "has_gstin": new_has_gstin,
            "is_service_provider": new_service,
        }

    def backfill_from_catalog(self) -> int:
        """Create/update profiles for listings that pre-date seller profiles.

        ProductCatalogRepository is initialized first in the application
        container, so seller_products is available in normal startup. Tests
        that instantiate this repository alone simply have nothing to backfill.
        Existing profile counts are never reduced.
        """
        now = self._now()
        with self._connect() as conn:
            table = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='seller_products'"
            ).fetchone()
            if not table:
                return 0
            rows = conn.execute(
                """SELECT seller_user_id,
                          COUNT(*) AS listing_count,
                          MAX(CASE WHEN TRIM(COALESCE(gstin,'')) <> '' THEN 1 ELSE 0 END) AS has_gstin,
                          MAX(CASE WHEN TRIM(COALESCE(service_area,'')) <> ''
                                        OR TRIM(COALESCE(working_hours,'')) <> ''
                                        OR lower(TRIM(COALESCE(category_tag,''))) LIKE '%service%'
                                   THEN 1 ELSE 0 END) AS is_service_provider
                   FROM seller_products
                   WHERE TRIM(COALESCE(seller_user_id,'')) <> ''
                   GROUP BY seller_user_id"""
            ).fetchall()
            changed = 0
            for item in rows:
                seller = str(item["seller_user_id"]).strip()
                catalog_count = int(item["listing_count"] or 0)
                catalog_gstin = bool(item["has_gstin"])
                catalog_service = bool(item["is_service_provider"])
                current = conn.execute(
                    "SELECT * FROM seller_profiles WHERE seller_user_id=?",
                    (seller,),
                ).fetchone()
                count = max(catalog_count, int(current["total_listing_count"]) if current else 0)
                has_gstin = catalog_gstin or (bool(current["has_gstin"]) if current else False)
                is_service = catalog_service or (
                    bool(current["is_service_provider"]) if current else False
                )
                tier = compute_tier(count, has_gstin, is_service)
                if current:
                    desired = (tier, count, int(has_gstin), int(is_service))
                    actual = (
                        current["tier"],
                        int(current["total_listing_count"]),
                        int(current["has_gstin"]),
                        int(current["is_service_provider"]),
                    )
                    if desired == actual:
                        continue
                    conn.execute(
                        """UPDATE seller_profiles
                           SET tier=?, total_listing_count=?, has_gstin=?,
                               is_service_provider=?, updated_at=?
                           WHERE seller_user_id=?""",
                        (*desired, now, seller),
                    )
                else:
                    conn.execute(
                        """INSERT INTO seller_profiles(
                               seller_user_id,tier,total_listing_count,has_gstin,
                               is_service_provider,created_at,updated_at
                           ) VALUES(?,?,?,?,?,?,?)""",
                        (
                            seller,
                            tier,
                            count,
                            int(has_gstin),
                            int(is_service),
                            now,
                            now,
                        ),
                    )
                changed += 1
        return changed
