"""One notification centre for every role, from data that already exists.

  GET /api/me/inbox      signed-in user / seller / provider: their requests,
                         requests to them, demand opportunities and in-app
                         notices, newest first (app + web chat use the same).
  GET /admin/cc/inbox    staff / admin: unread Command Center notifications +
                         the caller's permitted work queue + pending approvals.

Push is an ADDITIONAL delivery channel: it only works once Firebase is set
up (push.status = EXTERNAL_SETUP_REQUIRED until then); the inbox itself
never depends on it.
"""
from __future__ import annotations

from typing import Any, Dict, List

from fastapi import APIRouter, Request

router = APIRouter(tags=["inbox"])

_ORDER_WORDS = {
    "PLACED": ("Waiting for the seller to accept", "New request -- accept or decline"),
    "ACCEPTED": ("Accepted", "Accepted"), "REJECTED": ("Declined", "Declined"),
    "FULFILLED": ("Completed", "Completed"), "CANCELLED": ("Cancelled", "Cancelled"),
    "DISPUTED": ("Problem reported", "Problem reported"), "CLOSED": ("Closed", "Closed"),
}
_OPPORTUNITY_WORDS = {"new": "New demand -- accept or decline", "opened": "Seen -- accept or decline",
                      "accepted": "You accepted", "declined": "You declined", "expired": "Expired",
                      "fulfilled": "Fulfilled"}


def _push_status(container) -> Dict[str, str]:
    try:
        from app.services.push_service import push_service

        if push_service(container).configured:
            return {"status": "CONFIGURED", "note": "Push is sent in addition to this inbox."}
    except Exception:
        pass
    return {"status": "EXTERNAL_SETUP_REQUIRED",
            "note": "Background push needs FIREBASE_SERVICE_ACCOUNT_JSON + an Android Firebase app; until then "
                    "updates appear here and as silent notifications while the app is open."}


def _order_item(row: Dict[str, Any], *, mine: bool) -> Dict[str, Any]:
    status = str(row.get("status") or "").upper()
    words = _ORDER_WORDS.get(status, (status.replace("_", " ").lower(),) * 2)[0 if mine else 1]
    return {"key": f"{'order' if mine else 'incoming'}:{row.get('id')}", "kind": "request" if mine else "incoming",
            "title": str(row.get("product_title") or row.get("title") or "Request"), "status": words,
            "route": "/orders/mine" if mine else "/orders/incoming",
            "at": row.get("updated_at") or row.get("created_at"),
            "needs_action": (not mine and status == "PLACED")}


@router.get("/api/me/inbox")
def my_inbox(request: Request, language: str = "en", limit: int = 60) -> dict:
    from app.api.routes.demand_advisor import _log, _opportunity_view
    from app.api.routes.in_app_deal import _authenticated_app_user
    from app.api.routes.platform import platform, user_ref

    user = _authenticated_app_user(request)
    container = request.app.state.container
    items: List[Dict[str, Any]] = []
    sources: Dict[str, str] = {}
    orders = getattr(container, "order_repository", None)
    try:
        items += [_order_item(r, mine=True) for r in orders.list_for_buyer(user, limit=30)]
        items += [_order_item(r, mine=False) for r in orders.list_for_seller(user, limit=30)]
        sources["orders"] = "ok"
    except Exception as error:
        sources["orders"] = f"unavailable ({type(error).__name__})"
    try:
        for alert in _log(container).for_recipient(user, limit=30):
            view = _opportunity_view(alert, language)
            items.append({"key": f"opportunity:{view['id']}", "kind": "opportunity", "title": view["title"],
                          "body": view["body"], "status": _OPPORTUNITY_WORDS.get(view["status"], view["status"]),
                          "route": "/opportunities", "at": view["responded_at"] or view["sent_at"],
                          "needs_action": view["can_respond"], "expires_at": view["expires_at"]})
        sources["opportunities"] = "ok"
    except Exception as error:
        sources["opportunities"] = f"unavailable ({type(error).__name__})"
    try:
        for note in platform(container).notifications.inbox(user_ref(user)):
            items.append({"key": f"notice:{note['id']}", "kind": "notice", "title": note.get("title") or "",
                          "body": note.get("body") or "", "status": note.get("type") or "update",
                          "route": "/updates", "at": note.get("at"), "needs_action": False})
        sources["notices"] = "ok"
    except Exception as error:
        sources["notices"] = f"unavailable ({type(error).__name__})"
    items.sort(key=lambda i: str(i.get("at") or ""), reverse=True)
    items = items[:max(1, min(limit, 200))]
    counts: Dict[str, int] = {}
    for item in items:
        counts[item["kind"]] = counts.get(item["kind"], 0) + 1
    return {"items": items, "counts": counts, "needs_action": sum(1 for i in items if i.get("needs_action")),
            "sources": sources, "push": _push_status(container)}


@router.get("/admin/cc/inbox")
def staff_inbox(request: Request) -> dict:
    from app.api.routes.command_center import _can, _principal, command_center
    from app.api.routes.demand_advisor import staff_work_queue

    principal = _principal(request)
    container = request.app.state.container
    cc = command_center(container)
    out: Dict[str, Any] = {"role": principal.get("role"), "notifications": [], "work": [], "approvals": 0,
                           "push": _push_status(container)}
    if _can(principal, "notifications:view"):
        out["notifications"] = cc.notifications(unread_only=True)[:50]
    out["work"] = [w for w in staff_work_queue(request).get("items", []) if w.get("count")]
    if _can(principal, "approvals:view"):
        try:
            out["approvals"] = len([a for a in cc.approvals(status="PENDING")])
        except Exception:
            out["approvals"] = 0
    out["total"] = len(out["notifications"]) + sum(int(w.get("count") or 0) for w in out["work"]) + out["approvals"]
    return out
