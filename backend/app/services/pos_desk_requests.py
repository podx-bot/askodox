"""Table service requests (owner 2026-11-16): a dine-in customer taps (or says) "water / extra gravy / onions / bring the bill"
and the waiter hears it -- one queue per shop, answered with one tap.

On the ONE front-desk order: a request belongs to the customer's own running dine-in order (so it carries the table).
The shop chooses which quick requests its customers see (and adds its own, e.g. "Papad") in the desk settings.
Records only -- nothing here moves money.
"""
from __future__ import annotations

import json
import re
import sqlite3
from typing import Any, Dict, List, Optional

from app.services.pos_store import PosError, _clean, _id

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_desk_requests (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, order_id TEXT NOT NULL,"
    " table_id TEXT, customer_user TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL, label TEXT NOT NULL DEFAULT '',"
    " text TEXT NOT NULL DEFAULT '', qty INTEGER NOT NULL DEFAULT 1, status TEXT NOT NULL DEFAULT 'open',"
    " created_at TEXT NOT NULL, done_at TEXT, done_by TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_pos_desk_req_biz ON pos_desk_requests(business_id, status)",
    "CREATE INDEX IF NOT EXISTS idx_pos_desk_req_order ON pos_desk_requests(order_id, status)",
]

# key, English, Telugu, words that say it (lower-case; Telugu + English + common typed-English-Telugu)
DEFAULT_REQUESTS: List[Dict[str, Any]] = [
    {"key": "water", "en": "Water", "te": "నీళ్లు",
     "words": ["water", "neellu", "nillu", "నీళ్లు", "నీళ్ళు", "నీరు", "వాటర్"]},
    {"key": "extra_gravy", "en": "Extra gravy / shorba", "te": "ఎక్స్‌ట్రా గ్రేవీ / షేర్వా",
     "words": ["gravy", "shorba", "sherva", "curry", "గ్రేవీ", "షేర్వా", "షోర్బా", "కూర"]},
    {"key": "onions", "en": "Onions", "te": "ఆనియన్స్",
     "words": ["onion", "onions", "ullipaya", "ఆనియన్", "ఆనియన్స్", "ఉల్లిపాయ", "ఉల్లిపాయలు"]},
    {"key": "extra_plate", "en": "Plate / spoon", "te": "ప్లేట్ / స్పూన్",
     "words": ["plate", "spoon", "fork", "ప్లేట్", "స్పూన్", "చెంచా"]},
    {"key": "tissue", "en": "Tissue / hand wash", "te": "టిష్యూ / చేతులు కడుక్కోవడానికి",
     "words": ["tissue", "napkin", "టిష్యూ", "నాప్కిన్"]},
    {"key": "bill", "en": "Bring the bill", "te": "బిల్ తీసుకురండి",
     "words": ["bill", "check", "బిల్", "బిల్లు"]},
    {"key": "call", "en": "Call the waiter", "te": "వెయిటర్‌ని పిలవండి",
     "words": ["waiter", "call", "help", "వెయిటర్", "బేరర్", "బ్యారర్", "సర్"]},
]
STOP_WORDS = ["and", "also", "please", "pls", "plz", "extra", "more", "one", "two", "need", "want", "bring", "give", "send",
              "a", "the", "i", "we", "some", "కూడా", "ఇంకా", "ఒక", "రెండు", "మరియు", "ప్లీజ్", "కావాలి", "కావాలండి",
              "తీసుకురండి", "తీసుకురా", "తెండి", "ఇవ్వండి", "కొంచెం", "కాస్త", "సార్", "అండి", "ఇంకొంచెం"]
BUILT_IN = {r["key"] for r in DEFAULT_REQUESTS}
MAX_CUSTOM = 8
MAX_OPEN_PER_ORDER = 12


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").lower()).strip()


