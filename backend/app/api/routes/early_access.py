"""Early Access programme, feedback / problem reports and client diagnostics.

  GET  /api/early-access                     is this person in the ACTIVE programme? (label, free trial, prompt)
  POST /api/feedback                         "Report a problem / Send feedback" (masked; diagnostics only with consent)
  POST /api/diagnostics/client-error         one sanitized app error (consented), for error trends
  GET  /admin/cc/early-access/dashboard      programme users, usage, feedback, errors, poor / no-result searches

Everything is configured in the Command Center (``early_access`` and
``feedback_reports`` resources) -- nothing is hard-coded into the APK.
"""
from __future__ import annotations

import hashlib
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _principal
from app.services import governance as gov
from app.services.pii_mask import mask_sensitive

router = APIRouter(tags=["early-access"])
_SEEN: dict[str, str] = {}  # install hash -> day already counted (one event per person per day)


def _pf(request: Request):
    from app.api.routes.platform import platform

    return platform(request.app.state.container)


def _hash(value: str) -> str:
    return hashlib.sha256(f"ea:{value}".encode()).hexdigest()[:16] if value else ""


def _optional_user(request: Request) -> str:
    try:
        from app.api.routes.in_app_assistant import _optional_app_user

        user = _optional_app_user(request)
        return "" if user in ("", "guest") else user
    except Exception:
        return ""


def _bucket(identity: str, name: str) -> int:
    return int(hashlib.sha256(f"{name}:{identity}".encode()).hexdigest(), 16) % 100


def programme(pf: Any) -> dict | None:
    for record in pf.repo.list("early_access"):
        if record.get("status") == "ACTIVE" and not record.get("archived"):
            return {**(record.get("data") or {}), "id": record["id"]}
    return None


def resolve(pf: Any, *, identity: str, user: str, role: str, city: str, today: date | None = None) -> dict:
    """Same answer every time for the same person (stable % bucket)."""
    prog = programme(pf)
    off = {"active": False}
    if not prog:
        return off
    today = today or datetime.now(timezone.utc).date()
    if prog.get("start_at") and today.isoformat() < str(prog["start_at"])[:10]:
        return off
    if prog.get("end_at") and today.isoformat() > str(prog["end_at"])[:10]:
        return off
    included = user and user in (prog.get("include_users") or [])
    if not included:
        roles = prog.get("roles") or []
        if roles and role not in roles:
            return off
        regions = [r.lower() for r in prog.get("regions") or []]
        if regions and not any(r in city.lower() for r in regions):
            return off
        percent = prog.get("eligible_percent")
        if percent is not None and _bucket(identity or user, str(prog.get("name"))) >= int(percent):
            return off
    trial_days = int(prog.get("trial_days") or 0)
    return {"active": True, "programme": prog.get("name"), "label": prog.get("label") or "Early Access",
            "free_trial": bool(prog.get("free_trial", True)), "trial_days": trial_days or None,
            "ends_on": prog.get("end_at"), "feedback_prompt": bool(prog.get("feedback_prompt", True)),
            "features": prog.get("features") or [],
            "consent_text": prog.get("consent_text") or (
                "Send app version, screen and the error message with this report. No messages, contacts, "
                "location or payment details are included.")}


@router.get("/api/early-access")
def early_access(request: Request, install_id: str = "", role: str = "guest", city: str = "") -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "early_access", limit=120)
    pf = _pf(request)
    user = _optional_user(request)
    identity = install_id.strip()[:64] or user
    answer = resolve(pf, identity=identity, user=user, role=role[:20], city=city[:80])
    if answer["active"] and identity:
        key, day = _hash(identity), datetime.now(timezone.utc).date().isoformat()
        if _SEEN.get(key) != day:
            _SEEN[key] = day
            try:
                pf.repo.record_event("early_access_seen", detail={"who": key, "role": role[:20]})
            except Exception:
                pass
    return answer


class FeedbackBody(BaseModel):
    kind: str = Field(default="bug", pattern="^(bug|wrong_result|idea|praise|other)$")
    message: str = Field(min_length=3, max_length=4000)
    feature: str = Field(default="", max_length=80)
    app_version: str = Field(default="", max_length=40)
    platform: str = Field(default="android", max_length=20)
    install_id: str = Field(default="", max_length=64)
    consent_diagnostics: bool = False
    diagnostics: dict[str, Any] = Field(default_factory=dict)


_DIAG_KEYS = ("screen", "error", "build", "os", "device_model", "locale", "network", "last_action", "trace_key",
              "query")


