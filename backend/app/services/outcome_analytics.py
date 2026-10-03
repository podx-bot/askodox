"""Outcome analytics over the one event stream (pf_events) plus the alert
log and integration readiness -- computed on read, nothing new stored."""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

FUNNEL = ("search", "results_shown", "result_click", "request", "seller_accept", "order", "order_completed")


def _match(e: Dict[str, Any], *, category: str, location: str, role: str) -> bool:
    if category and category.casefold() not in str(e.get("category") or "").casefold():
        return False
    if location and location.casefold() not in str(e.get("location") or "").casefold():
        return False
    if role and str((e.get("detail") or {}).get("role") or "").casefold() not in ("", role.casefold()):
        return False
    return True


def outcomes(pf, container, *, days: int = 30, category: str = "", location: str = "", source: str = "",
             role: str = "") -> Dict[str, Any]:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    events = [e for e in pf.repo.events(since=since, limit=200000)
              if _match(e, category=category, location=location, role=role)]
    by = Counter(e["event"] for e in events)
    searches = [e for e in events if e["event"] == "search"]
    if source:
        searches = [e for e in searches if source in ((e.get("detail") or {}).get("sources") or {})]
    no_result = [e for e in searches if not (e.get("detail") or {}).get("results")]
    no_local = [e for e in searches if not (e.get("detail") or {}).get("local")]
    src = Counter()
    for e in searches:
        for k, v in ((e.get("detail") or {}).get("sources") or {}).items():
            src[k] += int(v or 0)
    clicks_by_source = Counter(str((e.get("detail") or {}).get("source") or (e.get("detail") or {}).get("segment")
                                   or "unknown") for e in events if e["event"] in ("result_click", "click"))
    gaps = Counter(str((e.get("detail") or {}).get("subject") or "").casefold()[:60] for e in no_local)
    gaps.pop("", None)
    failed = Counter(str((e.get("detail") or {}).get("subject") or "").casefold()[:60] for e in no_result)
    failed.pop("", None)
    advisor_fields = Counter(str((e.get("detail") or {}).get("field") or "") for e in events
                             if e["event"] == "advisor_question_asked")
    rejections = Counter(str((e.get("detail") or {}).get("reason") or "not given") for e in events
                         if e["event"] == "seller_decline" or (e["event"] == "seller_opportunity_response"
                                                             and (e.get("detail") or {}).get("response")
                                                             == "not_relevant"))
    auto = Counter(str((e.get("detail") or {}).get("status") or "") for e in events if e["event"] == "auto_response")
    try:
        from app.api.routes.demand_advisor import _log

        opportunities = _log(container).summary(since=since)
    except Exception:
        opportunities = {}
    try:
        from app.services.integration_readiness import readiness

        health = Counter(r.get("health") for r in readiness(pf.registry, outbox=pf.outbox, repo=pf.repo))
    except Exception:
        health = Counter()
    organic = sum(v for k, v in src.items() if k not in ("affiliate", "sponsored"))
    accepts, declines = by.get("seller_accept", 0), by.get("seller_decline", 0)
    return {
        "filters": {"days": days, "category": category or None, "location": location or None,
                    "source": source or None, "role": role or None},
        "demand": {"searches": len(searches), "no_result_searches": len(no_result),
                   "no_local_supply": len(no_local),
                   "by_category": Counter(e.get("category") or "(unknown)" for e in searches).most_common(15),
                   "by_location": Counter(e.get("location") or "(no location)" for e in searches).most_common(15)},
        "supply_gaps": gaps.most_common(15),
        "failed_searches": failed.most_common(15),
        "funnel": [{"step": step, "count": by.get(step, 0)} for step in FUNNEL],
        "source_performance": {"results": dict(src), "clicks": dict(clicks_by_source)},
        "organic_vs_affiliate": {"organic_results": organic, "affiliate_results": src.get("affiliate", 0),
                                 "sponsored_results": src.get("sponsored", 0),
                                 "affiliate_clicks": by.get("affiliate_click", 0)},
        "advisor": {"questions_asked": by.get("advisor_question_asked", 0), "by_field": dict(advisor_fields)},
        "video": {k: by.get(k, 0) for k in ("video_impression", "video_open", "video_watch_complete", "video_ask",
                                            "video_study", "video_product_click")},
        "offers": {k: by.get(k, 0) for k in ("offer_view", "offer_click", "coupon_claim", "coupon_redeem",
                                             "reward_claim")},
        "seller_response": {"accepted": accepts, "declined": declines,
                            "acceptance_rate": round(accepts / (accepts + declines), 3) if accepts + declines else None,
                            "rejection_reasons": rejections.most_common(10)},
        "opportunities": opportunities,
        "escalations": by.get("support_escalated", 0) + by.get("support_ticket", 0),
        "auto_responses": dict(auto),
        "stock_changes": by.get("stock_changed", 0), "commission_changes": by.get("commission_changed", 0),
        "integration_health": dict(health),
        "basis": "Recorded ASKODOX events only; counts are not estimates.",
    }
