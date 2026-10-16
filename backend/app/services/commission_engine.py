"""Universal commission engine (Integration Platform, phase 3) on top of the
Partner Hub (partners + partner_conversions) -- one ledger, no second system.

Commission rule (partner.commission JSON; older {percent, flat, per_category}
rules keep working unchanged):
  model            cps | cpi | cpa | cpl | cpc | recurring | revenue_share | fixed | percentage
  percent          % of the order value (cps / revenue_share / percentage / recurring)
  flat             fixed amount per qualifying event (cpi / cpa / cpl / fixed)
  per_category     {category: percent}
  per_event        {install|lead|action|signup|sale|subscription|renewal: amount}
  attribution_days how long after the ASKODOX click a conversion may count (default 30)
  hold_days        approved -> payable waiting period (returns / partner validation; default 30)
  recurring_months how many renewals pay (recurring)

Truth rules
- A click is never a conversion (CPC amounts are reported as an EXPECTATION from
  clicks only when the partner contract pays per click).
- A conversion exists only when the partner confirms it (signed postback or
  report import); a rule-computed amount is stored as commission_source='rule'
  ("expected"), never as the partner-reported amount.
- Lifecycle: PENDING -> CONFIRMED (approved) -> PAYABLE -> PAID; REJECTED and
  REVERSED (refund / chargeback) are final; moves are forward-only.
- Duplicates are impossible per (partner, external id); fraud signals are
  flagged for review, never silently dropped.
"""
from __future__ import annotations

import csv
import io
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Optional

MODELS = ("cps", "cpi", "cpa", "cpl", "cpc", "recurring", "revenue_share", "fixed", "percentage")
EVENTS = ("sale", "install", "lead", "action", "signup", "subscription", "renewal")
PERCENT_MODELS = ("cps", "revenue_share", "percentage", "recurring")
FLAT_MODELS = ("cpi", "cpa", "cpl", "fixed")
TRANSITIONS = {
    "PENDING": ("CONFIRMED", "REJECTED"),
    "CONFIRMED": ("PAYABLE", "REJECTED", "REVERSED"),
    "PAYABLE": ("PAID", "REVERSED"),
    "PAID": ("REVERSED",),
    "REJECTED": (),
    "REVERSED": (),
}
RANK = {"PENDING": 0, "CONFIRMED": 1, "PAYABLE": 2, "PAID": 3}
DEFAULT_ATTRIBUTION_DAYS = 30
DEFAULT_HOLD_DAYS = 30
FAST_SECONDS = 10  # a conversion this soon after the click is suspicious


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(ts: Any) -> Optional[datetime]:
    try:
        value = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


# -------------------------------------------------------------- rules --
def validate_rule(rule: Dict[str, Any]) -> Dict[str, Any]:
    """Raises ValueError with a human message; returns the cleaned rule."""
    rule = dict(rule or {})
    model = str(rule.get("model") or "").strip().lower()
    if model and model not in MODELS:
        raise ValueError(f"commission.model must be one of {', '.join(MODELS)}")
    for key in ("percent", "flat"):
        if rule.get(key) not in (None, ""):
            try:
                value = float(rule[key])
            except (TypeError, ValueError):
                raise ValueError(f"commission.{key} must be a valid number") from None
            if value < 0 or (key == "percent" and value > 100):
                raise ValueError(f"commission.{key} must be a valid number")
    for key, low, high in (("attribution_days", 1, 365), ("hold_days", 0, 365), ("recurring_months", 1, 120)):
        if rule.get(key) not in (None, ""):
            try:
                value = int(rule[key])
            except (TypeError, ValueError):
                raise ValueError(f"commission.{key} must be a whole number") from None
            if not low <= value <= high:
                raise ValueError(f"commission.{key} must be between {low} and {high}")
    for event, amount in (rule.get("per_event") or {}).items():
        try:
            bad = event not in EVENTS or float(amount) < 0
        except (TypeError, ValueError):
            bad = True
        if bad:
            raise ValueError(f"commission.per_event: unknown event or invalid amount ({event})")
    if model:
        rule["model"] = model
    return rule


