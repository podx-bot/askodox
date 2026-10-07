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
from app.services import governance as gov

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
        from app.repositories.command_center_repository import FLAG_DEFAULTS

        return FLAG_DEFAULTS.get(key, True)


def _escalations(container: Any) -> SupportEscalationRepository:
    repo = getattr(container, "support_escalation_repository", None)
    if repo is None:
        repo = SupportEscalationRepository(container.settings.database_path)
        container.support_escalation_repository = repo
    return repo


AUTH_FAIL_LIMIT = 10          # wrong keys / tokens per client ...
AUTH_FAIL_WINDOW = 600        # ... per 10 minutes, then locked out for the window


def _principal(request: Request) -> dict[str, Any]:
    from app.services import rate_limit

    container: Any = request.app.state.container
    owner_key = str(getattr(container.settings, "admin_seed_key", "") or "").strip()
    sent_key = (request.headers.get("x-askodox-admin-key") or "").strip()
    sent_token = (request.headers.get("x-askodox-staff-token") or "").strip()
    # Brute-force guard: after repeated wrong credentials this client is
    # refused BEFORE any comparison, so guessing cannot continue.
    if (sent_key or sent_token) and rate_limit.blocked(request, "cc_auth_fail", limit=AUTH_FAIL_LIMIT,
                                                        window_seconds=AUTH_FAIL_WINDOW):
        raise HTTPException(status_code=429, detail="Too many failed sign-in attempts. Try again later.")
    if owner_key and sent_key and hmac.compare_digest(sent_key, owner_key):
        return {"id": "owner", "name": "Owner", "role": "super_admin", "permissions": set(PERMISSIONS)}
    staff = command_center(container).staff_by_token(sent_token)
    sent_session = (request.headers.get("x-askodox-staff-session") or "").strip()
    if staff is None and sent_session:
        # Short-lived session from a phone / app sign-in (OTP-verified number).
        from app.services import staff_sessions

        staff_id = staff_sessions.verify(sent_session, container.settings.session_token_secret)
        candidate = command_center(container).get_staff(staff_id) if staff_id else None
        staff = candidate if candidate and candidate["active"] else None
        if staff is None:
            raise HTTPException(status_code=401, detail="Staff session expired -- sign in again")
    if staff:
        return {"id": f"staff-{staff['id']}", "name": staff["name"], "role": staff["role"],
                "permissions": set(staff["permissions"])}
    if sent_key or sent_token:
        rate_limit.hit(request, "cc_auth_fail")
        try:
            hour = datetime.now(timezone.utc).strftime("%Y%m%d%H")
            if rate_limit.blocked(request, "cc_auth_fail", limit=AUTH_FAIL_LIMIT, window_seconds=AUTH_FAIL_WINDOW):
                command_center(container).notify_once(f"security:auth_lockout:{hour}", "security_critical",
                                                      "Command Center: repeated wrong sign-in attempts (locked out)")
        except Exception:
            pass
    raise HTTPException(status_code=401, detail="Command Center sign-in required")


def _require(request: Request, permission: str) -> dict[str, Any]:
    """Server-side permission check (``<module>:manage`` implies create /
    edit / approve / delete). The 403 always carries the standard message."""
    principal = _principal(request)
    if not gov.has_permission(principal["permissions"], permission):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs {permission})")
    return principal


