"""Table watch (owner 2026-11-27, phase 5): who is sitting, for how long, and which table nobody has gone to yet.

QR ONLY -- no camera. The signal is the table's own QR: a customer opening the menu from it = someone sat down.
From there the table's state comes from records that already exist:

* ``seated``   -- sat down, no order yet (a staff member tapped "I am there", or under UNSEEN_MINUTES)
* ``unseen``   -- sat UNSEEN_MINUTES or more and nobody has gone to the table: the floor staff are told ONCE
* ``waiting``  -- an order is open and not served yet (the front-desk order, or a staff-made table order)
* ``eating``   -- served
* ``empty``

A sitting holds NO customer identity (a table, a time). Reads never write. Nothing here moves money or uses AI.
"""
from __future__ import annotations

from datetime import datetime, timedelta
import sqlite3
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import PERMISSIONS, PosError, PosStore, _id

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_table_sits (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, table_id TEXT NOT NULL,"
    " sat_at TEXT NOT NULL, seen_at TEXT, seen_by TEXT NOT NULL DEFAULT '', ended_at TEXT, alerted_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_table_sits ON pos_table_sits(business_id, table_id, ended_at)",
    "CREATE INDEX IF NOT EXISTS idx_pos_table_sits_due ON pos_table_sits(alerted_at, ended_at, sat_at)",
]

UNSEEN_MINUTES = 5          # sat this long with nobody at the table -> the staff are told
SIT_HOURS = 3               # a sitting with no order after this long is over (they left)
MAX_ALERTS_PER_TABLE_DAY = 20   # a QR photo scanned again and again cannot ring the staff all day
STATES = ("empty", "seated", "unseen", "waiting", "eating")
_FLOOR = ("tables", "kitchen", "sell")
_TELL_ROLES = ("owner", "manager", "waiter", "cashier")
_DESK_CLOSED = ("done", "rejected", "cancelled")


