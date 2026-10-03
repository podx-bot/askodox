"""Persistence for the ASKODOX Admin Command Center (Phases 18-23).

Staff accounts + permissions, feature flags, audit log, the no-match queue,
discovery/source usage events, integration check results and de-duplicated
admin notifications. Staff tokens are stored only as SHA-256 hashes; no
secret is ever returned after creation.
"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional

from app.services.governance import all_permissions, redact

# ------------------------------------------------------------ permissions --

_LEGACY_PERMISSIONS = (
    "overview:view",
    "users:view",
    "users:manage",
    "requests:view",
    "requests:manage",
    "catalog:view",
    "catalog:manage",
    "support:view",
    "support:manage",
    "nomatch:view",
    "nomatch:manage",
    "notifications:view",
    "analytics:view",
    "analytics:export",
    "health:view",
    "integrations:view",
    "integrations:manage",
    "config:view",
    "config:manage",
    "payments:view",
    "payments:manage",
    "staff:manage",
    "audit:view",
    # Offers, rewards/attribution, referrals, plans/subscriptions, catalog AI.
    "growth:view",
    "growth:manage",
    # Affiliate / Partner Hub and the Revenue Center.
    "partners:view",
    "partners:manage",
    "revenue:view",
    "revenue:manage",
    # Sponsored listings: advertisers, campaigns, approvals, analytics.
    "sponsored:view",
    "sponsored:manage",
    # Commercial platform: affiliate programs/links, smart links, merchant
    # offers, videos/creators/reviews, notification templates, finance
    # (payments ledger, revenue ledger), rewards ledger, AI insights.
    "affiliate:view",
    "affiliate:manage",
    "links:view",
    "links:manage",
    "offers:view",
    "offers:manage",
    "content:view",
    "content:manage",
    "notifications:manage",
    "finance:view",
    "finance:manage",
    "rewards:view",
    "rewards:manage",
    "insights:view",
    # Affiliate Product Manager (staff-curated Meesho / Amazon / Flipkart /
    # Wishlink products): each operation is its own grant -- staff never get
    # stock, commission or link control just because they can add products.
    "affiliate_products:view",
    "affiliate_products:create",
    "affiliate_products:edit",
    "affiliate_products:delete",
    "affiliate_products:stock",
    "affiliate_products:commission",
    "affiliate_products:links",
    "affiliate_products:bulk_import",
)

# Every module gets the full verb set (view / create / edit / approve /
# delete / export / manage); ``manage`` implies create/edit/approve/delete.
MODULES = tuple(dict.fromkeys([p.split(":", 1)[0] for p in _LEGACY_PERMISSIONS] + [
    "approvals",   # the reusable approvals workflow (ORANGE / RED changes)
    "selfheal",    # Self-Healing Engine
    "companion",   # AI Companion / Screen Guide
    "security",    # security posture (sign-in failures, headers, advisor)
    "roles",       # custom role definitions (Owner)
    "delivery",    # delivery partners / drivers
    "qa",          # phone-test / QA center
]))
PERMISSIONS = all_permissions(_LEGACY_PERMISSIONS, MODULES)

ROLE_PRESETS: Dict[str, tuple[str, ...]] = {
    "super_admin": PERMISSIONS,
    "operations_manager": (
        "overview:view", "users:view", "users:manage", "requests:view", "requests:manage",
        "catalog:view", "catalog:manage", "support:view", "support:manage", "nomatch:view",
        "nomatch:manage", "notifications:view", "analytics:view", "analytics:export",
        "health:view", "integrations:view", "config:view", "audit:view", "growth:view",
        "approvals:view", "selfheal:view", "companion:view",
    ),
    "support_agent": (
        "overview:view", "support:view", "support:manage", "requests:view", "notifications:view", "users:view",
    ),
    "seller_manager": (
        "overview:view", "users:view", "users:manage", "catalog:view", "catalog:manage", "notifications:view",
    ),
    "catalog_manager": (
        "overview:view", "catalog:view", "catalog:manage", "nomatch:view", "nomatch:manage",
    ),
    "analyst": ("overview:view", "analytics:view", "analytics:export", "health:view", "nomatch:view", "revenue:view"),
    "integrations_manager": (
        "overview:view", "integrations:view", "integrations:manage", "config:view", "config:manage", "health:view",
        "selfheal:view",
    ),
    "payments_manager": ("overview:view", "payments:view", "payments:manage", "growth:view", "revenue:view",
                         "revenue:manage", "analytics:export"),
    "growth_manager": ("overview:view", "growth:view", "growth:manage", "catalog:view", "analytics:view",
                       "partners:view", "partners:manage", "revenue:view", "sponsored:view", "sponsored:manage",
                       "offers:view", "offers:manage", "rewards:view", "links:view", "insights:view"),
    "campaign_manager": ("overview:view", "sponsored:view", "sponsored:manage", "links:view", "links:manage",
                         "offers:view", "analytics:view", "insights:view"),
    "affiliate_manager": ("overview:view", "affiliate:view", "affiliate:manage", "partners:view", "partners:manage",
                          "links:view", "links:manage", "revenue:view", "analytics:view",
                          "affiliate_products:view", "affiliate_products:create", "affiliate_products:edit",
                          "affiliate_products:delete", "affiliate_products:stock", "affiliate_products:commission",
                          "affiliate_products:links", "affiliate_products:bulk_import"),
    # Catalog staff: add / edit products, keep stock current, bulk entry.
    # No commission, link, delete or admin rights unless granted separately.
    "affiliate_catalog_staff": ("overview:view", "affiliate_products:view", "affiliate_products:create",
                                "affiliate_products:edit", "affiliate_products:stock",
                                "affiliate_products:bulk_import"),
    "finance": ("overview:view", "payments:view", "payments:manage", "finance:view", "finance:manage",
                "revenue:view", "revenue:manage", "rewards:view", "rewards:manage", "analytics:view",
                "analytics:export", "audit:view"),
    "content_moderator": ("overview:view", "content:view", "content:manage", "notifications:view"),
    "merchant_manager": ("overview:view", "users:view", "users:manage", "offers:view", "offers:manage",
                         "catalog:view", "catalog:manage", "support:view"),
    "analytics_viewer": ("overview:view", "analytics:view", "insights:view", "health:view", "companion:view"),
}

# ----------------------------------------------------------- feature flags --

FEATURE_FLAGS: Dict[str, str] = {
    "results.registered": "ASKODOX registered sellers/listings in chat results",
    "results.nearby_external": "Nearby/wider external shops (Google Places)",
    "results.online": "Online product results (web discovery)",
    "results.affiliate": "Affiliate partner results",
    "results.sponsored": "Sponsored campaign results (labelled, after organic results)",
    "results.used": "Used / second-hand results",
    "results.surplus": "Surplus / clearance / open-box results",
    "results.deals": "Deals & offers results",
    "results.videos": "Related videos / reviews",
    "support.escalation": "In-app customer-support escalation",
    "notifications.admin": "Admin notifications (no-match, critical escalations)",
    "payments.subscriptions": "Optional payment / subscription flows",
    "ai.assistant": "Universal AI assistant replies in Main Chat",
    "voice.sarvam_tts": "Sarvam Bulbul reply voice (device TTS fallback when off)",
    "links.smart": "Smart / deep links (/l/{slug}) with app -> web fallback",
    "offers.merchant": "Merchant-created offers (reviewed) on results and claims",
    "payments.online": "Online payment gateways (only once a gateway is configured)",
    "rewards": "Rewards ledger (cashback, points, merchant rewards)",
    "coupons": "Coupons and promo codes",
    "referrals": "Refer & earn",
    "support.whatsapp": "WhatsApp support channel (needs WhatsApp configuration)",
    "notifications.push": "Push notifications (needs Firebase configuration)",
    "notifications.email": "Email notifications (needs an email provider)",
    "notifications.sms": "SMS notifications (needs an SMS provider)",
    "notifications.whatsapp": "WhatsApp notifications (needs WhatsApp configuration)",
    "notifications.promotions": "Targeted promotions (reviewed campaigns, consent + frequency caps)",
    "companion.enabled": "AI Companion (master switch: off hides every companion capability; ASKODOX keeps working)",
    "companion.floating_bubble": "Floating ASKODOX bubble over other apps (Android, user-granted overlay)",
    "companion.screen_guide": "AI Companion Screen Guide over other apps (Android, opt-in, Privacy Shield)",
    "companion.accessibility": "Screen Guide may use the user-enabled Android accessibility service (policy kill switch)",
    "companion.privacy_shield": "Privacy Shield for the Screen Guide (fail-closed: switching it off stops the guide, never unprotects it)",
    "selfheal.enabled": "Self-Healing Engine: detect issues and propose fixes",
    "selfheal.green_auto": "Self-Healing: apply GREEN (safe, reversible) fixes automatically",
    "referrals.priority_credits": "Referrals earn Priority Notification Credits (rules in Growth -> Referral credit rules)",
    "location.proximity_alerts": "Hyper-local opportunity alerts (foreground / app-open by default)",
    "location.background_optin": "Offer background-location proximity alerts to users who explicitly opt in (Play declaration required)",
    "delivery.matching": "Match delivery requests to approved, available delivery partners",
}

# Flags that start OFF until the Owner switches them on (everything else
# defaults ON, as before).
FLAG_DEFAULTS: Dict[str, bool] = {"companion.screen_guide": False, "selfheal.green_auto": False,
                                  "referrals.priority_credits": False, "location.proximity_alerts": False,
                                  "location.background_optin": False, "delivery.matching": False}

ESCALATION_STATUSES = ("OPEN", "IN_PROGRESS", "WAITING_FOR_USER", "RESOLVED", "CLOSED")
NO_MATCH_STATUSES = ("OPEN", "INVESTIGATING", "SOURCE_ADDED", "CATEGORY_ADDED", "RESOLVED", "DISMISSED")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def hash_token(token: str) -> str:
    return hashlib.sha256(str(token).encode("utf-8")).hexdigest()


def mask_user_id(user_id: Any) -> str:
    """Phone-bearing ids ("app-phone-919876543210") are never shown in full:
    every digit except the last four is masked."""
    return re.sub(r"\d(?=\d{4})", "•", str(user_id or ""))


TRACE_KEEP = 5000  # newest flow traces kept


class CommandCenterRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS admin_staff (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    role TEXT NOT NULL,
                    permissions_json TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    active INTEGER NOT NULL DEFAULT 1,
                    created_by TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS feature_flags (
                    key TEXT PRIMARY KEY,
                    enabled INTEGER NOT NULL,
                    updated_by TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS admin_audit_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    actor TEXT NOT NULL,
                    action TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    before_json TEXT,
                    after_json TEXT,
                    reason TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS no_match_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    demand_id INTEGER NOT NULL UNIQUE,
                    subject TEXT,
                    domain TEXT,
                    location_text TEXT,
                    source_status_json TEXT,
                    status TEXT NOT NULL DEFAULT 'OPEN',
                    note TEXT,
                    assigned_to TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS discovery_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    demand_id INTEGER NOT NULL,
                    source TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE(demand_id, source)
                );
                CREATE TABLE IF NOT EXISTS integration_checks (
                    name TEXT PRIMARY KEY,
                    ok INTEGER NOT NULL,
                    detail TEXT,
                    checked_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS flow_traces (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    trace_key TEXT NOT NULL UNIQUE,
                    deal_id INTEGER,
                    data_json TEXT NOT NULL DEFAULT '{}',
                    stage TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_flow_traces_deal ON flow_traces(deal_id);
                CREATE TABLE IF NOT EXISTS admin_notifications (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_key TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    entity_id TEXT,
                    read INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                );
                -- 2026-09-30: reusable approvals (ORANGE / RED changes). The
                -- proposed state is a safe, redacted description plus the
                -- named executor's parameters -- never code, SQL or secrets.
                CREATE TABLE IF NOT EXISTS cc_approvals (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    action TEXT NOT NULL,
                    target TEXT NOT NULL,
                    risk TEXT NOT NULL,
                    reason TEXT,
                    old_json TEXT,
                    proposed_json TEXT,
                    params_json TEXT NOT NULL DEFAULT '{}',
                    status TEXT NOT NULL DEFAULT 'PENDING',
                    requested_by TEXT NOT NULL,
                    requested_role TEXT,
                    requested_at TEXT NOT NULL,
                    decided_by TEXT,
                    decided_at TEXT,
                    decision_note TEXT,
                    result_json TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_cc_approvals_status ON cc_approvals(status, id);
                -- Owner-defined roles and Owner overrides of the presets.
                CREATE TABLE IF NOT EXISTS cc_roles (
                    name TEXT PRIMARY KEY,
                    label TEXT,
                    permissions_json TEXT NOT NULL,
                    updated_by TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            # 2026-09-30: who (role) / risk / result on every audit row.
            for column in ("actor_role TEXT", "risk TEXT", "result TEXT"):
                try:
                    conn.execute(f"ALTER TABLE admin_audit_log ADD COLUMN {column}")
                except sqlite3.OperationalError:
                    pass  # already present

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # ---------------------------------------------------------------- staff --

    def create_staff(self, name: str, role: str, permissions: Iterable[str], created_by: str) -> Dict[str, Any]:
        token = "stf_" + secrets.token_urlsafe(24)
        clean = sorted({p for p in permissions if p in PERMISSIONS})
        now = _now()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO admin_staff(name,role,permissions_json,token_hash,active,created_by,created_at,updated_at) VALUES(?,?,?,?,1,?,?,?)",
                (name.strip()[:120], role, json.dumps(clean), hash_token(token), created_by, now, now),
            )
            staff_id = int(cur.lastrowid)
        staff = self.get_staff(staff_id) or {}
        # The only time the token exists in clear text; it is never stored.
        return {**staff, "token": token}

    def get_staff(self, staff_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM admin_staff WHERE id=?", (int(staff_id),)).fetchone()
        return self._staff(row) if row else None

    def staff_by_token(self, token: str) -> Optional[Dict[str, Any]]:
        if not token:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM admin_staff WHERE token_hash=? AND active=1", (hash_token(token),)
            ).fetchone()
        return self._staff(row) if row else None

    def list_staff(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM admin_staff ORDER BY id").fetchall()
        return [self._staff(row) for row in rows]

    def update_staff(self, staff_id: int, *, role: str | None = None, permissions: Iterable[str] | None = None,
                     active: bool | None = None) -> Optional[Dict[str, Any]]:
        current = self.get_staff(staff_id)
        if not current:
            return None
        perms = current["permissions"] if permissions is None else sorted({p for p in permissions if p in PERMISSIONS})
        with self._connect() as conn:
            conn.execute(
                "UPDATE admin_staff SET role=?, permissions_json=?, active=?, updated_at=? WHERE id=?",
                (role or current["role"], json.dumps(perms),
                 int(current["active"] if active is None else active), _now(), int(staff_id)),
            )
        return self.get_staff(staff_id)

    @staticmethod
    def _staff(row) -> Dict[str, Any]:
        data = dict(row)
        data.pop("token_hash", None)
        data["permissions"] = json.loads(data.pop("permissions_json") or "[]")
        data["active"] = bool(data["active"])
        return data

    # ---------------------------------------------------------------- flags --

    def flags(self) -> Dict[str, Dict[str, Any]]:
        with self._connect() as conn:
            rows = {r["key"]: dict(r) for r in conn.execute("SELECT * FROM feature_flags").fetchall()}
        result = {}
        for key, description in FEATURE_FLAGS.items():
            row = rows.get(key)
            result[key] = {
                "key": key,
                "description": description,
                "enabled": FLAG_DEFAULTS.get(key, True) if row is None else bool(row["enabled"]),
                "updated_by": row["updated_by"] if row else None,
                "updated_at": row["updated_at"] if row else None,
            }
        return result

    def flags_map(self) -> Dict[str, bool]:
        return {key: item["enabled"] for key, item in self.flags().items()}

    def is_enabled(self, key: str) -> bool:
        with self._connect() as conn:
            row = conn.execute("SELECT enabled FROM feature_flags WHERE key=?", (key,)).fetchone()
        return FLAG_DEFAULTS.get(key, True) if row is None else bool(row["enabled"])

    def set_flag(self, key: str, enabled: bool, actor: str) -> Dict[str, Any]:
        if key not in FEATURE_FLAGS:
            raise KeyError(key)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO feature_flags(key,enabled,updated_by,updated_at) VALUES(?,?,?,?) "
                "ON CONFLICT(key) DO UPDATE SET enabled=excluded.enabled, updated_by=excluded.updated_by, updated_at=excluded.updated_at",
                (key, int(bool(enabled)), actor, _now()),
            )
        return self.flags()[key]

    # ---------------------------------------------------------------- audit --

    def audit(self, actor: str, action: str, entity_type: str, entity_id: Any,
              before: Any = None, after: Any = None, reason: str = "", *, role: str | None = None,
              risk: str | None = None, result: str | None = "OK") -> None:
        """Append-only (no update / delete path exists). Secret-looking keys
        and values are redacted before they are stored."""
        from app.services.governance import flag_risk

        if risk is None:
            risk = flag_risk(str(entity_id)) if entity_type == "feature_flag" else "GREEN"
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO admin_audit_log(actor,action,entity_type,entity_id,before_json,after_json,reason,created_at,"
                "actor_role,risk,result) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (actor, action, entity_type, str(entity_id), json.dumps(redact(before), default=str),
                 json.dumps(redact(after), default=str), redact(reason or ""), _now(),
                 role or ("super_admin" if actor == "owner" else self._role_of(actor)), risk, result),
            )

    def _role_of(self, actor: str) -> Optional[str]:
        if str(actor).startswith("staff-") and str(actor)[6:].isdigit():
            staff = self.get_staff(int(str(actor)[6:]))
            return staff["role"] if staff else None
        return None

    def audit_log(self, limit: int = 100, *, actor: str = "", action: str = "", entity_type: str = "",
                  risk: str = "", q: str = "", since: str = "") -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM admin_audit_log WHERE 1=1", []
        for column, value in (("actor", actor), ("action", action), ("entity_type", entity_type), ("risk", risk)):
            if value:
                sql += f" AND {column}=?"
                params.append(value)
        if since:
            sql += " AND created_at>=?"
            params.append(since)
        if q:
            sql += " AND (entity_id LIKE ? OR action LIKE ? OR reason LIKE ?)"
            params += [f"%{q}%"] * 3
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(max(1, min(limit, 5000)))
        with self._connect() as conn:
            rows = conn.execute(sql, tuple(params)).fetchall()
        items = []
        for row in rows:
            data = dict(row)
            data["before"] = json.loads(data.pop("before_json") or "null")
            data["after"] = json.loads(data.pop("after_json") or "null")
            data["risk"] = data.get("risk") or "GREEN"
            items.append(data)
        return items

    # ------------------------------------------------------------ approvals --

    def create_approval(self, *, action: str, target: str, risk: str, reason: str, old: Any, proposed: Any,
                        params: Dict[str, Any], requested_by: str, requested_role: str) -> Dict[str, Any]:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO cc_approvals(action,target,risk,reason,old_json,proposed_json,params_json,status,"
                "requested_by,requested_role,requested_at) VALUES(?,?,?,?,?,?,?,'PENDING',?,?,?)",
                (action, str(target)[:200], risk, redact(reason or "")[:1000], json.dumps(redact(old), default=str),
                 json.dumps(redact(proposed), default=str), json.dumps(params, default=str), requested_by,
                 requested_role, _now()))
            approval_id = int(cur.lastrowid)
        return self.get_approval(approval_id) or {}

    def get_approval(self, approval_id: int, *, with_params: bool = False) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM cc_approvals WHERE id=?", (int(approval_id),)).fetchone()
        return self._approval(row, with_params) if row else None

    def approvals(self, status: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM cc_approvals", []
        if status:
            sql += " WHERE status=?"
            params.append(status)
        sql += " ORDER BY id DESC LIMIT ?"
        params.append(max(1, min(limit, 1000)))
        with self._connect() as conn:
            rows = conn.execute(sql, tuple(params)).fetchall()
        return [self._approval(r, False) for r in rows]

    def decide_approval(self, approval_id: int, *, status: str, decided_by: str, note: str = "",
                        result: Any = None) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.execute(
                "UPDATE cc_approvals SET status=?, decided_by=?, decided_at=?, decision_note=?, result_json=? "
                "WHERE id=? AND status='PENDING'",
                (status, decided_by, _now(), redact(note or "")[:1000], json.dumps(redact(result), default=str),
                 int(approval_id)))
            if cur.rowcount == 0:
                return None  # already decided (idempotent, no double execution)
        return self.get_approval(approval_id)

    def set_approval_result(self, approval_id: int, status: str, result: Any) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE cc_approvals SET status=?, result_json=? WHERE id=?",
                         (status, json.dumps(redact(result), default=str), int(approval_id)))

    @staticmethod
    def _approval(row, with_params: bool) -> Dict[str, Any]:
        data = dict(row)
        data["old"] = json.loads(data.pop("old_json") or "null")
        data["proposed"] = json.loads(data.pop("proposed_json") or "null")
        data["result"] = json.loads(data.pop("result_json") or "null")
        params = json.loads(data.pop("params_json") or "{}")
        if with_params:
            data["params"] = params
        return data

    # ---------------------------------------------------------------- roles --

    def roles(self) -> Dict[str, Dict[str, Any]]:
        """Presets merged with the Owner's overrides and custom roles."""
        out = {name: {"name": name, "label": name.replace("_", " ").title(), "permissions": list(perms),
                      "preset": True, "customised": False} for name, perms in ROLE_PRESETS.items()}
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM cc_roles").fetchall()
        for row in rows:
            perms = [p for p in json.loads(row["permissions_json"] or "[]") if p in PERMISSIONS]
            if row["name"] == "super_admin":
                continue  # the Owner role always has everything
            base = out.get(row["name"])
            out[row["name"]] = {"name": row["name"], "label": row["label"] or row["name"], "permissions": perms,
                                "preset": bool(base), "customised": True, "updated_by": row["updated_by"],
                                "updated_at": row["updated_at"]}
        return out

    def role_permissions(self, role: str) -> Optional[List[str]]:
        item = self.roles().get(role)
        return list(item["permissions"]) if item else None

    def save_role(self, name: str, label: str, permissions: Iterable[str], actor: str) -> Dict[str, Any]:
        clean = sorted({p for p in permissions if p in PERMISSIONS})
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO cc_roles(name,label,permissions_json,updated_by,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(name) DO UPDATE SET label=excluded.label, permissions_json=excluded.permissions_json, "
                "updated_by=excluded.updated_by, updated_at=excluded.updated_at",
                (name, label, json.dumps(clean), actor, _now()))
        return self.roles()[name]

    def reset_role(self, name: str) -> bool:
        with self._connect() as conn:
            return conn.execute("DELETE FROM cc_roles WHERE name=?", (name,)).rowcount > 0

    # ------------------------------------------------------- no-match queue --

    def record_no_match(self, demand: Dict[str, Any], source_status: Dict[str, str]) -> bool:
        """One queue row per request (repeat views of the same request never
        duplicate it). Returns True when a new row was created."""
        now = _now()
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT OR IGNORE INTO no_match_events(demand_id,subject,domain,location_text,source_status_json,status,created_at,updated_at) VALUES(?,?,?,?,?,'OPEN',?,?)",
                (int(demand["id"]), demand.get("subject"), demand.get("domain"), demand.get("location_text"),
                 json.dumps(source_status), now, now),
            )
            return cur.rowcount == 1

    def demand_gaps(self, min_count: int = 1, limit: int = 100) -> List[Dict[str, Any]]:
        """Repeated unmet demand by category + area (where to recruit
        providers). Built only from real no-match events."""
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT UPPER(COALESCE(domain,'')) AS category,
                       LOWER(TRIM(COALESCE(location_text,''))) AS area,
                       COUNT(*) AS requests,
                       COUNT(DISTINCT LOWER(TRIM(subject))) AS distinct_needs,
                       GROUP_CONCAT(DISTINCT LOWER(TRIM(subject))) AS needs,
                       SUM(CASE WHEN status='OPEN' THEN 1 ELSE 0 END) AS open_requests,
                       MAX(created_at) AS last_seen
                FROM no_match_events
                GROUP BY category, area
                HAVING COUNT(*) >= ?
                ORDER BY requests DESC, last_seen DESC
                LIMIT ?
                """,
                (int(min_count), int(limit)),
            ).fetchall()
        gaps = []
        for row in rows:
            item = dict(row)
            item["area"] = item["area"] or "unknown"
            item["needs"] = sorted(set((item.get("needs") or "").split(",")) - {""})[:10]
            gaps.append(item)
        return gaps

    def no_match_queue(self, status: str | None = None, limit: int = 100) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM no_match_events"
        params: tuple = ()
        if status:
            sql += " WHERE status=?"
            params = (status,)
        sql += " ORDER BY id DESC LIMIT ?"
        with self._connect() as conn:
            rows = conn.execute(sql, params + (max(1, min(limit, 500)),)).fetchall()
        items = []
        for row in rows:
            data = dict(row)
            data["source_status"] = json.loads(data.pop("source_status_json") or "{}")
            items.append(data)
        return items

    def update_no_match(self, event_id: int, *, status: str | None, note: str | None,
                        assigned_to: str | None) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM no_match_events WHERE id=?", (int(event_id),)).fetchone()
            if not row:
                return None
            conn.execute(
                "UPDATE no_match_events SET status=?, note=?, assigned_to=?, updated_at=? WHERE id=?",
                (status or row["status"], note if note is not None else row["note"],
                 assigned_to if assigned_to is not None else row["assigned_to"], _now(), int(event_id)),
            )
        return next((item for item in self.no_match_queue(limit=500) if item["id"] == int(event_id)), None)

    # ------------------------------------------------------ discovery usage --

    def record_discovery(self, demand_id: int, source_status: Dict[str, str]) -> None:
        now = _now()
        with self._connect() as conn:
            conn.executemany(
                # One row per request+source: re-opening the same results
                # updates the outcome instead of inflating usage counts.
                "INSERT INTO discovery_events(demand_id,source,status,created_at) VALUES(?,?,?,?) "
                "ON CONFLICT(demand_id, source) DO UPDATE SET status=excluded.status",
                [(int(demand_id), str(source), str(status), now) for source, status in source_status.items()],
            )

    # ------------------------------------------------------------ flow traces --
    # One row per customer request: what the app understood, what it asked,
    # which sources ran, what was filtered and why, what the customer got,
    # auth gates, deal stage, errors and latency. Real events only.

    def trace_upsert(self, trace_key: str, **fields: Any) -> None:
        now = _now()
        with self._connect() as conn:
            row = conn.execute("SELECT data_json FROM flow_traces WHERE trace_key=?", (trace_key,)).fetchone()
            data = json.loads(row["data_json"]) if row else {}
            stage = fields.pop("stage", None)
            deal_id = fields.pop("deal_id", None)
            for key, value in fields.items():
                if value is None or value == "":
                    continue  # an empty list/dict is a real answer ("nothing filtered")
                data[key] = value
            if stage:
                data.setdefault("timeline", []).append({"stage": stage, "at": now})
            if row:
                conn.execute(
                    "UPDATE flow_traces SET data_json=?, stage=COALESCE(?, stage), deal_id=COALESCE(?, deal_id), updated_at=? WHERE trace_key=?",
                    (json.dumps(data, ensure_ascii=False), stage, deal_id, now, trace_key),
                )
            else:
                conn.execute(
                    "INSERT INTO flow_traces(trace_key,deal_id,data_json,stage,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    (trace_key, deal_id, json.dumps(data, ensure_ascii=False), stage, now, now),
                )
                # Guest browsing is public: keep the trace table bounded.
                conn.execute(
                    "DELETE FROM flow_traces WHERE id <= (SELECT id FROM flow_traces ORDER BY id DESC LIMIT 1 OFFSET ?)",
                    (TRACE_KEEP,),
                )

    def trace_event(self, trace_key: str, event: dict[str, Any], *, limit: int = 40) -> bool:
        """Append one app event (result selected, action attempted, its
        outcome, a location/auth failure) to an EXISTING trace only."""
        now = _now()
        with self._connect() as conn:
            row = conn.execute("SELECT data_json FROM flow_traces WHERE trace_key=?", (trace_key,)).fetchone()
            if not row:
                return False
            data = json.loads(row["data_json"])
            events = data.setdefault("events", [])
            events.append({**event, "at": now})
            del events[:-limit]
            conn.execute("UPDATE flow_traces SET data_json=?, updated_at=? WHERE trace_key=?",
                         (json.dumps(data, ensure_ascii=False), now, trace_key))
            return True

    def trace_stage_for_deal(self, deal_id: Any, stage: str, **fields: Any) -> None:
        """Advance the business stage (request sent, accepted, disputed...)."""
        try:
            demand_id = int(deal_id)
        except (TypeError, ValueError):
            return
        self.trace_upsert(f"deal:{demand_id}", deal_id=demand_id, stage=stage, **fields)

    def _trace_row(self, row) -> Dict[str, Any]:
        return {"id": row["id"], "trace_key": row["trace_key"], "deal_id": row["deal_id"], "stage": row["stage"],
                "created_at": row["created_at"], "updated_at": row["updated_at"], **json.loads(row["data_json"] or "{}")}

    def traces(self, limit: int = 100, stage: str | None = None) -> List[Dict[str, Any]]:
        sql, params = "SELECT * FROM flow_traces", ()
        if stage:
            sql, params = sql + " WHERE stage=?", (stage,)
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY updated_at DESC, id DESC LIMIT ?", params + (max(1, min(limit, 500)),)).fetchall()
        return [self._trace_row(row) for row in rows]

    def trace(self, trace_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM flow_traces WHERE id=?", (int(trace_id),)).fetchone()
        return self._trace_row(row) if row else None

    # ------------------------------------------------------ integration checks --

    def save_check(self, name: str, ok: bool, detail: str) -> Dict[str, Any]:
        now = _now()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO integration_checks(name,ok,detail,checked_at) VALUES(?,?,?,?) "
                "ON CONFLICT(name) DO UPDATE SET ok=excluded.ok, detail=excluded.detail, checked_at=excluded.checked_at",
                (name, int(ok), detail[:300], now),
            )
        return {"name": name, "ok": ok, "detail": detail[:300], "checked_at": now}

    def checks(self) -> Dict[str, Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM integration_checks").fetchall()
        return {row["name"]: {**dict(row), "ok": bool(row["ok"])} for row in rows}

    # --------------------------------------------------------- notifications --

    def notify_once(self, event_key: str, kind: str, title: str, entity_id: Any = None) -> bool:
        """Admin notification for an event, at most once per event_key."""
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT OR IGNORE INTO admin_notifications(event_key,kind,title,entity_id,read,created_at) VALUES(?,?,?,?,0,?)",
                (event_key, kind, title[:200], None if entity_id is None else str(entity_id), _now()),
            )
            return cur.rowcount == 1

    def notifications(self, unread_only: bool = False, limit: int = 100) -> List[Dict[str, Any]]:
        sql = "SELECT * FROM admin_notifications" + (" WHERE read=0" if unread_only else "") + " ORDER BY id DESC LIMIT ?"
        with self._connect() as conn:
            rows = conn.execute(sql, (max(1, min(limit, 500)),)).fetchall()
        return [{**dict(row), "read": bool(row["read"])} for row in rows]

    def mark_read(self, notification_id: int) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE admin_notifications SET read=1 WHERE id=?", (int(notification_id),))
