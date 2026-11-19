"""Table reservation ahead of time (owner 2026-11-19).

"He is outside, he will come in an hour or two: show the free tables, let him reserve." A signed-in person picks a time
(up to ``MAX_AHEAD_DAYS`` ahead), the number of people, and one of the tables that is FREE around that time (no other
reservation within ``SLOT_MINUTES`` either side, enough seats). The reservation is confirmed at once (the shop owner
is told; less work for the owner) and can be cancelled by either side. A person who has not arrived ``HOLD_MINUTES``
after the time loses the table (status ``no_show``) -- computed when anyone looks, no timer needed.

Only the shop's own tables (``pos_tables``); nothing is charged and nothing is ordered here -- food is ordered through
the normal order desk (table QR / chat menu), before or after arriving.
"""
from __future__ import annotations

import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PosError

SLOT_MINUTES = 90
HOLD_MINUTES = 15
MAX_AHEAD_DAYS = 7
OPEN = ("booked",)

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_table_reservations (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, table_id TEXT NOT NULL,"
    " customer_user TEXT NOT NULL, customer_name TEXT NOT NULL DEFAULT '', people INTEGER NOT NULL DEFAULT 2,"
    " at_utc TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'booked', note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL, client_txn_id TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_pos_table_res_biz ON pos_table_reservations(business_id, at_utc)",
    "CREATE INDEX IF NOT EXISTS idx_pos_table_res_user ON pos_table_reservations(customer_user, at_utc)",
]


