"""Reports & analytics for any business (owner 2026-11-18): one day, the last 7 / 30 days, and the night report.

Everything is read from the shop's OWN rows (bills, payments, desk orders + their steps, table calls, attendance,
tasks, cashbook, reviews) -- nothing is estimated or invented. Each problem carries:
  - what happened (counted), why (which rows show it), and one suggestion (fixed rule text, en + te).
The day gets a face (good / ok / bad) from the same counts, so a person who cannot read still sees how the day went.

Night report: a background job sends ONE push per shop per day to the owner and everyone with the ``reports``
permission (default just after midnight for the day that ended; the owner can change the time or switch it off).
"""

from __future__ import annotations

import json
from datetime import date as Date, datetime, timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PERMISSIONS, PosError, PosStore

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS pos_report_settings (business_id TEXT PRIMARY KEY, night_push INTEGER NOT NULL DEFAULT 1,"
    " send_time TEXT NOT NULL DEFAULT '00:00', updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_report_sends (business_id TEXT NOT NULL, local_date TEXT NOT NULL, sent_at TEXT NOT NULL,"
    " pushed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (business_id, local_date))",
)

SLOW_ACCEPT_MIN = 5      # an order nobody accepted for this long
SLOW_READY_MIN = 25      # placed -> ready
REPEAT_CALLS = 3         # one table asking this many times for one order
SLOW_CALL_MIN = 5        # a table request answered after this long
DROP_PCT = 20            # sales below the same weekday last week by this much


def _ist(value: Any) -> Optional[datetime]:
    try:
        t = datetime.fromisoformat(str(value))
    except (TypeError, ValueError):
        return None
    if t.tzinfo is None:
        t = t.replace(tzinfo=IST)
    return t.astimezone(IST)


def _minutes(a: Any, b: Any) -> Optional[float]:
    ta, tb = _ist(a), _ist(b)
    if ta is None or tb is None:
        return None
    return max(0.0, (tb - ta).total_seconds() / 60)


def _grand(totals: str) -> int:
    try:
        return int(json.loads(totals or "{}").get("grand_total_paise") or 0)
    except (TypeError, ValueError):
        return 0


def _name(snapshot: str) -> str:
    try:
        return str(json.loads(snapshot or "{}").get("name") or "").strip()
    except (TypeError, ValueError):
        return ""


def _rupees(paise: int) -> str:
    return f"₹{paise / 100:,.0f}"


def _problem(key: str, level: str, count: int, en: str, te: str, why_en: str, why_te: str, do_en: str, do_te: str,
             page: str) -> Dict[str, Any]:
    return {"key": key, "level": level, "count": count, "text_en": en, "text_te": te, "why_en": why_en, "why_te": why_te,
            "do_en": do_en, "do_te": do_te, "page": page}


