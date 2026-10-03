"""Revenue Command Center: one reconciled view over every revenue record
ASKODOX actually holds -- never estimated or invented.

Sources merged (each counted once):
* the platform ledger (pf_ledger): affiliate, sponsored, lead fees, merchant
  promotion fees, subscriptions, paid notifications (promotion campaigns),
  referral commissions, platform / service fees;
* Partner Hub conversions (token-verified postbacks / imported reports);
* Partner Hub revenue entries recorded by admins.

A Partner Hub conversion that the platform ledger already carries (same
conversion id) is shown once. Customer payments are merchant money (GMV),
not ASKODOX revenue, and are reported separately. Reward costs paid by
ASKODOX reduce net revenue.
"""
from __future__ import annotations

from collections import defaultdict
from typing import Any, Dict, List

STATES = ("expected", "pending", "confirmed", "paid", "refund", "rejected")
_LEDGER_STATE = {"EXPECTED": "expected", "PENDING": "pending", "CONFIRMED": "confirmed", "PAID": "paid",
                 "REVERSED": "refund", "REJECTED": "rejected"}
_CONV_STATE = {"PENDING": "pending", "CONFIRMED": "confirmed", "PAID": "paid", "REVERSED": "refund",
               "REJECTED": "rejected"}
_KIND_SOURCE = {"affiliate_commission": "affiliate", "sponsored_revenue": "sponsored", "lead_fee": "lead_fees",
                "merchant_promotion_fee": "merchant_promotions", "subscription_revenue": "subscriptions",
                "referral_commission": "referrals", "service_fee": "platform_fees",
                "premium_service": "platform_fees", "other": "other"}
SOURCES = ("subscriptions", "sponsored", "external_ads", "paid_notifications", "affiliate", "smart_links",
           "merchant_promotions", "lead_fees", "platform_fees", "offers", "video_affiliate", "creator_campaigns",
           "referrals", "other")


def _ledger_source(entry: Dict[str, Any]) -> str:
    kind = entry.get("kind") or "other"
    campaign = str(entry.get("campaign_id") or "")
    if kind == "campaign_revenue":
        return "paid_notifications" if campaign.startswith("prm") else "creator_campaigns" if campaign.startswith(
            "crt") else "sponsored"
    if kind == "affiliate_commission":
        ref = str(entry.get("source_ref") or "")
        return "video_affiliate" if ref.startswith(("vid", "yt_", "wv_")) else "smart_links" if ref.startswith(
            "lnk") else "affiliate"
    return _KIND_SOURCE.get(kind, "other")


def _entry_source(source: str) -> str:
    s = str(source or "other").lower()
    aliases = {"subscription": "subscriptions", "ads": "external_ads", "external_ad": "external_ads",
               "notification": "paid_notifications", "lead_fee": "lead_fees", "platform_fee": "platform_fees",
               "merchant_promotion": "merchant_promotions", "creator_campaign": "creator_campaigns"}
    s = aliases.get(s, s)
    return s if s in SOURCES else "other"


def rows(pf_repo: Any, partner_repo: Any, start: str, end: str) -> Dict[str, Any]:
    out: List[Dict[str, Any]] = []
    seen: set[str] = set()
    duplicates: List[Dict[str, Any]] = []
    for e in pf_repo.ledger(since=start, until=end):
        key = f"conv:{e['conversion_id']}" if e.get("conversion_id") else f"led:{e['id']}"
        seen.add(key)
        out.append({"source": _ledger_source(e), "state": _LEDGER_STATE.get(e["state"], "pending"),
                    "amount": float(e["amount"] or 0), "ref": e["id"], "at": e.get("occurred_at"),
                    "campaign": e.get("campaign_id"), "affiliate": e.get("partner_id"), "merchant": None,
                    "category": None, "location": None, "origin": "platform_ledger"})
    if partner_repo is not None:
        partners = {p["id"]: p for p in partner_repo.partners()}
        for c in partner_repo.conversions_between(start, end):
            key = f"conv:{c['external_id']}"
            if key in seen:
                duplicates.append({"conversion": c["external_id"], "kept": "platform_ledger"})
                continue
            seen.add(key)
            out.append({"source": "affiliate", "state": _CONV_STATE.get(c["status"], "pending"),
                        "amount": float(c.get("commission") or 0), "ref": f"pc:{c['id']}", "at": c["occurred_at"],
                        "campaign": c.get("campaign"), "affiliate": (partners.get(c["partner_id"]) or {}).get("slug"),
                        "merchant": None, "category": c.get("category"), "location": c.get("location"),
                        "origin": "partner_conversion", "gmv": float(c.get("order_value") or 0)})
        for r in partner_repo.entries_between(start, end):
            key = f"ent:{r.get('reference') or r['id']}"
            if r.get("reference") and key in seen:
                duplicates.append({"entry": r["reference"], "kept": "first"})
                continue
            seen.add(key)
            out.append({"source": _entry_source(r.get("source")), "state": "confirmed",
                        "amount": float(r["amount"] or 0), "ref": f"re:{r['id']}", "at": r["occurred_at"],
                        "campaign": r.get("campaign"), "affiliate": (partners.get(r.get("partner_id")) or {}).get(
                            "slug"), "merchant": None, "category": r.get("category"), "location": r.get("location"),
                        "origin": "revenue_entry"})
    return {"rows": out, "duplicates_skipped": duplicates}


def _totals(items: List[Dict[str, Any]]) -> Dict[str, float]:
    t = {s: 0.0 for s in STATES}
    for r in items:
        t[r["state"]] = t.get(r["state"], 0.0) + r["amount"]
    gross = t["confirmed"] + t["paid"]
    return {**{k: round(v, 2) for k, v in t.items()}, "gross": round(gross, 2),
            "expected_total": round(t["expected"] + t["pending"] + gross, 2)}


def summary(pf_repo: Any, partner_repo: Any, bounds: Dict[str, Any], *, reward_cost: float = 0.0,
            gmv_payments: float = 0.0) -> Dict[str, Any]:
    data = rows(pf_repo, partner_repo, bounds["start"], bounds["end"])
    items = data["rows"]
    totals = _totals(items)
    totals["reward_cost"] = round(reward_cost, 2)
    totals["net"] = round(totals["gross"] - totals["refund"] - reward_cost, 2)
    breakdowns: Dict[str, List[Dict[str, Any]]] = {}
    for dim in ("source", "campaign", "merchant", "affiliate", "category", "location"):
        groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        for r in items:
            if r.get(dim):
                groups[str(r[dim])].append(r)
        breakdowns[dim] = sorted(({"key": k, **_totals(v)} for k, v in groups.items()),
                                 key=lambda x: -x["gross"])[:25]
    by_source = {s: _totals([r for r in items if r["source"] == s]) for s in SOURCES}
    return {"period": bounds, "totals": totals, "by_source": by_source, "breakdowns": breakdowns,
            "records": len(items), "duplicates_skipped": data["duplicates_skipped"],
            "gmv_customer_payments": round(gmv_payments, 2),
            "notes": ["Only recorded revenue: ledger entries, verified partner conversions and admin-recorded "
                      "entries. Nothing is estimated.",
                      "Gross = confirmed + paid. Net = gross - refunds/reversals - ASKODOX-paid reward costs.",
                      "Expected / pending are not revenue until confirmed.",
                      "Customer payments to merchants are GMV, not ASKODOX revenue.",
                      "A conversion present in both the platform ledger and Partner Hub is counted once."]}
