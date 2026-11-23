"""The ONE business hub (owner 2026-11-18): today's numbers for the 6 group pages and the ASK bar that every page carries.

The ASK bar turns a sentence ("chicken 65 off cheyyi", "rajesh baaki entha?", "menu sardu") into ONE of a fixed catalogue
of actions. Reading the sentence is the model's job; what may happen is decided here:

- ``open``     -> the app opens that page (never changes anything)
- ``answer``   -> a reply built ONLY from the shop's own numbers below (the model never makes numbers up)
- a change     -> returned as ``confirm`` with a one-line summary; nothing changes until the person taps ✓
                 (``/ask/confirm`` runs it as that person, with their own POS permissions).

Every business type gets the same catalogue; the page names the app shows adapt to the type.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PosError

# Pages the ASK bar may open: key -> (English, Telugu). The app maps each key to its route. A key that opens a shop page
# carries that page's ONE name (lib/features/pos/domain/shop_page_names.dart; checked by test_chat_actions.py).
PAGES: Dict[str, tuple] = {
    "hub": ("My business", "నా బిజినెస్"),
    "orders": ("Orders", "ఆర్డర్లు"),
    "orders.incoming": ("Incoming orders", "వచ్చిన ఆర్డర్లు"),
    "orders.tables": ("Tables", "టేబుల్స్"),
    "orders.calls": ("Table calls", "టేబుల్ పిలుపులు"),
    "orders.kitchen": ("Kitchen (KOT)", "వంటగది KOT"),
    "orders.delivery": ("Delivery / parcel", "డెలివరీ / పార్సిల్"),
    "orders.qr": ("Table QR codes", "టేబుల్ QR కోడ్‌లు"),
    "orders.alerts": ("Order alerts & who accepts", "ఆర్డర్ అలర్ట్స్"),
    "money": ("Bills & money", "బిల్లులు & డబ్బు"),
    "money.bill": ("Make a bill", "బిల్లు చేయి"),
    "money.cashbook": ("Cashbook", "క్యాష్‌బుక్"),
    "money.dues": ("Dues", "బాకీలు"),
    "money.sound": ("Payment sound", "పేమెంట్ సౌండ్"),
    "money.accounts": ("My QR / accounts", "నా QR / ఖాతాలు"),
    "money.sales": ("Sales", "అమ్మకాలు"),
    "money.history": ("Bill history", "బిల్లుల చరిత్ర"),
    "money.gst": ("GST report", "GST రిపోర్ట్"),
    "menu": ("Menu & items", "మెనూ & ఐటమ్స్"),
    "menu.add": ("Add an item", "ఐటమ్ చేర్చు"),
    "menu.photo": ("Menu photo", "మెనూ ఫోటో"),
    "menu.sort": ("Sort with AI", "AI తో సర్దు"),
    "menu.today": ("Available today", "ఈ రోజు ఉన్నవి"),
    "staff": ("Staff & attendance", "సిబ్బంది & హాజరు"),
    "staff.attendance": ("Attendance", "హాజరు"),
    "staff.salary": ("Salary & advance", "జీతాలు & అడ్వాన్స్"),
    "staff.tasks": ("Tasks", "పనులు"),
    "staff.add": ("Add staff", "సిబ్బందిని చేర్చు"),
    "staff.checkin": ("Check in / out", "హాజరు వేయి"),
    "customers": ("Customers & shop page", "కస్టమర్లు & షాప్ పేజీ"),
    "customers.page": ("My shop page", "నా షాప్ పేజీ"),
    "customers.reviews": ("Reviews", "రివ్యూలు"),
    "customers.post": ("Today's post", "ఈ రోజు పోస్ట్"),
    "customers.welcome": ("Welcome / thanks", "స్వాగతం / ధన్యవాదాలు"),
    "customers.list": ("Customer list", "కస్టమర్ల లిస్ట్"),
    "settings": ("Settings", "సెట్టింగ్స్"),
    "settings.details": ("Business details", "బిజినెస్ వివరాలు"),
    "settings.gst": ("GST report", "GST రిపోర్ట్"),
    "settings.printer": ("Printer", "ప్రింటర్"),
    "reports": ("Reports", "రిపోర్ట్స్"),
    "reports.settings": ("Night report", "రాత్రి రిపోర్ట్"),
}

# Changes the ASK bar may PROPOSE (each runs only after the person's ✓).
CHANGES = ("item_off", "item_on", "item_price", "menu_sort", "add_expense", "add_income", "staff_advance", "task_add",
           "att_mark")
OTHER = ("open", "answer", "report", "check_in", "unknown")
WHEN = ("today", "yesterday", "week", "month")
ATT_TE = {"P": "వచ్చారు", "A": "రాలేదు", "OT": "ఎక్కువ గంటలు", "leave": "సెలవు", "half": "సగం రోజు"}

PROMPT = (
    "You read ONE sentence a shop owner or staff said in any language (Telugu, English, mixed) inside their business "
    "app, and pick ONE action. Return ONLY JSON {\"action\": string, \"page\": string, \"item\": string, "
    "\"price\": number, \"question\": string, \"category\": string, \"note\": string, \"person\": string, \"status\": string, \"when\": string}.\n"
    "action is one of: open (they want to see a page), answer (they ask a question about today: sales, dues, orders, "
    "payments, staff), item_off (an item is finished / not available today), item_on (an item is available again), "
    "item_price (change an item's price; price in rupees), menu_sort (arrange / sort / organise the menu into "
    "sections), add_expense (money spent: write it in the cashbook; price = the rupees, category = one of stock, salary, "
    "rent, power, gas, transport, repair, other; note = what it was in a few words), add_income (money received that is "
    "not a bill: advance, catering ...; price = rupees), "
    "report (how the day / week went, problems, best or slow items, busy time, staff work, the night report), "
    "staff_advance (money given to a staff member in advance; person = their name, price = rupees), task_add (give a "
    "staff member a job to do; person = their name, note = the job in a few words), check_in (the speaker says they "
    "came to work / are leaving), att_mark (the owner marks ANOTHER person's attendance for today: person = name, "
    "status = P present, A absent, OT extra hours (price = the hours), leave, half), unknown (anything else, e.g. shopping, general talk, a question not about this "
    "business).\n"
    "when = today, yesterday, week or month (for report; else today).\n"
    "page = one key from this list when action is open (else \"\"): {pages}\n"
    "item = the item name exactly as said (for item_* actions), else \"\". question = the question in short English "
    "for answer, else \"\".\nThe person is on the page: {here}. When the page is chat (the app's main chat, where "
    "people also shop and ask anything), choose unknown unless the sentence is clearly about running THEIR OWN "
    "business.\nSentence: {text}"
)


def _today() -> str:
    return datetime.now(IST).strftime("%Y-%m-%d")


def _paise(totals: str) -> int:
    try:
        return int(json.loads(totals or "{}").get("grand_total_paise") or 0)
    except (TypeError, ValueError):
        return 0


def summary(conn, business_id: str) -> Dict[str, Any]:
    """Today's numbers for the hub + group pages. Each number is read on its own: a missing table gives 0, never an error."""
    today = _today()
    out: Dict[str, Any] = {"date": today}

    def safe(key: str, fn: Callable[[], Any], default: Any = 0) -> None:
        try:
            out[key] = fn()
        except Exception:  # a shop without that feature yet
            out[key] = default

    def sales() -> Dict[str, int]:
        rows = conn.execute("SELECT totals, balance_paise, status FROM pos_invoices WHERE business_id = ? AND local_date = ?"
                            " AND doc_kind = 'invoice'", (business_id, today)).fetchall()
        live = [r for r in rows if r["status"] != "cancelled"]
        return {"paise": sum(_paise(r["totals"]) for r in live), "bills": len(live)}

    def split() -> Dict[str, int]:
        cash = online = 0
        for r in conn.execute("SELECT method, amount_paise, kind FROM pos_payments WHERE business_id = ? AND local_date = ?",
                              (business_id, today)):
            if r["kind"] in ("refund",):
                continue
            if r["method"] == "cash":
                cash += r["amount_paise"]
            else:
                online += r["amount_paise"]
        return {"cash_paise": cash, "online_paise": online}

    def dues() -> Dict[str, int]:
        row = conn.execute("SELECT COALESCE(SUM(balance_paise), 0) AS d, COUNT(DISTINCT customer_id) AS n FROM pos_invoices"
                           " WHERE business_id = ? AND status != 'cancelled' AND balance_paise > 0", (business_id,)).fetchone()
        return {"paise": int(row["d"] or 0), "people": int(row["n"] or 0)}

    def orders() -> Dict[str, int]:
        rows = conn.execute("SELECT stage, placed_at FROM pos_desk_orders WHERE business_id = ? AND placed_at >= ?",
                            (business_id, (datetime.now(IST) - timedelta(hours=20)).astimezone().isoformat()[:10])).fetchall()
        return {"new": sum(1 for r in rows if r["stage"] == "placed"),
                "cooking": sum(1 for r in rows if r["stage"] in ("accepted", "preparing")),
                "done": sum(1 for r in rows if r["stage"] in ("served", "handed", "delivered", "done"))}

    def calls() -> int:
        return int(conn.execute("SELECT COUNT(*) AS n FROM pos_desk_requests WHERE business_id = ? AND status = 'open'",
                                (business_id,)).fetchone()["n"])

    def sounds() -> int:
        return int(conn.execute("SELECT COUNT(*) AS n FROM pos_payment_events WHERE business_id = ? AND test = 0"
                                " AND substr(received_at, 1, 10) = ?", (business_id, today)).fetchone()["n"])

    def staff() -> int:
        return int(conn.execute("SELECT COUNT(*) AS n FROM pos_members WHERE business_id = ? AND active = 1 AND role != 'owner'",
                                (business_id,)).fetchone()["n"])

    def menu() -> Dict[str, int]:
        rows = conn.execute("SELECT menu_group FROM pos_products WHERE business_id = ? AND active = 1", (business_id,)).fetchall()
        groups = {str(r["menu_group"] or "").strip() for r in rows} - {""}
        low = 0
        try:  # items the shop counts, at or under their own "low stock" mark
            stock = {r["product_id"]: int(r["qty"] or 0) for r in conn.execute(
                "SELECT product_id, SUM(qty_milli) AS qty FROM pos_stock_moves WHERE business_id = ? GROUP BY product_id",
                (business_id,))}
            for r in conn.execute("SELECT id, low_stock_milli FROM pos_products WHERE business_id = ? AND active = 1"
                                  " AND track_stock = 1", (business_id,)):
                if stock.get(r["id"], 0) <= int(r["low_stock_milli"] or 0):
                    low += 1
        except Exception:
            low = 0
        return {"items": len(rows), "sections": len(groups), "low_stock": low,
                "no_section": sum(1 for r in rows if not str(r["menu_group"] or "").strip())}

    def reviews() -> Dict[str, Any]:
        row = conn.execute("SELECT COUNT(*) AS n, AVG(stars) AS a FROM pos_reviews WHERE business_id = ? AND status = 'shown'",
                           (business_id,)).fetchone()
        unanswered = conn.execute("SELECT COUNT(*) AS n FROM pos_reviews WHERE business_id = ? AND status = 'shown'"
                                  " AND (reply IS NULL OR reply = '')", (business_id,)).fetchone()
        return {"count": int(row["n"] or 0), "average": round(float(row["a"]), 1) if row["a"] else None,
                "unanswered": int(unanswered["n"] or 0)}

    safe("sales", sales, {"paise": 0, "bills": 0})
    safe("split", split, {"cash_paise": 0, "online_paise": 0})
    safe("dues", dues, {"paise": 0, "people": 0})
    safe("orders", orders, {"new": 0, "cooking": 0, "done": 0})
    safe("calls", calls)
    safe("sounds", sounds)
    safe("staff", staff)
    safe("menu", menu, {"items": 0, "sections": 0, "no_section": 0})
    safe("reviews", reviews, {"count": 0, "average": None, "unanswered": 0})
    return out


