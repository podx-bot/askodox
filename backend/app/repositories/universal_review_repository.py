from __future__ import annotations

import sqlite3
from datetime import datetime, timezone


class UniversalReviewRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """CREATE TABLE IF NOT EXISTS universal_reviews(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    request_id INTEGER NOT NULL,
                    reviewer_user_id TEXT NOT NULL,
                    reviewed_user_id TEXT NOT NULL,
                    category TEXT,
                    rating INTEGER NOT NULL,
                    review_text TEXT,
                    created_at TEXT NOT NULL,
                    UNIQUE(request_id, reviewer_user_id, reviewed_user_id)
                )"""
            )

    def create(self, request_id, reviewer_user_id, reviewed_user_id, category, rating, review_text):
        rating = int(rating)
        if rating < 1 or rating > 5:
            raise ValueError("rating must be between 1 and 5")
        now = datetime.now(timezone.utc).isoformat()
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute(
                    """INSERT INTO universal_reviews(
                        request_id,reviewer_user_id,reviewed_user_id,category,rating,review_text,created_at
                    ) VALUES(?,?,?,?,?,?,?)""",
                    (int(request_id), str(reviewer_user_id), str(reviewed_user_id), str(category or "GENERAL"), rating, str(review_text or "").strip()[:2000], now),
                )
                return {"id": cursor.lastrowid, "status": "RECORDED"}
        except sqlite3.IntegrityError:
            return {"status": "ALREADY_REVIEWED"}

    def list_for_request(self, request_id):
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            return [dict(row) for row in conn.execute("SELECT * FROM universal_reviews WHERE request_id=? ORDER BY id", (int(request_id),))]

    def summary_for_user(self, reviewed_user_id):
        """Average rating + count across completed deals, for match cards."""
        with sqlite3.connect(self.db_path) as conn:
            row = conn.execute(
                "SELECT AVG(rating), COUNT(*) FROM universal_reviews WHERE reviewed_user_id=?",
                (str(reviewed_user_id),),
            ).fetchone()
        count = int(row[1] or 0) if row else 0
        if not count:
            return {"rating_average": None, "review_count": 0}
        return {"rating_average": round(float(row[0]), 1), "review_count": count}
