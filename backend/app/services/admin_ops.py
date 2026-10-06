"""Operational commands for the Admin Assistant (English + Telugu).

Each command answers from stored records only (OBSERVED), names what MIGHT
explain it, recommends an action, and -- when something could be changed --
returns an ``operation`` the console shows as a button with a preview. The
assistant itself never writes: every change happens on the module's own
screen, behind that screen's own confirmation (bulk import, notify sellers,
edits), so a misread question can never alter data.
"""
from __future__ import annotations

import re
from typing import Any, Callable, Dict, List, Optional

_URL = re.compile(r"https?://[^\s<>\"']+", re.I)
_TELUGU = re.compile(r"[ఀ-౿]")

COMMANDS = (
    ("add_links", r"\b(add|create|import|draft|make)\b.*\b(url|link|links|product|products|offer|coupon)\b"
                  r"|జోడించ|లింక్"),
    ("missing_prices", r"missing price|without (a )?price|no price|price missing|ధర లేని|ధర లేదు"),
    ("duplicates", r"duplicat|same product twice|నకిలీ|రెండుసార్లు"),
    ("failing_sources", r"source.{0,20}(fail|error|down|broken|not working)|failing source|సోర్స్"),
    ("needs_review", r"need(s|ing)? review|pending review|to review|waiting (for )?(approval|review)|సమీక్ష"),
    ("why_missing", r"why (didn'?t|did not|isn'?t|is not|doesn'?t|does not|wasn'?t).{0,60}(appear|show|visible|come)"
                    r"|ఎందుకు.{0,40}(కనిపించ|రాలేదు)"),
    ("opportunities", r"assign|opportunit|అవకాశ"),
)

TEXT = {
    "en": {
        "add_links": "Add links", "missing_prices": "Products without a price", "duplicates": "Possible duplicates",
        "failing_sources": "Failing sources", "needs_review": "Waiting for review", "why_missing": "Why it did not appear",
        "opportunities": "Opportunities to assign",
        "open_se": "Open in Smart Entry (preview, then import with confirmation)",
        "no_links": "No link found in the message. Paste the links after the command.",
        "fix_price": "Open each product and enter the price shown on its page (never estimate).",
        "dup_act": "Open both records; keep one and delete or disable the other.",
        "src_act": "Open Source health for the exact error; fix the source settings or disable it.",
        "rev_act": "Open the review queue and approve or reject each with a reason.",
        "opp_act": "Preview matching sellers in Demand intelligence, then notify (it asks to confirm).",
        "nothing": "Nothing found.",
    },
    "te": {
        "add_links": "లింక్‌లు జోడించండి", "missing_prices": "ధర లేని ఉత్పత్తులు", "duplicates": "నకిలీ కావచ్చు",
        "failing_sources": "విఫలమవుతున్న సోర్స్‌లు", "needs_review": "సమీక్ష కోసం ఎదురుచూస్తున్నవి",
        "why_missing": "ఎందుకు కనిపించలేదు", "opportunities": "కేటాయించాల్సిన అవకాశాలు",
        "open_se": "స్మార్ట్ ఎంట్రీలో తెరవండి (ముందు చూసి, నిర్ధారించి దిగుమతి)",
        "no_links": "సందేశంలో లింక్ లేదు. ఆదేశం తర్వాత లింక్‌లు పెట్టండి.",
        "fix_price": "ప్రతి ఉత్పత్తి తెరిచి, దాని పేజీలో ఉన్న ధర పెట్టండి (అంచనా వేయవద్దు).",
        "dup_act": "రెండు రికార్డులు తెరిచి, ఒకటి ఉంచి మరొకటి తొలగించండి లేదా ఆపండి.",
        "src_act": "సోర్స్ హెల్త్‌లో లోపం చూసి, సెట్టింగ్‌లు సరిచేయండి లేదా ఆపండి.",
        "rev_act": "సమీక్ష జాబితా తెరిచి, కారణంతో ఆమోదించండి లేదా తిరస్కరించండి.",
        "opp_act": "డిమాండ్‌లో సరిపోయే విక్రేతలను చూసి, తెలియజేయండి (నిర్ధారణ అడుగుతుంది).",
        "nothing": "ఏమీ లేదు.",
    },
}

REASONS = {
    "deleted": ("it was deleted", "అది తొలగించబడింది"),
    "disabled_by_staff": ("staff disabled it", "సిబ్బంది దాన్ని ఆపారు"),
    "out_of_stock": ("it is marked OUT_OF_STOCK", "స్టాక్ లేదు అని ఉంది"),
    "expired": ("its validity date has passed", "దాని గడువు ముగిసింది"),
    "commission_inactive_hidden": ("commission is INACTIVE and the policy hides such links",
                                   "కమీషన్ ఇనాక్టివ్, అలాంటి లింక్‌లు దాచబడతాయి"),
    "source_off": ("its source's organic results are switched off", "దాని సోర్స్ ఫలితాలు ఆపబడ్డాయి"),
}


