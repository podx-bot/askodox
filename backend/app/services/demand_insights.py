"""Demand Intelligence: what customers need, what they fail to find, and
which registered sellers / providers could serve it.

Built on the existing event store (``pf_events``: ``search``, ``no_match``,
``request``, ``seller_accept`` ...) -- no second analytics system. Search
events carry only aggregate-safe dimensions: category, subject, area text,
language, budget band, result counts. No user identity, phone, OTP or
payment data is read or stored here.

Matching reuses ``app_demand_broadcast.candidate_providers`` (the same
relevance + area rules as request leads) and adds price fit, stock and
response history. Every alert is logged with the rule that fired and why the
recipient was chosen; cooldown and a per-seller daily maximum prevent spam.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import statistics
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional

BUDGET_BANDS = ((0, 500), (500, 1000), (1000, 2000), (2000, 5000), (5000, 10000), (10000, 25000),
                (25000, 50000), (50000, 100000), (100000, 500000), (500000, None))
_STOP = {"show", "me", "find", "need", "want", "buy", "a", "an", "the", "for", "in", "near", "i", "to", "of",
         "and", "some", "please", "best", "good", "cheap", "online", "price", "under", "below", "around", "with"}


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    # Same precision as recorded events (a search recorded this very second
    # must still be inside a window ending now).
    return dt.isoformat()


def budget_band(value: Any) -> Optional[str]:
    try:
        amount = float(value)
    except (TypeError, ValueError):
        return None
    if amount <= 0:
        return None
    for low, high in BUDGET_BANDS:
        if high is None or amount < high:
            return f"₹{low:,}+" if high is None else f"₹{low:,}-{high:,}"
    return None


def band_upper(band: Optional[str]) -> Optional[float]:
    if not band or "-" not in band:
        return None
    try:
        return float(band.split("-")[1].replace(",", ""))
    except ValueError:
        return None


def subject_key(subject: Any) -> str:
    words = [w for w in re.findall(r"[^\W\d_]+", str(subject or "").casefold()) if w not in _STOP and len(w) > 1]
    return " ".join(words[:6])


def area_key(location: Any) -> str:
    """Coarse locality (first part of the place label): never an address."""
    text = str(location or "").strip()
    return text.split(",")[0].strip().casefold()[:60] if text else ""


# ------------------------------------------------------------- insights --

def _search_rows(repo, since: str, until: Optional[str] = None, limit: int = 20000) -> List[Dict[str, Any]]:
    rows = repo.events(event="search", since=since, until=until, limit=limit)
    out = []
    for r in rows:
        d = r.get("detail") or {}
        key = subject_key(d.get("subject"))
        if not key:
            continue
        out.append({"at": r["at"], "subject": key, "category": r.get("category") or "", "area": area_key(r.get("location")),
                    "results": int(d.get("results") or 0), "local": int(d.get("local") if d.get("local") is not None
                                                                         else d.get("results") or 0),
                    "band": d.get("budget_band"), "brand": d.get("brand"), "language": r.get("language") or ""})
    return out


def insights(repo, *, days: int = 7, category: str = "", area: str = "", top: int = 15,
             until: Optional[datetime] = None) -> Dict[str, Any]:
    """Facts only, from recorded events. Periods compare equal lengths."""
    end = until or now()
    start, prev_start = end - timedelta(days=days), end - timedelta(days=2 * days)
    rows = _search_rows(repo, iso(prev_start), iso(end))
    cur = [r for r in rows if r["at"] >= iso(start)]
    prev = [r for r in rows if r["at"] < iso(start)]
    if category:
        cur = [r for r in cur if r["category"].casefold() == category.casefold()]
        prev = [r for r in prev if r["category"].casefold() == category.casefold()]
    if area:
        cur = [r for r in cur if r["area"] == area_key(area)]
        prev = [r for r in prev if r["area"] == area_key(area)]
    counts, before = Counter(r["subject"] for r in cur), Counter(r["subject"] for r in prev)
    no_result = Counter(r["subject"] for r in cur if r["results"] == 0)
    no_local = Counter(r["subject"] for r in cur if r["local"] == 0)
    rising = []
    for subject, n in counts.items():
        p = before.get(subject, 0)
        if n >= 3 and (p == 0 or (n - p) / p >= 0.25):
            rising.append({"subject": subject, "now": n, "before": p,
                           "change_pct": None if p == 0 else round((n - p) / p * 100)})
    rising.sort(key=lambda x: -x["now"])
    bands: Dict[str, Counter] = defaultdict(Counter)
    for r in cur:
        if r["band"]:
            bands[r["subject"]][r["band"]] += 1
    by_hour = Counter(int(r["at"][11:13]) for r in cur if len(r["at"]) > 13)
    by_weekday = Counter(datetime.fromisoformat(r["at"]).strftime("%a") for r in cur)

    def funnel_count(event: str) -> int:
        return len(repo.events(event=event, since=iso(start), until=iso(end), limit=100000))

    funnel = {e: funnel_count(e) for e in ("search", "result_click", "click", "request", "seller_accept",
                                            "seller_decline", "order", "no_match")}
    searches = max(1, funnel["search"])
    return {
        "period": {"from": iso(start), "to": iso(end), "days": days},
        "filters": {"category": category or None, "area": area or None},
        "totals": {"searches": len(cur), "previous_searches": len(prev), "distinct_needs": len(counts),
                   "no_result_searches": sum(no_result.values()), "no_local_supply_searches": sum(no_local.values())},
        "top_searches": [{"subject": s, "count": n, "no_local_supply": no_local.get(s, 0),
                          "budget_bands": dict(bands[s].most_common(3))} for s, n in counts.most_common(top)],
        "rising": rising[:top],
        "no_result": [{"subject": s, "count": n} for s, n in no_result.most_common(top)],
        "unmet": [{"subject": s, "count": n, "share_no_local": round(n / counts[s], 2)}
                  for s, n in no_local.most_common(top) if counts[s]],
        "by_area": [{"area": a or "(no place given)", "count": n}
                    for a, n in Counter(r["area"] for r in cur).most_common(top)],
        "by_category": [{"category": c or "(unknown)", "count": n}
                        for c, n in Counter(r["category"] for r in cur).most_common(top)],
        "brands": [{"brand": b, "count": n} for b, n in Counter(r["brand"] for r in cur if r["brand"]).most_common(top)],
        "by_hour": dict(sorted(by_hour.items())), "by_weekday": dict(by_weekday),
        "funnel": funnel,
        "rates": {"request_per_search": round(funnel["request"] / searches, 3),
                  "accept_per_request": round(funnel["seller_accept"] / max(1, funnel["request"]), 3),
                  "order_per_search": round(funnel["order"] / searches, 3),
                  "no_result_rate": round(len([r for r in cur if r["results"] == 0]) / max(1, len(cur)), 3)},
    }


# --------------------------------------------------------- opportunities --

def opportunities(repo, rule: Dict[str, Any], *, until: Optional[datetime] = None) -> List[Dict[str, Any]]:
    """Unmet demand clusters (subject + area) that pass one rule."""
    days = int(rule.get("window_days") or 7)
    end = until or now()
    rows = _search_rows(repo, iso(end - timedelta(days=days)), iso(end))
    category = str(rule.get("category") or "").strip().casefold()
    if category and category != "any":
        rows = [r for r in rows if r["category"].casefold() == category]
    keywords = [str(k).casefold() for k in rule.get("keywords") or [] if str(k).strip()]
    if keywords:
        rows = [r for r in rows if any(k in r["subject"] for k in keywords)]
    if rule.get("area"):
        rows = [r for r in rows if r["area"] == area_key(rule["area"])]
    groups: Dict[tuple, List[Dict[str, Any]]] = defaultdict(list)
    for r in rows:
        groups[(r["subject"], r["area"])].append(r)
    max_local = rule.get("max_local_results")
    out = []
    for (subject, area), items in groups.items():
        if len(items) < int(rule.get("min_searches") or 1):
            continue
        local_median = statistics.median([i["local"] for i in items])
        if max_local is not None and local_median > int(max_local):
            continue  # demand is already served locally
        bands = Counter(i["band"] for i in items if i["band"])
        top_band = bands.most_common(1)[0][0] if bands else None
        key = hashlib.sha1(f"{subject}|{area}".encode()).hexdigest()[:16]
        out.append({"key": key, "subject": subject, "area": area, "searches": len(items),
                    "category": Counter(i["category"] for i in items).most_common(1)[0][0],
                    "local_results_median": local_median, "budget_band": top_band,
                    "budget_bands": dict(bands.most_common(4)),
                    "first_seen": min(i["at"] for i in items), "last_seen": max(i["at"] for i in items)})
    out.sort(key=lambda o: -o["searches"])
    return out


# ---------------------------------------------------- alert log + matching --

@dataclass
class DemandAlertLog:
    db_path: str

    def __post_init__(self) -> None:
        with self._connect() as conn:
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS demand_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                opportunity_key TEXT NOT NULL, subject TEXT NOT NULL, area TEXT NOT NULL DEFAULT '',
                recipient TEXT NOT NULL, rule_id TEXT NOT NULL, actor TEXT NOT NULL,
                reasons_json TEXT NOT NULL DEFAULT '[]', score REAL NOT NULL DEFAULT 0,
                channel TEXT NOT NULL DEFAULT 'in_app', status TEXT NOT NULL,
                searches INTEGER NOT NULL DEFAULT 0, budget_band TEXT,
                sent_at TEXT NOT NULL, day TEXT NOT NULL,
                opened_at TEXT, responded_at TEXT, response TEXT, fulfilled_at TEXT,
                UNIQUE(opportunity_key, recipient, day)
            );
            CREATE INDEX IF NOT EXISTS idx_demand_alerts_recipient ON demand_alerts(recipient, sent_at);
            """)
            have = {r[1] for r in conn.execute("PRAGMA table_info(demand_alerts)").fetchall()}
            for column in ("expires_at TEXT", "category TEXT NOT NULL DEFAULT ''", "decline_reason TEXT"):
                if column.split()[0] not in have:
                    conn.execute(f"ALTER TABLE demand_alerts ADD COLUMN {column}")

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def recent_for(self, recipient: str, opportunity_key: str, hours: int) -> bool:
        since = iso(now() - timedelta(hours=hours))
        with self._connect() as conn:
            return conn.execute("SELECT 1 FROM demand_alerts WHERE recipient=? AND opportunity_key=? AND sent_at>=?",
                                (recipient, opportunity_key, since)).fetchone() is not None

    def sent_today(self, recipient: str) -> int:
        with self._connect() as conn:
            return int(conn.execute("SELECT COUNT(*) FROM demand_alerts WHERE recipient=? AND day=?",
                                    (recipient, now().date().isoformat())).fetchone()[0])

    def history(self, recipient: str) -> Dict[str, int]:
        with self._connect() as conn:
            row = conn.execute("""SELECT COUNT(*) n, SUM(responded_at IS NOT NULL) r,
                SUM(response='interested') a FROM demand_alerts WHERE recipient=?""", (recipient,)).fetchone()
        return {"sent": int(row["n"] or 0), "responded": int(row["r"] or 0), "interested": int(row["a"] or 0)}

    def record(self, *, opportunity: Dict[str, Any], recipient: str, rule_id: str, actor: str,
               reasons: List[str], score: float, channel: str, status: str, expiry_hours: int = 72
               ) -> Optional[int]:
        at = now()
        try:
            with self._connect() as conn:
                cur = conn.execute("""INSERT INTO demand_alerts(opportunity_key,subject,area,recipient,rule_id,actor,
                    reasons_json,score,channel,status,searches,budget_band,sent_at,day,expires_at,category)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                                   (opportunity["key"], opportunity["subject"], opportunity.get("area") or "",
                                    recipient, rule_id, actor, json.dumps(reasons, ensure_ascii=False),
                                    round(score, 3), channel, status, int(opportunity.get("searches") or 0),
                                    opportunity.get("budget_band"), iso(at), at.date().isoformat(),
                                    iso(at + timedelta(hours=max(1, int(expiry_hours)))),
                                    str(opportunity.get("category") or "")[:80]))
                return int(cur.lastrowid)
        except sqlite3.IntegrityError:
            return None  # already alerted today: never twice

    def for_recipient(self, recipient: str, limit: int = 50) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM demand_alerts WHERE recipient=? ORDER BY id DESC LIMIT ?",
                                (recipient, limit)).fetchall()
        return [self._public(r) for r in rows]

    def listing(self, *, limit: int = 200, opportunity_key: str = "") -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM demand_alerts", []
        if opportunity_key:
            sql += " WHERE opportunity_key=?"
            args.append(opportunity_key)
        with self._connect() as conn:
            rows = conn.execute(sql + " ORDER BY id DESC LIMIT ?", (*args, limit)).fetchall()
        return [self._public(r) for r in rows]

    def mark(self, alert_id: int, recipient: str, *, action: str, response: str = "", reason: str = ""
             ) -> Optional[Dict[str, Any]]:
        """open / respond (interested | not_relevant | added_offer) / fulfil.
        An expired opportunity can still be opened but no longer answered."""
        column = {"open": "opened_at", "respond": "responded_at", "fulfil": "fulfilled_at"}[action]
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM demand_alerts WHERE id=? AND recipient=?",
                               (alert_id, recipient)).fetchone()
            if row is None:
                return None
            if action == "respond" and row["responded_at"] is None and lifecycle(dict(row)) == "expired":
                raise ValueError("This opportunity has expired")
            if action == "fulfil" and (row["response"] or "") not in ("interested", "added_offer"):
                raise ValueError("Accept the opportunity before marking it fulfilled")
            extra, args = "", []
            if action == "respond":
                extra, args = ", response=?, decline_reason=?", [response, (reason or None) if response ==
                                                                   "not_relevant" else None]
            conn.execute(f"UPDATE demand_alerts SET {column}=COALESCE({column}, ?)" + extra + " WHERE id=?",
                         (iso(now()), *args, alert_id))
            row = conn.execute("SELECT * FROM demand_alerts WHERE id=?", (alert_id,)).fetchone()
        return self._public(row)

    def summary(self, *, since: str = "") -> Dict[str, Any]:
        """Admin view: how alerted demand ended (accepted / declined / expired / fulfilled)."""
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(
                "SELECT * FROM demand_alerts" + (" WHERE sent_at>=?" if since else ""),
                (since,) if since else ()).fetchall()]
        counts: Dict[str, int] = {}
        reasons: Dict[str, int] = {}
        for row in rows:
            state = lifecycle(row)
            counts[state] = counts.get(state, 0) + 1
            if row.get("decline_reason"):
                reasons[row["decline_reason"]] = reasons.get(row["decline_reason"], 0) + 1
        accepted = counts.get("accepted", 0) + counts.get("fulfilled", 0)
        return {"alerts": len(rows), "by_status": counts, "accepted_total": accepted,
                "unfulfilled": len(rows) - counts.get("fulfilled", 0),
                "decline_reasons": sorted(({"reason": k, "count": v} for k, v in reasons.items()),
                                          key=lambda x: -x["count"])}

    @staticmethod
    def _public(row) -> Dict[str, Any]:
        item = dict(row)
        item["reasons"] = json.loads(item.pop("reasons_json") or "[]")
        item["lifecycle"] = lifecycle(item)
        return item


def lifecycle(row: Dict[str, Any]) -> str:
    """new -> opened -> accepted / declined -> fulfilled; unanswered past
    ``expires_at`` -> expired."""
    if row.get("fulfilled_at"):
        return "fulfilled"
    response = row.get("response") or ""
    if row.get("responded_at") and response in ("interested", "added_offer"):
        return "accepted"
    if row.get("responded_at") and response == "not_relevant":
        return "declined"
    expires = row.get("expires_at")
    if expires and str(expires) < iso(now()):
        return "expired"
    return "opened" if row.get("opened_at") else "new"


def _in_hours(spec: Any, at: Optional[datetime] = None) -> bool:
    if not spec:
        return True
    try:
        start, end = (int(x) for x in str(spec).split("-"))
    except ValueError:
        return True
    hour = ((at or now()) + timedelta(hours=5, minutes=30)).hour  # India time
    return start <= hour < end if start <= end else hour >= start or hour < end


def match_recipients(catalog, opportunity: Dict[str, Any], rule: Dict[str, Any], log: DemandAlertLog
                     ) -> Dict[str, Any]:
    """Ranked eligible sellers plus every excluded one with the reason."""
    from app.services.app_demand_broadcast import candidate_providers

    demand = {"subject": opportunity["subject"], "location_text": opportunity.get("area") or "", "user_id": ""}
    candidates = candidate_providers(catalog, demand, limit=100)
    listings = {}
    try:
        for row in catalog.search_active(opportunity["subject"], limit=50) or []:
            listings.setdefault(str(row.get("seller_user_id") or ""), []).append(row)
    except Exception:
        pass
    budget_cap = band_upper(opportunity.get("budget_band"))
    eligible, excluded = [], []
    for c in candidates:
        seller = c["user_id"]
        rows = listings.get(seller) or []
        reasons = [f"sells '{c.get('listing')}' (matches '{opportunity['subject']}')"]
        if opportunity.get("area"):
            reasons.append(f"serves or is located in {opportunity['area']}")
        score = 1.0
        prices = [float(r["price"]) for r in rows if r.get("price") not in (None, "")]
        if rule.get("require_budget_fit") and budget_cap:
            if prices and min(prices) <= budget_cap * 1.1:
                reasons.append(f"has a price within the demand budget ({opportunity['budget_band']})")
                score += 0.5
            else:
                excluded.append({"recipient": seller, "reason": "no listing within the demand budget"})
                continue
        if rule.get("require_in_stock") and rows and all(
                str(r.get("stock_status") or "").lower() in {"out_of_stock", "oos", "0"} for r in rows):
            excluded.append({"recipient": seller, "reason": "listing out of stock"})
            continue
        if log.recent_for(seller, opportunity["key"], int(rule.get("cooldown_hours") or 24)):
            excluded.append({"recipient": seller, "reason": "cooldown: already alerted about this demand"})
            continue
        if log.sent_today(seller) >= int(rule.get("daily_max_per_seller") or 3):
            excluded.append({"recipient": seller, "reason": "daily maximum reached"})
            continue
        history = log.history(seller)
        if history["sent"]:
            rate = history["responded"] / history["sent"]
            score += rate
            reasons.append(f"responded to {history['responded']} of {history['sent']} earlier alerts")
        eligible.append({"recipient": seller, "score": round(score, 3), "reasons": reasons,
                         "listing_id": c.get("listing_id")})
    eligible.sort(key=lambda e: -e["score"])
    cap = int(rule.get("max_recipients") or 10)
    for extra in eligible[cap:]:
        excluded.append({"recipient": extra["recipient"], "reason": f"below the top {cap} for this rule"})
    return {"eligible": eligible[:cap], "excluded": excluded}


def alert_text(opportunity: Dict[str, Any], language: str = "en") -> Dict[str, str]:
    n, subject = opportunity["searches"], opportunity["subject"]
    where = f" in {opportunity['area'].title()}" if opportunity.get("area") else ""
    band = f" (budget around {opportunity['budget_band']})" if opportunity.get("budget_band") else ""
    if language == "te":
        where_te = f" {opportunity['area'].title()}లో" if opportunity.get("area") else ""
        return {"title": "కొత్త డిమాండ్ అవకాశం",
                "body": f"{n} మంది కస్టమర్లు{where_te} '{subject}' కోసం వెతికారు{band}. మీ ఆఫర్ జోడించండి."}
    return {"title": "New demand opportunity",
            "body": f"{n} customers searched for '{subject}'{where}{band}. Add or update your offer."}


def _expiry_hours() -> int:
    try:
        from app.services import platform_settings

        return int(platform_settings.get("demand.opportunity_expiry_hours"))
    except Exception:
        return 72


def send(container, repo, log: DemandAlertLog, opportunity: Dict[str, Any], rule: Dict[str, Any], *,
         rule_id: str, actor: str, dry_run: bool = False, at: Optional[datetime] = None) -> Dict[str, Any]:
    """Alert the eligible recipients (in-app; push only when configured)."""
    catalog = getattr(container, "product_catalog_repository", None)
    if catalog is None:
        return {"status": "unavailable", "sent": 0, "eligible": [], "excluded": []}
    if not _in_hours(rule.get("business_hours"), at):
        return {"status": "outside_business_hours", "sent": 0, "eligible": [], "excluded": []}
    plan = match_recipients(catalog, opportunity, rule, log)
    if dry_run:
        return {"status": "preview", "sent": 0, **plan}
    channels = list(rule.get("channels") or ["in_app"])
    sent = []
    for target in plan["eligible"]:
        alert_id = log.record(opportunity=opportunity, recipient=target["recipient"], rule_id=rule_id, actor=actor,
                              reasons=target["reasons"], score=target["score"], channel=",".join(channels),
                              status="sent", expiry_hours=_expiry_hours())
        if alert_id is None:
            continue
        sent.append(target["recipient"])
        if "push" in channels:
            try:
                from app.services.push_service import push_service

                text = alert_text(opportunity)
                push_service(container).notify_async(target["recipient"], title=text["title"], body=text["body"],
                                                     route="/notifications", event_key=f"demand:{alert_id}")
            except Exception:
                pass
        try:
            repo.record_event("seller_notified", category=opportunity.get("category") or "",
                              location=opportunity.get("area") or "",
                              detail={"opportunity": opportunity["key"], "rule": rule_id, "alert": alert_id})
        except Exception:
            pass
    return {"status": "sent" if sent else "no_eligible_recipients", "sent": len(sent), "recipients": sent, **plan}
