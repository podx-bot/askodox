"""Listing spam / abuse screening (rule-based, explainable).

Every self-service listing is checked before it becomes searchable:

* block   -- prohibited items (editable term list) or flooding (more new
             listings in an hour than ``listings.max_per_hour``): refused
             with the reason, nothing is saved.
* review  -- contact details or links inside the listing text (contact is
             shared only through request -> acceptance), or one contact
             number listing from several accounts within a day (many shops
             legitimately sell the same product, so the name alone is never
             a signal): saved
             HIDDEN and queued in Command Center -> Listing reviews.
* allow   -- everything else, searchable at once (as before).

Reasons are always recorded; nothing is decided silently.
"""
from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List

from app.services.pii_mask import EMAIL, PHONE

URL = re.compile(r"(https?://|www\.)\S+|\b[a-z0-9-]+\.(com|in|net|org|shop|store|xyz|link|me)\b", re.IGNORECASE)

# Seeded once into the editable `prohibited_terms` resource; staff change it.
DEFAULT_PROHIBITED = (
    "gun", "pistol", "revolver", "ammunition", "bullets", "explosive", "ganja", "marijuana", "cannabis", "heroin",
    "cocaine", "mdma", "charas", "brown sugar drug", "fake currency", "counterfeit", "fake notes", "human organ",
    "kidney for sale", "tiger skin", "ivory", "rhino horn", "wildlife skin", "aadhaar card for sale",
    "pan card for sale", "fake certificate", "fake degree", "escort", "betting tips", "matka",
)


def _norm(text: Any) -> str:
    return re.sub(r"[^a-z0-9ऀ-෿]+", " ", str(text or "").casefold()).strip()


def _contains_term(text: str, term: str) -> bool:
    term = _norm(term)
    return bool(term) and re.search(rf"(?<!\w){re.escape(term)}(?!\w)", text) is not None


def content_reasons(text: str, prohibited: Iterable[str] = DEFAULT_PROHIBITED) -> List[str]:
    """Why a piece of listing text cannot be saved (edits): a prohibited
    item, contact details or a link. Empty list = fine."""
    norm = _norm(text)
    reasons = [f"prohibited item: '{t}'" for t in prohibited if _contains_term(norm, t)][:1]
    if PHONE.search(text or "") or EMAIL.search(text or ""):
        reasons.append("contact details in the listing text (shared only after a request is accepted)")
    if URL.search(text or ""):
        reasons.append("a link in the listing text")
    return reasons


def check(db_path: str, seller: str, fields: Dict[str, Any], *, prohibited: Iterable[str] = DEFAULT_PROHIBITED,
          max_per_hour: int = 20, cross_seller_limit: int = 3) -> Dict[str, Any]:
    """Decision for one new listing: allow / review / block, with reasons."""
    text_fields = " ".join(str(fields.get(k) or "") for k in ("subject", "variant", "seller_name", "description"))
    norm = _norm(text_fields)
    reasons: List[str] = []
    for term in prohibited:
        if _contains_term(norm, term):
            return {"decision": "block", "reasons": [f"prohibited item: '{term}'"]}
    now = datetime.now(timezone.utc)
    try:
        with sqlite3.connect(db_path) as conn:
            recent = conn.execute(
                "SELECT COUNT(*) FROM seller_products WHERE seller_user_id=? AND created_at>=?",
                (seller, (now - timedelta(hours=1)).isoformat())).fetchone()[0]
            phone = re.sub(r"\D", "", str(fields.get("contact_phone") or ""))[-10:]
            others = conn.execute(
                "SELECT COUNT(DISTINCT seller_user_id) FROM seller_products WHERE seller_user_id<>? "
                "AND created_at>=? AND substr(replace(replace(replace(COALESCE(contact_phone,''),' ',''),'-',''),"
                "'+',''), -10)=?",
                (seller, (now - timedelta(days=1)).isoformat(), phone)).fetchone()[0] if len(phone) == 10 else 0
    except sqlite3.Error:
        recent, others = 0, 0
    if max_per_hour and recent >= max_per_hour:
        return {"decision": "block", "reasons": [f"too many new listings in an hour ({recent} >= {max_per_hour})"]}
    if PHONE.search(text_fields) or EMAIL.search(text_fields):
        reasons.append("contact details in the listing text (shared only after a request is accepted)")
    if URL.search(text_fields):
        reasons.append("a link in the listing text")
    if cross_seller_limit and others + 1 >= cross_seller_limit:
        reasons.append(f"the same contact number listed from {others + 1} accounts in a day")
    return {"decision": "review" if reasons else "allow", "reasons": reasons}


def prohibited_terms(repo) -> List[str]:
    """Editable list (Command Center -> Prohibited terms) or the defaults."""
    try:
        rows = repo.list("prohibited_terms", status="ACTIVE")
    except Exception:
        rows = []
    terms = [str((r.get("data") or {}).get("term") or "").strip() for r in rows]
    terms = [t for t in terms if t]
    return terms or list(DEFAULT_PROHIBITED)
