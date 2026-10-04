import os
from fastapi import APIRouter, Request

from app.services.runtime_readiness_service import RuntimeReadinessService

router = APIRouter(tags=["Health"])


def _readiness_payload(settings, database_ok: bool) -> dict:
    readiness = RuntimeReadinessService(settings).check()
    live_test_ready = bool(database_ok and readiness.whatsapp_ready and readiness.webhook_ready)
    return {
        "status": "ready" if live_test_ready else "degraded",
        "live_test_ready": live_test_ready,
        "database_ready": bool(database_ok),
        "critical": {
            "whatsapp_send": readiness.whatsapp_ready,
            "webhook_verify": readiness.webhook_ready,
        },
        "optional": {
            "voice_stt": readiness.voice_stt_ready,
            "voice_tts": readiness.voice_tts_ready,
            "image_ai": readiness.image_ai_ready,
            "maps": readiness.maps_ready,
            "live_web_search": readiness.live_web_ready,
            "universal_ai": readiness.universal_ai_ready,
        },
        "warnings": list(readiness.warnings),
        "payment_policy": {
            "podx_platform_charge": 0,
            "gateway_required_for_testing": False,
        },
    }


@router.get("/")
def home() -> dict:
    return {
        "status": "Running",
        "app": "ASKODOX",
    }


@router.get("/health")
def health() -> dict:
    """Process liveness probe for Railway and load balancers.

    Keep this endpoint dependency-free so transient database or external-service
    problems do not make a healthy application process fail deployment health
    checks. Dependency readiness is reported by /readiness instead.
    """
    return {
        "status": "healthy",
        "app": "ASKODOX",
        # The deployed commit (public, not a secret): lets a smoke test wait
        # until an environment serves exactly the pushed code.
        "commit": os.getenv("RAILWAY_GIT_COMMIT_SHA", "")[:12],
    }


@router.get("/readiness")
def readiness(request: Request) -> dict:
    """Safe pre-live-test readiness summary. Never returns API keys or tokens."""
    container = request.app.state.container
    try:
        database_ok = bool(container.database.health_check())
    except Exception:
        database_ok = False
    payload = _readiness_payload(container.settings, database_ok)
    # External integrations: status words only (never values, field names or reasons).
    try:
        from app.api.routes.platform import platform

        registry = platform(container).registry
        items = [item for item in registry.all() if not item["internal"]]
        payload["integrations"] = {item["provider"]: item["status"] for item in items}
        payload["integration_readiness"] = {item["provider"]: item["readiness"] for item in items}
        payload["environment"] = os.getenv("RAILWAY_ENVIRONMENT_NAME", "") or "local"
    except Exception:
        payload["integrations"] = {}
    payload["web_search"] = _search_health(container)
    return payload


def _search_health(container) -> dict:
    """What the web-search provider last answered: state, HTTP status, its
    error code and rate-limit counters (no key, no query text)."""
    provider = getattr(container, "brave_web_search_provider", None)
    if provider is None or not hasattr(provider, "health_snapshot"):
        return {"state": "unavailable"}
    snap = provider.health_snapshot()
    return {k: snap.get(k) for k in ("state", "http_status", "provider_code", "rate", "at", "last_ok_at",
                                     "paused_for_seconds") if snap.get(k) is not None}


@router.get("/health/search")
def search_health(request: Request) -> dict:
    return _search_health(request.app.state.container)


_MAPS_HEALTH: dict = {}
MAPS_HEALTH_TTL = 900  # one live check per 15 minutes at most (each call is a paid Google request)


def _clean_google_message(text: str) -> str:
    import re

    return re.sub(r"\b\d{6,}\b", "<project>", str(text or ""))[:200]


@router.get("/health/maps")
def maps_health(request: Request) -> dict:
    """Which Google Maps APIs answer for the deployed key -- per API OK /
    FAILED with Google's own error text (project numbers masked, never the
    key). Live-checked at most once per 15 minutes, then served from memory."""
    import time

    from app.services import rate_limit

    rate_limit.check(request, "maps_health", limit=20)
    now = time.monotonic()
    if _MAPS_HEALTH.get("until", 0) > now:
        return _MAPS_HEALTH["body"]
    maps = getattr(request.app.state.container, "google_maps_service", None)
    if maps is None or not getattr(maps, "enabled", False):
        body = {"configured": False, "apis": {}, "note": "GOOGLE_MAPS_API_KEY is not set on this deployment"}
    else:
        from datetime import datetime, timezone

        status = maps.api_status()
        body = {"configured": True, "checked_at": datetime.now(timezone.utc).isoformat(),
                "apis": {k: _clean_google_message(v) for k, v in status.items()},
                "all_ok": all(v == "OK" for v in status.values())}
    _MAPS_HEALTH.update(until=now + MAPS_HEALTH_TTL, body=body)
    return body
