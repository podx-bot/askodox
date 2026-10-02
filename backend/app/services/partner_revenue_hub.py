from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Any


@dataclass
class PartnerRevenueHub:
    """Persistent foundation for ASKODOX partner, product, staff, BFSI and revenue workflows.

    This layer stores only verified/configured commercial metadata. Search ranking must remain
    relevance-first; monetisation is a routing attribute, never a ranking requirement.
    """

    db_path: str

    def __post_init__(self) -> None:
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS partner_revenue_registry (
                partner_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                sector TEXT NOT NULL DEFAULT 'general',
                category TEXT NOT NULL DEFAULT 'general',
                integration_modes_json TEXT NOT NULL DEFAULT '[]',
                commercial_model TEXT NOT NULL DEFAULT 'none',
                attribution_template TEXT NOT NULL DEFAULT '',
                human_support INTEGER NOT NULL DEFAULT 0,
                staff_fallback INTEGER NOT NULL DEFAULT 0,
                compliance_notes TEXT NOT NULL DEFAULT '',
                evidence_status TEXT NOT NULL DEFAULT 'unverified',
                active INTEGER NOT NULL DEFAULT 0,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS affiliate_products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                partner_id TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT '',
                merchant TEXT NOT NULL DEFAULT '',
                original_product_url TEXT NOT NULL,
                affiliate_url TEXT NOT NULL DEFAULT '',
                collection_url TEXT NOT NULL DEFAULT '',
                title TEXT NOT NULL DEFAULT '',
                category TEXT NOT NULL DEFAULT 'general',
                subcategory TEXT NOT NULL DEFAULT '',
                price REAL,
                currency TEXT NOT NULL DEFAULT 'INR',
                image_url TEXT NOT NULL DEFAULT '',
                stock_status TEXT NOT NULL DEFAULT '',
                verified_commission_rate REAL,
                active INTEGER NOT NULL DEFAULT 1,
                last_verified TEXT,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                UNIQUE(partner_id, original_product_url)
            );
            CREATE INDEX IF NOT EXISTS idx_affiliate_products_category
                ON affiliate_products(category, subcategory, active);

            CREATE TABLE IF NOT EXISTS partner_staff_assignments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                staff_ref TEXT NOT NULL,
                partner_id TEXT NOT NULL DEFAULT '',
                sector TEXT NOT NULL DEFAULT '',
                category TEXT NOT NULL DEFAULT '',
                permissions_json TEXT NOT NULL DEFAULT '[]',
                active INTEGER NOT NULL DEFAULT 1,
                UNIQUE(staff_ref, partner_id, sector, category)
            );

            CREATE TABLE IF NOT EXISTS bfsi_partner_flows (
                partner_id TEXT NOT NULL,
                product_type TEXT NOT NULL,
                lead_enabled INTEGER NOT NULL DEFAULT 0,
                journey_enabled INTEGER NOT NULL DEFAULT 0,
                callback_enabled INTEGER NOT NULL DEFAULT 0,
                status_enabled INTEGER NOT NULL DEFAULT 0,
                consent_required INTEGER NOT NULL DEFAULT 1,
                regulated_entity TEXT NOT NULL DEFAULT '',
                active INTEGER NOT NULL DEFAULT 0,
                metadata_json TEXT NOT NULL DEFAULT '{}',
                PRIMARY KEY(partner_id, product_type)
            );

            CREATE TABLE IF NOT EXISTS partner_revenue_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                partner_id TEXT NOT NULL DEFAULT '',
                product_ref TEXT NOT NULL DEFAULT '',
                user_ref TEXT NOT NULL DEFAULT '',
                external_reference TEXT NOT NULL DEFAULT '',
                value REAL NOT NULL DEFAULT 0,
                currency TEXT NOT NULL DEFAULT 'INR',
                settlement_status TEXT NOT NULL DEFAULT 'pending',
                metadata_json TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(partner_id, event_type, external_reference)
            );
            CREATE INDEX IF NOT EXISTS idx_partner_revenue_events_partner
                ON partner_revenue_events(partner_id, event_type, created_at);
            """)

    def upsert_partner(self, partner_id: str, **values: Any) -> dict[str, Any]:
        partner_id = str(partner_id or "").strip().lower()
        name = str(values.get("name") or partner_id).strip()
        if not partner_id or not name:
            raise ValueError("partner_id and name are required")
        modes = sorted({str(x).strip().lower() for x in values.get("integration_modes", []) if str(x).strip()})
        payload = (
            partner_id, name, str(values.get("sector") or "general").lower(),
            str(values.get("category") or "general").lower(), json.dumps(modes),
            str(values.get("commercial_model") or "none").lower(),
            str(values.get("attribution_template") or ""), int(bool(values.get("human_support"))),
            int(bool(values.get("staff_fallback"))), str(values.get("compliance_notes") or ""),
            str(values.get("evidence_status") or "unverified").lower(), int(bool(values.get("active"))),
            json.dumps(values.get("metadata") or {}, ensure_ascii=False),
        )
        with self._connect() as conn:
            conn.execute("""INSERT INTO partner_revenue_registry
                (partner_id,name,sector,category,integration_modes_json,commercial_model,
                 attribution_template,human_support,staff_fallback,compliance_notes,
                 evidence_status,active,metadata_json,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP)
                ON CONFLICT(partner_id) DO UPDATE SET
                 name=excluded.name,sector=excluded.sector,category=excluded.category,
                 integration_modes_json=excluded.integration_modes_json,
                 commercial_model=excluded.commercial_model,
                 attribution_template=excluded.attribution_template,
                 human_support=excluded.human_support,staff_fallback=excluded.staff_fallback,
                 compliance_notes=excluded.compliance_notes,evidence_status=excluded.evidence_status,
                 active=excluded.active,metadata_json=excluded.metadata_json,
                 updated_at=CURRENT_TIMESTAMP""", payload)
        return self.get_partner(partner_id) or {}

    def get_partner(self, partner_id: str) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM partner_revenue_registry WHERE partner_id=?",
                               (str(partner_id).strip().lower(),)).fetchone()
        if row is None:
            return None
        item = dict(row)
        item["integration_modes"] = json.loads(item.pop("integration_modes_json") or "[]")
        item["metadata"] = json.loads(item.pop("metadata_json") or "{}")
        item["active"] = bool(item["active"])
        item["human_support"] = bool(item["human_support"])
        item["staff_fallback"] = bool(item["staff_fallback"])
        return item

    def list_partners(self, *, sector: str = "", active_only: bool = False) -> list[dict[str, Any]]:
        sql, args = "SELECT partner_id FROM partner_revenue_registry WHERE 1=1", []
        if sector:
            sql += " AND sector=?"; args.append(sector.strip().lower())
        if active_only:
            sql += " AND active=1"
        sql += " ORDER BY sector,name"
        with self._connect() as conn:
            ids = [r["partner_id"] for r in conn.execute(sql, args).fetchall()]
        return [p for pid in ids if (p := self.get_partner(pid)) is not None]

    def record_event(self, event_type: str, partner_id: str, *, external_reference: str = "",
                     value: float = 0, currency: str = "INR", user_ref: str = "",
                     product_ref: str = "", metadata: dict[str, Any] | None = None) -> int:
        event_type = str(event_type or "").strip().lower()
        if not event_type:
            raise ValueError("event_type is required")
        with self._connect() as conn:
            cur = conn.execute("""INSERT INTO partner_revenue_events
                (event_type,partner_id,product_ref,user_ref,external_reference,value,currency,metadata_json)
                VALUES(?,?,?,?,?,?,?,?)""",
                (event_type, str(partner_id or "").strip().lower(), product_ref, user_ref,
                 external_reference, float(value or 0), currency or "INR",
                 json.dumps(metadata or {}, ensure_ascii=False)))
            return int(cur.lastrowid)
