"""Social Auto-DM: a registered business's approved auto-responses
(``auto_response_rules``) answering Facebook Page / Instagram direct
messages through Meta's Messenger Platform.

Built internally and testable end to end in MOCK mode:
  * the ASKODOX Meta app's credentials live in the Integration registry
    (provider ``meta_messaging``: app_secret + verify_token, encrypted,
    write-only); the mode decides delivery (mock = never contacts Meta);
  * a business's Page / Instagram account is linked by staff in
    ``social_dm_accounts`` (PENDING -> ACTIVE after ownership is checked);
    its Page access token is stored encrypted here, write-only;
  * inbound webhooks are accepted only with a valid X-Hub-Signature-256;
    the reply comes from the SAME ``auto_response.answer`` as ASKODOX chat
    (approved FAQ only, hours, handoff words, masked contacts, limits).

EXTERNAL SETUP REQUIRED (never claimed live): Meta App Review for
``pages_messaging`` / ``instagram_manage_messages`` and each business
connecting its Page. WhatsApp auto-DM needs the business's OWN WhatsApp
Business number (Meta Tech Provider / Embedded Signup) -- not the ASKODOX
number. Snapchat offers no public business messaging API.
"""
from __future__ import annotations

import hashlib
import hmac
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

from app.services import auto_response
from app.services import commerce_finance as fin

PROVIDER = "meta_messaging"
GRAPH_VERSION = "v21.0"
META_CHANNELS = ("facebook", "instagram")
NOT_AVAILABLE = {"snapchat": "Snapchat has no public business messaging API."}
EXTERNAL_ONLY = {"whatsapp": "Needs the business's own WhatsApp Business number connected through Meta's Tech "
                             "Provider / Embedded Signup -- not the ASKODOX number."}
META_SETUP = ("EXTERNAL SETUP REQUIRED: Meta App Review (pages_messaging / instagram_manage_messages), the "
              "ASKODOX Meta app credentials in Command Center -> Integrations -> Meta messaging, and the "
              "business's Page token.")

Http = Callable[..., Tuple[int, Any]]


class TokenStore:
    """Per-account Page access tokens, encrypted with the registry's secret box. Write-only."""

    def __init__(self, db_path: str, box: Any) -> None:
        self.db_path, self.box = db_path, box
        with self._connect() as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS social_dm_tokens (channel TEXT NOT NULL, account_id TEXT NOT "
                         "NULL, token_enc TEXT NOT NULL, updated_by TEXT, updated_at TEXT, PRIMARY KEY(channel, "
                         "account_id))")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def set(self, channel: str, account_id: str, token: str, *, actor: str) -> None:
        if self.box is None or not getattr(self.box, "configured", False):
            raise PermissionError("ASKODOX_SECRETS_KEY is not configured -- tokens cannot be stored")
        with self._connect() as conn:
            conn.execute("INSERT INTO social_dm_tokens VALUES (?,?,?,?,?) ON CONFLICT(channel, account_id) DO UPDATE "
                         "SET token_enc=excluded.token_enc, updated_by=excluded.updated_by, "
                         "updated_at=excluded.updated_at",
                         (channel, account_id, self.box.encrypt(token), actor,
                          datetime.now(timezone.utc).isoformat()))

    def delete(self, channel: str, account_id: str) -> None:
        with self._connect() as conn:
            conn.execute("DELETE FROM social_dm_tokens WHERE channel=? AND account_id=?", (channel, account_id))

    def get(self, channel: str, account_id: str) -> str:
        with self._connect() as conn:
            row = conn.execute("SELECT token_enc FROM social_dm_tokens WHERE channel=? AND account_id=?",
                               (channel, account_id)).fetchone()
        if not row or self.box is None:
            return ""
        try:
            return self.box.decrypt(row["token_enc"])
        except Exception:
            return ""

    def has(self, channel: str, account_id: str) -> bool:
        with self._connect() as conn:
            return conn.execute("SELECT 1 FROM social_dm_tokens WHERE channel=? AND account_id=?",
                                (channel, account_id)).fetchone() is not None


