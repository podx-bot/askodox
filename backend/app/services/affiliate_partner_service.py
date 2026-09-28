"""Universal affiliate / partner adapter (any company -- nothing hard-coded).

Capability levels (what the admin configured decides what exists):
  1. link     deep-link template or base URL + tracking ID -> a tracked
              "search on <partner>" result; ASKODOX measures impression,
              in-app click and redirect (partner opened).
  2. feed     a product/feed API the partner gave the owner (generic JSON
              adapter with a field mapping) -> real product rows.
  3. postback the partner calls ASKODOX's postback URL -> leads, orders,
              order value, commission states.
  4. import   partner report CSV / manual reconciliation (always).

An affiliate link does NOT give access to a partner's product database or
customer care; level 2/3 exist only when the partner provides them.
Secrets (API keys, postback token) stay in the backend: they are used here
and never included in any result row or admin response.
"""
from __future__ import annotations

import csv
import hmac
import io
import secrets
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qsl, quote, quote_plus, urlencode, urlparse, urlunparse

import httpx

from app.repositories.partner_revenue_repository import (
    PartnerRevenueRepository,
    normalize_status,
)
from app.services import external_call_budget

DISCLOSURE = "Partner link -- ASKODOX may earn a commission. Price and stock are on the partner's site."


def new_click_id() -> str:
    return "ck" + secrets.token_hex(8)


def _https(url: str) -> Optional[str]:
    url = str(url or "").strip()
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        return None
    return url


def build_link(partner: Dict[str, Any], *, query: str = "", click_id: str = "", target_url: str = "",
               category: str = "") -> Optional[str]:
    """The tracked partner URL (https only), or None when not configured.

    Template placeholders: {query} (url-encoded), {query_raw}, {url} (a
    product URL, encoded), {tracking_id}, {sub_id} / {click_id}, {campaign},
    {category}. The sub-ID parameter (e.g. "subid", "ascsubtag") carries
    ASKODOX's click id so the partner's report / postback can be matched.
    """
    campaign = str((partner.get("campaign_params") or {}).get("campaign") or "askodox")
    values = {
        "query": quote_plus(query.strip()), "query_raw": quote(query.strip()),
        "url": quote(target_url, safe=""), "tracking_id": str(partner.get("tracking_id") or ""),
        "sub_id": click_id, "click_id": click_id, "campaign": campaign, "category": quote_plus(category),
    }

    def fill(text: str) -> str:
        for key, value in values.items():
            text = text.replace("{" + key + "}", value)
        return text

    template = str(partner.get("deep_link_template") or "").strip()
    if template and ("{url}" not in template or target_url):
        url = fill(template)
    elif target_url:
        url = target_url
    else:
        base = str(partner.get("base_url") or "").strip()
        if not base:
            return None
        url = fill(base)
    url = _https(url)
    if url is None:
        return None
    parsed = urlparse(url)
    params = dict(parse_qsl(parsed.query, keep_blank_values=True))
    sub_param = str(partner.get("sub_id_param") or "").strip()
    if sub_param and click_id and click_id not in parsed.query:
        params[sub_param] = click_id
    for key, value in (partner.get("campaign_params") or {}).items():
        if key != "campaign" and key not in params:
            params[str(key)] = fill(str(value))
    return urlunparse(parsed._replace(query=urlencode(params)))


def _matches(partner: Dict[str, Any], *, category: str, subject: str, country: str, location: str) -> bool:
    countries = [str(c).strip().upper() for c in partner.get("countries") or [] if str(c).strip()]
    if countries and "ALL" not in countries and country.upper() not in countries:
        return False
    locations = [str(c).strip().casefold() for c in partner.get("locations") or [] if str(c).strip()]
    if locations and location and not any(loc in location.casefold() for loc in locations):
        return False
    cats = [str(c).strip().casefold() for c in partner.get("categories") or [] if str(c).strip()]
    if not cats or "all" in cats:
        return True
    wanted = f"{category} {subject}".casefold()
    return any(cat in wanted or (category and category.casefold() in cat) for cat in cats)