def _can(principal: dict[str, Any], permission: str) -> bool:
    return gov.has_permission(principal["permissions"], permission)


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
    held = set(principal["permissions"])
    effective = held | {f"{p.split(':')[0]}:{verb}" for p in held if p.endswith(":manage")
                        for verb in gov.IMPLIED_BY_MANAGE}
    return {**principal, "permissions": sorted(effective), "super": gov.is_super(principal)}


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
    # Business details from the user's own profile (public shop facts only;
    # personal name / phone / photo / home address stay private).
    business = {row["user_id"]: row for row in _rows(
        request, "SELECT user_id, business_name, business_category FROM user_profiles")}
    items = []
    for group, ids in people.items():
        if role != "all" and role != group:
            continue
        for user in sorted(ids):
            counts = listing_counts.get(user, {})
            shop = business.get(user, {})
            items.append({
                "user": mask_user_id(user),
                "user_ref": _ref(user),
                "role": group,
                "active_listings": int(counts.get("active_listings") or 0),
                "disabled_listings": int(counts.get("disabled_listings") or 0),
                "business_name": shop.get("business_name"),
                "business_category": shop.get("business_category"),
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
    sql = "SELECT * FROM orders"
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

def _handoff(item: dict[str, Any]) -> dict[str, Any]:
    """Stored handoff package, or one built from older tickets' context."""
    context = item.get("context") or {}
    if context.get("handoff"):
        return context["handoff"]
    from app.services import support_handoff

    return support_handoff.build(issue=item.get("issue") or "", category=item.get("category") or "", context=context)


@router.get("/escalations")
def escalations(request: Request, status: str = "", category: str = "", priority: str = "", assigned_to: str = "",
                sla: str = "", channel: str = "", q: str = "", mine: bool = False) -> dict[str, Any]:
    principal = _require(request, "support:view")
    items = _escalations(request.app.state.container).list(status=status.upper() or None, category=category or None,
                                                           limit=500, q=q.strip() or None)
    if mine:
        assigned_to = principal["id"]
    if priority:
        items = [i for i in items if i["priority"] == priority.upper()]
    if assigned_to:
        items = [i for i in items if (i.get("assigned_to") or "") == assigned_to]
    if sla:
        items = [i for i in items if i["sla_state"] == sla.upper()]
    if channel:
        items = [i for i in items if i["channel"] == channel]
    for item in items:
        item["requester"] = mask_user_id(item.pop("requester_user_id", ""))
        item["handoff"] = _handoff(item)
    summary: dict[str, int] = {}
    for item in items:
        summary[item["sla_state"]] = summary.get(item["sla_state"], 0) + 1
    return {"items": items, "sla_summary": summary}


@router.get("/escalations/{escalation_id}")
def escalation(escalation_id: int, request: Request) -> dict[str, Any]:
    _require(request, "support:view")
    item = _escalations(request.app.state.container).get(escalation_id)
    if not item:
        raise HTTPException(status_code=404, detail="Escalation not found")
    item["requester"] = mask_user_id(item.pop("requester_user_id", ""))
    item["handoff"] = _handoff(item)
    item["history"] = _escalations(request.app.state.container).history(escalation_id)
    item["thread"] = _escalations(request.app.state.container).thread(escalation_id, public_only=False)
    return item


class StaffReply(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    status: str = "WAITING_FOR_USER"
    attachments: list[str] = Field(default_factory=list, max_length=5)


_REF = __import__("re").compile(r"^[A-Za-z0-9_\-:.]{1,120}$")


@router.post("/escalations/{escalation_id}/reply")
def reply_escalation(escalation_id: int, payload: StaffReply, request: Request) -> dict[str, Any]:
    """A reply the customer sees in the app (in-app notification, plus any
    configured channel the customer did not switch off)."""
    principal = _require(request, "support:edit")
    container = request.app.state.container
    repo = _escalations(container)
    ticket = repo.get(escalation_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Escalation not found")
    if ticket["status"] == "CLOSED":
        raise HTTPException(status_code=409, detail="Reopen the ticket before replying")
    status = payload.status.upper()
    if status not in ("WAITING_FOR_USER", "IN_PROGRESS", "RESOLVED"):
        raise HTTPException(status_code=422, detail="status after a reply: WAITING_FOR_USER, IN_PROGRESS or RESOLVED")
    refs = [a for a in payload.attachments if _REF.match(a)]
    repo.add_message(escalation_id, author_kind="staff", author=principal["id"], body=payload.message,
                     attachments=refs)
    repo.mark_first_response(escalation_id)
    if status != ticket["status"]:
        repo.set_status(escalation_id, status, actor=principal["id"])
    if status == "RESOLVED" and not ticket.get("resolution_note"):
        repo.update(escalation_id, resolution_note=payload.message[:2000], actor=principal["id"])
    from app.api.routes.platform import notify

    notify(container, "support_update", ticket["requester_user_id"],
           {"ticket": escalation_id, "status": "new reply from ASKODOX support"})
    command_center(container).audit(principal["id"], "support_reply", "escalation", escalation_id,
                                    {"status": ticket["status"]}, {"status": status}, role=principal["role"])
    return escalation(escalation_id, request)


class EscalateBody(BaseModel):
    reason: str = Field(min_length=3, max_length=500)
    assigned_to: str | None = Field(default=None, max_length=120)


@router.post("/escalations/{escalation_id}/escalate")
def escalate_ticket(escalation_id: int, payload: EscalateBody, request: Request) -> dict[str, Any]:
    """Raise priority one level (tightens the SLA), optionally reassign."""
    principal = _require(request, "support:edit")
    container = request.app.state.container
    repo = _escalations(container)
    ticket = repo.get(escalation_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Escalation not found")
    order = list(repo.PRIORITIES)
    higher = order[min(order.index(ticket["priority"]) + 1, len(order) - 1)]
    repo.set_ticket_fields(escalation_id, actor=principal["id"], priority=higher, note=f"Escalated: {payload.reason}")
    if payload.assigned_to is not None:
        repo.update(escalation_id, assigned_to=payload.assigned_to, actor=principal["id"])
    cc = command_center(container)
    cc.notify_once(f"escalated:{escalation_id}:{higher}", "escalation_critical" if higher == "URGENT" else "escalation",
                   f"Ticket #{escalation_id} escalated to {higher}", str(escalation_id))
    cc.audit(principal["id"], "support_escalate", "escalation", escalation_id, {"priority": ticket["priority"]},
             {"priority": higher}, payload.reason, role=principal["role"])
    return escalation(escalation_id, request)


@router.post("/escalations/{escalation_id}/reopen")
def reopen_ticket(escalation_id: int, request: Request) -> dict[str, Any]:
    principal = _require(request, "support:edit")
    repo = _escalations(request.app.state.container)
    ticket = repo.get(escalation_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Escalation not found")
    if ticket["status"] not in ("RESOLVED", "CLOSED"):
        raise HTTPException(status_code=409, detail="Only a resolved or closed ticket can be reopened")
    repo.set_status(escalation_id, "OPEN", actor=principal["id"], action="reopened")
    command_center(request.app.state.container).audit(principal["id"], "support_reopen", "escalation", escalation_id,
                                                      {"status": ticket["status"]}, {"status": "OPEN"},
                                                      role=principal["role"])
    return escalation(escalation_id, request)


class EscalationUpdate(BaseModel):
    status: str | None = None
    assigned_to: str | None = Field(default=None, max_length=120)
    resolution_note: str | None = Field(default=None, max_length=2000)
    priority: str | None = None
    channel: str | None = None
    attachments: list[str] | None = None
    note: str | None = Field(default=None, max_length=2000)
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
    try:
        repo.set_ticket_fields(escalation_id, actor=principal["id"], priority=payload.priority,
                               channel=payload.channel, attachments=payload.attachments, note=payload.note)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None
    updated = repo.update(escalation_id, status=status, assigned_to=payload.assigned_to,
                          resolution_note=payload.resolution_note, actor=principal["id"])
    if status in ("RESOLVED", "CLOSED"):
        _resolve_linked_order(request.app.state.container, before)
    if status and status != before.get("status"):
        from app.api.routes.platform import notify

        notify(request.app.state.container, "support_update", before["requester_user_id"],
               {"ticket": escalation_id, "status": status.replace("_", " ").lower()})
    command_center(request.app.state.container).audit(
        principal["id"], "escalation_update", "escalation", escalation_id,
        {k: before.get(k) for k in ("status", "assigned_to")},
        {k: updated.get(k) for k in ("status", "assigned_to")}, payload.resolution_note or "")
    updated["requester"] = mask_user_id(updated.pop("requester_user_id", ""))
    return updated


def _resolve_linked_order(container: Any, escalation: dict[str, Any]) -> None:
    """A resolved dispute returns the deal to the customer for confirmation
    (it is not closed on the customer's behalf)."""
    order_id = (escalation.get("context") or {}).get("order_id")
    orders = getattr(container, "order_repository", None)
    if not order_id or orders is None:
        return
    order = orders.get(int(order_id))
    if order and order.get("status") == "DISPUTED":
        fields = {"status": "RESOLVED"}
        if order.get("payment_state") == "DISPUTED":
            fields["payment_state"] = "PROOF_SUBMITTED" if order.get("payment_reference") else "AWAITING_PAYMENT"
        orders.update_fields(int(order_id), **fields)


class PaymentVerification(BaseModel):
    state: str
    reason: str = Field(default="", max_length=500)
    confirm: bool = False


@router.patch("/orders/{order_id}/payment")
def verify_order_payment(order_id: int, payload: PaymentVerification, request: Request) -> dict[str, Any]:
    """Staff payment verification (UTR checked against the seller/UPI
    statement). Never automatic."""
    principal = _require(request, "payments:manage")
    container = request.app.state.container
    state = payload.state.strip().upper()
    if state not in ("VERIFIED", "FAILED"):
        raise HTTPException(status_code=422, detail="state must be VERIFIED or FAILED")
    _require_confirm(payload.confirm, f"mark payment for order {order_id} {state}")
    if not payload.reason.strip():
        raise HTTPException(status_code=422, detail="A verification note is required")
    order = container.order_repository.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.get("payment_state") not in ("PROOF_SUBMITTED", "DISPUTED"):
        raise HTTPException(status_code=409, detail="No submitted payment reference to verify")
    container.order_repository.update_fields(order_id, payment_state=state,
                                             payment_verified_by=principal["id"] if state == "VERIFIED" else None)
    command_center(container).audit(principal["id"], "payment_" + state.lower(), "order", order_id,
                                    {"payment_state": order.get("payment_state")}, {"payment_state": state},
                                    payload.reason)
    return {"id": order_id, "payment_state": state}


# --------------------------------------------------------- flow traces --

def _trace_outcome(t: dict[str, Any]) -> str:
    """The final outcome of a request, from what actually happened."""
    events = t.get("events") or []
    for event in reversed(events):
        name = event.get("event")
        if name == "action_result":
            return "action_ok" if event.get("ok") else f"action_failed:{event.get('reason') or 'unknown'}"
        if name in ("partner_opened", "partner_click"):
            return name
    if t.get("errors"):
        return "error"
    return str(t.get("stage") or "unknown")


@router.get("/traces")
def flow_traces(request: Request, stage: str = "", limit: int = 100, q: str = "", language: str = "",
                outcome: str = "", user: str = "", source: str = "", errors_only: bool = False,
                since: str = "", until: str = "", deal_id: str = "") -> dict[str, Any]:
    """Real per-request pipeline traces: query → language → intent/role/
    categories/slots → questions/answers → location → sources called and
    counts (registered / nearby / partner / web) → filtered + reasons →
    ranking → fallback → results → selected/clicked → action → auth gate /
    resume → request/order/deal id → outcome → errors → latency.
    Filters: q (query/category/title text), language, stage, outcome, user
    (masked id), source (a source that returned rows), errors_only,
    since/until (ISO dates), deal_id."""
    _require(request, "requests:view")
    items = command_center(request.app.state.container).traces(limit=500, stage=stage or None)

    def keep(t: dict[str, Any]) -> bool:
        if q:
            haystack = " ".join(str(v) for v in (t.get("query"), t.get("categories"), t.get("results"),
                                                  t.get("slots"))).casefold()
            if q.casefold() not in haystack:
                return False
        if language and language not in {str(t.get("reply_language") or ""), str(t.get("language") or "")}:
            return False
        if outcome and not _trace_outcome(t).startswith(outcome):
            return False
        if user and user != str(t.get("user") or ""):
            return False
        if source and not (t.get("source_counts") or {}).get(source):
            return False
        if errors_only and not t.get("errors"):
            return False
        if since and str(t.get("updated_at") or "") < since:
            return False
        if until and str(t.get("created_at") or "") > until + "T23:59:59":
            return False
        if deal_id and str(t.get("deal_id") or "") != deal_id:
            return False
        return True

    compact = [{
        "id": t["id"], "updated_at": t["updated_at"], "stage": t.get("stage"), "outcome": _trace_outcome(t),
        "user": t.get("user"), "query": t.get("query"),
        "language": t.get("reply_language") or t.get("language"), "intent": t.get("intent"),
        "role": t.get("active_role"), "categories": t.get("categories"),
        "attachments": [a.get("kind") for a in (t.get("attachments") or [])] or None,
        "results": t.get("results_count"), "sources": t.get("source_counts"), "fallback": t.get("fallback"),
        "auth_gate": t.get("auth_gate"), "deal_id": t.get("deal_id"), "errors": t.get("errors"),
        "latency_ms": t.get("latency_ms"), "trace_key": t.get("trace_key"),
        # Where the search actually looked, and the latest thing the customer
        # did with the results (selected / clicked / action / outcome).
        "location": (t.get("location_searched") or {}).get("label")
        or ("GPS point" if (t.get("location_searched") or {}).get("has_point") else None),
        "location_failure": (t.get("location_searched") or {}).get("failure"),
        "last_event": ((t.get("events") or [None])[-1]),
    } for t in items if keep(t)][:max(1, min(limit, 500))]
    return {"items": compact}


@router.get("/traces/{trace_id}")
def flow_trace(trace_id: int, request: Request) -> dict[str, Any]:
    _require(request, "requests:view")
    item = command_center(request.app.state.container).trace(trace_id)
    if not item:
        raise HTTPException(status_code=404, detail="Trace not found")
    return item


# ------------------------------------------------ demand gaps / API usage --

@router.get("/demand-gaps")
def demand_gaps(request: Request, min_count: int = 1) -> dict[str, Any]:
    """Unmet demand grouped by category + area: where ASKODOX should recruit
    sellers/providers. Real no-match events only."""
    _require(request, "nomatch:view")
    return {"items": command_center(request.app.state.container).demand_gaps(min_count=max(1, min_count))}


@router.get("/returns")
def returns_and_disputes(request: Request) -> dict[str, Any]:
    """Orders in return / refund / dispute states (the lifecycle audit)."""
    _require(request, "payments:view")
    rows = _rows(request, "SELECT id, product_title, status, kind, settlement_method, payment_state, total_amount, "
                          "return_reason, refund_reference, buyer_user_id, seller_user_id, updated_at FROM orders "
                          "WHERE status IN ('RETURN_REQUESTED','RETURNED','REFUND_DUE','REFUNDED','DISPUTED','RESOLVED')"
                          " ORDER BY updated_at DESC LIMIT 200")
    for row in rows:
        row["buyer_user_id"] = mask_user_id(row.get("buyer_user_id"))
        row["seller_user_id"] = mask_user_id(row.get("seller_user_id"))
    return {"items": rows}


@router.get("/api-usage")
def api_usage(request: Request) -> dict[str, Any]:
    """External API calls made by this server process (Brave, Places,
    Geocoding): real calls, cache hits and errors since the last deploy."""
    _require(request, "analytics:view")
    from app.services import external_call_budget

    costs = external_call_budget.cost_table()
    history: list[dict[str, Any]] = []
    try:
        from app.api.routes.growth import growth

        history = growth(request.app.state.container).usage(days=30)
    except Exception:
        history = []
    if history:
        totals: dict[str, dict[str, int]] = {}
        for row in history:
            t = totals.setdefault(row["provider"], {"calls": 0, "cache_hits": 0, "errors": 0})
            for k in ("calls", "cache_hits", "errors"):
                t[k] += int(row[k] or 0)
        scope = "last 30 days (persisted)"
    else:
        totals = external_call_budget.usage_snapshot()
        scope = "since last deploy (process-local)"
    items = [{"provider": name, **stats, "saved_by_cache": stats.get("cache_hits", 0),
              "est_cost_inr": round(stats.get("calls", 0) * costs.get(name, 0), 2),
              "est_saved_inr": round(stats.get("cache_hits", 0) * costs.get(name, 0), 2)}
             for name, stats in sorted(totals.items())]
    return {"items": items, "scope": scope, "daily": history[:200],
            "cost_note": "Estimated from list prices (configurable: ASKODOX_API_COST_INR); the provider bill is authoritative."}


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
    reason: str = Field(default="", max_length=500)


@router.put("/config/{key}")
def update_config(key: str, payload: FlagUpdate, request: Request) -> Any:
    principal = _require(request, "config:manage")
    if key not in FEATURE_FLAGS:
        raise HTTPException(status_code=404, detail="Unknown setting")
    risk = gov.flag_risk(key)
    if not payload.enabled or risk == gov.RED:
        _require_confirm(payload.confirm, f"{'enable' if payload.enabled else 'disable'} {key}")
    cc = command_center(request.app.state.container)
    before = cc.flags()[key]["enabled"]
    if risk != gov.GREEN and not gov.is_super(principal):
        # ORANGE: a second person approves; RED: only the Owner / Super Admin.
        return request_approval(request, principal, action="feature_flag.set", target=f"feature_flag:{key}",
                                risk=risk, reason=payload.reason, old={"enabled": before},
                                proposed={"enabled": payload.enabled},
                                params={"key": key, "enabled": payload.enabled, "needs": "config:manage"})
    flag = cc.set_flag(key, payload.enabled, principal["id"])
    cc.audit(principal["id"], "config_update", "feature_flag", key, {"enabled": before}, {"enabled": payload.enabled},
             payload.reason, role=principal["role"], risk=risk)
    return flag


# ---------------------------------------------------------- integrations --

def _integration_states(container: Any) -> list[dict[str, Any]]:
    from app.services.commerce_finance import youtube_api_key

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

    gateways: list[str] = []
    try:
        from app.api.routes.platform import platform as _platform
        from app.services import commerce_finance as fin

        for item in _platform(container).registry.all():
            if item["group"] == "payments" and not item["internal"] and item["provider"] != "sandbox_gateway" \
                    and item["status"] in (fin.STATUS_LIVE, fin.STATUS_TEST):
                gateways.append(item["label"])
    except Exception:
        gateways = []

    from app.services import provider_health

    _observed = provider_health.snapshot()
    _aliases = {"sarvam": ("sarvam_stt", "sarvam_tts")}

    def _latest(name):
        rows = [(_observed.get(n) or {}).get("last") for n in _aliases.get(name, (name,))]
        rows = [r for r in rows if r]
        return max(rows, key=lambda r: r.get("at") or "") if rows else None

    def observed_state(name):
        last = _latest(name)
        return last["outcome"] if last else None

    def observed_at(name):
        last = _latest(name)
        return last["at"] if last else None

    def state(name, label, configured, flag_keys=(), detail=""):
        enabled = all(flags[k]["enabled"] for k in flag_keys) if flag_keys else True
        check = checks.get(name)
        if not configured:
            status = "not_configured"
        elif not enabled:
            status = "disabled"
        elif observed_state(name) in ("QUOTA_EXHAUSTED", "ERROR", "LIVE") and (
                check is None or (observed_at(name) or "") >= str(check.get("at") or check.get("checked_at") or "")):
            # A real provider answer newer than the last manual check wins:
            # e.g. Sarvam HTTP 402 -> quota_exhausted, never "configured".
            status = {"QUOTA_EXHAUSTED": "quota_exhausted", "ERROR": "error", "LIVE": "ok"}[observed_state(name)]
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
        state("youtube_data_api", "YouTube Data API",
              bool(youtube_api_key()),
              detail="YouTube public-data search; key is read only from Railway environment variables"),
        state("push_notifications", "Background push (Firebase Cloud Messaging)",
              bool(os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()),
              detail="Server needs FIREBASE_SERVICE_ACCOUNT_JSON; the Android app needs google-services.json "
                     "(see docs/EXTERNAL_SETUP.md). Until then updates arrive only while the app is open."),
        # Gateways are prepared in Platform -> Integrations; "configured" only when
        # one has real credentials there (reported, not invented).
        state("payments", "Payment gateway", bool(gateways), ("payments.subscriptions",),
              detail=(f"Configured: {', '.join(gateways)}" if gateways else "No gateway configured") +
              " -- COD, cash on pickup and direct UPI to the seller work without one (Platform -> Integrations)."),
    ]


class AffiliateProviderUpdate(BaseModel):
    name: str = Field(default="", max_length=120)
    category: str = Field(default="general", max_length=80)
    normal_url: str = Field(default="", max_length=2000)
    deep_link: str = Field(default="", max_length=2000)
    api_base_url: str = Field(default="", max_length=2000)
    api_enabled: bool = False
    api_allowed_hosts: str = Field(default="", max_length=1000)
    callback_url: str = Field(default="", max_length=2000)
    callback_enabled: bool = False
    tracking_template: str = Field(default="", max_length=2000)
    gateway: str = Field(default="external", max_length=80)
    affiliate_url: str = Field(default="", max_length=2000)
    disclosure: str = Field(default="Affiliate link", max_length=200)
    active: bool = True


@router.get("/integrations/affiliate-providers")
def affiliate_providers(request: Request) -> dict[str, Any]:
    _require(request, "integrations:view")
    config = getattr(request.app.state.container, "affiliate_provider_config", None)
    return {"items": config.list() if config is not None else []}


@router.put("/integrations/affiliate-providers/{provider_id}")
def save_affiliate_provider(provider_id: str, body: AffiliateProviderUpdate, request: Request) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    config = getattr(request.app.state.container, "affiliate_provider_config", None)
    if config is None:
        raise HTTPException(status_code=503, detail="Affiliate provider registry unavailable")
    provider_id = provider_id.strip().lower()
    if not provider_id or len(provider_id) > 80:
        raise HTTPException(status_code=400, detail="Invalid provider id")
    before = dict(config.providers.get(provider_id) or {})
    config.register(provider_id, **body.model_dump())
    after = dict(config.providers[provider_id])
    command_center(request.app.state.container).audit(
        principal["id"], "affiliate_provider.save", "affiliate_provider", provider_id,
        before=before or None, after=after)
    return {"item": after}


@router.delete("/integrations/affiliate-providers/{provider_id}")
def delete_affiliate_provider(provider_id: str, request: Request, confirm: bool = False) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    _require_confirm(confirm, "delete affiliate provider")
    config = getattr(request.app.state.container, "affiliate_provider_config", None)
    if config is None:
        raise HTTPException(status_code=503, detail="Affiliate provider registry unavailable")
    before = dict(config.providers.get(provider_id) or {})
    if not config.remove(provider_id):
        raise HTTPException(status_code=404, detail="Affiliate provider not found")
    command_center(request.app.state.container).audit(
        principal["id"], "affiliate_provider.delete", "affiliate_provider", provider_id, before=before)
    return {"deleted": True, "provider_id": provider_id}


@router.get("/integrations/external-commerce-analytics")
def external_commerce_analytics(request: Request) -> dict[str, Any]:
    _require(request, "analytics:view")
    try:
        rows = _rows(request, """SELECT provider_id,event_type,COUNT(*) n,
            COALESCE(SUM(CASE WHEN event_type!='click' THEN value ELSE 0 END),0) value
            FROM external_commerce_events GROUP BY provider_id,event_type ORDER BY provider_id,event_type""")
    except Exception:
        rows = []
    providers: dict[str, dict[str, Any]] = {}
    for row in rows:
        item = providers.setdefault(row["provider_id"], {"provider_id": row["provider_id"], "clicks": 0, "conversions": 0, "value": 0.0})
        if row["event_type"] == "click":
            item["clicks"] += int(row["n"])
        else:
            item["conversions"] += int(row["n"])
            item["value"] += float(row["value"] or 0)
    return {"items": list(providers.values())}


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
            # Per API: Geocoding, Places (text + nearby), Routes are enabled
            # separately on the key's Google Cloud project.
            maps = getattr(container, "google_maps_service", None)
            status = maps.api_status() if maps is not None and hasattr(maps, "api_status") else {}
            ok = bool(status) and all(v == "OK" for v in status.values())
            detail = "; ".join(f"{api}: {verdict}" for api, verdict in status.items()) or "Maps service unavailable"
            # Integration Readiness reads the shared /health/maps cache. Persist
            # this explicit owner-triggered live probe there too, so a passed
            # Check now is immediately reflected as LIVE instead of reverting
            # to CONFIGURED NOT VERIFIED on refresh.
            if status:
                from datetime import datetime, timezone
                import time
                from app.api.routes.health import _MAPS_HEALTH, MAPS_HEALTH_TTL, _clean_google_message
                body = {"configured": True, "checked_at": datetime.now(timezone.utc).isoformat(),
                        "apis": {k: _clean_google_message(v) for k, v in status.items()},
                        "all_ok": ok}
                _MAPS_HEALTH.update(until=time.monotonic() + MAPS_HEALTH_TTL, body=body)
        elif name == "mobility":
            # Mobility matching is feature-flag gated. The runtime check is
            # truthful: it reports readiness without pretending disabled
            # production matching is live.
            flag = command_center(container).flags().get("delivery.matching", {})
            enabled = bool(flag.get("enabled"))
            ok = enabled
            detail = "delivery.matching is enabled" if enabled else "delivery.matching flag is off"
        elif name == "youtube_data_api":
            from app.services.social_video_api_service import SocialVideoApiService
            rows = SocialVideoApiService().youtube_search("ASKODOX", 1)
            ok = bool(rows)
            detail = "YouTube Data API search OK" if ok else "YouTube Data API returned no results"
        elif name == "sarvam":
            # Verify both directions. A TTS-only probe must never make STT look
            # verified: run a tiny real Sarvam transcription after synthesis.
            result = container.voice_assistant_service.synthesize("ASKODOX") or {}
            tts_ok = bool(result.get("success")) and str(result.get("tts_path") or "").startswith("sarvam")
            stt_ok = False
            stt_detail = "STT probe unavailable"
            audio = result.get("audio_bytes") or result.get("audio") or b""
            if tts_ok and audio:
                voice = container.voice_assistant_service
                transcribe = getattr(voice, "transcribe", None)
                if callable(transcribe):
                    stt = transcribe(audio_bytes=audio, mime_type=str(result.get("mime_type") or "audio/wav")) or {}
                    stt_ok = bool(stt.get("success")) or str(stt.get("status") or "").endswith("EMPTY_TRANSCRIPT")
                    stt_detail = str(stt.get("status") or ("OK" if stt_ok else "failed"))
            ok = tts_ok and stt_ok
            detail = f"Sarvam TTS: {'OK' if tts_ok else result.get('status')}; STT: {stt_detail}"
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
    phone: str | None = Field(default=None, max_length=20)  # link the staff member's own number ("" unlinks)
    role: str | None = None
    grant: list[str] = Field(default_factory=list)
    revoke: list[str] = Field(default_factory=list)
    active: bool | None = None
    confirm: bool = False
    reason: str = Field(default="", max_length=500)


def _no_escalation(principal: dict[str, Any], permissions) -> None:
    """A staff manager can only hand out permissions they hold themselves."""
    beyond = sorted(p for p in set(permissions) if not _can(principal, p))
    if beyond:
        raise HTTPException(status_code=403,
                            detail=f"{gov.FORBIDDEN} Cannot grant permissions you do not hold: {', '.join(beyond)}")


def _roles(container: Any) -> dict[str, dict[str, Any]]:
    return command_center(container).roles()


@router.get("/staff")
def staff(request: Request) -> dict[str, Any]:
    _require(request, "staff:manage")
    roles = _roles(request.app.state.container)
    return {"items": command_center(request.app.state.container).list_staff(),
            "roles": {name: role["permissions"] for name, role in roles.items()},
            "role_details": list(roles.values()),
            "permissions": list(PERMISSIONS),
            "permission_risk": {p: gov.permission_risk(p) for p in PERMISSIONS}}


class AdviseBody(BaseModel):
    staff_id: int | None = None
    role: str | None = None
    permissions: list[str] | None = None
    grant: list[str] = Field(default_factory=list)
    revoke: list[str] = Field(default_factory=list)


@router.post("/staff/advise")
def advise_permissions(payload: AdviseBody, request: Request) -> dict[str, Any]:
    """Permission Safety Advisor: preview the risk of a grant before saving."""
    principal = _require(request, "staff:manage")
    container = request.app.state.container
    current = command_center(container).get_staff(payload.staff_id) if payload.staff_id else None
    before = set(current["permissions"]) if current else set()
    role = payload.role or (current or {}).get("role") or ""
    base = set(payload.permissions) if payload.permissions is not None else (
        set(_roles(container).get(role, {}).get("permissions") or []) if payload.role or not current else set(before))
    after = (base | set(payload.grant)) - set(payload.revoke)
    advice = gov.advise(before, after, role=role)
    advice["needs_approval"] = [p for p in advice["added"] if gov.permission_risk(p) == gov.RED
                                and not gov.is_super(principal)]
    advice["cannot_grant"] = sorted(p for p in advice["added"] if not _can(principal, p))
    return advice


def _split_red(principal: dict[str, Any], added: set[str]) -> set[str]:
    """RED permissions a non-super staff manager may only *request*."""
    return set() if gov.is_super(principal) else {p for p in added if gov.permission_risk(p) == gov.RED}


@router.post("/staff")
def create_staff(payload: StaffCreate, request: Request) -> dict[str, Any]:
    principal = _require(request, "staff:manage")
    container = request.app.state.container
    roles = _roles(container)
    if payload.role not in roles:
        raise HTTPException(status_code=422, detail=f"role must be one of {', '.join(roles)}")
    if payload.role == "super_admin" and not gov.is_super(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} Only the Owner can create a Super Admin.")
    unknown = [p for p in (payload.permissions or []) if p not in PERMISSIONS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")
    perms = set(payload.permissions if payload.permissions is not None else roles[payload.role]["permissions"])
    _no_escalation(principal, perms)
    held_back = _split_red(principal, perms)
    cc = command_center(container)
    created = cc.create_staff(payload.name, payload.role, perms - held_back, principal["id"])
    advice = gov.advise(set(), perms, role=payload.role)
    cc.audit(principal["id"], "staff_created", "staff", created["id"], None,
             {"role": created["role"], "permissions": created["permissions"]}, role=principal["role"],
             risk=advice["risk"])
    created["advice"] = advice
    if held_back:
        created["approval"] = request_approval(
            request, principal, action="staff.grant", target=f"staff:{created['id']}", risk=gov.RED,
            reason="High-risk permissions requested at creation", old={"permissions": created["permissions"]},
            proposed={"grant": sorted(held_back)},
            params={"staff_id": created["id"], "grant": sorted(held_back), "needs": "staff:manage"})
    return created  # includes the one-time token


@router.patch("/staff/{staff_id}")
def update_staff(staff_id: int, payload: StaffUpdate, request: Request) -> Any:
    principal = _require(request, "staff:manage")
    container = request.app.state.container
    cc = command_center(container)
    current = cc.get_staff(staff_id)
    if not current:
        raise HTTPException(status_code=404, detail="Staff not found")
    roles = _roles(container)
    if payload.role and payload.role not in roles:
        raise HTTPException(status_code=422, detail="Unknown role")
    if principal["id"] == f"staff-{staff_id}" and (payload.grant or payload.role):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} You cannot change your own permissions.")
    if not gov.is_super(principal) and (current["role"] == "super_admin" or payload.role == "super_admin"):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} Only the Owner can change a Super Admin.")
    unknown = [p for p in payload.grant + payload.revoke if p not in PERMISSIONS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")
    if payload.active is False:
        _require_confirm(payload.confirm, f"deactivate staff {staff_id}")
    base = set(roles[payload.role]["permissions"]) if payload.role else set(current["permissions"])
    permissions = (base | set(payload.grant)) - set(payload.revoke)
    added = permissions - set(current["permissions"])
    _no_escalation(principal, added)
    held_back = _split_red(principal, added)
    advice = gov.advise(current["permissions"], permissions, role=payload.role or current["role"])
    updated = cc.update_staff(staff_id, role=payload.role, permissions=permissions - held_back, active=payload.active)
    if payload.phone is not None:
        from app.api.routes.onboarding_auth import _is_test_mobile, _mobile

        digits = "".join(ch for ch in payload.phone if ch.isdigit())
        try:
            mobile = _mobile(digits) if digits else ""
        except HTTPException:
            raise
        if mobile and _is_test_mobile(mobile):
            raise HTTPException(status_code=422, detail="Demo / test numbers cannot sign in as staff")
        try:
            updated = cc.link_staff_app_user(staff_id, f"app-phone-{mobile}" if mobile else None)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error))
        cc.audit(principal["id"], "staff_phone_linked" if mobile else "staff_phone_unlinked", "staff", staff_id,
                 None, {"linked": bool(mobile)}, role=principal["role"])
    cc.audit(principal["id"], "staff_updated", "staff", staff_id,
             {"role": current["role"], "permissions": current["permissions"], "active": current["active"]},
             {"role": updated["role"], "permissions": updated["permissions"], "active": updated["active"]},
             role=principal["role"], risk=advice["risk"])
    updated["advice"] = advice
    if held_back:
        updated["approval"] = request_approval(
            request, principal, action="staff.grant", target=f"staff:{staff_id}", risk=gov.RED,
            reason=payload.reason or "High-risk permission grant", old={"permissions": current["permissions"]},
            proposed={"grant": sorted(held_back)},
            params={"staff_id": staff_id, "grant": sorted(held_back), "needs": "staff:manage"})
    return updated


# ---------------------------------------------------------------- roles --

class RoleBody(BaseModel):
    label: str = Field(default="", max_length=80)
    permissions: list[str]


_ROLE_NAME = __import__("re").compile(r"^[a-z][a-z0-9_]{2,40}$")


@router.get("/roles")
def list_roles(request: Request) -> dict[str, Any]:
    _require(request, "staff:manage")
    return {"items": list(_roles(request.app.state.container).values()), "permissions": list(PERMISSIONS),
            "permission_risk": {p: gov.permission_risk(p) for p in PERMISSIONS}}


@router.put("/roles/{name}")
def save_role(name: str, payload: RoleBody, request: Request) -> dict[str, Any]:
    """Owner / Super Admin customise a preset or define a new role. Existing
    staff keep their own permission lists; the role is the template."""
    principal = _require(request, "staff:manage")
    if not gov.is_super(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} Only the Owner can define roles.")
    if name == "super_admin" or not _ROLE_NAME.match(name):
        raise HTTPException(status_code=422, detail="Role names are lower_case letters/digits/_ (not super_admin)")
    unknown = [p for p in payload.permissions if p not in PERMISSIONS]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unknown permissions: {', '.join(unknown)}")
    cc = command_center(request.app.state.container)
    before = cc.role_permissions(name)
    saved = cc.save_role(name, payload.label or name.replace("_", " ").title(), payload.permissions, principal["id"])
    advice = gov.advise(before or [], saved["permissions"], role=name)
    cc.audit(principal["id"], "role_saved", "role", name, {"permissions": before},
             {"permissions": saved["permissions"]}, role=principal["role"], risk=advice["risk"])
    return {**saved, "advice": advice}


@router.delete("/roles/{name}")
def reset_role(name: str, request: Request, confirm: bool = False) -> dict[str, Any]:
    principal = _require(request, "staff:manage")
    if not gov.is_super(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} Only the Owner can define roles.")
    _require_confirm(confirm, f"reset role {name}")
    cc = command_center(request.app.state.container)
    before = cc.role_permissions(name)
    if not cc.reset_role(name):
        raise HTTPException(status_code=404, detail="No customisation for this role")
    cc.audit(principal["id"], "role_reset", "role", name, {"permissions": before}, None, role=principal["role"],
             risk=gov.ORANGE)
    return {"reset": name}


# ------------------------------------------------------------- approvals --

APPROVAL_EXECUTORS: dict[str, Any] = {}


def register_executor(action: str):
    """Only named, reviewed executors can run on approval -- never code."""
    def wrap(fn):
        APPROVAL_EXECUTORS[action] = fn
        return fn
    return wrap


def request_approval(request: Request, principal: dict[str, Any], *, action: str, target: str, risk: str,
                     reason: str, old: Any, proposed: Any, params: dict[str, Any]) -> dict[str, Any]:
    if action not in APPROVAL_EXECUTORS:
        raise HTTPException(status_code=500, detail="Unknown approval action")
    cc = command_center(request.app.state.container)
    approval = cc.create_approval(action=action, target=target, risk=risk, reason=reason, old=old,
                                  proposed=proposed, params=params, requested_by=principal["id"],
                                  requested_role=principal["role"])
    cc.audit(principal["id"], "approval_requested", "approval", approval["id"], old, proposed, reason,
             role=principal["role"], risk=risk, result="PENDING")
    cc.notify_once(f"approval:{approval['id']}", "approval_critical" if risk == gov.RED else "approval",
                   f"{risk} approval needed: {action} on {target}", str(approval["id"]))
    return {"approval_required": True, "status": "PENDING_APPROVAL", "approval": approval,
            "message": ("Owner/Super Admin approval is required." if risk == gov.RED
                        else "Owner/Admin approval is required.")}


@register_executor("feature_flag.set")
def _exec_flag(container: Any, params: dict[str, Any], decider: dict[str, Any]) -> dict[str, Any]:
    cc = command_center(container)
    flag = cc.set_flag(params["key"], bool(params["enabled"]), decider["id"])
    return {"key": params["key"], "enabled": flag["enabled"]}


@register_executor("staff.grant")
def _exec_staff_grant(container: Any, params: dict[str, Any], decider: dict[str, Any]) -> dict[str, Any]:
    cc = command_center(container)
    current = cc.get_staff(int(params["staff_id"]))
    if not current:
        raise ValueError("staff no longer exists")
    updated = cc.update_staff(current["id"], permissions=set(current["permissions"]) | set(params["grant"]))
    return {"staff_id": current["id"], "granted": params["grant"], "permissions": len(updated["permissions"])}


@register_executor("selfheal.apply")
def _exec_selfheal(container: Any, params: dict[str, Any], decider: dict[str, Any]) -> dict[str, Any]:
    from app.services.self_healing import engine

    item = engine(container).execute_approved(int(params["log_id"]), decider["id"])
    return {"log_id": item.get("id"), "status": item.get("status")}


@router.get("/approvals")
def approvals(request: Request, status: str = "") -> dict[str, Any]:
    principal = _principal(request)
    if not (_can(principal, "approvals:view") or _can(principal, "approvals:approve")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs approvals:view)")
    items = command_center(request.app.state.container).approvals(status=status.upper())
    return {"items": items, "can_approve": _can(principal, "approvals:approve"),
            "can_approve_red": gov.is_super(principal), "me": principal["id"]}


class DecisionBody(BaseModel):
    note: str = Field(default="", max_length=1000)
    confirm: bool = False


def _decide(approval_id: int, request: Request, approve: bool, body: DecisionBody) -> dict[str, Any]:
    principal = _require(request, "approvals:approve")
    container = request.app.state.container
    cc = command_center(container)
    item = cc.get_approval(approval_id, with_params=True)
    if not item:
        raise HTTPException(status_code=404, detail="Approval not found")
    if item["status"] != "PENDING":
        raise HTTPException(status_code=409, detail=f"Already {item['status'].lower()}")
    if item["requested_by"] == principal["id"]:
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} You cannot approve your own request.")
    if item["risk"] == gov.RED and not gov.is_super(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} RED changes need the Owner / Super Admin.")
    needs = (item.get("params") or {}).get("needs")
    if approve and needs and not _can(principal, needs):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs {needs})")
    if approve and item["risk"] == gov.RED:
        _require_confirm(body.confirm, f"approve RED change #{approval_id}")
    decided = cc.decide_approval(approval_id, status="APPROVED" if approve else "REJECTED",
                                 decided_by=principal["id"], note=body.note)
    if decided is None:
        raise HTTPException(status_code=409, detail="Already decided")
    result, final = None, decided["status"]
    if not approve and item["action"] == "selfheal.apply":
        from app.services.self_healing import engine

        engine(container).mark_rejected(approval_id)
    if approve:
        try:
            result = APPROVAL_EXECUTORS[item["action"]](container, item.get("params") or {}, principal)
            final = "EXECUTED"
        except Exception as error:  # the approval stays recorded; nothing half-applied is hidden
            result, final = {"error": type(error).__name__, "detail": str(error)[:200]}, "FAILED"
        cc.set_approval_result(approval_id, final, result)
    cc.audit(principal["id"], "approval_" + ("approved" if approve else "rejected"), "approval", approval_id,
             item.get("old"), item.get("proposed"), body.note, role=principal["role"], risk=item["risk"],
             result=final)
    return cc.get_approval(approval_id) or {}


@router.post("/approvals/{approval_id}/approve")
def approve(approval_id: int, body: DecisionBody, request: Request) -> dict[str, Any]:
    return _decide(approval_id, request, True, body)


@router.post("/approvals/{approval_id}/reject")
def reject(approval_id: int, body: DecisionBody, request: Request) -> dict[str, Any]:
    return _decide(approval_id, request, False, body)


@router.post("/approvals/{approval_id}/cancel")
def cancel(approval_id: int, request: Request) -> dict[str, Any]:
    principal = _principal(request)
    cc = command_center(request.app.state.container)
    item = cc.get_approval(approval_id)
    if not item or item["requested_by"] != principal["id"]:
        raise HTTPException(status_code=404, detail="Approval not found")
    decided = cc.decide_approval(approval_id, status="CANCELLED", decided_by=principal["id"])
    if decided is None:
        raise HTTPException(status_code=409, detail="Already decided")
    cc.audit(principal["id"], "approval_cancelled", "approval", approval_id, role=principal["role"],
             risk=item["risk"], result="CANCELLED")
    return decided


# ---------------------------------------------------------------- audit --

@router.get("/audit")
def audit(request: Request, limit: int = 100, actor: str = "", action: str = "", entity_type: str = "",
          risk: str = "", q: str = "", days: int = 0) -> dict[str, Any]:
    _require(request, "audit:view")
    since = _since(days) if days else ""
    return {"items": command_center(request.app.state.container).audit_log(
        limit=limit, actor=actor, action=action, entity_type=entity_type, risk=risk.upper(), q=q, since=since),
        "editable": False}


@router.get("/audit/export.csv")
def audit_export(request: Request, days: int = 30, risk: str = "") -> Response:
    principal = _require(request, "audit:export")
    cc = command_center(request.app.state.container)
    rows = cc.audit_log(limit=5000, risk=risk.upper(), since=_since(days))
    out = io.StringIO()
    writer = csv.writer(out)
    writer.writerow(["id", "created_at", "actor", "actor_role", "action", "entity_type", "entity_id", "risk",
                     "result", "reason"])
    for r in rows:
        writer.writerow([r["id"], r["created_at"], r["actor"], r.get("actor_role") or "", r["action"],
                         r["entity_type"], r["entity_id"], r["risk"], r.get("result") or "", r.get("reason") or ""])
    cc.audit(principal["id"], "audit_export", "audit", f"{days}d", None, {"rows": len(rows)},
             role=principal["role"], risk=gov.ORANGE)
    return Response(out.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": "attachment; filename=askodox-audit.csv"})


# ---------------------------------------------------------- self-healing --

def _healer(request: Request):
    from app.services.self_healing import engine

    return engine(request.app.state.container)


@router.get("/selfheal")
def selfheal(request: Request) -> dict[str, Any]:
    _require(request, "selfheal:view")
    eng = _healer(request)
    return {"settings": eng.settings(), "bypassed_sources": sorted(eng.bypassed_sources()), "items": eng.log()}


@router.post("/selfheal/scan")
def selfheal_scan(request: Request) -> dict[str, Any]:
    principal = _require(request, "selfheal:manage")
    result = _healer(request).scan()
    command_center(request.app.state.container).audit(principal["id"], "selfheal_scan", "selfheal", "scan", None,
                                                      {"new_issues": result.get("new_issues", 0)},
                                                      role=principal["role"])
    return result


@router.post("/selfheal/{log_id}/apply")
def selfheal_apply(log_id: int, request: Request) -> dict[str, Any]:
    principal = _require(request, "selfheal:manage")
    try:
        item = _healer(request).apply(log_id, principal["id"])
    except KeyError:
        raise HTTPException(status_code=404, detail="Not found") from None
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} {error}") from None
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
    command_center(request.app.state.container).audit(principal["id"], "selfheal_apply", "selfheal", log_id, None,
                                                      {"action": item["action"], "target": item["target"]},
                                                      role=principal["role"], risk=item["risk"])
    return item


@router.post("/selfheal/{log_id}/rollback")
def selfheal_rollback(log_id: int, request: Request) -> dict[str, Any]:
    principal = _require(request, "selfheal:manage")
    try:
        item = _healer(request).rollback(log_id, principal["id"])
    except KeyError:
        raise HTTPException(status_code=404, detail="Not found") from None
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
    command_center(request.app.state.container).audit(principal["id"], "selfheal_rollback", "selfheal", log_id,
                                                      None, {"action": item["action"], "target": item["target"]},
                                                      role=principal["role"], risk=item["risk"])
    return item



# ---------------------------------------- Social / Ads / Offers / Rewards --

class VideoSourceUpsert(BaseModel):
    provider_type: str
    api_enabled: bool = False
    embed_enabled: bool = True
    active: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)

