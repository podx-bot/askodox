"""Observation + advisory engine: short, contextual advice -- only when it
can change cost, risk, safety, reliability, suitability, time, deal quality
or dispute prevention. At most two lines; most requests get none. The user
always decides; advice never blocks an action.

Inputs are what the pipeline actually knows (the demand and the real result
rows), so advice is never based on invented facts.
"""
from __future__ import annotations

import re
from typing import Any

from app.services import domain_adapters

MAX_ADVICE = 2


def _num(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def advise(demand: dict[str, Any], matches: list[dict[str, Any]], *, need_kind: str = "",
           scope: dict[str, Any] | None = None) -> list[dict[str, str]]:
    subject = str(demand.get("subject") or "")
    constraints = demand.get("constraints") or {}
    raw = f"{subject} {demand.get('raw_text') or ''} {constraints}".lower()
    adapter = domain_adapters.detect(raw)
    advice: list[dict[str, str]] = []

    def add(code: str, text: str, te: str, why: str) -> None:
        if all(a["code"] != code for a in advice):
            advice.append({"code": code, "text": text, "text_te": te, "why": why})

    # Safety first: health emergencies and "no diagnosis".
    if adapter and adapter.key == "healthcare":
        if domain_adapters.is_emergency(raw):
            add("health_emergency", "This sounds urgent -- call 108 or go to the nearest emergency room now.",
                "ఇది అత్యవసరంలా ఉంది -- వెంటనే 108 కి కాల్ చేయండి లేదా దగ్గరలోని ఎమర్జెన్సీకి వెళ్లండి.", "safety")
        specialty = domain_adapters.health_specialty(raw)
        add("health_specialty", f"ASKODOX can't diagnose; a {specialty} is the right professional to see for this.",
            f"ASKODOX రోగనిర్ధారణ చేయదు; దీనికి {specialty} ని సంప్రదించడం సరైనది.", "suitability")

    # Staffing: people don't always turn up.
    quantity = _num(demand.get("quantity")) or _num(constraints.get("people_count"))
    if (adapter and adapter.key == "catering") or re.search(r"\b(staff|workers|helpers|waiters|labou?r)\b", raw):
        if quantity and quantity >= 5:
            add("backup_staff", f"For {int(quantity)} people, ask 1-2 backup staff to stay available in case someone doesn't turn up.",
                f"{int(quantity)} మందికి, ఎవరైనా రాకపోతే 1-2 బ్యాకప్ సిబ్బందిని సిద్ధంగా ఉంచమని అడగండి.", "reliability")

    # Services: pay on completion rather than a full advance.
    if need_kind == "service" or (adapter and adapter.key in {"salon", "catering"}):
        add("pay_on_completion", "Prefer paying after the work is done (or a small advance), not the full amount upfront.",
            "పని పూర్తయ్యాక చెల్లించండి (లేదా చిన్న అడ్వాన్స్ మాత్రమే) -- మొత్తం ముందుగా ఇవ్వకండి.", "dispute_prevention")

    # Parcels: what not to send.
    if adapter and adapter.key == "parcel":
        add("parcel_safety", "Don't send cash or valuables; note the rider's name and vehicle when handing over.",
            "నగదు/విలువైన వస్తువులు పంపకండి; అప్పగించేటప్పుడు రైడర్ పేరు, వాహనం నమోదు చేసుకోండి.", "safety")

    # Used items: inspect.
    if re.search(r"\b(used|second hand|second-hand|pre-owned|refurbished)\b", raw):
        add("inspect_used", "Inspect it in person and ask for the bill/warranty before paying for a used item.",
            "పాత వస్తువుకు చెల్లించే ముందు చూసి, బిల్లు/వారంటీ అడగండి.", "risk")

    # Prices only from web page text.
    priced = [m for m in matches if _num(m.get("price"))]
    if priced and all(m.get("price_verified") is False for m in priced):
        add("verify_price", "Prices shown come from web pages and may be outdated -- confirm the final price before paying.",
            "చూపిన ధరలు వెబ్ పేజీల నుండి -- చెల్లించే ముందు తుది ధర నిర్ధారించుకోండి.", "cost")

    # Cheapest vs next: the difference is worth a look.
    verified = sorted((_num(m.get("price")), m) for m in priced if m.get("price_verified") is not False)
    if len(verified) >= 2 and verified[0][0] and verified[-1][0] and verified[-1][0] >= verified[0][0] * 1.25:
        low, high = verified[0][0], verified[-1][0]
        add("price_spread", f"Prices range ₹{low:,.0f}-₹{high:,.0f}; check warranty, condition and seller rating before picking the cheapest.",
            f"ధరలు ₹{low:,.0f}-₹{high:,.0f}; చౌకైనది ఎంచుకునే ముందు వారంటీ, కండిషన్, రేటింగ్ చూడండి.", "deal_quality")

    # Only far options.
    if scope and scope.get("expanded"):
        km = int(scope.get("radius_km") or 0)
        add("far_options", f"The nearest options are up to ~{km} km away -- ask about delivery or visit charges.",
            f"దగ్గరలోని ఎంపికలు ~{km} కి.మీ దూరంలో ఉన్నాయి -- డెలివరీ/విజిట్ ఛార్జీలు అడగండి.", "cost")

    return advice[:MAX_ADVICE]
