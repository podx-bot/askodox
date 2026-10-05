"""Business Command Center for a Party-B seller / provider: the same backend
truth the Command Center reads, turned into a short list of what to do.

Every insight is labelled
  CONFIRMED_FACT  -- counted from the seller's own records (orders, listings,
                     demand alerts, missing-data hits)
  POSSIBLE_CAUSE  -- a rule-based explanation that fits the facts but is not
                     proven (always worded as "may")
  RECOMMENDATION  -- one concrete action, with the app screen that does it
and carries a severity: red (act now), orange (worth doing today), green
(all good). Nothing is estimated: no views, sales or ranks are invented, and
a number the platform does not record is simply not shown.
"""
from __future__ import annotations

from typing import Any, Dict, List

from app.services.deal_lifecycle import CLOSED, COMPLETION_STATES, OPEN_EXECUTION, PLACED, REJECTED

FACT, CAUSE, ADVICE = "CONFIRMED_FACT", "POSSIBLE_CAUSE", "RECOMMENDATION"
LABELS = {"en": {FACT: "Confirmed fact", CAUSE: "Possible cause", ADVICE: "Recommendation"},
          "te": {FACT: "నిర్ధారిత వాస్తవం", CAUSE: "సాధ్యమైన కారణం", ADVICE: "సూచన"}}


def _say(language: str, en: str, te: str) -> str:
    return te if language == "te" else en


def _insight(kind: str, severity: str, title: str, detail: str, language: str,
             action: Dict[str, str] | None = None, basis: str = "") -> Dict[str, Any]:
    return {"kind": kind, "label": LABELS.get(language, LABELS["en"])[kind], "severity": severity,
            "title": title, "detail": detail, "action": action, "basis": basis}


def summary(listings: List[Dict[str, Any]], gaps: List[Dict[str, Any]], opportunities: List[Dict[str, Any]],
            orders: List[Dict[str, Any]]) -> Dict[str, int]:
    status = [str(o.get("status") or "").upper() for o in orders]
    return {
        "listings": len(listings),
        "out_of_stock": sum(1 for l in listings if str(l.get("stock_status") or "").upper() == "OUT_OF_STOCK"),
        "without_price": sum(1 for l in listings if l.get("price") in (None, "")),
        "requests_waiting": status.count(PLACED),
        "in_progress": sum(1 for s in status if s in OPEN_EXECUTION),
        "completed": sum(1 for s in status if s in COMPLETION_STATES or s == CLOSED),
        "declined": status.count(REJECTED),
        "opportunities_new": sum(1 for o in opportunities if o.get("status") in ("new", "opened")),
        "missing_data_hits": sum(int(g.get("hits") or 0) for g in gaps),
    }


