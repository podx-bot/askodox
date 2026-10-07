"""Integration readiness: one row per external integration, computed from the
live registry, delivery outbox, sandbox payments and partner tables -- never
from a hand-set flag. "Live" requires real credentials AND a passed live
check (registry status LIVE); a mock delivery proves the wiring only.
"""
from __future__ import annotations

from typing import Any, Dict, List

from app.services import commerce_finance as fin
from app.services.comms import MOCK_DELIVERED

WHERE_TO_ADD = ("Command Center -> Integrations -> {label} -> Configure (stored encrypted, write-only), "
                "or the Railway variables {env} on the environment that should use it")

GROUPS = (
    # (integration, providers, kind)
    ("Payment gateway", ("razorpay", "cashfree", "phonepe", "paytm", "stripe"), "payments"),
    ("WhatsApp", ("whatsapp_cloud",), "whatsapp"),
    ("SMS", ("sms",), "sms"),
    ("Email", ("email",), "email"),
    ("Firebase push", ("fcm_push",), "push"),
    ("YouTube Data API", ("youtube_data",), "youtube"),
    ("Affiliate partners", ("amazon_associates", "flipkart_affiliate", "cuelinks", "admitad"), "affiliate"),
    ("Social auto-DM (Facebook / Instagram)", ("meta_messaging",), "social_dm"),
)


def _where(status: Dict[str, Any]) -> str:
    names = set(status.get("env_vars", {}).values())
    for aliases in (status.get("env_aliases") or {}).values():
        names.update(aliases)
    env = ", ".join(sorted(names)) or "(Command Center only)"
    return WHERE_TO_ADD.format(label=status["label"], env=env)


def readiness(registry: fin.IntegrationRegistry, *, outbox: Any = None, repo: Any = None,
              partners: List[Dict[str, Any]] | None = None) -> List[Dict[str, Any]]:
    outbox_summary = outbox.summary() if outbox is not None else {}
    rows = []
    for name, providers, kind in GROUPS:
        statuses = [registry.status(p) for p in providers]
        live = [s for s in statuses if s["status"] == fin.STATUS_LIVE]
        configured = [s for s in statuses if s["status"] in (fin.STATUS_LIVE, fin.STATUS_TEST)]
        errors = [s for s in statuses if s["status"] == fin.STATUS_ERROR]
        row: Dict[str, Any] = {
            "integration": name,
            "providers": [{"provider": s["provider"], "label": s["label"], "status": s["status"],
                           "mode": s["mode"], "missing": s["missing"], "sources": s["sources"],
                           "last_check_ok": s["last_check_ok"], "last_check_detail": s["last_check_detail"]}
                          for s in statuses],
            "backend_ready": True,
            "admin_control_ready": True,
            "status": "LIVE" if live else ("CONFIGURED_NOT_VERIFIED" if configured else
                                           ("ERROR" if errors else "NOT_CONFIGURED")),
            "real_credential_required": not live,
            "credentials": {s["provider"]: {"required": s["required"],
                                            "env_vars": s.get("env_vars", {}),
                                            "env_aliases": s.get("env_aliases", {})} for s in statuses},
            "where_to_add": _where(statuses[0]) if len(statuses) == 1 else
            "Command Center -> Integrations -> the chosen provider -> Configure",
        }
        if kind in ("whatsapp", "sms", "email", "push"):
            delivered = outbox_summary.get(kind, {})
            row["mock_verified"] = delivered.get(MOCK_DELIVERED, 0) > 0
            row["deliveries"] = delivered
        elif kind == "payments":
            sandbox = [p for p in (repo.payments(limit=500) if repo is not None else [])
                       if p["provider"] == "sandbox_gateway"]
            row["mock_verified"] = any(p["status"] in ("PAID", "FAILED", "REFUNDED", "PARTIALLY_REFUNDED",
                                                         "SETTLED") for p in sandbox)
            row["sandbox_available"] = registry.available("sandbox_gateway")
            row["without_gateway"] = ["cod", "cash_on_pickup", "direct_upi (upi:// link to the seller's own UPI ID)",
                                      "direct_merchant (offline)"]
        elif kind == "youtube":
            row["mock_verified"] = None  # covered by automated tests with recorded API responses
            row["fallback"] = "Real web videos via Brave (already configured) with YouTube oEmbed checks"
        elif kind == "affiliate":
            active = [p for p in (partners or []) if p.get("active")]
            programs = [p for p in (repo.list("affiliate_programs") if repo is not None else [])
                        if p["status"] == "ACTIVE"]
            row["partner_hub_active_partners"] = len(active)
            row["active_affiliate_programs"] = len(programs)
            row["mock_verified"] = None  # tracked /go/af redirects + postbacks covered by automated tests
            if not active and not programs:
                row["status"] = "NOT_CONFIGURED"
                row["real_credential_required"] = True
        elif kind == "social_dm":
            sent = [e for e in (repo.events(event="social_dm", limit=500) if repo is not None else [])
                    if (e.get("detail") or {}).get("sent")]
            row["mock_verified"] = any((e.get("detail") or {}).get("mode") == "mock" for e in sent)
            row["external_setup"] = ("Meta App Review (pages_messaging / instagram_manage_messages); each business "
                                     "connects its Page. WhatsApp auto-DM needs the business's own WhatsApp "
                                     "Business number; Snapchat has no public messaging API.")
        if kind == "affiliate":
            from app.services import marketplace_api

            row["product_apis"] = {p: marketplace_api.status(registry, p)["status"]
                                   for p in marketplace_api.PLATFORM_PROVIDER}
        row["health"], row["health_reason"] = health(row, statuses)
        rows.append(row)
    return rows


