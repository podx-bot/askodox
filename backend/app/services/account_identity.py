"""ONE account per phone number (Integration Platform, phase 5).

The app account id has always been "app-phone-<digits exactly as typed at
sign-in>", so the same person signing in once as 9876543210 and once as
+91 98765 43210 got TWO accounts (orders, profile, listings split). From now
on every verified sign-in is mapped through ``auth_accounts`` (keyed by the
last 10 digits): the first id ever issued for a number is reused forever.

For numbers that signed in before this table existed, an existing profile row
(``user_profiles``) with the same number is adopted, so nobody loses the
account they already use; only when nothing is known is a new id created
(the same "app-phone-<digits>" form as before). Nothing is merged or moved
automatically -- historical duplicates are reported for staff, never joined
silently.
"""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Any, Dict, List


def phone_key(value: str) -> str:
    """The account key of a number. Indian spellings (9876543210, 09876543210,
    919876543210, +91 98765 43210) share the 10-digit key; any other country's
    number keeps its full international digits, so two different countries'
    numbers that end in the same 10 digits never share an account."""
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    if len(digits) == 11 and digits.startswith("0"):
        return digits[1:]
    if len(digits) == 12 and digits.startswith("91"):
        return digits[2:]
    return digits


def same_number(a: str, b: str) -> bool:
    """Two phone-based app ids for the same 10-digit number."""
    a, b = str(a or ""), str(b or "")
    if not (a.startswith("app-phone-") and b.startswith("app-phone-")):
        return False
    ka, kb = phone_key(a), phone_key(b)
    return len(ka) >= 10 and ka == kb


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("CREATE TABLE IF NOT EXISTS auth_accounts (phone_key TEXT PRIMARY KEY, user_id TEXT NOT NULL, "
                 "created_at TEXT NOT NULL, last_sign_in_at TEXT NOT NULL, sign_ins INTEGER NOT NULL DEFAULT 0)")
    return conn


def resolve(db_path: str, mobile_digits: str) -> Dict[str, Any]:
    """The account id for a verified mobile number (creating the mapping once)."""
    key = phone_key(mobile_digits)
    now = datetime.now(timezone.utc).isoformat()
    with _connect(db_path) as conn:
        row = conn.execute("SELECT user_id FROM auth_accounts WHERE phone_key=?", (key,)).fetchone()
        if row:
            conn.execute("UPDATE auth_accounts SET last_sign_in_at=?, sign_ins=sign_ins+1 WHERE phone_key=?",
                         (now, key))
            return {"user_id": row["user_id"], "source": "existing_account"}
        user_id, source = f"app-phone-{mobile_digits}", "new_account"
        try:
            known = [r["user_id"] for r in conn.execute("SELECT user_id FROM user_profiles WHERE user_id LIKE ?",
                                                         (f"app-phone-%{key}",))]
        except sqlite3.Error:
            known = []
        known = [u for u in known if phone_key(u) == key]
        if known:
            user_id, source = sorted(known, key=len)[0], "adopted_profile"
        conn.execute("INSERT INTO auth_accounts(phone_key,user_id,created_at,last_sign_in_at,sign_ins) "
                     "VALUES(?,?,?,?,1)", (key, user_id, now, now))
    return {"user_id": user_id, "source": source}


def duplicate_profiles(db_path: str) -> List[Dict[str, Any]]:
    """Historical split accounts (same number, several ids) for staff review."""
    try:
        with _connect(db_path) as conn:
            ids = [r["user_id"] for r in conn.execute("SELECT user_id FROM user_profiles WHERE user_id LIKE "
                                                      "'app-phone-%'")]
    except sqlite3.Error:
        return []
    groups: Dict[str, List[str]] = {}
    for uid in ids:
        groups.setdefault(phone_key(uid), []).append(uid)
    return [{"phone_last4": k[-4:], "user_ids": v} for k, v in groups.items() if len(v) > 1]