def expected_commission(partner: Dict[str, Any], order_value: float | None, category: str = "") -> Optional[float]:
    """Commission from the admin's rule (an EXPECTATION, never confirmed)."""
    rule = partner.get("commission") or {}
    if order_value is None:
        return None
    rate = (rule.get("per_category") or {}).get(str(category or "").casefold(), rule.get("percent"))
    if rate not in (None, ""):
        return round(float(order_value) * float(rate) / 100.0, 2)
    if rule.get("flat") not in (None, ""):
        return round(float(rule["flat"]), 2)
    return None


class PartnerFeedError(RuntimeError):
    pass


def _dig(data: Any, path: str) -> Any:
    for part in [p for p in str(path or "").split(".") if p]:
        if isinstance(data, dict):
            data = data.get(part)
        elif isinstance(data, list) and part.isdigit() and int(part) < len(data):
            data = data[int(part)]
        else:
            return None
    return data


def fetch_feed(repo: PartnerRevenueRepository, partner: Dict[str, Any], query: str, *, limit: int = 3,
               client: httpx.Client | None = None) -> List[Dict[str, Any]]:
    """Generic JSON product feed: feed = {url (may contain {query}),
    items_path, title, item_url, price, image, currency, auth: header:<Name> |
    query:<param> | bearer}. The key comes from partner secrets."""
    feed = partner.get("feed") or {}
    url = _https(str(feed.get("url") or "").replace("{query}", quote_plus(query)))
    if url is None:
        raise PartnerFeedError("feed url must be https")
    headers: Dict[str, str] = {}
    params: Dict[str, str] = {}
    auth = str(feed.get("auth") or "")
    key = repo.secret(partner["id"], "feed_token") or repo.secret(partner["id"], "api_key")
    if auth and not key:
        raise PartnerFeedError("feed needs an API key (not set)")
    if auth == "bearer":
        headers["Authorization"] = f"Bearer {key}"
    elif auth.startswith("header:"):
        headers[auth.split(":", 1)[1]] = key
    elif auth.startswith("query:"):
        params[auth.split(":", 1)[1]] = key

    def call() -> list:
        try:
            if client is not None:
                response = client.get(url, headers=headers, params=params)
            else:
                with httpx.Client(timeout=6.0, follow_redirects=True) as own:
                    response = own.get(url, headers=headers, params=params)
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPError, ValueError) as error:
            raise PartnerFeedError(f"{type(error).__name__}: {str(error)[:160]}") from error
        items = _dig(data, str(feed.get("items_path") or ""))
        if not isinstance(items, list):
            raise PartnerFeedError("items_path did not point to a list")
        return items

    items = external_call_budget.cached_call(f"partner:{partner['slug']}", (query.casefold(),), call, ttl=900)
    rows = []
    for item in items:
        if not isinstance(item, dict):
            continue
        title = str(_dig(item, feed.get("title") or "title") or "").strip()
        link = _https(str(_dig(item, feed.get("item_url") or "url") or ""))
        if not title or not link:
            continue
        price = _dig(item, feed.get("price") or "price")
        try:
            price = float(price) if price not in (None, "") else None
        except (TypeError, ValueError):
            price = None
        rows.append({"title": title[:140], "url": link, "price": price,
                     "image": _https(str(_dig(item, feed.get("image") or "image") or "")),
                     "currency": str(_dig(item, feed.get("currency") or "currency") or "INR")})
        if len(rows) >= limit:
            break
    return rows