class SponsoredCampaignCreate(BaseModel):
    owner_ref: str = "askodox"
    campaign_type: str = "sponsored"
    title: str
    destination_url: str | None = None
    category: str | None = None
    location_scope: str | None = None
    budget: float | None = Field(default=None, ge=0)
    starts_at: str | None = None
    ends_at: str | None = None
    active: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)

class PartnerOfferCreate(BaseModel):
    partner_id: str
    offer_type: str
    title: str
    bank_name: str | None = None
    card_network: str | None = None
    merchant: str | None = None
    promo_code: str | None = None
    discount_value: float | None = None
    discount_unit: str | None = None
    starts_at: str | None = None
    ends_at: str | None = None
    terms_url: str | None = None
    source_url: str | None = None
    verified: bool = False
    active: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)

def _social_hub(request: Request):
    hub = getattr(request.app.state.container, "social_ads_offers_hub", None)
    if hub is None:
        from app.services.social_ads_offers_hub import SocialAdsOffersHub
        hub = SocialAdsOffersHub(request.app.state.container.settings.database_path)
        request.app.state.container.social_ads_offers_hub = hub
    return hub

@router.get("/social-growth/api-status")
def social_api_status(request: Request) -> dict[str, Any]:
    _require(request, "integrations:view")
    from app.services.social_video_api_service import SocialVideoApiService
    return {"items": SocialVideoApiService().status()}

