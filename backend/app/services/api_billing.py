"""API Health & Billing (Command Center): per external provider -- real
state, failure type, credits / usage %, daily + monthly usage, reset date,
estimated vs actual cost, rate limit, dashboard link, timestamps -- and
threshold / spike / failure alerts (deduplicated; acknowledge / resolve).

Truth rules:
* A remaining balance is REAL only when the provider itself reports it
  (Brave's X-RateLimit monthly limit / remaining headers). Otherwise it is
  UNKNOWN -- or, when an admin entered a monthly budget, an ESTIMATE from
  counted calls x list price, always labelled as an estimate.
* Actual cost is the provider's bill: UNKNOWN here (no billing API is read).
* Failure types: billing_quota, credential, rate_limit, downtime.
* ASKODOX never recharges or pays: the only action is the provider's own
  dashboard link, opened by a person.
* No key, token or secret is ever read into this payload.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any

from app.services import external_call_budget, provider_health

THRESHOLDS = (20, 10, 5, 0)
NO_RECHARGE = "Manual only: open the provider's dashboard. ASKODOX never recharges or pays by itself."

PROVIDERS: dict[str, dict[str, Any]] = {
    "brave": {"label": "Brave Search", "usage": ("brave",), "fallback": "google_cse",
              "dashboard": "https://api-dashboard.search.brave.com/app/subscriptions"},
    "google_cse": {"label": "Google Programmable Search (web fallback)", "usage": ("google_cse",), "fallback": None,
                   "dashboard": "https://console.cloud.google.com/apis/dashboard"},
    "google_maps": {"label": "Google Maps (Places / Geocoding / Routes)", "usage": ("google_places", "google_geocode"),
                    "fallback": None, "dashboard": "https://console.cloud.google.com/billing"},
    "gemini": {"label": "Gemini (conversation brain)", "usage": (), "fallback": "openai",
               "dashboard": "https://aistudio.google.com/usage"},
    "openai": {"label": "OpenAI (brain fallback)", "usage": (), "fallback": None,
               "dashboard": "https://platform.openai.com/usage"},
    "sarvam": {"label": "Sarvam (voice STT / TTS)", "usage": (), "fallback": "device voice",
               "dashboard": "https://dashboard.sarvam.ai/"},
}

_BRAVE_STATE = {"ok": "LIVE", "quota_exhausted": "QUOTA_EXHAUSTED", "rate_limited": "RATE_LIMITED",
                "auth_failed": "CREDENTIAL_ERROR", "bad_request": "ERROR", "error": "DOWN",
                "unknown": "CONFIGURED_NOT_VERIFIED", "not_configured": "NEEDS_CONFIGURATION"}
_FAILURE_TYPE = {"QUOTA_EXHAUSTED": "billing_quota", "CREDENTIAL_ERROR": "credential", "RATE_LIMITED": "rate_limit",
                 "DOWN": "downtime", "ERROR": "downtime"}


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS api_billing_settings (
        provider TEXT PRIMARY KEY, monthly_budget_inr REAL, reset_day INTEGER, dashboard_url TEXT,
        updated_by TEXT, updated_at REAL)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS api_billing_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, alert_key TEXT UNIQUE NOT NULL, provider TEXT NOT NULL,
        kind TEXT NOT NULL, severity TEXT NOT NULL, message TEXT NOT NULL, evidence TEXT, status TEXT NOT NULL,
        created_at REAL NOT NULL, updated_at REAL NOT NULL, acted_by TEXT)""")
    return conn


