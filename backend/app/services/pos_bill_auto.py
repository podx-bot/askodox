"""Bills ASKODOX sends by itself (owner 2026-11-27) -- the paid automatic option next to the owner's free manual send.

A bill goes out on its own only when ALL hold: staff switched ``bills.auto_send`` on, the approved bill template is
configured, the shop OWNER switched "send by itself" on for his shop (the same switch as the baaki reminders), the
bill has a customer number and is under a day old, and the owner's AI Credits pay one ``shop_message``.

* A customer who uses ASKODOX gets the bill in "My bills" + a push: free, never charged.
* Anyone else gets the approved WhatsApp template from ASKODOX's own number: ONE price, taken from the OWNER's credits.
* Too few credits -> nothing is sent; the owner still sends it himself (free, his own WhatsApp).
* A refused send is given back; every bill is tried once (no loop of failures), the owner's manual send stays.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import timedelta
from typing import Any, Callable, Dict, List, Optional, Tuple

from app.services import shop_messages
from app.services.account_identity import phone_key

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_bill_auto (invoice_id TEXT PRIMARY KEY, business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " outcome TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_bill_auto_days (business_id TEXT NOT NULL, day TEXT NOT NULL,"
    " sent INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (business_id, day))",
]
WINDOW_HOURS = 24


def _rupees(paise: int) -> str:
    return f"₹{paise // 100}" if paise % 100 == 0 else f"₹{paise / 100:.2f}"


class PosBillAuto:
    def __init__(self, store: Any, bills: Any, follow: Any, *,
                 whatsapp: Optional[Callable[[str, List[str]], Tuple[bool, str]]] = None,
                 auto: Optional[Callable[[], Dict[str, Any]]] = None, credits: Any = None, base_url: str = "") -> None:
        self.store, self.bills, self.follow = store, bills, follow
        self.whatsapp = whatsapp
        self.auto = auto or (lambda: {"enabled": False, "daily": 0})
        self.credits = credits
        self.base_url = base_url
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def run(self) -> Dict[str, int]:
        try:
            state = self.auto()
        except Exception:
            state = {}
        if self.whatsapp is None or not state.get("enabled"):
            return {"bills": 0, "sent": 0, "in_app": 0, "kept_for_owner": 0}
        daily = int(state.get("daily") or 0)
        now = self.follow.clock()
        today = self.follow._today()
        since = (now - timedelta(hours=WINDOW_HOURS)).isoformat()
        with self.store._connect() as conn:
            invoices = conn.execute(
                "SELECT i.* FROM pos_invoices i WHERE i.status = 'issued' AND i.issued_at >= ? AND NOT EXISTS"
                " (SELECT 1 FROM pos_bill_auto a WHERE a.invoice_id = i.id) ORDER BY i.issued_at LIMIT 500",
                (since,)).fetchall()
        sent = in_app = kept = 0
        for inv in invoices:
            business_id = inv["business_id"]
            with self.store._tx() as conn:
                if not self.follow._auto_on(conn, business_id):
                    continue  # the owner never switched it on: his own manual send only
                phone = self.follow._phone_of(conn, inv)
                key = phone_key(phone) if phone else ""
                if len(key) < 10:
                    continue
                biz = self.store._business_row(conn, business_id)
                owner = str(biz["owner_user_id"] or "")
                on_askodox = bool(self.bills._account_user(conn, key))
                row = conn.execute("SELECT sent FROM pos_bill_auto_days WHERE business_id = ? AND day = ?",
                                   (business_id, today)).fetchone()
                over_cap = daily <= 0 or (row is not None and row["sent"] >= daily)
                try:
                    name = json.loads(inv["customer_snapshot"] or "{}").get("name") or ""
                except (TypeError, ValueError):
                    name = ""
                total = int(json.loads(inv["totals"]).get("grand_total_paise") or 0)
            if on_askodox:  # in-app + push: free for the shop, never a charge
                try:
                    self.bills.send(business_id, owner, inv["id"], phone, base_url=self.base_url)
                    self._mark(business_id, inv["id"], today, "in_app", count=False)
                    in_app += 1
                except Exception as problem:
                    print(f"ASKODOX BILL AUTO in_app failed shop={business_id} error={type(problem).__name__}", flush=True)
                continue
            if over_cap:
                kept += 1
                continue
            ref = f"shopmsg:bill:{inv['id']}"
            if not shop_messages.charge(self.credits, owner, ref):
                self._mark(business_id, inv["id"], today, "no_credits", count=False)
                kept += 1
                continue
            try:
                shared = self.bills.send(business_id, owner, inv["id"], phone, base_url=self.base_url)
                ok, error = self.whatsapp(phone, [name or "కస్టమర్", str(biz["name"]), str(inv["number"]),
                                                  _rupees(total), shared["url"]])
            except Exception as problem:
                ok, error = False, type(problem).__name__
            if not ok:
                shop_messages.give_back(self.credits, owner, ref)
                print(f"ASKODOX BILL AUTO failed shop={business_id} bill={inv['id']} error={str(error)[:120]}", flush=True)
                self._mark(business_id, inv["id"], today, "failed", count=False)
                kept += 1
                continue
            self._mark(business_id, inv["id"], today, "sent", count=True)
            sent += 1
        return {"bills": len(invoices), "sent": sent, "in_app": in_app, "kept_for_owner": kept}

    def _mark(self, business_id: str, invoice_id: str, day: str, outcome: str, *, count: bool) -> None:
        with self.store._tx() as conn:
            try:
                conn.execute("INSERT INTO pos_bill_auto (invoice_id, business_id, day, outcome) VALUES (?, ?, ?, ?)",
                             (invoice_id, business_id, day, outcome))
            except sqlite3.IntegrityError:
                return
            if count:
                conn.execute("INSERT INTO pos_bill_auto_days (business_id, day, sent) VALUES (?, ?, 1)"
                             " ON CONFLICT(business_id, day) DO UPDATE SET sent = sent + 1", (business_id, day))


def auto_bill_whatsapp(container: Any) -> Tuple[Optional[Callable[[str, List[str]], Tuple[bool, str]]],
                                                 Callable[[], Dict[str, Any]], str]:
    """(sender, state, base url) for the automatic bill message; sender is None until staff configured the approved
    bill template (``whatsapp_cloud`` ``bill_template_name``, five body values: customer, shop, bill no, amount, link)."""
    from app.services import comms, platform_settings
    from app.services.otp_delivery import _registry

    def state() -> Dict[str, Any]:
        return {"enabled": platform_settings.get("bills.auto_send") >= 1,
                "daily": int(platform_settings.get("bills.auto_daily_per_shop"))}

    base = str(getattr(getattr(container, "settings", None), "public_base_url", "") or "").rstrip("/")
    reg = _registry(container)
    try:
        template = reg.config_value("whatsapp_cloud", "bill_template_name") if reg is not None else ""
        ready = bool(template and reg.config_value("whatsapp_cloud", "phone_number_id")
                     and reg.secret("whatsapp_cloud", "access_token"))
    except Exception:
        template, ready = "", False
    if not ready:
        return None, state, base
    http = getattr(container, "comms_http", None) or comms.default_http

    def send(phone: str, values: List[str]) -> Tuple[bool, str]:
        from app.services.pos_bills import whatsapp_number

        ok, _mid, error = comms.send_whatsapp_named_template(reg, http, whatsapp_number(phone), template, values)
        return ok, error

    return send, state, base
