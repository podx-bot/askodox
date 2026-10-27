"""AI Admin action layer over the staff work queue: every item explains
WHAT HAPPENED -> WHY -> IMPACT -> RECOMMENDED ACTION (+ the button that does
it) as ONE mixed Telugu-English text, with a 🔴 / 🟠 / 🟢 status.

Only real counts from the work queue are used; the wording is fixed per item
(rule-based, not generated), so an explanation can never state something the
records do not.
"""
from __future__ import annotations

from typing import Any, Dict, List

ICON = {"red": "🔴", "orange": "🟠", "green": "🟢"}

# Items where any open count means a customer / the platform is affected now.
URGENT = {"support", "integrations", "requests_waiting"}

# ONE mixed Telugu-English text per item (owner rule 2026-10-27): business /
# tech words stay English, actions / status / warnings in simple Telugu. Never
# an English sentence plus a Telugu copy of it.
TEXT: Dict[str, Dict[str, str]] = {
    "stock_unknown": {"what": "{n} products stock తెలియదు.", "why": "వాటి source page check చేయలేదు, లేదా చదవలేకపోయాం.",
                      "impact": "అవి available అని చూపించం — customers వాటిని చూడకపోవచ్చు.",
                      "action": "ప్రతి source page open చేసి In stock / Out of stock పెట్టండి."},
    "stock_out": {"what": "{n} products Out of stock అని ఉన్నాయి.", "why": "Staff లేదా feed వాటిని unavailable అని పెట్టారు.",
                  "impact": "మళ్ళీ check చేసే వరకు recommendations లో రావు.",
                  "action": "మళ్ళీ check చేసి, stock ఉంటే In stock పెట్టండి."},
    "commission_unknown": {"what": "{n} products commission తెలియదు.", "why": "Affiliate network ఇంకా confirm చేయలేదు.",
                           "impact": "అవి normal links గా open అవుతాయి — commission రాదు.",
                           "action": "Network తో confirm చేసి Active / Inactive పెట్టండి."},
    "no_match": {"what": "{n} searches కి match దొరకలేదు.", "why": "అడిగినది ఏ seller, source, category లోనూ లేదు.",
                 "impact": "ప్రతి ఒక్కటి result లేకుండా వెళ్ళిపోయిన customer.",
                 "action": "ఆ అవసరానికి source, category లేదా seller చేర్చండి."},
    "demand": {"what": "{n} demand అవకాశాలు ఇంకా తీరలేదు.", "why": "Customers వెతికారు, కానీ local supply లేదు.",
               "impact": "Seller కి చెప్పే వరకు / కొత్త seller వచ్చే వరకు demand తీరదు.",
               "action": "Matching sellers చూసి notify చేయండి, లేదా recruit చేయండి."},
    "supply_gaps": {"what": "{n} seller listings లో customers అడిగిన వివరం (size, price, colour ...) లేదు.",
                    "why": "Customer ఇచ్చిన detail listing లో లేదు.",
                    "impact": "ఆ listings కిందకు వెళ్తాయి; customers కి 'seller చెప్పలేదు' అని కనిపిస్తుంది.",
                    "action": "Missing detail చేర్చమని sellers ని అడగండి."},
    "listing_reviews": {"what": "{n} కొత్త seller listings review కోసం ఆగాయి.",
                        "why": "వాటిలో phone number, link, లేదా వేరే account number ఉంది.",
                        "impact": "Staff Approve / Reject చేసే వరకు customers కి కనిపించవు.",
                        "action": "కారణం రాసి ఒక్కొక్కటి Approve లేదా Reject చేయండి."},
    "support": {"what": "{n} support cases open గా ఉన్నాయి.", "why": "Customers లేదా sellers help అడిగారు.",
                "impact": "SLA time నడుస్తోంది — late reply అయితే నమ్మకం తగ్గుతుంది.",
                "action": "Context package చూసి reply ఇవ్వండి (మళ్ళీ అడగకండి)."},
    "content": {"what": "{n} videos review కోసం ఆగాయి.", "why": "Review లేకుండా కొత్త videos చూపించం.",
                "impact": "Review అయ్యే వరకు sellers videos కనిపించవు.",
                "action": "కారణం రాసి ఒక్కొక్కటి Approve లేదా Reject చేయండి."},
    "integrations": {"what": "{n} integrations లో error వస్తోంది.", "why": "Provider call ని reject చేసింది, లేదా key తప్పు / లేదు.",
                     "impact": "వాటి మీద ఆధారపడిన features పని చేయవు, లేదా fallback కి వెళ్తాయి.",
                     "action": "Integration సిద్ధత page లో అసలు కారణం చూడండి; key ని Railway లో సరిచేయండి (chat లో paste చేయకండి)."},
}

_GREEN = {"what": "ఏమీ pending లేదు.", "why": "", "impact": "", "action": "ఏమీ చేయక్కర్లేదు."}

BUTTON = "Open చేయండి"


def severity(item: Dict[str, Any]) -> str:
    if not item.get("count"):
        return "green"
    return "red" if item.get("key") in URGENT else "orange"


def enrich(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Adds severity, icon and the one mixed explanation to each queue item;
    red first, then orange (largest count first), green last."""
    for item in items:
        sev = severity(item)
        item["severity"], item["icon"] = sev, ICON[sev]
        texts = TEXT.get(item.get("key") or "")
        if not texts:
            base = dict(_GREEN, what=str(item.get("title") or item.get("key")) + ": " + str(item.get("count", 0)),
                        why=str(item.get("why") or ""))
        elif sev == "green":  # say WHICH module is clear
            base = dict(texts, why="", impact="", action=_GREEN["action"])
        else:
            base = texts
        explain = {k: v.format(n=item.get("count", 0)) for k, v in base.items()}
        explain["button"] = BUTTON
        item["explain"] = explain
    rank = {"red": 0, "orange": 1, "green": 2}
    return sorted(items, key=lambda i: (rank[i["severity"]], -int(i.get("count") or 0)))


def counts(items: List[Dict[str, Any]]) -> Dict[str, int]:
    out = {"red": 0, "orange": 0, "green": 0}
    for item in items:
        out[item["severity"]] += 1
    return out