def _rupees(paise: int) -> str:
    rupees = paise / 100
    return f"₹{rupees:,.0f}" if paise % 100 == 0 else f"₹{rupees:,.2f}"


def answer_text(numbers: Dict[str, Any], te: bool) -> str:
    """The reply to a question about today: only the shop's own numbers, in one or two short sentences."""
    s, d, o = numbers.get("sales", {}), numbers.get("dues", {}), numbers.get("orders", {})
    sp = numbers.get("split", {})
    if te:
        return (f"ఈ రోజు {s.get('bills', 0)} బిల్లులు, అమ్మకం {_rupees(int(s.get('paise', 0)))} "
                f"(క్యాష్ {_rupees(int(sp.get('cash_paise', 0)))}, ఆన్‌లైన్ {_rupees(int(sp.get('online_paise', 0)))}). "
                f"బాకీ మొత్తం {_rupees(int(d.get('paise', 0)))}, {d.get('people', 0)} మంది. "
                f"కొత్త ఆర్డర్లు {o.get('new', 0)}, వంటలో {o.get('cooking', 0)}.")
    return (f"Today {s.get('bills', 0)} bills, sales {_rupees(int(s.get('paise', 0)))} "
            f"(cash {_rupees(int(sp.get('cash_paise', 0)))}, online {_rupees(int(sp.get('online_paise', 0)))}). "
            f"Dues {_rupees(int(d.get('paise', 0)))} from {d.get('people', 0)} people. "
            f"New orders {o.get('new', 0)}, cooking {o.get('cooking', 0)}.")