class YouTubeImportRequest(BaseModel):
    query: str
    max_results: int = Field(default=10, ge=1, le=25)
    category: str = ""
    related_ref: str = ""

@router.post("/social-growth/youtube/import")
def social_youtube_import(payload: YouTubeImportRequest, request: Request) -> dict[str, Any]:
    _require(request, "growth:manage")
    from app.services.social_video_api_service import SocialVideoApiService
    try:
        rows=SocialVideoApiService().youtube_search(payload.query,payload.max_results)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"YouTube API unavailable: {type(exc).__name__}") from exc
    saved=[]
    for row in rows:
        saved.append(_social_hub(request).upsert_video(**row,category=payload.category,related_ref=payload.related_ref))
    return {"imported":len(saved),"items":saved}

@router.get("/social-growth/video-sources")
def social_video_sources(request: Request) -> dict[str, Any]:
    _require(request, "integrations:view")
    return {"items": _rows(request, "SELECT provider_id,provider_type,api_enabled,embed_enabled,active,updated_at FROM social_video_sources ORDER BY provider_id")}

@router.put("/social-growth/video-sources/{provider_id}")
def social_video_source_upsert(provider_id: str, payload: VideoSourceUpsert, request: Request) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    item = _social_hub(request).upsert_video_source(provider_id, **payload.model_dump())
    command_center(request.app.state.container).audit(principal["id"], "video_source_upsert", "video_source", provider_id, None, {"active": item["active"]})
    return item

