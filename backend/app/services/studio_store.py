"""ASKODOX Studio (owner 2026-11-21): products staff BUY to shoot, from purchase to return.

One row per purchase: store, buying account (whitelisted or not, per store), what was paid, pack, order / delivery
dates, the store's return option and days -> the return deadline (computed, never typed), the commission link (for
Instagram / Facebook / YouTube) and Meesho's Share & Earn link (WhatsApp only), the stage
(bought -> delivered -> shot -> edited -> posted -> returned / kept) and the return record (return id, pickup date,
fee, refund state).

Money is integer paise. Staff see their own purchases; publishers / the owner see all (Studio spec: money totals to
the owner, staff only their own). Reminders (``due_reminders``) are sent once per purchase and kind.
"""
from __future__ import annotations

import datetime as dt
import json
import sqlite3
from typing import Any, Callable, Dict, List, Optional

IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
STORES = ("Meesho", "Flipkart", "Myntra", "Amazon", "Ajio", "Other")
STAGES = ("bought", "delivered", "shot", "edited", "posted")
CLOSED = ("returned", "kept")
RETURN_OPTIONS = ("return", "exchange", "none")
REFUND_STATES = ("", "sent", "picked", "refunded")
PACKS = ("single", "pair", "combo")

SCHEMA = (
    """CREATE TABLE IF NOT EXISTS studio_purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL, item_id INTEGER, title TEXT NOT NULL, store TEXT NOT NULL,
        account_id INTEGER, account_label TEXT NOT NULL DEFAULT '', account_whitelisted INTEGER NOT NULL DEFAULT 0,
        paid_paise INTEGER NOT NULL DEFAULT 0, pack TEXT NOT NULL DEFAULT 'single', pack_count INTEGER NOT NULL DEFAULT 1,
        order_date TEXT NOT NULL DEFAULT '', delivery_date TEXT NOT NULL DEFAULT '',
        return_option TEXT NOT NULL DEFAULT 'return', return_days INTEGER NOT NULL DEFAULT 0,
        return_deadline TEXT NOT NULL DEFAULT '', affiliate_link TEXT NOT NULL DEFAULT '',
        share_earn_link TEXT NOT NULL DEFAULT '', stage TEXT NOT NULL DEFAULT 'bought',
        return_id TEXT NOT NULL DEFAULT '', pickup_date TEXT NOT NULL DEFAULT '', return_fee_paise INTEGER NOT NULL DEFAULT 0,
        refund_status TEXT NOT NULL DEFAULT '', kept_reason TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '')""",
    """CREATE TABLE IF NOT EXISTS studio_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, store TEXT NOT NULL, label TEXT NOT NULL,
        whitelisted INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
        UNIQUE(store, label))""",
    """CREATE TABLE IF NOT EXISTS studio_reminders (
        purchase_id INTEGER NOT NULL, kind TEXT NOT NULL, sent_at TEXT NOT NULL, PRIMARY KEY (purchase_id, kind))""",
)


class StudioError(ValueError):
    pass


def _date(value: Any, field: str, required: bool = False) -> str:
    text = str(value or "").strip()[:10]
    if not text:
        if required:
            raise StudioError(f"{field} కావాలి / {field} is required")
        return ""
    try:
        return dt.date.fromisoformat(text).isoformat()
    except ValueError:
        raise StudioError(f"{field}: YYYY-MM-DD తేదీ పెట్టండి") from None


def _paise(value: Any, field: str) -> int:
    if value in (None, ""):
        return 0
    try:
        rupees = float(str(value).replace("₹", "").replace(",", "").strip())
    except ValueError:
        raise StudioError(f"{field}: సంఖ్య పెట్టండి") from None
    if rupees < 0 or rupees > 1_000_000:
        raise StudioError(f"{field}: 0 నుంచి 10 లక్షల మధ్య")
    return int(round(rupees * 100))


def deadline(delivery_date: str, return_option: str, return_days: int) -> str:
    """Last day to return = delivery + return days, only for 'return' (exchange / no return -> none)."""
    if return_option != "return" or not delivery_date or return_days <= 0:
        return ""
    return (dt.date.fromisoformat(delivery_date) + dt.timedelta(days=int(return_days))).isoformat()


