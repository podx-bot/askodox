"""Social Auto-DM (Facebook Page / Instagram) -- see ``app/services/social_dm.py``.

  GET  /webhooks/meta-messaging            Meta subscription check (hub.verify_token)
  POST /webhooks/meta-messaging            inbound DMs; X-Hub-Signature-256 required
  GET  /admin/cc/social-dm                 channel status + linked accounts (autoresponse:view)
  PUT  /admin/cc/social-dm/token           set a Page token, write-only     (autoresponse:manage)
  DELETE /admin/cc/social-dm/token         remove a Page token               (autoresponse:manage)
  POST /admin/cc/social-dm/simulate        run one DM through the real pipeline with MOCK
                                           delivery (never contacts Meta)   (autoresponse:manage)
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from app.api.routes.command_center import _require
from app.api.routes.platform import _audit, platform
from app.services import social_dm

router = APIRouter(tags=["social-dm"])


def _http(container: Any):
    from app.services import comms

    return getattr(container, "comms_http", None) or comms.default_http


def _tokens(pf: Any) -> social_dm.TokenStore:
    return social_dm.TokenStore(pf.repo.db_path, pf.registry.box)


@router.get("/webhooks/meta-messaging", response_class=PlainTextResponse)
def verify(request: Request, hub_mode: str = Query("", alias="hub.mode"),
           hub_verify_token: str = Query("", alias="hub.verify_token"),
           hub_challenge: str = Query("", alias="hub.challenge")) -> str:
    import hmac

    expected = platform(request.app.state.container).registry.secret(social_dm.PROVIDER, "verify_token")
    if hub_mode == "subscribe" and expected and hmac.compare_digest(hub_verify_token, expected):
        return hub_challenge
    raise HTTPException(status_code=403, detail="verification failed")


@router.post("/webhooks/meta-messaging")
async def inbound(request: Request) -> dict:
    container = request.app.state.container
    pf = platform(container)
    secret = pf.registry.secret(social_dm.PROVIDER, "app_secret")
    if not secret:
        raise HTTPException(status_code=503, detail="EXTERNAL SETUP REQUIRED: Meta messaging app_secret is not set")
    raw = await request.body()
    if not social_dm.verify_signature(secret, raw, request.headers.get("x-hub-signature-256") or ""):
        raise HTTPException(status_code=403, detail="bad signature")
    from app.api.routes.in_app_deal import _flag_on

    if not _flag_on(container, "autoresponse.enabled"):
        return {"ok": True, "handled": 0, "status": "switched_off"}
    try:
        payload = json.loads(raw or b"{}")
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid JSON")
    results = social_dm.handle(pf, pf.registry, _http(container), _tokens(pf), payload)
    return {"ok": True, "handled": len(results)}  # Meta only needs a 200; details stay server-side


@router.get("/admin/cc/social-dm")
def status(request: Request) -> dict:
    _require(request, "autoresponse:view")
    pf = platform(request.app.state.container)
    tokens = _tokens(pf)
    accounts = []
    for record in pf.repo.list("social_dm_accounts"):
        data = record.get("data") or {}
        accounts.append({"id": record["id"], "name": data.get("name"), "channel": data.get("channel"),
                         "account_id": data.get("account_id"), "business_ref": data.get("business_ref"),
                         "status": record.get("status"),
                         "token_set": tokens.has(str(data.get("channel")), str(data.get("account_id")))})
    events = pf.repo.events(event="social_dm", limit=200)
    counts: dict[str, int] = {}
    for e in events:
        key = str((e.get("detail") or {}).get("status") or "unknown")
        counts[key] = counts.get(key, 0) + 1
    channels = {c: social_dm.channel_status(pf.registry, c)
                for c in ("askodox_chat", "facebook", "instagram", "whatsapp", "snapchat")}
    return {"channels": channels, "accounts": accounts, "recent": counts,
            "webhook": "/webhooks/meta-messaging",
            "note": "Nothing is sent to Meta unless the channel is LIVE (or CONFIGURED_NOT_VERIFIED while testing) "
                    "and the account has a token. Mock mode records replies only."}


class TokenBody(BaseModel):
    channel: str = Field(pattern="^(facebook|instagram)$")
    account_id: str = Field(min_length=1, max_length=64)
    token: str = Field(default="", max_length=1000)


@router.put("/admin/cc/social-dm/token")
def set_token(body: TokenBody, request: Request) -> dict:
    principal = _require(request, "autoresponse:manage")
    pf = platform(request.app.state.container)
    if not body.token.strip():
        raise HTTPException(status_code=422, detail="token is required")
    try:
        _tokens(pf).set(body.channel, body.account_id, body.token.strip(), actor=principal["id"])
    except PermissionError as error:
        raise HTTPException(status_code=409, detail=str(error))
    _audit(request, principal, "social_dm.token_set", f"social_dm:{body.channel}:{body.account_id}", {})
    return {"ok": True, "token_set": True}


@router.delete("/admin/cc/social-dm/token")
def delete_token(request: Request, channel: str, account_id: str) -> dict:
    principal = _require(request, "autoresponse:manage")
    _tokens(platform(request.app.state.container)).delete(channel, account_id)
    _audit(request, principal, "social_dm.token_delete", f"social_dm:{channel}:{account_id}", {})
    return {"ok": True, "token_set": False}


class SimulateBody(BaseModel):
    channel: str = Field(pattern="^(facebook|instagram)$")
    account_id: str = Field(min_length=1, max_length=64)
    sender_id: str = Field(default="simulated-customer", max_length=64)
    text: str = Field(min_length=1, max_length=2000)


@router.post("/admin/cc/social-dm/simulate")
def simulate(body: SimulateBody, request: Request) -> dict:
    """The real pipeline (linked account -> rule -> approved answer -> limits)
    with MOCK delivery: proves the wiring without contacting Meta."""
    principal = _require(request, "autoresponse:manage")
    container = request.app.state.container
    pf = platform(container)
    payload = {"object": "page" if body.channel == "facebook" else "instagram",
               "entry": [{"id": body.account_id, "messaging": [{
                   "sender": {"id": body.sender_id}, "recipient": {"id": body.account_id},
                   "message": {"mid": "simulated", "text": body.text}}]}]}
    results = social_dm.handle(pf, pf.registry, _http(container), _tokens(pf), payload, force_mock=True)
    _audit(request, principal, "social_dm.simulate", f"social_dm:{body.channel}:{body.account_id}", {})
    return {"results": results, "delivery": "mock (simulation never contacts Meta)"}
