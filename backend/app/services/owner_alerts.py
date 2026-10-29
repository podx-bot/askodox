"""Owner / staff push alerts for demand the platform could not serve
(owner request 2026-10-29: "when a user searches for something we don't
have, or the AI says it doesn't know, tell us right away").

Every 15 minutes (periodic_jobs "owner_alerts") the last 24 hours of events
are grouped by subject:
  * ``search`` with no local supply (``local`` == 0: no registered seller /
    nearby shop, even when online rows exist) -> unmet demand
  * ``knowledge_gap`` (AI could not confirm / the user corrected it)
A subject that reaches the threshold creates ONE Command Center notification
and ONE push per staff member with ``demand:view`` (linked app number), per
subject per day. Subjects only -- never who searched.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any, Callable

UNMET_MIN = 3   # zero-result searches for one subject in 24 h
GAP_MIN = 2     # knowledge gaps for one subject in 24 h


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _key(text: Any) -> str:
    return " ".join(str(text or "").casefold().split())[:80]


def due_subjects(repo: Any, *, at: datetime | None = None) -> list[dict[str, Any]]:
    moment = at or _now()
    since = (moment - timedelta(hours=24)).isoformat()
    unmet: Counter = Counter()
    gaps: Counter = Counter()
    label: dict[str, str] = {}
    for row in repo.events(event="search", since=since, limit=20000):
        detail = row.get("detail") or {}
        local = detail.get("local") if detail.get("local") is not None else detail.get("results")
        if str(local) == "0":  # nothing of ours: no registered / nearby supply (online rows may exist)
            subject = str(detail.get("subject") or "").strip()
            if subject:
                unmet[_key(subject)] += 1
                label.setdefault(_key(subject), subject)
    for row in repo.events(event="knowledge_gap", since=since, limit=20000):
        subject = str((row.get("detail") or {}).get("subject") or "").strip()
        if subject:
            gaps[_key(subject)] += 1
            label.setdefault(_key(subject), subject)
    out = []
    for key in set(unmet) | set(gaps):
        if unmet[key] >= UNMET_MIN or gaps[key] >= GAP_MIN:
            out.append({"subject": label[key], "key": key, "unmet": unmet[key], "gaps": gaps[key]})
    return sorted(out, key=lambda s: -(s["unmet"] + s["gaps"]))


def run(repo: Any, cc: Any, *, notify: Callable[..., int] | None = None, at: datetime | None = None,
        has_permission: Callable[[Any, str], bool] | None = None) -> dict[str, Any]:
    moment = at or _now()
    day = moment.strftime("%Y%m%d")
    created = pushed = 0
    staff = []
    try:
        staff = [s for s in cc.list_staff() if s.get("active") and s.get("app_user_id")
                 and (has_permission(s.get("permissions") or [], "demand:view") if has_permission else True)]
    except Exception:
        staff = []
    for item in due_subjects(repo, at=moment):
        parts = []
        if item["unmet"]:
            parts.append(f"{item['unmet']} సార్లు search, మన sellers దగ్గర లేదు")
        if item["gaps"]:
            parts.append(f"AI {item['gaps']} సార్లు confirm చేయలేదు / user సరిచేశారు")
        title = f"\"{item['subject']}\": " + "; ".join(parts)
        if not cc.notify_once(f"owner_alert:{day}:{item['key']}", "demand_gap", title):
            continue
        created += 1
        for person in staff:
            if notify is not None:
                pushed += int(notify(person["app_user_id"], title="ASKODOX: మన దగ్గర లేనిది అడిగారు",
                                     body=title[:170], route="/admin", event_key=f"owner_alert:{day}:{item['key']}") or 0)
    return {"alerts": created, "pushed": pushed}
