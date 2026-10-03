"""Support handoff package: what a human agent needs at a glance when the
in-app assistant hands a conversation over -- issue, a short factual
summary, what the customer was trying to get (request + category), what
was already tried, the deal / order status, and the next step. Built only
from what the conversation actually contains (no AI guesswork), with
contact details masked.
"""
from __future__ import annotations

from typing import Any, Dict, List

from app.services.pii_mask import mask


def _clip(text: Any, n: int) -> str:
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


def _request_of(requirement: Dict[str, Any]) -> str:
    for key in ("subject", "item", "product", "service", "need", "query", "title"):
        if requirement.get(key):
            return _clip(mask(requirement[key]), 120)
    return ""


def build(*, issue: str, category: str, context: Dict[str, Any]) -> Dict[str, Any]:
    conversation: List[Dict[str, Any]] = list(context.get("conversation") or [])
    requirement = dict(context.get("requirement") or {})
    user_turns = [_clip(mask(t.get("text") or t.get("content") or ""), 200) for t in conversation
                  if str(t.get("role") or "") == "user"]
    user_turns = [t for t in user_turns if t]
    request = _request_of(requirement) or (user_turns[0] if user_turns else "")
    request_category = str(requirement.get("category") or requirement.get("domain") or "").strip()
    tried = [_clip(a, 80) for a in (context.get("actions_tried") or []) if str(a).strip()]
    status = str(context.get("status") or "").strip()
    parts = [f"Customer needs help with: {_clip(mask(issue), 160)}."]
    if request:
        parts.append(f"They were looking for {request}" + (f" ({request_category})" if request_category else "") + ".")
    if context.get("deal_id"):
        parts.append(f"Related deal/order {context['deal_id']}" + (f", status {status}" if status else "") + ".")
    elif status:
        parts.append(f"Status: {status}.")
    if tried:
        parts.append("Already tried: " + "; ".join(tried[-5:]) + ".")
    if context.get("ai_attempted"):
        parts.append("The in-app assistant answered first and could not resolve it.")
    next_step = ("Check the deal/order with the other party" if context.get("deal_id")
                 else "Reply to the customer with the next step" if request else "Ask what they need")
    return {
        "issue": _clip(mask(issue), 300),
        "summary": " ".join(parts),
        "request": request,
        "request_category": request_category,
        "support_category": category,
        "previous_actions": tried[-10:],
        "status": status,
        "deal_id": context.get("deal_id"),
        "role": context.get("active_role") or "",
        "language": context.get("locale") or "",
        "last_messages": user_turns[-3:],
        "ai_attempted": bool(context.get("ai_attempted")),
        "suggested_next_step": next_step,
    }