def expected(rule: Dict[str, Any], event: str, order_value: Optional[float], category: str = "") -> Optional[float]:
    """The amount the partner's rule PROMISES for one confirmed event (an
    expectation until the partner reports the amount)."""
    rule = rule or {}
    model = str(rule.get("model") or "").lower()
    if model == "cpc":
        return None  # clicks are never conversions
    per_event = rule.get("per_event") or {}
    if per_event.get(event) not in (None, ""):
        return round(float(per_event[event]), 2)
    rate = (rule.get("per_category") or {}).get(str(category or "").casefold(), rule.get("percent"))
    if model in FLAT_MODELS:
        return round(float(rule["flat"]), 2) if rule.get("flat") not in (None, "") else None
    if rate not in (None, "") and order_value is not None:
        return round(float(order_value) * float(rate) / 100.0, 2)
    if rule.get("flat") not in (None, "") and model not in PERCENT_MODELS:
        return round(float(rule["flat"]), 2)
    return None


def conversion_event(word: str) -> Optional[str]:
    word = str(word or "order").strip().casefold()
    return {"order": "sale", "sale": "sale", "purchase": "sale", "install": "install", "app_install": "install",
            "action": "action", "signup": "signup", "registration": "signup", "account_opened": "signup",
            "subscription": "subscription", "renewal": "renewal"}.get(word)


# -------------------------------------------------------------- flags --
def flags_for(partner: Dict[str, Any], *, context: Optional[Dict[str, Any]], click_id: str, event: str,
              occurred_at: Optional[str], repo: Any) -> List[str]:
    rule = partner.get("commission") or {}
    out: List[str] = []
    if not click_id:
        out.append("no_click_id")
    elif context is None:
        out.append("unknown_or_expired_click")
    else:
        clicked = _parse(context.get("occurred_at"))
        when = _parse(occurred_at) or _now()
        if clicked:
            if when - clicked > timedelta(days=int(rule.get("attribution_days") or DEFAULT_ATTRIBUTION_DAYS)):
                out.append("outside_attribution_window")
            if (when - clicked).total_seconds() < FAST_SECONDS:
                out.append("too_fast_after_click")
    if click_id and event in ("install", "signup"):
        with repo._connect() as conn:  # noqa: SLF001 -- same repository, read-only
            n = conn.execute("SELECT COUNT(*) FROM partner_conversions WHERE partner_id=? AND click_id=? AND "
                             "COALESCE(event,'sale')=?", (partner["id"], click_id, event)).fetchone()[0]
        if n:
            out.append("repeat_conversion_for_click")
    return out


# ---------------------------------------------------------- lifecycle --
def transition(repo: Any, conversion_id: int, to: str, *, actor: str, note: str = "") -> Dict[str, Any]:
    to = str(to or "").upper()
    with repo._connect() as conn:  # noqa: SLF001
        row = conn.execute("SELECT * FROM partner_conversions WHERE id=?", (conversion_id,)).fetchone()
        if row is None:
            raise KeyError(conversion_id)
        current = row["status"]
        if to not in TRANSITIONS.get(current, ()):
            raise ValueError(f"conversion {current} cannot become {to}")
        conn.execute("UPDATE partner_conversions SET status=?, state_changed_at=?, updated_at=? WHERE id=?",
                     (to, _now().isoformat(), _now().isoformat(), conversion_id))
    repo.add_conversion_event(conversion_id, current, to, actor, note)
    return repo.get_conversion(conversion_id)


def promote_payable(repo: Any, *, actor: str = "system", now: Optional[datetime] = None) -> Dict[str, Any]:
    """CONFIRMED conversions whose hold period ended become PAYABLE."""
    now = now or _now()
    moved = []
    partners = {p["id"]: p for p in repo.partners()}
    with repo._connect() as conn:  # noqa: SLF001
        rows = conn.execute("SELECT id, partner_id, COALESCE(state_changed_at, updated_at) AS since, flags_json "
                            "FROM partner_conversions WHERE status='CONFIRMED'").fetchall()
    for row in rows:
        rule = (partners.get(row["partner_id"]) or {}).get("commission") or {}
        since = _parse(row["since"])
        flagged = json.loads(row["flags_json"] or "[]")
        if since and not flagged and now - since >= timedelta(days=int(rule.get("hold_days", DEFAULT_HOLD_DAYS))):
            transition(repo, row["id"], "PAYABLE", actor=actor, note="hold period ended")
            moved.append(row["id"])
    return {"moved_to_payable": moved}