def partner_results(repo: PartnerRevenueRepository, demand: Dict[str, Any], *, country: str = "IN",
                    trace_key: str = "", feed_client: httpx.Client | None = None) -> tuple[list, list]:
    """Partner rows for a request + errors. Every row records an impression
    with its own click id (so a later click/postback maps back to the
    search's category/location/language)."""
    category = str(demand.get("domain") or "").strip()
    subject = str(demand.get("subject") or "").strip()
    location = str(demand.get("location_text") or "").strip()
    language = str(demand.get("language") or (demand.get("constraints") or {}).get("language") or "")
    rows: list[dict] = []
    errors: list[str] = []
    if not subject:
        return rows, errors
    for partner in repo.partners(active_only=True):
        if not _matches(partner, category=category, subject=subject, country=country, location=location):
            continue
        campaign = str((partner.get("campaign_params") or {}).get("campaign") or "askodox")
        found: list[dict] = []
        if partner["capabilities"]["level2_feed"]:
            try:
                for n, item in enumerate(fetch_feed(repo, partner, subject, client=feed_client)):
                    click_id = new_click_id()
                    link = build_link(partner, query=subject, click_id=click_id, target_url=item["url"],
                                      category=category)
                    if not link:
                        continue
                    found.append({
                        "id": f"partner-{partner['slug']}-{n}", "title": item["title"],
                        "subtitle": partner["name"], "price": item["price"],
                        "price_verified": item["price"] is not None, "image_url": item["image"] or partner.get("logo_url"),
                        "destination_url": link, "click_id": click_id,
                    })
            except PartnerFeedError as error:
                errors.append(f"partner:{partner['slug']}:feed")
                repo.record_event("error", partner_id=partner["id"], trace_key=trace_key, category=category,
                                  detail={"stage": "feed", "error": str(error)[:200]})
        if not found:
            click_id = new_click_id()
            link = build_link(partner, query=subject, click_id=click_id, category=category)
            if link:
                found.append({
                    "id": f"partner-{partner['slug']}", "title": f"{subject} on {partner['name']}",
                    "subtitle": "Search results on the partner's site", "price": None, "price_verified": False,
                    "image_url": partner.get("logo_url"), "destination_url": link, "click_id": click_id,
                })
            elif not partner["capabilities"]["level2_feed"]:
                errors.append(f"partner:{partner['slug']}:no_link")
        for item in found:
            repo.record_event("impression", partner_id=partner["id"], click_id=item["click_id"], trace_key=trace_key,
                              category=category, subject=subject, location=location, language=language,
                              campaign=campaign, detail={"url": item["destination_url"], "title": item["title"][:80]})
            rows.append({
                **item,
                "match_id": item["id"], "provider_id": f"partner:{partner['slug']}",
                "match_source": "online", "source": "online", "segment": "partner",
                "source_name": partner["name"], "affiliate": True, "disclosure": DISCLOSURE,
                "partner_slug": partner["slug"], "redirect_path": f"/go/{item['click_id']}",
                "score": 0.3, "demo": False,
            })
    return rows, errors


# --------------------------------------------------------------- admin --

REQUIRED_HELP = {
    "name": "Partner / company name as the owner wants it shown.",
    "signup_url": "Where the owner applies for the partner's affiliate program.",
    "tracking_id": "The owner's affiliate/tracking ID (partner dashboard -> account / link tools).",
    "deep_link_template": "A link that searches or opens the partner site with your tag, e.g. "
                          "https://partner.example/search?q={query}&tag={tracking_id}",
    "sub_id_param": "The partner's sub-ID / click-reference parameter name, so reports can be matched to ASKODOX clicks.",
    "commission": "Commission model (percent or flat, per category if different) -- only used for 'expected' amounts.",
}


def integration_test(repo: PartnerRevenueRepository, partner: Dict[str, Any], *,
                     feed_client: httpx.Client | None = None) -> Dict[str, Any]:
    """Check what works with the current config. Never calls a paid API
    more than once (feed test uses one query)."""
    report: Dict[str, Any] = {"checks": [], "missing": []}
    for field, help_text in REQUIRED_HELP.items():
        value = partner.get(field)
        if not value:
            report["missing"].append({"field": field, "why": help_text})
    sample = build_link(partner, query="test", click_id="ckTEST", category=(partner.get("categories") or [""])[0])
    report["checks"].append({"check": "tracked link", "ok": bool(sample), "value": sample or
                             "no https deep-link template or base URL"})
    if sample and partner.get("sub_id_param"):
        report["checks"].append({"check": "sub-ID carries the ASKODOX click id", "ok": "ckTEST" in sample})
    feed_ok = None
    if partner["capabilities"]["level2_feed"]:
        try:
            items = fetch_feed(repo, partner, "test", client=feed_client)
            feed_ok = True
            report["checks"].append({"check": "product feed", "ok": True, "value": f"{len(items)} item(s) parsed"})
        except PartnerFeedError as error:
            feed_ok = False
            report["checks"].append({"check": "product feed", "ok": False, "value": str(error)})
    report["checks"].append({
        "check": "conversion postback", "ok": partner["capabilities"]["level3_postback"],
        "value": "token set" if partner["capabilities"]["level3_postback"] else
        "not set up -- leads/orders/commission can only come from a report import",
    })
    ok = bool(sample) and feed_ok is not False
    if not ok:
        report["error"] = "tracked link missing" if not sample else "feed failed"
    repo.record_check(partner["id"], ok, report, synced=bool(feed_ok))
    return {"ok": ok, **report}


