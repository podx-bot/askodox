"""Universal Advisor, Demand Intelligence, seller opportunities, platform
settings, Admin Assistant and Staff work queue.

Customer / seller (same API for app and web):
  POST /api/advisor/next                       next decision-relevant question(s) + guidance (public, rate-limited)
  GET  /api/opportunities                      the signed-in seller's demand opportunities (no buyer identity)
  GET  /api/business/command-center            the seller's facts + labelled insights + actions (en / te)
  POST /api/opportunities/{id}/open|respond    open / interested / not_relevant

Command Center:
  GET  /admin/cc/demand/insights               demand facts (demand:view)
  GET  /admin/cc/demand/opportunities          unmet demand per rule (demand:view)
  GET  /admin/cc/demand/supply-gaps            listing details customers asked for that sellers did not state (demand:view)
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
from app.services import admin_ops, advisor_engine, demand_insights as di

router = APIRouter(tags=["advisor-demand"])


def _pf(container):
    from app.api.routes.platform import platform

    return platform(container)


def _flag(container, key: str) -> bool:
    try:
        return command_center(container).is_enabled(key)
    except Exception:
        return True


def _log(container) -> di.DemandAlertLog:
    log = getattr(container, "demand_alert_log", None)
    if log is None or log.db_path != container.settings.database_path:
        log = di.DemandAlertLog(container.settings.database_path)
        container.demand_alert_log = log
    return log


_FAILING = {"ERROR", "CHECK_FAILED", "DEGRADED", "QUOTA_EXHAUSTED"}


def _failing_integrations(container) -> tuple:
    """(["name: STATE", ...], error) from the same live state the readiness
    page shows; error is set only when the check itself could not run."""
    try:
        from app.api.routes.health import _search_health
        from app.api.routes.platform import integration_runtime
        from app.services.integration_readiness import integration_state, readiness, search_state

        pf = _pf(container)
        web = _search_health(container)
        rows = [(i.get("integration"), integration_state(i))
                for i in readiness(pf.registry, outbox=pf.outbox, repo=pf.repo, partners=[])]
        rows += [("Web search (Brave)", search_state(web))]
        rows += [(r.get("integration"), r.get("state")) for r in integration_runtime(container, web)]
        return [f"{n}: {st}" for n, st in rows if str(st or "").upper() in _FAILING], None
    except Exception as error:
        return [], type(error).__name__


# ------------------------------------------------------------- advisor --

def advisor_view(container, demand: Dict[str, Any], *, language: str = "en", asked=(), show_now: bool = False
                 ) -> Dict[str, Any]:
    """The advisor block shared by /deals/discover and /api/advisor/next."""
    try:
        from app.services import platform_settings

        from app.services import flag_targeting

        if not flag_targeting.enabled(container, "advisor.enabled", flag_targeting.context_for_demand(demand)):
            return {"questions": [], "ready": True, "guidance": [], "field_states": {}, "switched_off": True}
        repo = _pf(container).repo
        limit = int(platform_settings.get("advisor.max_questions_per_turn"))
        skip = () if platform_settings.get("advisor.ask_budget") else ("budget",)
        view = advisor_engine.advise(demand, repo.list("advisor_questions"), repo.list("advisor_rules"),
                                     language=language, limit=limit, asked=asked, show_now=show_now,
                                     category_records=repo.list("advisor_categories"), skip_fields=skip)
        category = (view.get("category") or {}).get("key") or str(demand.get("domain") or "")
        for q in view["questions"]:
            repo.record_event("advisor_question_asked", category=category[:60],
                              detail={"field": q["field"], "question_id": q.get("id"), "required": q["required"],
                                      "matched_by": (view.get("category") or {}).get("matched_by")})
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
    demand = {"side": "NEED", "domain": (body.category or "").upper(), "category": body.category or "",
              "subject": body.subject or body.raw_text,
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
    demand = {"side": "NEED", "domain": body.category.upper(), "category": body.category, "subject": body.text,
              "raw_text": body.text,
              "constraints": {"dynamic_fields": dict(body.known or {})}}
    view = advisor_engine.advise(demand, repo.list("advisor_questions"), repo.list("advisor_rules"),
                                 language=body.language, limit=3, category_records=repo.list("advisor_categories"))
    cat = view.get("category")
    view["explanation"] = ([
        f"Category '{cat['label']}' ({cat['key']}) -- matched by {cat['matched_by'].replace('_', ' ')} "
        f"'{cat['alias']}'; required: {', '.join(cat['required_fields']) or 'none'}; optional: "
        f"{', '.join(cat['optional_fields']) or 'none'}"] if cat else
        ["No advisor category matched -- only legacy keyword questions can apply."])
    view["explanation"] += [
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


@router.get("/admin/cc/demand/supply-gaps")
def demand_supply_gaps(request: Request) -> dict:
    """Seller listings that could not answer a customer's constraint (size,
    price, colour ...), counted per listing + field. Sellers are masked."""
    _require(request, "demand:view")
    from app.repositories.command_center_repository import mask_user_id
    from app.services import supply_fit

    rows = supply_fit.top_gaps(request.app.state.container.settings.database_path)
    for row in rows:
        row["seller"] = mask_user_id(row.pop("seller_user_id"))
    return {"items": rows, "note": "Sellers see these in My business with an Edit listing button."}


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
    if not _flag(container, "demand.alerts"):
        raise HTTPException(status_code=409, detail="Demand alerts are switched off (feature flag demand.alerts)")
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
    if not _flag(container, "demand.alerts"):
        return {**summary, "switched_off": True}
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
    log = _log(request.app.state.container)
    return {"items": log.listing(limit=max(1, min(limit, 1000)), opportunity_key=opportunity_key),
            "summary": log.summary()}


# --------------------------------------------- seller opportunities (Party B) --

def _seller(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


_CONSENT_NOTE = {
    "en": "Customers' names and numbers are never shared. Accepting tells ASKODOX you can serve this demand: "
          "your listing is shown to matching customers, and a customer contacts you only if they choose to.",
    "te": "కస్టమర్ల పేర్లు, నంబర్లు ఎప్పుడూ పంచుకోబడవు. అంగీకరిస్తే మీ లిస్టింగ్ సరిపోయే కస్టమర్లకు చూపబడుతుంది; "
          "కస్టమర్ కోరుకుంటేనే మిమ్మల్ని సంప్రదిస్తారు.",
    "hi": "ग्राहकों के नाम और नंबर कभी साझा नहीं होते। स्वीकार करने पर आपकी लिस्टिंग मिलते-जुलते ग्राहकों को दिखेगी; "
          "ग्राहक चाहें तभी आपसे संपर्क करेंगे।",
}


def _opportunity_view(alert: Dict[str, Any], language: str) -> Dict[str, Any]:
    text = di.alert_text({"searches": alert["searches"], "subject": alert["subject"], "area": alert["area"],
                          "budget_band": alert["budget_band"]}, language[:2])
    return {"id": alert["id"], "subject": alert["subject"], "category": alert.get("category") or "",
            "area": alert["area"], "searches": alert["searches"], "budget_band": alert["budget_band"],
            "sent_at": alert["sent_at"], "expires_at": alert.get("expires_at"), "opened_at": alert["opened_at"],
            "responded_at": alert.get("responded_at"), "fulfilled_at": alert.get("fulfilled_at"),
            "response": alert["response"], "status": alert["lifecycle"],
            "can_respond": alert["lifecycle"] in ("new", "opened"),
            "can_fulfil": alert["lifecycle"] == "accepted", **text}


@router.get("/api/opportunities")
def my_opportunities(request: Request, language: str = "en") -> dict:
    """Demand relevant to what this seller offers. Aggregate only: how many
    customers, what, where (area only), budget band -- never who."""
    seller = _seller(request)
    items = [_opportunity_view(a, language) for a in _log(request.app.state.container).for_recipient(seller)]
    counts: Dict[str, int] = {}
    for item in items:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
    return {"items": items, "counts": counts, "privacy": _CONSENT_NOTE.get(language[:2], _CONSENT_NOTE["en"])}


class OpportunityResponse(BaseModel):
    response: str = Field(default="interested",
                          pattern="^(interested|not_relevant|added_offer|accepted|declined)$")
    reason: str = Field(default="", max_length=120)


@router.post("/api/opportunities/{alert_id}/{action}")
def respond_opportunity(alert_id: int, action: str, request: Request, body: OpportunityResponse | None = None,
                        language: str = "en") -> dict:
    """open / respond (accept = interested, decline = not_relevant + reason) / fulfil."""
    if action not in {"open", "respond", "accept", "decline", "fulfil"}:
        raise HTTPException(status_code=404, detail="Unknown action")
    seller = _seller(request)
    container = request.app.state.container
    response = (body.response if body else "interested")
    response = {"accepted": "interested", "declined": "not_relevant"}.get(response, response)
    if action == "accept":
        action, response = "respond", (response if response in ("interested", "added_offer") else "interested")
    elif action == "decline":
        action, response = "respond", "not_relevant"
    try:
        item = _log(container).mark(alert_id, seller, action=action, response=response,
                                    reason=(body.reason if body else ""))
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from None
    if item is None:
        raise HTTPException(status_code=404, detail="Opportunity not found")
    if action in ("respond", "fulfil"):
        _pf(container).repo.record_event(
            "seller_opportunity_response", category=(item.get("category") or "")[:60],
            detail={"alert": alert_id, "response": item["response"], "status": item["lifecycle"],
                    "reason": item.get("decline_reason")})
    return {"item": _opportunity_view(item, language)}


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
    question: str = Field(min_length=2, max_length=4000)  # room for pasted links
    days: int = 7
    language: str = ""
    mode: str = ""  # "incidents": the grounded incident report


_TOPICS = (
    ("unmet", r"unmet|not find|no result|fail|supply|recruit|need more sellers|where should"),
    ("rising", r"increase|rise|rising|grow|trend|what.*today|spike|why did"),
    ("stock", r"stock|out of stock"),
    ("commission", r"commission|affiliate"),
    ("integrations", r"integration|failing|broken|health|down"),
    ("sellers", r"seller|respond|not responding|provider"),
    ("staff", r"staff|work on|today's work|what should"),
)


def _ops_getters(request: Request, principal: dict, repo: Any, days: int) -> Dict[str, Any]:
    """Data access for admin_ops, each only when the caller may see it."""
    container = request.app.state.container
    out: Dict[str, Any] = {"catalog_items": None, "prepare_links": None, "sources_overview": None,
                           "review_counts": None, "unmet": None}
    if _can(principal, "affiliate_products:view"):
        def catalog_items() -> List[Dict[str, Any]]:
            from app.api.routes.affiliate_catalog import catalog, sources

            return catalog(container).list(limit=500, sources=sources(container))["items"]
        out["catalog_items"] = catalog_items
    from app.api.routes import smart_entry as se_route

    if any(_can(principal, p) for p in set(se_route.TARGET_PERMISSION.values())):
        def prepare_links(links: List[str], target: str) -> Dict[str, Any]:
            return se_route.smart_entry_prepare(se_route.SmartEntryBody(inputs=links, target=target), request)
        out["prepare_links"] = prepare_links
    if _can(principal, "sources:view"):
        def sources_overview() -> List[Dict[str, Any]]:
            from app.api.routes.universal_deals import _universal_sources

            return _universal_sources(container).overview()
        out["sources_overview"] = sources_overview

    def review_counts() -> Dict[str, int]:
        from app.services import platform_schema as ps

        counts: Dict[str, int] = {}
        for name, res in ps.RESOURCES.items():
            if "PENDING_REVIEW" in res.statuses and _can(principal, res.permission + ":view"):
                counts[res.label] = len(repo.list(name, status="PENDING_REVIEW"))
        if _can(principal, "affiliate_products:view"):
            items = out["catalog_items"]() if out["catalog_items"] else []
            counts["Catalog items (needs review / draft)"] = sum(
                1 for i in items if i.get("review_status") in ("NEEDS_REVIEW", "DRAFT"))
        return counts
    out["review_counts"] = review_counts
    if _can(principal, "demand:view"):
        out["unmet"] = lambda: di.insights(repo, days=days)["unmet"]
    return out


@router.post("/admin/cc/assistant/ask")
def admin_assistant(body: AskBody, request: Request) -> dict:
    """Answers from recorded data only. Every answer separates what was
    OBSERVED, what MIGHT explain it (marked as unverified), and what to DO."""
    principal = _require(request, "overview:view")
    container = request.app.state.container
    text = body.question.casefold()
    days = max(1, min(body.days, 90))
    repo = _pf(container).repo
    ops = admin_ops.commands(body.question)
    if ops:  # operational command: answered (and previewed) by admin_ops, never executed here
        lang = admin_ops.language(body.question, body.language)
        getters = _ops_getters(request, principal, repo, days)
        return {"question": body.question, "language": lang,
                "answers": [admin_ops.run(op, body.question, lang, **getters) for op in ops],
                "basis": "Recorded ASKODOX records only; changes happen on the linked screen after you confirm."}
    from app.services import admin_incidents

    if body.mode == "incidents" or (admin_incidents.is_incident_question(body.question)
                                    and not any(re.search(p, text) for _, p in _TOPICS)):
        if _can(principal, "health:view"):
            from app.api.routes.command_center import incident_report

            lang = admin_ops.language(body.question, body.language)
            return {"question": body.question, "language": lang, "mode": "incidents",
                    **incident_report(request, lang)}
    topics = [name for name, pattern in _TOPICS if re.search(pattern, text)] or ["rising", "unmet"]
    answers = []
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
            bad, error = _failing_integrations(container)
            if error:
                bad = [f"readiness check unavailable ({error})"]
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
    if _can(principal, "catalog:view"):
        held = len([r for r in _pf(container).repo.list("listing_reviews") if r["status"] == "PENDING_REVIEW"])
        items.append({"key": "listing_reviews", "title": "Seller listings held for review", "count": held,
                      "where": "/admin/console#r:listing_reviews", "what_to_do": "Approve or reject with a reason.",
                      "why": "Held listings are hidden from customers.", "done_when": "No PENDING_REVIEW listings."})
    if _can(principal, "demand:view"):
        from app.services import supply_fit

        gaps = supply_fit.listings_with_gaps(container.settings.database_path)
        items.append({"key": "supply_gaps", "title": "Seller listings missing details customers asked for",
                      "count": gaps, "where": "/admin/console#demand",
                      "what_to_do": "Ask the sellers to add the missing detail.",
                      "why": "Listings that state it rank higher.", "done_when": "Sellers updated their listings."})
    if _can(principal, "integrations:view"):
        failing, check_error = _failing_integrations(container)
        items.append({"key": "integrations", "title": "Integrations reporting an error", "count": len(failing),
                      "where": "/admin/console#readiness", "what_to_do": "Open Integration readiness for the reason.",
                      "why": "Features depending on them fail or fall back.", "done_when": "No integration in ERROR.",
                      **({"check_error": check_error} if check_error else {})})
    from app.services import admin_actions

    items = admin_actions.enrich(items)
    return {"role": principal.get("role"), "items": items, "status": admin_actions.counts(items),
            "basis": "Counted from ASKODOX records now; explanations are fixed rules, not guesses."}


# ------------------------------------------- business auto-response (owner) --

class AutoResponseBody(BaseModel):
    enabled: bool = False
    language: str = Field(default="", max_length=12)
    business_hours: str = Field(default="", max_length=8)
    faq: Dict[str, str] = Field(default_factory=dict)
    handoff_words: List[str] = Field(default_factory=list)
    out_of_hours_reply: str = Field(default="", max_length=500)


@router.get("/api/business/command-center")
def my_business_command_center(request: Request, language: str = "en") -> dict:
    """The signed-in seller's own facts + what to do next (same records the
    Command Center reads; aggregates only, never a customer's identity)."""
    from app.services import business_command_center as bcc, supply_fit

    seller = _seller(request)
    container = request.app.state.container
    listings = container.product_catalog_repository.list_active_for_seller(seller, limit=200)
    gaps = supply_fit.gaps_for_seller(container.settings.database_path, seller)
    opportunities = [_opportunity_view(a, language) for a in _log(container).for_recipient(seller)]
    orders = container.order_repository.list_for_seller(seller, limit=200)
    return {"summary": bcc.summary(listings, gaps, opportunities, orders),
            "insights": bcc.insights(listings, gaps, opportunities, orders, language),
            "missing_data": gaps[:20],
            "basis": "Your own orders, listings and demand alerts on ASKODOX. Views, sales elsewhere and "
                     "ranks are not recorded, so they are not shown."}