class PosReservations:
    def __init__(self, store: Any, *, notify: Optional[Callable[[str, str, str, str, str], Any]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.notify = notify or (lambda user, title, body, route, key: None)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------------ helpers
    def _when(self, value: Any) -> datetime:
        try:
            at = datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
        except ValueError:
            raise PosError(400, "at", "Choose the time you will come.")
        if at.tzinfo is None:
            at = at.replace(tzinfo=IST)
        at = at.astimezone(timezone.utc)
        now = self.clock()
        if at < now - timedelta(minutes=5) or at > now + timedelta(days=MAX_AHEAD_DAYS):
            raise PosError(400, "at", f"Choose a time from now up to {MAX_AHEAD_DAYS} days ahead.")
        return at

    def _expire(self, conn: sqlite3.Connection, business_id: str) -> None:
        cut = (self.clock() - timedelta(minutes=HOLD_MINUTES)).isoformat()
        conn.execute("UPDATE pos_table_reservations SET status = 'no_show', updated_at = ? WHERE business_id = ? AND"
                     " status = 'booked' AND at_utc < ?", (self.clock().isoformat(), business_id, cut))

    def _free(self, conn: sqlite3.Connection, business_id: str, at: datetime, people: int) -> List[Dict[str, Any]]:
        low, high = (at - timedelta(minutes=SLOT_MINUTES)).isoformat(), (at + timedelta(minutes=SLOT_MINUTES)).isoformat()
        taken = {r["table_id"] for r in conn.execute(
            "SELECT table_id FROM pos_table_reservations WHERE business_id = ? AND status = 'booked' AND at_utc > ? AND at_utc < ?",
            (business_id, low, high))}
        soon = abs((at - self.clock()).total_seconds()) < SLOT_MINUTES * 60
        out = []
        for t in conn.execute("SELECT id, name, area, seats FROM pos_tables WHERE business_id = ? AND active = 1 ORDER BY seats, name",
                              (business_id,)):
            if t["id"] in taken or int(t["seats"]) < people:
                continue
            # coming within the slot: a table people are sitting at right now is not offered
            if soon and conn.execute("SELECT 1 FROM pos_orders WHERE business_id = ? AND table_id = ? AND status = 'open'",
                                     (business_id, t["id"])).fetchone():
                continue
            out.append({"id": t["id"], "name": t["name"], "area": t["area"], "seats": int(t["seats"])})
        return out

    @staticmethod
    def _view(row: sqlite3.Row, table: str, shop: str) -> Dict[str, Any]:
        return {"id": row["id"], "business_id": row["business_id"], "shop": shop, "table_id": row["table_id"],
                "table_name": table, "people": row["people"], "at": row["at_utc"], "status": row["status"],
                "customer_name": row["customer_name"], "note": row["note"]}

    def _out(self, conn: sqlite3.Connection, row: sqlite3.Row) -> Dict[str, Any]:
        table = conn.execute("SELECT name FROM pos_tables WHERE id = ?", (row["table_id"],)).fetchone()
        shop = self.store._business_row(conn, row["business_id"])["name"]
        return self._view(row, table["name"] if table else "", shop)

    # ------------------------------------------------------------------ customer
    def free_tables(self, business_id: str, at: Any, people: int = 2) -> Dict[str, Any]:
        when = self._when(at)
        people = max(1, min(int(people or 2), 50))
        with self.store._tx() as conn:
            self.store._business_row(conn, business_id)
            self._expire(conn, business_id)
            tables = self._free(conn, business_id, when, people)
            total = conn.execute("SELECT COUNT(*) AS n FROM pos_tables WHERE business_id = ? AND active = 1", (business_id,)).fetchone()["n"]
        return {"at": when.isoformat(), "people": people, "tables": tables, "has_tables": total > 0,
                "hold_minutes": HOLD_MINUTES}

    def book(self, user: str, business_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        when = self._when(data.get("at"))
        people = max(1, min(int(data.get("people") or 2), 50))
        txn = str(data.get("client_txn_id") or "")[:64]
        with self.store._tx() as conn:
            biz = self.store._business_row(conn, business_id)
            self._expire(conn, business_id)
            if txn:
                again = conn.execute("SELECT * FROM pos_table_reservations WHERE customer_user = ? AND client_txn_id = ?",
                                     (user, txn)).fetchone()
                if again:
                    return self._out(conn, again)
            free = {t["id"]: t for t in self._free(conn, business_id, when, people)}
            table = free.get(str(data.get("table_id") or ""))
            if table is None:
                raise PosError(409, "table", "That table is no longer free at that time. Choose another.")
            mine = conn.execute("SELECT COUNT(*) AS n FROM pos_table_reservations WHERE customer_user = ? AND status = 'booked'",
                                (user,)).fetchone()["n"]
            if mine >= 3:
                raise PosError(409, "limit", "You already have 3 reservations. Cancel one first.")
            res_id, now = "res_" + uuid.uuid4().hex[:16], self.clock().isoformat()
            name = " ".join(str(data.get("name") or "").split())[:60]
            conn.execute("INSERT INTO pos_table_reservations (id, business_id, table_id, customer_user, customer_name, people,"
                         " at_utc, status, note, created_at, updated_at, client_txn_id) VALUES (?,?,?,?,?,?,?,'booked',?,?,?,?)",
                         (res_id, business_id, table["id"], user, name, people, when.isoformat(),
                          " ".join(str(data.get("note") or "").split())[:160], now, now, txn))
            out = self._out(conn, conn.execute("SELECT * FROM pos_table_reservations WHERE id = ?", (res_id,)).fetchone())
            owner = biz["owner_user_id"]
        local = when.astimezone(IST).strftime("%d %b %I:%M %p")
        self.notify(owner, "Table reserved / టేబుల్ రిజర్వ్ అయింది",
                    f"{table['name']} · {local} · {people} {'· ' + name if name else ''}".strip(),
                    f"/pos/{business_id}/tables", f"table_res:{res_id}")
        return out

    def mine(self, user: str) -> List[Dict[str, Any]]:
        with self.store._tx() as conn:
            rows = conn.execute("SELECT * FROM pos_table_reservations WHERE customer_user = ? ORDER BY at_utc DESC LIMIT 20",
                                (user,)).fetchall()
            for biz in {r["business_id"] for r in rows}:
                self._expire(conn, biz)
            rows = conn.execute("SELECT * FROM pos_table_reservations WHERE customer_user = ? ORDER BY at_utc DESC LIMIT 20",
                                (user,)).fetchall()
            return [self._out(conn, r) for r in rows]

    def cancel_mine(self, user: str, res_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_table_reservations WHERE id = ? AND customer_user = ?", (res_id, user)).fetchone()
            if row is None:
                raise PosError(404, "reservation", "Reservation not found.")
            if row["status"] == "booked":
                conn.execute("UPDATE pos_table_reservations SET status = 'cancelled', updated_at = ? WHERE id = ?",
                             (self.clock().isoformat(), res_id))
            out = self._out(conn, conn.execute("SELECT * FROM pos_table_reservations WHERE id = ?", (res_id,)).fetchone())
            owner = self.store._business_row(conn, row["business_id"])["owner_user_id"]
        if row["status"] == "booked":
            self.notify(owner, "Reservation cancelled / రిజర్వేషన్ రద్దు", f"{out['table_name']}",
                        f"/pos/{row['business_id']}/tables", f"table_res_cancel:{res_id}")
        return out

    # ------------------------------------------------------------------ shop
    def for_business(self, business_id: str, user: str) -> List[Dict[str, Any]]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            self._expire(conn, business_id)
            since = (self.clock() - timedelta(hours=12)).isoformat()
            rows = conn.execute("SELECT * FROM pos_table_reservations WHERE business_id = ? AND at_utc >= ? ORDER BY at_utc",
                                (business_id, since)).fetchall()
            return [self._out(conn, r) for r in rows]

    def set_status(self, business_id: str, user: str, res_id: str, status: str) -> Dict[str, Any]:
        if status not in ("arrived", "cancelled", "no_show"):
            raise PosError(400, "status", "Unknown status.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "tables")
            row = conn.execute("SELECT * FROM pos_table_reservations WHERE id = ? AND business_id = ?", (res_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "reservation", "Reservation not found.")
            conn.execute("UPDATE pos_table_reservations SET status = ?, updated_at = ? WHERE id = ?",
                         (status, self.clock().isoformat(), res_id))
            out = self._out(conn, conn.execute("SELECT * FROM pos_table_reservations WHERE id = ?", (res_id,)).fetchone())
        if status == "cancelled" and row["status"] == "booked":
            self.notify(row["customer_user"], f"{out['shop']}: reservation cancelled / రిజర్వేషన్ రద్దు", out["table_name"],
                        "/", f"table_res_shop_cancel:{res_id}")
        return out
