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


def default_jobs() -> List[Tuple[str, float, Callable[[Any], Any]]]:
    return [("promotions", 60.0, _promotions), ("selfheal", 120.0, _selfheal), ("feeds", 900.0, _feeds),
            ("crm_reminders", 300.0, _crm_reminders)]
