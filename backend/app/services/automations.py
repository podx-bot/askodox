"""ASKODOX automations (owner "Ok" 2026-11-25 on design UFxZdSJNjNKMMMneqhyT5t; built 2026-11-26).

Six things ASKODOX notices by itself. The owner's rules for all of them:

* money and messages to customers are DRAFTS only -- nothing is ordered, sent or paid until the person taps;
* every card can be put away: "వద్దు" (not now) or "ఇక చూపించకు" (never again for this thing);
* a habit is a habit only after the same shop on the same weekday ``automation.habit_times`` times (3);
* every number is a Command Center setting (``platform_settings``), never a constant in the app.

1. Buyer "same again?" card ........ ``habit``            (reads the person's own finished orders)
2. Bill reminder by voice .......... on the phone (``askodoxAutoBillDues`` in the app; nothing on the server)
3. Low stock -> supplier order draft ``low_stock`` / ``low_stock_draft`` (a ``draft`` purchase order, never sent)
4. Regulars not seen for N days .... ``winback``          (a list + a message draft; the owner sends it himself)
5. Stopped shops: help push + list . ``stopped_shops`` / ``nudge_stopped`` (staff press the button; once a week a shop)
6. AI cost guard ................... ``cost_guard``       (today's AI bill against the staff's daily budget)

Reads the POS tables directly (read only); writes only its own two tables and, for 3, a normal draft purchase
order through ``PosPurchases.create_po`` (so the shop's permissions and audit apply).
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services import platform_settings

IST = timezone(timedelta(hours=5, minutes=30))
DONE_STAGES = ("served", "handed", "delivered", "done")
HABIT_WINDOW_DAYS = 70
WINBACK_REGULAR_BILLS = 3  # bills in the 90 days before they went quiet
WINBACK_LOOK_BACK_DAYS = 120  # older than this is a lost customer, not one to win back with a message
LIST_LIMIT = 50
KINDS = ("habit", "low_stock", "winback")
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS automation_dismissals (user_id TEXT NOT NULL, kind TEXT NOT NULL, ref TEXT NOT NULL,"
    " until TEXT NOT NULL DEFAULT '', at TEXT NOT NULL, PRIMARY KEY (user_id, kind, ref))",
    "CREATE TABLE IF NOT EXISTS automation_log (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,"
    " ref TEXT NOT NULL, actor TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '{}', at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_automation_log ON automation_log(kind, ref, at)",
]


class AutomationError(Exception):
    def __init__(self, code: str, status: int = 400) -> None:
        super().__init__(code)
        self.code, self.status = code, status


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _setting(key: str) -> float:
    return float(platform_settings.get(key))


def mask_phone(value: Any) -> str:
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    return ("••••" + digits[-4:]) if len(digits) >= 4 else ""


class Automations:
    def __init__(self, db_path: str, *, clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.clock = clock
        with closing(sqlite3.connect(db_path)) as conn:
            for statement in SCHEMA:
                conn.execute(statement)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def _today(self):
        return self.clock().astimezone(IST).date()

    @staticmethod
    def _has(conn: sqlite3.Connection, table: str) -> bool:
        return conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)).fetchone() is not None

    # ---------------------------------------------------------- put away --
    def dismiss(self, user: str, kind: str, ref: str, *, forever: bool) -> Dict[str, Any]:
        """"వద్దు" = not today; "ఇక చూపించకు" = never again for this shop / supplier / customer."""
        if kind not in KINDS or not ref or len(ref) > 120:
            raise AutomationError("bad_dismiss")
        until = "" if forever else self._today().isoformat()
        with closing(self._connect()) as conn:
            conn.execute("INSERT INTO automation_dismissals(user_id, kind, ref, until, at) VALUES(?,?,?,?,?)"
                         " ON CONFLICT(user_id, kind, ref) DO UPDATE SET until = excluded.until, at = excluded.at",
                         (user, kind, ref, until, self.clock().isoformat()))
            conn.commit()
        return {"kind": kind, "ref": ref, "forever": forever}

    def _dismissed(self, conn: sqlite3.Connection, user: str, kind: str) -> set:
        today = self._today().isoformat()
        return {r["ref"] for r in conn.execute("SELECT ref, until FROM automation_dismissals WHERE user_id = ? AND"
                                               " kind = ?", (user, kind)) if r["until"] == "" or r["until"] >= today}

    # ------------------------------------------------- 1. buyer habit card --
    def habit(self, user: str) -> List[Dict[str, Any]]:
        """Shops this person ordered from on THIS weekday at least N times (finished orders, last 10 weeks) and not
        yet today. Each card carries the newest such order so the app opens the same cart (never orders by itself)."""
        times = int(_setting("automation.habit_times"))
        today = self._today()
        since = (datetime.combine(today, datetime.min.time(), IST) - timedelta(days=HABIT_WINDOW_DAYS)).astimezone(
            timezone.utc).isoformat()
        with closing(self._connect()) as conn:
            if not self._has(conn, "pos_desk_orders"):
                return []
            rows = conn.execute("SELECT o.id, o.business_id, o.kind, o.items_json, o.stage, o.placed_at, b.name AS shop"
                                " FROM pos_desk_orders o JOIN pos_businesses b ON b.id = o.business_id WHERE"
                                " o.customer_user = ? AND o.placed_at >= ? ORDER BY o.placed_at DESC", (user, since)).fetchall()
            put_away = self._dismissed(conn, user, "habit")
        by_shop: Dict[str, Dict[str, Any]] = {}
        for row in rows:
            placed = datetime.fromisoformat(row["placed_at"])
            day = (placed if placed.tzinfo else placed.replace(tzinfo=timezone.utc)).astimezone(IST).date()
            shop = by_shop.setdefault(row["business_id"], {"days": set(), "today": False, "newest": None, "name": row["shop"]})
            if day == today:
                shop["today"] = True  # any order today (even a running one): nothing to suggest
            if row["stage"] not in DONE_STAGES or day.weekday() != today.weekday() or day == today:
                continue
            shop["days"].add(day)
            shop["newest"] = shop["newest"] or row
        cards = []
        for business_id, shop in by_shop.items():
            if shop["today"] or len(shop["days"]) < times or business_id in put_away:
                continue
            newest = shop["newest"]
            try:
                items = [i for i in json.loads(newest["items_json"]) if isinstance(i, dict)]
            except (TypeError, ValueError):
                continue
            cards.append({"kind": "habit", "ref": business_id, "times": len(shop["days"]), "weekday": today.weekday(),
                          # the shape of GET /desk/mine, so the app's own "same again" builder makes the cart
                          "order": {"id": newest["id"], "business_id": business_id, "business_name": shop["name"],
                                    "kind": newest["kind"], "stage": "done", "items": items}})
        return sorted(cards, key=lambda c: -c["times"])[:3]

    # ----------------------------------- 3. low stock -> supplier order draft --
    def low_stock(self, store: Any, business_id: str, user: str) -> Dict[str, Any]:
        """Items at or under their own low-stock mark, grouped by the supplier they were last bought from, with the
        quantity bought last time. Items already on an open purchase order are left out."""
        with store._connect() as conn:
            store._require(conn, business_id, user, "purchases")
            stock = {r["product_id"]: int(r["qty"] or 0) for r in conn.execute(
                "SELECT product_id, SUM(qty_milli) AS qty FROM pos_stock_moves WHERE business_id = ? GROUP BY product_id",
                (business_id,))}
            low = [dict(r) for r in conn.execute(
                "SELECT id, name, unit, low_stock_milli FROM pos_products WHERE business_id = ? AND active = 1 AND"
                " track_stock = 1 AND low_stock_milli > 0 AND is_service = 0 ORDER BY name", (business_id,))
                   if stock.get(r["id"], 0) <= r["low_stock_milli"]]
            on_order = set()
            for r in conn.execute("SELECT lines FROM pos_purchase_orders WHERE business_id = ? AND status IN"
                                  " ('draft', 'sent', 'partly_received')", (business_id,)):
                on_order |= {line.get("product_id") for line in json.loads(r["lines"] or "[]")}
            last = {r["product_id"]: dict(r) for r in conn.execute(
                "SELECT l.product_id, p.supplier_id, s.name AS supplier, l.qty_milli, l.cost_paise, MAX(p.created_at) AS at"
                " FROM pos_purchase_lines l JOIN pos_purchases p ON p.id = l.purchase_id JOIN pos_suppliers s ON"
                " s.id = p.supplier_id WHERE p.business_id = ? AND p.status != 'cancelled' GROUP BY l.product_id",
                (business_id,))}
        with closing(self._connect()) as conn:
            put_away = self._dismissed(conn, user, "low_stock")
        groups: Dict[str, Dict[str, Any]] = {}
        no_supplier: List[Dict[str, Any]] = []
        for item in low:
            if item["id"] in on_order:
                continue
            have = stock.get(item["id"], 0)
            bought = last.get(item["id"])
            line = {"product_id": item["id"], "name": item["name"], "unit": item["unit"], "stock_milli": have,
                    "low_milli": item["low_stock_milli"],
                    # what was bought last time, and never less than what brings the shelf above its mark again
                    "qty_milli": max(int(bought["qty_milli"]) if bought else 0, 2 * item["low_stock_milli"] - have, 1000),
                    "cost_paise": int(bought["cost_paise"]) if bought else None}
            if not bought:
                no_supplier.append(line)
                continue
            ref = f"{business_id}:{bought['supplier_id']}"
            if ref in put_away:
                continue
            group = groups.setdefault(bought["supplier_id"], {"kind": "low_stock", "ref": ref,
                                                              "supplier_id": bought["supplier_id"],
                                                              "supplier": bought["supplier"], "lines": []})
            group["lines"].append(line)
        return {"suppliers": sorted(groups.values(), key=lambda g: -len(g["lines"])), "no_supplier": no_supplier,
                "draft_only": True}

    def low_stock_draft(self, store: Any, purchases: Any, business_id: str, user: str, supplier_id: str) -> Dict[str, Any]:
        """Makes ONE draft purchase order for that supplier's low items. A draft: the owner checks and sends it."""
        group = next((g for g in self.low_stock(store, business_id, user)["suppliers"] if g["supplier_id"] == supplier_id),
                     None)
        if group is None:
            raise AutomationError("nothing_low", 409)
        order = purchases.create_po(business_id, user, {
            "supplier_id": supplier_id, "notes": "ASKODOX: stock తక్కువ. Draft -- check and send.",
            "lines": [{"product_id": line["product_id"], "qty_milli": line["qty_milli"], "cost_paise": line["cost_paise"]}
                      for line in group["lines"]]})
        self._log("low_stock_draft", f"{business_id}:{supplier_id}", user, {"po": order.get("id"), "lines": len(group["lines"])})
        return {"order": order, "sent": False}

    # --------------------------------------- 4. regulars who stopped coming --
    def winback(self, store: Any, business_id: str, user: str) -> Dict[str, Any]:
        """Saved customers with a phone who were regulars (3+ bills in the 90 days before their last bill) and have no
        bill for ``automation.winback_days`` days. A list and a message DRAFT: the owner sends it himself."""
        days = int(_setting("automation.winback_days"))
        today = self._today()
        quiet_from = (today - timedelta(days=days)).isoformat()
        oldest = (today - timedelta(days=WINBACK_LOOK_BACK_DAYS)).isoformat()
        with store._connect() as conn:
            store._require(conn, business_id, user, "customers")
            shop = conn.execute("SELECT name FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()["name"]
            rows = conn.execute(
                "SELECT c.id, c.name, c.phone, MAX(i.local_date) AS last_day FROM pos_customers c JOIN pos_invoices i ON"
                " i.customer_id = c.id AND i.business_id = c.business_id WHERE c.business_id = ? AND c.phone != '' AND"
                " i.doc_kind = 'invoice' AND i.status != 'cancelled' GROUP BY c.id HAVING last_day <= ? AND last_day >= ?"
                " ORDER BY last_day DESC", (business_id, quiet_from, oldest)).fetchall()
            people = []
            for row in rows:
                last = datetime.fromisoformat(row["last_day"]).date()
                bills = conn.execute("SELECT COUNT(*) FROM pos_invoices WHERE business_id = ? AND customer_id = ? AND"
                                     " doc_kind = 'invoice' AND status != 'cancelled' AND local_date >= ?",
                                     (business_id, row["id"], (last - timedelta(days=90)).isoformat())).fetchone()[0]
                if bills >= WINBACK_REGULAR_BILLS:
                    people.append({"kind": "winback", "ref": f"{business_id}:{row['id']}", "customer_id": row["id"],
                                   "name": row["name"], "phone": row["phone"], "last_day": row["last_day"],
                                   "days": (today - last).days, "bills": int(bills)})
        with closing(self._connect()) as conn:
            put_away = self._dismissed(conn, user, "winback")
        people = [p for p in people if p["ref"] not in put_away][:LIST_LIMIT]
        return {"days": days, "people": people, "draft_only": True,
                "draft": {"te": f"నమస్తే! {shop} నుంచి. చాలా రోజులైంది, మీరు రాలేదు. ఈ వారం వస్తే మీ కోసం ప్రత్యేక ఆఫర్ ఉంది.",
                          "en": f"Namaste! From {shop}. We have not seen you for a while. Come this week, there is a "
                                "special offer for you."}}

    # --------------------------------------------- 5. stopped shops (staff) --
    def nudge_stopped(self, shops: List[Dict[str, Any]], *, actor: str, notify: Callable[..., int]) -> Dict[str, Any]:
        """Staff pressed "help push": each shop's OWNER gets one offer of help, at most once per
        ``automation.stopped_push_gap_days``. ``shops`` = [{id, owner}] from the retention lists."""
        gap = int(_setting("automation.stopped_push_gap_days"))
        since = (self.clock() - timedelta(days=gap)).isoformat()
        sent, skipped = 0, 0
        for shop in shops[:200]:
            business_id, owner = str(shop.get("id") or ""), str(shop.get("owner") or "")
            if not business_id or not owner:
                continue
            with closing(self._connect()) as conn:
                recent = conn.execute("SELECT 1 FROM automation_log WHERE kind = 'stopped_push' AND ref = ? AND at >= ?",
                                      (business_id, since)).fetchone()
            if recent:
                skipped += 1
                continue
            delivered = notify(owner, title="ASKODOX సాయం కావాలా?",
                               body="Shop లో ASKODOX వాడటంలో ఏదైనా ఇబ్బందా? ఒక్కసారి తెరవండి, మేము సాయం చేస్తాం.",
                               route="/", event_key=f"shop_help:{business_id}:{self._today().isoformat()}")
            self._log("stopped_push", business_id, actor, {"devices": int(delivered or 0)})
            sent += 1
        return {"sent": sent, "skipped_recent": skipped, "gap_days": gap}

    def nudges(self, business_ids: List[str]) -> Dict[str, str]:
        """business id -> when the last help push went (for the call list)."""
        if not business_ids:
            return {}
        with closing(self._connect()) as conn:
            marks = ",".join("?" * len(business_ids))
            return {r["ref"]: r["at"] for r in conn.execute(
                f"SELECT ref, MAX(at) AS at FROM automation_log WHERE kind = 'stopped_push' AND ref IN ({marks})"
                " GROUP BY ref", business_ids)}

    # ----------------------------------------------------- 6. AI cost guard --
    def cost_guard(self, *, today_cost_inr: float, users: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
        """Today's AI bill (estimate) against the staff's daily budget, and people far above the per-person mark.
        It only WARNS: shop core and paying users are never cut by it (owner: paid users have no limit)."""
        budget = _setting("automation.ai_cost_daily_inr")
        per_user = _setting("automation.ai_cost_user_daily_inr")
        share = (today_cost_inr / budget) if budget > 0 else 0.0
        state = "off" if budget <= 0 else "over" if share >= 1 else "warn" if share >= 0.8 else "ok"
        heavy = [{"user": u.get("user"), "cost_inr": round(float(u.get("cost_inr") or 0), 2), "uses": u.get("uses")}
                 for u in (users or []) if per_user > 0 and float(u.get("cost_inr") or 0) >= per_user]
        return {"state": state, "today_cost_inr": round(today_cost_inr, 2), "budget_inr": budget,
                "percent": round(100 * share) if budget > 0 else None, "per_user_inr": per_user, "heavy_users": heavy[:20],
                "estimate": True}

    def cost_alert_due(self, guard: Dict[str, Any]) -> bool:
        """True once per India day and state (warn / over): the caller then tells staff."""
        if guard["state"] not in ("warn", "over"):
            return False
        ref = f"{self._today().isoformat()}:{guard['state']}"
        with closing(self._connect()) as conn:
            if conn.execute("SELECT 1 FROM automation_log WHERE kind = 'cost_alert' AND ref = ?", (ref,)).fetchone():
                return False
        self._log("cost_alert", ref, "system", {"cost_inr": guard["today_cost_inr"], "budget_inr": guard["budget_inr"]})
        return True

    # ------------------------------------------------------------------ log --
    def _log(self, kind: str, ref: str, actor: str, detail: Dict[str, Any]) -> None:
        with closing(self._connect()) as conn:
            conn.execute("INSERT INTO automation_log(kind, ref, actor, detail, at) VALUES(?,?,?,?,?)",
                         (kind, ref, actor, json.dumps(detail), self.clock().isoformat()))
            conn.commit()