@router.get("/api/business/auto-response")
def my_auto_response(request: Request) -> dict:
    owner = _seller(request)
    pf = _pf(request.app.state.container)
    mine = [r for r in pf.repo.list("auto_response_rules", owner_ref=owner)]
    from app.services import auto_response

    from app.services import social_dm

    platforms = {}
    for channel in ("askodox_chat", "facebook", "instagram", "whatsapp", "snapchat"):
        try:  # real state only: LIVE needs a passed check, never key presence
            platforms[channel] = social_dm.channel_status(pf.registry, channel)
        except Exception:
            platforms[channel] = {"status": "UNKNOWN", "reason": "status could not be read"}
    return {"item": mine[0] if mine else None,
            "channels": auto_response.channel_status((mine[0]["data"] if mine else {}), pf.registry),
            "platforms": platforms,
            "note": "Answers only from your approved FAQ; anything else comes to you. Contact details are "
                    "shared only after you accept a request. Instagram / Facebook / WhatsApp / Snapchat need "
                    "your authorised platform connection and are not messaged from here."}


@router.put("/api/business/auto-response")
def save_my_auto_response(body: AutoResponseBody, request: Request) -> dict:
    owner = _seller(request)
    if len(body.faq) > 50:
        raise HTTPException(status_code=400, detail="At most 50 approved answers")
    if body.business_hours and not re.match(r"^\d{1,2}-\d{1,2}$", body.business_hours):
        raise HTTPException(status_code=400, detail="business_hours: use HH-HH, e.g. 09-21")
    pf = _pf(request.app.state.container)
    data = {"name": f"Auto-response {owner[-4:]}", "business_ref": owner, "language": body.language,
            "business_hours": body.business_hours, "faq": {k[:60]: v[:500] for k, v in body.faq.items()},
            "handoff_words": [w[:40] for w in body.handoff_words[:30]], "out_of_hours_reply": body.out_of_hours_reply,
            "knowledge": [], "share_contact": "after_consent"}
    mine = pf.repo.list("auto_response_rules", owner_ref=owner)
    if mine:
        record = pf.resources.update("auto_response_rules", mine[0]["id"], data, actor=owner,
                                     expected_version=mine[0].get("version"), owner_ref=owner)
    else:
        record = pf.resources.create("auto_response_rules", data, actor=owner, owner_ref=owner)
    want = "ACTIVE" if body.enabled else "DISABLED"
    if record["status"] != want:
        record = pf.resources.action("auto_response_rules", record["id"], "enable" if body.enabled else "disable",
                                     actor=owner, owner_ref=owner)
    return {"item": record}