def _parse(raw: str) -> Dict[str, Any]:
    match = re.search(r"\{.*\}", raw or "", re.S)
    if not match:
        return {}
    try:
        data = json.loads(match.group(0))
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def _norm(text: str) -> str:
    return re.sub(r"[^a-z0-9ఀ-౿]+", "", str(text or "").lower())


def find_item(items: List[Dict[str, Any]], said: str) -> Optional[Dict[str, Any]]:
    """The menu item the person named: exact, then contained, then the most shared words. None when unsure."""
    want = _norm(said)
    if not want:
        return None
    for it in items:
        if _norm(it.get("name")) == want:
            return it
    contained = [it for it in items if want in _norm(it.get("name")) or _norm(it.get("name")) in want]
    if len(contained) == 1:
        return contained[0]
    words = set(re.findall(r"[a-z0-9ఀ-౿]+", str(said).lower()))
    best, score = None, 0
    for it in items:
        have = set(re.findall(r"[a-z0-9ఀ-౿]+", str(it.get("name") or "").lower()))
        common = len(words & have)
        if common > score:
            best, score = it, common
        elif common == score and common:
            best = None  # two equally good matches: ask rather than guess
    return best if score else None


def read(text: str, here: str, write_text: Callable[..., str]) -> Dict[str, Any]:
    prompt = PROMPT.replace("{pages}", ", ".join(PAGES)).replace("{here}", here or "hub").replace("{text}", text[:400])
    raw = write_text(prompt, max_tokens=300)
    data = _parse(raw or "")
    action = str(data.get("action") or "unknown")
    if action not in OTHER + CHANGES:
        action = "unknown"
    page = str(data.get("page") or "")
    if action == "open" and page not in PAGES:
        action = "unknown"
    price = data.get("price")
    try:
        price = float(price) if price not in (None, "") else None
    except (TypeError, ValueError):
        price = None
    return {"action": action, "page": page, "item": str(data.get("item") or "")[:80], "price": price,
            "question": str(data.get("question") or "")[:200], "category": str(data.get("category") or "other")[:30],
            "note": str(data.get("note") or "")[:120], "person": str(data.get("person") or "")[:60],
            "status": str(data.get("status") or "")[:6],
            "when": str(data.get("when") or "today") if str(data.get("when") or "today") in WHEN else "today"}


