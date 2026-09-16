"""Per-seller-account profile: tier classification and listing history.

Added 2026-09-16 (round 12) -- roadmap Phase 2 ("Seller tiers & verification
foundation": https://claude.ai/artifact/TWUnjbA2TTubwczT9Lxg4n). Before this,
ASKODOX had no table keyed by seller_user_id at all: gstin/pan/
id_verification_status (see product_catalog_repository.py) live per
*listing*, not per seller, and driver_kyc_repository.py's DRAFT/SUBMITTED/
APPROVED/REJECTED state machine is specific to driver/vehicle KYC. This is
the first real per-seller-account record.

Deliberately mirrors the schema-evolution style already used elsewhere in
this codebase (ProductCatalogRepository, DriverKYCRepository): CREATE TABLE
IF NOT EXISTS now, plus guarded ALTER TABLE for any columns added later,
since CREATE TABLE IF NOT EXISTS never alters an already-existing table on
Railway's persistent volume.
"""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from app.services.seller_tiers import compute_tier


class SellerProfileRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

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
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def get(self, seller_user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM seller_profiles WHERE seller_user_id=?",
                (str(seller_user_id or "").strip(),),
            ).fetchone()
        return dict(row) if row else None

    def record_listing_created(self, seller_user_id: str, *, has_gstin: bool = False) -> Dict[str, Any]:
        """Update (or create) a seller's profile after they publish a listing.

        total_listing_count counts every successful self-service listing
        creation, not just currently-active ones -- see the round-12
        tracker entry: a seller who later deactivates a listing has still
        genuinely demonstrated the activity level that earned their tier,
        so tier is not walked back on deactivation. has_gstin is sticky
        once true: a seller who supplies a GSTIN on any one listing is
        treated as a verified business from then on, even if a later
        listing omits it.
        """
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
            new_count = existing_count + 1
            new_has_gstin = existing_has_gstin or bool(has_gstin)
            new_tier = compute_tier(new_count, new_has_gstin)
            if row:
                conn.execute(
                    "UPDATE seller_profiles SET tier=?, total_listing_count=?, has_gstin=?, updated_at=? WHERE seller_user_id=?",
                    (new_tier, new_count, 1 if new_has_gstin else 0, now, seller),
                )
            else:
                conn.execute(
                    "INSERT INTO seller_profiles(seller_user_id, tier, total_listing_count, has_gstin, created_at, updated_at) VALUES(?,?,?,?,?,?)",
                    (seller, new_tier, new_count, 1 if new_has_gstin else 0, now, now),
                )
        return {
            "seller_user_id": seller,
            "tier": new_tier,
            "total_listing_count": new_count,
            "has_gstin": new_has_gstin,
        }
