"""Universal Advisor, Demand Intelligence, seller opportunities, platform
settings, Admin Assistant and Staff work queue.

Customer / seller (same API for app and web):
  POST /api/advisor/next                       next decision-relevant question(s) + guidance (public, rate-limited)
  GET  /api/opportunities                      the signed-in seller's demand opportunities (no buyer identity)
  POST /api/opportunities/{id}/open|respond    open / interested / not_relevant

Command Center:
  GET  /admin/cc/demand/insights               demand facts (demand:view)
  GET  /admin/cc/demand/opportunities          unmet demand per rule (demand:view)
  POST /admin/cc/demand/opportunities/preview  who would be alerted and why, who is excluded and why (demand:view)
  POST /admin/cc/demand/opportunities/notify   alert matching sellers (demand:notify, confirm)
  POST /admin/cc/demand/run                    evaluate every ACTIVE rule now (demand:notify, confirm)
  GET  /admin/cc/demand/alerts                 alert log: rule, reasons, sent / opened / responded
  POST /admin/cc/advisor/preview               which questions a sample need would get, and why (advisor:view)
  GET  /admin/cc/settings/effective            platform settings with value + source (config:view)
  POST /admin/cc/assistant/ask                 Admin Assistant over real system data (overview:view)
  GET  /admin/cc/staff/work-queue              the caller's permitted work items (any staff)
"""
from __future__ import annotations

import re
import threading
import time
from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.command_center import _can, _principal, _require, _require_confirm, command_center
from app.services import advisor_engine, demand_insights as di

router = APIRouter(tags=["advisor-demand"])


def _pf(container):
    from app.api.routes.platform import platform

    return platform(container)


def _log(container) -> di.DemandAlertLog:
    log = getattr(container, "demand_alert_log", None)
    if log is None or log.db_path != container.settings.database_path:
        log = di.DemandAlertLog(container.settings.database_path)
        container.demand_alert_log = log
    return log


# ------------------------------------------------------------- advisor --

def advisor_view(container, demand: Dict[str, Any], *, language: str = "en", asked=(), show_now: bool = False
                 ) -> Dict[str, Any]:
    """The advisor block shared by /deals/discover and /api/advisor/next."""
    try:
        from app.services import platform_settings

        repo = _pf(container).repo
        limit = int(platform_settings.get("advisor.max_questions_per_turn"))
        questions = repo.list("advisor_questions")
        if not platform_settings.get("advisor.ask_budget"):
            questions = [q for q in questions if (q.get("data") or {}).get("field") != "budget"]
        view = advisor_engine.advise(demand, questions, repo.list("advisor_rules"), language=language,
                                     limit=limit, asked=asked, show_now=show_now)
        for q in view["questions"]:
            repo.record_event("advisor_question_asked", category=str(demand.get("domain") or "")[:60],
                              detail={"field": q["field"], "question_id": q.get("id"), "required": q["required"]})
        return view
    except Exception as error:  # the advisor never breaks discovery
        return {"questions": [], "ready": True, "guidance": [], "field_states": {},
                "error": type(error).__name__}


_SHOW_NOW = re.compile(r"\b(show( me)?( now)?|just show|results now|చూపించు|చూపండి|दिखाओ|दिखाइए)\b",
                       re.IGNORECASE)


def wants_results_now(text: str) -> bool:
    return bool(_SHOW_NOW.search(text or ""))


class AdvisorNextRequest(BaseModel):
    raw_text: str = Field(min_length=1, max_length=4000)
    subject: str | None = Field(default=None, max_length=300)
    category: str | None = Field(default=None, max_length=80)
    price: float | None = None
    dynamic_fields: dict = Field(default_factory=dict)
    language: str = Field(default="en", max_length=12)
    asked: List[str] = Field(default_factory=list)


@router.post("/api/advisor/next")
def advisor_next(body: AdvisorNextRequest, request: Request) -> dict:
    from app.services import rate_limit

    rate_limit.check(request, "advisor_next", limit=60)
    demand = {"side": "NEED", "domain": (body.category or "").upper(), "subject": body.subject or body.raw_text,
              "raw_text": body.raw_text, "price": body.price,
              "constraints": {"dynamic_fields": dict(body.dynamic_fields or {})}}
    return advisor_view(request.app.state.container, demand, language=body.language, asked=body.asked,
                        show_now=wants_results_now(body.raw_text))


class AdvisorPreviewRequest(BaseModel):
    text: str = Field(min_length=1, max_length=1000)
    category: str = ""
    known: dict = Field(default_factory=dict)
    language: str = "en"


