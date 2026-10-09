"""Conversation -> profile memory: what a person needs or offers, kept as
structured, private, user-controlled items on their ONE profile.

* Role and category come from the request the app already understood
  (side + need kind): buyer, seller, service_provider, service_taker
  (someone seeking a service or a job -- not a survey taker).
* The same need again UPDATES its item (history kept), never duplicates it.
* Statuses: active / updated / completed / cancelled / expired (expiry is
  computed on read from expires_at).
* Private by default; public only with the person's explicit consent, and a
  public view never carries contact details.
* Never stored: OTPs, passwords, PINs, CVVs, card / account / Aadhaar / PAN
  numbers (keys dropped, values masked); contacts are masked.
* The person can view, correct, delete (one or all) and disable it; every
  query is scoped to the signed-in user.
"""
from __future__ import annotations

import json
import re
import sqlite3
import time
from contextlib import closing
from typing import Any

from app.services.pii_mask import mask_sensitive

ROLES = ("buyer", "seller", "service_provider", "service_taker")
STATUSES = ("active", "updated", "completed", "cancelled", "expired")
USER_STATUSES = ("active", "completed", "cancelled")
EXPIRY_SECONDS = 30 * 24 * 3600
_SECRET_KEY = re.compile(r"otp|pass(word|code)?|\bpin\b|upi_?pin|cvv|cvc|card|account_?(no|number)|aadhaar|aadhar"
                         r"|\bpan\b|ifsc|secret|token|credential", re.IGNORECASE)
# Internal routing keys that are not the person's requirement.
_INTERNAL_KEYS = {"requested_groups", "wants_videos", "language", "category_detected", "subcategory_detected",
                  "channel", "radius_km", "searched", "said_subject"}


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS profile_memory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, role TEXT NOT NULL, kind TEXT NOT NULL,
        category TEXT, subject TEXT NOT NULL, canonical_key TEXT NOT NULL, details_json TEXT NOT NULL,
        status TEXT NOT NULL, visibility TEXT NOT NULL DEFAULT 'private', source_json TEXT,
        created_at REAL NOT NULL, updated_at REAL NOT NULL, expires_at REAL)""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_profile_memory_user ON profile_memory_items(user_id, status)")
    conn.execute("""CREATE TABLE IF NOT EXISTS profile_memory_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_id INTEGER NOT NULL, user_id TEXT NOT NULL, at REAL NOT NULL,
        action TEXT NOT NULL, change_json TEXT NOT NULL, source_json TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS profile_memory_settings (
        user_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL, updated_at REAL NOT NULL)""")
    return conn


def _clean(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k)[:40]: _clean(v) for k, v in list(value.items())[:30]
                if not _SECRET_KEY.search(str(k)) and v not in (None, "", [], {})}
    if isinstance(value, list):
        return [_clean(v) for v in value[:20]]
    if isinstance(value, str):
        return mask_sensitive(value)[:300]
    return value


def _key(role: str, subject: str) -> str:
    words = sorted({w.rstrip("s") for w in re.findall(r"\w+", subject.casefold()) if len(w) > 1})
    return f"{role}:{' '.join(words)}"


def role_of(demand: dict[str, Any]) -> str:
    """buyer / seller / service_provider / service_taker from the understood request."""
    from app.services.universal_multi_source_result_service import NEED_JOB, NEED_PRODUCT, need_kind

    kind = need_kind(demand)
    offer = str(demand.get("side") or "").upper() == "OFFER"
    if kind == NEED_JOB:
        return "service_taker"  # a job seeker
    if offer:
        return "seller" if kind == NEED_PRODUCT else "service_provider"
    return "buyer" if kind == NEED_PRODUCT else "service_taker"


def enabled(db_path: str, user_id: str) -> bool:
    with closing(_connect(db_path)) as conn:
        row = conn.execute("SELECT enabled FROM profile_memory_settings WHERE user_id=?", (user_id,)).fetchone()
    return True if row is None else bool(row["enabled"])


def set_enabled(db_path: str, user_id: str, on: bool) -> dict[str, Any]:
    with closing(_connect(db_path)) as conn:
        conn.execute("INSERT OR REPLACE INTO profile_memory_settings(user_id, enabled, updated_at) VALUES(?,?,?)",
                     (user_id, 1 if on else 0, time.time()))
        conn.commit()
    return {"enabled": on}


