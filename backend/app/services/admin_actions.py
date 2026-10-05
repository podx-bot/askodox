"""AI Admin action layer over the staff work queue: every item explains
WHAT HAPPENED -> WHY -> IMPACT -> RECOMMENDED ACTION (+ the button that does
it) in English and Telugu, with a 🔴 / 🟠 / 🟢 status.

Only real counts from the work queue are used; the wording is fixed per item
(rule-based, not generated), so an explanation can never state something the
records do not.
"""
from __future__ import annotations

from typing import Any, Dict, List

ICON = {"red": "🔴", "orange": "🟠", "green": "🟢"}

# Items where any open count means a customer / the platform is affected now.
URGENT = {"support", "integrations", "requests_waiting"}

TEXT: Dict[str, Dict[str, Dict[str, str]]] = {
    "stock_unknown": {
        "en": {"what": "{n} products have unknown stock.", "why": "Their source page was never checked or could not be read.",
               "impact": "They are never shown as available, so customers may miss them.",
               "action": "Open each source page and set In stock / Out of stock."},
        "te": {"what": "{n} ఉత్పత్తుల స్టాక్ తెలియదు.", "why": "వాటి సోర్స్ పేజీ తనిఖీ చేయలేదు లేదా చదవలేకపోయాం.",
               "impact": "అవి అందుబాటులో ఉన్నట్లు చూపబడవు, కస్టమర్లు వాటిని చూడకపోవచ్చు.",
               "action": "ప్రతి సోర్స్ పేజీ తెరిచి స్టాక్ ఉంది / లేదు అని పెట్టండి."}},
    "stock_out": {
        "en": {"what": "{n} products are marked out of stock.", "why": "Staff or a feed marked them unavailable.",
               "impact": "They are hidden from recommendations until re-checked.",
               "action": "Re-check them and mark In stock when available again."},
        "te": {"what": "{n} ఉత్పత్తులు స్టాక్ లేదు అని ఉన్నాయి.", "why": "సిబ్బంది లేదా ఫీడ్ వాటిని అందుబాటులో లేవని గుర్తించారు.",
               "impact": "మళ్లీ తనిఖీ చేసే వరకు అవి సిఫార్సుల్లో కనిపించవు.",
               "action": "మళ్లీ తనిఖీ చేసి, అందుబాటులో ఉంటే స్టాక్ ఉంది అని పెట్టండి."}},
    "commission_unknown": {
        "en": {"what": "{n} products have unknown commission.", "why": "The affiliate network has not been confirmed.",
               "impact": "They open as normal links, so no commission is earned on them.",
               "action": "Confirm with the network and set Active / Inactive."},
        "te": {"what": "{n} ఉత్పత్తుల కమీషన్ తెలియదు.", "why": "అఫిలియేట్ నెట్‌వర్క్ నిర్ధారించలేదు.",
               "impact": "అవి సాధారణ లింక్‌లుగా తెరుచుకుంటాయి, కమీషన్ రాదు.",
               "action": "నెట్‌వర్క్‌తో నిర్ధారించి యాక్టివ్ / ఇనాక్టివ్ పెట్టండి."}},
    "no_match": {
        "en": {"what": "{n} searches found no match.", "why": "No seller, source or category covered what was asked.",
               "impact": "Each one is a customer who left without a result.",
               "action": "Add a source, category or seller for the need."},
        "te": {"what": "{n} శోధనలకు ఫలితం దొరకలేదు.", "why": "అడిగినదాన్ని ఏ విక్రేత, సోర్స్ లేదా వర్గం కవర్ చేయలేదు.",
               "impact": "ప్రతి ఒక్కటి ఫలితం లేకుండా వెళ్లిన కస్టమర్.",
               "action": "ఆ అవసరానికి సోర్స్, వర్గం లేదా విక్రేతను జోడించండి."}},
    "demand": {
        "en": {"what": "{n} unmet demand opportunities.", "why": "Customers searched for it and local supply is missing.",
               "impact": "Demand goes unserved until a seller is told or recruited.",
               "action": "Preview matching sellers, then notify or recruit."},
        "te": {"what": "{n} తీరని డిమాండ్ అవకాశాలు.", "why": "కస్టమర్లు వెతికారు కానీ స్థానిక సరఫరా లేదు.",
               "impact": "విక్రేతకు తెలియజేసే వరకు ఆ డిమాండ్ తీరదు.",
               "action": "సరిపోయే విక్రేతలను చూసి, తెలియజేయండి లేదా చేర్చుకోండి."}},
    "supply_gaps": {
        "en": {"what": "{n} seller listings could not answer what customers asked (size, price, colour ...).",
               "why": "The listing does not state the detail the customer gave.",
               "impact": "Those listings rank below ones that state it; customers see 'not stated by the seller'.",
               "action": "Ask the sellers to add the missing detail."},
        "te": {"what": "{n} విక్రేత లిస్టింగ్‌లు కస్టమర్లు అడిగిన వివరం (సైజు, ధర, రంగు ...) చెప్పలేదు.",
               "why": "కస్టమర్ ఇచ్చిన వివరం లిస్టింగ్‌లో లేదు.",
               "impact": "ఆ లిస్టింగ్‌లు కింద చూపబడతాయి; 'విక్రేత చెప్పలేదు' అని కనిపిస్తుంది.",
               "action": "లోపించిన వివరం జోడించమని విక్రేతలను అడగండి."}},
    "listing_reviews": {
        "en": {"what": "{n} new seller listings are held for review.", "why": "They contain contact details, links or a number used by another account.",
               "impact": "They stay hidden from customers until staff approve or reject them.",
               "action": "Approve or reject each one with a reason."},
        "te": {"what": "{n} కొత్త విక్రేత లిస్టింగ్‌లు సమీక్ష కోసం ఆపబడ్డాయి.", "why": "వాటిలో ఫోన్ నంబర్, లింక్ లేదా వేరే ఖాతా నంబర్ ఉంది.",
               "impact": "సిబ్బంది ఆమోదించే వరకు కస్టమర్లకు కనిపించవు.",
               "action": "కారణంతో ప్రతి ఒక్కటి ఆమోదించండి లేదా తిరస్కరించండి."}},
    "support": {
        "en": {"what": "{n} support cases are open.", "why": "Customers or sellers asked for help.",
               "impact": "SLA timers are running; a late reply costs trust.",
               "action": "Reply using the context package (do not re-ask)."},
        "te": {"what": "{n} సపోర్ట్ కేసులు తెరిచి ఉన్నాయి.", "why": "కస్టమర్లు లేదా విక్రేతలు సహాయం అడిగారు.",
               "impact": "SLA సమయం నడుస్తోంది; ఆలస్యం నమ్మకాన్ని తగ్గిస్తుంది.",
               "action": "సందర్భ వివరాలతో జవాబు ఇవ్వండి (మళ్లీ అడగవద్దు)."}},
    "content": {
        "en": {"what": "{n} videos are waiting for review.", "why": "New videos are not shown before a review.",
               "impact": "Sellers' videos stay invisible until reviewed.",
               "action": "Approve or reject each with a reason."},
        "te": {"what": "{n} వీడియోలు సమీక్ష కోసం ఎదురుచూస్తున్నాయి.", "why": "సమీక్ష లేకుండా కొత్త వీడియోలు చూపబడవు.",
               "impact": "సమీక్షించే వరకు విక్రేతల వీడియోలు కనిపించవు.",
               "action": "కారణంతో ప్రతి ఒక్కటి ఆమోదించండి లేదా తిరస్కరించండి."}},
    "integrations": {
        "en": {"what": "{n} integrations report an error.", "why": "A provider rejected a call or a key is wrong / missing.",
               "impact": "The features that depend on them fail or fall back.",
               "action": "Open Integration readiness for the exact reason; fix the key in Railway (never paste it in chat)."},
        "te": {"what": "{n} ఇంటిగ్రేషన్లలో లోపం ఉంది.", "why": "ప్రొవైడర్ కాల్ తిరస్కరించింది లేదా కీ తప్పు / లేదు.",
               "impact": "వాటిపై ఆధారపడిన ఫీచర్లు పనిచేయవు.",
               "action": "ఇంటిగ్రేషన్ రెడీనెస్‌లో కారణం చూడండి; కీ Railway లో సరిచేయండి (చాట్‌లో పెట్టవద్దు)."}},
}