class PosDeskRequests:
    """Lives on PosFrontDesk (``desk.requests``); shares its store, clock, staff routing and push."""

    def __init__(self, desk: Any) -> None:
        self.desk = desk
        with desk.store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            try:  # the shop's own choice of quick requests: {"off": [keys], "custom": [{key, en, te}]}
                conn.execute("ALTER TABLE pos_desk_settings ADD COLUMN requests_json TEXT NOT NULL DEFAULT '{}'")
            except sqlite3.OperationalError:
                pass

    # ------------------------------------------------------------------ the shop's list
    def _config(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT requests_json FROM pos_desk_settings WHERE business_id = ?", (business_id,)).fetchone()
        try:
            data = json.loads(row["requests_json"]) if row else {}
        except ValueError:
            data = {}
        off = [str(k) for k in (data.get("off") or []) if str(k) in BUILT_IN]
        custom = []
        for c in (data.get("custom") or [])[:MAX_CUSTOM]:
            label = _clean(c.get("en") or c.get("te"), 40)
            if label:
                custom.append({"key": _clean(c.get("key"), 40) or "c_" + re.sub(r"[^a-z0-9]+", "_", _norm(label))[:30],
                               "en": _clean(c.get("en") or c.get("te"), 40), "te": _clean(c.get("te") or c.get("en"), 40),
                               "custom": True})
        return {"off": off, "custom": custom}

    def catalogue(self, conn: sqlite3.Connection, business_id: str, *, everything: bool = False) -> List[Dict[str, Any]]:
        cfg = self._config(conn, business_id)
        out = [{"key": r["key"], "en": r["en"], "te": r["te"], "custom": False, "enabled": r["key"] not in cfg["off"]}
               for r in DEFAULT_REQUESTS]
        out += [{**c, "enabled": True} for c in cfg["custom"]]
        return out if everything else [r for r in out if r["enabled"]]

    def settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.desk.store._connect() as conn:
            self.desk.store._require(conn, business_id, user, "settings")
            return {"requests": self.catalogue(conn, business_id, everything=True), "max_custom": MAX_CUSTOM}

    def set_settings(self, business_id: str, user: str, off: Optional[List[str]], custom: Optional[List[Dict[str, Any]]]) -> Dict[str, Any]:
        """Owner only: switch a built-in quick request off / on, and add the shop's own (max 8)."""
        with self.desk.store._tx() as conn:
            self.desk.store._require(conn, business_id, user, "settings")
            cur = self._config(conn, business_id)
            new_off = cur["off"] if off is None else [str(k) for k in off if str(k) in BUILT_IN]
            new_custom = cur["custom"] if custom is None else custom
            if len(new_custom) > MAX_CUSTOM:
                raise PosError(400, "requests", f"At most {MAX_CUSTOM} of your own quick requests.")
            data = {"off": new_off, "custom": [{"key": c.get("key") or "", "en": _clean(c.get("en"), 40),
                                                "te": _clean(c.get("te"), 40)} for c in new_custom
                                               if _clean(c.get("en") or c.get("te"), 40)]}
            conn.execute("INSERT INTO pos_desk_settings (business_id, routing_json, auto_confirm, updated_at, requests_json)"
                         " VALUES (?, '{}', 0, ?, ?) ON CONFLICT(business_id) DO UPDATE SET requests_json = excluded.requests_json,"
                         " updated_at = excluded.updated_at",
                         (business_id, self.desk._now().isoformat(), json.dumps(data)))
        return self.settings(business_id, user)

    # ------------------------------------------------------------------ understanding what was said
    def parse(self, conn: sqlite3.Connection, business_id: str, text: str) -> List[Dict[str, Any]]:
        """'extra onions and water' -> [onions, water]. Words nothing matches stay as ONE free request (never dropped)."""
        said = _norm(text)
        if not said:
            return []
        hits: List[Dict[str, Any]] = []
        used = said
        shop = self.catalogue(conn, business_id)
        words = {r["key"]: r["words"] for r in DEFAULT_REQUESTS}
        for item in shop:
            terms = words.get(item["key"]) or [_norm(item["en"]), _norm(item["te"])]
            if any(t and t in said for t in terms):
                hits.append({"kind": item["key"], "label_en": item["en"], "label_te": item["te"]})
                for t in sorted(terms, key=len, reverse=True):
                    used = used.replace(t, " ")
        for w in STOP_WORDS:
            used = re.sub(rf"(?<![\w]){re.escape(w)}(?![\w])", " ", used)
        leftover = re.sub(r"[\s,.;/&+-]+", " ", used).strip()
        if len(leftover) >= (1 if not hits else 4):  # something nothing matched (e.g. "papad") stays a free request
            hits.append({"kind": "other", "label_en": _clean(leftover, 80), "label_te": _clean(leftover, 80),
                         "text": _clean(leftover, 120)})
        return hits

    # ------------------------------------------------------------------ the customer
    def _own_dine_in(self, conn: sqlite3.Connection, user: str, order_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
        if row is None:
            raise PosError(404, "order", "Order not found.")
        row = dict(row)
        if row["kind"] != "dine_in":
            raise PosError(409, "kind", "టేబుల్ సర్వీస్ అభ్యర్థనలు ఇక్కడ తినే ఆర్డర్‌లకే (Table requests are for dine-in orders).")
        if row["stage"] in ("done", "rejected", "cancelled", "placed"):
            raise PosError(409, "stage", "షాప్ ఆర్డర్ అంగీకరించాక అడగవచ్చు (You can ask once the shop has accepted the order).")
        return row

    def ask(self, user: str, order_id: str, kinds: Optional[List[str]] = None, text: str = "", qty: int = 1) -> Dict[str, Any]:
        """Kinds tapped from the shop's quick list and / or free text (typed or spoken). The same open request on an order is
        never doubled (tapping twice only reminds); a bill request is one at a time."""
        qty = max(1, min(int(qty or 1), 9))
        created: List[Dict[str, Any]] = []
        with self.desk.store._tx() as conn:
            row = self._own_dine_in(conn, user, order_id)
            biz = row["business_id"]
            shop = {r["key"]: r for r in self.catalogue(conn, biz)}
            wanted: List[Dict[str, Any]] = []
            for k in dict.fromkeys(kinds or []):
                if k not in shop:
                    raise PosError(400, "kind", "ఈ షాప్ ఈ అభ్యర్థన ఇవ్వట్లేదు (This shop does not offer that request).")
                wanted.append({"kind": k, "label_en": shop[k]["en"], "label_te": shop[k]["te"]})
            if text.strip():
                have = {x["kind"] for x in wanted}
                wanted += [w for w in self.parse(conn, biz, text) if w["kind"] == "other" or w["kind"] not in have]
            if not wanted:
                raise PosError(400, "request", "ఏమి కావాలో చెప్పండి (Tell us what you need).")
            open_now = conn.execute("SELECT COUNT(*) AS n FROM pos_desk_requests WHERE order_id = ? AND status = 'open'",
                                    (order_id,)).fetchone()["n"]
            now = self.desk._now().isoformat()
            for w in wanted:
                same = conn.execute("SELECT * FROM pos_desk_requests WHERE order_id = ? AND status = 'open' AND kind = ? AND"
                                    " (kind != 'other' OR text = ?)", (order_id, w["kind"], w.get("text", ""))).fetchone()
                if same:  # already waiting: nothing new, the waiter already has it
                    continue
                if open_now >= MAX_OPEN_PER_ORDER:
                    raise PosError(429, "too_many", "చాలా అభ్యర్థనలు వేచి ఉన్నాయి (Too many requests are waiting).")
                rid = _id("req")
                conn.execute("INSERT INTO pos_desk_requests (id, business_id, order_id, table_id, customer_user, kind, label,"
                             " text, qty, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)",
                             (rid, biz, order_id, row["table_id"], user, w["kind"], w["label_en"], w.get("text", ""),
                              qty if w["kind"] not in ("bill", "call") else 1, now))
                open_now += 1
                created.append({"id": rid, **w})
            table = conn.execute("SELECT name FROM pos_tables WHERE id = ?", (row["table_id"],)).fetchone() if row["table_id"] else None
            targets = self.desk._targets(conn, biz, "ready")
            table_name = table["name"] if table else ""
        if created:
            line = ", ".join(w["label_te"] for w in created)
            urgent = any(w["kind"] == "bill" for w in created)
            self.desk._push(targets, f"{table_name or 'టేబుల్'} · {'బిల్ కావాలి' if urgent else 'సర్వీస్ కావాలి'}"[:70], line[:160],
                            f"/desk/{biz}", f"desk:{order_id}:req:{created[0]['id']}")
        return {"asked": [{"kind": w["kind"], "label": {"en": w["label_en"], "te": w["label_te"]}} for w in created],
                "already_waiting": len(wanted) - len(created), "requests": self.for_order(user, order_id)["requests"]}

    def for_order(self, user: str, order_id: str) -> Dict[str, Any]:
        with self.desk.store._connect() as conn:
            row = conn.execute("SELECT business_id, kind, stage FROM pos_desk_orders WHERE id = ? AND customer_user = ?",
                               (order_id, user)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            rows = conn.execute("SELECT * FROM pos_desk_requests WHERE order_id = ? ORDER BY created_at DESC LIMIT 30",
                                (order_id,)).fetchall()
            can_ask = row["kind"] == "dine_in" and row["stage"] not in ("done", "rejected", "cancelled", "placed")
            return {"can_ask": can_ask, "quick": self.catalogue(conn, row["business_id"]) if can_ask else [],
                    "requests": [self._row(r) for r in rows]}

    def cancel_mine(self, user: str, request_id: str) -> Dict[str, Any]:
        with self.desk.store._tx() as conn:
            r = conn.execute("SELECT * FROM pos_desk_requests WHERE id = ? AND customer_user = ?", (request_id, user)).fetchone()
            if r is None:
                raise PosError(404, "request", "Request not found.")
            if r["status"] == "open":
                conn.execute("UPDATE pos_desk_requests SET status = 'cancelled', done_at = ? WHERE id = ?",
                             (self.desk._now().isoformat(), request_id))
        return {"ok": True}

    # ------------------------------------------------------------------ the shop
    @staticmethod
    def _row(r: sqlite3.Row) -> Dict[str, Any]:
        return {"id": r["id"], "order_id": r["order_id"], "table_id": r["table_id"], "kind": r["kind"], "label": r["label"],
                "text": r["text"], "qty": r["qty"], "status": r["status"], "created_at": r["created_at"],
                "done_at": r["done_at"], "done_by_last4": (r["done_by"] or "")[-4:]}

    def open_list(self, business_id: str, user: str) -> Dict[str, Any]:
        """The waiter's queue: open requests, oldest first, with the table's name."""
        with self.desk.store._connect() as conn:
            self.desk._floor(conn, business_id, user)
            rows = conn.execute(
                "SELECT r.*, t.name AS table_name FROM pos_desk_requests r LEFT JOIN pos_tables t ON t.id = r.table_id"
                " WHERE r.business_id = ? AND r.status = 'open' ORDER BY r.created_at", (business_id,)).fetchall()
            out = [{**self._row(r), "table_name": r["table_name"] or ""} for r in rows]
            return {"requests": out, "count": len(out)}

    def done(self, business_id: str, user: str, request_id: str) -> Dict[str, Any]:
        with self.desk.store._tx() as conn:
            self.desk._floor(conn, business_id, user)
            r = conn.execute("SELECT * FROM pos_desk_requests WHERE id = ? AND business_id = ?", (request_id, business_id)).fetchone()
            if r is None:
                raise PosError(404, "request", "Request not found.")
            if r["status"] == "open":
                conn.execute("UPDATE pos_desk_requests SET status = 'done', done_at = ?, done_by = ? WHERE id = ?",
                             (self.desk._now().isoformat(), user, request_id))
            cust, order_id, label = r["customer_user"], r["order_id"], r["label"]
        if cust:
            self.desk._push([cust], "వస్తోంది · On the way", f"{label}", f"/order/track/{order_id}", f"desk:{order_id}:reqdone:{request_id}")
        return self.open_list(business_id, user)
