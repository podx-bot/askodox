"""Platform housekeeping run by the existing background runner
(ScheduledTaskRunner): due promotion windows and Self-Healing scans. Each
job is best-effort and isolated -- one failing never stops the others."""
from __future__ import annotations

import time
from typing import Any, Callable, Dict, List, Tuple


class PeriodicJobs:
    def __init__(self, container: Any, *, jobs: List[Tuple[str, float, Callable[[Any], Any]]] | None = None) -> None:
        self.container = container
        self.jobs = jobs if jobs is not None else default_jobs()
        self._last: Dict[str, float] = {}
        self.last_results: Dict[str, Any] = {}

    def run_once(self) -> Dict[str, Any]:
        now = time.monotonic()
        for name, every, job in self.jobs:
            if now - self._last.get(name, -1e9) < every:
                continue
            self._last[name] = now
            try:
                self.last_results[name] = job(self.container)
            except Exception as error:  # isolated: the next job still runs
                self.last_results[name] = {"error": type(error).__name__}
        return self.last_results


def _promotions(container: Any) -> Any:
    from app.api.routes.platform import platform

    return platform(container).run_due_promotions()


def _selfheal(container: Any) -> Any:
    from app.services.self_healing import engine

    return engine(container).scan()


def _feeds(container: Any) -> Any:
    """Universal Sources feeds that are due (older than sources.feed_refresh_hours)."""
    from app.api.routes.universal_deals import _universal_sources

    return _universal_sources(container).sync_due_feeds(actor="system:scheduler", limit=3)


def _crm_reminders(container: Any) -> Any:
    """Business CRM follow-ups whose time has come: one push to the assigned staff member (once each)."""
    from app.services.pos_crm import PosCrm
    from app.services.pos_store import PosStore
    from app.services.push_service import push_service

    store = getattr(container, "pos_store", None) or PosStore(container.settings.database_path)
    due = PosCrm(store).due_reminders()
    sent = 0
    push = push_service(container)
    for item in due:
        if item.get("app_user_id"):
            sent += push.notify(item["app_user_id"], title="Follow-up time", body=str(item["note"])[:160],
                                route=f"/pos/{item['business_id']}/crm?tab=followups",
                                event_key=f"crm_followup:{item['id']}")
    return {"due": len(due), "pushed": sent}


def _night_reports(container: Any) -> Any:
    """Each shop's day report, once per day, to the owner + people with the reports permission (pos_reports.py)."""
    from app.services.pos_reports import PosReports
    from app.services.pos_store import PosStore
    from app.services.push_service import push_service

    store = getattr(container, "pos_store", None) or PosStore(container.settings.database_path)
    push = push_service(container)

    def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
        push.notify(user_id, title=title, body=body, route=route, event_key=event_key)

    return PosReports(store, notify=notify).run_night()


def _availability(container: Any) -> Any:
    """"Tell me when it is available": new listings matching a buyer's watch -> one push each."""
    from app.api.routes.availability import store
    from app.api.routes.platform import platform
    from app.services import availability_watch
    from app.services.push_service import push_service

    push = push_service(container)
    return availability_watch.run(container, store(container), notify=push.notify,
                                  record=platform(container).repo.record_event)


def _owner_alerts(container: Any) -> Any:
    """Unmet demand / AI knowledge gaps over the threshold -> Command Center + push to demand staff."""
    from app.api.routes.command_center import command_center
    from app.api.routes.platform import platform
    from app.services import governance as gov
    from app.services import owner_alerts
    from app.services.push_service import push_service

    return owner_alerts.run(platform(container).repo, command_center(container), notify=push_service(container).notify,
                            has_permission=gov.has_permission)


