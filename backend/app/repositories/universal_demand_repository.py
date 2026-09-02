"""Persistence for universal NEED/OFFER records.

This repository intentionally stays domain-neutral: work, workers, services,
products and future request types use the same storage model.

Important: this storage uses its own table name. The older DemandRepository
already owns `universal_demands` with a different schema, so sharing that table
causes startup failures on both fresh and existing databases.

TEST/DEMO isolation uses the existing ``source`` column so no destructive schema
migration is needed. Normal production reads exclude test/demo rows by default;
test mode reads only those rows.
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


class UniversalDemandRepository:
    TABLE = "universal_need_offer_records"
    TEST_SOURCES = ("demo", "test", "seed", "qa")

    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                f"""
                CREATE TABLE IF NOT EXISTS {self.TABLE} (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    side TEXT NOT NULL,
                    domain TEXT NOT NULL,
                    subject TEXT NOT NULL,
                    quantity REAL,
                    unit TEXT,
                    price REAL,
                    currency TEXT,
                    when_text TEXT,
                    latitude REAL,
                    longitude REAL,
                    location_text TEXT,
                    constraints_json TEXT NOT NULL DEFAULT '{{}}',
                    source TEXT NOT NULL DEFAULT 'text',
                    media_ref TEXT,
                    status TEXT NOT NULL DEFAULT 'ACTIVE',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            conn.execute(
                f"CREATE INDEX IF NOT EXISTS idx_need_offer_side_status ON {self.TABLE}(side, status)"
            )
            conn.execute(
                f"CREATE INDEX IF NOT EXISTS idx_need_offer_domain_status ON {self.TABLE}(domain, status)"
            )
            conn.execute(
                f"CREATE INDEX IF NOT EXISTS idx_need_offer_user_status ON {self.TABLE}(user_id, status)"
            )
            conn.execute(
                f"CREATE INDEX IF NOT EXISTS idx_need_offer_source_status ON {self.TABLE}(source, status)"
            )

    @classmethod
    def is_test_source(cls, value: Any) -> bool:
        source = str(value or "").strip().casefold()
        return source in cls.TEST_SOURCES or source.startswith("demo:") or source.startswith("test:")

    @classmethod
    def is_test_record(cls, record: Dict[str, Any]) -> bool:
        return cls.is_test_source(record.get("source"))

    @classmethod
    def _mode_sql(cls, test_mode: bool) -> tuple[str, List[Any]]:
        markers = ",".join("?" for _ in cls.TEST_SOURCES)
        test_expression = (
            f"(LOWER(source) IN ({markers}) OR LOWER(source) LIKE 'demo:%' OR LOWER(source) LIKE 'test:%')"
        )
        if test_mode:
            return f" AND {test_expression}", list(cls.TEST_SOURCES)
        return f" AND NOT {test_expression}", list(cls.TEST_SOURCES)

    @classmethod
    def _test_expression(cls) -> tuple[str, List[Any]]:
        markers = ",".join("?" for _ in cls.TEST_SOURCES)
        expression = (
            f"(LOWER(source) IN ({markers}) OR LOWER(source) LIKE 'demo:%' OR LOWER(source) LIKE 'test:%')"
        )
        return expression, list(cls.TEST_SOURCES)

    def create(self, record: Dict[str, Any]) -> int:
        now = datetime.now(timezone.utc).isoformat()
        constraints = record.get("constraints") or {}
        with self._connect() as conn:
            cur = conn.execute(
                f"""
                INSERT INTO {self.TABLE} (
                    user_id, side, domain, subject, quantity, unit, price,
                    currency, when_text, latitude, longitude, location_text,
                    constraints_json, source, media_ref, status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(record["user_id"]), str(record["side"]).upper(),
                    str(record.get("domain") or "OTHER").upper(),
                    str(record["subject"]).strip(), record.get("quantity"),
                    record.get("unit"), record.get("price"),
                    record.get("currency"), record.get("when") or record.get("when_text"),
                    record.get("latitude"), record.get("longitude"),
                    record.get("location_text"), json.dumps(constraints, ensure_ascii=False),
                    record.get("source") or "text", record.get("media_ref"),
                    record.get("status") or "ACTIVE", now, now,
                ),
            )
            return int(cur.lastrowid)

    def get(self, demand_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                f"SELECT * FROM {self.TABLE} WHERE id = ?", (demand_id,)
            ).fetchone()
        return self._row(row) if row else None

    def latest_active_for_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                f"""
                SELECT *
                FROM {self.TABLE}
                WHERE user_id = ? AND status = 'ACTIVE'
                ORDER BY id DESC
                LIMIT 1
                """,
                (str(user_id),),
            ).fetchone()
        return self._row(row) if row else None

    def latest_active_for_user_missing_location(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute(
                f"""
                SELECT *
                FROM {self.TABLE}
                WHERE user_id = ?
                  AND status = 'ACTIVE'
                  AND latitude IS NULL
                  AND longitude IS NULL
                ORDER BY id DESC
                LIMIT 1
                """,
                (str(user_id),),
            ).fetchone()
        return self._row(row) if row else None

    def update_location_text(self, demand_id: int, location_text: str) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                f"""
                UPDATE {self.TABLE}
                SET location_text = ?, updated_at = ?
                WHERE id = ?
                """,
                (str(location_text).strip(), now, int(demand_id)),
            )

    def update_location(
        self,
        demand_id: int,
        latitude: float,
        longitude: float,
        location_text: Optional[str] = None,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                f"""
                UPDATE {self.TABLE}
                SET latitude = ?, longitude = ?, location_text = COALESCE(?, location_text), updated_at = ?
                WHERE id = ?
                """,
                (float(latitude), float(longitude), location_text, now, int(demand_id)),
            )

    def list_active(
        self,
        limit: int = 500,
        exclude_user_id: Optional[str] = None,
        test_mode: bool = False,
    ) -> List[Dict[str, Any]]:
        sql = f"SELECT * FROM {self.TABLE} WHERE status = 'ACTIVE'"
        params: List[Any] = []
        mode_sql, mode_params = self._mode_sql(test_mode)
        sql += mode_sql
        params.extend(mode_params)
        if exclude_user_id is not None:
            sql += " AND user_id <> ?"
            params.append(str(exclude_user_id))
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(limit)
        with self._connect() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [self._row(row) for row in rows]

    def list_opposite_active(
        self,
        side: str,
        domain: Optional[str] = None,
        limit: int = 200,
        test_mode: bool = False,
    ) -> List[Dict[str, Any]]:
        opposite = "OFFER" if str(side).upper() == "NEED" else "NEED"
        sql = f"SELECT * FROM {self.TABLE} WHERE side = ? AND status = 'ACTIVE'"
        params: List[Any] = [opposite]
        mode_sql, mode_params = self._mode_sql(test_mode)
        sql += mode_sql
        params.extend(mode_params)
        if domain:
            sql += " AND domain = ?"
            params.append(str(domain).upper())
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(limit)
        with self._connect() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [self._row(row) for row in rows]

    def delete_test_records(self) -> int:
        """Delete only controlled TEST/DEMO rows and preserve production rows."""
        expression, params = self._test_expression()
        with self._connect() as conn:
            cur = conn.execute(
                f"DELETE FROM {self.TABLE} WHERE {expression}",
                params,
            )
            return int(cur.rowcount if cur.rowcount is not None else 0)

    def update_status(self, demand_id: int, status: str) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self._connect() as conn:
            conn.execute(
                f"UPDATE {self.TABLE} SET status = ?, updated_at = ? WHERE id = ?",
                (status.upper(), now, demand_id),
            )

    @staticmethod
    def _row(row: sqlite3.Row) -> Dict[str, Any]:
        data = dict(row)
        data["constraints"] = json.loads(data.pop("constraints_json") or "{}")
        return data
