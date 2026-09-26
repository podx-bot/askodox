"""ASKODOX Admin Command Center API (Phases 18-23).

Every endpoint enforces a permission server-side. Callers authenticate with
either the owner key (``X-ASKODOX-Admin-Key`` = ADMIN_SEED_KEY, full access)
or a staff token (``X-ASKODOX-Staff-Token``) whose permissions an admin
grants/revokes. Secrets are never returned: integrations report only
configured / not configured / enabled / disabled / last check result.
All data is read from the real tables; nothing here is demo data.
"""
from __future__ import annotations

import csv
import hmac
import io
import os
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.repositories.command_center_repository import (
    ESCALATION_STATUSES,
    FEATURE_FLAGS,
    NO_MATCH_STATUSES,
    PERMISSIONS,
    ROLE_PRESETS,
    CommandCenterRepository,
    mask_user_id,
)
from app.repositories.hybrid_support_repository import SupportEscalationRepository

router = APIRouter(prefix="/admin/cc", tags=["command-center"])

JOB_DOMAINS = ("WORK", "WORKERS", "JOBS", "JOB")
MOBILITY_DOMAINS = ("RIDE", "MOBILITY", "DELIVERY", "COURIER", "PARCEL")


# -------------------------------------------------------------- plumbing --

def command_center(container: Any) -> CommandCenterRepository:
    repo = getattr(container, "command_center_repository", None)
    if repo is None:
        repo = CommandCenterRepository(container.settings.database_path)
        container.command_center_repository = repo
    return repo


def feature_enabled(container: Any, key: str) -> bool:
    """Admin feature flag (defaults to enabled; never raises)."""
    try:
        return command_center(container).is_enabled(key)
    except Exception:
        return True


def _escalations(container: Any) -> SupportEscalationRepository:
    repo = getattr(container, "support_escalation_repository", None)
    if repo is None:
        repo = SupportEscalationRepository(container.settings.database_path)
        container.support_escalation_repository = repo
    return repo


def _principal(request: Request) -> dict[str, Any]:
    container: Any = request.app.state.container
    owner_key = str(getattr(container.settings, "admin_seed_key", "") or "").strip()
    sent_key = (request.headers.get("x-askodox-admin-key") or "").strip()
    if owner_key and sent_key and hmac.compare_digest(sent_key, owner_key):
        return {"id": "owner", "name": "Owner", "role": "super_admin", "permissions": set(PERMISSIONS)}
    staff = command_center(container).staff_by_token((request.headers.get("x-askodox-staff-token") or "").strip())
    if staff:
        return {"id": f"staff-{staff['id']}", "name": staff["name"], "role": staff["role"],
                "permissions": set(staff["permissions"])}
    raise HTTPException(status_code=401, detail="Command Center sign-in required")


def _require(request: Request, permission: str) -> dict[str, Any]:
    principal = _principal(request)
    if permission not in principal["permissions"]:
        raise HTTPException(status_code=403, detail=f"Missing permission: {permission}")
    return principal


def _db(request: Request):
    return request.app.state.container.database