def handle_postback(repo: PartnerRevenueRepository, partner: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
    """A partner's conversion/lead callback. Token-verified; the click id
    maps it back to the ASKODOX search (category, location, language)."""
    expected = repo.secret(partner["id"], "postback_token")
    sent = str(params.get("token") or "")
    if not expected or not sent or not hmac.compare_digest(sent, expected):
        raise PermissionError("invalid postback token")
    click_id = str(params.get("click_id") or params.get("sub_id") or params.get("subid") or "").strip()[:40]
    context = repo.impression_context(click_id) if click_id else None
    attrs = {k: (context or {}).get(k) or "" for k in ("category", "location", "language", "campaign")}
    event = str(params.get("event") or "order").casefold()
    if event == "lead":
        repo.record_event("lead", partner_id=partner["id"], click_id=click_id or None, detail={"source": "postback"},
                          **attrs)
        return {"recorded": "lead", "matched_click": bool(context)}
    order_id = str(params.get("order_id") or params.get("transaction_id") or params.get("conversion_id") or "")

    def number(*keys: str) -> Optional[float]:
        for key in keys:
            if params.get(key) not in (None, ""):
                try:
                    return float(params[key])
                except (TypeError, ValueError):
                    raise ValueError(f"{key} must be a number")
        return None

    value = number("order_value", "amount", "sale_amount")
    commission = number("commission", "payout")
    source = "partner"
    if commission is None:
        commission, source = expected_commission(partner, value, attrs["category"]), "rule"
    conversion = repo.upsert_conversion(
        partner_id=partner["id"], external_id=order_id, source="postback", status=params.get("status") or "pending",
        click_id=click_id or None, order_value=value, commission=commission, commission_source=source,
        currency=str(params.get("currency") or "INR")[:3].upper(), raw={k: str(v)[:120] for k, v in params.items()
                                                                        if k != "token"}, **attrs,
    )
    return {"recorded": "order", "conversion_id": conversion["id"], "status": conversion["status"],
            "matched_click": bool(context)}


def _iso_date(value: Any) -> Optional[str]:
    text = str(value or "").strip()
    if not text:
        return None
    if len(text) == 10:
        return f"{text}T00:00:00+00:00"
    return text


def import_report(repo: PartnerRevenueRepository, partner: Dict[str, Any], csv_text: str) -> Dict[str, Any]:
    """Level 4: a partner report (CSV) -> conversions. Columns (any order,
    case-insensitive): order_id, click_id|sub_id, order_value, commission,
    status, date, currency."""
    reader = csv.DictReader(io.StringIO(csv_text.strip()))
    imported, errors = 0, []
    for line, raw in enumerate(reader, start=2):
        row = {str(k or "").strip().casefold(): str(v or "").strip() for k, v in raw.items()}
        try:
            def num(key: str) -> Optional[float]:
                return float(row[key].replace(",", "")) if row.get(key) else None

            click_id = row.get("click_id") or row.get("sub_id") or row.get("subid") or ""
            context = repo.impression_context(click_id) if click_id else None
            attrs = {k: (context or {}).get(k) or "" for k in ("category", "location", "language", "campaign")}
            value, commission = num("order_value"), num("commission")
            source = "partner"
            if commission is None:
                commission, source = expected_commission(partner, value, attrs["category"]), "rule"
            repo.upsert_conversion(
                partner_id=partner["id"], external_id=row.get("order_id") or "", source="import",
                status=row.get("status") or "pending", click_id=click_id or None, order_value=value,
                commission=commission, commission_source=source, currency=(row.get("currency") or "INR")[:3].upper(),
                occurred_at=_iso_date(row.get("date")), raw=row, **attrs,
            )
            imported += 1
        except ValueError as error:
            errors.append({"line": line, "error": str(error)[:160]})
    return {"imported": imported, "errors": errors}


__all__ = [
    "DISCLOSURE", "build_link", "expected_commission", "fetch_feed", "handle_postback", "import_report",
    "integration_test", "new_click_id", "normalize_status", "partner_results", "PartnerFeedError",
]