def insights(listings: List[Dict[str, Any]], gaps: List[Dict[str, Any]], opportunities: List[Dict[str, Any]],
             orders: List[Dict[str, Any]], language: str = "en") -> List[Dict[str, Any]]:
    lang = "te" if str(language or "").lower().startswith("te") else "en"
    s = summary(listings, gaps, opportunities, orders)
    out: List[Dict[str, Any]] = []

    if s["requests_waiting"]:
        n = s["requests_waiting"]
        out.append(_insight(FACT, "red",
                            _say(lang, f"{n} customer request(s) waiting for your answer",
                                 f"{n} కస్టమర్ అభ్యర్థన(లు) మీ జవాబు కోసం ఎదురుచూస్తున్నాయి"),
                            _say(lang, "A customer sees no reply until you accept or decline.",
                                 "మీరు అంగీకరించే లేదా తిరస్కరించే వరకు కస్టమర్‌కు జవాబు కనిపించదు."),
                            lang, {"label": _say(lang, "Open requests", "అభ్యర్థనలు తెరవండి"),
                                   "route": "/orders/incoming"}, "orders with status PLACED"))

    by_listing: Dict[int, List[Dict[str, Any]]] = {}
    for gap in gaps:
        by_listing.setdefault(int(gap["listing_id"]), []).append(gap)
    titles = {int(l["id"]): l.get("subject") or "" for l in listings if str(l.get("id") or "").isdigit()}
    for listing_id, rows in sorted(by_listing.items(), key=lambda kv: -sum(r["hits"] for r in kv[1]))[:3]:
        if listing_id not in titles:
            continue  # listing removed since
        fields = ", ".join(r["field"] for r in rows)
        hits = sum(int(r["hits"]) for r in rows)
        name = titles[listing_id] or rows[0].get("subject") or "your listing"
        out.append(_insight(FACT, "orange",
                            _say(lang, f"{hits} searches asked for {fields}; '{name}' does not say",
                                 f"{hits} శోధనలు {fields} అడిగాయి; '{name}' లో అది లేదు"),
                            _say(lang, "These customers saw your listing marked 'not stated by the seller'.",
                                 "ఈ కస్టమర్లకు మీ లిస్టింగ్ 'విక్రేత చెప్పలేదు' అని కనిపించింది."),
                            lang, None, "supply_gaps (aggregated, no customer identity)"))
        out.append(_insight(ADVICE, "orange",
                            _say(lang, f"Add {fields} to '{name}'", f"'{name}' కు {fields} జోడించండి"),
                            _say(lang, "Listings that state what customers ask for rank above ones that do not.",
                                 "కస్టమర్లు అడిగేది చెప్పే లిస్టింగ్‌లు ముందు చూపబడతాయి."),
                            lang, {"label": _say(lang, "Edit listing", "లిస్టింగ్ మార్చండి"),
                                   "route": "/listings/mine"}))

    if s["out_of_stock"]:
        out.append(_insight(FACT, "orange",
                            _say(lang, f"{s['out_of_stock']} listing(s) marked out of stock",
                                 f"{s['out_of_stock']} లిస్టింగ్(లు) స్టాక్ లేదు అని ఉన్నాయి"),
                            _say(lang, "Out-of-stock listings rank last and cannot match a need.",
                                 "స్టాక్ లేని లిస్టింగ్‌లు చివర చూపబడతాయి."),
                            lang, {"label": _say(lang, "Update stock", "స్టాక్ నవీకరించండి"),
                                   "route": "/listings/mine"}, "seller_products.stock_status"))
    if s["without_price"]:
        out.append(_insight(ADVICE, "orange",
                            _say(lang, f"Add a price to {s['without_price']} listing(s)",
                                 f"{s['without_price']} లిస్టింగ్(ల)కు ధర జోడించండి"),
                            _say(lang, "Without a price, a customer's budget cannot be checked, so the listing "
                                       "shows as 'price not stated'.",
                                 "ధర లేకపోతే కస్టమర్ బడ్జెట్‌తో సరిపోల్చలేము."),
                            lang, {"label": _say(lang, "Edit listing", "లిస్టింగ్ మార్చండి"),
                                   "route": "/listings/mine"}))

    if s["opportunities_new"]:
        n = s["opportunities_new"]
        out.append(_insight(FACT, "orange",
                            _say(lang, f"{n} new demand opportunit{'y' if n == 1 else 'ies'} near you",
                                 f"మీ దగ్గర {n} కొత్త డిమాండ్ అవకాశం(లు)"),
                            _say(lang, "Customers searched for what you sell in your area (no identities shared).",
                                 "మీ ప్రాంతంలో మీరు అమ్మేదాని కోసం కస్టమర్లు వెతికారు (వివరాలు పంచుకోబడవు)."),
                            lang, {"label": _say(lang, "See opportunities", "అవకాశాలు చూడండి"),
                                   "route": "/opportunities"}, "demand_alerts for this seller"))

    if s["declined"] >= 3 and s["declined"] > s["completed"]:
        out.append(_insight(CAUSE, "orange",
                            _say(lang, "You declined more requests than you completed",
                                 "పూర్తి చేసిన వాటికంటే ఎక్కువ అభ్యర్థనలు తిరస్కరించారు"),
                            _say(lang, "This may mean listings show items or quantities you cannot supply now.",
                                 "మీరు ఇప్పుడు ఇవ్వలేని వస్తువులు లిస్టింగ్‌లో ఉండి ఉండవచ్చు."),
                            lang, {"label": _say(lang, "Review listings", "లిస్టింగ్‌లు చూడండి"),
                                   "route": "/listings/mine"}, f"{s['declined']} declined, {s['completed']} completed"))

    if not listings:
        out.append(_insight(ADVICE, "orange",
                            _say(lang, "Add your first listing", "మీ మొదటి లిస్టింగ్ జోడించండి"),
                            _say(lang, "Customers can only be matched to what you list.",
                                 "మీరు జాబితా చేసిన వాటికే కస్టమర్లు సరిపోలుతారు."),
                            lang, {"label": _say(lang, "Add listing", "లిస్టింగ్ జోడించండి"),
                                   "route": "/listings/mine"}))
    if not out:
        out.append(_insight(FACT, "green", _say(lang, "Nothing needs your attention now",
                                                "ఇప్పుడు మీరు చేయాల్సింది ఏమీ లేదు"),
                            _say(lang, "No waiting requests, missing details or new opportunities.",
                                 "ఎదురుచూస్తున్న అభ్యర్థనలు, లోపించిన వివరాలు లేదా కొత్త అవకాశాలు లేవు."), lang))
    rank = {"red": 0, "orange": 1, "green": 2}
    return sorted(out, key=lambda i: rank[i["severity"]])