_GREEN = {"en": {"what": "Nothing open.", "why": "", "impact": "", "action": "No action needed."},
          "te": {"what": "ఏమీ పెండింగ్ లేదు.", "why": "", "impact": "", "action": "చర్య అవసరం లేదు."}}

BUTTON = {"en": "Open", "te": "తెరవండి"}


def severity(item: Dict[str, Any]) -> str:
    if not item.get("count"):
        return "green"
    return "red" if item.get("key") in URGENT else "orange"


def enrich(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Adds severity, icon and the en / te explanation to each queue item;
    red first, then orange (largest count first), green last."""
    for item in items:
        sev = severity(item)
        item["severity"], item["icon"] = sev, ICON[sev]
        texts = TEXT.get(item.get("key") or "")
        explain = {}
        for lang in ("en", "te"):
            if not texts:
                base = dict(_GREEN[lang], what=str(item.get("title") or item.get("key")) + ": "
                            + str(item.get("count", 0)), why=str(item.get("why") or ""))
            elif sev == "green":  # say WHICH module is clear, in the reader's language
                base = dict(texts[lang], why="", impact="", action=_GREEN[lang]["action"])
            else:
                base = texts[lang]
            explain[lang] = {k: v.format(n=item.get("count", 0)) for k, v in base.items()}
            explain[lang]["button"] = BUTTON[lang]
        item["explain"] = explain
    rank = {"red": 0, "orange": 1, "green": 2}
    return sorted(items, key=lambda i: (rank[i["severity"]], -int(i.get("count") or 0)))


def counts(items: List[Dict[str, Any]]) -> Dict[str, int]:
    out = {"red": 0, "orange": 0, "green": 0}
    for item in items:
        out[item["severity"]] += 1
    return out
