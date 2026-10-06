"""Smart Entry -- PASTE / SHARE -> DETECT -> FETCH -> EXTRACT -> AUTO-FILL ->
VALIDATE -> REVIEW. One ingestion layer for every Command Center / Staff form
(offers, affiliate links, catalog products, sources, videos, sponsored
campaigns, merchant offers ...). It only PREPARES a form: nothing is saved or
published here.

Every extracted field carries
  value       -- what the page / text actually says
  confidence  -- high (the page's own structured metadata or an exact
                 pattern), medium (a pattern in visible text), low (inferred)
  provenance  -- where it came from (og:title, schema.org Product, page text,
                 url, ...)
High-confidence fields may pre-fill; medium / low ones are marked
``needs_review``. Nothing is ever invented: a field the input does not state
is simply absent.

Batches run with bounded concurrency; one failing URL never cancels the rest.
Identical inputs within a batch are processed once (idempotent).
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import re
from typing import Any, Callable, Dict, List, Optional
from urllib.parse import urlparse

from app.services import affiliate_catalog as ac

MAX_BATCH = 50
WORKERS = 4

# Which fields each target form understands (only these are returned).
TARGET_FIELDS: Dict[str, List[str]] = {
    "offer": ["title", "merchant", "discount_percent", "discount_amount", "min_spend", "max_benefit",
              "payment_eligibility", "coupon_code", "starts_on", "ends_on", "terms", "source_url"],
    "merchant_offer": ["title", "merchant", "discount_percent", "discount_amount", "min_spend", "max_benefit",
                       "coupon_code", "ends_on", "terms", "source_url"],
    "affiliate_link": ["title", "merchant", "network", "destination_url", "category", "image_url", "price",
                       "source_url"],
    "catalog": ["title", "brand", "category", "image_url", "price", "currency", "stock", "variant",
                "description", "source_url"],
    "source": ["name", "domain", "result_type", "source_url"],
    "video": ["title", "platform", "video_id", "channel", "source_url"],
    "sponsored": ["title", "advertiser", "destination_url", "image_url", "source_url"],
    "content": ["title", "description", "image_url", "published_on", "source_url"],
}

_NETWORKS = {"amzn.to": "Amazon Associates", "amazon.in": "Amazon Associates", "fkrt.it": "Flipkart Affiliate",
             "flipkart.com": "Flipkart Affiliate", "linksredirect.com": "Cuelinks", "earnkaro.com": "EarnKaro",
             "inrdeals": "INRDeals", "vcommission": "vCommission", "admitad": "Admitad"}
_VIDEO_HOSTS = ("youtube.com", "youtu.be", "instagram.com/reel", "facebook.com/watch", "fb.watch")
_MONTHS = "jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec"


def _f(value: Any, confidence: str, provenance: str) -> Dict[str, Any]:
    return {"value": value, "confidence": confidence, "provenance": provenance}


def _host(url: str) -> str:
    return (urlparse(url).hostname or "").lower().removeprefix("www.")


def detect(raw: str) -> Dict[str, str]:
    """What was pasted: url (product / offer / affiliate / video / website),
    pdf / image / feed links, or plain text."""
    text = (raw or "").strip()
    if not re.match(r"^https?://", text, re.IGNORECASE):
        return {"kind": "text"}
    url = text.split()[0]
    host, path = _host(url), urlparse(url).path.lower()
    if any(h in host + path for h in _VIDEO_HOSTS):
        return {"kind": "video", "url": url}
    if path.endswith(".pdf"):
        return {"kind": "pdf", "url": url}
    if re.search(r"\.(png|jpe?g|webp|gif)$", path):
        return {"kind": "image", "url": url}
    if path.endswith((".xml", ".csv", ".json")) or "feed" in path or "rss" in path:
        return {"kind": "feed", "url": url}
    if any(n in host or n in url for n in _NETWORKS) and (host in ("amzn.to", "fkrt.it") or "tag=" in url
                                                          or "affid=" in url or "linksredirect" in host):
        return {"kind": "affiliate", "url": url}
    if re.search(r"offer|coupon|deal|cashback|promo|sale|discount", path):
        return {"kind": "offer", "url": url}
    if re.search(r"/(dp|p|product|item|itm)/|/products?/", path):
        return {"kind": "product", "url": url}
    return {"kind": "website", "url": url}


def offer_fields(text: str, provenance: str = "page text") -> Dict[str, Dict[str, Any]]:
    """Benefit terms a page / message states in words (medium confidence:
    patterns in visible text -- staff confirm)."""
    t = " ".join(str(text or "").split())
    out: Dict[str, Dict[str, Any]] = {}

    def money(pattern: str) -> Optional[float]:
        m = re.search(pattern, t, re.IGNORECASE)
        if not m:
            return None
        try:
            return float(m.group(1).replace(",", ""))
        except ValueError:
            return None

    pct = re.search(r"(\d{1,2}(?:\.\d)?)\s*%\s*(?:off|discount|cashback|instant)", t, re.IGNORECASE)
    if pct:
        out["discount_percent"] = _f(float(pct.group(1)), "medium", provenance)
    flat = money(r"(?:flat|get)\s*(?:₹|rs\.?|inr)\s*([\d,]+)\s*(?:off|discount|cashback)")
    if flat is not None:
        out["discount_amount"] = _f(flat, "medium", provenance)
    mn = money(r"(?:min(?:imum)?\.?\s*(?:order|purchase|spend|transaction|bill)(?:\s*value)?\s*(?:of)?\s*)(?:₹|rs\.?|inr)\s*([\d,]+)")
    if mn is not None:
        out["min_spend"] = _f(mn, "medium", provenance)
    mx = money(r"(?:max(?:imum)?\.?\s*(?:discount|cashback|benefit|off)?\s*(?:of|up\s*to)?\s*|up\s*to\s*)(?:₹|rs\.?|inr)\s*([\d,]+)")
    if mx is not None:
        out["max_benefit"] = _f(mx, "medium", provenance)
    code = re.search(r"\b(?:use\s+)?(?:coupon|promo|code)\s*(?:code)?\s*[:\-]?\s*([A-Z0-9]{4,20})\b", t)
    if code and not code.group(1).isdigit():
        out["coupon_code"] = _f(code.group(1), "medium", provenance)
    cards = re.findall(r"\b(HDFC|ICICI|SBI|Axis|Kotak|IDFC|Yes Bank|RBL|AU|OneCard|Amex|American Express|"
                       r"Bank of Baroda|BOB|IndusInd|Federal)\b[^.]{0,30}?\b(credit|debit)\s*cards?", t, re.IGNORECASE)
    if cards:
        out["payment_eligibility"] = _f(sorted({f"{b} {k.lower()} card" for b, k in cards}), "medium", provenance)
    elif re.search(r"\bUPI\b", t):
        out["payment_eligibility"] = _f(["UPI"], "low", provenance)
    date = rf"(\d{{1,2}}(?:st|nd|rd|th)?\s+(?:{_MONTHS})[a-z]*\.?,?\s+\d{{4}}|\d{{1,2}}[/-]\d{{1,2}}[/-]\d{{2,4}})"
    end = re.search(rf"(?:valid\s*(?:till|until|upto|up to)|ends?\s*(?:on)?|expires?\s*(?:on)?|offer\s*period.*?to)\s*{date}",
                    t, re.IGNORECASE)
    if end:
        out["ends_on"] = _f(end.group(1), "medium", provenance)
    start = re.search(rf"(?:valid\s*from|starts?\s*(?:on)?|from)\s*{date}", t, re.IGNORECASE)
    if start:
        out["starts_on"] = _f(start.group(1), "medium", provenance)
    terms = re.search(r"((?:T&C|terms(?:\s*(?:and|&)\s*conditions)?)\s*[:\-]?\s*.{20,400}?)(?:$|\n)", t, re.IGNORECASE)
    if terms:
        out["terms"] = _f(terms.group(1)[:400], "low", provenance)
    return out


def _from_product_page(url: str, fetch: Optional[Callable[[str], str]]) -> Dict[str, Any]:
    meta = ac.extract_metadata(url, fetch=fetch)
    fields = meta.get("fields") or {}
    status_by_field = meta.get("field_status") or {}
    out: Dict[str, Dict[str, Any]] = {}

    def put(key: str, src: str, value: Any = None) -> None:
        v = fields.get(src) if value is None else value
        if v in (None, "", []):
            return
        state = str(status_by_field.get(src) or "")
        conf = "high" if state in ("found", "extracted", "verified") or src in ("title", "image_url") else "medium"
        out[key] = _f(v, conf, f"page metadata ({src})")

    put("title", "title")
    put("brand", "brand")
    put("category", "category")
    put("image_url", "image_url")
    put("price", "price")
    put("currency", "currency")
    put("description", "description")
    put("variant", "variant")
    if meta.get("suggested_stock"):
        out["stock"] = _f(meta["suggested_stock"], "medium", "page metadata (availability)")
    host = _host(url)
    out["merchant"] = _f(fields.get("source") or host, "high" if fields.get("source") else "medium", "url host")
    return {"status": meta.get("status", "ok"), "note": meta.get("note"), "fields": out,
            "page_text": " ".join(str(fields.get(k) or "") for k in ("title", "description"))}


def ingest(raw: str, target: str = "auto", *, fetch: Optional[Callable[[str], str]] = None) -> Dict[str, Any]:
    """One input -> a prepared form for ``target`` (or the best-fit target)."""
    found = detect(raw)
    kind = found["kind"]
    url = found.get("url")
    chosen = target if target in TARGET_FIELDS else {
        "affiliate": "affiliate_link", "offer": "offer", "product": "catalog", "video": "video",
        "feed": "source", "website": "source", "pdf": "content", "image": "catalog", "text": "offer",
    }[kind]
    fields: Dict[str, Dict[str, Any]] = {}
    status, note = "ok", None
    if url:
        fields["source_url"] = _f(url, "high", "pasted")
    if kind == "text":
        fields.update(offer_fields(raw, "pasted text"))
        title = raw.strip().splitlines()[0][:140]
        if title:
            fields.setdefault("title", _f(title, "low", "first line of pasted text"))
    elif kind == "video":
        vid = re.search(r"(?:v=|youtu\.be/|shorts/|reel/)([A-Za-z0-9_-]{6,})", url or "")
        fields["platform"] = _f("youtube" if "youtu" in url else _host(url).split(".")[0], "high", "url host")
        if vid:
            fields["video_id"] = _f(vid.group(1), "high", "url")
    elif kind in ("pdf", "image", "feed"):
        fields["name" if chosen == "source" else "title"] = _f(urlparse(url).path.rsplit("/", 1)[-1][:120],
                                                                "low", "file name in url")
        note = {"pdf": "Upload the PDF in the form to read its text; the link alone is not opened here.",
                "image": "The image is used as-is; its contents are not described automatically here.",
                "feed": "Add it as a Feed source to sync items on the background runner."}[kind]
    else:
        try:
            page = _from_product_page(url, fetch)
            fields.update(page["fields"])
            status, note = page["status"], page.get("note")
            if chosen in ("offer", "merchant_offer"):
                for k, v in offer_fields(page.get("page_text", ""), "page metadata text").items():
                    fields.setdefault(k, v)
        except Exception as error:  # one bad page never breaks the batch
            status, note = "unavailable", f"The page could not be read ({type(error).__name__}). Fill it by hand."
        host = _host(url)
        if kind == "affiliate" or chosen == "affiliate_link":
            net = next((v for k, v in _NETWORKS.items() if k in host or k in url), None)
            if net:
                fields["network"] = _f(net, "medium", "url host")
            fields.setdefault("destination_url", _f(url, "high", "pasted"))
        if chosen == "source":
            fields["domain"] = _f(host, "high", "url host")
            fields.setdefault("name", _f(host.split(".")[0].title(), "low", "url host"))
            fields["result_type"] = _f("product" if kind == "product" else "website", "low", "url pattern")
        if chosen == "sponsored":
            fields.setdefault("destination_url", _f(url, "high", "pasted"))
            if "merchant" in fields:
                fields["advertiser"] = fields.pop("merchant")
    allowed = set(TARGET_FIELDS[chosen])
    fields = {k: v for k, v in fields.items() if k in allowed}
    review = sorted(k for k, v in fields.items() if v["confidence"] != "high")
    missing = [k for k in TARGET_FIELDS[chosen] if k not in fields]
    return {"input": raw[:500], "kind": kind, "target": chosen, "status": status, "note": note,
            "fields": fields, "needs_review": review, "not_found": missing,
            "prefill": {k: v["value"] for k, v in fields.items() if v["confidence"] == "high"}}


def ingest_batch(inputs: List[str], target: str = "auto", *, fetch: Optional[Callable[[str], str]] = None,
                 workers: int = WORKERS) -> Dict[str, Any]:
    """Many inputs at once: bounded concurrency, de-duplicated, each isolated."""
    items = [i.strip() for i in inputs if str(i or "").strip()][:MAX_BATCH]
    unique: Dict[str, str] = {}
    for item in items:
        unique.setdefault(hashlib.sha256(item.encode()).hexdigest()[:16], item)
    results: Dict[str, Dict[str, Any]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(workers, 8))) as pool:
        futures = {pool.submit(ingest, raw, target, fetch=fetch): key for key, raw in unique.items()}
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            try:
                results[key] = future.result()
            except Exception as error:
                results[key] = {"input": unique[key][:500], "status": "failed",
                                "note": f"{type(error).__name__}", "fields": {}, "needs_review": [],
                                "not_found": [], "prefill": {}}
    ordered = [results[k] for k in unique]
    return {"items": ordered, "count": len(ordered), "duplicates_skipped": len(items) - len(unique),
            "failed": sum(1 for r in ordered if r.get("status") in ("failed", "unavailable")),
            "truncated": max(0, len([i for i in inputs if str(i or "").strip()]) - MAX_BATCH)}


# ---------------------------------------------------------------- templates --
# Built-in templates prefill STRUCTURE only: the target form, defaults that are
# true for every record of that kind (country, currency, platform, offer type
# ...) and the example input shown as a placeholder. They never carry a
# price, stock, rating, commission or any other fact about a real record.
# Each default is marked "template default" in the form so staff see where
# it came from.
def _t(tid: str, label: str, target: str, defaults: Dict[str, Any], example: str, hint: str) -> Dict[str, Any]:
    return {"id": tid, "label": label, "target": target, "defaults": defaults, "example": example, "hint": hint,
            "builtin": True}


TEMPLATES: List[Dict[str, Any]] = [
    _t("amazon", "Amazon product", "catalog", {"platform": "amazon", "currency": "INR", "availability": "All India"},
       "https://www.amazon.in/dp/…", "Paste the amazon.in product page; the affiliate link goes in its own field."),
    _t("flipkart", "Flipkart product", "catalog", {"platform": "flipkart", "currency": "INR",
                                                   "availability": "All India"},
       "https://www.flipkart.com/…/p/…", "Paste the flipkart.com product page."),
    _t("meesho", "Meesho product", "catalog", {"platform": "meesho", "currency": "INR", "availability": "All India"},
       "https://www.meesho.com/…/p/…", "Paste the meesho.com product page."),
    _t("generic_product", "Generic online product", "catalog", {"platform": "other", "currency": "INR"},
       "https://shop.example.in/products/…", "Any store's product page; check every fetched value."),
    _t("local_seller", "Local seller product", "catalog", {"platform": "other", "currency": "INR",
                                                           "availability": "Local pickup / delivery"},
       "Seller's product page or WhatsApp catalogue link",
       "Set the seller and location; registered app sellers add their own listings in the app."),
    _t("used_product", "Used product", "catalog", {"platform": "other", "currency": "INR", "category": "used",
                                                   "subcategory": "pre-owned"},
       "Listing page of the used item", "State the condition in the description; never assume it."),
    _t("service_provider", "Service provider", "catalog", {"platform": "other", "currency": "INR",
                                                           "category": "services"},
       "Provider's website / profile page", "Service area goes in Location."),
    _t("restaurant", "Restaurant", "catalog", {"platform": "other", "currency": "INR", "category": "food",
                                              "subcategory": "restaurant"},
       "Restaurant's menu / ordering page", "Prices only from the menu page."),
    _t("hotel", "Hotel", "catalog", {"platform": "other", "currency": "INR", "category": "travel",
                                    "subcategory": "hotel"},
       "Hotel booking page", "Room price only when the page states it for a date."),
    _t("ac_service", "AC service", "catalog", {"platform": "other", "currency": "INR", "category": "home_services",
                                              "subcategory": "ac service"},
       "AC service provider's page", "Visit / repair charges only as published."),
    _t("car_listing", "Car listing", "catalog", {"platform": "other", "currency": "INR", "category": "automobiles",
                                                "subcategory": "car"},
       "Car listing page", "Model, year and km go in the description as the page states them."),
    _t("insurance_lead", "Insurance lead program", "affiliate_link", {"link_type": "insurance", "country": "IN",
                                                                      "category": "insurance"},
       "https://partner.example.in/insurance?aff=…", "Choose the affiliate program; commission comes from it."),
    _t("loan_lead", "Loan lead program", "affiliate_link", {"link_type": "service", "country": "IN",
                                                            "category": "loans"},
       "https://partner.example.in/loans?aff=…", "Choose the affiliate program; no rate is shown unless verified."),
    _t("affiliate_link", "Affiliate link", "affiliate_link", {"link_type": "product", "country": "IN"},
       "https://amzn.to/…", "Tracking link + the program it belongs to."),
    _t("credit_card_offer", "Credit-card offer", "offer", {"offer_type": "bank_card"},
       "Bank's offer page or the offer text", "Needs the page where the bank publishes it."),
    _t("bank_offer", "Bank offer (debit / UPI)", "offer", {"offer_type": "upi_wallet"},
       "Bank / UPI app offer page", "Needs the page where the offer is published."),
    _t("coupon", "Coupon", "offer", {"offer_type": "coupon"},
       "Merchant coupon page or the coupon text", "The code exactly as published."),
    _t("sponsored", "Sponsored campaign", "sponsored", {"kind": "sponsored_listing", "language": "en", "format": "result_card"},
       "Advertiser landing page (https)", "Budgets and dates are entered by staff, never fetched."),
    _t("youtube_video", "YouTube video", "video", {"platform": "youtube"},
       "https://www.youtube.com/watch?v=…", "Title and type are confirmed by staff."),
    _t("creator_video", "Creator video", "video", {"platform": "creator", "video_type": "review"},
       "Creator's video link", "Link the creator record."),
    _t("news_source", "News source", "source", {"source_type": "news_content", "connector": "feed",
                                                "feed_format": "json", "countries": ["IN"]},
       "https://publisher.example.in/feed.json", "Approved feed only; items sync on the background runner."),
]

# Form field groups for progressive disclosure (keys = the smart-entry field
# names; forms map them onto their own inputs).
FIELD_GROUPS: Dict[str, Dict[str, List[str]]] = {
    "catalog": {"required": ["source_url", "title"], "recommended": ["price", "image_url", "brand", "category"]},
    "content": {"required": ["source_url", "title"], "recommended": ["description", "image_url"]},
    "affiliate_link": {"required": ["title", "destination_url"], "recommended": ["image_url", "category"]},
    "offer": {"required": ["title", "source_url"], "recommended": ["merchant", "discount_percent", "ends_on"]},
    "merchant_offer": {"required": ["title"], "recommended": ["merchant", "ends_on", "terms"]},
    "source": {"required": ["name"], "recommended": ["domain"]},
    "video": {"required": ["title", "source_url", "platform"], "recommended": []},
    "sponsored": {"required": ["title", "destination_url"], "recommended": ["image_url"]},
}

# Targets that bulk import can save as drafts / review items (the others need
# a person per record: offers need verification, campaigns need budgets).
IMPORTABLE = {"catalog", "content", "affiliate_link", "source", "video", "merchant_offer"}
PLATFORM_RESOURCE = {"affiliate_link": "affiliate_links", "source": "sources", "video": "videos",
                     "merchant_offer": "merchant_offers"}

VERDICTS = ("NEW", "UPDATE", "DUPLICATE", "INVALID", "NEEDS_REVIEW")


def to_record(target: str, fields: Dict[str, Any], defaults: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Prepared fields (value dicts or plain values) -> the target store's
    record shape. Only stated values are carried; defaults fill gaps only."""
    v = {k: (f.get("value") if isinstance(f, dict) and "value" in f else f) for k, f in (fields or {}).items()}
    v = {k: x for k, x in v.items() if x not in (None, "", [])}
    out: Dict[str, Any]
    if target in ("catalog", "content"):
        out = {"original_product_url": v.get("source_url"), "title": v.get("title"), "brand": v.get("brand"),
               "category": v.get("category"), "price": v.get("price"), "description": v.get("description"),
               "currency": v.get("currency"),
               "images": [v["image_url"]] if v.get("image_url") else None,
               "variants": [v["variant"]] if isinstance(v.get("variant"), str) else v.get("variant")}
    elif target == "affiliate_link":
        out = {"title": v.get("title"), "affiliate_url": v.get("destination_url") or v.get("source_url"),
               "original_url": v.get("source_url") if v.get("source_url") != v.get("destination_url") else None,
               "image_url": v.get("image_url"), "category": v.get("category")}
    elif target == "source":
        out = {"name": v.get("name"), "domains": [v["domain"]] if v.get("domain") else None}
    elif target == "video":
        out = {"title": v.get("title"), "platform": v.get("platform"), "url": v.get("source_url")}
    elif target == "merchant_offer":
        out = {"title": v.get("title"), "merchant_name": v.get("merchant"), "max_discount": v.get("max_benefit"),
               "min_bill": v.get("min_spend"), "terms": v.get("terms")}
    else:
        out = dict(v)
    out = {k: x for k, x in out.items() if x not in (None, "", [])}
    for k, x in (defaults or {}).items():
        if x not in (None, "", []) and k not in out:
            out[k] = x
    return out