def channel_status(registry: Optional[fin.IntegrationRegistry], channel: str) -> Dict[str, str]:
    """LIVE only when the registry says so (real credentials + passed check)."""
    if channel == "askodox_chat":
        return {"status": "LIVE", "reason": "ASKODOX deal chats"}
    if channel in NOT_AVAILABLE:
        return {"status": "NOT_AVAILABLE", "reason": NOT_AVAILABLE[channel]}
    if channel in EXTERNAL_ONLY or channel not in META_CHANNELS or registry is None:
        return {"status": "EXTERNAL_SETUP_REQUIRED", "reason": EXTERNAL_ONLY.get(channel, META_SETUP)}
    state = registry.status(PROVIDER)["status"]
    if state == fin.STATUS_LIVE:
        return {"status": "LIVE", "reason": "Meta app verified; replies go to linked accounts with a token"}
    if state == fin.STATUS_MOCK:
        return {"status": "MOCK", "reason": "mock mode: replies are recorded, nothing is sent to Meta"}
    if state == fin.STATUS_TEST:
        return {"status": "CONFIGURED_NOT_VERIFIED", "reason": "credentials present; run Check in Integrations"}
    return {"status": "EXTERNAL_SETUP_REQUIRED", "reason": META_SETUP}


def verify_signature(app_secret: str, raw: bytes, header: str) -> bool:
    if not app_secret or not header.startswith("sha256="):
        return False
    expected = hmac.new(app_secret.encode(), raw, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header[7:])


def parse_inbound(payload: Dict[str, Any]) -> List[Dict[str, str]]:
    """Messenger / Instagram webhook -> text messages (echoes and non-text skipped)."""
    kind = str((payload or {}).get("object") or "")
    channel = {"page": "facebook", "instagram": "instagram"}.get(kind)
    if channel is None:
        return []
    out = []
    for entry in payload.get("entry") or []:
        for item in entry.get("messaging") or []:
            message = item.get("message") or {}
            text = str(message.get("text") or "").strip()
            if not text or message.get("is_echo"):
                continue
            out.append({"channel": channel, "account_id": str((item.get("recipient") or {}).get("id") or
                                                              entry.get("id") or ""),
                        "sender_id": str((item.get("sender") or {}).get("id") or ""), "text": text[:2000],
                        "message_id": str(message.get("mid") or "")})
    return out


def send(registry: fin.IntegrationRegistry, http: Http, tokens: TokenStore, channel: str, account_id: str,
         recipient: str, text: str, *, force_mock: bool = False) -> Dict[str, Any]:
    """One reply. MOCK never contacts Meta; anything not configured is EXTERNAL_SETUP_REQUIRED."""
    state = channel_status(registry, channel)
    if force_mock or state["status"] == "MOCK":
        return {"sent": True, "mode": "mock", "ref": f"mock-{uuid.uuid4().hex[:10]}"}
    if state["status"] not in ("LIVE", "CONFIGURED_NOT_VERIFIED"):
        return {"sent": False, "mode": "none", "error": state["status"], "reason": state["reason"]}
    token = tokens.get(channel, account_id)
    if not token:
        return {"sent": False, "mode": "none", "error": "EXTERNAL_SETUP_REQUIRED",
                "reason": "this business's Page token is not set"}
    version = registry.config_value(PROVIDER, "api_version") or GRAPH_VERSION
    code, data = http("POST", f"https://graph.facebook.com/{version}/me/messages",
                      headers={"Authorization": f"Bearer {token}"},
                      json={"recipient": {"id": recipient}, "messaging_type": "RESPONSE",
                            "message": {"text": text[:1900]}})
    if code == 200 and isinstance(data, dict) and data.get("message_id"):
        return {"sent": True, "mode": "live", "ref": str(data["message_id"])}
    detail = ((data or {}).get("error") or {}).get("code") if isinstance(data, dict) else None
    return {"sent": False, "mode": "live", "error": f"HTTP {code}" + (f" ({detail})" if detail else "")}


