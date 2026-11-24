"""Owner 2026-11-24 ("must work for businesses with multiple branches"): an owner links his own shops into ONE group.
* Shared pool: the delivery people of every branch in the group can be asked / given a delivery job of any branch
  (`pos_delivery_jobs._people` reads `sibling_ids`); each stays a member of their own branch only.
* All-branches view: today's sales / orders / delivery jobs per branch + total, for the OWNER of all of them.
Each branch stays its own `pos_businesses` row (own bills, GST, stock); nothing is merged or copied."""
from __future__ import annotations

import re
import sqlite3
import uuid
from typing import Any, Dict, List

from app.services.pos_store import PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_branch_groups (id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL, name TEXT NOT NULL,"
    " created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_branch_members (business_id TEXT PRIMARY KEY, group_id TEXT NOT NULL)",
]


def sibling_ids(conn: sqlite3.Connection, business_id: str) -> List[str]:
    """The OTHER branches of the same group ([] when the shop is on its own or the tables do not exist yet)."""
    try:
        row = conn.execute("SELECT group_id FROM pos_branch_members WHERE business_id = ?", (business_id,)).fetchone()
        if row is None:
            return []
        return [r["business_id"] for r in conn.execute(
            "SELECT business_id FROM pos_branch_members WHERE group_id = ? AND business_id != ?", (row["group_id"], business_id))]
    except sqlite3.OperationalError:
        return []


class PosBranches:
    def __init__(self, store: Any) -> None:
        self.store = store
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _owned(self, conn: sqlite3.Connection, user: str, business_id: str) -> sqlite3.Row:
        row = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        if row is None or self.store.role_of(conn, business_id, user) != "owner":
            raise PosError(404, "business", "Business not found.")
        return row

    def save(self, user: str, name: str, business_ids: List[str]) -> Dict[str, Any]:
        """Link the owner's OWN shops (he must be the owner of every one). Saving again replaces the group."""
        ids = list(dict.fromkeys(str(b) for b in business_ids))
        if len(ids) < 2:
            raise PosError(400, "branches", "Choose at least two of your shops.")
        name = re.sub(r"\s+", " ", str(name or "")).strip()[:60] or "My branches"
        with self.store._tx() as conn:
            for b in ids:
                self._owned(conn, user, b)
            groups = {r["group_id"] for b in ids for r in conn.execute(
                "SELECT group_id FROM pos_branch_members WHERE business_id = ?", (b,))}
            gid = sorted(groups)[0] if groups else f"brg_{uuid.uuid4().hex[:12]}"
            for g in groups - {gid}:
                conn.execute("UPDATE pos_branch_members SET group_id = ? WHERE group_id = ?", (gid, g))
                conn.execute("DELETE FROM pos_branch_groups WHERE id = ?", (g,))
            if conn.execute("SELECT 1 FROM pos_branch_groups WHERE id = ?", (gid,)).fetchone():
                conn.execute("UPDATE pos_branch_groups SET name = ? WHERE id = ?", (name, gid))
            else:
                conn.execute("INSERT INTO pos_branch_groups (id, owner_user_id, name, created_at) VALUES (?,?,?,?)",
                             (gid, user, name, self.store.clock().isoformat()))
            for b in ids:
                conn.execute("INSERT OR REPLACE INTO pos_branch_members (business_id, group_id) VALUES (?,?)", (b, gid))
        return self.mine(user)

    def leave(self, user: str, business_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self._owned(conn, user, business_id)
            row = conn.execute("SELECT group_id FROM pos_branch_members WHERE business_id = ?", (business_id,)).fetchone()
            conn.execute("DELETE FROM pos_branch_members WHERE business_id = ?", (business_id,))
            if row and conn.execute("SELECT COUNT(*) AS n FROM pos_branch_members WHERE group_id = ?",
                                    (row["group_id"],)).fetchone()["n"] < 2:
                conn.execute("DELETE FROM pos_branch_members WHERE group_id = ?", (row["group_id"],))
                conn.execute("DELETE FROM pos_branch_groups WHERE id = ?", (row["group_id"],))
        return self.mine(user)

    def mine(self, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            groups = []
            for g in conn.execute("SELECT * FROM pos_branch_groups WHERE owner_user_id = ? ORDER BY created_at", (user,)):
                branches = [{"id": r["id"], "name": r["name"]} for r in conn.execute(
                    "SELECT b.id, b.name FROM pos_branch_members m JOIN pos_businesses b ON b.id = m.business_id WHERE"
                    " m.group_id = ? ORDER BY b.created_at", (g["id"],))]
                groups.append({"id": g["id"], "name": g["name"], "branches": branches})
            owned = [{"id": r["id"], "name": r["name"]} for r in conn.execute(
                "SELECT b.id, b.name FROM pos_members m JOIN pos_businesses b ON b.id = m.business_id WHERE m.role = 'owner'"
                " AND m.active = 1 AND (m.app_user_id = ?) ORDER BY b.created_at", (user,))]
        return {"groups": groups, "my_shops": owned}

    def overview(self, user: str, group_id: str, local_date: str) -> Dict[str, Any]:
        """Today in every branch + the total (only the owner of the group)."""
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", local_date or ""):
            raise PosError(400, "local_date", "local_date must be YYYY-MM-DD.")
        with self.store._connect() as conn:
            g = conn.execute("SELECT * FROM pos_branch_groups WHERE id = ? AND owner_user_id = ?", (group_id, user)).fetchone()
            if g is None:
                raise PosError(404, "group", "Group not found.")
            rows = []
            for b in conn.execute("SELECT b.id, b.name FROM pos_branch_members m JOIN pos_businesses b ON b.id ="
                                  " m.business_id WHERE m.group_id = ? ORDER BY b.created_at", (group_id,)):
                day = self.store._day(conn, b["id"], local_date)
                try:
                    jobs = conn.execute("SELECT COUNT(*) AS n FROM pos_dlv_jobs WHERE business_id = ? AND status = 'done'"
                                        " AND substr(done_at, 1, 10) >= ?", (b["id"], local_date)).fetchone()["n"]
                except sqlite3.OperationalError:
                    jobs = 0
                dues = conn.execute("SELECT COALESCE(SUM(bal), 0) AS n FROM (SELECT SUM(debit_paise - credit_paise) AS bal FROM"
                                    " pos_ledger WHERE business_id = ? AND customer_id IS NOT NULL GROUP BY customer_id"
                                    " HAVING bal > 0)", (b["id"],)).fetchone()["n"]
                rows.append({"id": b["id"], "name": b["name"], "invoices": day["invoices"], "sales_paise": day["sales_paise"],
                             "delivery_done": jobs, "dues_paise": int(dues or 0)})
        total = {k: sum(r[k] for r in rows) for k in ("invoices", "sales_paise", "delivery_done", "dues_paise")}
        return {"group": {"id": g["id"], "name": g["name"]}, "local_date": local_date, "branches": rows, "total": total}