def _minutes(since: str, now: datetime) -> int:
    try:
        return max(0, int((now - datetime.fromisoformat(since)).total_seconds() // 60))
    except (TypeError, ValueError):
        return 0


class PosTableWatch:
    def __init__(self, store: PosStore, clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.clock = clock or store.clock
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------------ helpers
    def _floor(self, conn: sqlite3.Connection, business_id: str, user: str) -> str:
        self.store._business_row(conn, business_id)
        role = self.store.role_of(conn, business_id, user)
        if role is None:
            raise PosError(404, "business", "Business not found.")
        if role == "delivery" or not (PERMISSIONS[role] & set(_FLOOR)):
            raise PosError(403, "permission", f"Your role ({role}) cannot see the tables.", role=role)
        return role

    @staticmethod
    def _has(conn: sqlite3.Connection, table: str) -> bool:
        return conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone() is not None

    def _order_state(self, conn: sqlite3.Connection, business_id: str, table_id: str) -> Optional[Dict[str, Any]]:
        """The table's open order, if any: waiting (not served yet) or eating (served)."""
        if self._has(conn, "pos_desk_orders"):
            marks = ",".join("?" * len(_DESK_CLOSED))
            desk = conn.execute(
                f"SELECT id, stage, placed_at, updated_at, pos_order_id FROM pos_desk_orders WHERE business_id = ? AND table_id = ?"
                f" AND stage NOT IN ({marks}) ORDER BY placed_at LIMIT 1", (business_id, table_id, *_DESK_CLOSED)).fetchone()
            if desk is not None:
                if desk["stage"] == "served":
                    at = conn.execute("SELECT MAX(at) AS at FROM pos_desk_events WHERE order_id = ? AND stage = 'served'",
                                      (desk["id"],)).fetchone()
                    return {"state": "eating", "since": (at["at"] if at and at["at"] else desk["updated_at"]),
                            "desk_order_id": desk["id"], "pos_order_id": desk["pos_order_id"] or ""}
                return {"state": "waiting", "since": desk["placed_at"], "desk_order_id": desk["id"],
                        "pos_order_id": desk["pos_order_id"] or ""}
        if self._has(conn, "pos_orders"):
            order = conn.execute("SELECT id, created_at FROM pos_orders WHERE business_id = ? AND table_id = ? AND status = 'open'"
                                 " ORDER BY created_at LIMIT 1", (business_id, table_id)).fetchone()
            if order is not None:
                kots = conn.execute("SELECT status, updated_at FROM pos_kots WHERE business_id = ? AND order_id = ?",
                                    (business_id, order["id"])).fetchall()
                if kots and all(k["status"] == "served" for k in kots):
                    return {"state": "eating", "since": max(k["updated_at"] for k in kots), "desk_order_id": "",
                            "pos_order_id": order["id"]}
                return {"state": "waiting", "since": order["created_at"], "desk_order_id": "", "pos_order_id": order["id"]}
        return None

    def _ordered_since(self, conn: sqlite3.Connection, business_id: str, table_id: str, since: str) -> bool:
        """An order (any state) was made on this table at or after [since]: that sitting was answered."""
        if self._has(conn, "pos_desk_orders") and conn.execute(
                "SELECT 1 FROM pos_desk_orders WHERE business_id = ? AND table_id = ? AND placed_at >= ? LIMIT 1",
                (business_id, table_id, since)).fetchone() is not None:
            return True
        return self._has(conn, "pos_orders") and conn.execute(
            "SELECT 1 FROM pos_orders WHERE business_id = ? AND table_id = ? AND created_at >= ? LIMIT 1",
            (business_id, table_id, since)).fetchone() is not None

    def _sit(self, conn: sqlite3.Connection, business_id: str, table_id: str, now: datetime) -> Optional[sqlite3.Row]:
        """The live sitting of a table: not ended, not too old, and no order made since."""
        floor = (now - timedelta(hours=SIT_HOURS)).isoformat()
        row = conn.execute("SELECT * FROM pos_table_sits WHERE business_id = ? AND table_id = ? AND ended_at IS NULL"
                           " AND sat_at > ? ORDER BY sat_at DESC LIMIT 1", (business_id, table_id, floor)).fetchone()
        if row is None or self._ordered_since(conn, business_id, table_id, row["sat_at"]):
            return None
        return row

    # ------------------------------------------------------------------ the customer sat down
    def sat(self, business_id: str, table_id: str) -> bool:
        """The table's QR was opened. A new sitting starts only on a table with no open order and no live sitting,
        so a second person at the same table, or the same person opening the menu again, changes nothing."""
        now = self.clock()
        with self.store._tx() as conn:
            table = conn.execute("SELECT 1 FROM pos_tables WHERE id = ? AND business_id = ? AND active = 1",
                                 (table_id, business_id)).fetchone()
            if table is None:
                return False
            if self._order_state(conn, business_id, table_id) is not None or self._sit(conn, business_id, table_id, now):
                return False
            conn.execute("INSERT INTO pos_table_sits (id, business_id, table_id, sat_at) VALUES (?, ?, ?, ?)",
                         (_id("sit"), business_id, table_id, now.isoformat()))
        return True

    # ------------------------------------------------------------------ the floor view
    def watch(self, business_id: str, user: str) -> Dict[str, Any]:
        now = self.clock()
        with self.store._connect() as conn:
            self._floor(conn, business_id, user)
            out: List[Dict[str, Any]] = []
            for t in conn.execute("SELECT id, name, area FROM pos_tables WHERE business_id = ? AND active = 1"
                                  " ORDER BY area, name", (business_id,)).fetchall():
                item: Dict[str, Any] = {"id": t["id"], "name": t["name"], "area": t["area"], "state": "empty", "minutes": 0,
                                        "since": "", "desk_order_id": "", "pos_order_id": "", "seen": False}
                order = self._order_state(conn, business_id, t["id"])
                if order is not None:
                    item.update(order, minutes=_minutes(order["since"], now))
                else:
                    sit = self._sit(conn, business_id, t["id"], now)
                    if sit is not None:
                        minutes = _minutes(sit["sat_at"], now)
                        seen = bool(sit["seen_at"])
                        item.update(state="seated" if seen or minutes < UNSEEN_MINUTES else "unseen", minutes=minutes,
                                    since=sit["sat_at"], seen=seen)
                out.append(item)
        counts = {state: sum(1 for t in out if t["state"] == state) for state in STATES}
        return {"now": now.isoformat(), "unseen_minutes": UNSEEN_MINUTES, "tables": out, "counts": counts,
                "alerts": [{"table_id": t["id"], "table_name": t["name"], "minutes": t["minutes"]}
                           for t in out if t["state"] == "unseen"]}

    def _mark(self, business_id: str, user: str, table_id: str, *, end: bool) -> Dict[str, Any]:
        now = self.clock()
        with self.store._tx() as conn:
            self._floor(conn, business_id, user)
            sit = self._sit(conn, business_id, table_id, now)
            if sit is None:
                return {"ok": True, "changed": False}
            if end:
                conn.execute("UPDATE pos_table_sits SET ended_at = ? WHERE id = ?", (now.isoformat(), sit["id"]))
            elif not sit["seen_at"]:
                conn.execute("UPDATE pos_table_sits SET seen_at = ?, seen_by = ? WHERE id = ?", (now.isoformat(), user, sit["id"]))
            else:
                return {"ok": True, "changed": False}
        return {"ok": True, "changed": True}

    def seen(self, business_id: str, user: str, table_id: str) -> Dict[str, Any]:
        """A staff member is at the table ("I am there"): it stops being unseen."""
        return self._mark(business_id, user, table_id, end=False)

    def free(self, business_id: str, user: str, table_id: str) -> Dict[str, Any]:
        """They left without ordering: the table is empty again."""
        return self._mark(business_id, user, table_id, end=True)

    # ------------------------------------------------------------------ tell the staff (once per sitting)
    def due_alerts(self) -> List[Dict[str, Any]]:
        """Sittings that passed UNSEEN_MINUTES with nobody at the table. Each is returned ONCE (marked here); the caller
        sends the push. A sitting that was answered meanwhile (an order, "I am there", left) is closed silently."""
        now = self.clock()
        due = (now - timedelta(minutes=UNSEEN_MINUTES)).isoformat()
        floor = (now - timedelta(hours=SIT_HOURS)).isoformat()
        day = now.isoformat()[:10]
        out: List[Dict[str, Any]] = []
        with self.store._tx() as conn:
            rows = conn.execute("SELECT s.*, t.name AS table_name FROM pos_table_sits s JOIN pos_tables t ON t.id = s.table_id"
                                " WHERE s.alerted_at IS NULL AND s.ended_at IS NULL AND s.seen_at IS NULL AND s.sat_at <= ?"
                                " AND s.sat_at > ? AND t.active = 1 ORDER BY s.sat_at LIMIT 200", (due, floor)).fetchall()
            for row in rows:
                conn.execute("UPDATE pos_table_sits SET alerted_at = ? WHERE id = ?", (now.isoformat(), row["id"]))
                if self._ordered_since(conn, row["business_id"], row["table_id"], row["sat_at"]):
                    continue
                told = conn.execute("SELECT COUNT(*) AS n FROM pos_table_sits WHERE business_id = ? AND table_id = ?"
                                    " AND alerted_at LIKE ? AND id != ?", (row["business_id"], row["table_id"], f"{day}%", row["id"]))
                if told.fetchone()["n"] >= MAX_ALERTS_PER_TABLE_DAY:
                    continue
                out.append({"sit_id": row["id"], "business_id": row["business_id"], "table_id": row["table_id"],
                            "table_name": row["table_name"], "minutes": _minutes(row["sat_at"], now),
                            "users": self._tell(conn, row["business_id"])})
        return out

    @staticmethod
    def _tell(conn: sqlite3.Connection, business_id: str) -> List[str]:
        """The owner and the floor people (manager / waiter / cashier) with an app account; never kitchen or delivery."""
        owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        users = [owner["owner_user_id"]] if owner and owner["owner_user_id"] else []
        marks = ",".join("?" * len(_TELL_ROLES))
        for r in conn.execute(f"SELECT app_user_id FROM pos_members WHERE business_id = ? AND active = 1 AND paused = 0"
                              f" AND role IN ({marks}) AND app_user_id IS NOT NULL AND app_user_id != ''",
                              (business_id, *_TELL_ROLES)):
            users.append(r["app_user_id"])
        return list(dict.fromkeys(users))


def alert_text(item: Dict[str, Any]) -> Dict[str, str]:
    """One notification, Telugu first (the staff hear it)."""
    name, minutes = item["table_name"], item["minutes"]
    return {"title": f"టేబుల్ {name} · కస్టమర్ వేచి ఉన్నారు",
            "body": f"{minutes} నిమిషాలుగా కూర్చున్నారు. వెళ్ళి ఆర్డర్ తీసుకోండి. · Table {name}: seated {minutes} min, order to be taken.",
            "route": f"/pos/{item['business_id']}/tables/watch", "key": f"tablewatch:{item['sit_id']}"}
