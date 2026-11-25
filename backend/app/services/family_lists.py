"""Family shopping list (owner 2026-11-25, "ఒక్క టచ్" buyer list): ONE shared list per home.

Anyone in the home adds what is needed ("2 kg sugar"), whoever is at the shop ticks it off, and the others see it at
once. People are added by their 10-digit number (the same number they sign in with); a number not on ASKODOX yet joins
the list by itself on the day it signs in. Every item can be edited, paused (kept but greyed: "not this week") or
deleted (standing UI rule 2026-11-17). Only members see a list. Pushes go to the OTHER members on add (one per item)
and when the whole list is done. Leaving / account deletion removes the person; the last person out deletes the list.
No money, no shop, no AI here -- "find nearby" in the app hands the open items to the chat.
"""
from __future__ import annotations

import hashlib
import re
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

MAX_ITEMS = 200
MAX_MEMBERS = 12
MAX_LISTS = 5

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS family_lists (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    # member = user id once known; phone_key = the 10 digits (an invited number not yet on ASKODOX has user_id '')
    "CREATE TABLE IF NOT EXISTS family_list_members (list_id TEXT NOT NULL, phone_key TEXT NOT NULL,"
    " user_id TEXT NOT NULL DEFAULT '', label TEXT NOT NULL DEFAULT '', added_by TEXT NOT NULL, added_at TEXT NOT NULL,"
    " PRIMARY KEY (list_id, phone_key))",
    "CREATE INDEX IF NOT EXISTS idx_family_members_user ON family_list_members(user_id)",
    "CREATE TABLE IF NOT EXISTS family_list_items (id TEXT PRIMARY KEY, list_id TEXT NOT NULL, text TEXT NOT NULL,"
    " qty TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'open', added_by TEXT NOT NULL,"
    " done_by TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_family_items_list ON family_list_items(list_id)",
]

STATES = ("open", "done", "paused")


class FamilyListError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


def phone_key(raw: Any) -> str:
    digits = re.sub(r"\D", "", str(raw or ""))
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    if len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    return digits if re.fullmatch(r"[6-9]\d{9}", digits) else ""


def phone_of_user(user_id: str) -> str:
    if not str(user_id or "").startswith("app-phone-"):
        return ""
    return phone_key(user_id[len("app-phone-"):])


