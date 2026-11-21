"""Affiliate products, four steps (owner 2026-11-20): paste the commission link (never opened), add photos (+ review
screenshots), "fill from photos" writes the name / description from what the photos SHOW, staff type the price; the
video, the DM answers and the social captions make themselves.

* ``read_product_photos`` -- the product photos' own text and look -> title / description / colour / material / sizes.
  Never a price (staff type it), never a claim the photos do not show.
* ``faq_prompt`` / ``clean_faq`` -- ready answers for the questions buyers ask in DMs, ONLY from the item record and
  the read reviews; an unknown answer says so.
* ``share_texts`` -- Facebook / Instagram / YouTube captions with the ASKODOX product-page link and the affiliate
  disclosure (ASCI: "#Affiliate" up front). Instagram captions and YouTube Shorts descriptions do not make links
  clickable, so those point to the profile link (askodox.com/shop).
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

SHOP_URL = "https://askodox.com/shop"

PHOTO_PROMPT = (
    "You see photos of ONE product a shop sells (product photos, packaging, size chart, label; any language). Return "
    "ONLY JSON: {\"title\": string or null, \"category\": string or null, \"brand\": string or null, \"colour\": string "
    "or null, \"material\": string or null, \"sizes\": [string], \"features\": [string], \"description\": string or "
    "null}. Rules: write only what the photos clearly SHOW or what is printed on them; title = a plain shop title "
    "(e.g. 'Women Cotton Floral Nightdress'); features = at most 6 short visible facts (neck, sleeves, pattern, pack "
    "size ...); description = 2-4 plain English sentences built from those facts. NEVER a price, discount, rating, "
    "delivery, health or quality claim. null / [] when not visible.")


def _text(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit] if isinstance(value, (str, int, float)) else ""


def clean_photo_fields(payload: Any) -> Dict[str, Any]:
    if not isinstance(payload, dict):
        return {}
    out: Dict[str, Any] = {}
    for key, limit in (("title", 160), ("category", 80), ("brand", 80), ("colour", 60), ("material", 60)):
        value = _text(payload.get(key), limit)
        if value and value.lower() not in ("null", "none", "n/a", "unknown"):
            out[key] = value
    for key, limit, most in (("sizes", 20, 20), ("features", 80, 6)):
        items = payload.get(key)
        if isinstance(items, list):
            kept = [x for x in (_text(i, limit) for i in items) if x]
            if kept:
                out[key] = list(dict.fromkeys(kept))[:most]
    desc = _text(payload.get("description"), 900)
    if re.search(r"(₹|rs\.?\s*\d|\bprice\b|\boff\b|discount|best|guarantee)", desc, re.I):
        desc = ""  # a price / promise slipped in -- rebuild from the plain facts instead
    if not desc and (out.get("features") or out.get("colour") or out.get("material")):
        bits = [out.get("title") or "This product"]
        if out.get("colour") or out.get("material"):
            bits.append("in " + " ".join(x for x in (out.get("colour"), out.get("material")) if x))
        desc = " ".join(bits) + "." + (" " + ". ".join(out.get("features", [])) + "." if out.get("features") else "")
    if out.get("sizes"):
        desc = (desc + " Sizes: " + ", ".join(out["sizes"]) + ".").strip()
    if desc:
        out["description"] = desc[:1200]
    return out


def read_product_photos(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    photos = [(d, m) for d, m in list(images)[:4] if d]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return {"fields": {}, "read": False}
    try:
        payload, _calls = image_service.analyze_with_prompt(photos, PHOTO_PROMPT, max_models=2,
                                                            allow_second_provider=True)
    except Exception:
        return {"fields": {}, "read": False}
    fields = clean_photo_fields(payload)
    return {"fields": fields, "read": bool(fields.get("title") or fields.get("description"))}


# ----------------------------------------------------------------------- FAQ --

def faq_prompt(item: Dict[str, Any], reviews: Dict[str, Any], language: str = "te") -> str:
    lang = {"te": "Telugu", "hi": "Hindi", "en": "English"}.get(language, "Telugu")
    facts = {k: item.get(k) for k in ("title", "description", "price", "mrp", "brand", "category")
             if item.get(k) not in (None, "")}
    return (
        f"Buyers send DMs about this product. Write 6 likely questions and short answers in simple {lang} (English "
        "product words may stay). Return ONLY JSON: {\"faq\": [{\"q\": string, \"a\": string}]}. Answers ONLY from "
        "PRODUCT and REVIEWS below; when the answer is not there, the answer is that the buyer should check the size "
        "chart / details on the buy page. Never promise delivery dates, returns, cash on delivery, discounts or "
        "quality beyond REVIEWS; never a reviewer's name. Include: price, sizes / fit, material / colour, what buyers "
        "said, and how to buy (the link).\n"
        f"PRODUCT: {json.dumps(facts, ensure_ascii=False)}\nREVIEWS: {json.dumps(reviews or {}, ensure_ascii=False)}")


_PROMISE = re.compile(r"(cash on delivery|\bcod\b|free delivery|guarantee|warranty|return|refund|రిటర్న్|గ్యారంటీ)", re.I)


def clean_faq(raw: Any) -> List[Dict[str, str]]:
    items = raw.get("faq") if isinstance(raw, dict) else raw
    out: List[Dict[str, str]] = []
    for row in items if isinstance(items, list) else []:
        if not isinstance(row, dict):
            continue
        q, a = _text(row.get("q"), 160), _text(row.get("a"), 400)
        if q and a and not _PROMISE.search(a):
            out.append({"q": q, "a": a})
    return out[:8]


def write_faq(write: Any, item: Dict[str, Any], reviews: Dict[str, Any], language: str = "te") -> List[Dict[str, str]]:
    if write is None:
        return []
    try:
        text = write(faq_prompt(item, reviews, language)) or ""
        match = re.search(r"\{.*\}", text, re.DOTALL)
        return clean_faq(json.loads(match.group(0))) if match else []
    except Exception:
        return []


# -------------------------------------------------------------- share texts --

def _facts_line(item: Dict[str, Any]) -> List[str]:
    desc = re.sub(r"\s+", " ", str(item.get("description") or "")).strip()
    sentences = [s.strip() for s in re.split(r"(?<=[.!?।])\s+", desc) if 8 <= len(s.strip()) <= 140]
    return sentences[:3]


def _price(item: Dict[str, Any]) -> str:
    try:
        value = float(item.get("price"))
    except (TypeError, ValueError):
        return ""
    return f"₹{value:,.0f}" if value > 0 else ""


def _tags(item: Dict[str, Any], store: str) -> str:
    words = [w for w in re.findall(r"[A-Za-z]{4,}", str(item.get("title") or ""))][:4]
    tags = ["#Affiliate", "#ASKODOX", "#ASKODOXPicks"] + ([f"#{store}"] if store and store != "ASKODOX" else [])
    tags += [f"#{w.capitalize()}" for w in words]
    return " ".join(dict.fromkeys(tags))


def share_texts(item: Dict[str, Any], reviews: Dict[str, Any], store: str, page_url: str) -> Dict[str, Any]:
    """Ready-to-paste captions per platform. The disclosure (#Affiliate) is always first in the hashtags."""
    title = _text(item.get("title"), 90) or "ASKODOX Pick"
    price = _price(item)
    facts = _facts_line(item)
    rating = ""
    if reviews.get("rating"):
        n = reviews.get("ratings_count")
        rating = f"⭐ {store} రేటింగ్ {reviews['rating']}/5" + (f" ({n} మంది)" if n else "")
    body = [f"✨ {title}"] + [f"• {f}" for f in facts] + ([f"💰 ధర {price}"] if price else []) + ([rating] if rating else [])
    tags = _tags(item, store)
    disclosure = "Affiliate link: మీరు కొంటే మాకు కమీషన్ వస్తుంది, మీకు ధర మారదు."
    fb = "\n".join(body + ["", f"👉 ఇక్కడ చూడండి / కొనండి: {page_url}", "", disclosure, tags])
    ig = "\n".join(body + ["", f"👉 లింక్ మా ప్రొఫైల్ బయోలో ఉంది ({SHOP_URL})", "", disclosure, tags])
    yt_title = f"{title} | ASKODOX Picks #shorts"[:100]
    yt_desc = "\n".join(body + ["", f"👉 లింక్: ఛానెల్ ప్రొఫైల్‌లో ({SHOP_URL})", page_url, "", disclosure, tags])
    meesho = _is_meesho(store)
    if meesho:  # Studio spec: Meesho posts tag @meeshoapp
        fb, ig, yt_desc = (t.replace(tags, "@meeshoapp " + tags) for t in (fb, ig, yt_desc))
    wa = whatsapp_status([(title, price, page_url, meesho)])
    return {"facebook": {"text": fb}, "instagram": {"text": ig}, "youtube": {"title": yt_title, "text": yt_desc},
            "whatsapp": {"text": wa}, "link": page_url, "shop": SHOP_URL}


def _is_meesho(store: str) -> bool:
    return "meesho" in str(store or "").lower()


MEESHO_WA_NOTE = "(Meesho Share & Earn లింక్ ఇక్కడ పెట్టండి)"


def whatsapp_status(rows: List[Tuple[str, str, str, bool]]) -> str:
    """WhatsApp status text. Studio spec: a Meesho item never carries the affiliate / ASKODOX buy link on WhatsApp --
    staff paste Meesho's own Share & Earn link in its place."""
    lines = ["✨ ASKODOX Picks"]
    for k, (title, price, link, meesho) in enumerate(rows):
        head = f"{k + 1}. {title}" if len(rows) > 1 else title
        lines.append(head + (f" -- {price}" if price else ""))
        lines.append(f"👉 {MEESHO_WA_NOTE if meesho else link + '?from=wa'}")
    lines += ["", f"ఇంకా: {SHOP_URL}"]
    return "\n".join(lines)


def collection_share_texts(rows: List[Dict[str, Any]], theme: str) -> Dict[str, Any]:
    """Captions for a collection video. rows = [{"item": {...}, "store": str, "page": url}] in video order."""
    theme = _text(theme, 40) or "TOP FINDS"
    listed, tags, any_meesho, wa_rows = [], ["#Affiliate", "#ASKODOX", "#ASKODOXPicks"], False, []
    for k, row in enumerate(rows):
        item, store, page = row["item"], row.get("store") or "ASKODOX", row["page"]
        title, price = _text(item.get("title"), 70) or "ASKODOX Pick", _price(item)
        listed.append((k + 1, title, price, page))
        any_meesho = any_meesho or _is_meesho(store)
        wa_rows.append((title, price, page, _is_meesho(store)))
        if store and store != "ASKODOX":
            tags.append(f"#{store}")
    tag_line = ("@meeshoapp " if any_meesho else "") + " ".join(dict.fromkeys(tags))
    disclosure = "Affiliate links: మీరు కొంటే మాకు కమీషన్ వస్తుంది, మీకు ధర మారదు."
    head = f"✨ {theme} -- ASKODOX Picks"
    fb = "\n".join([head, ""] + [f"{n}. {t}" + (f" -- {p}" if p else "") + f"\n👉 {u}?from=fb" for n, t, p, u in listed]
                   + ["", disclosure, tag_line])
    ig = "\n".join([head, ""] + [f"{n}. {t}" + (f" -- {p}" if p else "") for n, t, p, _u in listed]
                   + ["", f"👉 లింక్‌లు మా ప్రొఫైల్ బయోలో ({SHOP_URL})", "", disclosure, tag_line])
    yt_title = f"{theme} | ASKODOX Picks #shorts"[:100]
    yt = "\n".join([head, ""] + [f"{n}. {t}" + (f" -- {p}" if p else "") + f"\n{u}?from=yt" for n, t, p, u in listed]
                   + ["", f"👉 అన్నీ: {SHOP_URL}", "", disclosure, tag_line])
    return {"facebook": {"text": fb}, "instagram": {"text": ig}, "youtube": {"title": yt_title, "text": yt},
            "whatsapp": {"text": whatsapp_status(wa_rows)}, "link": SHOP_URL, "shop": SHOP_URL}
