"""ASKODOX Executive AI (AXE): ONE executive brief for the Owner, built on the
systems that already exist -- never a parallel monitoring stack:

- release state      -> ``release_gate.evaluate`` (strict, device = PHONE VERIFIED)
- risks              -> ``admin_incidents`` (template text over telemetry)
- spend              -> ``api_billing.overview`` (estimates; real balance only
                         from a provider) + the Travel Radio cost model
- approved scope     -> ``docs/approved_features.json`` (Feature Registry)
- what to do next    -> actions from ``admin_action_framework.CATALOG`` only;
                         AXE RECOMMENDS, it never runs or approves anything.

Every line carries a grade: CONFIRMED (recorded state / provider answer),
ESTIMATE (admin-set unit costs), PENDING (needs a real phone or the Owner).
Fixed en / te templates -- no model call, so the brief costs nothing and
cannot invent a cause.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

_T = {
    "en": {
        "READY": "Release gate: READY -- every condition passes.",
        "NOT_READY": "Release gate: NOT READY -- {n} condition(s) fail.",
        "BLOCKED_ON_DEVICE_VERIFICATION": "Release gate: waiting for real-phone verification ({evidence}).",
        "no_risk": "No open red / orange incident in recorded telemetry.",
        "spend": "API spend this month (estimate): Rs {inr}. Real balances come only from each provider's own page.",
        "radio_loss": "Travel Radio: at the proposed price, '{plan}' does not cover a {profile} listener "
                      "(estimated cost Rs {cost} vs price Rs {price}).",
        "radio_ok": "Travel Radio: the proposed prices cover every simulated listener profile (estimate).",
        "d_radio": "Decide Travel Radio prices and whether to activate its billing (plans are stored inactive).",
        "d_payment": "Choose a payment gateway: paid plans and passes stay PENDING_PAYMENT until one exists.",
        "d_phone": "Run the real-phone acceptance checks: {n} are not PHONE VERIFIED.",
        "registry": "{n} approved features are protected by the Feature Registry gate.",
    },
    "te": {
        "READY": "రిలీజ్ గేట్: సిద్ధం -- అన్ని షరతులు పాస్.",
        "NOT_READY": "రిలీజ్ గేట్: సిద్ధం కాదు -- {n} షరతులు విఫలం.",
        "BLOCKED_ON_DEVICE_VERIFICATION": "రిలీజ్ గేట్: నిజమైన ఫోన్ పరీక్ష కోసం వేచి ఉంది ({evidence}).",
        "no_risk": "రికార్డ్ అయిన టెలిమెట్రీలో ఎరుపు / నారింజ సమస్యలు లేవు.",
        "spend": "ఈ నెల API ఖర్చు (అంచనా): Rs {inr}. నిజమైన బ్యాలెన్స్ ప్రొవైడర్ పేజీలో మాత్రమే.",
        "radio_loss": "ట్రావెల్ రేడియో: ప్రతిపాదిత ధరలో '{plan}' {profile} శ్రోత ఖర్చును కవర్ చేయదు "
                      "(అంచనా ఖర్చు Rs {cost}, ధర Rs {price}).",
        "radio_ok": "ట్రావెల్ రేడియో: ప్రతిపాదిత ధరలు అన్ని శ్రోత ప్రొఫైల్స్‌ను కవర్ చేస్తాయి (అంచనా).",
        "d_radio": "ట్రావెల్ రేడియో ధరలు, బిల్లింగ్ ప్రారంభం నిర్ణయించండి (ప్లాన్లు నిష్క్రియంగా ఉన్నాయి).",
        "d_payment": "పేమెంట్ గేట్‌వే ఎంచుకోండి: అది వచ్చే వరకు పెయిడ్ ప్లాన్లు PENDING_PAYMENTలోనే.",
        "d_phone": "నిజమైన ఫోన్ పరీక్షలు చేయండి: {n} ఇంకా PHONE VERIFIED కాలేదు.",
        "registry": "{n} ఆమోదిత ఫీచర్లు ఫీచర్ రిజిస్ట్రీ గేట్ రక్షణలో ఉన్నాయి.",
    },
}


def brief(*, gate: Dict[str, Any], incidents: List[Dict[str, Any]], billing: Dict[str, Any],
          radio_model: Optional[Dict[str, Any]], radio_plans: List[Dict[str, Any]],
          registry: List[Dict[str, Any]], payments_configured: bool, catalog: Dict[str, Dict[str, Any]],
          lang: str = "en") -> Dict[str, Any]:
    lang = "te" if lang == "te" else "en"
    t = _T[lang]
    findings: List[Dict[str, Any]] = []

    overall = str(gate.get("overall") or "NOT_READY")
    failing = [c for c in gate.get("conditions") or [] if c.get("status") == "FAIL"]
    device = next((c for c in gate.get("conditions") or [] if c.get("id") == "real_phone_acceptance"), {})
    findings.append({"area": "release", "grade": "CONFIRMED" if overall != "BLOCKED_ON_DEVICE_VERIFICATION"
                     else "PENDING", "text": t[overall].format(n=len(failing), evidence=device.get("evidence", "")),
                     "evidence": [f"{c['id']}={c['status']}" for c in gate.get("conditions") or []]})

    risks = [i for i in incidents if i.get("severity") in ("red", "orange")][:5]
    for inc in risks:
        action = _action(inc.get("proposed_action"), catalog)
        findings.append({"area": "risk", "grade": "CONFIRMED" if inc.get("reason_confirmed") else "POSSIBLE",
                         "severity": inc["severity"], "text": inc.get("ai_explanation") or inc.get("problem"),
                         "evidence": inc.get("evidence") or [], "recommended_action": action})
    if not risks:
        findings.append({"area": "risk", "grade": "CONFIRMED", "text": t["no_risk"], "evidence": []})

    spend = sum(float((((p.get("cost") or {}).get("estimated_inr")) or {}).get("month") or 0)
                for p in billing.get("providers") or [])
    findings.append({"area": "spend", "grade": "ESTIMATE", "text": t["spend"].format(inr=round(spend, 2)),
                     "evidence": [f"{p['provider']}={p['state']}" for p in billing.get("providers") or []]})

    decisions: List[Dict[str, Any]] = []
    if radio_model:
        losses = [(row["profile"], plan) for row in radio_model.get("profiles") or []
                  for plan in row.get("plans") or [] if not plan.get("covers_cost")]
        for profile, plan in losses[:3]:
            findings.append({"area": "pricing", "grade": "ESTIMATE",
                             "text": t["radio_loss"].format(plan=plan["code"], profile=profile,
                                                            cost=plan["cost_estimate_inr"], price=plan["price"]),
                             "evidence": [f"assumptions={radio_model.get('assumptions', {}).get('note', '')}"]})
        if not losses:
            findings.append({"area": "pricing", "grade": "ESTIMATE", "text": t["radio_ok"], "evidence": []})
    if radio_plans and not any(p.get("active") for p in radio_plans):
        decisions.append({"key": "radio_pricing", "text": t["d_radio"]})
    if not payments_configured:
        decisions.append({"key": "payment_gateway", "text": t["d_payment"]})
    pending = device.get("status") == "PENDING"
    if pending:
        count = str(device.get("evidence") or "").split(" ")[0]
        decisions.append({"key": "phone_acceptance", "text": t["d_phone"].format(n=count if count.isdigit() else "?")})

    approved = [f for f in registry if f.get("status") == "approved"]
    findings.append({"area": "scope", "grade": "CONFIRMED", "text": t["registry"].format(n=len(approved)),
                     "evidence": []})
    return {"overall": overall, "findings": findings, "owner_decisions": decisions,
            "rule": "AXE recommends only; actions run through the approval framework, never from this brief.",
            "language": lang}


def _action(spec: Any, catalog: Dict[str, Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """``read:recheck:brave`` / ``change:selfheal_apply:12`` -> a catalog action
    the console can PROPOSE (approval rules unchanged); unknown -> None."""
    parts = str(spec or "").split(":", 2)
    if len(parts) != 3 or parts[1] not in catalog:
        return None
    return {"action": parts[1], "target": parts[2], "risk": catalog[parts[1]]["risk"],
            "needs_approval": catalog[parts[1]]["risk"] != "read_only"}