HEALTH_STATES = ("LIVE", "CONFIGURED", "DEGRADED", "DISABLED", "NEEDS_CONFIGURATION", "CHECK_FAILED")


def health(row: Dict[str, Any], statuses: List[Dict[str, Any]]) -> tuple:
    """One vocabulary for every integration: LIVE (a real check passed),
    CONFIGURED (credentials present, not yet verified), DEGRADED (live but
    failing deliveries or near its quota), DISABLED, NEEDS_CONFIGURATION,
    CHECK_FAILED. Derived from live state only -- never a hand-set flag."""
    if row["status"] == "ERROR" or any(s["status"] == fin.STATUS_ERROR for s in statuses):
        return "CHECK_FAILED", "the last real check failed"
    if row["status"] == "NOT_CONFIGURED":
        if statuses and all(s["status"] == fin.STATUS_DISABLED and not s["missing"] for s in statuses):
            return "DISABLED", "switched off in the Command Center"
        return "NEEDS_CONFIGURATION", "credentials missing: " + ", ".join(
            sorted({m for s in statuses for m in s["missing"]})[:6]) if any(s["missing"] for s in statuses) \
            else "no active provider"
    if row["status"] == "LIVE":
        failed = int((row.get("deliveries") or {}).get("FAILED", 0) or 0)
        sent = sum(int(v or 0) for v in (row.get("deliveries") or {}).values())
        if sent >= 5 and failed / sent > 0.2:
            return "DEGRADED", f"{failed} of {sent} recent deliveries failed"
        for s in statuses:
            quota = s.get("quota") or {}
            if quota.get("daily_cap") and quota.get("used_today", 0) >= 0.9 * quota["daily_cap"]:
                return "DEGRADED", f"{s['label']} near its daily quota"
        return "LIVE", "a real check passed"
    return "CONFIGURED", "credentials present; run Check to verify"



# ONE truthful state per integration for the owner, verified at runtime:
# LIVE / NOT_CONFIGURED / DEGRADED / ERROR / QUOTA_EXHAUSTED / DISABLED
# (CONFIGURED_NOT_VERIFIED only until the first real check has run).
INTEGRATION_STATES = ("LIVE", "NOT_CONFIGURED", "DEGRADED", "ERROR", "QUOTA_EXHAUSTED", "DISABLED",
                      "CONFIGURED_NOT_VERIFIED")


def integration_state(row: Dict[str, Any]) -> str:
    raw = str(row.get("status") or "").upper()
    if raw in ("QUOTA_EXHAUSTED",):
        return "QUOTA_EXHAUSTED"
    return {"LIVE": "LIVE", "CONFIGURED": "CONFIGURED_NOT_VERIFIED", "DEGRADED": "DEGRADED",
            "DISABLED": "DISABLED", "NEEDS_CONFIGURATION": "NOT_CONFIGURED", "CHECK_FAILED": "ERROR"}.get(
        str(row.get("health") or ""), "ERROR")


def search_state(web: Dict[str, Any]) -> str:
    state = str(web.get("state") or "unknown")
    return {"ok": "LIVE", "unknown": "CONFIGURED_NOT_VERIFIED", "not_configured": "NOT_CONFIGURED",
            "unavailable": "NOT_CONFIGURED", "rate_limited": "DEGRADED", "quota_exhausted": "QUOTA_EXHAUSTED",
            "auth_failed": "ERROR", "bad_request": "DEGRADED"}.get(state, "ERROR")