def days_left(row: Dict[str, Any], today: dt.date) -> Optional[int]:
    if row.get("stage") in CLOSED or not row.get("return_deadline"):
        return None
    return (dt.date.fromisoformat(row["return_deadline"]) - today).days


def bucket(left: Optional[int]) -> str:
    """today (red; overdue too) / tomorrow (yellow) / time (green) / '' (no deadline)."""
    if left is None:
        return ""
    return "today" if left <= 0 else "tomorrow" if left == 1 else "time"


def warnings(row: Dict[str, Any]) -> List[str]:
    out = []
    if row.get("return_option") in ("exchange", "none"):
        out.append("keep")  # "ఇది ఉంచుకోవాల్సిందే"
    if row.get("account_label") and not row.get("account_whitelisted"):
        out.append("not_whitelisted")
    if row.get("return_option") == "return" and not row.get("delivery_date"):
        out.append("no_delivery_date")
    return out


def next_action(row: Dict[str, Any], left: Optional[int]) -> str:
    stage = row.get("stage")
    if stage in CLOSED:
        return ""
    if row.get("refund_status") in ("sent", "picked"):
        return "refund"
    if left is not None and left <= 1 and stage != "bought":
        return "return"
    return {"bought": "delivered", "delivered": "shot", "shot": "edited", "edited": "posted",
            "posted": "return" if row.get("return_option") == "return" else "keep"}.get(str(stage), "")


