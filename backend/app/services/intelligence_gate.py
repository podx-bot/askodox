"""Decides when the ONE conversation brain's reply carries an intelligence
block (tax / GST, fraud & market reality, smart tricks) -- the same pattern
as ``buyer_guide_gate``: deterministic, on the user's OWN words only (the
app's "Options already shown" context is stripped), never forced into a
conversation that did not ask (master command 20: no repetitive warnings,
simple questions get simple answers).

Also enforces the two hard limits: how-to-evade-tax and how-to-commit-fraud
asks get awareness + consequences, never operational steps
(``override_reply``).
"""
from __future__ import annotations

import re
from typing import Any, Dict, Optional

from app.services import fraud_awareness, smart_tricks, tax_intelligence

_INCOME_TAX = re.compile(
    r"\b(income[- ]?tax|tax (regime|slab|slabs|rebate)|new regime|old regime|itr|80c|80d|tds|advance tax|"
    r"standard deduction|taxable income|tax on (my )?(salary|income))\b|ఆదాయపు పన్ను|ఇన్‌కమ్ ట్యాక్స్|పన్ను శ్లాబ్")
_GST = re.compile(
    r"\b(gst|gstin|input tax credit|itc|composition scheme|composition dealer|hsn|sac code|e-?way bill|"
    r"bill of supply|gst registration|gst rate)\b|జీఎస్టీ|జిఎస్టి")
_TRICKS = {
    "buy_vs_rent": re.compile(r"\b(buy or rent|rent or buy|renting vs buying|buying vs renting)\b|కొనాలా అద్దెకా|అద్దెకా కొనాలా"),
    "repair_vs_replace": re.compile(r"\b(repair or replace|replace or repair|worth repairing|worth fixing|"
                                    r"fix or buy new)\b|రిపేర్ చేయాలా కొత్తది"),
    "unit_price": re.compile(r"\b(which pack is cheaper|cheaper per (kg|litre|liter|unit|piece)|price per (kg|litre|unit)|"
                             r"bigger pack|family pack worth)\b"),
    "bulk_buy": re.compile(r"\b(buy in bulk|bulk buy|bulk purchase|wholesale (buy|purchase)|buy wholesale)\b|హోల్‌సేల్‌గా కొనాలా"),
    "total_cost": re.compile(r"\b(total cost of ownership|running cost|cost to own|petrol or (ev|electric|diesel)|"
                             r"ev or petrol|cheaper to own)\b"),
}
_SAVE_MONEY = re.compile(r"\b(save money|cheaper way|how can i (buy|get) (this|it) cheaper|cut (my )?costs?|"
                         r"reduce (my )?(cost|bill|expenses))\b|డబ్బు ఆదా|తక్కువ ఖర్చుతో")


def _user_words(message: str) -> str:
    try:
        from app.services.universal_ai_assistant_service import UniversalAIAssistantService

        return UniversalAIAssistantService.split_app_context(message)[0]
    except Exception:
        return str(message or "")


def _te(language: str | None) -> bool:
    return str(language or "").lower().startswith("te")