@router.post("/admin/cc/advisor/preview")
def advisor_preview(body: AdvisorPreviewRequest, request: Request) -> dict:
    """'Why did ASKODOX ask this question?' -- the same decision, explained."""
    _require(request, "advisor:view")
    repo = _pf(request.app.state.container).repo
    demand = {"side": "NEED", "domain": body.category.upper(), "subject": body.text, "raw_text": body.text,
              "constraints": {"dynamic_fields": dict(body.known or {})}}
    view = advisor_engine.advise(demand, repo.list("advisor_questions"), repo.list("advisor_rules"),
                                 language=body.language, limit=3)
    view["explanation"] = [
        f"'{q['question']}' -- fills '{q['field']}' ({'required' if q['required'] else 'optional'}); "
        f"{q['why'] or 'configured for this category'}" for q in view["questions"]]
    view["explanation"] += [f"'{f}' already {state.replace('_', ' ')} -- not asked again"
                            for f, state in view["field_states"].items() if state != "unknown"]
    return view


# ------------------------------------------------------ demand (admin) --

@router.get("/admin/cc/demand/insights")
def demand_insights(request: Request, days: int = 7, category: str = "", area: str = "") -> dict:
    _require(request, "demand:view")
    days = max(1, min(int(days or 7), 90))
    return di.insights(_pf(request.app.state.container).repo, days=days, category=category, area=area)


def _rules(container, rule_id: str = "", *, active_only: bool = True) -> List[Dict[str, Any]]:
    rows = _pf(container).repo.list("demand_alert_rules")
    if rule_id:
        rows = [r for r in rows if r["id"] == rule_id]
    elif active_only:
        rows = [r for r in rows if r["status"] == "ACTIVE"]
    return rows


@router.get("/admin/cc/demand/opportunities")
def demand_opportunities(request: Request, rule_id: str = "") -> dict:
    _require(request, "demand:view")
    container = request.app.state.container
    out = []
    for rule in _rules(container, rule_id, active_only=not rule_id):
        for opp in di.opportunities(_pf(container).repo, rule["data"]):
            out.append({**opp, "rule_id": rule["id"], "rule": rule["name"], "rule_status": rule["status"]})
    note = None if out else ("No ACTIVE demand alert rule yet -- create one in Demand alert rules."
                             if not _rules(container) and not rule_id else "No demand passes the rule thresholds.")
    return {"items": out, "note": note}


class OpportunityAction(BaseModel):
    rule_id: str
    opportunity_key: str
    confirm: bool = False


def _find(container, body: OpportunityAction):
    rules = _rules(container, body.rule_id, active_only=False)
    if not rules:
        raise HTTPException(status_code=404, detail="Rule not found")
    rule = rules[0]
    opp = next((o for o in di.opportunities(_pf(container).repo, rule["data"]) if o["key"] == body.opportunity_key),
               None)
    if opp is None:
        raise HTTPException(status_code=404, detail="That demand no longer passes this rule")
    return rule, opp


@router.post("/admin/cc/demand/opportunities/preview")
def demand_preview(body: OpportunityAction, request: Request) -> dict:
    _require(request, "demand:view")
    container = request.app.state.container
    rule, opp = _find(container, body)
    result = di.send(container, _pf(container).repo, _log(container), opp, rule["data"], rule_id=rule["id"],
                     actor="preview", dry_run=True)
    return {"opportunity": opp, "rule": rule["name"], **result}


@router.post("/admin/cc/demand/opportunities/notify")
def demand_notify(body: OpportunityAction, request: Request) -> dict:
    principal = _require(request, "demand:notify")
    _require_confirm(body.confirm, "alert matching sellers")
    container = request.app.state.container
    rule, opp = _find(container, body)
    if rule["status"] != "ACTIVE":
        raise HTTPException(status_code=409, detail="Enable the rule before sending alerts with it")
    result = di.send(container, _pf(container).repo, _log(container), opp, rule["data"], rule_id=rule["id"],
                     actor=principal["id"])
    if not result["eligible"] and result["status"] == "no_eligible_recipients":
        result["note"] = "No eligible seller: invite / recruit sellers for this need (nobody was messaged)."
    command_center(container).audit(principal["id"], "demand.notify", "demand_opportunity", opp["key"],
                                    after={"rule": rule["id"], "sent": result["sent"], "subject": opp["subject"]},
                                    role=principal.get("role"))
    return {"opportunity": opp, **result}


