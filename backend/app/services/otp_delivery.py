"""OTP delivery with provider fallback (Integration Platform, auth category).

The sign-in code is sent through the FIRST configured channel that accepts it,
in the order of the deployment variable ASKODOX_OTP_CHANNELS (default
"whatsapp_template,whatsapp,sms"):

  whatsapp_template  WhatsApp Cloud API with an approved template (registry
                     provider whatsapp_cloud + config template_name) -- the
                     only WhatsApp form Meta delivers to someone who has not
                     messaged the business in the last 24 h.
  whatsapp           the legacy WhatsApp service (free-form text; works only
                     inside the 24 h customer-service window).
  sms                the registry SMS gateway (MSG91 DLT flow / Twilio).

A channel that is not configured is skipped (never "failed"); a configured one
that refuses falls through to the next. The code itself is never logged or
returned -- callers get the channel used and per-channel outcomes.
"""
from __future__ import annotations

import logging
import os
from typing import Any, Callable, Dict, List, Tuple

_log = logging.getLogger("uvicorn.error")
DEFAULT_ORDER = ("whatsapp_template", "whatsapp", "sms")
CHANNELS = DEFAULT_ORDER


def order(env: Dict[str, str] | None = None) -> List[str]:
    raw = (env if env is not None else os.environ).get("ASKODOX_OTP_CHANNELS", "")
    picked = [c.strip().lower() for c in raw.split(",") if c.strip().lower() in CHANNELS]
    return picked or list(DEFAULT_ORDER)


def _registry_ready(reg: Any, provider: str) -> bool:
    try:
        return reg.status(provider)["status"] in ("LIVE", "TEST")
    except Exception:
        return False


def channels(container: Any) -> List[Dict[str, Any]]:
    """Each channel with whether it can send right now (for the Setup Wizard)."""
    out = []
    reg = _registry(container)
    for name in order():
        if name == "whatsapp_template":
            ready = bool(reg and _registry_ready(reg, "whatsapp_cloud")
                         and reg.config_value("whatsapp_cloud", "template_name"))
            need = "WhatsApp Cloud API credentials + an approved authentication template (template_name)"
        elif name == "whatsapp":
            svc = getattr(container, "whatsapp_service", None)
            ready = bool(svc is not None and getattr(svc, "is_configured", lambda: False)())
            need = "WHATSAPP_ACCESS_TOKEN + WHATSAPP_PHONE_NUMBER_ID (free text reaches only users who messaged in 24 h)"
        else:
            ready = bool(reg and _registry_ready(reg, "sms"))
            need = "SMS gateway credentials (MSG91 with an approved DLT template, or Twilio)"
        out.append({"channel": name, "ready": ready, "needs": "" if ready else need})
    return out


def _registry(container: Any) -> Any:
    try:
        from app.api.routes.platform import platform

        return platform(container).registry
    except Exception:
        return None


def deliver(container: Any, mobile: str, text: str, *,
            http: Callable[..., Tuple[int, Any]] | None = None) -> Dict[str, Any]:
    from app.services import comms

    reg = _registry(container)
    http = http or getattr(container, "comms_http", None) or comms.default_http
    attempts: List[Dict[str, Any]] = []
    for item in channels(container):
        name = item["channel"]
        if not item["ready"]:
            attempts.append({"channel": name, "outcome": "not_configured"})
            continue
        mid = None
        try:
            if name == "whatsapp_template":
                ok, mid, err = comms.send_whatsapp(reg, http, mobile, "", text)
            elif name == "whatsapp":
                result = container.whatsapp_service.send_text_message(mobile, text)
                ok, err = bool(result.get("success")), str(result.get("status") or "provider error")
                mid = result.get("provider_message_id")
            else:
                ok, _mid, err = comms.send_sms(reg, http, mobile, "", text)
        except Exception as error:  # one provider failing never blocks the next
            ok, err = False, type(error).__name__
        if ok and name.startswith("whatsapp") and mid:
            # Meta answers 200 when it ACCEPTS a message and reports a failed
            # delivery a moment later on the webhook (e.g. 131047: outside the
            # 24-hour window). Wait briefly for that status before saying "sent".
            confirmed = delivery_confirmation(container, str(mid))
            if confirmed["state"] == "failed":
                ok, err = False, "undelivered: " + confirmed["reason"]
        attempts.append({"channel": name, "outcome": "sent" if ok else "failed",
                         **({} if ok else {"reason": str(err)[:240]})})
        if ok:
            _log.info("otp.delivery channel=%s mobile=...%s", name, str(mobile)[-4:])
            return {"success": True, "channel": name, "attempts": attempts}
        _log.warning("otp.delivery channel=%s failed mobile=...%s reason=%s", name, str(mobile)[-4:], str(err)[:120])
    _log.warning("otp.delivery failed mobile=...%s attempts=%s", str(mobile)[-4:],
                 ",".join(f"{a['channel']}:{a['outcome']}" for a in attempts))
    return {"success": False, "channel": None, "attempts": attempts}


# Meta error codes worth explaining to the person (never shows the number).
META_REASONS = {
    "131047": "WhatsApp delivers this code only if you sent a message to the ASKODOX WhatsApp number in the last "
              "24 hours",
    "131026": "this number cannot receive WhatsApp messages",
    "131049": "WhatsApp did not deliver the message (Meta limited delivery to this number)",
    "130472": "WhatsApp did not deliver the message (this number is part of a Meta experiment)",
    "131056": "too many messages were sent to this number; wait and try again",
}


def _wait_seconds(env: Dict[str, str] | None = None) -> float:
    raw = (env if env is not None else os.environ).get("ASKODOX_OTP_DELIVERY_WAIT_SECONDS", "4")
    try:
        return max(0.0, min(float(raw), 10.0))
    except ValueError:
        return 4.0


def delivery_confirmation(container: Any, message_id: str, *, wait: float | None = None,
                          sleep: Callable[[float], None] | None = None) -> Dict[str, Any]:
    """failed / delivered / unknown for a WhatsApp message id, from the webhook
    statuses stored by /webhook (delivery_statuses). Waits up to ``wait`` s."""
    import time

    repo = getattr(container, "delivery_log_repository", None)
    if repo is None or not message_id:
        return {"state": "unknown", "reason": ""}
    sleep = sleep or time.sleep
    deadline = _wait_seconds() if wait is None else wait
    waited = 0.0
    while True:
        try:
            row = repo.latest_for_message(message_id)
        except Exception:
            row = None
        status = str((row or {}).get("status") or "").lower()
        if status in ("failed", "undelivered", "error"):
            detail = str((row or {}).get("error_message") or "")
            code = ""
            if "META_CODE=" in detail:
                code = detail.split("META_CODE=", 1)[1].split()[0].strip(" ;,|")
            reason = META_REASONS.get(code, "WhatsApp could not deliver the message")
            return {"state": "failed", "reason": reason + (f" (Meta error {code})" if code else ""), "code": code}
        if status in ("sent", "delivered", "read"):
            return {"state": "delivered", "reason": status}
        if waited >= deadline:
            return {"state": "unknown", "reason": "no delivery report yet"}
        sleep(0.25)
        waited += 0.25