def member_ref(list_id: str, key: str) -> str:
    """A member's handle in answers: never the number (other people see only the last 4 digits)."""
    return hashlib.sha256(f"{list_id}:{key}".encode()).hexdigest()[:12]


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class FamilyLists:
    def __init__(self, database_path: str, notify: Optional[Callable[[str, str, str, str, str], None]] = None):
        self.database_path = database_path
        self.notify = notify or (lambda user, title, body, route, key: None)
        with closing(self._connect()) as conn:
            for sql in SCHEMA:
                conn.execute(sql)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.database_path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    # ------------------------------------------------------------------ membership
    def _claim(self, conn: sqlite3.Connection, user: str) -> None:
        """A number invited before it signed in becomes this user the first time they open any list."""
        key = phone_of_user(user)
        if conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'auth_accounts'").fetchone():
            row = conn.execute("SELECT phone_key FROM auth_accounts WHERE user_id = ?", (user,)).fetchone()
            key = row["phone_key"] if row else key
        if key:
            conn.execute("UPDATE family_list_members SET user_id = ? WHERE phone_key = ? AND user_id = ''", (user, key))

    def _member(self, conn: sqlite3.Connection, list_id: str, user: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM family_list_members WHERE list_id = ? AND user_id = ?", (list_id, user)).fetchone()
        if row is None:
            raise FamilyListError(404, "list", "List not found.")
        return row

    def _others(self, conn: sqlite3.Connection, list_id: str, user: str) -> List[str]:
        return [r["user_id"] for r in conn.execute(
            "SELECT user_id FROM family_list_members WHERE list_id = ? AND user_id NOT IN ('', ?)", (list_id, user))]

    def _who(self, conn: sqlite3.Connection, list_id: str, user: str) -> str:
        row = conn.execute("SELECT label, phone_key FROM family_list_members WHERE list_id = ? AND user_id = ?",
                           (list_id, user)).fetchone()
        if row is None:
            return ""
        return row["label"] or f"••{row['phone_key'][-4:]}"

    # ------------------------------------------------------------------ reads
    def mine(self, user: str) -> Dict[str, Any]:
        """The caller's lists; a person with none gets one home list made for them (one tap, nothing to set up)."""
        with closing(self._connect()) as conn:
            self._claim(conn, user)
            ids = [r["list_id"] for r in conn.execute(
                "SELECT m.list_id FROM family_list_members m JOIN family_lists l ON l.id = m.list_id WHERE m.user_id = ?"
                " ORDER BY l.updated_at DESC", (user,))]
            if not ids:
                ids = [self._create(conn, user, "")]
            conn.commit()
            return {"lists": [self._list(conn, i, user) for i in ids]}

    def _list(self, conn: sqlite3.Connection, list_id: str, user: str) -> Dict[str, Any]:
        head = conn.execute("SELECT * FROM family_lists WHERE id = ?", (list_id,)).fetchone()
        members = []
        for m in conn.execute("SELECT * FROM family_list_members WHERE list_id = ? ORDER BY added_at", (list_id,)):
            members.append({"phone": f"••••••{m['phone_key'][-4:]}", "ref": member_ref(list_id, m["phone_key"]),
                            "label": m["label"], "me": m["user_id"] == user, "joined": bool(m["user_id"])})
        names = {m["user_id"]: (m["label"] or f"••{m['phone_key'][-4:]}") for m in conn.execute(
            "SELECT user_id, label, phone_key FROM family_list_members WHERE list_id = ?", (list_id,)) if m["user_id"]}
        items = []
        for r in conn.execute("SELECT * FROM family_list_items WHERE list_id = ? ORDER BY"
                              " CASE state WHEN 'open' THEN 0 WHEN 'paused' THEN 1 ELSE 2 END, created_at", (list_id,)):
            items.append({"id": r["id"], "text": r["text"], "qty": r["qty"], "state": r["state"],
                          "added_by": "me" if r["added_by"] == user else names.get(r["added_by"], ""),
                          "done_by": "" if not r["done_by"] else ("me" if r["done_by"] == user else names.get(r["done_by"], "")),
                          "updated_at": r["updated_at"]})
        return {"id": list_id, "name": head["name"] if head else "", "members": members, "items": items,
                "open": sum(1 for i in items if i["state"] == "open")}

    # ------------------------------------------------------------------ lists
    def _create(self, conn: sqlite3.Connection, user: str, name: str) -> str:
        list_id = "fam_" + uuid.uuid4().hex[:16]
        now = _now()
        conn.execute("INSERT INTO family_lists (id, name, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                     (list_id, _clean(name, 40), user, now, now))
        key = phone_of_user(user) or ("u" + uuid.uuid5(uuid.NAMESPACE_URL, user).hex[:9])
        conn.execute("INSERT INTO family_list_members (list_id, phone_key, user_id, added_by, added_at) VALUES (?, ?, ?, ?, ?)",
                     (list_id, key, user, user, now))
        return list_id

    def create(self, user: str, name: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._claim(conn, user)
            count = conn.execute("SELECT COUNT(*) FROM family_list_members WHERE user_id = ?", (user,)).fetchone()[0]
            if count >= MAX_LISTS:
                raise FamilyListError(409, "lists", f"At most {MAX_LISTS} lists.")
            list_id = self._create(conn, user, name)
            conn.commit()
            return self._list(conn, list_id, user)

    def rename(self, user: str, list_id: str, name: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            conn.execute("UPDATE family_lists SET name = ?, updated_at = ? WHERE id = ?", (_clean(name, 40), _now(), list_id))
            conn.commit()
            return self._list(conn, list_id, user)

    # ------------------------------------------------------------------ people
    def add_member(self, user: str, list_id: str, phone: Any, label: str) -> Dict[str, Any]:
        key = phone_key(phone)
        if not key:
            raise FamilyListError(400, "phone", "Give a 10-digit mobile number.")
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            n = conn.execute("SELECT COUNT(*) FROM family_list_members WHERE list_id = ?", (list_id,)).fetchone()[0]
            if n >= MAX_MEMBERS:
                raise FamilyListError(409, "members", f"At most {MAX_MEMBERS} people in one list.")
            exists = conn.execute("SELECT user_id FROM auth_accounts WHERE phone_key = ?", (key,)).fetchone() \
                if conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'auth_accounts'").fetchone() else None
            known = exists["user_id"] if exists else ""
            conn.execute("INSERT OR IGNORE INTO family_list_members (list_id, phone_key, user_id, label, added_by, added_at)"
                         " VALUES (?, ?, '', ?, ?, ?)", (list_id, key, _clean(label, 30), user, _now()))
            if exists:
                conn.execute("UPDATE family_list_members SET user_id = ? WHERE list_id = ? AND phone_key = ? AND user_id = ''",
                             (known, list_id, key))
            conn.commit()
            who = self._who(conn, list_id, user)
            joined = conn.execute("SELECT user_id FROM family_list_members WHERE list_id = ? AND phone_key = ?",
                                  (list_id, key)).fetchone()
            if joined and joined["user_id"] and joined["user_id"] != user:
                self.notify(joined["user_id"], "ఇంటి లిస్ట్‌లో మిమ్మల్ని చేర్చారు",
                            f"{who} షాపింగ్ లిస్ట్ పంచుకున్నారు", "/me/family-list", f"family_join:{list_id}")
            return self._list(conn, list_id, user)

    @staticmethod
    def _key_of(conn: sqlite3.Connection, list_id: str, ref: str) -> str:
        for r in conn.execute("SELECT phone_key FROM family_list_members WHERE list_id = ?", (list_id,)):
            if member_ref(list_id, r["phone_key"]) == ref:
                return r["phone_key"]
        raise FamilyListError(404, "member", "Person not found.")

    def update_member(self, user: str, list_id: str, ref: str, label: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            conn.execute("UPDATE family_list_members SET label = ? WHERE list_id = ? AND phone_key = ?",
                         (_clean(label, 30), list_id, self._key_of(conn, list_id, ref)))
            conn.commit()
            return self._list(conn, list_id, user)

    def remove_member(self, user: str, list_id: str, ref: str) -> Dict[str, Any]:
        """Anyone in the home may take a person out (a family list, not a shop); the last person out deletes it."""
        with closing(self._connect()) as conn:
            me = self._member(conn, list_id, user)
            key = self._key_of(conn, list_id, ref) if ref else me["phone_key"]
            conn.execute("DELETE FROM family_list_members WHERE list_id = ? AND phone_key = ?", (list_id, key))
            self._drop_if_empty(conn, list_id)
            conn.commit()
            gone = conn.execute("SELECT 1 FROM family_list_members WHERE list_id = ? AND user_id = ?", (list_id, user)).fetchone()
            return {"left": True} if gone is None else self._list(conn, list_id, user)

    @staticmethod
    def _drop_if_empty(conn: sqlite3.Connection, list_id: str) -> None:
        if conn.execute("SELECT 1 FROM family_list_members WHERE list_id = ? AND user_id != ''", (list_id,)).fetchone() is None:
            for table, col in (("family_list_items", "list_id"), ("family_list_members", "list_id"), ("family_lists", "id")):
                conn.execute(f"DELETE FROM {table} WHERE {col} = ?", (list_id,))

    def delete_user(self, user: str) -> None:
        """Account deletion: the person leaves every list; the items they added stay for the others."""
        with closing(self._connect()) as conn:
            ids = [r["list_id"] for r in conn.execute("SELECT list_id FROM family_list_members WHERE user_id = ?", (user,))]
            conn.execute("DELETE FROM family_list_members WHERE user_id = ?", (user,))
            for list_id in ids:
                self._drop_if_empty(conn, list_id)
            conn.commit()

    # ------------------------------------------------------------------ items
    def add_items(self, user: str, list_id: str, texts: List[str], qty: str = "") -> Dict[str, Any]:
        clean = [t for t in (_clean(x, 80) for x in texts) if t]
        if not clean:
            raise FamilyListError(400, "text", "Write what is needed.")
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            n = conn.execute("SELECT COUNT(*) FROM family_list_items WHERE list_id = ?", (list_id,)).fetchone()[0]
            if n + len(clean) > MAX_ITEMS:
                raise FamilyListError(409, "items", f"At most {MAX_ITEMS} items. Delete the bought ones first.")
            now = _now()
            for text in clean:
                conn.execute("INSERT INTO family_list_items (id, list_id, text, qty, added_by, created_at, updated_at)"
                             " VALUES (?, ?, ?, ?, ?, ?, ?)", ("fli_" + uuid.uuid4().hex[:16], list_id, text,
                                                              _clean(qty, 20) if len(clean) == 1 else "", user, now, now))
            conn.execute("UPDATE family_lists SET updated_at = ? WHERE id = ?", (now, list_id))
            conn.commit()
            who = self._who(conn, list_id, user)
            body = ", ".join(clean[:4]) + (f" +{len(clean) - 4}" if len(clean) > 4 else "")
            for other in self._others(conn, list_id, user):
                self.notify(other, f"{who} లిస్ట్‌లో చేర్చారు", body, "/me/family-list", f"family_add:{list_id}:{now}")
            return self._list(conn, list_id, user)

    def update_item(self, user: str, list_id: str, item_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            row = conn.execute("SELECT * FROM family_list_items WHERE id = ? AND list_id = ?", (item_id, list_id)).fetchone()
            if row is None:
                raise FamilyListError(404, "item", "Item not found.")
            sets: Dict[str, Any] = {}
            if "text" in data:
                text = _clean(data["text"], 80)
                if not text:
                    raise FamilyListError(400, "text", "Write what is needed.")
                sets["text"] = text
            if "qty" in data:
                sets["qty"] = _clean(data["qty"], 20)
            if "state" in data:
                state = str(data["state"])
                if state not in STATES:
                    raise FamilyListError(400, "state", "Unknown state.")
                sets["state"] = state
                sets["done_by"] = user if state == "done" else ""
            if not sets:
                return self._list(conn, list_id, user)
            now = _now()
            conn.execute(f"UPDATE family_list_items SET {', '.join(f'{k} = ?' for k in sets)}, updated_at = ? WHERE id = ?",
                         (*sets.values(), now, item_id))
            conn.execute("UPDATE family_lists SET updated_at = ? WHERE id = ?", (now, list_id))
            conn.commit()
            if sets.get("state") == "done" and row["state"] != "done":
                left = conn.execute("SELECT COUNT(*) FROM family_list_items WHERE list_id = ? AND state = 'open'",
                                    (list_id,)).fetchone()[0]
                if left == 0:
                    who = self._who(conn, list_id, user)
                    for other in self._others(conn, list_id, user):
                        self.notify(other, "లిస్ట్ మొత్తం అయిపోయింది ✓", f"{who} అన్నీ కొన్నారు", "/me/family-list",
                                    f"family_done:{list_id}:{now[:13]}")
            return self._list(conn, list_id, user)

    def delete_item(self, user: str, list_id: str, item_id: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            conn.execute("DELETE FROM family_list_items WHERE id = ? AND list_id = ?", (item_id, list_id))
            conn.commit()
            return self._list(conn, list_id, user)

    def clear_done(self, user: str, list_id: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            self._member(conn, list_id, user)
            conn.execute("DELETE FROM family_list_items WHERE list_id = ? AND state = 'done'", (list_id,))
            conn.commit()
            return self._list(conn, list_id, user)