def language(question: str, requested: str = "") -> str:
    if str(requested or "").lower().startswith("te") or _TELUGU.search(question or ""):
        return "te"
    return "en"


def commands(question: str) -> List[str]:
    text = (question or "").casefold()
    found = [name for name, pattern in COMMANDS if re.search(pattern, text)]
    if _URL.search(question or "") and "add_links" not in found:
        found.insert(0, "add_links")
    return found


def _target(question: str) -> str:
    t = question.casefold()
    if re.search(r"offer|coupon|cashback|bank|ఆఫర్", t):
        return "offer"
    if re.search(r"video|వీడియో", t):
        return "video"
    if re.search(r"source|సోర్స్", t):
        return "source"
    if re.search(r"product|item|ఉత్పత్తి", t):
        return "catalog"
    return "auto"


def _subject(question: str) -> str:
    quoted = re.search(r"[\"“]([^\"”]{2,80})[\"”]", question) or re.search(r"(?:^|\s)[‘']([^‘’']{2,80})[’'](?:\s|\?|$)", question)
    if quoted:
        return quoted.group(1).strip()
    m = re.search(r"why (?:didn'?t|did not|isn'?t|is not|doesn'?t|does not|wasn'?t)\s+(?:the\s+)?(?:product\s+)?"
                  r"(.{2,80}?)\s+(?:appear|show|visible|come)", question, re.I)
    return m.group(1).strip() if m else ""


def _norm(title: Any) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(title or "").lower()).strip()


