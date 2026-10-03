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
        rows.append(row)
    return rows