class AutoPreviewBody(BaseModel):
    message: str = Field(min_length=1, max_length=1000)


@router.post("/api/business/auto-response/preview")
def preview_my_auto_response(body: AutoPreviewBody, request: Request) -> dict:
    owner = _seller(request)
    from app.services import auto_response

    mine = _pf(request.app.state.container).repo.list("auto_response_rules", owner_ref=owner)
    if not mine:
        raise HTTPException(status_code=404, detail="Set up your auto-response first")
    return auto_response.answer(body.message, mine[0]["data"])


class ContentAskBody(BaseModel):
    business_ref: str = Field(min_length=1, max_length=120)
    trigger_type: str = Field(pattern="^(video|image|catalog|product|offer|listing|creator_content)$")
    target: str = Field(default="", max_length=120)
    message: str = Field(min_length=1, max_length=1000)


@router.post("/api/auto-response/ask")
def ask_about_content(body: ContentAskBody, request: Request) -> dict:
    """A customer asks about a business's video / image / catalog / product /
    offer / listing / creator content inside ASKODOX: the business's matching
    ACTIVE trigger answers from approved text only, or hands to the owner."""
    from app.api.routes.in_app_deal import _cust, _flag_on, auto_response_limit
    from app.services import auto_response, rate_limit

    rate_limit.check(request, "auto_response_ask", limit=30)
    container = request.app.state.container
    if not _flag_on(container, "autoresponse.enabled"):
        return {"status": "switched_off", "text": None, "handoff_to_owner": True}
    pf = _pf(container)
    rule = auto_response.rule_for(pf.repo.list("auto_response_rules"), body.business_ref,
                                  trigger=body.trigger_type, target=body.target, message=body.message)
    if rule is None:
        return {"status": "no_rule", "text": None, "handoff_to_owner": True}
    from app.api.routes.in_app_assistant import _optional_app_user

    customer = _optional_app_user(request)
    if customer in ("", "guest"):  # every signed-out caller shares "guest"
        customer = "ip:" + (request.client.host if request.client else "anon")
    blocked = auto_response_limit(pf, rule, customer)
    if blocked:
        return {"status": "limited", "text": None, "reason": blocked, "handoff_to_owner": True}
    result = auto_response.answer(body.message, rule)
    pf.repo.record_event("auto_response", detail={"status": result["status"], "rule": rule.get("_id"),
                                                  "source": result["source"], "customer": _cust(customer),
                                                  "trigger": body.trigger_type, "sent": bool(result["text"])})
    return {**result, "handoff_to_owner": result["status"] != "answered",
            "channels": auto_response.channel_status(rule, pf.registry)}