def _payalert_missed(container: Any) -> Any:
    """Owner 2026-11-18: a phone that was sent a payment sound and never answered -> ONE push to the shop owner
    (whose phone, why) + ONE push to that phone's person (open ASKODOX, do the one step)."""
    from app.services.pos_payment_alerts import PosPaymentAlerts, missed_texts
    from app.services.pos_store import PosStore
    from app.services.push_service import push_service

    store = getattr(container, "pos_store", None) or PosStore(container.settings.database_path)
    alerts = getattr(container, "pos_payment_alerts", None)
    if alerts is None or alerts.store is not store:
        alerts = PosPaymentAlerts(store)
    push = push_service(container)
    items = alerts.missed_sounds()
    sent = 0
    for item in items:
        t = missed_texts(item)
        biz = item["business_id"]
        sent += bool(push.notify(item["owner"], title=t["owner_title"], body=t["owner_body"],
                                 route=f"/me/payment-alerts/{biz}/who",
                                 event_key=f"payalert_missed:{item['event_id']}:{item['device_id']}"))
        if item["user_id"] != item["owner"]:
            sent += bool(push.notify(item["user_id"], title=t["phone_title"], body=t["phone_body"],
                                     route=f"/pos/{biz}/payment-alerts",
                                     event_key=f"payalert_missed_me:{item['event_id']}:{item['device_id']}"))
    return {"missed": len(items), "pushed": sent}


def _dues_followup(container: Any) -> Any:
    """Baaki follow-up by itself: reminders to the customer, the promised date back to the shop (pos_dues_followup.py)."""
    from app.services.pos_bills import PosBills
    from app.services.pos_dues_followup import PosDuesFollowup
    from app.services.pos_store import PosStore
    from app.services.push_service import push_service

    store = getattr(container, "pos_store", None) or PosStore(container.settings.database_path)
    push = push_service(container)

    def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
        push.notify(user_id, title=title, body=body, route=route, event_key=event_key)

    from app.services.pos_dues_followup import auto_whatsapp

    send, state, base = auto_whatsapp(container)
    return PosDuesFollowup(store, PosBills(store), notify=notify, whatsapp=send, auto=state, base_url=base).run()


def _expiry_alerts(container: Any) -> Any:
    """Stock that expires soon -> ONE push a day to the shop owner (no searching by hand; owner 2026-11-19)."""
    from app.services.pos_store import PosStore
    from app.services.push_service import push_service

    store = getattr(container, "pos_store", None) or PosStore(container.settings.database_path)
    push = push_service(container)
    shops = store.expiring_soon_all()
    sent = 0
    for shop in shops:
        names = ", ".join(shop["names"][:3]) + (f" +{shop['count'] - 3}" if shop["count"] > 3 else "")
        sent += bool(push.notify(shop["owner"], title=f"{shop['name']}: {shop['count']} expiring / ఎక్స్‌పైరీ దగ్గర",
                                 body=names, route=f"/pos/{shop['business_id']}/stock-report",
                                 event_key=f"expiry:{shop['business_id']}:{shop['day']}"))
    return {"shops": len(shops), "pushed": sent}


def _studio_reminders(container: Any) -> Any:
    """ASKODOX Studio return-deadline / shoot reminders (owner 2026-11-21), once per purchase and kind."""
    from app.api.routes.studio import send_reminders

    return send_reminders(container)


def _shop_activity(container: Any) -> Any:
    """Each shop's working days copied into shop_activity_days (owner 2026-11-23: do shops keep using ASKODOX?).
    Payment events are deleted after 90 days; the roll-up keeps the days for the Command Center retention page."""
    from app.services.shop_retention import shop_retention

    return shop_retention(container).roll()


def default_jobs() -> List[Tuple[str, float, Callable[[Any], Any]]]:
    return [("promotions", 60.0, _promotions), ("selfheal", 120.0, _selfheal), ("feeds", 900.0, _feeds),
            ("crm_reminders", 300.0, _crm_reminders), ("availability", 600.0, _availability),
            ("owner_alerts", 900.0, _owner_alerts), ("night_reports", 600.0, _night_reports),
            ("payalert_missed", 60.0, _payalert_missed), ("dues_followup", 3600.0, _dues_followup),
            ("expiry_alerts", 3600.0, _expiry_alerts), ("studio_reminders", 1800.0, _studio_reminders),
            ("shop_activity", 21600.0, _shop_activity)]