class SocialVideoUpsert(BaseModel):
    provider_id: str
    external_video_id: str
    canonical_url: str
    title: str = ""
    creator: str = ""
    category: str = ""
    thumbnail_url: str = ""
    related_ref: str = ""
    active: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)

class VideoDiscussionCreate(BaseModel):
    user_ref: str
    body: str
    kind: str = "question"
    parent_id: int | None = None

@router.get("/social-growth/videos")
def social_videos(request: Request, limit: int = 100) -> dict[str, Any]:
    _require(request, "growth:view")
    limit=max(1,min(limit,500))
    return {"items": _rows(request, "SELECT * FROM social_videos ORDER BY id DESC LIMIT ?", (limit,))}

@router.post("/social-growth/videos")
def social_video_upsert(payload: SocialVideoUpsert, request: Request) -> dict[str, Any]:
    _require(request, "growth:manage")
    try:
        return _social_hub(request).upsert_video(**payload.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

@router.get("/social-growth/videos/{video_id}/discussion")
def social_video_discussion(video_id: int, request: Request) -> dict[str, Any]:
    _require(request, "growth:view")
    items=_social_hub(request).discussions(video_id)
    for item in items:
        item["user_ref"]=mask_user_id(str(item.get("user_ref") or ""))
    return {"items":items}

@router.post("/social-growth/videos/{video_id}/discussion")
def social_video_discussion_add(video_id: int, payload: VideoDiscussionCreate, request: Request) -> dict[str, Any]:
    _require(request, "growth:manage")
    try:
        item=_social_hub(request).add_discussion(video_id, **payload.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    item["user_ref"]=mask_user_id(str(item.get("user_ref") or ""))
    return item

@router.get("/social-growth/campaigns")
def social_campaigns(request: Request) -> dict[str, Any]:
    _require(request, "growth:view")
    _social_hub(request)  # creates / migrates the hub's own campaign table first
    return {"items": _rows(request, "SELECT * FROM social_sponsored_campaigns ORDER BY id DESC LIMIT 500")}

@router.post("/social-growth/campaigns")
def social_campaign_create(payload: SponsoredCampaignCreate, request: Request) -> dict[str, Any]:
    principal = _require(request, "growth:manage")
    try:
        item = _social_hub(request).create_campaign(**payload.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    command_center(request.app.state.container).audit(principal["id"], "campaign_create", "sponsored_campaign", str(item["id"]), None, {"type": item["campaign_type"], "active": item["active"]})
    return item

@router.get("/social-growth/partner-offers")
def social_partner_offers(request: Request) -> dict[str, Any]:
    _require(request, "growth:view")
    return {"items": _rows(request, "SELECT * FROM partner_offers ORDER BY id DESC LIMIT 500")}

@router.post("/social-growth/partner-offers")
def social_partner_offer_create(payload: PartnerOfferCreate, request: Request) -> dict[str, Any]:
    principal = _require(request, "growth:manage")
    item = _social_hub(request).create_offer(**payload.model_dump())
    command_center(request.app.state.container).audit(principal["id"], "partner_offer_create", "partner_offer", str(item["id"]), None, {"verified": item["verified"], "active": item["active"]})
    return item

@router.get("/social-growth/scratch-rewards")
def social_scratch_rewards(request: Request) -> dict[str, Any]:
    _require(request, "growth:view")
    items = _rows(request, "SELECT id,user_ref,trigger_type,trigger_ref,reward_type,reward_value,status,expires_at,revealed_at,redeemed_at,created_at FROM scratch_rewards ORDER BY id DESC LIMIT 500")
    for item in items:
        item["user_ref"] = mask_user_id(str(item.get("user_ref") or ""))
    return {"items": items}


# ----------------------------------------------- Partner & Revenue Hub --

class PartnerRevenueUpsert(BaseModel):
    name: str
    sector: str = "general"
    category: str = "general"
    integration_modes: list[str] = Field(default_factory=list)
    commercial_model: str = "none"
    attribution_template: str = ""
    human_support: bool = False
    staff_fallback: bool = False
    compliance_notes: str = ""
    evidence_status: str = "unverified"
    active: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)


def _partner_hub(request: Request):
    hub = getattr(request.app.state.container, "partner_revenue_hub", None)
    if hub is None:
        from app.services.partner_revenue_hub import PartnerRevenueHub
        hub = PartnerRevenueHub(request.app.state.container.settings.database_path)
        request.app.state.container.partner_revenue_hub = hub
    return hub


@router.get("/partner-revenue/partners")
def partner_revenue_partners(request: Request, sector: str = "", active_only: bool = False) -> dict[str, Any]:
    _require(request, "integrations:view")
    return {"items": _partner_hub(request).list_partners(sector=sector, active_only=active_only)}


@router.put("/partner-revenue/partners/{partner_id}")
def upsert_partner_revenue_partner(partner_id: str, payload: PartnerRevenueUpsert, request: Request) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    item = _partner_hub(request).upsert_partner(partner_id, **payload.model_dump())
    try:
        command_center(request.app.state.container).audit(
            principal["id"], "partner_revenue_upsert", "partner", partner_id, None,
            {"sector": item.get("sector"), "active": item.get("active")})
    except Exception:
        pass
    return item


@router.get("/partner-revenue/summary")
def partner_revenue_summary(request: Request) -> dict[str, Any]:
    _require(request, "analytics:view")
    partners = _partner_hub(request).list_partners()
    rows = _rows(request, """SELECT partner_id,event_type,COUNT(*) n,
        COALESCE(SUM(value),0) value FROM partner_revenue_events
        GROUP BY partner_id,event_type ORDER BY partner_id,event_type""")
    return {
        "partners": {"total": len(partners), "active": sum(1 for p in partners if p.get("active"))},
        "events": rows,
    }


class AffiliateProductUpsert(BaseModel):
    original_product_url: str
    source: str = ""
    merchant: str = ""
    affiliate_url: str = ""
    collection_url: str = ""
    title: str = ""
    category: str = "general"
    subcategory: str = ""
    price: float | None = None
    currency: str = "INR"
    image_url: str = ""
    stock_status: str = ""
    verified_commission_rate: float | None = None
    active: bool = True
    last_verified: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


@router.get("/partner-revenue/products")
def partner_revenue_products(request: Request, q: str = "", category: str = "", limit: int = 50) -> dict[str, Any]:
    _require(request, "integrations:view")
    return {"items": _partner_hub(request).search_products(q, category, limit)}


@router.put("/partner-revenue/products/{partner_id}")
def upsert_partner_revenue_product(partner_id: str, payload: AffiliateProductUpsert, request: Request) -> dict[str, Any]:
    principal = _require(request, "integrations:manage")
    item = _partner_hub(request).upsert_product(partner_id, payload.original_product_url, **payload.model_dump(exclude={"original_product_url"}))
    try:
        command_center(request.app.state.container).audit(
            principal["id"], "affiliate_product_upsert", "affiliate_product",
            f"{partner_id}:{item.get('id','')}", None, {"category": item.get("category")})
    except Exception:
        pass
    return item


class PartnerStaffAssignment(BaseModel):
    staff_ref: str
    partner_id: str = ""
    sector: str = ""
    category: str = ""
    permissions: list[str] = Field(default_factory=list)
    active: bool = True


@router.put("/partner-revenue/staff-assignment")
def partner_revenue_staff_assignment(payload: PartnerStaffAssignment, request: Request) -> dict[str, Any]:
    _require(request, "staff:manage")
    _partner_hub(request).assign_staff(**payload.model_dump())
    return {"saved": True}


class BFSIFlowUpsert(BaseModel):
    lead_enabled: bool = False
    journey_enabled: bool = False
    callback_enabled: bool = False
    status_enabled: bool = False
    consent_required: bool = True
    regulated_entity: str = ""
    active: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)


@router.put("/partner-revenue/bfsi/{partner_id}/{product_type}")
def partner_revenue_bfsi(partner_id: str, product_type: str, payload: BFSIFlowUpsert, request: Request) -> dict[str, Any]:
    _require(request, "integrations:manage")
    _partner_hub(request).upsert_bfsi_flow(partner_id, product_type, **payload.model_dump())
    return {"saved": True, "partner_id": partner_id, "product_type": product_type}
