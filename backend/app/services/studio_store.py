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
    """CREATE TABLE IF NOT EXISTS studio_voice_cache (
        key TEXT PRIMARY KEY, path TEXT NOT NULL, provider TEXT NOT NULL, text TEXT NOT NULL, created_at TEXT NOT NULL)""",
    """CREATE TABLE IF NOT EXISTS studio_earnings (
        id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
        month TEXT NOT NULL, orders INTEGER NOT NULL DEFAULT 0, returns INTEGER NOT NULL DEFAULT 0,
        confirmed_paise INTEGER NOT NULL DEFAULT 0, pending_paise INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
        updated_by TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(purchase_id, source, month))""",
    """CREATE TABLE IF NOT EXISTS studio_unlocks (
        key TEXT PRIMARY KEY, value REAL NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', updated_by TEXT NOT NULL,
        updated_at TEXT NOT NULL)""",
    """CREATE TABLE IF NOT EXISTS studio_reminders (
        purchase_id INTEGER NOT NULL, kind TEXT NOT NULL, sent_at TEXT NOT NULL, PRIMARY KEY (purchase_id, kind))""",
)


# Round 2 (shoot -> ASKODOX edit -> checklist -> posts). Added with ALTER TABLE, never by recreating the table.
MIGRATIONS = (
    ("video_file", "TEXT NOT NULL DEFAULT ''"), ("video_seconds", "REAL NOT NULL DEFAULT 0"),
    ("edited_file", "TEXT NOT NULL DEFAULT ''"), ("edit_status", "TEXT NOT NULL DEFAULT ''"),
    ("edit_reason", "TEXT NOT NULL DEFAULT ''"), ("edit_options", "TEXT NOT NULL DEFAULT '{}'"),
    ("show_price_paise", "INTEGER NOT NULL DEFAULT 0"), ("checks", "TEXT NOT NULL DEFAULT '{}'"),
    ("posts", "TEXT NOT NULL DEFAULT '{}'"), ("published_at", "TEXT NOT NULL DEFAULT ''"),
    ("voice_paise", "INTEGER NOT NULL DEFAULT 0"),  # round 3: what the new voice lines cost
)
# Round 3 (owner 2026-11-21): Studio spec 10 -- unlock targets, numbers typed by the owner.
UNLOCKS = (
    {"key": "meesho_whitelisted", "store": "Meesho", "label": "Meesho: whitelisted (lifetime)", "target": 1, "kind": "yes"},
    {"key": "flipkart_exclusive_posts", "store": "Flipkart", "label": "Flipkart: 1 exclusive post", "target": 1,
     "kind": "count"},
    {"key": "myntra_sales_6m", "store": "Myntra", "label": "Myntra: 6 నెలల్లో 10,000 sales", "target": 10000,
     "kind": "count"},
    {"key": "wishlink_non_meesho_sales", "store": "Wishlink", "label": "Wishlink sourcing: ₹2.5 లక్షల non-Meesho sales",
     "target": 250000, "kind": "rupees"},
    {"key": "wishlink_non_meesho_content", "store": "Wishlink", "label": "Wishlink sourcing: 5 non-Meesho content",
     "target": 5, "kind": "count"},
)
SOURCES = ("Wishlink", "Meesho Creator Club", "Flipkart", "Myntra", "Amazon", "EarnKaro", "GrabCash", "Other")
JSON_FIELDS = ("edit_options", "checks", "posts")
PLATFORMS = ("instagram", "facebook", "youtube", "whatsapp")


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
            have = {r[1] for r in conn.execute("PRAGMA table_info(studio_purchases)").fetchall()}
            for column, kind in MIGRATIONS:
                if column not in have:
                    conn.execute(f"ALTER TABLE studio_purchases ADD COLUMN {column} {kind}")

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
        for key in JSON_FIELDS:
            try:
                row[key] = json.loads(row.get(key) or "{}")
            except ValueError:
                row[key] = {}
        row["show_price"] = (row.get("show_price_paise") or 0) / 100
        row["voice_cost"] = (row.get("voice_paise") or 0) / 100
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
        changes = {**{k: (json.dumps(v, ensure_ascii=False) if k in JSON_FIELDS else v) for k, v in changes.items()},
                   "updated_at": self.now()}
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

    # ------------------------------------------------------ round 2: video --
    def set_video(self, purchase_id: int, name: str, seconds: float) -> Dict[str, Any]:
        row = self._must(purchase_id)
        changes: Dict[str, Any] = {"video_file": name, "video_seconds": round(float(seconds), 1),
                                   "edited_file": "", "edit_status": "", "edit_reason": "", "published_at": ""}
        if STAGES.index(row["stage"]) < STAGES.index("shot"):
            changes["stage"] = "shot"
            if not row["delivery_date"]:
                changes["delivery_date"] = self.today().isoformat()
                changes["return_deadline"] = deadline(changes["delivery_date"], row["return_option"], row["return_days"])
        return self._update(purchase_id, changes)

    def set_edit(self, purchase_id: int, *, status: str, options: Optional[Dict[str, Any]] = None, edited: str = "",
                 reason: str = "") -> Dict[str, Any]:
        row = self.get(purchase_id)
        if not row:
            raise LookupError("Purchase not found")
        changes: Dict[str, Any] = {"edit_status": status, "edit_reason": reason[:120], "published_at": ""}
        if options is not None:
            changes["edit_options"] = options
        if edited:
            changes["edited_file"] = edited
        if status == "READY" and row["stage"] in ("bought", "delivered", "shot"):
            changes["stage"] = "edited"
        return self._update(purchase_id, changes)

    def set_checks(self, purchase_id: int, ticks: Dict[str, Any], show_price: Any = None) -> Dict[str, Any]:
        row = self._must(purchase_id)
        checks = dict(row["checks"])
        for key, value in ticks.items():
            checks[str(key)[:40]] = bool(value)
        changes: Dict[str, Any] = {"checks": checks}
        if show_price not in (None, ""):
            paise = _paise(show_price, "ఈరోజు ధర")
            if paise <= 0:
                raise StudioError("ఈరోజు యాప్‌లో ఉన్న ధర పెట్టండి")
            changes["show_price_paise"] = paise
            checks["price_checked_on"] = self.today().isoformat()  # the tick is valid for TODAY only
            if row["show_price_paise"] and paise != row["show_price_paise"] and row["edited_file"]:
                changes["edit_status"] = "PRICE_CHANGED"  # the video says the old price -> make it again
        return self._update(purchase_id, changes)

    def mark_published(self, purchase_id: int) -> Dict[str, Any]:
        self._must(purchase_id)
        return self._update(purchase_id, {"published_at": self.now()})

    def add_post(self, purchase_id: int, platform: str, url: str) -> Dict[str, Any]:
        row = self._must(purchase_id)
        if platform not in PLATFORMS:
            raise StudioError("Platform: " + " / ".join(PLATFORMS))
        if not row["published_at"]:
            raise StudioError("ముందు Publish checklist పూర్తి చేయండి")
        link = str(url or "").strip()[:500]
        if platform != "whatsapp" and not link.startswith("https://"):
            raise StudioError("Post లింక్ https:// తో పెట్టండి")
        posts = dict(row["posts"])
        posts[platform] = {"url": link, "at": self.now()}
        changes: Dict[str, Any] = {"posts": posts}
        if STAGES.index(row["stage"]) < STAGES.index("posted"):
            changes["stage"] = "posted"
        return self._update(purchase_id, changes)

    # ------------------------------------------------------ round 3: money --
    def add_voice_cost(self, purchase_id: int, paise: int) -> None:
        if paise > 0:
            with self._connect() as conn:
                conn.execute("UPDATE studio_purchases SET voice_paise=voice_paise+? WHERE id=?", (int(paise), int(purchase_id)))

    def save_earning(self, data: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
        """One row per (product, source, month) -- typing again for the same month replaces it (dashboards update)."""
        source = str(data.get("source") or "").strip()
        match = next((s for s in SOURCES if s.lower() == source.lower()), None)
        if not match:
            raise StudioError("Source: " + " / ".join(SOURCES))
        month = str(data.get("month") or self.today().strftime("%Y-%m"))[:7]
        try:
            dt.date.fromisoformat(month + "-01")
        except ValueError:
            raise StudioError("నెల: YYYY-MM") from None
        purchase_id = int(data.get("purchase_id") or 0)
        if purchase_id and not self.get(purchase_id):
            raise LookupError("Purchase not found")
        counts = []
        for field in ("orders", "returns"):
            try:
                value = int(data.get(field) or 0)
            except (TypeError, ValueError):
                raise StudioError(f"{field}: సంఖ్య") from None
            if not 0 <= value <= 1_000_000:
                raise StudioError(f"{field}: 0 లేదా ఎక్కువ")
            counts.append(value)
        row = (purchase_id, match, month, counts[0], counts[1], _paise(data.get("confirmed"), "Confirm కమిషన్"),
               _paise(data.get("pending"), "Pending కమిషన్"), str(data.get("note") or "").strip()[:200], actor, self.now())
        with self._connect() as conn:
            conn.execute("INSERT INTO studio_earnings(purchase_id,source,month,orders,returns,confirmed_paise,pending_paise,"
                         "note,updated_by,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(purchase_id,source,month) DO "
                         "UPDATE SET orders=excluded.orders, returns=excluded.returns, confirmed_paise=excluded.confirmed_paise,"
                         " pending_paise=excluded.pending_paise, note=excluded.note, updated_by=excluded.updated_by,"
                         " updated_at=excluded.updated_at", row)
            got = conn.execute("SELECT * FROM studio_earnings WHERE purchase_id=? AND source=? AND month=?",
                               (purchase_id, match, month)).fetchone()
        return dict(got)

    def earnings(self, month: Optional[str] = None) -> List[Dict[str, Any]]:
        sql, args = "SELECT * FROM studio_earnings", []
        if month:
            sql += " WHERE month=?"
            args.append(month)
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(sql + " ORDER BY month DESC, id DESC", args).fetchall()]

    def money(self, month: str, *, actor: Optional[str] = None) -> Dict[str, Any]:
        """Studio spec 9: per product cost (kept + return fee + voice), orders, returns, commission; the month's
        confirmed / pending / cost / profit (nothing of ASKODOX's own investment); best kinds. Staff: own only."""
        from app.services.studio_video import product_kind  # local: studio_video imports nothing from here

        dt.date.fromisoformat(str(month)[:7] + "-01")  # ValueError on a bad month
        rows = self.list(actor=actor)
        mine = {r["id"] for r in rows}
        earn = [e for e in self.earnings(month) if actor is None or e["purchase_id"] in mine]
        by_purchase: Dict[int, Dict[str, int]] = {}
        for e in earn:
            agg = by_purchase.setdefault(e["purchase_id"], {"orders": 0, "returns": 0, "confirmed": 0, "pending": 0})
            agg["orders"] += e["orders"]
            agg["returns"] += e["returns"]
            agg["confirmed"] += e["confirmed_paise"]
            agg["pending"] += e["pending_paise"]
        products, kinds = [], {}
        cost_total = stuck = 0
        for r in rows:
            in_month = (r["order_date"] or r["created_at"][:10])[:7] == month
            e = by_purchase.get(r["id"], {"orders": 0, "returns": 0, "confirmed": 0, "pending": 0})
            cost = (r["paid_paise"] if r["stage"] == "kept" else 0) + r["return_fee_paise"] + r["voice_paise"]
            if in_month:
                cost_total += cost
                if r["stage"] not in CLOSED or r["refund_status"] in ("sent", "picked"):
                    stuck += r["paid_paise"]  # paid, refund not back yet
            if not in_month and not any(e.values()):
                continue
            kind = product_kind(r["title"])
            k = kinds.setdefault(kind, {"kind": kind, "orders": 0, "confirmed": 0, "products": 0})
            k["orders"] += e["orders"]
            k["confirmed"] += e["confirmed"]
            k["products"] += 1
            products.append({"id": r["id"], "title": r["title"], "store": r["store"], "kind": kind,
                             "created_by": r["created_by"], "stage": r["stage"], "cost": cost / 100,
                             "orders": e["orders"], "returns": e["returns"], "confirmed": e["confirmed"] / 100,
                             "pending": e["pending"] / 100, "profit": (e["confirmed"] - (cost if in_month else 0)) / 100})
        general = [e for e in earn if not e["purchase_id"]]
        confirmed = sum(e["confirmed_paise"] for e in earn)
        pending = sum(e["pending_paise"] for e in earn)
        best = sorted(kinds.values(), key=lambda k: (-k["orders"], -k["confirmed"], k["kind"]))
        last = max((e["updated_at"] for e in self.earnings()), default="")
        return {"month": month, "products": products,
                "general": [{**g, "confirmed": g["confirmed_paise"] / 100, "pending": g["pending_paise"] / 100}
                            for g in general],
                "totals": {"confirmed": confirmed / 100, "pending": pending / 100, "cost": cost_total / 100,
                           "profit": (confirmed - cost_total) / 100, "stuck": stuck / 100,
                           "orders": sum(e["orders"] for e in earn), "returns": sum(e["returns"] for e in earn)},
                "best_kinds": [{**k, "confirmed": k["confirmed"] / 100} for k in best], "last_entry": last}

    def unlocks(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            saved = {r["key"]: dict(r) for r in conn.execute("SELECT * FROM studio_unlocks").fetchall()}
        posted_non_meesho = sum(1 for r in self.list() if r["store"] != "Meesho" and r["posts"])
        out = []
        for u in UNLOCKS:
            got = saved.get(u["key"], {})
            value = float(got.get("value") or 0)
            out.append({**u, "value": value, "note": got.get("note") or "", "updated_at": got.get("updated_at") or "",
                        "percent": min(100, round(100 * value / u["target"])) if u["target"] else 0,
                        "done": value >= u["target"],
                        "hint": (f"Studio లో non-Meesho పోస్ట్‌లు: {posted_non_meesho}"
                                 if u["key"] == "wishlink_non_meesho_content" else "")})
        return out

    def save_unlock(self, key: str, value: Any, note: str, *, actor: str) -> Dict[str, Any]:
        if key not in {u["key"] for u in UNLOCKS}:
            raise StudioError("Unknown unlock")
        try:
            number = float(str(value).replace(",", "").replace("₹", "").strip() or 0)
        except ValueError:
            raise StudioError("సంఖ్య పెట్టండి") from None
        if number < 0:
            raise StudioError("0 లేదా ఎక్కువ")
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO studio_unlocks(key,value,note,updated_by,updated_at) VALUES(?,?,?,?,?)",
                         (key, number, str(note or "").strip()[:200], actor, self.now()))
        return next(u for u in self.unlocks() if u["key"] == key)

    def weekly_commission_due(self) -> Optional[str]:
        """Monday from 10:00 IST: the week key when this week's commission reminder has not gone yet."""
        now = self.clock().astimezone(IST)
        if now.weekday() != 0 or now.hour < 10:
            return None
        year, week, _ = now.isocalendar()
        return f"{year}-W{week:02d}"

    def published_by_file(self, name: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT id FROM studio_purchases WHERE edited_file=? AND published_at!=''", (name,)).fetchone()
        return self.get(row["id"]) if row else None

    def voice_cached(self, key: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM studio_voice_cache WHERE key=?", (key,)).fetchone()
        return dict(row) if row else None

    def voice_store(self, key: str, path: str, provider: str, text: str) -> None:
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO studio_voice_cache(key,path,provider,text,created_at) VALUES(?,?,?,?,?)",
                         (key, path, provider, text[:300], self.now()))

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