def _clean_diagnostics(raw: dict[str, Any]) -> dict[str, Any]:
    """Allow-listed, short, masked diagnostics -- never free-form payloads."""
    out = {}
    for key in _DIAG_KEYS:
        if key in raw and raw[key] not in (None, ""):
            out[key] = mask_sensitive(str(raw[key]))[:300]
    return out


@router.post("/api/feedback")
def send_feedback(body: FeedbackBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "feedback", limit=10)
    pf = _pf(request)
    user = _optional_user(request)
    identity = body.install_id or user
    message = mask_sensitive(body.message)
    data = {"summary": message[:90], "kind": body.kind, "feature": body.feature[:80], "message": message,
            "app_version": body.app_version, "platform": body.platform, "user_ref": _hash(user or identity),
            "early_access": resolve(pf, identity=identity, user=user, role="buyer" if user else "guest",
                                    city="")["active"],
            "diagnostics": _clean_diagnostics(body.diagnostics) if body.consent_diagnostics else {}}
    record = pf.resources.create("feedback_reports", data, actor="app")
    pf.repo.record_event("feedback", detail={"kind": body.kind, "feature": body.feature[:80]})
    return {"ok": True, "reference": record["id"],
            "message": "Thanks -- the ASKODOX team will look at this."}


class ClientErrorBody(BaseModel):
    screen: str = Field(default="", max_length=80)
    error: str = Field(min_length=1, max_length=500)
    app_version: str = Field(default="", max_length=40)
    consent: bool = False


@router.post("/api/diagnostics/client-error")
def client_error(body: ClientErrorBody, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "client_error", limit=20)
    if not body.consent:
        return {"ok": False, "stored": False}
    signature = hashlib.sha256(body.error.split("\n")[0].encode()).hexdigest()[:12]
    _pf(request).repo.record_event("client_error", detail={
        "screen": body.screen[:80], "signature": signature, "app_version": body.app_version[:40],
        "error": mask_sensitive(body.error.split("\n")[0])[:200]})
    return {"ok": True, "stored": True}


@router.get("/admin/cc/early-access/dashboard")
def dashboard(request: Request, days: int = 30) -> dict:
    principal = _principal(request)
    if not (gov.has_permission(principal["permissions"], "early_access:view")
            or gov.has_permission(principal["permissions"], "feedback:view")):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (needs early_access:view)")
    pf = _pf(request)
    days = max(1, min(int(days), 365))
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    seen = pf.repo.events(event="early_access_seen", since=since, limit=100000)
    users = {(e.get("detail") or {}).get("who") for e in seen}
    per_day: dict[str, set] = {}
    for e in seen:
        per_day.setdefault(str(e.get("at") or "")[:10], set()).add((e.get("detail") or {}).get("who"))
    errors = pf.repo.events(event="client_error", since=since, limit=100000)
    signatures: dict[str, dict] = {}
    for e in errors:
        d = e.get("detail") or {}
        row = signatures.setdefault(d.get("signature"), {"error": d.get("error"), "screen": d.get("screen"),
                                                         "count": 0, "versions": set()})
        row["count"] += 1
        row["versions"].add(d.get("app_version"))
    reports = [r for r in pf.repo.list("feedback_reports") if str(r.get("created_at") or "") >= since[:19]]
    by_kind: dict[str, int] = {}
    by_feature: dict[str, int] = {}
    for r in reports:
        d = r.get("data") or {}
        by_kind[d.get("kind") or "other"] = by_kind.get(d.get("kind") or "other", 0) + 1
        by_feature[d.get("feature") or "-"] = by_feature.get(d.get("feature") or "-", 0) + 1
    poor = {}
    try:
        from app.services import outcome_analytics

        out = outcome_analytics.outcomes(pf, request.app.state.container, days=days)
        poor = {"no_result_searches": (out.get("demand") or {}).get("no_result_searches"),
                "failed_searches": out.get("failed_searches"), "supply_gaps": out.get("supply_gaps"),
                "funnel": out.get("funnel")}
    except Exception:
        pass
    return {"programme": programme(pf), "days": days, "early_access_users": len(users - {None}),
            "active_by_day": {d: len(v) for d, v in sorted(per_day.items())},
            "feedback": {"total": len(reports), "by_kind": by_kind, "by_feature": by_feature,
                         "open": sum(1 for r in reports if r.get("status") in ("NEW", "TRIAGED", "IN_PROGRESS"))},
            "errors": sorted(({**v, "versions": sorted(x for x in v["versions"] if x)} for v in signatures.values()),
                             key=lambda v: -v["count"])[:20],
            "poor_results": poor}