def runtime_rows(container: Any, *, maps_body: Dict[str, Any] | None, web: Dict[str, Any],
                 flag: Any, partners: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Search fallback, Maps (per API), delivery matching and native video,
    each from live state: the last real call / check, flags and approved
    records -- never a hand-set value."""
    rows: List[Dict[str, Any]] = []
    fallbacks = web.get("fallbacks") or {}
    cse = fallbacks.get("google_cse") if isinstance(fallbacks, dict) else None
    cse_state = {"not_configured": "DISABLED", None: "CONFIGURED_NOT_VERIFIED", "ok": "LIVE",
                 "error": "ERROR", "quota_exhausted": "QUOTA_EXHAUSTED"}.get(cse, "ERROR") \
        if "google_cse" in fallbacks else "DISABLED"
    rows.append({"integration": "Legacy web-search fallback (Google Programmable Search)", "state": cse_state,
                 "reason": ("legacy entitlement only; Google closed Custom Search JSON API to new customers "
                            "on 2026-01-20; Brave remains the primary whole-web provider")
                 if cse_state == "DISABLED" else
                 "legacy provider; used only when Brave fails"})
    if not maps_body or not maps_body.get("configured"):
        rows.append({"integration": "Google Maps", "state": "NOT_CONFIGURED",
                     "reason": "GOOGLE_MAPS_API_KEY is not set on this deployment", "apis": {}})
    else:
        apis = maps_body.get("apis") or {}
        bad = [k for k, v in apis.items() if v != "OK"]
        quota = [k for k in bad if "quota" in str(apis[k]).lower() or "exceeded" in str(apis[k]).lower()]
        state = "LIVE" if not bad else ("QUOTA_EXHAUSTED" if quota and len(quota) == len(bad) else
                                        ("DEGRADED" if len(bad) < len(apis) else "ERROR"))
        rows.append({"integration": "Google Maps", "state": state, "apis": {k: ("OK" if v == "OK" else "FAILED")
                                                                             for k, v in apis.items()},
                     "reason": "every API answered" if not bad else "failing: " + ", ".join(bad),
                     "checked_at": maps_body.get("checked_at")})
    approved = [p for p in partners if p.get("status") == "ACTIVE" and not p.get("archived")]
    online = [p for p in approved if (p.get("data") or {}).get("available")]
    if not flag("delivery.matching"):
        d_state, d_reason = "DISABLED", "delivery.matching flag is off"
    elif not approved:
        d_state, d_reason = "NOT_CONFIGURED", "no approved driver / delivery partner yet"
    else:
        d_state = "LIVE" if online else "DEGRADED"
        d_reason = f"{len(approved)} approved partner(s), {len(online)} online now"
    rows.append({"integration": "Mobility (rides / delivery matching)", "state": d_state, "reason": d_reason})
    # AI / voice providers: from REAL calls (provider_health), never from key
    # presence alone. Sarvam answering HTTP 402 (credit exhausted) shows as
    # QUOTA_EXHAUSTED, not LIVE and not "not configured".
    from app.services import provider_health

    settings = getattr(container, "settings", None)
    for name, label, key_attr, flag_key in (
            ("sarvam_stt", "Sarvam speech-to-text (voice input)", "sarvam_api_key", None),
            ("sarvam_tts", "Sarvam text-to-speech (reply voice)", "sarvam_api_key", "voice.sarvam_tts"),
            ("gemini", "Gemini (conversation brain)", "gemini_api_key", "ai.assistant"),
            ("openai", "OpenAI (AI fallback)", "openai_api_key", None)):
        observed = provider_health.state(
            name, configured=bool(str(getattr(settings, key_attr, "") or "").strip()),
            enabled=bool(flag(flag_key)) if flag_key else True)
        rows.append({"integration": label, "provider": name,
                     "state": "NOT_CONFIGURED" if observed["state"] == provider_health.NEEDS_CONFIGURATION
                     else observed["state"],
                     "reason": observed["reason"], "checked_at": observed["last_checked_at"],
                     "last_success_at": observed["last_success_at"], "last_status_code": observed["last_status_code"]})
    rows.append({"integration": "ASKODOX native video upload",
                 "state": "LIVE" if flag("videos.upload") else "DISABLED",
                 "reason": "stored on the ASKODOX volume; staff review before publishing"})
    rows.append({"integration": "Native Auto-DM (inside ASKODOX)",
                 "state": "LIVE" if flag("autoresponse.enabled") else "DISABLED",
                 "reason": "approved FAQ answers in ASKODOX chats and video messages; no external platform"})
    return rows
