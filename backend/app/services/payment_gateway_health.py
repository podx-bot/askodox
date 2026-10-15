"""ONE truthful Razorpay gateway state for every screen (public
/health/integrations, Integration readiness, API Health & Billing, Billing).

The key check is Razorpay's own answer to an authenticated, read-only call
(GET /v1/payments?count=1 -- nothing is created, captured or refunded),
cached for CHECK_TTL seconds (a staff "Check with gateway" forces a fresh one,
at most once per FORCE_MIN_INTERVAL). A passed check is recorded on the
integration row (last_check_ok), so readiness pages stop saying "not
verified"; only an authentication refusal (HTTP 401) is recorded as a failure
-- a network blip never switches checkout off. Webhook evidence comes from
the signature-verified events actually stored (pf_payment_events). Nothing
here returns a key, a secret or a signature.
"""
from __future__ import annotations

import sqlite3
import time
from datetime import datetime, timezone
from typing import Any, Dict

CHECK_TTL = 900.0
FORCE_MIN_INTERVAL = 60.0
_CACHE: Dict[str, Any] = {}       # until, ok, detail, checked_at, forced_at
WEBHOOK_REJECTIONS = {"count": 0, "last_at": None}  # per process: bad signatures on the Razorpay webhook


def note_webhook_rejected() -> None:
    WEBHOOK_REJECTIONS["count"] += 1
    WEBHOOK_REJECTIONS["last_at"] = datetime.now(timezone.utc).isoformat()


def _webhook_evidence(db_path: str) -> Dict[str, Any]:
    try:
        with sqlite3.connect(db_path) as conn:
            row = conn.execute(
                "SELECT COUNT(*), MAX(received_at) FROM pf_payment_events WHERE provider='razorpay' "
                "AND provider_event_id NOT LIKE 'checkout:%'").fetchone()
    except sqlite3.Error:
        row = (0, None)
    return {"verified_events": int(row[0] or 0), "last_verified_at": row[1],
            "rejected_signatures_since_deploy": WEBHOOK_REJECTIONS["count"],
            "last_rejected_at": WEBHOOK_REJECTIONS["last_at"]}


def check(container: Any, *, force: bool = False) -> Dict[str, Any]:
    from app.api.routes.command_center import feature_enabled
    from app.api.routes.platform import platform
    from app.services import comms
    from app.services import commerce_finance as fin

    pf = platform(container)
    reg = pf.registry
    st = reg.status("razorpay")
    kind = fin.key_kind("razorpay", reg.config_value("razorpay", "key_id"))
    out: Dict[str, Any] = {
        "provider": "razorpay", "mode": st["mode"], "key_kind": kind,
        "webhook_signing": "set" if "webhook_secret" in st["secrets_set"] else "not set",
        "enabled_by": st.get("enabled_by") or ("command_center" if st["enabled"] else ""),
        "webhooks": _webhook_evidence(container.settings.database_path),
        "live_payments_approved": bool(st.get("live_approved")),
    }
    if st["missing"]:
        return {**out, "state": "NEEDS_CONFIGURATION", "key_check": "NOT_RUN", "checkout_ready": False,
                "reason": "Razorpay API keys are not set in the deployment"}
    if st.get("live_locked"):
        return {**out, "state": "LIVE_MODE_LOCKED", "key_check": "NOT_RUN", "checkout_ready": False,
                "reason": "live key without the Owner's approval: takes no payment"}
    if st["status"] == fin.STATUS_DISABLED:
        return {**out, "state": "DISABLED", "key_check": "NOT_RUN", "checkout_ready": False,
                "reason": "switched off in the Command Center"}
    now = time.monotonic()
    fresh = force and now - float(_CACHE.get("forced_at") or -1e9) >= FORCE_MIN_INTERVAL
    if fresh or float(_CACHE.get("until") or 0) < now:
        http = getattr(container, "comms_http", None) or comms.default_http
        try:
            ok, detail = comms.probe_razorpay(reg, http)
        except Exception as error:
            ok, detail = False, f"unreachable ({type(error).__name__})"
        _CACHE.update(until=now + CHECK_TTL, ok=ok, detail=str(detail)[:160],
                      checked_at=datetime.now(timezone.utc).isoformat())
        if fresh:
            _CACHE["forced_at"] = now
        if ok or str(detail).startswith("HTTP 401"):
            try:
                reg.record_check("razorpay", ok, "read-only key check: " + str(detail)[:120])
            except Exception:
                pass
    ok = bool(_CACHE.get("ok"))
    auth_failed = str(_CACHE.get("detail") or "").startswith("HTTP 401")
    state = (("TEST_MODE_VERIFIED" if kind == "test" else "LIVE") if ok
             else "CREDENTIAL_ERROR" if auth_failed else "CHECK_FAILED")
    ready = bool(ok and feature_enabled(container, "payments.online") and pf.checkout_provider() == "razorpay")
    return {**out, "state": state, "key_check": "OK" if ok else "FAILED", "checked_at": _CACHE.get("checked_at"),
            "checkout_ready": ready,
            "reason": ("test keys accepted by Razorpay (authenticated read-only check); TEST mode moves no real "
                       "money" if ok and kind == "test" else "keys accepted by Razorpay" if ok
                       else "Razorpay refused the keys (HTTP 401)" if auth_failed
                       else "Razorpay could not be reached for the check; checkout is unchanged")}