def run_rules(container, *, actor: str = "rules", mode: str | None = None) -> Dict[str, Any]:
    summary = {"rules": 0, "opportunities": 0, "sent": 0, "details": []}
    for rule in _rules(container):
        if mode and (rule["data"].get("mode") or "instant") != mode:
            continue
        summary["rules"] += 1
        for opp in di.opportunities(_pf(container).repo, rule["data"]):
            summary["opportunities"] += 1
            result = di.send(container, _pf(container).repo, _log(container), opp, rule["data"],
                             rule_id=rule["id"], actor=actor)
            summary["sent"] += result["sent"]
            summary["details"].append({"rule": rule["id"], "subject": opp["subject"], "area": opp["area"],
                                       "status": result["status"], "sent": result["sent"]})
    return summary


class RunBody(BaseModel):
    confirm: bool = False
    mode: str | None = None


@router.post("/admin/cc/demand/run")
def demand_run(body: RunBody, request: Request) -> dict:
    principal = _require(request, "demand:notify")
    _require_confirm(body.confirm, "evaluate all active demand rules and alert sellers")
    container = request.app.state.container
    summary = run_rules(container, actor=principal["id"], mode=body.mode)
    command_center(container).audit(principal["id"], "demand.run", "demand_rules", "all",
                                    after={k: summary[k] for k in ("rules", "opportunities", "sent")},
                                    role=principal.get("role"))
    return summary


_LAST_AUTO = {"at": 0.0}
AUTO_INTERVAL_SECONDS = 600


def maybe_run_instant_rules(container) -> None:
    """Called after new demand: evaluates ACTIVE 'instant' rules at most once
    per 10 minutes per process, in the background. Never raises."""
    if time.monotonic() - _LAST_AUTO["at"] < AUTO_INTERVAL_SECONDS:
        return
    _LAST_AUTO["at"] = time.monotonic()

    def run():
        try:
            run_rules(container, actor="rules:instant", mode="instant")
        except Exception:
            pass

    threading.Thread(target=run, daemon=True).start()


@router.get("/admin/cc/demand/alerts")
def demand_alerts(request: Request, opportunity_key: str = "", limit: int = 200) -> dict:
    _require(request, "demand:view")
    return {"items": _log(request.app.state.container).listing(limit=max(1, min(limit, 1000)),
                                                                opportunity_key=opportunity_key)}


# --------------------------------------------- seller opportunities (Party B) --