def _details(demand: dict[str, Any]) -> dict[str, Any]:
    constraints = {k: v for k, v in dict(demand.get("constraints") or {}).items() if k not in _INTERNAL_KEYS}
    return _clean({
        "quantity": demand.get("quantity"), "unit": demand.get("unit"), "budget": demand.get("price"),
        "when": demand.get("when_text"), "location": demand.get("location_text"), **constraints,
    })


def record_from_demand(db_path: str, user_id: str, demand: dict[str, Any], *, now: float | None = None
                       ) -> dict[str, Any] | None:
    """Remember (or update) what this person needs / offers. None when memory
    is off or the request has no subject."""
    subject = " ".join(str(demand.get("subject") or "").split())[:160]
    if not user_id or not subject or not enabled(db_path, user_id):
        return None
    now = now or time.time()
    role = role_of(demand)
    kind = "offer" if role in ("seller", "service_provider") or (
        role == "service_taker" and str(demand.get("side") or "").upper() == "OFFER") else "need"
    constraints = dict(demand.get("constraints") or {})
    category = str(constraints.get("category_detected") or demand.get("domain") or "").strip().lower()[:60]
    details = _details(demand)
    source = {"type": "conversation", "deal_id": demand.get("id"),
              "said": mask_sensitive(str(demand.get("said") or demand.get("raw_text") or ""))[:200]}
    key = _key(role, subject)
    with closing(_connect(db_path)) as conn:
        row = conn.execute(
            "SELECT * FROM profile_memory_items WHERE user_id=? AND canonical_key=? AND status IN ('active','updated') "
            "ORDER BY updated_at DESC LIMIT 1", (user_id, key)).fetchone()
        if row is not None:
            before = json.loads(row["details_json"] or "{}")
            merged = {**before, **details}
            change = {k: {"from": before.get(k), "to": v} for k, v in details.items() if before.get(k) != v}
            status = "updated" if change else row["status"]
            conn.execute("UPDATE profile_memory_items SET details_json=?, status=?, source_json=?, updated_at=?, "
                         "expires_at=? WHERE id=? AND user_id=?",
                         (json.dumps(merged), status, json.dumps(source), now, now + EXPIRY_SECONDS, row["id"], user_id))
            if change:
                conn.execute("INSERT INTO profile_memory_history(item_id, user_id, at, action, change_json, source_json) "
                             "VALUES(?,?,?,?,?,?)", (row["id"], user_id, now, "updated", json.dumps(change),
                                                     json.dumps(source)))
            conn.commit()
            return get(db_path, user_id, int(row["id"]), now=now)
        cur = conn.execute(
            "INSERT INTO profile_memory_items(user_id, role, kind, category, subject, canonical_key, details_json, "
            "status, visibility, source_json, created_at, updated_at, expires_at) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (user_id, role, kind, category, mask_sensitive(subject), key, json.dumps(details), "active", "private",
             json.dumps(source), now, now, now + EXPIRY_SECONDS))
        conn.execute("INSERT INTO profile_memory_history(item_id, user_id, at, action, change_json, source_json) "
                     "VALUES(?,?,?,?,?,?)", (cur.lastrowid, user_id, now, "created", json.dumps(details),
                                             json.dumps(source)))
        conn.commit()
        return get(db_path, user_id, int(cur.lastrowid), now=now)


def _view(row: sqlite3.Row, now: float) -> dict[str, Any]:
    status = row["status"]
    if status in ("active", "updated") and row["expires_at"] and row["expires_at"] < now:
        status = "expired"
    return {"id": row["id"], "role": row["role"], "kind": row["kind"], "category": row["category"],
            "subject": row["subject"], "details": json.loads(row["details_json"] or "{}"), "status": status,
            "visibility": row["visibility"], "source": json.loads(row["source_json"] or "{}"),
            "created_at": row["created_at"], "updated_at": row["updated_at"], "expires_at": row["expires_at"]}


def get(db_path: str, user_id: str, item_id: int, *, now: float | None = None) -> dict[str, Any] | None:
    with closing(_connect(db_path)) as conn:
        row = conn.execute("SELECT * FROM profile_memory_items WHERE id=? AND user_id=?", (item_id, user_id)).fetchone()
    return None if row is None else _view(row, now or time.time())


