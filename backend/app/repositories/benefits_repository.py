"""Offers, coupons & rewards (benefits) -- part of the Partner / Revenue
architecture (same database, same Revenue Center).

- benefit_campaigns  any benefit type: bank/card, UPI/wallet, merchant/brand,
                     affiliate/partner, coupon, cashback, ASKODOX credit,
                     referral reward, free gift/service, scratch reward, other.
                     External offers exist only as verified rows (admin-entered
                     from a source, partner feed/API or import) -- never invented.
- benefit_coupons    coupon-code inventory (encrypted with the secrets key when
                     configured); a code is revealed only to the person who claims it
- benefit_claims     issuance (claim / scratch) and redemption, idempotent:
                     one claim per (campaign, user, trigger); a redemption
                     reference can be used once.

Rewards are decided here on the server; the app only displays them.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.services.secret_box import SecretBox

OFFER_TYPES = (
    "bank_card", "upi_wallet", "merchant_brand", "affiliate_partner", "coupon", "cashback", "askodox_credit",
    "referral_reward", "free_gift", "scratch_reward", "other",
)
FUNDING = ("askodox", "partner", "merchant", "bank", "shared")
SOURCE_KINDS = ("admin_entered", "partner_feed", "partner_api", "import")
CLAIM_STATES = ("ISSUED", "REDEEMED", "EXPIRED", "VOID")
_JSON = {"categories": [], "keywords": [], "locations": [], "countries": [], "payment_methods": [],
         "tracking_params": {}}
FIELDS = (
    "name", "partner_id", "provider_name", "offer_type", "description", "categories", "keywords", "locations",
    "countries", "payment_methods", "min_purchase", "max_discount", "discount_amount", "discount_percent",
    "cashback_amount", "cashback_percent", "credit_amount", "free_benefit", "starts_at", "ends_at",
    "per_user_limit", "total_budget", "total_cap", "funding_source", "partner_share_percent", "terms",
    "source_url", "source_kind", "verified_at", "active", "priority", "tracking_params",
)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _loads(raw: Any, default: Any) -> Any:
    try:
        return json.loads(raw) if raw else default
    except (TypeError, ValueError):
        return default


class BenefitError(ValueError):
    pass


class BenefitsRepository:
    def __init__(self, db_path: str = "podx.db", *, secret_box: SecretBox | None = None) -> None:
        self.db_path = db_path
        self.box = secret_box or SecretBox()
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS benefit_campaigns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL, partner_id INTEGER, provider_name TEXT, offer_type TEXT NOT NULL,
                    description TEXT, categories_json TEXT NOT NULL DEFAULT '[]', keywords_json TEXT NOT NULL DEFAULT '[]',
                    locations_json TEXT NOT NULL DEFAULT '[]', countries_json TEXT NOT NULL DEFAULT '[]',
                    payment_methods_json TEXT NOT NULL DEFAULT '[]',
                    min_purchase REAL, max_discount REAL, discount_amount REAL, discount_percent REAL,
                    cashback_amount REAL, cashback_percent REAL, credit_amount REAL, free_benefit TEXT,
                    starts_at TEXT, ends_at TEXT, per_user_limit INTEGER NOT NULL DEFAULT 1,
                    total_budget REAL, total_cap INTEGER, funding_source TEXT NOT NULL DEFAULT 'askodox',
                    partner_share_percent REAL, terms TEXT, source_url TEXT,
                    source_kind TEXT NOT NULL DEFAULT 'admin_entered', verified_at TEXT,
                    active INTEGER NOT NULL DEFAULT 0, priority INTEGER NOT NULL DEFAULT 0,
                    tracking_params_json TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS benefit_coupons (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id INTEGER NOT NULL, code TEXT NOT NULL, code_hash TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'AVAILABLE', claim_id INTEGER, created_at TEXT NOT NULL,
                    UNIQUE(campaign_id, code_hash)
                );
                CREATE TABLE IF NOT EXISTS benefit_claims (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id INTEGER NOT NULL, user_id TEXT NOT NULL, trigger_ref TEXT NOT NULL DEFAULT '',
                    kind TEXT NOT NULL, value REAL, coupon_id INTEGER, status TEXT NOT NULL,
                    created_at TEXT NOT NULL, redeemed_at TEXT, redemption_ref TEXT UNIQUE,
                    order_value REAL, askodox_cost REAL, partner_cost REAL,
                    UNIQUE(campaign_id, user_id, trigger_ref)
                );
                CREATE INDEX IF NOT EXISTS idx_benefit_claims_time ON benefit_claims(created_at);
                """
            )

    # ---------------------------------------------------------- campaigns --

    def _values(self, data: Dict[str, Any]) -> Dict[str, Any]:
        values: Dict[str, Any] = {}
        for field in FIELDS:
            if field not in data:
                continue
            value = data[field]
            if field in _JSON:
                values[f"{field}_json"] = json.dumps(value if value is not None else _JSON[field])
            elif field == "active":
                values["active"] = 1 if value else 0
            else:
                values[field] = value.strip() if isinstance(value, str) else value
        return values

    @staticmethod
    def _campaign(row: sqlite3.Row | None) -> Optional[Dict[str, Any]]:
        if row is None:
            return None
        item = dict(row)
        for field, default in _JSON.items():
            item[field] = _loads(item.pop(f"{field}_json", None), default)
        item["active"] = bool(item["active"])
        return item

    def create_campaign(self, data: Dict[str, Any]) -> Dict[str, Any]:
        values = self._values(data)
        now = _now()
        values.update(created_at=now, updated_at=now)
        with self._connect() as conn:
            cursor = conn.execute(
                f"INSERT INTO benefit_campaigns ({', '.join(values)}) VALUES ({', '.join('?' for _ in values)})",
                tuple(values.values()),
            )
            return self._campaign(conn.execute("SELECT * FROM benefit_campaigns WHERE id = ?",
                                               (cursor.lastrowid,)).fetchone())

    def update_campaign(self, campaign_id: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        values = self._values(data)
        with self._connect() as conn:
            if values:
                values["updated_at"] = _now()
                conn.execute(f"UPDATE benefit_campaigns SET {', '.join(f'{k} = ?' for k in values)} WHERE id = ?",
                             (*values.values(), campaign_id))
            return self._campaign(conn.execute("SELECT * FROM benefit_campaigns WHERE id = ?",
                                               (campaign_id,)).fetchone())

    def campaign(self, campaign_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            return self._campaign(conn.execute("SELECT * FROM benefit_campaigns WHERE id = ?",
                                               (campaign_id,)).fetchone())

    def campaigns(self, *, active_only: bool = False) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM benefit_campaigns" + (" WHERE active = 1" if active_only else "") + \
              " ORDER BY priority DESC, id"
        with self._connect() as conn:
            items = [self._campaign(r) for r in conn.execute(sql).fetchall()]
            usage = {r["campaign_id"]: dict(r) for r in conn.execute(
                "SELECT campaign_id, COUNT(*) AS claims, SUM(CASE WHEN status='REDEEMED' THEN 1 ELSE 0 END) AS "
                "redemptions, COALESCE(SUM(CASE WHEN status != 'VOID' THEN value END), 0) AS committed, "
                "(SELECT COUNT(*) FROM benefit_coupons c WHERE c.campaign_id = benefit_claims.campaign_id AND "
                "c.status = 'AVAILABLE') AS coupons_left FROM benefit_claims GROUP BY campaign_id").fetchall()}
            coupons = {r["campaign_id"]: r["n"] for r in conn.execute(
                "SELECT campaign_id, COUNT(*) AS n FROM benefit_coupons WHERE status = 'AVAILABLE' GROUP BY campaign_id")}
        for item in items:
            use = usage.get(item["id"], {})
            item["claims"] = int(use.get("claims") or 0)
            item["redemptions"] = int(use.get("redemptions") or 0)
            item["budget_committed"] = float(use.get("committed") or 0)
            item["coupons_available"] = int(coupons.get(item["id"], 0))
        return items

    # ------------------------------------------------------------ coupons --

    def _hash(self, code: str) -> str:
        import hashlib

        return hashlib.sha256(code.strip().upper().encode()).hexdigest()

    def add_coupons(self, campaign_id: int, codes: List[str]) -> Dict[str, int]:
        added = skipped = 0
        with self._connect() as conn:
            for raw in codes:
                code = str(raw or "").strip()
                if not code or len(code) > 64:
                    skipped += 1
                    continue
                stored = self.box.encrypt(code) if self.box.configured else code
                try:
                    conn.execute("INSERT INTO benefit_coupons (campaign_id, code, code_hash, created_at) VALUES "
                                 "(?, ?, ?, ?)", (campaign_id, stored, self._hash(code), _now()))
                    added += 1
                except sqlite3.IntegrityError:
                    skipped += 1  # duplicate code in this campaign
        return {"added": added, "skipped": skipped}

    def _code(self, stored: str) -> str:
        return self.box.decrypt(stored)

    # ------------------------------------------------------------- claims --

    def claims_for(self, user_id: str, campaign_id: int | None = None) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM benefit_claims WHERE user_id = ?", [user_id]
        if campaign_id is not None:
            sql, args = sql + " AND campaign_id = ?", args + [campaign_id]
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(sql + " ORDER BY id DESC", args).fetchall()]
            for row in rows:
                coupon = conn.execute("SELECT code FROM benefit_coupons WHERE id = ?",
                                      (row["coupon_id"],)).fetchone() if row["coupon_id"] else None
                row["code"] = self._code(coupon["code"]) if coupon else None
        return rows

    def issue(self, campaign: Dict[str, Any], user_id: str, *, trigger_ref: str = "", kind: str = "claim",
              value: float | None = None) -> Dict[str, Any]:
        """Issue a benefit (idempotent per campaign + user + trigger).
        Enforces per-user limit, total cap, total budget and coupon stock."""
        with self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute("SELECT * FROM benefit_claims WHERE campaign_id = ? AND user_id = ? AND "
                                    "trigger_ref = ?", (campaign["id"], user_id, trigger_ref)).fetchone()
            if existing is not None:
                conn.commit()
                return {**dict(existing), "duplicate": True}
            used_by_user = conn.execute("SELECT COUNT(*) FROM benefit_claims WHERE campaign_id = ? AND user_id = ? "
                                        "AND status != 'VOID'", (campaign["id"], user_id)).fetchone()[0]
            if used_by_user >= int(campaign.get("per_user_limit") or 1):
                raise BenefitError("already_claimed")
            totals = conn.execute("SELECT COUNT(*), COALESCE(SUM(value), 0) FROM benefit_claims WHERE "
                                  "campaign_id = ? AND status != 'VOID'", (campaign["id"],)).fetchone()
            if campaign.get("total_cap") and totals[0] >= int(campaign["total_cap"]):
                raise BenefitError("campaign_full")
            if campaign.get("total_budget") and value and totals[1] + value > float(campaign["total_budget"]):
                raise BenefitError("budget_exhausted")
            coupon_id = None
            stock = conn.execute("SELECT COUNT(*) FROM benefit_coupons WHERE campaign_id = ?",
                                 (campaign["id"],)).fetchone()[0]
            if stock:
                coupon = conn.execute("SELECT id FROM benefit_coupons WHERE campaign_id = ? AND status = 'AVAILABLE' "
                                      "ORDER BY id LIMIT 1", (campaign["id"],)).fetchone()
                if coupon is None:
                    raise BenefitError("out_of_codes")
                coupon_id = coupon["id"]
            cursor = conn.execute(
                "INSERT INTO benefit_claims (campaign_id, user_id, trigger_ref, kind, value, coupon_id, status, "
                "created_at) VALUES (?, ?, ?, ?, ?, ?, 'ISSUED', ?)",
                (campaign["id"], user_id, trigger_ref, kind, value, coupon_id, _now()),
            )
            if coupon_id:
                conn.execute("UPDATE benefit_coupons SET status = 'CLAIMED', claim_id = ? WHERE id = ?",
                             (cursor.lastrowid, coupon_id))
            conn.commit()
            row = dict(conn.execute("SELECT * FROM benefit_claims WHERE id = ?", (cursor.lastrowid,)).fetchone())
        return {**row, "duplicate": False}

    def claim(self, claim_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM benefit_claims WHERE id = ?", (claim_id,)).fetchone()
        return dict(row) if row else None

    def claim_by_code(self, campaign_ids: List[int], code: str) -> Optional[Dict[str, Any]]:
        if not campaign_ids:
            return None
        with self._connect() as conn:
            row = conn.execute(
                f"SELECT claim_id FROM benefit_coupons WHERE code_hash = ? AND campaign_id IN "
                f"({', '.join('?' for _ in campaign_ids)}) AND claim_id IS NOT NULL",
                (self._hash(code), *campaign_ids)).fetchone()
        return self.claim(row["claim_id"]) if row else None

    def redeem(self, claim_id: int, *, redemption_ref: str, order_value: float | None, benefit_value: float,
               funding_source: str, partner_share_percent: float | None = None) -> Dict[str, Any]:
        """Mark a claim redeemed ONCE; the cost is split by who funds it."""
        ref = str(redemption_ref or "").strip()[:120]
        if not ref:
            raise BenefitError("redemption reference required")
        if funding_source == "askodox":
            askodox_cost, partner_cost = benefit_value, 0.0
        elif funding_source == "shared":
            share = max(0.0, min(100.0, float(partner_share_percent or 0))) / 100
            partner_cost = round(benefit_value * share, 2)
            askodox_cost = round(benefit_value - partner_cost, 2)
        else:
            askodox_cost, partner_cost = 0.0, benefit_value
        with self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT * FROM benefit_claims WHERE id = ?", (claim_id,)).fetchone()
            if row is None:
                raise BenefitError("claim not found")
            if row["status"] == "REDEEMED":
                conn.commit()
                if row["redemption_ref"] == ref:
                    return {**dict(row), "duplicate": True}
                raise BenefitError("already_redeemed")
            if row["status"] != "ISSUED":
                raise BenefitError(f"claim is {row['status']}")
            if conn.execute("SELECT 1 FROM benefit_claims WHERE redemption_ref = ?", (ref,)).fetchone():
                raise BenefitError("redemption reference already used")
            conn.execute(
                "UPDATE benefit_claims SET status = 'REDEEMED', redeemed_at = ?, redemption_ref = ?, order_value = ?, "
                "value = ?, askodox_cost = ?, partner_cost = ? WHERE id = ?",
                (_now(), ref, order_value, benefit_value, askodox_cost, partner_cost, claim_id))
            if row["coupon_id"]:
                conn.execute("UPDATE benefit_coupons SET status = 'REDEEMED' WHERE id = ?", (row["coupon_id"],))
            conn.commit()
            return {**dict(conn.execute("SELECT * FROM benefit_claims WHERE id = ?", (claim_id,)).fetchone()),
                    "duplicate": False}

    def claims_between(self, start: str, end: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM benefit_claims WHERE (created_at >= ? AND created_at < ?) OR "
                "(redeemed_at >= ? AND redeemed_at < ?) ORDER BY id", (start, end, start, end)).fetchall()]
