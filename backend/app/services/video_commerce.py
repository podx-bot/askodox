"""Registered ASKODOX video commerce: grounded answers about a video, seller
AI-reply controls, comment moderation and demand signals.

Every answer says WHERE it comes from:
  seen_in_video   -- shown in the video (study fact basis "shown")
  said_by_seller  -- said in the video by the seller (basis "said")
  listing         -- the seller's approved listing / FAQ
  askodox         -- ASKODOX's own derived note (distance, comparison)
  unknown         -- not established anywhere -> "not confirmed", never guessed
Sensitive topics (payment / refund disputes, legal, medical / safety claims,
custom price negotiation, private details) are NEVER answered by AI; they go
to the seller.
"""
from __future__ import annotations

import re
from collections import Counter
from typing import Any, Dict, Iterable, List, Optional

from app.services.video_study import BASIS_CLAIM, BASIS_CONFIRMED

AI_MODES = ("off", "draft", "auto")

_SENSITIVE = re.compile(
    r"\b(refund|chargeback|dispute|scam|fraud|cheat|legal|lawyer|court|police|complaint|"
    r"medical|medicine|doctor|safe for (kids|children|pregnan)|side effect|injur|allerg|"
    r"discount|negotiat|lowest price|best price|last price|reduce|bargain|"
    r"phone number|whatsapp|address|otp|password|upi pin|bank)\b"
    r"|రీఫండ్|మోసం|ఫిర్యాదు|డిస్కౌంట్|తగ్గించ|ఫోన్ నంబర్|చిరునామా",
    re.IGNORECASE)

_STOP = {"the", "a", "an", "is", "it", "this", "that", "does", "do", "can", "you", "what", "how", "of", "in", "on",
         "for", "to", "and", "or", "with", "i", "me", "my", "are", "there", "any", "will", "be", "have", "has"}


def is_sensitive(text: str) -> bool:
    return bool(_SENSITIVE.search(str(text or "")))


def question_key(text: str) -> str:
    """A rough topic key for grouping customer questions (top questions)."""
    words = [w for w in re.findall(r"[^\W_]{3,}", str(text or "").lower()) if w not in _STOP]
    return " ".join(sorted(set(words))[:3]) or "other"


def _listing_answer(question: str, listing: Optional[Dict[str, Any]], faq: Dict[str, str]) -> Optional[Dict[str, Any]]:
    if not listing:
        return None
    q = question.lower()
    checks = [
        (r"price|cost|rate|ఎంత|ధర", "price", lambda l: f"₹{float(l['price']):,.0f}" if l.get("price") else None),
        (r"stock|available|availability|ఉందా|స్టాక్", "stock_status",
         lambda l: {"IN_STOCK": "In stock", "OUT_OF_STOCK": "Out of stock"}.get(str(l.get("stock_status") or ""), None)),
        (r"deliver|delivery|డెలివరీ", "delivery_available",
         lambda l: ("Delivery available" + (f" ({l['service_area']})" if l.get("service_area") else ""))
         if str(l.get("delivery_available")) in ("1", "True", "true") else
         ("Pickup only" if str(l.get("pickup_available")) in ("1", "True", "true") else None)),
        (r"where|location|shop|ఎక్కడ", "location_label", lambda l: l.get("location_label") or None),
        (r"brand|బ్రాండ్", "brand", lambda l: l.get("brand") or None),
    ]
    for pattern, key, fn in checks:
        if re.search(pattern, q):
            value = fn(listing)
            if value:
                return {"answer": f"{value} (from the seller's listing)", "basis": "listing", "fact_keys": [key]}
    for key, answer in faq.items():
        if any(w in q for w in re.findall(r"[a-z]{4,}", key.replace("_", " "))):
            return {"answer": f"{answer} (seller confirmed)", "basis": "listing", "fact_keys": [key]}
    return None


