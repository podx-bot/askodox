"""ONE canonical result contract for every ASKODOX surface (app, web chat).

``build(...)`` turns the merged discovery rows into versioned, independent
SECTIONS. The orchestrator only classifies, orders and explains -- it never
drops a relevant row because another section exists:

* every row gets exactly one canonical ``section`` (local, deals, online,
  affiliate, partner, sponsored, videos, shorts, jobs, content);
* sections are additive -- adding videos never removes links, adding local
  never removes online; a failed source affects only its own section;
* each section carries its rows' ids in display order, its source status and
  whether the user asked for it (an asked-for empty section is still
  returned, with the reason, so the client never shows nothing silently);
* local rows are ranked nearest first (radius widens only in discovery);
* section order and per-section limits come from the Command Center
  (``result_orchestration`` resource), else the built-in order;
* ``conversation_state`` echoes the explicit constraints exactly as the
  user gave them (Size 9 stays "9") so diagnostics can prove they survived;
* ``answer`` says honestly what was found -- never "showing options" with
  zero cards.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional

from app.services.provider_failure import FAILURE_STATES

CONTRACT_VERSION = 2
SECTION_KINDS = ("local", "deals", "online", "affiliate", "partner", "content", "videos", "shorts", "jobs",
                 "sponsored")
DEFAULT_ORDER = ("local", "deals", "online", "affiliate", "partner", "content", "videos", "shorts", "jobs",
                 "sponsored")
LOCAL_SEGMENTS = {"registered", "individual", "nearby_external", "wider_local", "askodox", "local"}
DEALS_SEGMENTS = {"deals", "used", "surplus", "offers"}
# Which source_status keys feed each section (for "why is it empty").
SECTION_SOURCES = {
    "local": ("askodox", "nearby"), "deals": ("used_deals",), "online": ("online", "marketplaces"),
    "affiliate": ("online",), "partner": ("partner",), "videos": ("videos",), "shorts": ("videos",),
    "jobs": ("jobs",), "sponsored": ("sponsored",), "content": ("content",),
}
GROUP_TO_SECTIONS = {"local": ("local",), "deals": ("deals",), "online": ("online", "affiliate"),
                     "videos": ("videos", "shorts"), "jobs": ("jobs",)}


def section_of(row: Dict[str, Any]) -> str:
    """The ONE canonical section of a result row."""
    if row.get("sponsored"):
        return "sponsored"
    source = str(row.get("match_source") or row.get("source") or "").lower()
    segment = str(row.get("segment") or "").lower()
    if source == "video" or segment in ("video", "videos"):
        return "shorts" if str(row.get("video_format") or "").lower() == "short" else "videos"
    if str(row.get("item_type") or "") in ("news", "content", "video") and row.get("origin") == "content":
        return "content"
    if segment == "jobs" or source == "jobs":
        return "jobs"
    if segment == "partner":
        return "partner"
    if segment in DEALS_SEGMENTS:
        return "deals"
    if segment in LOCAL_SEGMENTS or source in ("askodox", "registered", "nearby", "local", "interest", "match"):
        return "local"
    if row.get("affiliate") or str(row.get("routing") or "") == "affiliate":
        return "affiliate"
    return "online"


_SHORT_ASK = ("short", "shorts", "reel", "reels", "quick", "30 sec", "1 min", "షార్ట్", "రీల్")
_LONG_ASK = ("review", "reviews", "comparison", "compare", " vs ", "unboxing", "how to", "tutorial", "explained",
             "detailed", "full", "guide", "install", "repair", "రివ్యూ", "पूरा", "रिव्यू")


def video_preference(demand: Dict[str, Any]) -> str:
    """'shorts' / 'videos' / '' -- which video kind the customer's own words
    favour. Shorts are never the only kind: both sections stay."""
    words = f" {demand.get('said') or ''} {demand.get('raw_text') or ''} ".lower()
    short = any(w in words for w in _SHORT_ASK)
    long = any(w in words for w in _LONG_ASK)
    if short and not long:
        return "shorts"
    if long and not short:
        return "videos"
    return ""


def _tokens(text: Any) -> set:
    import re

    return {t for t in re.findall(r"[a-z0-9\u0c00-\u0c7f\u0900-\u097f]+", str(text or "").lower()) if len(t) > 1}


def _video_rank(row: Dict[str, Any], subject_tokens: set, index: int) -> tuple:
    """Relevance first (share of the subject's words in the title / channel),
    then the source's own order. Never drops a row."""
    title = _tokens(f"{row.get('title') or ''} {row.get('source_name') or ''}")
    overlap = len(subject_tokens & title) / len(subject_tokens) if subject_tokens else 0.0
    reviewed = 1 if row.get("origin") in ("reviewed", "command_center") or row.get("reviewed") else 0
    return (-round(overlap, 2), -reviewed, index)


def _distance(row: Dict[str, Any]) -> float:
    for key in ("distance_km", "distanceKm", "distance"):
        try:
            value = row.get(key)
            if value is not None:
                return float(value)
        except (TypeError, ValueError):
            continue
    return float("inf")


def explicit_constraints(demand: Dict[str, Any]) -> Dict[str, Any]:
    """The user's own constraints exactly as given -- never widened."""
    constraints = dict(demand.get("constraints") or {})
    keep = {}
    for key in ("size", "quantity", "budget", "budget_max", "budget_min", "brand", "color", "condition",
                "model", "dates", "date", "time", "radius_km", "gender"):
        value = constraints.get(key, (demand.get("dynamic_fields") or {}).get(key))
        if value not in (None, "", [], {}):
            keep[key] = value
    return keep


def conversation_state(demand: Dict[str, Any], advisor: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    constraints = demand.get("constraints") or {}
    return {
        "intent": demand.get("intent") or demand.get("side"),
        "role": demand.get("role") or demand.get("side"),
        "category": demand.get("domain") or demand.get("category"),
        "query": demand.get("subject"),
        "explicit_constraints": explicit_constraints(demand),
        "location": demand.get("location_text") or None,
        "radius_km": constraints.get("radius_km") or demand.get("radius_km"),
        "requested_groups": list(constraints.get("requested_groups") or []),
        "advisor": {"category": ((advisor or {}).get("category") or {}).get("key"),
                    "known": (advisor or {}).get("known") or {},
                    "open_required": [q.get("field") for q in (advisor or {}).get("questions") or []
                                      if q.get("required")]} if advisor else None,
    }


def settings_from(pf: Any) -> Dict[str, Any]:
    """Command Center ``result_orchestration`` (first ACTIVE record)."""
    try:
        for record in pf.repo.list("result_orchestration"):
            if record.get("status") == "ACTIVE" and not record.get("archived"):
                return record.get("data") or {}
    except Exception:
        pass
    return {}


def build(matches: Iterable[Dict[str, Any]], *, demand: Dict[str, Any], source_status: Dict[str, Any] | None = None,
          errors: Iterable[str] = (), advisor: Optional[Dict[str, Any]] = None,
          settings: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    rows = list(matches or [])
    status = dict(source_status or {})
    settings = settings or {}
    order = [k for k in (settings.get("section_order") or []) if k in SECTION_KINDS]
    order += [k for k in DEFAULT_ORDER if k not in order]
    limits = settings.get("section_limits") if isinstance(settings.get("section_limits"), dict) else {}
    requested = set()
    for group in (demand.get("constraints") or {}).get("requested_groups") or []:
        requested.update(GROUP_TO_SECTIONS.get(str(group), ()))

    by_section: Dict[str, List[Dict[str, Any]]] = {k: [] for k in SECTION_KINDS}
    seen: set = set()
    duplicates = 0
    for row in rows:
        key = str(row.get("id") or row.get("match_id") or "")
        if key and key in seen:
            duplicates += 1  # the same item twice -- never two different items
            continue
        seen.add(key)
        section = section_of(row)
        row["section"] = section
        by_section[section].append(row)
    by_section["local"].sort(key=_distance)  # nearest first; stable for equal / unknown distance
    subject_tokens = _tokens(demand.get("subject"))
    for kind in ("videos", "shorts"):
        ranked = sorted(enumerate(by_section[kind]), key=lambda pair: _video_rank(pair[1], subject_tokens, pair[0]))
        by_section[kind] = [row for _, row in ranked]
    # The video kind the customer asked for comes first (unless staff fixed
    # an explicit order in the Command Center).
    preferred = video_preference(demand)
    if preferred and not settings.get("section_order"):
        other = "videos" if preferred == "shorts" else "shorts"
        if order.index(preferred) > order.index(other):
            order.remove(preferred)
            order.insert(order.index(other), preferred)

    sections, suppressed = [], {}
    for kind in order:
        items = by_section[kind]
        limit = int(limits.get(kind) or 0)
        shown = items[:limit] if limit > 0 else items
        if limit and len(items) > limit:
            suppressed[kind] = f"limited to {limit} by Command Center"
        source_states = {s: status.get(s) for s in SECTION_SOURCES.get(kind, ()) if status.get(s)}
        if shown or kind in requested:
            sections.append({"kind": kind, "item_ids": [str(r.get("id")) for r in shown], "count": len(shown),
                             "requested": kind in requested, "status": source_states,
                             **({"empty_reason": _why_empty(kind, source_states)} if not shown else {})})
        elif source_states and any(v not in ("ok", "not_applicable", "no_results") for v in source_states.values()):
            suppressed[kind] = "source unavailable: " + ", ".join(f"{k}={v}" for k, v in source_states.items())
    total = sum(s["count"] for s in sections)
    checked = sorted(k for k, v in status.items() if v and v != "not_applicable")
    unavailable = sorted(k for k, v in status.items() if v in ("unavailable", "needs_location", *FAILURE_STATES))
    return {
        "result_contract_version": CONTRACT_VERSION,
        "sections": sections,
        "conversation_state": conversation_state(demand, advisor),
        "answer": {"has_results": total > 0, "count": total, "checked": checked, "unavailable": unavailable,
                   # The client must not claim "showing options" unless this is true.
                   "may_claim_results": total > 0},
        "orchestration": {"order": order, "suppressed": suppressed, "duplicates_dropped": duplicates,
                          # The same failure is reported once, never twice.
                          "errors": list(dict.fromkeys(str(e) for e in errors))},
    }


def _why_empty(kind: str, states: Dict[str, Any]) -> str:
    if not states:
        return "no matching results"
    bad = {k: v for k, v in states.items() if v not in ("ok", "no_results")}
    if bad:
        return "source unavailable right now: " + ", ".join(f"{k} ({v})" for k, v in bad.items())
    return "checked -- nothing matched"


# --------------------------------------------------------------------------
# Result Diagnostics (Command Center): one row per query, the app later
# reports which sections it actually rendered.
# --------------------------------------------------------------------------
_KEEP_ROWS = 5000


def _table(db) -> None:
    db.execute("""CREATE TABLE IF NOT EXISTS result_diagnostics (
        trace_key TEXT PRIMARY KEY, created_at REAL NOT NULL, query TEXT, payload TEXT NOT NULL,
        rendered TEXT)""")


def remember(container, trace_key: str, demand: Dict[str, Any], discovered: Dict[str, Any],
             contract: Dict[str, Any]) -> None:
    import json
    import time

    if not trace_key:
        return
    db = container.database
    _table(db)
    payload = {
        "understood": {k: v for k, v in contract["conversation_state"].items() if k != "advisor"},
        "advisor": contract["conversation_state"].get("advisor"),
        "preserved_constraints": contract["conversation_state"]["explicit_constraints"],
        "sources_attempted": discovered.get("source_status") or {},
        "counts_per_source": discovered.get("counts") or {},
        "filtered": discovered.get("filtered") or {},
        "merge_decision": discovered.get("fallback_decision"),
        "errors": list(discovered.get("errors") or []),
        "sections_returned": [{"kind": s["kind"], "count": s["count"], "requested": s["requested"],
                               **({"empty_reason": s["empty_reason"]} if "empty_reason" in s else {})}
                              for s in contract["sections"]],
        "suppressed": contract["orchestration"]["suppressed"],
        "duplicates_dropped": contract["orchestration"]["duplicates_dropped"],
        "order": contract["orchestration"]["order"],
        "answer": contract["answer"],
        "latency_ms": discovered.get("latency_ms"),
        **_decision_trace(demand, discovered),
    }
    db.execute("INSERT OR REPLACE INTO result_diagnostics(trace_key,created_at,query,payload,rendered) "
               "VALUES(?,?,?,?,(SELECT rendered FROM result_diagnostics WHERE trace_key=?))",
               (trace_key, time.time(), str(demand.get("subject") or "")[:200], json.dumps(payload, default=str),
                trace_key))
    db.execute("DELETE FROM result_diagnostics WHERE trace_key NOT IN "
               "(SELECT trace_key FROM result_diagnostics ORDER BY created_at DESC LIMIT ?)", (_KEEP_ROWS,))


def row_action(row: Dict[str, Any]) -> str:
    """The card action the app offers for a row (mirrors chat_result_policy):
    a registered ASKODOX listing -> order request, a nearby place ->
    directions, a video -> play, anything with a link -> open link."""
    section = section_of(row)
    source = str(row.get("match_source") or row.get("source") or "").lower()
    if section in ("videos", "shorts"):
        return "play"
    if section == "local" and (source in ("registered", "askodox", "listing") or str(row.get("id") or "").isdigit()):
        return "order_request"
    if section == "local" and (row.get("lat") is not None or row.get("maps_url") or row.get("place_id")):
        return "directions"
    if row.get("url") or row.get("destination_url") or row.get("link"):
        return "open_link"
    return "none"


def _decision_trace(demand: Dict[str, Any], discovered: Dict[str, Any]) -> Dict[str, Any]:
    """Mode, requested location, price provenance, rejections, ranking and
    actions for Result Diagnostics (no customer identity: subjects, counts,
    titles of public rows only)."""
    rows = list(discovered.get("matches") or [])
    loc = demand.get("location")
    if isinstance(loc, dict):
        loc = loc.get("label") or loc.get("name") or loc.get("city")
    kinds: Dict[str, int] = {}
    fits: Dict[str, int] = {}
    actions: Dict[str, Dict[str, int]] = {}
    for row in rows:
        if row.get("price") is not None or row.get("offer_price") is not None:
            k = str(row.get("price_kind") or ("verified" if row.get("price_verified") else "stated"))
            kinds[k] = kinds.get(k, 0) + 1
        if row.get("offer_price") is not None:
            kinds["conditional_offer"] = kinds.get("conditional_offer", 0) + 1
        if row.get("budget_fit"):
            fits[row["budget_fit"]] = fits.get(row["budget_fit"], 0) + 1
        sec = actions.setdefault(section_of(row), {})
        act = row_action(row)
        sec[act] = sec.get(act, 0) + 1
    raw = sum(int(v or 0) for v in (discovered.get("counts") or {}).values() if isinstance(v, (int, float)))
    return {
        "mode": str(demand.get("mode") or demand.get("intent") or demand.get("deal_type") or "commerce"),
        "requested_location": str(loc or "") or None,
        "counts_raw_vs_kept": {"raw": raw, "kept": len(rows), "rejected": len(discovered.get("rejected") or [])},
        "rejected": list(discovered.get("rejected") or [])[:30],
        "price_provenance": kinds,
        "budget_fit": fits,
        "ranking": [{"rank": i + 1, "section": section_of(r), "title": str(r.get("title") or "")[:80],
                     "price_kind": r.get("price_kind"), "budget_fit": r.get("budget_fit"),
                     "fit": (r.get("fit") or {}).get("state") if isinstance(r.get("fit"), dict) else r.get("fit")}
                    for i, r in enumerate(rows[:15])],
        "actions": actions,
    }


def record_rendered(container, trace_key: str, rendered: Iterable[str], hidden: Dict[str, str] | None = None) -> bool:
    """What the client ACTUALLY drew (and why it hid anything)."""
    import json

    db = container.database
    _table(db)
    row = db.fetchone("SELECT trace_key FROM result_diagnostics WHERE trace_key=?", (trace_key,))
    if not row:
        return False
    kinds = [str(k)[:20] for k in rendered if str(k) in SECTION_KINDS or str(k) in ("advisor", "notice")][:20]
    reasons = {str(k)[:20]: str(v)[:160] for k, v in (hidden or {}).items()}
    db.execute("UPDATE result_diagnostics SET rendered=? WHERE trace_key=?",
               (json.dumps({"sections": kinds, "hidden": reasons}), trace_key))
    return True


def diagnostics(container, *, trace_key: str = "", query: str = "", limit: int = 20) -> List[Dict[str, Any]]:
    """Newest first; each with returned vs rendered sections compared."""
    import json

    db = container.database
    _table(db)
    if trace_key:
        rows = db.fetchall("SELECT * FROM result_diagnostics WHERE trace_key=?", (trace_key,))
    elif query:
        rows = db.fetchall("SELECT * FROM result_diagnostics WHERE query LIKE ? ORDER BY created_at DESC LIMIT ?",
                           (f"%{query[:100]}%", max(1, min(limit, 100))))
    else:
        rows = db.fetchall("SELECT * FROM result_diagnostics ORDER BY created_at DESC LIMIT ?",
                           (max(1, min(limit, 100)),))
    out = []
    for row in rows:
        payload = json.loads(row["payload"])
        rendered = json.loads(row["rendered"]) if row["rendered"] else None
        returned = [s["kind"] for s in payload["sections_returned"] if s["count"]]
        not_rendered = {}
        if rendered is not None:
            for kind in returned:
                if kind not in rendered["sections"]:
                    not_rendered[kind] = rendered["hidden"].get(kind) or "returned but not rendered (no reason given)"
        out.append({"trace_key": row["trace_key"], "created_at": row["created_at"], "query": row["query"],
                    **payload, "sections_rendered": rendered["sections"] if rendered else None,
                    "render_suppressed": not_rendered if rendered is not None else "app has not reported yet"})
    return out