class StudioStore:
    def __init__(self, db_path: str, *, clock: Callable[[], dt.datetime] | None = None) -> None:
        self.db_path = db_path
        self.clock = clock or (lambda: dt.datetime.now(dt.timezone.utc))
        with self._connect() as conn:
            for sql in SCHEMA:
                conn.execute(sql)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    def now(self) -> str:
        return self.clock().astimezone(dt.timezone.utc).replace(microsecond=0).isoformat()

    def today(self) -> dt.date:
        return self.clock().astimezone(IST).date()

    # ---------------------------------------------------------------- accounts --
    def accounts(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM studio_accounts WHERE active=1 ORDER BY store, label").fetchall()]

    def save_account(self, store: str, label: str, whitelisted: bool) -> Dict[str, Any]:
        store, label = _store(store), str(label or "").strip()[:60]
        if not label:
            raise StudioError("అకౌంట్ పేరు / నంబర్ చివరి అంకెలు పెట్టండి")
        with self._connect() as conn:
            conn.execute("INSERT INTO studio_accounts(store,label,whitelisted,active,created_at) VALUES(?,?,?,1,?)"
                         " ON CONFLICT(store,label) DO UPDATE SET whitelisted=excluded.whitelisted, active=1",
                         (store, label, int(bool(whitelisted)), self.now()))
            row = conn.execute("SELECT * FROM studio_accounts WHERE store=? AND label=?", (store, label)).fetchone()
        return dict(row)

    def _account(self, account_id: Any) -> Optional[Dict[str, Any]]:
        if account_id in (None, ""):
            return None
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM studio_accounts WHERE id=?", (int(account_id),)).fetchone()
        return dict(row) if row else None

    # --------------------------------------------------------------- purchases --
    def create(self, data: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
        title = str(data.get("title") or "").strip()[:160]
        if not title:
            raise StudioError("ప్రోడక్ట్ పేరు పెట్టండి")
        store = _store(data.get("store"))
        option = str(data.get("return_option") or "return")
        if option not in RETURN_OPTIONS:
            raise StudioError("Return ఆప్షన్: return / exchange / none")
        days = int(data.get("return_days") or 0)
        if not 0 <= days <= 60:
            raise StudioError("Return రోజులు 0-60")
        pack = str(data.get("pack") or "single")
        if pack not in PACKS:
            raise StudioError("ప్యాక్: single / pair / combo")
        account = self._account(data.get("account_id"))
        delivery = _date(data.get("delivery_date"), "Delivery తేదీ")
        order_date = _date(data.get("order_date"), "ఆర్డర్ తేదీ") or min(delivery or "9999", self.today().isoformat())
        if delivery and delivery < order_date:
            raise StudioError("Delivery తేదీ ఆర్డర్ తేదీ కంటే ముందు ఉండకూడదు")
        row = {
            "created_at": self.now(), "updated_at": self.now(), "created_by": actor,
            "item_id": int(data["item_id"]) if str(data.get("item_id") or "").isdigit() else None,
            "title": title, "store": store,
            "account_id": account["id"] if account else None,
            "account_label": account["label"] if account else str(data.get("account_label") or "").strip()[:60],
            "account_whitelisted": int(bool(account and account["whitelisted"])),
            "paid_paise": _paise(data.get("paid"), "చెల్లించిన ధర"), "pack": pack,
            "pack_count": max(1, min(int(data.get("pack_count") or (2 if pack == "pair" else 1)), 50)),
            "order_date": order_date, "delivery_date": delivery, "return_option": option, "return_days": days,
            "return_deadline": deadline(delivery, option, days),
            "affiliate_link": _link(data.get("affiliate_link")), "share_earn_link": _link(data.get("share_earn_link")),
            "stage": "delivered" if delivery and delivery <= self.today().isoformat() else "bought",
            "notes": str(data.get("notes") or "").strip()[:500],
        }
        cols = ",".join(row)
        with self._connect() as conn:
            cur = conn.execute(f"INSERT INTO studio_purchases({cols}) VALUES({','.join('?' * len(row))})",
                               list(row.values()))
            new_id = cur.lastrowid
        return self.get(new_id)

    def get(self, purchase_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM studio_purchases WHERE id=?", (int(purchase_id),)).fetchone()
        return self._view(dict(row)) if row else None

    def _view(self, row: Dict[str, Any]) -> Dict[str, Any]:
        left = days_left(row, self.today())
        return {**row, "days_left": left, "bucket": bucket(left), "warnings": warnings(row),
                "next_action": next_action(row, left), "paid": row["paid_paise"] / 100,
                "return_fee": row["return_fee_paise"] / 100}

    def list(self, *, actor: Optional[str] = None, include_closed: bool = True) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM studio_purchases", []
        where = []
        if actor:
            where.append("created_by=?")
            args.append(actor)
        if not include_closed:
            where.append("stage NOT IN ('returned','kept')")
        if where:
            sql += " WHERE " + " AND ".join(where)
        with self._connect() as conn:
            rows = [self._view(dict(r)) for r in conn.execute(sql + " ORDER BY id DESC LIMIT 500", args).fetchall()]
        order = {"today": 0, "tomorrow": 1, "time": 2, "": 3}
        rows.sort(key=lambda r: (r["stage"] in CLOSED, order[r["bucket"]], r["days_left"] if r["days_left"] is not None
                                 else 999, -r["id"]))
        return rows

    def summary(self, rows: List[Dict[str, Any]]) -> Dict[str, Any]:
        open_rows = [r for r in rows if r["stage"] not in CLOSED]
        return {"today": sum(r["bucket"] == "today" for r in open_rows),
                "tomorrow": sum(r["bucket"] == "tomorrow" for r in open_rows),
                "time": sum(r["bucket"] == "time" for r in open_rows),
                "need_shoot": sum(r["stage"] in ("bought", "delivered") for r in open_rows),
                "need_post": sum(r["stage"] in ("shot", "edited") for r in open_rows),
                "returning": sum(r["refund_status"] in ("sent", "picked") for r in open_rows),
                "open": len(open_rows),
                "spent": sum(r["paid_paise"] for r in rows if r["stage"] == "kept") / 100
                + sum(r["return_fee_paise"] for r in rows) / 100}

    def _update(self, purchase_id: int, changes: Dict[str, Any]) -> Dict[str, Any]:
        changes = {**changes, "updated_at": self.now()}
        sets = ",".join(f"{k}=?" for k in changes)
        with self._connect() as conn:
            conn.execute(f"UPDATE studio_purchases SET {sets} WHERE id=?", [*changes.values(), int(purchase_id)])
        return self.get(purchase_id)

    def set_stage(self, purchase_id: int, stage: str, *, delivery_date: str = "") -> Dict[str, Any]:
        row = self._must(purchase_id)
        if stage not in STAGES:
            raise StudioError("Stage: " + " / ".join(STAGES))
        if STAGES.index(stage) < STAGES.index(row["stage"]):
            raise StudioError("వెనక్కి వెళ్లలేం / a stage only moves forward")
        changes: Dict[str, Any] = {"stage": stage}
        if stage == "delivered" or delivery_date:
            delivery = _date(delivery_date, "Delivery తేదీ") or row["delivery_date"] or self.today().isoformat()
            changes["delivery_date"] = delivery
            changes["return_deadline"] = deadline(delivery, row["return_option"], row["return_days"])
        return self._update(purchase_id, changes)

    def record_return(self, purchase_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
        row = self._must(purchase_id)
        state = str(data.get("refund_status") or row["refund_status"] or "sent")
        if state not in REFUND_STATES or not state:
            raise StudioError("Refund: sent / picked / refunded")
        if REFUND_STATES.index(state) < REFUND_STATES.index(row["refund_status"] or ""):
            raise StudioError("Refund స్థితి వెనక్కి వెళ్లదు")
        changes = {"refund_status": state,
                   "return_id": str(data.get("return_id") or row["return_id"]).strip()[:60],
                   "pickup_date": _date(data.get("pickup_date"), "Pickup తేదీ") or row["pickup_date"],
                   "return_fee_paise": _paise(data.get("fee"), "Return ఫీజు") if data.get("fee") not in (None, "")
                   else row["return_fee_paise"]}
        if state == "refunded":
            changes["stage"] = "returned"
        return self._update(purchase_id, changes)

    def keep(self, purchase_id: int, reason: str) -> Dict[str, Any]:
        self._must(purchase_id)
        return self._update(purchase_id, {"stage": "kept", "kept_reason": str(reason or "studio").strip()[:120]})

    def _must(self, purchase_id: int) -> Dict[str, Any]:
        row = self.get(purchase_id)
        if not row:
            raise LookupError("Purchase not found")
        if row["stage"] in CLOSED:
            raise StudioError("ఇది ఇప్పటికే మూసేశాం (returned / kept)")
        return row

    # --------------------------------------------------------------- reminders --
    def due_reminders(self) -> List[Dict[str, Any]]:
        """Reminders to send now, each kind once per purchase: the day before the deadline, the deadline morning
        (from 08:00 IST), "not shot yet" two days before, "send the return" when posted with <= 1 day left."""
        now_ist = self.clock().astimezone(IST)
        out = []
        for row in self.list(include_closed=False):
            left = row["days_left"]
            if left is None or row["refund_status"] in ("sent", "picked", "refunded"):
                continue
            kinds = []
            if left == 1:
                kinds.append("d1")
            if left <= 0 and now_ist.hour >= 8:
                kinds.append("d0")
            if left <= 2 and row["stage"] in ("bought", "delivered"):
                kinds.append("not_shot")
            if left <= 1 and row["stage"] == "posted":
                kinds.append("send_return")
            for kind in kinds:
                out.append({"purchase": row, "kind": kind})
        return out

    def mark_sent(self, purchase_id: int, kind: str) -> bool:
        with self._connect() as conn:
            cur = conn.execute("INSERT OR IGNORE INTO studio_reminders(purchase_id,kind,sent_at) VALUES(?,?,?)",
                               (int(purchase_id), kind, self.now()))
            return cur.rowcount == 1


def reminder_text(row: Dict[str, Any], kind: str) -> Dict[str, str]:
    name = str(row.get("title") or "ప్రోడక్ట్")[:50]
    store = row.get("store") or "store"
    return {
        "d1": {"title": f"రేపు return ఆఖరు: {name}", "body": f"{store} return గడువు రేపు. షూట్ / పోస్ట్ ఈరోజే ముగించండి."},
        "d0": {"title": f"ఈరోజే return ఆఖరు: {name}",
               "body": f"{store} యాప్‌లో return బుక్ చేసి, Studio లో \"పంపాను\" నొక్కండి."},
        "not_shot": {"title": f"ఇంకా షూట్ చేయలేదు: {name}", "body": "Return గడువు దగ్గర పడింది. ఈరోజే షూట్ చేయండి."},
        "send_return": {"title": f"Return పంపండి: {name}", "body": "పోస్ట్ అయింది. గడువులోపు return బుక్ చేయండి."},
    }[kind]


def _store(value: Any) -> str:
    text = str(value or "").strip()
    for name in STORES:
        if text.lower() == name.lower():
            return name
    if not text:
        raise StudioError("Store ఎంచుకోండి")
    return text[:30]


def _link(value: Any) -> str:
    text = str(value or "").strip()[:500]
    if text and not text.startswith("https://"):
        raise StudioError("లింక్ https:// తో మొదలవ్వాలి")
    return text


def dumps(rows: Any) -> str:
    return json.dumps(rows, ensure_ascii=False)