def build(message: str, language: str = "en") -> Optional[Dict[str, Any]]:
    text = _user_words(message)
    q = text.lower()
    te = _te(language)
    if not q.strip():
        return None

    if tax_intelligence.evasion_intent(q):
        return {"kind": "tax_evasion_awareness",
                "title": "పన్ను ఎగవేత — అవగాహన" if te else "Tax evasion — awareness only",
                **tax_intelligence.evasion_response(),
                "action": {"route": "/intel/tax", "label": "లీగల్ ట్యాక్స్ ప్లానింగ్" if te else "Lawful tax planning"}}

    if fraud_awareness.commit_intent(q):
        scheme_id = fraud_awareness.match(q)
        return {"kind": "fraud_refusal",
                "title": "మోసం — అవగాహన మాత్రమే" if te else "Fraud — awareness only",
                "refusal": ("ASKODOX does not explain how to carry out a scam, tamper with goods or forge records. "
                            "It can explain how such schemes are recognised and reported."),
                "scheme": fraud_awareness.scheme(scheme_id, language) if scheme_id else None}

    if fraud_awareness.fraud_intent(q):
        scheme_id = fraud_awareness.match(q)
        card: Dict[str, Any] = {"kind": "fraud",
                                "title": "మోసం జాగ్రత్తలు" if te else "Fraud & market reality"}
        if scheme_id:
            card["scheme"] = fraud_awareness.scheme(scheme_id, language)
            card["action"] = {"route": f"/intel/fraud/{scheme_id}",
                              "label": "పూర్తి వివరాలు" if te else "Full checklist"}
        else:
            card["schemes"] = fraud_awareness.list_schemes(language)
            card["action"] = {"route": "/intel/fraud", "label": "మోసాల జాబితా" if te else "All scam checklists"}
        return card

    if _GST.search(q):
        gst = tax_intelligence.GST_RATE_STRUCTURE
        return {"kind": "gst",
                "title": "జీఎస్టీ సమాచారం" if te else "GST — what applies",
                "summary": gst["summary"], "rate_rule": gst["rate_rule"],
                "facts": [
                    "Registration by turnover: Rs 40 lakh (goods) / Rs 20 lakh (services) in most States; lower in some "
                    "States -- the GST tool checks your State.",
                    "Composition scheme: up to Rs 1.5 crore (goods, most States) at a flat % of turnover, no input tax credit.",
                    "A bill without GST is not automatically illegal (unregistered or exempt sellers).",
                ],
                "sources": [{"id": s, **tax_intelligence.SOURCES[s]}
                            for s in ("gst_56th_council", "cbic_gst_update_2019", "pib_msme_2019")],
                "verified_on": tax_intelligence.VERIFIED_ON,
                "professional_note": tax_intelligence.PROFESSIONAL_NOTE,
                "action": {"route": "/intel/gst", "label": "GST టూల్" if te else "Open GST tool"}}

    if _INCOME_TAX.search(q):
        year = tax_intelligence.INCOME_TAX_YEARS[tax_intelligence.CURRENT_TAX_YEAR]
        return {"kind": "income_tax",
                "title": "ఆదాయపు పన్ను" if te else "Income tax — current rules",
                "year_label": year["label"], "law": year["law"], "rule_status": year["status"],
                "facts": [
                    "New regime (default): nil up to Rs 4 lakh, then 5% / 10% / 15% / 20% / 25% in Rs 4 lakh steps, "
                    "30% above Rs 24 lakh.",
                    "Rebate makes tax nil up to Rs 12 lakh taxable income (Rs 12.75 lakh salary with the Rs 75,000 "
                    "standard deduction); capital gains are outside this.",
                    "Old regime keeps deductions such as 80C / 80D / HRA but has higher slab rates -- compare both.",
                ],
                "sources": [{"id": s, **tax_intelligence.SOURCES[s]} for s in year["sources"]],
                "verified_on": tax_intelligence.VERIFIED_ON,
                "professional_note": tax_intelligence.PROFESSIONAL_NOTE,
                "action": {"route": "/intel/tax", "label": "పన్ను లెక్కించు" if te else "Calculate my tax"}}

    for key, pattern in _TRICKS.items():
        if pattern.search(q):
            return {"kind": "smart_tricks", "calculator": key,
                    "title": "స్మార్ట్ ట్రిక్" if te else "ASKODOX Smart Trick",
                    "evidence_rule": smart_tricks.EVIDENCE_RULE,
                    "action": {"route": f"/intel/tricks?calc={key}", "label": "లెక్కించు" if te else "Work it out"}}
    if _SAVE_MONEY.search(q):
        return {"kind": "smart_tricks", "calculator": None,
                "title": "స్మార్ట్ ట్రిక్" if te else "ASKODOX Smart Trick",
                "evidence_rule": smart_tricks.EVIDENCE_RULE,
                "action": {"route": "/intel/tricks", "label": "సేవింగ్ కాలిక్యులేటర్లు" if te else "Savings calculators"}}
    return None


def override_reply(intelligence: Optional[Dict[str, Any]], language: str = "en") -> Optional[str]:
    """The reply text that REPLACES the model's answer for refused asks."""
    if not intelligence:
        return None
    te = _te(language)
    if intelligence.get("kind") == "tax_evasion_awareness":
        return ("పన్ను ఎగవేత లేదా నకిలీ బిల్లుల గురించి నేను పద్ధతులు చెప్పను. ఇవి ఎలా పట్టుబడతాయో, శిక్షలు ఏమిటో, "
                "చట్టబద్ధంగా పన్ను ఎలా తగ్గించుకోవచ్చో క్రింద ఉంది.") if te else (
                "I can't explain how to evade tax or create false bills. Below is how these schemes are detected, "
                "the consequences, and lawful ways to reduce tax.")
    if intelligence.get("kind") == "fraud_refusal":
        return ("మోసం ఎలా చేయాలో నేను చెప్పను. ఇలాంటి మోసాలను ఎలా గుర్తించాలో, ఎక్కడ ఫిర్యాదు చేయాలో చెప్పగలను.") if te else (
                "I can't help carry out a scam or tamper with goods or records. I can explain how such schemes are "
                "recognised and where to report them.")
    return None