def _rows(request: Request, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
    try:
        return [dict(row) for row in _db(request).fetchall(sql, params)]
    except Exception:
        return []  # table not present in this deployment


def _scalar(request: Request, sql: str, params: tuple = ()) -> int:
    rows = _rows(request, sql, params)
    if not rows:
        return 0
    return int(next(iter(rows[0].values())) or 0)


def _require_confirm(confirm: bool, what: str) -> None:
    if not confirm:
        raise HTTPException(status_code=409, detail=f"Confirmation required to {what}")


# ------------------------------------------------------------------ me --

@router.get("/me")
def me(request: Request) -> dict[str, Any]:
    principal = _principal(request)
    return {**principal, "permissions": sorted(principal["permissions"])}


# ------------------------------------------------------------ overview --

@router.get("/overview")
def overview(request: Request) -> dict[str, Any]:
    _require(request, "overview:view")
    container = request.app.state.container
    cc = command_center(container)
    users = _participants(request)
    return {
        "participants": {role: len(ids) for role, ids in users.items()},
        "requests": {
            "active": _scalar(request, "SELECT COUNT(*) FROM universal_need_offer_records WHERE status='ACTIVE'"),
            "total": _scalar(request, "SELECT COUNT(*) FROM universal_need_offer_records"),
        },
        "orders": {row["status"]: row["n"] for row in _rows(request, "SELECT status, COUNT(*) n FROM orders GROUP BY status")},
        "listings": {
            "active": _scalar(request, "SELECT COUNT(*) FROM seller_products WHERE active=1"),
            "disabled": _scalar(request, "SELECT COUNT(*) FROM seller_products WHERE active=0"),
        },
        "support_open": len([e for e in _escalations(container).list(limit=500) if e["status"] not in ("RESOLVED", "CLOSED")]),
        "no_match_open": len(cc.no_match_queue(status="OPEN", limit=500)),
        "unread_notifications": len(cc.notifications(unread_only=True, limit=500)),
    }


def _participants(request: Request) -> dict[str, set[str]]:
    people: dict[str, set[str]] = defaultdict(set)
    for row in _rows(request, "SELECT user_id, side, domain FROM universal_need_offer_records"):
        side, domain, user = str(row.get("side") or "").upper(), str(row.get("domain") or "").upper(), row.get("user_id")
        if not user:
            continue
        if side == "NEED":
            people["buyers"].add(user)
        elif domain in JOB_DOMAINS:
            people["job_seekers"].add(user)
        elif domain in MOBILITY_DOMAINS:
            people["delivery_ride"].add(user)
        elif domain in ("SERVICES", "SERVICE"):
            people["service_providers"].add(user)
        else:
            people["sellers"].add(user)
    for row in _rows(request, "SELECT buyer_user_id FROM orders"):
        if row.get("buyer_user_id"):
            people["buyers"].add(row["buyer_user_id"])
    for row in _rows(request, "SELECT seller_user_id, tier, is_service_provider FROM seller_profiles"):
        target = "service_providers" if row.get("is_service_provider") or row.get("tier") == "service_provider" else "sellers"
        people[target].add(row["seller_user_id"])
    for row in _rows(request, "SELECT DISTINCT seller_user_id FROM seller_products"):
        if row.get("seller_user_id") and row["seller_user_id"] not in people["service_providers"]:
            people["sellers"].add(row["seller_user_id"])
    for key in ("buyers", "sellers", "service_providers", "job_seekers", "delivery_ride"):
        people.setdefault(key, set())
    return people


# --------------------------------------------------------------- users --

@router.get("/users")
def users(request: Request, role: str = "all") -> dict[str, Any]:
    _require(request, "users:view")
    people = _participants(request)
    listing_counts = {row["seller_user_id"]: row for row in _rows(
        request,
        "SELECT seller_user_id, SUM(active=1) active_listings, SUM(active=0) disabled_listings FROM seller_products GROUP BY seller_user_id")}
    items = []
    for group, ids in people.items():
        if role != "all" and role != group:
            continue
        for user in sorted(ids):
            counts = listing_counts.get(user, {})
            items.append({
                "user": mask_user_id(user),
                "user_ref": _ref(user),
                "role": group,
                "active_listings": int(counts.get("active_listings") or 0),
                "disabled_listings": int(counts.get("disabled_listings") or 0),
            })
    return {"items": items}


def _ref(user_id: str) -> str:
    """Opaque reference so staff can act on a user without seeing contact."""
    import hashlib

    return hashlib.sha256(f"askodox-user:{user_id}".encode()).hexdigest()[:16]


class ListingsToggle(BaseModel):
    active: bool
    reason: str = Field(default="", max_length=500)
    confirm: bool = False


@router.post("/users/{user_ref}/listings")
def toggle_user_listings(user_ref: str, payload: ListingsToggle, request: Request) -> dict[str, Any]:
    principal = _require(request, "users:manage")
    if not payload.active:
        _require_confirm(payload.confirm, "disable all listings of this seller")
        if not payload.reason.strip():
            raise HTTPException(status_code=422, detail="A reason is required to disable a seller")
    sellers = {_ref(row["seller_user_id"]): row["seller_user_id"]
               for row in _rows(request, "SELECT DISTINCT seller_user_id FROM seller_products")}
    seller = sellers.get(user_ref)
    if not seller:
        raise HTTPException(status_code=404, detail="Seller not found")
    _db(request).execute("UPDATE seller_products SET active=? WHERE seller_user_id=?", (int(payload.active), seller))
    command_center(request.app.state.container).audit(
        principal["id"], "seller_listings_" + ("enabled" if payload.active else "disabled"), "seller",
        mask_user_id(seller), reason=payload.reason)
    return {"user": mask_user_id(seller), "active": payload.active}


# ----------------------------------------------------- requests / orders --

@router.get("/requests")
def requests_list(request: Request, status: str = "", domain: str = "", limit: int = 100) -> dict[str, Any]:
    _require(request, "requests:view")
    clauses, params = [], []
    if status:
        clauses.append("status=?")
        params.append(status.upper())
    if domain:
        clauses.append("domain=?")
        params.append(domain.upper())
    sql = "SELECT id,user_id,side,domain,subject,quantity,unit,price,location_text,status,created_at FROM universal_need_offer_records"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY id DESC LIMIT ?"
    params.append(max(1, min(limit, 500)))
    rows = _rows(request, sql, tuple(params))
    for row in rows:
        row["user"] = mask_user_id(row.pop("user_id", ""))
    return {"items": rows}


class RequestUpdate(BaseModel):
    status: str
    reason: str = Field(default="", max_length=500)
    confirm: bool = False


@router.patch("/requests/{request_id}")
def update_request(request_id: int, payload: RequestUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "requests:manage")
    status = payload.status.upper()
    if status not in ("ACTIVE", "CLOSED", "CANCELLED"):
        raise HTTPException(status_code=422, detail="status must be ACTIVE, CLOSED or CANCELLED")
    if status != "ACTIVE":
        _require_confirm(payload.confirm, f"mark request {request_id} {status}")
    before = _rows(request, "SELECT status FROM universal_need_offer_records WHERE id=?", (request_id,))
    if not before:
        raise HTTPException(status_code=404, detail="Request not found")
    _db(request).execute("UPDATE universal_need_offer_records SET status=? WHERE id=?", (status, request_id))
    command_center(request.app.state.container).audit(
        principal["id"], "request_status", "request", request_id, before[0], {"status": status}, payload.reason)
    return {"id": request_id, "status": status}


@router.get("/orders")
def orders(request: Request, status: str = "", limit: int = 100) -> dict[str, Any]:
    _require(request, "requests:view")
    sql = "SELECT id,buyer_user_id,seller_user_id,product_title,quantity,unit,price,total_amount,status,created_at FROM orders"
    params: tuple = ()
    if status:
        sql += " WHERE status=?"
        params = (status.upper(),)
    rows = _rows(request, sql + " ORDER BY id DESC LIMIT ?", params + (max(1, min(limit, 500)),))
    for row in rows:
        # Contact stays hidden in admin views too (only masked refs).
        row["buyer"] = mask_user_id(row.pop("buyer_user_id", ""))
        row["seller"] = mask_user_id(row.pop("seller_user_id", ""))
    return {"items": rows}


# ------------------------------------------------ listings / categories --

@router.get("/listings")
def listings(request: Request, q: str = "", active: str = "", limit: int = 100) -> dict[str, Any]:
    _require(request, "catalog:view")
    clauses, params = [], []
    if q.strip():
        clauses.append("(lower(subject) LIKE ? OR lower(COALESCE(brand,'')) LIKE ? OR lower(COALESCE(category_tag,'')) LIKE ?)")
        params += [f"%{q.strip().lower()}%"] * 3
    if active in ("0", "1"):
        clauses.append("active=?")
        params.append(int(active))
    sql = "SELECT id,seller_user_id,subject,brand,variant,price,unit,stock_status,category_tag,location_label,active,updated_at FROM seller_products"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    rows = _rows(request, sql + " ORDER BY id DESC LIMIT ?", tuple(params) + (max(1, min(limit, 500)),))
    for row in rows:
        row["seller"] = mask_user_id(row.pop("seller_user_id", ""))
        row["active"] = bool(row.get("active"))
    return {"items": rows}


class ListingUpdate(BaseModel):
    active: bool
    reason: str = Field(default="", max_length=500)
    confirm: bool = False


@router.patch("/listings/{listing_id}")
def update_listing(listing_id: int, payload: ListingUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "catalog:manage")
    if not payload.active:
        _require_confirm(payload.confirm, f"disable listing {listing_id}")
        if not payload.reason.strip():
            raise HTTPException(status_code=422, detail="A moderation reason is required to disable a listing")
    before = _rows(request, "SELECT active FROM seller_products WHERE id=?", (listing_id,))
    if not before:
        raise HTTPException(status_code=404, detail="Listing not found")
    _db(request).execute("UPDATE seller_products SET active=? WHERE id=?", (int(payload.active), listing_id))
    command_center(request.app.state.container).audit(
        principal["id"], "listing_" + ("enabled" if payload.active else "disabled"), "listing", listing_id,
        before[0], {"active": payload.active}, payload.reason)
    return {"id": listing_id, "active": payload.active}


@router.get("/categories")
def categories(request: Request) -> dict[str, Any]:
    _require(request, "catalog:view")
    demand = {row["domain"]: row["n"] for row in _rows(
        request, "SELECT domain, COUNT(*) n FROM universal_need_offer_records GROUP BY domain")}
    supply = {row["category"]: row["n"] for row in _rows(
        request, "SELECT COALESCE(category_tag,'uncategorised') category, COUNT(*) n FROM seller_products WHERE active=1 GROUP BY category")}
    no_match = Counter(str(item.get("domain") or "") for item in command_center(request.app.state.container).no_match_queue(limit=500))
    return {"demand_by_domain": demand, "listings_by_category": supply, "no_match_by_domain": dict(no_match)}


# ------------------------------------------------------ support / disputes --

@router.get("/escalations")
def escalations(request: Request, status: str = "", category: str = "") -> dict[str, Any]:
    _require(request, "support:view")
    items = _escalations(request.app.state.container).list(status=status.upper() or None, category=category or None)
    for item in items:
        item["requester"] = mask_user_id(item.pop("requester_user_id", ""))
    return {"items": items}


@router.get("/escalations/{escalation_id}")
def escalation(escalation_id: int, request: Request) -> dict[str, Any]:
    _require(request, "support:view")
    item = _escalations(request.app.state.container).get(escalation_id)
    if not item:
        raise HTTPException(status_code=404, detail="Escalation not found")
    item["requester"] = mask_user_id(item.pop("requester_user_id", ""))
    return item


class EscalationUpdate(BaseModel):
    status: str | None = None
    assigned_to: str | None = Field(default=None, max_length=120)
    resolution_note: str | None = Field(default=None, max_length=2000)
    confirm: bool = False


@router.patch("/escalations/{escalation_id}")
def update_escalation(escalation_id: int, payload: EscalationUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "support:manage")
    repo = _escalations(request.app.state.container)
    before = repo.get(escalation_id)
    if not before:
        raise HTTPException(status_code=404, detail="Escalation not found")
    status = payload.status.upper() if payload.status else None
    if status and status not in ESCALATION_STATUSES:
        raise HTTPException(status_code=422, detail=f"status must be one of {', '.join(ESCALATION_STATUSES)}")
    if status in ("RESOLVED", "CLOSED"):
        _require_confirm(payload.confirm, f"mark escalation {escalation_id} {status}")
        if not (payload.resolution_note or before.get("resolution_note") or "").strip():
            raise HTTPException(status_code=422, detail="A resolution note is required to resolve or close")
    updated = repo.update(escalation_id, status=status, assigned_to=payload.assigned_to,
                          resolution_note=payload.resolution_note)
    command_center(request.app.state.container).audit(
        principal["id"], "escalation_update", "escalation", escalation_id,
        {k: before.get(k) for k in ("status", "assigned_to")},
        {k: updated.get(k) for k in ("status", "assigned_to")}, payload.resolution_note or "")
    updated["requester"] = mask_user_id(updated.pop("requester_user_id", ""))
    return updated


# ----------------------------------------------------------- no-match --

@router.get("/no-match")
def no_match(request: Request, status: str = "") -> dict[str, Any]:
    _require(request, "nomatch:view")
    return {"items": command_center(request.app.state.container).no_match_queue(status=status or None),
            "statuses": list(NO_MATCH_STATUSES)}


class NoMatchUpdate(BaseModel):
    status: str | None = None
    note: str | None = Field(default=None, max_length=2000)
    assigned_to: str | None = Field(default=None, max_length=120)


@router.patch("/no-match/{event_id}")
def update_no_match(event_id: int, payload: NoMatchUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "nomatch:manage")
    status = payload.status.upper() if payload.status else None
    if status and status not in NO_MATCH_STATUSES:
        raise HTTPException(status_code=422, detail=f"status must be one of {', '.join(NO_MATCH_STATUSES)}")
    cc = command_center(request.app.state.container)
    updated = cc.update_no_match(event_id, status=status, note=payload.note, assigned_to=payload.assigned_to)
    if not updated:
        raise HTTPException(status_code=404, detail="No-match item not found")
    cc.audit(principal["id"], "no_match_update", "no_match", event_id, None,
             {"status": updated["status"]}, payload.note or "")
    return updated


# -------------------------------------------------------- notifications --

@router.get("/notifications")
def notifications(request: Request, unread: bool = False) -> dict[str, Any]:
    _require(request, "notifications:view")
    return {"items": command_center(request.app.state.container).notifications(unread_only=unread)}


@router.post("/notifications/{notification_id}/read")
def read_notification(notification_id: int, request: Request) -> dict[str, Any]:
    _require(request, "notifications:view")
    command_center(request.app.state.container).mark_read(notification_id)
    return {"id": notification_id, "read": True}


# ---------------------------------------------------------- configuration --

@router.get("/config")
def config(request: Request) -> dict[str, Any]:
    _require(request, "config:view")
    container = request.app.state.container
    flags = command_center(container).flags()
    integrations = {item["name"]: item for item in _integration_states(container)}
    needs = {
        "results.nearby_external": "google_maps",
        "results.online": "brave_search",
        "results.used": "brave_search",
        "results.surplus": "brave_search",
        "results.deals": "brave_search",
        "results.videos": "brave_search",
        "results.affiliate": "affiliate_sources",
        "voice.sarvam_tts": "sarvam",
        "payments.subscriptions": "payments",
    }
    for key, flag in flags.items():
        integration = needs.get(key)
        flag["requires"] = integration
        flag["integration_configured"] = None if integration is None else integrations[integration]["configured"]
    return {"flags": list(flags.values())}


class FlagUpdate(BaseModel):
    enabled: bool
    confirm: bool = False


@router.put("/config/{key}")
def update_config(key: str, payload: FlagUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "config:manage")
    if key not in FEATURE_FLAGS:
        raise HTTPException(status_code=404, detail="Unknown setting")
    if not payload.enabled:
        _require_confirm(payload.confirm, f"disable {key}")
    cc = command_center(request.app.state.container)
    before = cc.flags()[key]["enabled"]
    flag = cc.set_flag(key, payload.enabled, principal["id"])
    cc.audit(principal["id"], "config_update", "feature_flag", key, {"enabled": before}, {"enabled": payload.enabled})
    return flag


# ---------------------------------------------------------- integrations --

def _integration_states(container: Any) -> list[dict[str, Any]]:
    settings = container.settings
    cc = command_center(container)
    flags = cc.flags()
    checks = cc.checks()
    affiliate = getattr(container, "affiliate_provider_config", None)
    affiliate_count = 0
    try:
        affiliate_count = len([p for p in (getattr(affiliate, "providers", None) or {}).values()
                               if (p or {}).get("active", True)]) if affiliate is not None else 0
    except Exception:
        affiliate_count = 0

    def state(name, label, configured, flag_keys=(), detail=""):
        enabled = all(flags[k]["enabled"] for k in flag_keys) if flag_keys else True
        check = checks.get(name)
        if not configured:
            status = "not_configured"
        elif not enabled:
            status = "disabled"
        elif check is None:
            status = "configured"  # present but not verified -- never "connected"
        else:
            status = "ok" if check["ok"] else "error"
        return {"name": name, "label": label, "configured": bool(configured), "enabled": enabled,
                "status": status, "last_check": check, "detail": detail, "flags": list(flag_keys)}

    return [
        state("google_maps", "Google Maps / Places (nearby shops)", bool(settings.google_maps_api_key),
              ("results.nearby_external",)),
        state("brave_search", "Brave web + video discovery", bool(settings.brave_search_api_key),
              ("results.online",)),
        state("sarvam", "Sarvam voice (STT saaras / TTS Bulbul v3)", bool(settings.sarvam_api_key),
              ("voice.sarvam_tts",)),
        state("gemini", "Gemini AI / voice fallback", bool(settings.gemini_api_key), ("ai.assistant",)),
        state("openai", "OpenAI vision/text", bool(settings.openai_api_key)),
        state("whatsapp", "WhatsApp Cloud API (support channel)",
              bool(settings.whatsapp_access_token and settings.whatsapp_phone_number_id)),
        state("support_channels", "Support WhatsApp / phone numbers",
              bool(os.getenv("SUPPORT_WHATSAPP_NUMBER", "").strip() or os.getenv("SUPPORT_PHONE_NUMBER", "").strip()),
              ("support.escalation",)),
        state("affiliate_sources", "Affiliate / online partner sources", affiliate_count > 0,
              ("results.affiliate",), detail=f"{affiliate_count} active provider(s)"),
        # No payment gateway exists in this codebase: reported, not invented.
        state("payments", "Payment gateway", False, ("payments.subscriptions",),
              detail="No payment gateway is integrated in this build"),
    ]


@router.get("/integrations")
def integrations(request: Request) -> dict[str, Any]:
    _require(request, "integrations:view")
    return {"items": _integration_states(request.app.state.container)}


@router.post("/integrations/{name}/check")
def check_integration(name: str, request: Request) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    container = request.app.state.container
    states = {item["name"]: item for item in _integration_states(container)}
    if name not in states:
        raise HTTPException(status_code=404, detail="Unknown integration")
    if not states[name]["configured"]:
        raise HTTPException(status_code=409, detail="Integration is not configured")
    ok, detail = False, "No live check is available for this integration"
    try:
        if name == "brave_search":
            provider = getattr(container, "brave_web_search_provider", None)
            rows = provider("ASKODOX marketplace", 1) if provider else []
            ok, detail = bool(rows), "Web search returned results" if rows else "Web search returned nothing or failed"
        elif name == "google_maps":
            maps = getattr(container, "google_maps_service", None)
            place = maps.geocode("Vijayawada") if maps else None
            ok, detail = place is not None, "Geocoding OK" if place else "Geocoding failed"
        elif name == "sarvam":
            result = container.voice_assistant_service.synthesize("ASKODOX") or {}
            ok = bool(result.get("success")) and str(result.get("tts_path") or "").startswith("sarvam")
            detail = "Bulbul v3 synthesis OK" if ok else f"Sarvam TTS: {result.get('status')}"
        else:
            return {**states[name], "checked": False}
    except Exception as error:  # a failed check is recorded, never raised to the UI
        ok, detail = False, f"{type(error).__name__}"
    cc = command_center(container)
    cc.save_check(name, ok, detail)
    cc.audit(principal["id"], "integration_check", "integration", name, None, {"ok": ok})
    item = next(i for i in _integration_states(container) if i["name"] == name)
    return {"item": item, "checked": True}


# ------------------------------------------------------------- payments --

@router.get("/payments")
def payments(request: Request) -> dict[str, Any]:
    _require(request, "payments:view")
    container = request.app.state.container
    return {
        "gateway": next(i for i in _integration_states(container) if i["name"] == "payments"),
        "subscriptions_enabled": feature_enabled(container, "payments.subscriptions"),
    }


# ------------------------------------------------------------ analytics --

def _since(days: int) -> str:
    # Date-only bound: compares correctly with both ISO ("...T...") and
    # SQLite ("... ...") timestamps stored by different tables.
    return (datetime.now(timezone.utc) - timedelta(days=max(1, min(days, 365)))).date().isoformat()


def _analytics(request: Request, days: int, domain: str) -> dict[str, Any]:
    since = _since(days)
    domain_clause, domain_params = ("", ())
    if domain:
        domain_clause, domain_params = (" AND domain=?", (domain.upper(),))
    daily: dict[str, Counter] = defaultdict(Counter)

    def bump(rows, key, field="created_at"):
        for row in rows:
            day = str(row.get(field) or "")[:10]
            if day:
                daily[day][key] += 1

    requests_rows = _rows(request, "SELECT created_at, domain FROM universal_need_offer_records WHERE created_at>=?" + domain_clause, (since,) + domain_params)
    bump(requests_rows, "requests")
    interest_rows = _rows(request, "SELECT created_at, responder_status, requester_status FROM universal_interests WHERE created_at>=?", (since,))
    bump([r for r in interest_rows if str(r.get("responder_status")).upper() == "INTERESTED"], "matches")
    declined = [r for r in interest_rows if "DECLIN" in str(r.get("requester_status")).upper()
                or "DECLIN" in str(r.get("responder_status")).upper() or "REJECT" in str(r.get("requester_status")).upper()]
    cc = command_center(request.app.state.container)
    no_match = [e for e in cc.no_match_queue(limit=500) if e["created_at"] >= since and (not domain or str(e.get("domain")).upper() == domain.upper())]
    bump(no_match, "no_match")
    joins = _rows(request, "SELECT created_at FROM seller_profiles WHERE created_at>=?", (since,))
    bump(joins, "seller_joins")
    escalations = [e for e in _escalations(request.app.state.container).list(limit=500) if e["created_at"] >= since]
    bump(escalations, "escalations")
    orders_rows = _rows(request, "SELECT status, created_at FROM orders WHERE created_at>=?", (since,))
    bump(orders_rows, "orders")
    source_usage = _rows(request, "SELECT source, status, COUNT(*) n FROM discovery_events WHERE created_at>=? GROUP BY source, status", (since,))
    return {
        "days": days,
        "domain": domain or None,
        "totals": {
            "requests": len(requests_rows),
            "successful_matches": len([r for r in interest_rows if str(r.get("responder_status")).upper() == "INTERESTED"]),
            "no_match_requests": len(no_match),
            "declined_requests": len(declined),
            "seller_provider_joins": len(joins),
            "orders": len(orders_rows),
            "rejected_orders": len([o for o in orders_rows if str(o.get("status")).upper() in ("REJECTED", "DECLINED")]),
            "support_escalations": len(escalations),
        },
        "orders_by_status": dict(Counter(str(o.get("status")) for o in orders_rows)),
        "escalations_by_category": dict(Counter(str(e.get("category")) for e in escalations)),
        "source_usage": source_usage,
        "failures": [c for c in cc.checks().values() if not c["ok"]],
        "daily": [{"date": day, **{k: counts.get(k, 0) for k in ("requests", "matches", "no_match", "orders", "escalations", "seller_joins")}}
                  for day, counts in sorted(daily.items())],
    }


@router.get("/analytics")
def analytics(request: Request, days: int = 30, domain: str = "") -> dict[str, Any]:
    _require(request, "analytics:view")
    return _analytics(request, days, domain)


@router.get("/analytics/export.csv")
def analytics_export(request: Request, days: int = 30, domain: str = "") -> Response:
    principal = _require(request, "analytics:export")
    data = _analytics(request, days, domain)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["date", "requests", "matches", "no_match", "orders", "escalations", "seller_joins"])
    for row in data["daily"]:
        writer.writerow([row["date"], row["requests"], row["matches"], row["no_match"], row["orders"], row["escalations"], row["seller_joins"]])
    command_center(request.app.state.container).audit(principal["id"], "analytics_export", "report", f"{days}d")
    return Response(content=buffer.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": f'attachment; filename="askodox-analytics-{days}d.csv"'})


# --------------------------------------------------------------- health --

@router.get("/health")
def health(request: Request) -> dict[str, Any]:
    _require(request, "health:view")
    container = request.app.state.container
    components = [{"name": "backend_api", "status": "ok", "detail": "Command Center API responded"}]
    try:
        container.database.fetchone("SELECT 1 AS ok")
        components.append({"name": "database", "status": "ok", "detail": "SELECT 1 succeeded"})
    except Exception as error:
        components.append({"name": "database", "status": "error", "detail": type(error).__name__})
    try:
        _db(request).fetchone("SELECT COUNT(*) AS n FROM universal_need_offer_records")
        matcher = getattr(container, "universal_matcher", None)
        components.append({"name": "matching", "status": "ok" if matcher is not None else "error",
                           "detail": "Demand store readable; matcher loaded" if matcher is not None else "Matcher not loaded"})
    except Exception as error:
        components.append({"name": "matching", "status": "error", "detail": type(error).__name__})
    try:
        _escalations(container).list(limit=1)
        command_center(container).notifications(limit=1)
        components.append({"name": "support_notifications", "status": "ok", "detail": "Escalation and notification stores readable"})
    except Exception as error:
        components.append({"name": "support_notifications", "status": "error", "detail": type(error).__name__})
    for item in _integration_states(container):
        # Configured but never checked = unknown, never a dummy green.
        status = {"not_configured": "not_configured", "disabled": "disabled", "configured": "unknown",
                  "ok": "ok", "error": "error"}[item["status"]]
        components.append({"name": item["name"], "status": status, "detail": (item.get("last_check") or {}).get("detail") or item["detail"]})
    since = _since(1)
    failures = [c for c in command_center(container).checks().values() if not c["ok"]]
    try:
        failed_deliveries = container.admin_monitoring_service.failed_deliveries(limit=10)
    except Exception:
        failed_deliveries = []
    return {
        "components": components,
        "recent_failures": {
            "integration_checks": failures,
            "failed_deliveries": failed_deliveries,
            "no_match_last_24h": len([e for e in command_center(container).no_match_queue(limit=500) if e["created_at"] >= since]),
        },
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------- staff --

class StaffCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    role: str
    permissions: list[str] | None = None


class StaffUpdate(BaseModel):
    role: str | None = None
    grant: list[str] = Field(default_factory=list)
    revoke: list[str] = Field(default_factory=list)
    active: bool | None = None
    confirm: bool = False


def _no_escalation(principal: dict[str, Any], permissions) -> None:
    """A staff manager can only hand out permissions they hold themselves."""
    beyond = sorted(set(permissions) - set(principal["permissions"]))
    if beyond:
        raise HTTPException(status_code=403, detail=f"Cannot grant permissions you do not hold: {', '.join(beyond)}")


@router.get("/staff")
def staff(request: Request) -> dict[str, Any]:
    _require(request, "staff:manage")
    return {"items": command_center(request.app.state.container).list_staff(),
            "roles": {role: list(perms) for role, perms in ROLE_PRESETS.items()},
            "permissions": list(PERMISSIONS)}


@router.post("/staff")
def create_staff(payload: StaffCreate, request: Request) -> dict[str, Any]:
    principal = _require(request, "staff:manage")
    if payload.role not in ROLE_PRESETS:
        raise HTTPException(status_code=422, detail=f"role must be one of {', '.join(ROLE_PRESETS)}")
    unknown = [p for p in (payload.permissions or []) if p not in PERMISSIONS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")
    perms = payload.permissions if payload.permissions is not None else ROLE_PRESETS[payload.role]
    _no_escalation(principal, perms)
    cc = command_center(request.app.state.container)
    created = cc.create_staff(payload.name, payload.role, perms, principal["id"])
    cc.audit(principal["id"], "staff_created", "staff", created["id"], None,
             {"role": created["role"], "permissions": created["permissions"]})
    return created  # includes the one-time token


@router.patch("/staff/{staff_id}")
def update_staff(staff_id: int, payload: StaffUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "staff:manage")
    cc = command_center(request.app.state.container)
    current = cc.get_staff(staff_id)
    if not current:
        raise HTTPException(status_code=404, detail="Staff not found")
    if payload.role and payload.role not in ROLE_PRESETS:
        raise HTTPException(status_code=422, detail="Unknown role")
    unknown = [p for p in payload.grant + payload.revoke if p not in PERMISSIONS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")
    if payload.active is False:
        _require_confirm(payload.confirm, f"deactivate staff {staff_id}")
    base = set(ROLE_PRESETS[payload.role]) if payload.role else set(current["permissions"])
    permissions = (base | set(payload.grant)) - set(payload.revoke)
    _no_escalation(principal, permissions - set(current["permissions"]))
    updated = cc.update_staff(staff_id, role=payload.role, permissions=permissions, active=payload.active)
    cc.audit(principal["id"], "staff_updated", "staff", staff_id,
             {"role": current["role"], "permissions": current["permissions"], "active": current["active"]},
             {"role": updated["role"], "permissions": updated["permissions"], "active": updated["active"]})
    return updated


# ---------------------------------------------------------------- audit --

@router.get("/audit")
def audit(request: Request, limit: int = 100) -> dict[str, Any]:
    _require(request, "audit:view")
    return {"items": command_center(request.app.state.container).audit_log(limit=limit)}
