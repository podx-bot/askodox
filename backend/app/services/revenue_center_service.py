"""Revenue Center: one place for ALL ASKODOX revenue + the funnel behind it.

Sources: partner conversions (affiliate commissions), revenue entries
(subscription payments, lead/service fees, promotions/ads, transaction
fees, partner revenue, other) and subscription counts from the growth
tables (no payment gateway yet -> PENDING_PAYMENT is NOT revenue).

Revenue ("total ASKODOX revenue") = confirmed + paid commission + recorded
revenue entries. Pending commission is shown separately; rejected and
reversed are never counted.

"Why up / down" compares the period with the previous one of equal length
and only states what the recorded data shows. Each finding carries a level:
  CONFIRMED            arithmetic on recorded data, or a mechanical fact
                       (a partner was disabled / its integration errored
                       and it had no activity)
  POSSIBLE_CORRELATION two changes happened together; not proven cause
  INSUFFICIENT_EVIDENCE too few records to say anything
"""
from __future__ import annotations

import csv
import io
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional
from zoneinfo import ZoneInfo

from app.repositories.partner_revenue_repository import PartnerRevenueRepository

PERIODS = ("today", "7d", "30d", "month", "custom")
MIN_EVENTS = 20       # below this many funnel events a rate change is not evidence
MIN_ORDERS = 5        # below this many orders a conversion-rate change is not evidence
REVENUE_STATES = ("CONFIRMED", "PAID")


def period_bounds(period: str, *, tz: str = "Asia/Kolkata", start: str = "", end: str = "",
                  now: datetime | None = None) -> Dict[str, Any]:
    """[start, end) in UTC ISO for a period in the owner's time zone, plus
    the previous period of equal length."""
    zone = ZoneInfo(tz)
    local_now = (now or datetime.now(timezone.utc)).astimezone(zone)
    today = local_now.date()
    if period == "today":
        first, last = today, today
    elif period == "7d":
        first, last = today - timedelta(days=6), today
    elif period == "30d":
        first, last = today - timedelta(days=29), today
    elif period == "month":
        first, last = today.replace(day=1), today
    elif period == "custom":
        try:
            first, last = date.fromisoformat(start), date.fromisoformat(end)
        except ValueError as error:
            raise ValueError("custom period needs start and end as YYYY-MM-DD") from error
        if last < first:
            raise ValueError("end is before start")
        if (last - first).days > 366:
            raise ValueError("custom period is limited to one year")
    else:
        raise ValueError(f"period must be one of {', '.join(PERIODS)}")
    days = (last - first).days + 1

    def utc(d: date) -> str:
        return datetime.combine(d, time.min, zone).astimezone(timezone.utc).isoformat()

    prev_first = first - timedelta(days=days)
    return {
        "period": period, "tz": tz, "first_day": first.isoformat(), "last_day": last.isoformat(), "days": days,
        "start": utc(first), "end": utc(last + timedelta(days=1)),
        "previous": {"first_day": prev_first.isoformat(), "last_day": (first - timedelta(days=1)).isoformat(),
                     "start": utc(prev_first), "end": utc(first)},
    }


def _local_day(iso: str, zone: ZoneInfo) -> str:
    try:
        moment = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return str(iso)[:10]
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(zone).date().isoformat()


_PLURAL = {"search": "searches", "impression": "impressions", "card_view": "card_views", "click": "clicks",
           "partner_opened": "partner_opened", "lead": "leads", "error": "errors",
           "offer_impression": "offer_impressions", "offer_open": "offer_opens", "offer_claim": "offer_claims"}


def _pct(current: float, previous: float) -> Optional[float]:
    if previous == 0:
        return None if current == 0 else 100.0
    return round((current - previous) / previous * 100.0, 1)


def _rate(num: float, den: float) -> Optional[float]:
    return round(num / den * 100.0, 2) if den else None