def run(command: str, question: str, lang: str, *, catalog_items: Optional[Callable[[], List[Dict[str, Any]]]] = None,
        prepare_links: Optional[Callable[[List[str], str], Dict[str, Any]]] = None,
        sources_overview: Optional[Callable[[], List[Dict[str, Any]]]] = None,
        review_counts: Optional[Callable[[], Dict[str, int]]] = None,
        unmet: Optional[Callable[[], List[Dict[str, Any]]]] = None) -> Dict[str, Any]:
    """One command -> {topic, title, observed, likely, actions, operation?}.
    A data getter that is None means the caller lacks the permission."""
    T = TEXT[lang]
    out: Dict[str, Any] = {"topic": command, "title": T[command], "observed": [], "likely": [], "actions": [],
                           "operation": None}
    denied = "You do not have permission to see this." if lang == "en" else "దీన్ని చూసే అనుమతి లేదు."

    if command == "add_links":
        links = list(dict.fromkeys(_URL.findall(question)))[:50]
        if not links:
            out["observed"] = [T["no_links"]]
            return out
        target = _target(_URL.sub(" ", question))
        if prepare_links is None:
            out["observed"] = [denied]
            return out
        prepared = prepare_links(links, target)
        verdicts = prepared.get("verdicts") or {}
        out["observed"] = [(f"{len(links)} link(s) read: " if lang == "en" else f"{len(links)} లింక్‌లు చదివాం: ") + ", ".join(f"{k} {v}" for k, v in verdicts.items() if v)]
        out["observed"] += [f"- {i.get('verdict')}: {str(i.get('input'))[:70]}"
                            + (f" ({'; '.join(i.get('errors') or [])})" if i.get("errors") else "")
                            for i in (prepared.get("items") or [])[:8]]
        out["actions"] = [T["open_se"]]
        out["operation"] = {"kind": "open_smart_entry", "label": T["open_se"], "inputs": links, "target": target,
                            "preview": verdicts}
        return out

    if command in ("missing_prices", "duplicates", "why_missing"):
        if catalog_items is None:
            out["observed"] = [denied]
            return out
        items = catalog_items()
        if command == "missing_prices":
            rows = [i for i in items if i.get("price") in (None, "")]
            out["observed"] = [f"{len(rows)} catalog product(s) have no price" if lang == "en" else f"{len(rows)} ఉత్పత్తులకు ధర లేదు"] + \
                [f"- #{i['id']} {str(i.get('title'))[:70]} ({i.get('platform')})" for i in rows[:10]]
            if rows:
                out["actions"] = [T["fix_price"]]
                out["operation"] = {"kind": "open_view", "view": "affproducts", "label": T["missing_prices"]}
        elif command == "duplicates":
            groups: Dict[str, List[Dict[str, Any]]] = {}
            for i in items:
                key = _norm(i.get("title"))
                if key:
                    groups.setdefault(key, []).append(i)
            dups = [g for g in groups.values() if len(g) > 1]
            out["observed"] = [f"{len(dups)} title(s) used by more than one product" if lang == "en"
                                  else f"{len(dups)} పేర్లు ఒకటి కంటే ఎక్కువ ఉత్పత్తులకు ఉన్నాయి"] + \
                ["- " + " / ".join(f"#{i['id']} {str(i.get('title'))[:40]} ({i.get('platform')})" for i in g[:3])
                 for g in dups[:8]]
            if dups:
                out["likely"] = ["Same product from two stores, or one product added twice with different links."
                                 if lang == "en" else "రెండు దుకాణాల నుండి ఒకే ఉత్పత్తి, లేదా రెండుసార్లు జోడించారు."]
                out["actions"] = [T["dup_act"]]
                out["operation"] = {"kind": "open_view", "view": "affproducts", "label": T["duplicates"]}
        else:
            name = _subject(question)
            words = [w for w in _norm(name).split() if len(w) > 1]
            hits = [i for i in items if words and all(w in _norm(i.get("title")) for w in words)][:5]
            if not name:
                out["observed"] = ["Name the product in quotes, e.g. why didn't \"Kurti Blue\" appear?"
                                   if lang == "en" else "ఉత్పత్తి పేరు కోట్స్‌లో ఇవ్వండి."]
            elif not hits:
                out["observed"] = [f"No catalog product matches '{name}'." if lang == "en"
                                   else f"'{name}' కి సరిపోయే ఉత్పత్తి కేటలాగ్‌లో లేదు."]
                out["likely"] = ["Seller listings and web / map results are not catalog items: check Result "
                                 "diagnostics for that search to see each source and why rows were dropped."
                                 if lang == "en" else "విక్రేత లిస్టింగ్‌లు, వెబ్ ఫలితాలు వేరు: ఆ శోధన కోసం "
                                 "రిజల్ట్ డయాగ్నస్టిక్స్ చూడండి."]
                out["operation"] = {"kind": "open_view", "view": "resultdiag", "label": "Result diagnostics",
                                    "query": name}
            for i in hits:
                ev = i.get("eligibility") or {}
                reasons = ev.get("reasons") or []
                idx = 1 if lang == "te" else 0
                words_ = [REASONS.get(r, (r.replace("review_", "review status is ").upper()
                                          if r.startswith("review_") else r,) * 2)[idx] for r in reasons]
                if reasons:
                    out["observed"].append(f"#{i['id']} {str(i.get('title'))[:60]}: " + "; ".join(words_))
                else:
                    out["observed"].append(
                        f"#{i['id']} {str(i.get('title'))[:60]}: eligible -- it can appear when a search matches "
                        "its title / category and location." if lang == "en" else
                        f"#{i['id']} {str(i.get('title'))[:60]}: అర్హత ఉంది -- శోధన సరిపోతే కనిపిస్తుంది.")
            if hits:
                out["actions"] = ["Open the product to change the state that blocks it (with a reason)."
                                  if lang == "en" else "అడ్డుకుంటున్న స్థితిని మార్చడానికి ఉత్పత్తి తెరవండి."]
                out["operation"] = {"kind": "open_view", "view": "affproducts", "label": T["why_missing"]}
        if not out["observed"]:
            out["observed"] = [T["nothing"]]
        return out

    if command == "failing_sources":
        if sources_overview is None:
            out["observed"] = [denied]
            return out
        bad = [s for s in sources_overview() if (s.get("health") or {}).get("status") not in ("ok", "not_checked", None)
               or int((s.get("health") or {}).get("failures_in_row") or 0) > 0]
        out["observed"] = [f"{len(bad)} source(s) report an error" if lang == "en" else f"{len(bad)} సోర్స్‌లలో లోపం ఉంది"] + \
            [f"- {s.get('name')}: {(s.get('health') or {}).get('last_error') or (s.get('health') or {}).get('status')}"
             f" ({(s.get('health') or {}).get('failures_in_row', 0)} in a row)" for s in bad[:8]]
        if bad:
            out["actions"] = [T["src_act"]]
            out["operation"] = {"kind": "open_view", "view": "sourcehealth", "label": T["failing_sources"]}
        return out

    if command == "needs_review":
        if review_counts is None:
            out["observed"] = [denied]
            return out
        counts = {k: v for k, v in review_counts().items() if v}
        out["observed"] = [f"{k}: {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])] or [T["nothing"]]
        if counts:
            out["actions"] = [T["rev_act"]]
            out["operation"] = {"kind": "open_view", "view": "workspace", "label": T["needs_review"]}
        return out

    if command == "opportunities":
        if unmet is None:
            out["observed"] = [denied]
            return out
        rows = unmet()[:5]
        out["observed"] = [f"'{r.get('subject')}': {r.get('count')} searches without local supply" if lang == "en"
                           else f"'{r.get('subject')}': స్థానిక సరఫరా లేని {r.get('count')} శోధనలు" for r in rows] \
            or [T["nothing"]]
        if rows:
            out["actions"] = [T["opp_act"]]
            out["operation"] = {"kind": "open_view", "view": "demand", "label": T["opportunities"]}
        return out
    return out