def items(db_path: str, user_id: str, *, now: float | None = None) -> list[dict[str, Any]]:
    now = now or time.time()
    with closing(_connect(db_path)) as conn:
        rows = conn.execute("SELECT * FROM profile_memory_items WHERE user_id=? ORDER BY updated_at DESC LIMIT 200",
                            (user_id,)).fetchall()
    return [_view(r, now) for r in rows]


def correct(db_path: str, user_id: str, item_id: int, *, subject: str | None = None,
            details: dict[str, Any] | None = None, status: str | None = None, visibility: str | None = None,
            consent: bool = False, now: float | None = None) -> dict[str, Any] | None:
    """The person's own correction. Public needs explicit consent."""
    now = now or time.time()
    current = get(db_path, user_id, item_id, now=now)
    if current is None:
        return None
    if status is not None and status not in USER_STATUSES:
        raise ValueError("status must be one of " + ", ".join(USER_STATUSES))
    if visibility is not None and visibility not in ("private", "public"):
        raise ValueError("visibility must be private or public")
    if visibility == "public" and not consent:
        raise PermissionError("publishing needs your explicit consent")
    change: dict[str, Any] = {}
    fields: dict[str, Any] = {}
    if subject is not None and subject.strip() and subject.strip() != current["subject"]:
        clean = mask_sensitive(" ".join(subject.split()))[:160]
        change["subject"] = {"from": current["subject"], "to": clean}
        fields["subject"] = clean
        fields["canonical_key"] = _key(current["role"], clean)
    if details is not None:
        clean = _clean(details)
        merged = {**current["details"], **clean}
        merged = {k: v for k, v in merged.items() if k in clean or k in current["details"]}
        diff = {k: {"from": current["details"].get(k), "to": v} for k, v in clean.items()
                if current["details"].get(k) != v}
        if diff:
            change["details"] = diff
            fields["details_json"] = json.dumps(merged)
    if status is not None and status != current["status"]:
        change["status"] = {"from": current["status"], "to": status}
        fields["status"] = status
        if status == "active":
            fields["expires_at"] = now + EXPIRY_SECONDS
    if visibility is not None and visibility != current["visibility"]:
        change["visibility"] = {"from": current["visibility"], "to": visibility}
        fields["visibility"] = visibility
    if not change:
        return current
    fields["updated_at"] = now
    sets = ", ".join(f"{k}=?" for k in fields)
    with closing(_connect(db_path)) as conn:
        conn.execute(f"UPDATE profile_memory_items SET {sets} WHERE id=? AND user_id=?",
                     [*fields.values(), item_id, user_id])
        conn.execute("INSERT INTO profile_memory_history(item_id, user_id, at, action, change_json, source_json) "
                     "VALUES(?,?,?,?,?,?)", (item_id, user_id, now, "corrected_by_user", json.dumps(change),
                                             json.dumps({"type": "user"})))
        conn.commit()
    return get(db_path, user_id, item_id, now=now)


def history(db_path: str, user_id: str, item_id: int) -> list[dict[str, Any]]:
    with closing(_connect(db_path)) as conn:
        rows = conn.execute("SELECT at, action, change_json, source_json FROM profile_memory_history "
                            "WHERE item_id=? AND user_id=? ORDER BY at, id", (item_id, user_id)).fetchall()
    return [{"at": r["at"], "action": r["action"], "change": json.loads(r["change_json"] or "{}"),
             "source": json.loads(r["source_json"] or "{}")} for r in rows]


def delete(db_path: str, user_id: str, item_id: int | None = None) -> int:
    """One item, or (item_id None) all of the person's memory."""
    with closing(_connect(db_path)) as conn:
        if item_id is None:
            conn.execute("DELETE FROM profile_memory_history WHERE user_id=?", (user_id,))
            n = conn.execute("DELETE FROM profile_memory_items WHERE user_id=?", (user_id,)).rowcount
        else:
            conn.execute("DELETE FROM profile_memory_history WHERE user_id=? AND item_id=?", (user_id, item_id))
            n = conn.execute("DELETE FROM profile_memory_items WHERE user_id=? AND id=?", (user_id, item_id)).rowcount
        conn.commit()
    return n


def public_view(item: dict[str, Any]) -> dict[str, Any]:
    """What others may see of a PUBLIC item: never contacts or the source."""
    return {"role": item["role"], "kind": item["kind"], "category": item["category"], "subject": item["subject"],
            "details": {k: v for k, v in item["details"].items() if k in ("quantity", "unit", "budget", "when",
                                                                        "location")}}