class RevenueCenter:
    def __init__(self, repo: PartnerRevenueRepository, growth_repo: Any = None, benefits_repo: Any = None) -> None:
        self.repo = repo
        self.growth = growth_repo
        self.benefits = benefits_repo

    # ----------------------------------------------------------- summary --

    def _window(self, start: str, end: str, filters: Dict[str, str], first_day: str = "",
                last_day: str = "") -> Dict[str, Any]:
        partners = {p["id"]: p for p in self.repo.partners()}
        events = self.repo.events_between(start, end)
        if first_day and last_day:
            # Raw events older than the retention window live on as per-day
            # counts; they are merged in so totals and trends stay exact.
            for row in self.repo.rollups_between(first_day, last_day):
                events.append({"occurred_at": f"{row['day']}T12:00:00+05:30", "event": row["event"],
                               "partner_id": row["partner_id"] or None, "category": row["category"],
                               "location": row["location"], "language": row["language"],
                               "campaign": row["campaign"], "count": row["count"], "click_id": None,
                               "detail": {}})
        conversions = self.repo.conversions_between(start, end)
        entries = self.repo.entries_between(start, end)

        def keep(row: Dict[str, Any]) -> bool:
            for key in ("category", "location", "campaign", "language"):
                if filters.get(key) and str(row.get(key) or "").casefold() != filters[key].casefold():
                    return False
            if filters.get("partner"):
                slug = (partners.get(row.get("partner_id")) or {}).get("slug")
                if slug != filters["partner"]:
                    return False
            return True

        events = [e for e in events if keep(e)]
        conversions = [c for c in conversions if keep(c)]
        entries = [e for e in entries if keep(e)]
        rewards = {"claims": 0, "redemptions": 0, "askodox_cost": 0.0, "partner_cost": 0.0}
        if self.benefits is not None and not filters:
            for claim in self.benefits.claims_between(start, end):
                if start <= claim["created_at"] < end:
                    rewards["claims"] += 1
                if claim["status"] == "REDEEMED" and claim["redeemed_at"] and start <= claim["redeemed_at"] < end:
                    rewards["redemptions"] += 1
                    rewards["askodox_cost"] += float(claim["askodox_cost"] or 0)
                    rewards["partner_cost"] += float(claim["partner_cost"] or 0)
        return {"partners": partners, "events": events, "conversions": conversions, "entries": entries,
                "rewards": rewards}

    @staticmethod
    def _metrics(data: Dict[str, Any]) -> Dict[str, Any]:
        counts: Dict[str, int] = defaultdict(int)
        for event in data["events"]:
            counts[event["event"]] += event.get("count", 1)
        by_state: Dict[str, float] = defaultdict(float)
        orders = gmv = 0.0
        for conv in data["conversions"]:
            by_state[conv["status"]] += float(conv["commission"] or 0)
            if conv["status"] not in ("REJECTED",):
                orders += 1
                gmv += float(conv["order_value"] or 0)
        entries_total = sum(float(e["amount"]) for e in data["entries"])
        commission_revenue = by_state["CONFIRMED"] + by_state["PAID"]
        return {
            "searches": counts["search"], "impressions": counts["impression"], "card_views": counts["card_view"],
            "clicks": counts["click"], "partner_opened": counts["partner_opened"], "leads": counts["lead"],
            "errors": counts["error"],
            "ctr_pct": _rate(counts["click"], counts["impression"]),
            "orders": int(orders), "conversion_rate_pct": _rate(orders, counts["click"] or counts["partner_opened"]),
            "gmv": round(gmv, 2),
            "expected_commission": round(by_state["PENDING"] + by_state["CONFIRMED"] + by_state["PAID"], 2),
            "pending_commission": round(by_state["PENDING"], 2),
            "confirmed_commission": round(by_state["CONFIRMED"], 2),
            "paid_commission": round(by_state["PAID"], 2),
            "rejected_commission": round(by_state["REJECTED"], 2),
            "reversed_commission": round(by_state["REVERSED"], 2),
            "other_revenue": round(entries_total, 2),
            "total_revenue": round(commission_revenue + entries_total, 2),
            # Offers & rewards: what ASKODOX (and partners) paid out.
            "offer_impressions": counts["offer_impression"], "offer_opens": counts["offer_open"],
            "reward_claims": data["rewards"]["claims"], "reward_redemptions": data["rewards"]["redemptions"],
            "reward_cost_askodox": round(data["rewards"]["askodox_cost"], 2),
            "reward_cost_partner": round(data["rewards"]["partner_cost"], 2),
            "net_revenue": round(commission_revenue + entries_total - data["rewards"]["askodox_cost"], 2),
        }

    @staticmethod
    def _breakdowns(data: Dict[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
        partners = data["partners"]
        name = lambda pid: (partners.get(pid) or {}).get("name") or ("ASKODOX" if pid is None else f"#{pid}")

        def group(key_fn) -> List[Dict[str, Any]]:
            table: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
            for event in data["events"]:
                if event["event"] in ("impression", "click", "search", "lead"):
                    table[key_fn(event)][_PLURAL[event["event"]]] += event.get("count", 1)
            for conv in data["conversions"]:
                row = table[key_fn(conv)]
                if conv["status"] != "REJECTED":
                    row["orders"] += 1
                    row["gmv"] += float(conv["order_value"] or 0)
                if conv["status"] in REVENUE_STATES:
                    row["revenue"] += float(conv["commission"] or 0)
                if conv["status"] == "PENDING":
                    row["pending"] += float(conv["commission"] or 0)
            for entry in data["entries"]:
                table[key_fn(entry)]["revenue"] += float(entry["amount"])
            rows = [{"key": k or "(not set)", **{m: round(v, 2) for m, v in vals.items()}} for k, vals in table.items()]
            return sorted(rows, key=lambda r: (-r.get("revenue", 0), -r.get("clicks", 0), -r.get("searches", 0)))

        by_source: Dict[str, float] = defaultdict(float)
        for conv in data["conversions"]:
            if conv["status"] in REVENUE_STATES:
                by_source["affiliate_commission"] += float(conv["commission"] or 0)
        for entry in data["entries"]:
            by_source[entry["source"]] += float(entry["amount"])
        return {
            "source": [{"key": k, "revenue": round(v, 2)} for k, v in sorted(by_source.items(), key=lambda x: -x[1])],
            "partner": group(lambda r: name(r.get("partner_id")) if r.get("partner_id") is not None else "(none)"),
            "category": group(lambda r: str(r.get("category") or "")),
            "location": group(lambda r: str(r.get("location") or "")),
            "campaign": group(lambda r: str(r.get("campaign") or "")),
            "language": group(lambda r: str(r.get("language") or "")),
        }

    def _series(self, data: Dict[str, Any], bounds: Dict[str, Any]) -> List[Dict[str, Any]]:
        zone = ZoneInfo(bounds["tz"])
        first = date.fromisoformat(bounds["first_day"])
        days = {(first + timedelta(days=i)).isoformat(): defaultdict(float) for i in range(bounds["days"])}
        for event in data["events"]:
            day = days.get(_local_day(event["occurred_at"], zone))
            if day is not None:
                day[_PLURAL[event["event"]]] += event.get("count", 1)
        for conv in data["conversions"]:
            day = days.get(_local_day(conv["occurred_at"], zone))
            if day is None:
                continue
            if conv["status"] != "REJECTED":
                day["orders"] += 1
                day["gmv"] += float(conv["order_value"] or 0)
            day[f"commission_{conv['status'].lower()}"] += float(conv["commission"] or 0)
            if conv["status"] in REVENUE_STATES:
                day["revenue"] += float(conv["commission"] or 0)
        for entry in data["entries"]:
            day = days.get(_local_day(entry["occurred_at"], zone))
            if day is not None:
                day["revenue"] += float(entry["amount"])
        return [{"day": d, **{k: round(v, 2) for k, v in vals.items()}} for d, vals in days.items()]

    def subscriptions(self) -> Dict[str, Any]:
        if self.growth is None:
            return {"available": False}
        try:
            with self.growth._connect() as conn:
                rows = conn.execute("SELECT status, COUNT(*) AS n FROM growth_subscriptions GROUP BY status").fetchall()
        except Exception:
            return {"available": False}
        return {"available": True, "by_status": {r["status"]: r["n"] for r in rows},
                "note": "No payment gateway yet: PENDING_PAYMENT is not revenue. Record real subscription payments "
                        "as revenue entries (source 'subscription')."}

    def summary(self, bounds: Dict[str, Any], filters: Dict[str, str] | None = None) -> Dict[str, Any]:
        filters = {k: v for k, v in (filters or {}).items() if v}
        current = self._window(bounds["start"], bounds["end"], filters, bounds["first_day"], bounds["last_day"])
        previous = self._window(bounds["previous"]["start"], bounds["previous"]["end"], filters,
                            bounds["previous"]["first_day"], bounds["previous"]["last_day"])
        now_m, prev_m = self._metrics(current), self._metrics(previous)
        change = {k: _pct(float(now_m[k] or 0), float(prev_m[k] or 0)) for k in now_m
                  if isinstance(now_m[k], (int, float)) or now_m[k] is None}
        funnel = [{"stage": s, "count": now_m[k]} for s, k in (
            ("Searches", "searches"), ("Impressions", "impressions"), ("Card views", "card_views"),
            ("Clicks", "clicks"), ("Partner opened", "partner_opened"), ("Leads", "leads"), ("Orders", "orders"))]
        return {
            "period": bounds, "filters": filters, "metrics": now_m, "previous": prev_m, "change_pct": change,
            "series": self._series(current, bounds), "breakdowns": self._breakdowns(current), "funnel": funnel,
            "subscriptions": self.subscriptions(),
            "partners": [{"slug": p["slug"], "name": p["name"], "active": p["active"],
                          "level": p["capabilities"]["highest_level"], "last_check_ok": p["last_check_ok"],
                          "last_error": p["last_error"]} for p in current["partners"].values()],
            "measurement_notes": [
                "Leads, orders and commission exist only for partners with a postback or an imported report.",
                "Expected commission = pending + confirmed + paid; commission computed from a rule is marked "
                "commission_source='rule' in the records.",
                "Revenue = confirmed + paid commission + recorded revenue entries.",
            ],
        }

    # --------------------------------------------------------- why up/down --

    def explain(self, bounds: Dict[str, Any], filters: Dict[str, str] | None = None) -> Dict[str, Any]:
        filters = {k: v for k, v in (filters or {}).items() if v}
        cur = self._window(bounds["start"], bounds["end"], filters, bounds["first_day"], bounds["last_day"])
        prev = self._window(bounds["previous"]["start"], bounds["previous"]["end"], filters,
                            bounds["previous"]["first_day"], bounds["previous"]["last_day"])
        a, b = self._metrics(cur), self._metrics(prev)
        findings: List[Dict[str, Any]] = []

        def add(level: str, statement: str, data: Dict[str, Any]) -> None:
            findings.append({"level": level, "statement": statement, "data": data})

        facts = []
        for key in ("total_revenue", "searches", "impressions", "clicks", "ctr_pct", "orders",
                    "conversion_rate_pct", "gmv", "pending_commission", "reversed_commission", "errors"):
            facts.append({"metric": key, "current": a[key], "previous": b[key],
                          "change_pct": _pct(float(a[key] or 0), float(b[key] or 0))})
        revenue_delta = round(a["total_revenue"] - b["total_revenue"], 2)
        direction = "up" if revenue_delta > 0 else "down" if revenue_delta < 0 else "flat"
        volume = a["impressions"] + b["impressions"] + a["searches"] + b["searches"]
        if volume < MIN_EVENTS and a["orders"] + b["orders"] < MIN_ORDERS and not (a["total_revenue"] or b["total_revenue"]):
            add("INSUFFICIENT_EVIDENCE", "Too little recorded activity in these two periods to explain any change.",
                {"events_both_periods": volume, "orders_both_periods": a["orders"] + b["orders"],
                 "minimum_events": MIN_EVENTS})
            return {"period": bounds, "direction": direction, "revenue_delta": revenue_delta, "facts": facts,
                    "findings": findings, "method": _METHOD}

        # 1. Revenue change split by partner / category / source (exact arithmetic).
        if revenue_delta:
            for dim in ("partner", "category", "source"):
                now_rows = {r["key"]: r.get("revenue", 0) for r in self._breakdowns(cur)[dim]}
                old_rows = {r["key"]: r.get("revenue", 0) for r in self._breakdowns(prev)[dim]}
                deltas = sorted(((k, round(now_rows.get(k, 0) - old_rows.get(k, 0), 2))
                                 for k in set(now_rows) | set(old_rows)), key=lambda kv: -abs(kv[1]))
                top = [(k, d) for k, d in deltas if d][:3]
                if top:
                    share = abs(top[0][1]) / abs(revenue_delta) * 100
                    context = (f"{share:.0f}% of the {revenue_delta:+,.2f} total change" if share <= 100 else
                               f"larger than the {revenue_delta:+,.2f} total change -- other "
                               f"{ {'category': 'categories'}.get(dim, dim + 's') } moved the other way")
                    add("CONFIRMED", f"By {dim}: '{top[0][0]}' changed revenue by {top[0][1]:+,.2f} ({context}).",
                        {"dimension": dim, "top_changes": [{"key": k, "delta": d} for k, d in top]})
        # 2. Funnel stages (facts), with rate changes only when volume allows.
        for key, label in (("searches", "Searches"), ("impressions", "Partner impressions"), ("clicks", "Clicks")):
            change = _pct(a[key], b[key])
            if change is not None and abs(change) >= 10 and max(a[key], b[key]) >= MIN_EVENTS:
                add("CONFIRMED", f"{label} went {'down' if change < 0 else 'up'} {abs(change):g}% ({b[key]} -> {a[key]}).",
                    {"metric": key, "current": a[key], "previous": b[key]})
                if revenue_delta and (change < 0) == (revenue_delta < 0):
                    add("POSSIBLE_CORRELATION",
                        f"{label} and revenue moved in the same direction; fewer/more {label.lower()} may explain part "
                        "of the revenue change, but the data does not prove it.",
                        {"metric": key, "change_pct": change, "revenue_delta": revenue_delta})
        if a["impressions"] >= MIN_EVENTS and b["impressions"] >= MIN_EVENTS and a["ctr_pct"] is not None \
                and b["ctr_pct"] is not None and abs(a["ctr_pct"] - b["ctr_pct"]) >= 1:
            add("CONFIRMED", f"Click-through rate changed from {b['ctr_pct']}% to {a['ctr_pct']}%.",
                {"current": a["ctr_pct"], "previous": b["ctr_pct"], "impressions": [b["impressions"], a["impressions"]]})
        if a["orders"] + b["orders"] >= MIN_ORDERS and a["conversion_rate_pct"] is not None \
                and b["conversion_rate_pct"] is not None and a["conversion_rate_pct"] != b["conversion_rate_pct"]:
            add("CONFIRMED", f"Conversion rate (orders per click) changed from {b['conversion_rate_pct']}% to "
                             f"{a['conversion_rate_pct']}%.",
                {"orders": [b["orders"], a["orders"]], "clicks": [b["clicks"], a["clicks"]]})
        elif a["orders"] + b["orders"] and a["orders"] + b["orders"] < MIN_ORDERS:
            add("INSUFFICIENT_EVIDENCE", "Too few orders to judge a conversion-rate change.",
                {"orders": [b["orders"], a["orders"]], "minimum": MIN_ORDERS})
        # Offers & rewards cost (reduces net revenue).
        if a["reward_cost_askodox"] != b["reward_cost_askodox"]:
            add("CONFIRMED", f"ASKODOX-funded reward cost changed from {b['reward_cost_askodox']:,.2f} to "
                             f"{a['reward_cost_askodox']:,.2f} (net revenue {b['net_revenue']:,.2f} -> "
                             f"{a['net_revenue']:,.2f}).",
                {"reward_cost_askodox": [b["reward_cost_askodox"], a["reward_cost_askodox"]],
                 "redemptions": [b["reward_redemptions"], a["reward_redemptions"]]})
        # 3. Reversals / rejections.
        if a["reversed_commission"] > b["reversed_commission"]:
            add("CONFIRMED", f"Reversed commission rose from {b['reversed_commission']:,.2f} to "
                             f"{a['reversed_commission']:,.2f} (not counted as revenue).",
                {"current": a["reversed_commission"], "previous": b["reversed_commission"]})
        # 4. Category / location demand (searches), facts only.
        for dim in ("category", "location"):
            now_rows = {r["key"]: r.get("searches", 0) for r in self._breakdowns(cur)[dim]}
            old_rows = {r["key"]: r.get("searches", 0) for r in self._breakdowns(prev)[dim]}
            moves = sorted(((k, now_rows.get(k, 0) - old_rows.get(k, 0)) for k in set(now_rows) | set(old_rows)),
                           key=lambda kv: -abs(kv[1]))
            moves = [(k, int(d)) for k, d in moves if abs(d) >= 5][:3]
            if moves:
                add("CONFIRMED", f"Search demand by {dim}: " + ", ".join(f"'{k}' {d:+d}" for k, d in moves) + ".",
                    {"dimension": dim, "changes": [{"key": k, "searches_delta": d} for k, d in moves]})
        # 5. Partner integration state (mechanical facts first, coincidences second).
        prev_rev = {r["key"]: r for r in self._breakdowns(prev)["partner"]}
        now_rev = {r["key"]: r for r in self._breakdowns(cur)["partner"]}
        for partner in cur["partners"].values():
            before, after = prev_rev.get(partner["name"], {}), now_rev.get(partner["name"], {})
            errors = [e for e in cur["events"] if e["event"] == "error" and e["partner_id"] == partner["id"]
                      and not e.get("count")]
            if not partner["active"] and (before.get("impressions") or before.get("revenue")) and not after.get("impressions"):
                add("CONFIRMED", f"Partner '{partner['name']}' is disabled: it had {int(before.get('impressions', 0))} "
                                 f"impressions / {before.get('revenue', 0):,.2f} revenue before and none now.",
                    {"partner": partner["slug"], "previous": before, "current": after})
            elif errors:
                level = "CONFIRMED" if not after.get("impressions") and before.get("impressions") else "POSSIBLE_CORRELATION"
                add(level, f"Partner '{partner['name']}' recorded {len(errors)} integration error(s) this period"
                           + (" and showed no results." if level == "CONFIRMED" else "; this may relate to the change."),
                    {"partner": partner["slug"], "errors": len(errors),
                     "last_error": (errors[-1].get("detail") or {}).get("error"),
                     "impressions": [before.get("impressions", 0), after.get("impressions", 0)]})
            if partner["last_check_ok"] is False:
                add("CONFIRMED", f"Partner '{partner['name']}' failed its last integration check: {partner['last_error']}.",
                    {"partner": partner["slug"], "last_check_at": partner["last_check_at"]})
        if not findings:
            add("INSUFFICIENT_EVIDENCE", "No recorded metric moved enough to explain the change.",
                {"revenue_delta": revenue_delta})
        order = {"CONFIRMED": 0, "POSSIBLE_CORRELATION": 1, "INSUFFICIENT_EVIDENCE": 2}
        findings.sort(key=lambda f: order[f["level"]])
        return {"period": bounds, "direction": direction, "revenue_delta": revenue_delta, "facts": facts,
                "findings": findings, "method": _METHOD}

    # ------------------------------------------------------------- export --

    def export_csv(self, kind: str, bounds: Dict[str, Any], filters: Dict[str, str] | None = None) -> str:
        filters = {k: v for k, v in (filters or {}).items() if v}
        data = self._window(bounds["start"], bounds["end"], filters, bounds["first_day"], bounds["last_day"])
        rows: Iterable[Dict[str, Any]]
        if kind == "events":
            rows = [{k: v for k, v in e.items() if k != "detail"} for e in data["events"]]
        elif kind == "conversions":
            rows = [{k: v for k, v in c.items() if k != "raw"} for c in data["conversions"]]
        elif kind == "entries":
            rows = data["entries"]
        elif kind == "daily":
            rows = self._series(data, bounds)
        else:
            raise ValueError("kind must be events, conversions, entries or daily")
        rows = list(rows)
        out = io.StringIO()
        columns: List[str] = []
        for row in rows:
            columns += [c for c in row if c not in columns]
        writer = csv.DictWriter(out, fieldnames=columns or ["no_records"])
        writer.writeheader()
        writer.writerows(rows)
        return out.getvalue()

    def records(self, kind: str, bounds: Dict[str, Any], filters: Dict[str, str] | None = None,
                limit: int = 200) -> List[Dict[str, Any]]:
        filters = {k: v for k, v in (filters or {}).items() if v}
        data = self._window(bounds["start"], bounds["end"], filters, bounds["first_day"], bounds["last_day"])
        key = {"events": "events", "conversions": "conversions", "entries": "entries"}.get(kind)
        if key is None:
            raise ValueError("kind must be events, conversions or entries")
        return list(reversed(data[key]))[:limit]


_METHOD = ("Rule-based comparison of recorded telemetry with the previous period of equal length. "
           "CONFIRMED = arithmetic on recorded data or a mechanical fact; POSSIBLE_CORRELATION = changes that "
           "happened together without proof of cause; INSUFFICIENT_EVIDENCE = too few records. No cause is stated "
           "without the data shown next to it.")
