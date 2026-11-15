"""Customer Care ticket alerts (owner 2026-11-15, pani D).

Customer Care is AI-first: a ticket exists only after ASKODOX AI could not solve the problem and the customer
tapped "Send to ASKODOX team". Each ticket then reaches the owner at once:

* ONE email to the owner address (env ``ASKODOX_OWNER_EMAIL``, default admin@askodox.com) through the ONE
  outbound path (``Messenger.send("email")`` -> outbox, provider state decides MOCK / TEST / LIVE);
* ONE phone notification per active staff member who may handle support (``support:view`` / ``support:manage``,
  linked app number), deduplicated per ticket by the push service's event key.

No customer phone number, token or private field is put in the alert -- only the ticket number, category and the
first words of the issue. Everything is best effort and runs off the request thread: an alert never delays or
fails the customer's ticket.
"""
from __future__ import annotations

import os
import threading
from typing import Any, Callable, Dict, List

DEFAULT_OWNER_EMAIL = "admin@askodox.com"


def owner_email(env: Dict[str, str] | None = None) -> str:
    value = str((env if env is not None else os.environ).get("ASKODOX_OWNER_EMAIL", "") or "").strip()
    return value if "@" in value else DEFAULT_OWNER_EMAIL


def alert_text(case_id: Any, category: str, issue: str, critical: bool) -> Dict[str, str]:
    head = "అత్యవసరం" if critical else "కొత్త"
    issue = " ".join(str(issue or "").split())[:160]
    title = f"ASKODOX Customer Care: {head} టికెట్ #{case_id}"
    body = (f"టికెట్ #{case_id} ({category or 'GENERAL'}). AI పరిష్కరించలేకపోయింది, customer టీమ్‌కి పంపారు.\n"
            f"సమస్య: {issue}\n"
            f"Command Center -> Support లో మొత్తం సంభాషణ ఉంది: https://admin.askodox.com/admin/console")
    return {"title": title, "body": body}


def support_staff(staff: List[Dict[str, Any]], has_permission: Callable[[Any, str], bool]) -> List[Dict[str, Any]]:
    return [s for s in staff if s.get("active") and s.get("app_user_id")
            and (has_permission(s.get("permissions") or [], "support:view")
                 or has_permission(s.get("permissions") or [], "support:manage"))]


def send(*, case_id: Any, category: str, issue: str, critical: bool, email: Callable[..., Any] | None,
         push: Callable[..., Any] | None, staff: List[Dict[str, Any]], to: str) -> Dict[str, Any]:
    """Synchronous core (tests call it directly). Returns what was attempted."""
    text = alert_text(case_id, category, issue, critical)
    out: Dict[str, Any] = {"email": None, "pushed": 0}
    if email is not None and to:
        try:
            out["email"] = (email("email", to=to, title=text["title"], body=text["body"], event="support_ticket") or {}
                            ).get("status")
        except Exception:
            out["email"] = "error"
    if push is not None:
        for person in staff:
            try:
                out["pushed"] += int(push(person["app_user_id"], title=text["title"], body=text["body"][:170],
                                          route="/admin", event_key=f"support_ticket:{case_id}") or 0)
            except Exception:
                pass
    return out


def notify_ticket(container: Any, case: Dict[str, Any], *, category: str, issue: str, critical: bool) -> None:
    """Fire and forget from the escalation route."""
    case_id = case.get("id")
    if not case_id:
        return

    def run() -> None:
        try:
            from app.api.routes.command_center import command_center
            from app.api.routes.platform import platform
            from app.services import governance as gov
            from app.services.push_service import push_service

            try:
                staff = support_staff(command_center(container).list_staff(), gov.has_permission)
            except Exception:
                staff = []
            try:
                messenger = platform(container).messenger
                email = messenger.send
            except Exception:
                email = None
            send(case_id=case_id, category=category, issue=issue, critical=critical, email=email,
                 push=push_service(container).notify, staff=staff, to=owner_email())
        except Exception:
            pass

    threading.Thread(target=run, name=f"support-alert-{case_id}", daemon=True).start()