def _customer(channel: str, sender: str) -> str:
    return hashlib.sha256(f"socialdm:{channel}:{sender}".encode()).hexdigest()[:16]


def linked_business(records: List[Dict[str, Any]], channel: str, account_id: str) -> Optional[str]:
    for record in records or []:
        data = record.get("data") or {}
        if record.get("status") == "ACTIVE" and not record.get("archived") and data.get("channel") == channel \
                and str(data.get("account_id") or "") == account_id:
            return str(data.get("business_ref") or "") or None
    return None


def handle(pf: Any, registry: fin.IntegrationRegistry, http: Http, tokens: TokenStore, payload: Dict[str, Any], *,
           force_mock: bool = False, at: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Answer every inbound text with the linked business's ACTIVE rule. Each
    outcome is logged as a ``social_dm`` event (customer id hashed)."""
    results = []
    accounts = pf.repo.list("social_dm_accounts")
    rules = pf.repo.list("auto_response_rules")
    for msg in parse_inbound(payload):
        channel, customer = msg["channel"], _customer(msg["channel"], msg["sender_id"])
        outcome: Dict[str, Any] = {"channel": channel, "account_id": msg["account_id"], "customer": customer}
        business = linked_business(accounts, channel, msg["account_id"])
        rule = auto_response.rule_for(rules, business, message=msg["text"], channel=channel, at=at) \
            if business else None
        if business is None:
            outcome["status"] = "no_linked_business"
        elif rule is None:
            outcome["status"] = "no_rule"
        else:
            blocked = _limit(pf, rule, customer)
            if blocked:
                outcome |= {"status": "limited", "reason": blocked}
            else:
                answer = auto_response.answer(msg["text"], rule, at=at)
                outcome |= {"status": answer["status"], "source": answer["source"], "text": answer["text"]}
                if answer["text"]:
                    outcome["delivery"] = send(registry, http, tokens, channel, msg["account_id"], msg["sender_id"],
                                               answer["text"], force_mock=force_mock)
                outcome["handoff_to_owner"] = answer["status"] != "answered"
            outcome["rule"] = rule.get("_id")
        pf.repo.record_event("social_dm", detail={k: v for k, v in outcome.items() if k != "text"} |
                             {"sent": bool((outcome.get("delivery") or {}).get("sent")),
                              "mode": (outcome.get("delivery") or {}).get("mode")})
        results.append(outcome)
    return results


def _limit(pf: Any, rule: Dict[str, Any], customer: str) -> Optional[str]:
    if not (rule.get("daily_limit") or rule.get("per_customer_daily_limit")):
        return None
    since = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    sent = [e for e in pf.repo.events(event="social_dm", since=since, limit=100000)
            if (e.get("detail") or {}).get("rule") == rule.get("_id") and (e.get("detail") or {}).get("sent")]
    mine = [e for e in sent if (e.get("detail") or {}).get("customer") == customer]
    return auto_response.within_limits(rule, sent_today=len(sent), sent_to_customer_today=len(mine))


def probe_meta(registry: fin.IntegrationRegistry, http: Http) -> Tuple[bool, str]:
    """App credentials check: GET /app with the app access token (app_id|app_secret)."""
    app_id = registry.config_value(PROVIDER, "app_id")
    code, data = http("GET", f"https://graph.facebook.com/{GRAPH_VERSION}/app",
                      params={"access_token": f"{app_id}|{registry.secret(PROVIDER, 'app_secret')}"})
    if code == 200 and isinstance(data, dict) and str(data.get("id") or "") == app_id:
        return True, f"Meta app {data.get('name') or app_id} verified"
    return False, f"HTTP {code}"