class PosReports:
    def __init__(self, store: PosStore, notify: Optional[Callable[..., Any]] = None) -> None:
        self.store = store
        self.notify = notify
        with store._connect() as conn:
            for stmt in SCHEMA:
                conn.execute(stmt)

    # ------------------------------------------------------------------ reading helpers
    @staticmethod
    def _rows(conn, sql: str, args: tuple) -> List[Any]:
        try:
            return conn.execute(sql, args).fetchall()
        except Exception:  # that feature's table does not exist yet for this install
            return []

    def _sales(self, conn, business_id: str, start: str, end: str) -> List[Any]:
        return [r for r in self._rows(conn, "SELECT id, issued_at, local_date, totals, customer_id, customer_snapshot,"
                                            " created_by, balance_paise, status FROM pos_invoices WHERE business_id = ?"
                                            " AND doc_kind = 'invoice' AND local_date BETWEEN ? AND ?",
                                      (business_id, start, end)) if r["status"] != "cancelled"]

    def _items(self, conn, invoice_ids: List[str]) -> Dict[str, Dict[str, Any]]:
        out: Dict[str, Dict[str, Any]] = {}
        for i in range(0, len(invoice_ids), 400):
            chunk = invoice_ids[i:i + 400]
            marks = ",".join("?" * len(chunk))
            for r in self._rows(conn, f"SELECT product_id, name, qty_milli, total_paise FROM pos_invoice_lines"
                                      f" WHERE invoice_id IN ({marks})", tuple(chunk)):
                key = r["product_id"] or r["name"]
                row = out.setdefault(key, {"product_id": r["product_id"], "name": r["name"], "qty": 0.0, "paise": 0})
                row["qty"] += (r["qty_milli"] or 0) / 1000
                row["paise"] += int(r["total_paise"] or 0)
        return out

    def _labels(self, conn, business_id: str) -> Dict[str, str]:
        out: Dict[str, str] = {}
        owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        if owner:
            out[owner["owner_user_id"]] = "Owner"
        for r in self._rows(conn, "SELECT app_user_id, label, phone_key FROM pos_members WHERE business_id = ?", (business_id,)):
            if r["app_user_id"] and r["app_user_id"] not in out:
                out[r["app_user_id"]] = (r["label"] or "").strip() or f"••{str(r['phone_key'])[-4:]}"
        return out

    # ------------------------------------------------------------------ one day
    def day(self, business_id: str, user: str, date: str = "") -> Dict[str, Any]:
        try:
            day = Date.fromisoformat(date) if date else datetime.now(IST).date()
        except ValueError as exc:
            raise PosError(400, "date", "Date must be YYYY-MM-DD.") from exc
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            return self._day(conn, business_id, day)

    def _day(self, conn, business_id: str, day: Date) -> Dict[str, Any]:
        d = day.isoformat()
        bills = self._sales(conn, business_id, d, d)
        paise = sum(_grand(r["totals"]) for r in bills)
        last_week = day - timedelta(days=7)
        lw = sum(_grand(r["totals"]) for r in self._sales(conn, business_id, last_week.isoformat(), last_week.isoformat()))
        yday = day - timedelta(days=1)
        yd = sum(_grand(r["totals"]) for r in self._sales(conn, business_id, yday.isoformat(), yday.isoformat()))
        change = round((paise - lw) * 100 / lw) if lw else None

        # busy hours
        hours = [{"hour": h, "bills": 0, "paise": 0} for h in range(24)]
        for r in bills:
            t = _ist(r["issued_at"])
            if t:
                hours[t.hour]["bills"] += 1
                hours[t.hour]["paise"] += _grand(r["totals"])
        peak = max(hours, key=lambda x: (x["bills"], x["paise"])) if bills else None

        # money
        cash = online = refunds = 0
        for r in self._rows(conn, "SELECT method, amount_paise, kind FROM pos_payments WHERE business_id = ? AND local_date = ?",
                            (business_id, d)):
            if r["kind"] == "refund":
                refunds += r["amount_paise"]
            elif r["method"] == "cash":
                cash += r["amount_paise"]
            else:
                online += r["amount_paise"]
        spent: Dict[str, int] = {}
        other_in = 0
        for r in self._rows(conn, "SELECT kind, category, amount_paise FROM pos_cashbook WHERE business_id = ? AND local_date = ?"
                                  " AND removed_at IS NULL", (business_id, d)):
            if r["kind"] == "expense":
                spent[r["category"] or "other"] = spent.get(r["category"] or "other", 0) + r["amount_paise"]
            else:
                other_in += r["amount_paise"]
        new_dues = sum(int(r["balance_paise"] or 0) for r in bills)
        expense = sum(spent.values())
        money = {"cash_paise": cash, "online_paise": online, "refund_paise": refunds, "other_in_paise": other_in,
                 "expense_paise": expense, "expense_by_category": spent, "new_dues_paise": new_dues,
                 "left_paise": cash + online + other_in - refunds - expense}

        # items
        items = self._items(conn, [r["id"] for r in bills])
        top = sorted(items.values(), key=lambda x: (-x["paise"], x["name"]))[:8]
        week_ids = [r["id"] for r in self._sales(conn, business_id, (day - timedelta(days=6)).isoformat(), d)]
        sold_week = {k for k in self._items(conn, week_ids)}
        not_selling = [{"product_id": r["id"], "name": r["name"]}
                       for r in self._rows(conn, "SELECT id, name FROM pos_products WHERE business_id = ? AND active = 1"
                                                 " ORDER BY name", (business_id,))
                       if r["id"] not in sold_week and r["name"] not in sold_week][:12]

        # customers
        seen_before = set()
        ids = [r["customer_id"] for r in bills if r["customer_id"]]
        for i in range(0, len(ids), 400):
            chunk = ids[i:i + 400]
            for r in self._rows(conn, f"SELECT DISTINCT customer_id FROM pos_invoices WHERE business_id = ? AND local_date < ?"
                                      f" AND customer_id IN ({','.join('?' * len(chunk))})", (business_id, d, *chunk)):
                seen_before.add(r["customer_id"])
        by_customer: Dict[str, Dict[str, Any]] = {}
        for r in bills:
            if not r["customer_id"]:
                continue
            c = by_customer.setdefault(r["customer_id"], {"name": _name(r["customer_snapshot"]) or "—", "bills": 0,
                                                          "paise": 0, "new": r["customer_id"] not in seen_before})
            c["bills"] += 1
            c["paise"] += _grand(r["totals"])
        customers = {"named": len(by_customer), "walk_in": sum(1 for r in bills if not r["customer_id"]),
                     "new": sum(1 for c in by_customer.values() if c["new"]),
                     "returning": sum(1 for c in by_customer.values() if not c["new"]),
                     "top": sorted(by_customer.values(), key=lambda x: -x["paise"])[:5]}

        # orders + table calls
        orders = self._rows(conn, "SELECT id, source, kind, table_id, stage, reason, placed_at FROM pos_desk_orders"
                                  " WHERE business_id = ? AND substr(placed_at, 1, 10) BETWEEN ? AND ?",
                            (business_id, (day - timedelta(days=1)).isoformat(), d))
        orders = [o for o in orders if (_ist(o["placed_at"]) or datetime.min.replace(tzinfo=IST)).date() == day]
        steps: Dict[str, Dict[str, str]] = {}
        for o in orders:
            for e in self._rows(conn, "SELECT stage, at FROM pos_desk_events WHERE order_id = ? ORDER BY id", (o["id"],)):
                steps.setdefault(o["id"], {}).setdefault(e["stage"], e["at"])
        tables = {r["id"]: r["name"] for r in self._rows(conn, "SELECT id, name FROM pos_tables WHERE business_id = ?",
                                                          (business_id,))}
        accept, ready, slow_accept, slow_ready, lost = [], [], [], [], []
        for o in orders:
            s = steps.get(o["id"], {})
            a = _minutes(o["placed_at"], s.get("accepted")) if s.get("accepted") else None
            r = _minutes(o["placed_at"], s.get("ready")) if s.get("ready") else None
            label = tables.get(o["table_id"] or "", "") or o["kind"]
            if a is not None:
                accept.append(a)
                if a > SLOW_ACCEPT_MIN:
                    slow_accept.append({"order_id": o["id"], "where": label, "minutes": round(a)})
            if r is not None:
                ready.append(r)
                if r > SLOW_READY_MIN:
                    slow_ready.append({"order_id": o["id"], "where": label, "minutes": round(r)})
            if o["stage"] in ("rejected", "cancelled"):
                lost.append({"order_id": o["id"], "where": label, "stage": o["stage"], "reason": o["reason"] or ""})
        calls = self._rows(conn, "SELECT order_id, table_id, kind, label, status, created_at, done_at FROM pos_desk_requests"
                                 " WHERE business_id = ? AND substr(created_at, 1, 10) BETWEEN ? AND ?",
                           (business_id, (day - timedelta(days=1)).isoformat(), d))
        calls = [c for c in calls if (_ist(c["created_at"]) or datetime.min.replace(tzinfo=IST)).date() == day]
        per_order: Dict[str, List[Any]] = {}
        waits: List[float] = []
        slow_calls = 0
        for c in calls:
            per_order.setdefault(c["order_id"], []).append(c)
            m = _minutes(c["created_at"], c["done_at"]) if c["done_at"] else None
            if m is not None:
                waits.append(m)
            if (m is not None and m > SLOW_CALL_MIN) or c["status"] == "open":
                slow_calls += 1
        repeat = [{"order_id": k, "where": tables.get(v[0]["table_id"] or "", "") or "—", "times": len(v),
                   "asked": sorted({x["label"] or x["kind"] for x in v})}
                  for k, v in per_order.items() if len(v) >= REPEAT_CALLS]
        avg = (lambda xs: round(sum(xs) / len(xs), 1) if xs else None)
        order_block = {"count": len(orders), "by_source": {}, "avg_accept_min": avg(accept), "avg_ready_min": avg(ready),
                       "slow_accept": slow_accept, "slow_ready": slow_ready, "lost": lost,
                       "calls": len(calls), "avg_call_min": avg(waits), "slow_calls": slow_calls, "repeat_calls": repeat}
        for o in orders:
            order_block["by_source"][o["source"]] = order_block["by_source"].get(o["source"], 0) + 1

        # staff
        labels = self._labels(conn, business_id)
        made: Dict[str, Dict[str, int]] = {}
        for r in bills:
            m = made.setdefault(r["created_by"], {"bills": 0, "paise": 0})
            m["bills"] += 1
            m["paise"] += _grand(r["totals"])
        att = {r["phone_key"]: r for r in self._rows(conn, "SELECT phone_key, status, late_min, far FROM pos_attendance"
                                                           " WHERE business_id = ? AND local_date = ?", (business_id, d))}
        people = []
        for r in self._rows(conn, "SELECT phone_key, label, app_user_id, role FROM pos_members WHERE business_id = ?"
                                  " AND active = 1 AND role != 'owner'", (business_id,)):
            a = att.get(r["phone_key"])
            people.append({"name": (r["label"] or "").strip() or f"••{str(r['phone_key'])[-4:]}", "role": r["role"],
                           "status": a["status"] if a else "A", "late_min": int(a["late_min"]) if a else 0,
                           "far": bool(a["far"]) if a else False, **made.get(r["app_user_id"] or "", {"bills": 0, "paise": 0})})
        tasks = self._rows(conn, "SELECT title, assignee, due_at, status, done_at FROM pos_tasks WHERE business_id = ?"
                                 " AND substr(created_at, 1, 10) BETWEEN ? AND ?",
                           (business_id, (day - timedelta(days=1)).isoformat(), d))
        late_tasks = [t for t in tasks if t["due_at"] and ((t["status"] != "done" and (_ist(t["due_at"]) or datetime.max.replace(tzinfo=IST)).date() <= day)
                                                           or (t["done_at"] and (_minutes(t["due_at"], t["done_at"]) or 0) > 0))]
        staff = {"people": people, "present": sum(1 for p in people if p["status"] in ("P", "OT", "half")),
                 "absent": sum(1 for p in people if p["status"] == "A"),
                 "late": sum(1 for p in people if p["late_min"] > 0),
                 "tasks": len(tasks), "tasks_done": sum(1 for t in tasks if t["status"] == "done"),
                 "tasks_late": len(late_tasks), "by_person": [{"name": labels.get(k, "—"), **v} for k, v in made.items()]}

        reviews = self._rows(conn, "SELECT stars, text FROM pos_reviews WHERE business_id = ? AND substr(created_at, 1, 10) = ?",
                             (business_id, d))
        review_block = {"count": len(reviews), "low": sum(1 for r in reviews if (r["stars"] or 0) <= 2),
                        "average": round(sum(r["stars"] or 0 for r in reviews) / len(reviews), 1) if reviews else None}

        problems = self._problems(paise, lw, change, order_block, staff, review_block, money, top, not_selling, peak)
        high = sum(1 for p in problems if p["level"] == "high")
        mood = "bad" if high >= 2 or (change is not None and change <= -30) else (
            "good" if high == 0 and (change is None or change >= -10) and len(problems) <= 2 else "ok")
        out = {"date": d, "mood": mood,
               "sales": {"paise": paise, "bills": len(bills), "avg_bill_paise": paise // len(bills) if bills else 0,
                         "yesterday_paise": yd, "last_week_paise": lw, "change_pct": change},
               "hours": hours, "peak_hour": peak["hour"] if peak else None, "money": money,
               "items": {"top": top, "not_selling": not_selling}, "customers": customers, "orders": order_block,
               "staff": staff, "reviews": review_block, "problems": problems}
        out["say_te"], out["say_en"] = self._say(out, True), self._say(out, False)
        return out

    @staticmethod
    def _problems(paise: int, lw: int, change: Optional[int], o: Dict[str, Any], staff: Dict[str, Any],
                  reviews: Dict[str, Any], money: Dict[str, Any], top: List[Dict[str, Any]],
                  not_selling: List[Dict[str, Any]], peak: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if o["repeat_calls"]:
            worst = max(o["repeat_calls"], key=lambda x: x["times"])
            out.append(_problem(
                "repeat_calls", "high", len(o["repeat_calls"]),
                f"{len(o['repeat_calls'])} tables had to call {REPEAT_CALLS}+ times",
                f"{len(o['repeat_calls'])} టేబుల్స్ {REPEAT_CALLS} సార్లు పైగా పిలవాల్సి వచ్చింది",
                f"Table {worst['where']} called {worst['times']} times ({', '.join(worst['asked'])}).",
                f"టేబుల్ {worst['where']} {worst['times']} సార్లు పిలిచింది ({', '.join(worst['asked'])}).",
                "Give each waiter fixed tables, keep water / onions on the table at busy time.",
                "ఒక్కో వెయిటర్‌కి కొన్ని టేబుల్స్ ఇవ్వండి; రద్దీ టైంలో నీళ్ళు / ఉల్లిపాయలు ముందే టేబుల్‌పై పెట్టండి.",
                "orders.calls"))
        if o["slow_ready"]:
            worst = max(o["slow_ready"], key=lambda x: x["minutes"])
            names = ", ".join(t["name"] for t in top[:2])
            out.append(_problem(
                "slow_food", "high" if len(o["slow_ready"]) >= 3 else "mid", len(o["slow_ready"]),
                f"{len(o['slow_ready'])} orders took over {SLOW_READY_MIN} min",
                f"{len(o['slow_ready'])} ఆర్డర్లు {SLOW_READY_MIN} నిమిషాలు దాటాయి",
                f"Slowest: {worst['where']} — {worst['minutes']} min.",
                f"ఎక్కువ ఆలస్యం: {worst['where']} — {worst['minutes']} ని.",
                f"Prepare the top items ({names}) ahead before {peak['hour'] if peak else 12}:00." if names else
                "Prepare the most-sold items ahead of the busy hour.",
                f"ఎక్కువ అమ్మే ఐటమ్స్ ({names}) {peak['hour'] if peak else 12} గంటల ముందే రెడీ చేయండి." if names else
                "ఎక్కువ అమ్మే ఐటమ్స్ రద్దీ ముందే రెడీ చేయండి.",
                "orders.kitchen"))
        if o["slow_accept"]:
            out.append(_problem(
                "slow_accept", "mid", len(o["slow_accept"]),
                f"{len(o['slow_accept'])} orders waited over {SLOW_ACCEPT_MIN} min for someone to accept",
                f"{len(o['slow_accept'])} ఆర్డర్లు {SLOW_ACCEPT_MIN} ని. పైగా ఎవరూ ఒప్పుకోలేదు",
                f"Longest wait {max(x['minutes'] for x in o['slow_accept'])} min.",
                f"ఎక్కువ వేచి ఉంది {max(x['minutes'] for x in o['slow_accept'])} ని.",
                "Let one more person accept orders and keep the shop phone's sound on.",
                "ఇంకొకరికి ఆర్డర్ ఒప్పుకునే పని ఇవ్వండి; షాప్ ఫోన్ సౌండ్ ఆన్‌లో ఉంచండి.",
                "orders.alerts"))
        if o["slow_calls"] and not o["repeat_calls"]:
            out.append(_problem(
                "slow_calls", "mid", o["slow_calls"],
                f"{o['slow_calls']} table requests were answered late",
                f"{o['slow_calls']} టేబుల్ పిలుపులకు ఆలస్యంగా వెళ్ళారు",
                f"Average answer time {o['avg_call_min']} min.", f"సగటున {o['avg_call_min']} ని. పట్టింది.",
                "Turn on the table-call sound on the waiters' phones.",
                "వెయిటర్ల ఫోన్‌లో టేబుల్ పిలుపు సౌండ్ ఆన్ చేయండి.", "orders.calls"))
        if o["lost"]:
            reasons = ", ".join(sorted({x["reason"] for x in o["lost"] if x["reason"]})[:3]) or "—"
            out.append(_problem(
                "lost_orders", "high" if len(o["lost"]) >= 3 else "mid", len(o["lost"]),
                f"{len(o['lost'])} orders were rejected / cancelled", f"{len(o['lost'])} ఆర్డర్లు రద్దు అయ్యాయి",
                f"Reasons: {reasons}.", f"కారణాలు: {reasons}.",
                "Switch finished items off early so customers do not order them.",
                "అయిపోయిన ఐటమ్స్ వెంటనే ఆఫ్ చేయండి — కస్టమర్ ఆర్డర్ చేయరు.", "menu.today"))
        if change is not None and change <= -DROP_PCT:
            out.append(_problem(
                "sales_drop", "high" if change <= -35 else "mid", abs(change),
                f"Sales {abs(change)}% lower than the same day last week",
                f"గత వారం ఇదే రోజు కంటే అమ్మకం {abs(change)}% తక్కువ",
                f"{_rupees(paise)} today vs {_rupees(lw)}.", f"ఈ రోజు {_rupees(paise)}, గత వారం {_rupees(lw)}.",
                "Post today's special on your shop page and tell regular customers.",
                "మీ షాప్ పేజీలో ఈ రోజు స్పెషల్ పోస్ట్ చేయండి; రెగ్యులర్ కస్టమర్లకు చెప్పండి.", "customers.post"))
        if staff["late"] or staff["absent"]:
            out.append(_problem(
                "staff", "mid" if staff["absent"] else "low", staff["late"] + staff["absent"],
                f"{staff['late']} late, {staff['absent']} absent", f"{staff['late']} మంది ఆలస్యం, {staff['absent']} మంది రాలేదు",
                ", ".join(p["name"] for p in staff["people"] if p["late_min"] or p["status"] == "A")[:120],
                ", ".join(p["name"] for p in staff["people"] if p["late_min"] or p["status"] == "A")[:120],
                "Check the month page of the people who are often late.",
                "తరచూ ఆలస్యం వచ్చేవారి నెల పేజీ చూడండి.", "staff.attendance"))
        if staff["tasks_late"]:
            out.append(_problem(
                "tasks_late", "low", staff["tasks_late"], f"{staff['tasks_late']} tasks were late",
                f"{staff['tasks_late']} పనులు ఆలస్యం", "", "", "Give a time with each task.",
                "ప్రతి పనికి టైం పెట్టండి.", "staff.tasks"))
        if reviews["low"]:
            out.append(_problem(
                "low_reviews", "high", reviews["low"], f"{reviews['low']} low ratings (1-2 stars)",
                f"{reviews['low']} తక్కువ రేటింగ్స్ (1-2 స్టార్)", "", "",
                "Reply to them politely today.", "ఈ రోజే మర్యాదగా రిప్లై ఇవ్వండి.", "customers.reviews"))
        if money["expense_paise"] > money["cash_paise"] + money["online_paise"] + money["other_in_paise"] and money["expense_paise"]:
            out.append(_problem(
                "spent_more", "mid", 1, "More money went out than came in", "వచ్చిన దాని కంటే ఖర్చు ఎక్కువ",
                f"Out {_rupees(money['expense_paise'])}.", f"ఖర్చు {_rupees(money['expense_paise'])}.",
                "Check the cashbook for big expenses.", "క్యాష్‌బుక్‌లో పెద్ద ఖర్చులు చూడండి.", "money.cashbook"))
        if money["new_dues_paise"] > 0:
            out.append(_problem(
                "new_dues", "low", 1, f"{_rupees(money['new_dues_paise'])} given on credit today",
                f"ఈ రోజు {_rupees(money['new_dues_paise'])} బాకీ పెట్టారు", "", "",
                "Send a reminder from the dues page.", "బాకీల పేజీ నుంచి గుర్తు చేయండి.", "money.dues"))
        if len(not_selling) >= 5:
            out.append(_problem(
                "not_selling", "low", len(not_selling), f"{len(not_selling)} items did not sell this week",
                f"{len(not_selling)} ఐటమ్స్ ఈ వారం అమ్ముడు కాలేదు",
                ", ".join(x["name"] for x in not_selling[:4]), ", ".join(x["name"] for x in not_selling[:4]),
                "Make fewer of these, or offer them as a combo.", "ఇవి తక్కువ చేయండి, లేదా కాంబోగా పెట్టండి.", "menu"))
        order = {"high": 0, "mid": 1, "low": 2}
        return sorted(out, key=lambda p: order[p["level"]])

    @staticmethod
    def _say(r: Dict[str, Any], te: bool) -> str:
        s = r["sales"]
        top = r["items"]["top"][0]["name"] if r["items"]["top"] else ""
        if te:
            mood = {"good": "ఈ రోజు బాగుంది.", "ok": "ఈ రోజు పర్వాలేదు.", "bad": "ఈ రోజు కొన్ని సమస్యలు ఉన్నాయి."}[r["mood"]]
            parts = [mood, f"{s['bills']} బిల్లులు, మొత్తం {_rupees(s['paise'])}."]
            if s["change_pct"] is not None:
                parts.append(f"గత వారం కంటే {abs(s['change_pct'])}% {'ఎక్కువ' if s['change_pct'] >= 0 else 'తక్కువ'}.")
            if top:
                parts.append(f"ఎక్కువ అమ్మింది {top}.")
            if r["peak_hour"] is not None:
                parts.append(f"రద్దీ {r['peak_hour']} గంటలకు.")
            parts += [p["text_te"] + "." for p in r["problems"][:2]]
            return " ".join(parts)
        mood = {"good": "Today went well.", "ok": "Today was okay.", "bad": "Today had some problems."}[r["mood"]]
        parts = [mood, f"{s['bills']} bills, {_rupees(s['paise'])} in all."]
        if s["change_pct"] is not None:
            parts.append(f"{abs(s['change_pct'])}% {'more' if s['change_pct'] >= 0 else 'less'} than last week.")
        if top:
            parts.append(f"Top item {top}.")
        if r["peak_hour"] is not None:
            parts.append(f"Busiest at {r['peak_hour']}:00.")
        parts += [p["text_en"] + "." for p in r["problems"][:2]]
        return " ".join(parts)

    # ------------------------------------------------------------------ 7 / 30 days
    def range(self, business_id: str, user: str, days: int = 7) -> Dict[str, Any]:
        days = 30 if days > 7 else 7
        end = datetime.now(IST).date()
        start = end - timedelta(days=days - 1)
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            bills = self._sales(conn, business_id, start.isoformat(), end.isoformat())
            series = {(start + timedelta(days=i)).isoformat(): {"paise": 0, "bills": 0} for i in range(days)}
            hours = [{"hour": h, "bills": 0} for h in range(24)]
            weekdays = [{"weekday": w, "paise": 0, "days": 0} for w in range(7)]
            for r in bills:
                if r["local_date"] in series:
                    series[r["local_date"]]["paise"] += _grand(r["totals"])
                    series[r["local_date"]]["bills"] += 1
                t = _ist(r["issued_at"])
                if t:
                    hours[t.hour]["bills"] += 1
            for k, v in series.items():
                w = Date.fromisoformat(k).weekday()
                weekdays[w]["paise"] += v["paise"]
                weekdays[w]["days"] += 1
            items = sorted(self._items(conn, [r["id"] for r in bills]).values(), key=lambda x: -x["paise"])
            spent: Dict[str, int] = {}
            for r in self._rows(conn, "SELECT category, amount_paise FROM pos_cashbook WHERE business_id = ? AND kind = 'expense'"
                                      " AND removed_at IS NULL AND local_date BETWEEN ? AND ?",
                                (business_id, start.isoformat(), end.isoformat())):
                spent[r["category"] or "other"] = spent.get(r["category"] or "other", 0) + r["amount_paise"]
            staff = []
            for m in self._rows(conn, "SELECT phone_key, label FROM pos_members WHERE business_id = ? AND active = 1"
                                      " AND role != 'owner'", (business_id,)):
                rows = self._rows(conn, "SELECT status, late_min FROM pos_attendance WHERE business_id = ? AND phone_key = ?"
                                        " AND local_date BETWEEN ? AND ?", (business_id, m["phone_key"], start.isoformat(),
                                                                            end.isoformat()))
                staff.append({"name": (m["label"] or "").strip() or f"••{str(m['phone_key'])[-4:]}",
                              "present": sum(1 for r in rows if r["status"] in ("P", "OT", "half")),
                              "late": sum(1 for r in rows if (r["late_min"] or 0) > 0),
                              "leave": sum(1 for r in rows if r["status"] == "leave")})
            customers: Dict[str, Dict[str, Any]] = {}
            for r in bills:
                if r["customer_id"]:
                    c = customers.setdefault(r["customer_id"], {"name": _name(r["customer_snapshot"]) or "—", "bills": 0, "paise": 0})
                    c["bills"] += 1
                    c["paise"] += _grand(r["totals"])
        total = sum(v["paise"] for v in series.values())
        best = max(series.items(), key=lambda kv: kv[1]["paise"]) if bills else None
        return {"days": days, "from": start.isoformat(), "to": end.isoformat(), "total_paise": total, "bills": len(bills),
                "avg_day_paise": total // days,
                "series": [{"date": k, **v} for k, v in series.items()], "hours": hours,
                "weekdays": [{"weekday": w["weekday"], "avg_paise": w["paise"] // w["days"] if w["days"] else 0}
                             for w in weekdays],
                "best_day": {"date": best[0], **best[1]} if best else None,
                "items_top": items[:10], "items_low": [x for x in items if x["qty"] > 0][-5:][::-1] if len(items) > 10 else [],
                "expense_by_category": spent, "expense_paise": sum(spent.values()), "staff": staff,
                "customers_top": sorted(customers.values(), key=lambda x: -x["paise"])[:8], "customers_count": len(customers)}

    # ------------------------------------------------------------------ night report
    def settings(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "reports")
            row = conn.execute("SELECT night_push, send_time FROM pos_report_settings WHERE business_id = ?",
                               (business_id,)).fetchone()
        return {"night_push": bool(row["night_push"]) if row else True, "send_time": row["send_time"] if row else "00:00"}

    def save_settings(self, business_id: str, user: str, night_push: Optional[bool], send_time: Optional[str]) -> Dict[str, Any]:
        cur = self.settings(business_id, user)
        if send_time is not None:
            try:
                h, m = (int(x) for x in str(send_time).split(":"))
                assert 0 <= h < 24 and 0 <= m < 60
            except Exception as exc:
                raise PosError(400, "send_time", "Time must be HH:MM.") from exc
            cur["send_time"] = f"{h:02d}:{m:02d}"
        if night_push is not None:
            cur["night_push"] = bool(night_push)
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "settings")
            conn.execute("INSERT INTO pos_report_settings (business_id, night_push, send_time, updated_at) VALUES (?, ?, ?, ?)"
                         " ON CONFLICT(business_id) DO UPDATE SET night_push = excluded.night_push,"
                         " send_time = excluded.send_time, updated_at = excluded.updated_at",
                         (business_id, 1 if cur["night_push"] else 0, cur["send_time"], datetime.now(IST).isoformat()))
        return cur

    @staticmethod
    def due_date(send_time: str, now: datetime) -> Optional[Date]:
        """Which day's report is due now: a time before noon reports the day that ended; a later time reports today."""
        h, m = (int(x) for x in send_time.split(":"))
        at = now.replace(hour=h, minute=m, second=0, microsecond=0)
        if now < at:
            return None
        return now.date() if h >= 12 else now.date() - timedelta(days=1)

    def run_night(self, now: Optional[datetime] = None) -> Dict[str, Any]:
        now = (now or datetime.now(IST)).astimezone(IST)
        sent = checked = 0
        with self.store._connect() as conn:
            shops = conn.execute("SELECT b.id, b.name, b.owner_user_id, s.night_push, s.send_time FROM pos_businesses b"
                                 " LEFT JOIN pos_report_settings s ON s.business_id = b.id").fetchall()
            for shop in shops:
                if shop["night_push"] is not None and not shop["night_push"]:
                    continue
                day = self.due_date(shop["send_time"] or "00:00", now)
                if day is None or (now.date() - day).days > 1:
                    continue
                checked += 1
                if conn.execute("SELECT 1 FROM pos_report_sends WHERE business_id = ? AND local_date = ?",
                                (shop["id"], day.isoformat())).fetchone():
                    continue
                report = self._day(conn, shop["id"], day)
                users = [shop["owner_user_id"]]
                for r in self._rows(conn, "SELECT role, app_user_id FROM pos_members WHERE business_id = ? AND active = 1"
                                          " AND app_user_id IS NOT NULL AND app_user_id != ''", (shop["id"],)):
                    if "reports" in PERMISSIONS.get(r["role"], frozenset()):
                        users.append(r["app_user_id"])
                pushed = 0
                if report["sales"]["bills"] or report["orders"]["count"] or report["staff"]["present"]:
                    face = {"good": "😊", "ok": "😐", "bad": "😟"}[report["mood"]]
                    title = f"{face} {shop['name']} — {day.strftime('%d/%m')} రిపోర్ట్"
                    body = (f"{report['sales']['bills']} బిల్లులు · {_rupees(report['sales']['paise'])}"
                            + (f" · సమస్యలు {len(report['problems'])}" if report["problems"] else " · సమస్యలు లేవు"))
                    for u in dict.fromkeys(users):
                        try:
                            if self.notify:
                                self.notify(u, title, body, f"/biz/{shop['id']}/reports/day?date={day.isoformat()}",
                                            f"night_report:{shop['id']}:{day.isoformat()}:{u}")
                                pushed += 1
                        except Exception:
                            pass
                conn.execute("INSERT OR IGNORE INTO pos_report_sends (business_id, local_date, sent_at, pushed) VALUES (?, ?, ?, ?)",
                             (shop["id"], day.isoformat(), now.isoformat(), pushed))
                sent += 1
        return {"checked": checked, "sent": sent}