# ------------------------------------------------------ reconciliation --
def reconcile(repo: Any, partner: Dict[str, Any], csv_text: str) -> Dict[str, Any]:
    """Compare the partner's settlement statement with the ASKODOX ledger.
    READ-ONLY: it changes nothing (apply a statement with the report import)."""
    statement: Dict[str, Dict[str, Any]] = {}
    for row in csv.DictReader(io.StringIO(csv_text or "")):
        row = {str(k or "").strip().casefold(): str(v or "").strip() for k, v in row.items()}
        oid = row.get("order_id") or row.get("conversion_id") or row.get("transaction_id")
        if oid:
            statement[oid] = row
    with repo._connect() as conn:  # noqa: SLF001
        ours = {r["external_id"]: dict(r) for r in conn.execute(
            "SELECT * FROM partner_conversions WHERE partner_id=?", (partner["id"],))}
    from app.repositories.partner_revenue_repository import normalize_status

    matched, amount_mismatch, status_mismatch = [], [], []
    for oid, row in statement.items():
        mine = ours.get(oid)
        if mine is None:
            continue
        theirs_amount = row.get("commission") or row.get("payout")
        state = normalize_status(row.get("status") or mine["status"])
        if theirs_amount not in (None, "") and mine["commission"] is not None and \
                abs(float(theirs_amount) - float(mine["commission"])) > 0.01:
            amount_mismatch.append({"order_id": oid, "askodox": mine["commission"], "partner": float(theirs_amount)})
        elif state != mine["status"] and not (state == "CONFIRMED" and mine["status"] in ("PAYABLE", "PAID")):
            status_mismatch.append({"order_id": oid, "askodox": mine["status"], "partner": state})
        else:
            matched.append(oid)
    return {"matched": len(matched), "amount_mismatch": amount_mismatch, "status_mismatch": status_mismatch,
            "missing_in_askodox": sorted(set(statement) - set(ours)),
            "missing_in_statement": sorted(k for k, v in ours.items()
                                           if k not in statement and v["status"] not in ("REJECTED", "REVERSED")),
            "note": "Read-only comparison. Apply the partner's statement with Partners -> Import report."}


# ------------------------------------------------------------ summary --
def summary(repo: Any) -> Dict[str, Any]:
    partners = {p["id"]: p for p in repo.partners()}
    with repo._connect() as conn:  # noqa: SLF001
        rows = [dict(r) for r in conn.execute("SELECT * FROM partner_conversions")]
        clicks = conn.execute("SELECT partner_id, COUNT(*) AS n FROM revenue_events WHERE event='click' "
                              "GROUP BY partner_id").fetchall()
    by_state: Dict[str, Dict[str, float]] = {}
    by_partner: Dict[str, Dict[str, Any]] = {}
    flagged = []
    for r in rows:
        st = by_state.setdefault(r["status"], {"count": 0, "commission": 0.0, "expected_only": 0})
        st["count"] += 1
        st["commission"] = round(st["commission"] + float(r["commission"] or 0), 2)
        if r.get("commission_source") == "rule":
            st["expected_only"] += 1
        p = partners.get(r["partner_id"]) or {"name": f"partner {r['partner_id']}", "commission": {}}
        bp = by_partner.setdefault(p["name"], {"model": (p.get("commission") or {}).get("model") or "",
                                               "conversions": 0, "by_event": {}, "commission": 0.0})
        bp["conversions"] += 1
        ev = r.get("event") or "sale"
        bp["by_event"][ev] = bp["by_event"].get(ev, 0) + 1
        if r["status"] not in ("REJECTED", "REVERSED"):
            bp["commission"] = round(bp["commission"] + float(r["commission"] or 0), 2)
        flags = json.loads(r.get("flags_json") or "[]")
        if flags and r["status"] not in ("REJECTED", "REVERSED"):
            flagged.append({"id": r["id"], "partner": p["name"], "external_id": r["external_id"], "flags": flags,
                            "status": r["status"]})
    cpc = []
    for c in clicks:
        p = partners.get(c["partner_id"]) or {}
        rule = p.get("commission") or {}
        if str(rule.get("model") or "") == "cpc" and rule.get("flat") not in (None, ""):
            cpc.append({"partner": p.get("name"), "clicks": c["n"],
                        "expected_cpc_amount": round(c["n"] * float(rule["flat"]), 2),
                        "label": "EXPECTED from clicks -- confirmed only by the partner's statement"})
    return {"by_state": by_state, "by_partner": by_partner, "fraud_review": flagged, "cpc_expected": cpc,
            "lifecycle": ["PENDING", "CONFIRMED", "PAYABLE", "PAID"], "final_states": ["REJECTED", "REVERSED"]}


def as_rule_text(rule: Dict[str, Any]) -> str:
    return json.dumps(rule or {}, sort_keys=True)


__all__: Iterable[str] = ("MODELS", "EVENTS", "validate_rule", "expected", "conversion_event", "flags_for",
                          "transition", "promote_payable", "reconcile", "summary")