def _fact_match(question: str, study: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """The stored fact whose key / label / value shares the question's words."""
    asked = {w for w in re.findall(r"[^\W_]{3,}", str(question or "").lower()) if w not in _STOP}
    best, score = None, 0
    for fact in (study or {}).get("facts") or []:
        words = set(re.findall(r"[^\W_]{3,}", f"{fact.get('key', '').replace('_', ' ')} {fact.get('label', '')} "
                                                 f"{fact.get('value', '')}".lower()))
        hit = sum(1 for a in asked if any(w.startswith(a[:5]) or a.startswith(w[:5]) for w in words))
        if hit > score:
            best, score = fact, hit
    return best if score >= 1 else None


def ground_answer(question: str, *, study: Optional[Dict[str, Any]], study_answer: Optional[Dict[str, Any]],
                  listing: Optional[Dict[str, Any]] = None, faq: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """The one grounded answer for a question about a registered video."""
    if is_sensitive(question):
        return {"found": False, "basis": "unknown", "sensitive": True,
                "answer": "This needs the seller's own answer -- ASKODOX has passed your question to them."}
    if study_answer and study_answer.get("found"):
        keys = study_answer.get("fact_keys") or []
        facts = {f["key"]: f for f in (study or {}).get("facts") or []}
        bases = {facts[k]["basis"] for k in keys if k in facts}
        basis = "said_by_seller" if bases and BASIS_CONFIRMED not in bases else "seen_in_video"
        return {"found": True, "basis": basis if keys else "seen_in_video", "answer": study_answer.get("answer"),
                "fact_keys": keys, "timestamps": study_answer.get("timestamps") or []}
    fact = _fact_match(question, study)
    if fact:
        said = fact["basis"] == BASIS_CLAIM
        stamp = f" [{fact['timestamp']}]" if fact.get("timestamp") else ""
        return {"found": True, "basis": "said_by_seller" if said else "seen_in_video",
                "answer": f"{fact['label']}: {fact['value']}" + (" (the seller says)" if said else " (shown in the video)")
                          + stamp, "fact_keys": [fact["key"]],
                "timestamps": [fact["timestamp"]] if fact.get("timestamp") else []}
    listed = _listing_answer(question, listing, faq or {})
    if listed:
        return {"found": True, **listed, "timestamps": []}
    return {"found": False, "basis": "unknown",
            "answer": "Not confirmed in this video or the seller's listing. ASKODOX can ask the seller."}


def reply_plan(mode: str, paused: bool, grounded: Dict[str, Any]) -> str:
    """What happens to an AI answer: 'auto' publish, 'draft' for the seller,
    or 'seller' (no AI reply -- sensitive, unknown, AI off or paused)."""
    if paused or mode == "off" or not grounded.get("found") or grounded.get("sensitive"):
        return "seller"
    return "auto" if mode == "auto" else "draft"


_CONTACT = re.compile(r"(\+?\d[\d\s-]{8,}\d)|(https?://\S+)|(www\.\S+)|([\w.+-]+@[\w-]+\.[\w.]+)")


def moderate(text: str, prohibited: Iterable[str] = ()) -> Dict[str, Any]:
    """Comment moderation: contact / link leakage is masked; prohibited terms
    or obvious spam hide the comment for staff review."""
    from app.services.pii_mask import mask_sensitive

    clean = mask_sensitive(str(text or "").strip())
    low = clean.lower()
    hits = [t for t in prohibited if t and t.lower() in low]
    spam = len(set(low.split())) <= 2 and len(low) > 40 or bool(re.search(r"(.)\1{9,}", low))
    leak = bool(_CONTACT.search(str(text or "")))
    return {"text": clean, "status": "FLAGGED" if hits or spam else "VISIBLE",
            "reasons": (["prohibited:" + h for h in hits] + (["spam"] if spam else []) +
                        (["contact_masked"] if leak else []))}


def demand_summary(comments: List[Dict[str, Any]], events: List[Dict[str, Any]],
                   preorders: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Seller / admin demand signals -- counts and topics only, never who asked."""
    topics = Counter(question_key(c["text"]) for c in comments if c.get("kind") == "question")
    areas = Counter((e.get("area") or "").strip().title() for e in events if (e.get("area") or "").strip())
    counts = Counter(e.get("kind") for e in events)
    unanswered = sum(1 for c in comments if c.get("kind") == "question" and c.get("reply_status") in
                     ("waiting_seller", "draft_pending"))
    return {"views": counts.get("view", 0), "asks": counts.get("ask", 0), "shares": counts.get("share", 0),
            "questions": sum(1 for c in comments if c.get("kind") == "question"),
            "comments": sum(1 for c in comments if c.get("kind") == "comment"),
            "unanswered": unanswered,
            "ai_answered": sum(1 for c in comments if c.get("reply_status") == "ai_answered"),
            "top_questions": [{"topic": k, "count": v} for k, v in topics.most_common(5)],
            "demand_by_area": [{"area": k, "count": v} for k, v in areas.most_common(10)],
            "pre_orders": len(preorders),
            "pre_orders_accepted": sum(1 for p in preorders if p.get("status") == "ACCEPTED"),
            "requests": counts.get("request", 0)}


def suggestions_from_study(study: Dict[str, Any], taxonomy_resolve: Any = None) -> Dict[str, Any]:
    """Metadata ONLY from what the analysis established (never the old title)."""
    facts = study.get("facts") or []
    shown = [f for f in facts if f.get("basis") == BASIS_CONFIRMED]
    brand = next((f["value"] for f in facts if f.get("key") in ("brand", "make", "manufacturer")), None)
    subject = (study.get("subject") or "").strip()
    out: Dict[str, Any] = {
        "title": subject[:140] or None,
        "caption": (study.get("summary") or "").strip()[:600] or None,
        "brand": brand,
        "features": [f"{f['label']}: {f['value']}" for f in shown][:8],
        "tags": sorted({w for f in facts for w in re.findall(r"[^\W_]{3,}", f"{f.get('label', '')}".lower())
                        if w not in _STOP})[:12],
        "evidence": [{"key": f["key"], "timestamp": f.get("timestamp"), "evidence": f.get("evidence")}
                     for f in facts][:12],
        "not_established": study.get("missing") or [],
    }
    if taxonomy_resolve and subject:
        resolved = taxonomy_resolve(f"{subject} {study.get('category') or ''}")
        if resolved.get("matched"):
            out["category"] = resolved["path"][0]["key"]
            out["subcategory"] = resolved["key"] if len(resolved["path"]) > 1 else None
            out["category_path"] = [p["label"] for p in resolved["path"]]
    return {k: v for k, v in out.items() if v not in (None, [], "")}