def settings(db_path: str) -> dict[str, dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        return {r["provider"]: dict(r) for r in conn.execute("SELECT * FROM api_billing_settings").fetchall()}


def save_settings(db_path: str, provider: str, *, actor: str, monthly_budget_inr: float | None = None,
                  reset_day: int | None = None, dashboard_url: str | None = None) -> dict[str, Any]:
    if provider not in PROVIDERS:
        raise KeyError(provider)
    if dashboard_url and not dashboard_url.startswith("https://"):
        raise ValueError("dashboard_url must start with https://")
    if reset_day is not None and not 1 <= int(reset_day) <= 28:
        raise ValueError("reset_day must be 1-28")
    if monthly_budget_inr is not None and monthly_budget_inr < 0:
        raise ValueError("monthly_budget_inr must be >= 0")
    with closing(_connect(db_path)) as conn:
        conn.execute("INSERT OR REPLACE INTO api_billing_settings VALUES(?,?,?,?,?,?)",
                     (provider, monthly_budget_inr, reset_day, dashboard_url, actor, time.time()))
        conn.commit()
    return settings(db_path)[provider]


def _usage(rows: list[dict[str, Any]], keys: tuple[str, ...], today: str, month: str) -> dict[str, Any]:
    costs = external_call_budget.cost_table()
    daily = {"calls": 0, "errors": 0, "cache_hits": 0}
    monthly = {"calls": 0, "errors": 0}
    est_today = est_month = 0.0
    history: dict[str, int] = {}
    for r in rows:
        if r.get("provider") not in keys:
            continue
        calls, errors = int(r.get("calls") or 0), int(r.get("errors") or 0)
        price = float(costs.get(str(r["provider"]), 0.0))
        history[r["day"]] = history.get(r["day"], 0) + calls
        if r["day"] == today:
            daily["calls"] += calls
            daily["errors"] += errors
            daily["cache_hits"] += int(r.get("cache_hits") or 0)
            est_today += calls * price
        if str(r["day"]).startswith(month):
            monthly["calls"] += calls
            monthly["errors"] += errors
            est_month += calls * price
    return {"daily": daily, "monthly": monthly, "history": history,
            "estimated_cost_inr": {"today": round(est_today, 2), "month": round(est_month, 2),
                                   "label": "estimate (counted calls x list price)"} if keys else None}


def _state(name: str, container: Any) -> dict[str, Any]:
    """Real state only; never from key presence."""
    if name in ("brave", "google_cse"):
        brave = getattr(container, "brave_web_search_provider", None)
        if name == "brave":
            snap = brave.health_snapshot() if hasattr(brave, "health_snapshot") else {}
            state = _BRAVE_STATE.get(str(snap.get("state") or "unknown"), "ERROR")
            return {"state": state, "last_checked_at": snap.get("at"), "last_success_at": snap.get("last_ok_at"),
                    "http_status": snap.get("http_status"), "rate": snap.get("rate") or {},
                    "paused_for_seconds": snap.get("paused_for_seconds")}
        chain = getattr(container, "web_search_chain", None)
        fallbacks = chain.health_snapshot().get("fallbacks", {}) if hasattr(chain, "health_snapshot") else {}
        raw = fallbacks.get("google_cse")
        return {"state": "LIVE" if raw == "ok" else ("NEEDS_CONFIGURATION" if raw in (None, "not_configured")
                                                    else "CONFIGURED_NOT_VERIFIED" if raw == "unknown" else "ERROR")}
    if name == "google_maps":
        return {"state": "UNVERIFIED", "note": "use Integrations -> Check now / /health/maps for a real probe"}
    observed = provider_health.snapshot()
    keys = [k for k in observed if k == name or k.startswith(name + "_")]
    if not keys:
        return {"state": "CONFIGURED_NOT_VERIFIED", "note": "no real call observed since the last deploy"}
    worst = None
    for key in keys:
        row = provider_health.state(key, configured=True)
        if worst is None or row["state"] != "LIVE":
            worst = row
    state = worst["state"]
    if state == "ERROR" and worst.get("last_status_code") in (401, 403):
        state = "CREDENTIAL_ERROR"
    elif state == "ERROR" and worst.get("last_status_code") == 429:
        state = "RATE_LIMITED"
    return {"state": state, "last_checked_at": worst.get("last_checked_at"),
            "last_success_at": worst.get("last_success_at"), "http_status": worst.get("last_status_code")}


def _credits(name: str, live: dict[str, Any], usage: dict[str, Any], budget: dict[str, Any] | None,
             now: datetime) -> dict[str, Any]:
    rate = live.get("rate") or {}
    limit, remaining, reset = rate.get("limit"), rate.get("remaining"), rate.get("reset")
    if name == "brave" and isinstance(limit, list) and len(limit) > 1 and isinstance(remaining, list) \
            and len(remaining) > 1 and limit[1]:
        left = max(0.0, 100.0 * remaining[1] / limit[1])
        reset_at = (now + timedelta(seconds=int(reset[1]))).isoformat() if isinstance(reset, list) and len(reset) > 1 \
            else None
        return {"source": "provider", "label": "reported by Brave (X-RateLimit headers)", "limit": limit[1],
                "remaining": remaining[1], "remaining_pct": round(left, 1), "used_pct": round(100 - left, 1),
                "reset_at": reset_at, "rate_limit_per_second": limit[0]}
    if live.get("state") == "QUOTA_EXHAUSTED":
        return {"source": "provider", "label": "provider refused for credit / quota", "remaining_pct": 0.0,
                "used_pct": 100.0, "reset_at": None}
    spend = (usage.get("estimated_cost_inr") or {}).get("month")
    if budget and budget.get("monthly_budget_inr") and spend is not None:
        total = float(budget["monthly_budget_inr"])
        left = max(0.0, 100.0 * (total - spend) / total) if total else 0.0
        day = int(budget.get("reset_day") or 1)
        nxt = now.replace(day=day, hour=0, minute=0, second=0, microsecond=0)
        if nxt <= now:
            nxt = (nxt.replace(day=1) + timedelta(days=32)).replace(day=day)
        return {"source": "estimate", "label": "ESTIMATE from counted calls vs your monthly budget",
                "budget_inr": total, "remaining_pct": round(left, 1), "used_pct": round(100 - left, 1),
                "reset_at": nxt.isoformat()}
    return {"source": "unknown", "label": "UNKNOWN -- the provider does not report a balance here; set a monthly "
                                          "budget for an estimate", "remaining_pct": None, "used_pct": None,
            "reset_at": None}


def overview(container: Any, db_path: str, *, now: datetime | None = None,
             usage_rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    today, month = now.date().isoformat(), now.strftime("%Y-%m")
    if usage_rows is None:
        try:
            from app.api.routes.growth import growth

            usage_rows = growth(container).usage(days=40)
        except Exception:
            usage_rows = []
    budgets = settings(db_path)
    rows = []
    for name, meta in PROVIDERS.items():
        live = _state(name, container)
        usage = _usage(usage_rows, meta["usage"], today, month)
        budget = budgets.get(name)
        credits = _credits(name, live, usage, budget, now)
        rows.append({
            "provider": name, "label": meta["label"], "state": live["state"],
            "failure_type": _FAILURE_TYPE.get(live["state"]),
            "credits": credits,
            "usage": {"daily": usage["daily"], "monthly": usage["monthly"]} if meta["usage"] else
                     {"note": "calls are not counted for this provider yet"},
            "cost": {"estimated_inr": usage["estimated_cost_inr"], "actual_inr": None,
                     "actual_label": "UNKNOWN -- see the provider's bill"},
            "rate_limit": {"per_second": credits.get("rate_limit_per_second")} if credits.get("rate_limit_per_second")
                          else {"label": "UNKNOWN"},
            "fallback": meta["fallback"],
            "dashboard_url": (budget or {}).get("dashboard_url") or meta["dashboard"],
            "recharge": NO_RECHARGE,
            "timestamps": {"last_checked_at": live.get("last_checked_at"),
                           "last_success_at": live.get("last_success_at")},
            "http_status": live.get("http_status"),
            "_history": usage["history"],
        })
    return {"generated_at": now.isoformat(), "providers": rows, "thresholds": list(THRESHOLDS),
            "recharge_policy": NO_RECHARGE}


def _alert(conn, key: str, provider: str, kind: str, severity: str, message: str, evidence: str, now: float) -> bool:
    cur = conn.execute("INSERT OR IGNORE INTO api_billing_alerts(alert_key, provider, kind, severity, message, "
                       "evidence, status, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                       (key, provider, kind, severity, message, evidence, "OPEN", now, now))
    return cur.rowcount > 0


def scan(container: Any, db_path: str, *, now: datetime | None = None,
         usage_rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Raise the alerts the current numbers justify (each once per period)."""
    now = now or datetime.now(timezone.utc)
    data = overview(container, db_path, now=now, usage_rows=usage_rows)
    today, month = now.date().isoformat(), now.strftime("%Y-%m")
    created = []
    with closing(_connect(db_path)) as conn:
        for row in data["providers"]:
            p, credits = row["provider"], row["credits"]
            left = credits.get("remaining_pct")
            if left is not None:
                crossed = [t for t in THRESHOLDS if left <= t]
                if crossed:
                    t = min(crossed)
                    est = credits["source"] == "estimate"
                    msg = (f"{row['label']}: {left:.0f}% remaining ({'estimate' if est else 'reported by provider'})"
                           f" -- {'recharge or raise the quota' if t == 0 else 'below ' + str(t) + '%'}. {NO_RECHARGE}")
                    if _alert(conn, f"{p}:remaining:{t}:{month}", p, "low_balance",
                              "red" if t <= 5 else "orange", msg, credits["label"], now.timestamp()):
                        created.append(f"{p}:remaining:{t}")
            daily = (row["usage"] or {}).get("daily") or {}
            history = row["_history"]
            past = [history.get((now.date() - timedelta(days=d)).isoformat(), 0) for d in range(1, 8)]
            avg = sum(past) / 7.0
            calls = int(daily.get("calls") or 0)
            if calls >= 20 and calls > 3 * max(avg, 1):
                if _alert(conn, f"{p}:spike:{today}", p, "spend_spike", "orange",
                          f"{row['label']}: {calls} calls today vs {avg:.0f}/day over the last 7 days.",
                          "counted calls (growth_api_usage)", now.timestamp()):
                    created.append(f"{p}:spike")
            errors = int(daily.get("errors") or 0)
            if errors >= 5 and errors >= 0.5 * max(calls, 1):
                if _alert(conn, f"{p}:failures:{today}", p, "repeated_failures", "red",
                          f"{row['label']}: {errors} failed calls today ({row['failure_type'] or 'cause unknown'}).",
                          "counted errors (growth_api_usage) + provider state", now.timestamp()):
                    created.append(f"{p}:failures")
            if row["failure_type"] in ("credential", "billing_quota", "downtime", "rate_limit"):
                if _alert(conn, f"{p}:{row['failure_type']}:{today}", p, row["failure_type"],
                          "red" if row["failure_type"] in ("credential", "billing_quota") else "orange",
                          f"{row['label']}: {row['state']} (HTTP {row.get('http_status') or '-'}).",
                          "last real call", now.timestamp()):
                    created.append(f"{p}:{row['failure_type']}")
        conn.commit()
    return {"created": created, "alerts": alerts(db_path)}


def alerts(db_path: str, *, include_resolved: bool = False) -> list[dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        sql = "SELECT * FROM api_billing_alerts" + ("" if include_resolved else " WHERE status != 'RESOLVED'")
        return [dict(r) for r in conn.execute(sql + " ORDER BY created_at DESC LIMIT 200").fetchall()]


def act(db_path: str, alert_id: int, action: str, *, actor: str) -> dict[str, Any] | None:
    status = {"acknowledge": "ACKNOWLEDGED", "resolve": "RESOLVED"}.get(action)
    if status is None:
        raise ValueError("action must be acknowledge or resolve")
    with closing(_connect(db_path)) as conn:
        n = conn.execute("UPDATE api_billing_alerts SET status=?, updated_at=?, acted_by=? WHERE id=?",
                         (status, time.time(), actor, alert_id)).rowcount
        conn.commit()
        row = conn.execute("SELECT * FROM api_billing_alerts WHERE id=?", (alert_id,)).fetchone()
    return dict(row) if n and row else None