def validate(target: str, fields: Dict[str, Dict[str, Any]]) -> List[str]:
    """Problems that make an item INVALID (missing required / malformed)."""
    errors: List[str] = []
    values = {k: (f or {}).get("value") for k, f in (fields or {}).items()}
    for key in FIELD_GROUPS.get(target, {}).get("required", []):
        if key == "platform":
            continue  # chosen in the form / by the template
        if values.get(key) in (None, "", []):
            errors.append(f"{key} missing")
    for key in ("source_url", "destination_url", "image_url"):
        url = values.get(key)
        if url and not re.match(r"^https://[^\s/$.?#][^\s]*$", str(url), re.IGNORECASE):
            errors.append(f"{key} must be an https link")
    price = values.get("price")
    if price not in (None, ""):
        try:
            if float(str(price).replace(",", "")) <= 0:
                errors.append("price must be above 0")
        except ValueError:
            errors.append("price is not a number")
    return errors


def _same(a: Any, b: Any) -> bool:
    try:
        return float(str(a).replace(",", "")) == float(str(b).replace(",", ""))
    except ValueError:
        return str(a).strip().lower() == str(b).strip().lower()


def verdict(item: Dict[str, Any], existing: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """NEW / UPDATE / DUPLICATE / INVALID / NEEDS_REVIEW for one prepared item.
    ``existing`` = the stored record with the same identity (or None); UPDATE
    lists the stated fields that differ from it."""
    errors = list(item.get("errors") or []) + validate(item.get("target") or "", item.get("fields") or {})
    item["errors"] = sorted(set(errors))
    if item.get("status") == "failed" or item["errors"]:
        item["verdict"] = "INVALID"
        return item
    if existing:
        stated = to_record(item.get("target") or "", item.get("fields") or {})
        changes = {k: {"from": existing.get(k), "to": val} for k, val in stated.items()
                   if k in existing and existing.get(k) not in (None, "") and not _same(existing.get(k), val)
                   and not isinstance(val, list)}
        item["existing"] = {"id": existing.get("id"), "title": existing.get("title") or existing.get("name")}
        item["changes"] = changes
        item["verdict"] = "UPDATE" if changes else "DUPLICATE"
        return item
    item["verdict"] = "NEEDS_REVIEW" if (item.get("needs_review") or item.get("status") == "unavailable") else "NEW"
    return item


_CSV_ALIASES = {"url": "source_url", "link": "source_url", "product_url": "source_url",
                "original_product_url": "source_url", "name": "title", "product_name": "title",
                "image": "image_url", "img": "image_url", "affiliate_url": "destination_url",
                "mrp": "list_price", "store": "merchant", "seller": "merchant"}


def parse_csv(text: str, target: str) -> List[Dict[str, Any]]:
    """CSV rows -> prepared items (values staff typed: provenance 'CSV column',
    high confidence; nothing is fetched). Unknown columns are reported."""
    import csv
    import io

    target = target if target in TARGET_FIELDS else "catalog"
    allowed = set(TARGET_FIELDS[target]) | {"name"}
    reader = csv.DictReader(io.StringIO((text or "").strip()))
    items: List[Dict[str, Any]] = []
    for line, row in enumerate(reader, start=2):
        if len(items) >= MAX_BATCH * 4:
            break
        fields: Dict[str, Dict[str, Any]] = {}
        unknown: List[str] = []
        for col, raw in (row or {}).items():
            if col is None:
                continue
            key = _CSV_ALIASES.get(col.strip().lower(), col.strip().lower())
            value = (raw or "").strip()
            if not value:
                continue
            if key not in allowed:
                unknown.append(col)
                continue
            if key == "price":
                try:
                    value = float(value.replace(",", "").replace("₹", ""))
                except ValueError:
                    pass  # validate() reports it
            fields[key] = _f(value, "high", f"CSV column '{col.strip()}'")
        if not fields:
            continue
        items.append({"input": f"CSV row {line}", "kind": "csv", "target": target, "status": "ok",
                      "note": ("Ignored columns: " + ", ".join(unknown)) if unknown else None,
                      "fields": fields, "needs_review": [], "not_found": [k for k in TARGET_FIELDS[target]
                                                                          if k not in fields],
                      "prefill": {k: v["value"] for k, v in fields.items()}})
    return items


def summarize(items: List[Dict[str, Any]]) -> Dict[str, int]:
    out = {v: 0 for v in VERDICTS}
    for item in items:
        if item.get("verdict") in out:
            out[item["verdict"]] += 1
    return out