def plan(intent: Dict[str, Any], items: List[Dict[str, Any]], numbers: Dict[str, Any], te: bool,
         people: Optional[List[Dict[str, Any]]] = None, report: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Intent -> what the app shows: a reply, a page to open and/or ONE change waiting for ✓."""
    action = intent["action"]
    if action == "report":
        if not report:
            return {"reply": "రిపోర్ట్ తెరుస్తున్నాను." if te else "Opening the report.", "open": "reports"}
        text = report.get("say_te" if te else "say_en") or ""
        first = (report.get("problems") or [None])[0]
        if first:
            text += ("\n💡 " + (first.get("do_te") if te else first.get("do_en")))
        return {"reply": text, "open": None, "link": "reports", "mood": report.get("mood")}
    if action == "check_in":
        return {"reply": "హాజరు పేజీ తెరుస్తున్నాను — మీ ఫోన్ లాక్‌తో వేయండి." if te
                else "Opening attendance — check in with your phone lock.", "open": "staff.checkin"}
    if action in ("staff_advance", "task_add", "att_mark"):
        who = find_item(people or [], intent.get("person") or "")
        if who is None:
            return {"reply": (f"\"{intent.get('person') or ''}\" అనే సిబ్బంది కనబడలేదు. సిబ్బంది పేజీ తెరుస్తున్నాను." if te
                              else f"I could not find \"{intent.get('person') or ''}\" in your staff. Opening staff."),
                    "open": "staff"}
        if action == "att_mark":
            status = {"p": "P", "a": "A", "ot": "OT", "leave": "leave", "half": "half"}.get((intent.get("status") or "").lower())
            if status is None:
                return {"reply": f"{who['name']} — వచ్చారా, రాలేదా, సెలవా?" if te else f"{who['name']} — present, absent or leave?",
                        "open": "staff"}
            ot = int(round((intent.get("price") or 0) * 60)) if status == "OT" else 0
            if status == "OT" and ot <= 0:
                return {"reply": f"{who['name']} ఎన్ని గంటలు ఎక్కువ?" if te else f"How many extra hours for {who['name']}?", "open": None}
            label = ATT_TE[status] if te else {"P": "present", "A": "absent", "OT": "overtime", "leave": "leave", "half": "half day"}[status]
            text = (f"ఈ రోజు {who['name']} — {label}" + (f" ({ot // 60} గం.)" if ot else "") if te
                    else f"Today {who['name']} — {label}" + (f" ({ot // 60} h)" if ot else ""))
            return {"reply": text, "confirm": {"action": "att_mark", "ref": who["id"], "note": status,
                                               "amount_paise": ot or None, "summary": text}}
        if action == "staff_advance":
            if not intent.get("price") or intent["price"] <= 0:
                return {"reply": f"{who['name']} కి ఎంత అడ్వాన్స్?" if te else f"How much advance to {who['name']}?", "open": None}
            paise = int(round(intent["price"] * 100))
            text = (f"{who['name']} కి అడ్వాన్స్ {_rupees(paise)} — జీతంలో తగ్గుతుంది, క్యాష్‌బుక్‌లో పడుతుంది" if te
                    else f"Advance {_rupees(paise)} to {who['name']} — taken from salary, written in the cashbook")
            return {"reply": text, "confirm": {"action": "staff_advance", "ref": who["id"], "amount_paise": paise,
                                               "summary": text}}
        job = (intent.get("note") or "").strip()
        if not job:
            return {"reply": f"{who['name']} కి ఏ పని?" if te else f"What task for {who['name']}?", "open": None}
        text = f"{who['name']} కి పని: {job} (వారి ఫోన్ మోగుతుంది)" if te else f"Task for {who['name']}: {job} (their phone rings)"
        return {"reply": text, "confirm": {"action": "task_add", "ref": who["id"], "note": job, "summary": text}}
    if action == "open":
        en, tel = PAGES[intent["page"]]
        return {"reply": f"{tel} తెరుస్తున్నాను." if te else f"Opening {en}.", "open": intent["page"]}
    if action == "answer":
        return {"reply": answer_text(numbers, te), "open": None}
    if action == "menu_sort":
        return {"reply": "మెనూని AI తో సర్దుతాను — ముందు చూపించి, మీరు ఓకే అంటేనే సేవ్." if te
                else "I'll sort the menu with AI — you see it first, nothing saves until you say OK.", "open": "menu.sort"}
    if action in ("add_expense", "add_income"):
        if not intent.get("price") or intent["price"] <= 0:
            return {"reply": "ఎంత రూపాయలు?" if te else "How many rupees?", "open": None}
        paise = int(round(intent["price"] * 100))
        kind = "expense" if action == "add_expense" else "income"
        what = intent.get("note") or intent.get("category") or ""
        summary_text = ((f"క్యాష్‌బుక్‌లో ఖర్చు: {what} {_rupees(paise)}" if kind == "expense"
                         else f"క్యాష్‌బుక్‌లో ఆదాయం: {what} {_rupees(paise)}") if te
                        else f"Cashbook {'expense' if kind == 'expense' else 'income'}: {what} {_rupees(paise)}")
        return {"reply": summary_text, "confirm": {"action": action, "amount_paise": paise, "category": intent.get("category") or "other",
                                                   "note": intent.get("note") or "", "summary": summary_text}}
    if action in ("item_off", "item_on", "item_price"):
        item = find_item(items, intent["item"])
        if item is None:
            return {"reply": (f"\"{intent['item']}\" అనే ఐటమ్ మెనూలో కనబడలేదు. మెనూ తెరుస్తున్నాను." if te
                              else f"I could not find \"{intent['item']}\" in the menu. Opening the menu."), "open": "menu"}
        name = item["name"]
        if action == "item_price":
            if not intent.get("price") or intent["price"] <= 0:
                return {"reply": f"{name} కి ఏ ధర పెట్టాలి?" if te else f"What price for {name}?", "open": None}
            paise = int(round(intent["price"] * 100))
            summary_text = (f"{name} ధర {_rupees(int(item.get('price_paise') or 0))} → {_rupees(paise)}" if te
                            else f"{name}: {_rupees(int(item.get('price_paise') or 0))} → {_rupees(paise)}")
            return {"reply": summary_text, "confirm": {"action": "item_price", "product_id": item["id"],
                                                       "price_paise": paise, "summary": summary_text}}
        on = action == "item_on"
        summary_text = (f"{name} — ఈ రోజు {'ఉంది (ఆన్)' if on else 'లేదు (ఆఫ్)'}" if te
                        else f"{name} — {'available (on)' if on else 'not available today (off)'}")
        return {"reply": summary_text, "confirm": {"action": action, "product_id": item["id"], "summary": summary_text}}
    return {"reply": ("అర్థం కాలేదు. ఇలా చెప్పండి: \"చికెన్ 65 ఆఫ్ చెయ్యి\", \"ఈ రోజు ఎంత అమ్మాం?\", \"బాకీలు చూపించు\"." if te
                      else "I didn't get that. Try: \"turn chicken 65 off\", \"how much did we sell today?\", \"show dues\"."),
            "open": None}


def range_say(r: Dict[str, Any], te: bool) -> Dict[str, Any]:
    """A 7 / 30-day report in two or three spoken sentences (only the shop's own numbers)."""
    days = r.get("days", 7)
    best = r.get("best_day") or {}
    top = (r.get("items_top") or [{}])[0].get("name") or ""
    week_te = ["సోమ", "మంగళ", "బుధ", "గురు", "శుక్ర", "శని", "ఆది"]
    week_en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    wd = max(r.get("weekdays") or [{"weekday": 0, "avg_paise": 0}], key=lambda w: w["avg_paise"])
    if te:
        text = (f"గత {days} రోజుల్లో {r.get('bills', 0)} బిల్లులు, మొత్తం {_rupees(int(r.get('total_paise') or 0))}, "
                f"రోజుకు సగటు {_rupees(int(r.get('avg_day_paise') or 0))}.")
        if best:
            text += f" ఎక్కువ అమ్మిన రోజు {best.get('date')} ({_rupees(int(best.get('paise') or 0))})."
        if wd["avg_paise"]:
            text += f" {week_te[wd['weekday']]}వారం ఎక్కువ అమ్ముతుంది."
        if top:
            text += f" ఎక్కువ అమ్ముడైనది {top}."
    else:
        text = (f"Last {days} days: {r.get('bills', 0)} bills, {_rupees(int(r.get('total_paise') or 0))} in all, "
                f"{_rupees(int(r.get('avg_day_paise') or 0))} a day.")
        if best:
            text += f" Best day {best.get('date')} ({_rupees(int(best.get('paise') or 0))})."
        if wd["avg_paise"]:
            text += f" {week_en[wd['weekday']]} sells most."
        if top:
            text += f" Top item {top}."
    return {"say_te": text, "say_en": text, "mood": None, "problems": []}


def run(change: Dict[str, Any], *, store, desk, business_id: str, user: str) -> Dict[str, Any]:
    """Runs ONE confirmed change as the person who confirmed it (their own POS permissions apply)."""
    action = change.get("action")
    product_id = str(change.get("product_id") or "")
    if action in ("item_off", "item_on"):
        desk.set_availability(business_id, user, product_id, action == "item_on")
        return {"done": True}
    if action == "item_price":
        paise = int(change.get("price_paise") or 0)
        if paise <= 0:
            raise PosError(400, "price", "A price is needed.")
        store.update_product(business_id, user, product_id, {"price_paise": paise})
        return {"done": True}
    if action in ("add_expense", "add_income"):
        from app.services.pos_cashbook import PosCashbook

        return PosCashbook(store).add(business_id, user, {
            "kind": "expense" if action == "add_expense" else "income", "amount_paise": change.get("amount_paise"),
            "category": change.get("category") or "other", "note": change.get("note") or "", "source": "ask"})
    if action in ("staff_advance", "task_add", "att_mark"):
        from app.services.pos_attendance import PosAttendance

        att = PosAttendance(store, notify=getattr(desk, "notify", None))
        ref = str(change.get("ref") or "")[:20]
        if action == "att_mark":
            return att.mark(business_id, user, ref, _today(), str(change.get("note") or ""),
                            ot_min=int(change.get("amount_paise") or 0))
        if action == "staff_advance":
            return att.advance(business_id, user, ref, int(change.get("amount_paise") or 0), change.get("note") or "")
        return att.add_task(business_id, user, change.get("note") or "", ref)
    raise PosError(400, "action", "This change cannot run from the ASK bar.")