def _seller(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


@router.get("/api/opportunities")
def my_opportunities(request: Request, language: str = "en") -> dict:
    """Demand relevant to what this seller offers. Aggregate only: how many
    customers, what, where, budget band -- never who."""
    seller = _seller(request)
    items = []
    for alert in _log(request.app.state.container).for_recipient(seller):
        text = di.alert_text({"searches": alert["searches"], "subject": alert["subject"], "area": alert["area"],
                              "budget_band": alert["budget_band"]}, language[:2])
        items.append({"id": alert["id"], "subject": alert["subject"], "area": alert["area"],
                      "searches": alert["searches"], "budget_band": alert["budget_band"], "sent_at": alert["sent_at"],
                      "opened_at": alert["opened_at"], "response": alert["response"], **text})
    return {"items": items}


class OpportunityResponse(BaseModel):
    response: str = Field(default="interested", pattern="^(interested|not_relevant|added_offer)$")


@router.post("/api/opportunities/{alert_id}/{action}")
def respond_opportunity(alert_id: int, action: str, request: Request, body: OpportunityResponse | None = None) -> dict:
    if action not in {"open", "respond"}:
        raise HTTPException(status_code=404, detail="Unknown action")
    seller = _seller(request)
    container = request.app.state.container
    item = _log(container).mark(alert_id, seller, action=action,
                                response=(body.response if body else "interested"))
    if item is None:
        raise HTTPException(status_code=404, detail="Opportunity not found")
    if action == "respond":
        _pf(container).repo.record_event("seller_opportunity_response", detail={"alert": alert_id,
                                                                               "response": item["response"]})
    return {"item": {k: item[k] for k in ("id", "subject", "area", "opened_at", "responded_at", "response")}}


# ------------------------------------------------------------- settings --

@router.get("/admin/cc/settings/effective")
def effective_settings(request: Request) -> dict:
    _require(request, "config:view")
    from app.services import platform_settings

    _pf(request.app.state.container)  # binds the settings source
    platform_settings.invalidate()
    return {"items": platform_settings.describe()}


# -------------------------------------------------------- admin assistant --

class AskBody(BaseModel):
    question: str = Field(min_length=2, max_length=500)
    days: int = 7


_TOPICS = (
    ("unmet", r"unmet|not find|no result|fail|supply|recruit|need more sellers|where should"),
    ("rising", r"increase|rise|rising|grow|trend|what.*today|spike|why did"),
    ("stock", r"stock|out of stock"),
    ("commission", r"commission|affiliate"),
    ("integrations", r"integration|failing|broken|health|down"),
    ("sellers", r"seller|respond|not responding|provider"),
    ("staff", r"staff|work on|today's work|what should"),
)


@router.post("/admin/cc/assistant/ask")
def admin_assistant(body: AskBody, request: Request) -> dict:
    """Answers from recorded data only. Every answer separates what was
    OBSERVED, what MIGHT explain it (marked as unverified), and what to DO."""
    principal = _require(request, "overview:view")
    container = request.app.state.container
    text = body.question.casefold()
    topics = [name for name, pattern in _TOPICS if re.search(pattern, text)] or ["rising", "unmet"]
    days = max(1, min(body.days, 90))
    answers = []
    repo = _pf(container).repo
    data = di.insights(repo, days=days) if _can(principal, "demand:view") else None
    for topic in dict.fromkeys(topics):
        if topic in {"unmet", "rising"} and data is None:
            answers.append({"topic": topic, "observed": [], "likely": [],
                            "actions": ["Ask an admin for demand:view to see demand data."]})
            continue
        if topic == "rising":
            rows = data["rising"][:5]
            answers.append({"topic": "rising", "observed": [
                f"'{r['subject']}': {r['now']} searches in {days} days vs {r['before']} before"
                + (f" (+{r['change_pct']}%)" if r["change_pct"] is not None else " (new)") for r in rows]
                or [f"No need grew by 25%+ with at least 3 searches in the last {days} days."],
                "likely": ["Causes are not recorded (season, promotion or local event are possibilities) -- "
                           "check campaigns and dates before concluding."] if rows else [],
                "actions": ["Check supply for the rising needs in Demand -> Opportunities."] if rows else []})
        elif topic == "unmet":
            rows = data["unmet"][:5]
            answers.append({"topic": "unmet", "observed": [
                f"'{r['subject']}': {r['count']} searches with no local supply ({int(r['share_no_local'] * 100)}%)"
                for r in rows] or ["Every recent need had at least one local result."],
                "likely": ["Few or no registered sellers list these items in the searched areas."] if rows else [],
                "actions": ["Preview matching sellers, then notify or recruit (Demand -> Opportunities)."]
                if rows else []})
        elif topic == "stock" and _can(principal, "affiliate_products:view"):
            from app.api.routes.affiliate_catalog import catalog

            listing = catalog(container).list(stock="OUT_OF_STOCK", limit=10)
            answers.append({"topic": "stock", "observed": [f"{listing['summary']['total']} catalog products are "
                                                           "OUT_OF_STOCK (not shown to customers)"]
                            + [f"- {i['title']} ({i['platform_name']})" for i in listing["items"][:5]],
                            "likely": [], "actions": ["Re-check stock on the source page and update it."]})
        elif topic == "commission" and _can(principal, "affiliate_products:view"):
            from app.api.routes.affiliate_catalog import catalog, sources

            listing = catalog(container).list(commission="INACTIVE", limit=10)
            src = [s["name"] for s in sources(container).values() if s.get("commission_state") == "INACTIVE"]
            answers.append({"topic": "commission", "observed": [
                f"{listing['summary']['total']} products have commission INACTIVE (shown organically)"]
                + ([f"Sources with commission INACTIVE: {', '.join(src)}"] if src else []),
                "likely": [], "actions": ["Confirm with the affiliate network, then set the state."]})
        elif topic == "integrations" and _can(principal, "integrations:view"):
            try:
                from app.services.integration_readiness import readiness

                rows = readiness(container)
                items = rows.get("items", rows) if isinstance(rows, dict) else rows
                bad = [f"{i.get('name') or i.get('provider')}: {i.get('status')}" for i in items
                       if str(i.get("status")) in {"ERROR", "FAILED", "DEGRADED"}]
            except Exception as error:
                bad = [f"readiness check unavailable ({type(error).__name__})"]
            answers.append({"topic": "integrations", "observed": bad or ["No integration reports an error."],
                            "likely": [], "actions": ["Open System -> Integration readiness for the reason."]
                            if bad else []})
        elif topic == "sellers" and _can(principal, "demand:view"):
            alerts = _log(container).listing(limit=500)
            per: Dict[str, List[int]] = {}
            for a in alerts:
                per.setdefault(a["recipient"], [0, 0])
                per[a["recipient"]][0] += 1
                per[a["recipient"]][1] += int(bool(a["responded_at"]))
            quiet = [r for r, (n, resp) in per.items() if n >= 3 and resp == 0]
            from app.repositories.command_center_repository import mask_user_id

            answers.append({"topic": "sellers", "observed": [
                f"{len(quiet)} sellers got 3+ demand alerts and answered none"]
                + [f"- {mask_user_id(r)}" for r in quiet[:5]],
                "likely": [], "actions": ["Contact them or lower their alert priority."] if quiet else []})
        elif topic == "staff":
            queue = staff_work_queue(request)
            answers.append({"topic": "staff", "observed": [f"{q['title']}: {q['count']}" for q in queue["items"]],
                            "likely": [], "actions": [q["what_to_do"] for q in queue["items"][:3]]})
    return {"question": body.question, "answers": answers,
            "basis": "Recorded ASKODOX events and records only; nothing is guessed."}


# -------------------------------------------------------- staff work queue --

@router.get("/admin/cc/staff/work-queue")
def staff_work_queue(request: Request) -> dict:
    principal = _principal(request)
    container = request.app.state.container
    items = []
    if _can(principal, "affiliate_products:view"):
        from app.api.routes.affiliate_catalog import catalog

        store = catalog(container)
        unknown = store.list(stock="UNKNOWN", limit=1)["summary"]["total"]
        oos = store.list(stock="OUT_OF_STOCK", limit=1)["summary"]["total"]
        no_comm = store.list(commission="UNKNOWN", limit=1)["summary"]["total"]
        items += [
            {"key": "stock_unknown", "title": "Products with unknown stock", "count": unknown,
             "where": "/admin/console#affproducts", "what_to_do": "Open the source page and set In stock / Out of stock.",
             "why": "Unknown stock is never shown as a fact to customers.", "done_when": "Stock is not UNKNOWN."},
            {"key": "stock_out", "title": "Out-of-stock products to re-check", "count": oos,
             "where": "/admin/console#affproducts", "what_to_do": "Re-check; mark In stock when available again.",
             "why": "Back-in-stock products are re-enabled automatically once marked.", "done_when": "Status current."},
        ]
        if _can(principal, "affiliate_products:commission"):
            items.append({"key": "commission_unknown", "title": "Products with unknown commission", "count": no_comm,
                          "where": "/admin/console#affproducts",
                          "what_to_do": "Confirm with the network and set Active / Inactive.",
                          "why": "Only ACTIVE commission uses the affiliate link.", "done_when": "Not UNKNOWN."})
    if _can(principal, "nomatch:view"):
        rows = command_center(container).no_match_queue(status="OPEN", limit=500)
        items.append({"key": "no_match", "title": "Searches with no match to review", "count": len(rows),
                      "where": "/admin", "what_to_do": "Add a source, category or seller for the need.",
                      "why": "Each is a customer who found nothing.", "done_when": "Status RESOLVED / SOURCE_ADDED."})
    if _can(principal, "demand:view"):
        opps = sum(len(di.opportunities(_pf(container).repo, r["data"])) for r in _rules(container))
        items.append({"key": "demand", "title": "Unmet demand opportunities", "count": opps,
                      "where": "/admin/console#demand", "what_to_do": "Preview matching sellers, then notify or recruit.",
                      "why": "Customers want it and local supply is missing.", "done_when": "Notified or recruited."})
    if _can(principal, "support:view"):
        try:
            from app.api.routes.command_center import _escalations

            open_cases = _escalations(container).list_open(limit=500)
        except Exception:
            open_cases = []
        items.append({"key": "support", "title": "Open support cases", "count": len(open_cases),
                      "where": "/admin/console#support", "what_to_do": "Reply using the context package (no re-asking).",
                      "why": "SLA timers are running.", "done_when": "Resolved or waiting for the user."})
    if _can(principal, "content:view"):
        pending = len([r for r in _pf(container).repo.list("videos") if r["status"] == "PENDING_REVIEW"])
        items.append({"key": "content", "title": "Videos waiting for review", "count": pending,
                      "where": "/admin/console#r:videos", "what_to_do": "Approve or reject with a reason.",
                      "why": "Only reviewed videos are shown.", "done_when": "No PENDING_REVIEW videos."})
    items.sort(key=lambda i: -i["count"])
    return {"role": principal.get("role"), "items": items}
