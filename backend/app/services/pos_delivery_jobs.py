"""Delivery jobs for a shop's own people (owner-approved plan 2026-11-24, design 5wns7Bm9FEEnr4ug3E9PQv, step 1).

a. The owner says ONE line ("ఉయ్యూరు నుంచి పారం కి కేక్ ఒకటి డెలివరీ, 250 రూపాయలు ఇస్తారు") -> a job card: the shop
   order number (#12 -- ONE order, ONE number: the job, the person, the QR, the cash, the bill and complaints all hang
   on it), from, to, item, ₹ to the delivery person, amount to collect, ≈ km / minutes (Google Routes on the server,
   cached per from -> to pair so the same trip is never asked twice).
b. "Who should go": the shop's people by their own colour -- 🟢 free first, then 🟠 on a job, then 🔴 busy / off, grey
   = not set for 3 h. Ask all free people or one person (free FCM push, never a paid call / SMS).
c. Each person answers on their phone: now / 10 / 20 / 30 min / can't. Calls = their own dialer (the app shows tel:).
d. The owner sees the answers and taps "give"; or the switch "give it to the first 'now' by itself".
e. The person's status page: big colour buttons, the current job, directions (the phone's Google Maps), money =
   cash / UPI (the OWNER's own UPI QR with the amount -- ASKODOX never holds money) / paid before -> "done" -> green.

Status colours are SET BY THE PERSON (no GPS tracking): accept a job -> orange; done -> green; no change for 3 h -> grey;
from 23:00 IST -> red, until the person sets a colour again.
"""
from __future__ import annotations

import re
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS pos_order_numbers (business_id TEXT PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS pos_dlv_jobs (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, order_no INTEGER NOT NULL,"
    " from_text TEXT NOT NULL, to_text TEXT NOT NULL, item TEXT NOT NULL DEFAULT '', fee_paise INTEGER NOT NULL DEFAULT 0,"
    " collect_paise INTEGER NOT NULL DEFAULT 0, km REAL, minutes INTEGER, status TEXT NOT NULL DEFAULT 'asking',"
    " assignee_user TEXT NOT NULL DEFAULT '', auto_first INTEGER NOT NULL DEFAULT 0, money_mode TEXT NOT NULL DEFAULT '',"
    " request_id TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL, done_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_pos_dlv_jobs_biz ON pos_dlv_jobs(business_id, created_at)",
    "CREATE INDEX IF NOT EXISTS idx_pos_dlv_jobs_user ON pos_dlv_jobs(assignee_user, status)",
    "CREATE TABLE IF NOT EXISTS pos_dlv_asks (job_id TEXT NOT NULL, user_id TEXT NOT NULL, answer TEXT NOT NULL DEFAULT"
    " 'waiting', asked_at TEXT NOT NULL, answered_at TEXT, PRIMARY KEY (job_id, user_id))",
    "CREATE TABLE IF NOT EXISTS pos_work_status (user_id TEXT PRIMARY KEY, colour TEXT NOT NULL, reason TEXT NOT NULL"
    " DEFAULT '', set_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_route_cache (pair TEXT PRIMARY KEY, km REAL, minutes INTEGER, at TEXT NOT NULL)",
]

COLOURS = ("free", "busy", "off")  # 🟢 ఖాళీ / 🟠 పనిలో / 🔴 బిజీ-ఆఫ్ ; "unknown" (grey) is only ever computed
ANSWERS = ("now", "10", "20", "30", "no")
OPEN = ("asking", "given", "picked")
STEPS = {"given": ("picked", "done", "cancelled"), "picked": ("done", "cancelled"), "asking": ("cancelled",)}
MONEY = ("cash", "upi", "prepaid")
GREY_AFTER = timedelta(hours=3)
NIGHT_HOUR = 23
MAX_PAISE = 10_00_000_00  # ₹10 lakh per job, a sanity cap
ROUTE_DAYS = 30

_NUM = r"((?:\d[\d,]*\d|\d)(?:\.\d+)?)"
_RUPEE = r"(?:రూపాయలు|రూపాయిలు|రూ\.?|rupees?|rs\.?|₹|rupaye|रुपये|रुपए)"


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _paise(value: Any, field: str) -> int:
    try:
        amount = int(value or 0)
    except (TypeError, ValueError):
        raise PosError(400, field, f"{field} must be a whole number of paise.")
    if amount < 0 or amount > MAX_PAISE:
        raise PosError(400, field, f"{field} is out of range.")
    return amount


def parse_line(text: str) -> Dict[str, Any]:
    """One spoken / typed line -> the job's boxes (Telugu, Hindi, English, mixed). Never guesses a box it cannot read:
    the box stays empty and is listed in ``missing`` (the owner fills it)."""
    line = _clean(text, 400)
    low = line.lower()
    out: Dict[str, Any] = {"from": "", "to": "", "item": "", "fee_paise": 0, "collect_paise": 0, "missing": []}
    end = r"(?=\s|[,.]|$)"
    m = re.search(r"\b(?i:from)\s+(.+?)\s+(?i:to)\s+([A-Z][\w-]*(?:\s[A-Z][\w-]*)?|\S+)", line)
    if m:
        out["from"], out["to"] = m.group(1).strip(" ,"), m.group(2).strip(" ,")
    else:
        m = re.search(r"(\S+)\s*(?:నుంచి|నుండి|నుంచీ|నుండీ|nunchi|nundi|unchi|se|से)\s+(\S+?)\s*"
                      r"(?:కి|కు|కీ|ki|ku|ke|tak|तक|को)" + end, line, re.I)
        if m:
            out["from"], out["to"] = m.group(1).strip(" ,"), m.group(2).strip(" ,")
        else:  # only where to ("గుడివాడ కి పార్సిల్"): from = the shop itself (left empty, the app shows the shop)
            m = re.search(r"(\S+?)\s+(?:కి|కు|కీ|ki|ku|tak|तक|को)" + end, line, re.I)
            if m:
                out["to"] = m.group(1).strip(" ,")
    # The item: words between the place and the word "delivery" / "parcel".
    place = re.escape(out["to"]) if out["to"] else r"\S+"
    item = re.search(place + r"\s*(?:కి|కు|కీ|ki|ku|tak|तक|को)?(?=\s)\s+(.+?)\s*(?:డెలివరీ|delivery|deliver|పార్సిల్|parcel|डिलीवरी)",
                     line, re.I)
    if item:
        out["item"] = re.sub(r"^(?:కి|కు|కీ|ki|ku|tak|तक|को)(?:\s+|$)", "", item.group(1).strip(" ,"), flags=re.I)
    for amount in re.finditer(_NUM + r"\s*" + _RUPEE + r"|" + _RUPEE + r"\s*" + _NUM, low, re.I):
        raw = (amount.group(1) or amount.group(2) or "0").replace(",", "")
        try:
            paise = int(round(float(raw) * 100))
        except ValueError:
            continue
        after = re.split(r"[,.;]", low[amount.end():amount.end() + 40])[0]
        before = re.split(r"[,.;]", low[max(0, amount.start() - 40):amount.start()])[-1]
        if re.search(r"కూలి|కిరాయి|charge|fee|kooli|kirayi|bhada|भाड़ा|delivery boy ki|అతనికి|వాడికి", before + after):
            out["fee_paise"] = paise
        else:  # "250 రూపాయలు ఇస్తారు / kattali / collect" = the customer pays it
            out["collect_paise"] = out["collect_paise"] or paise
    if not out["to"]:
        out["missing"].append("to")
    return out


class PosDeliveryJobs:
    def __init__(self, store: Any, *, notify: Optional[Callable[..., Any]] = None, maps: Any = None,
                 collect: Any = None, clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.notify = notify or (lambda *a, **k: None)
        self.maps = maps
        self.collect = collect  # PosPaymentAlerts (owner-UPI collect requests)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _now(self) -> datetime:
        return self.clock()

    # ------------------------------------------------------------------ order numbers
    @staticmethod
    def next_order_no(conn: sqlite3.Connection, business_id: str) -> int:
        """ONE order, ONE number per shop (#12): the job card, the person, the QR, cash, bill and complaints use it."""
        conn.execute("INSERT OR IGNORE INTO pos_order_numbers (business_id, n) VALUES (?, 0)", (business_id,))
        conn.execute("UPDATE pos_order_numbers SET n = n + 1 WHERE business_id = ?", (business_id,))
        return int(conn.execute("SELECT n FROM pos_order_numbers WHERE business_id = ?", (business_id,)).fetchone()["n"])

    # ------------------------------------------------------------------ status colours
    def status_of(self, conn: sqlite3.Connection, user: str) -> Dict[str, Any]:
        row = conn.execute("SELECT colour, reason, set_at FROM pos_work_status WHERE user_id = ?", (user,)).fetchone()
        now = self._now()
        if row is None:
            return {"colour": "unknown", "set_at": None, "reason": "never_set"}
        set_at = datetime.fromisoformat(row["set_at"])
        colour, reason = row["colour"], row["reason"]
        local = now.astimezone(IST)
        night_start = local.replace(hour=NIGHT_HOUR, minute=0, second=0, microsecond=0)
        if colour != "off" and local >= night_start and set_at.astimezone(IST) < night_start:
            colour, reason = "off", "night"
        elif colour == "free" and now - set_at > GREY_AFTER:
            colour, reason = "unknown", "not_set_3h"
        return {"colour": colour, "set_at": row["set_at"], "reason": reason}

    def _set_status(self, conn: sqlite3.Connection, user: str, colour: str, reason: str) -> None:
        conn.execute("INSERT INTO pos_work_status (user_id, colour, reason, set_at) VALUES (?,?,?,?) ON CONFLICT(user_id)"
                     " DO UPDATE SET colour = excluded.colour, reason = excluded.reason, set_at = excluded.set_at",
                     (user, colour, reason, self._now().isoformat()))

    def set_status(self, user: str, colour: str) -> Dict[str, Any]:
        if colour not in COLOURS:
            raise PosError(400, "colour", "Choose free, busy or off.")
        with self.store._tx() as conn:
            self._set_status(conn, user, colour, "self")
            return self.status_of(conn, user)

    def my_status(self, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            return self.status_of(conn, user)

    # ------------------------------------------------------------------ people
    def _people(self, conn: sqlite3.Connection, business_id: str) -> List[Dict[str, Any]]:
        owner = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        people: List[Dict[str, Any]] = []
        if owner:
            people.append({"id": owner["owner_user_id"], "role": "owner", "label": "Owner", "phone": ""})
        for r in conn.execute("SELECT role, app_user_id, label, phone_key FROM pos_members WHERE business_id = ?"
                              " AND active = 1 AND role != 'owner'", (business_id,)):
            phone = re.sub(r"\D", "", str(r["phone_key"] or ""))[-10:]
            # An account id is 'app-phone-<number>': staff who never opened the app yet still get the push later.
            pid = r["app_user_id"] or (f"app-phone-{phone}" if len(phone) == 10 else "")
            if not pid:
                continue
            people.append({"id": pid, "role": r["role"], "phone": phone,
                           "label": r["label"] or (f"••{phone[-4:]}" if phone else r["role"])})
        return people

    def people(self, business_id: str, user: str) -> Dict[str, Any]:
        """The shop's people, free first: 🟢, then 🟠, then grey, then 🔴 (each with its own phone for a tel: call)."""
        order = {"free": 0, "busy": 1, "unknown": 2, "off": 3}
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            people = self._people(conn, business_id)
            for p in people:
                p.update(self.status_of(conn, p["id"]))
                p["on_job"] = conn.execute("SELECT COUNT(*) AS n FROM pos_dlv_jobs WHERE business_id = ? AND"
                                           " assignee_user = ? AND status IN ('given','picked')",
                                           (business_id, p["id"])).fetchone()["n"]
        people.sort(key=lambda p: (order.get(p["colour"], 9), p["role"] == "owner"))
        return {"people": people}

    # ------------------------------------------------------------------ route (cached per pair)
    def route(self, from_text: str, to_text: str, near: str = "") -> Dict[str, Any]:
        pair = f"{_clean(from_text, 80).lower()}|{_clean(to_text, 80).lower()}|{_clean(near, 60).lower()}"
        with self.store._connect() as conn:
            row = conn.execute("SELECT km, minutes, at FROM pos_route_cache WHERE pair = ?", (pair,)).fetchone()
        if row and self._now() - datetime.fromisoformat(row["at"]) < timedelta(days=ROUTE_DAYS):
            return {"km": row["km"], "minutes": row["minutes"], "cached": True}
        if self.maps is None or not getattr(self.maps, "enabled", False) or not from_text or not to_text:
            return {"km": None, "minutes": None, "cached": False}
        try:
            suffix = f", {near}" if near else ""
            a, b = self.maps.geocode(from_text + suffix), self.maps.geocode(to_text + suffix)
            if not a or not b or a.get("latitude") is None or b.get("latitude") is None:
                return {"km": None, "minutes": None, "cached": False}
            route = self.maps.compute_route([{"latitude": a["latitude"], "longitude": a["longitude"]},
                                             {"latitude": b["latitude"], "longitude": b["longitude"]}]) or {}
        except Exception:
            return {"km": None, "minutes": None, "cached": False}
        km, minutes = route.get("distance_km"), route.get("duration_minutes")
        if km is not None:
            with self.store._tx() as conn:
                conn.execute("INSERT OR REPLACE INTO pos_route_cache (pair, km, minutes, at) VALUES (?,?,?,?)",
                             (pair, km, minutes, self._now().isoformat()))
        return {"km": km, "minutes": minutes, "cached": False}

    def draft(self, business_id: str, user: str, text: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "sell")
            town = str(self.store._business_row(conn, business_id)["name"] or "")
        out = parse_line(text)
        out.update(self.route(out["from"], out["to"]))
        out["town"] = town
        return out

    # ------------------------------------------------------------------ jobs
    def _view(self, conn: sqlite3.Connection, row: Dict[str, Any], viewer: str) -> Dict[str, Any]:
        asks = [{"user": a["user_id"], "answer": a["answer"], "answered_at": a["answered_at"]}
                for a in conn.execute("SELECT user_id, answer, answered_at FROM pos_dlv_asks WHERE job_id = ?"
                                      " ORDER BY answered_at IS NULL, answered_at", (row["id"],))]
        names = {p["id"]: p for p in self._people(conn, row["business_id"])}
        for a in asks:
            a["label"] = names.get(a["user"], {}).get("label", "")
            a["phone"] = names.get(a["user"], {}).get("phone", "")
        shop = self.store._business_row(conn, row["business_id"])
        request = None
        if row["request_id"] and self.collect is not None:
            got = conn.execute("SELECT * FROM pos_payment_requests WHERE id = ?", (row["request_id"],)).fetchone()
            if got:
                request = self.collect._request_out(got)
        return {
            "id": row["id"], "business_id": row["business_id"], "shop": shop["name"], "order_no": row["order_no"],
            "label": f"#{row['order_no']}", "from": row["from_text"], "to": row["to_text"], "item": row["item"],
            "fee_paise": row["fee_paise"], "collect_paise": row["collect_paise"], "km": row["km"],
            "minutes": row["minutes"], "status": row["status"], "assignee_user": row["assignee_user"],
            "assignee_label": names.get(row["assignee_user"], {}).get("label", ""), "auto_first": bool(row["auto_first"]),
            "money_mode": row["money_mode"], "request": request, "asks": asks, "mine": row["assignee_user"] == viewer,
            "created_at": row["created_at"], "done_at": row["done_at"],
            "maps_url": "https://www.google.com/maps/dir/?api=1&destination=" + re.sub(r"\s+", "+", row["to_text"]),
        }

    def create(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        from_text, to_text = _clean(data.get("from"), 80), _clean(data.get("to"), 80)
        if not to_text:
            raise PosError(400, "places", "Say where it goes.")
        if not from_text:  # "గుడివాడ కి పార్సిల్" = from the shop itself
            with self.store._connect() as conn:
                from_text = _clean(self.store._business_row(conn, business_id)["name"], 80)
        fee, collect = _paise(data.get("fee_paise"), "fee_paise"), _paise(data.get("collect_paise"), "collect_paise")
        ask = data.get("ask") or "free"
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            people = {p["id"]: p for p in self._people(conn, business_id)}
            if ask == "free":
                targets = [pid for pid in people if pid != user and self.status_of(conn, pid)["colour"] == "free"]
            elif ask == "all":
                targets = [pid for pid in people if pid != user]
            else:
                targets = [pid for pid in (ask if isinstance(ask, list) else [ask]) if pid in people]
            if not targets:
                raise PosError(409, "nobody", "Nobody is free (green) right now. Choose a person, or ask everyone.")
            jid = f"dlv_{uuid.uuid4().hex[:16]}"
            no = self.next_order_no(conn, business_id)
            now = self._now().isoformat()
            km, minutes = data.get("km"), data.get("minutes")
            conn.execute("INSERT INTO pos_dlv_jobs (id, business_id, order_no, from_text, to_text, item, fee_paise,"
                         " collect_paise, km, minutes, auto_first, note, created_by, created_at, updated_at)"
                         " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                         (jid, business_id, no, from_text, to_text, _clean(data.get("item"), 80), fee, collect,
                          float(km) if isinstance(km, (int, float)) else None,
                          int(minutes) if isinstance(minutes, (int, float)) else None,
                          1 if data.get("auto_first") else 0, _clean(data.get("note"), 200), user, now, now))
            for pid in targets:
                conn.execute("INSERT OR IGNORE INTO pos_dlv_asks (job_id, user_id, asked_at) VALUES (?,?,?)",
                             (jid, pid, now))
            shop = self.store._business_row(conn, business_id)["name"]
        rupees = f" · ₹{fee // 100}" if fee else ""
        for pid in targets:
            self._push(pid, f"#{no} {from_text} → {to_text}{rupees}", f"{shop}: వస్తారా? · Can you go?",
                       "/me/jobs", f"dlv:{jid}:ask")
        return self.job(business_id, user, jid)

    def _push(self, user: str, title: str, body: str, route: str, key: str) -> None:
        try:
            self.notify(user, title, body, route, f"{key}:{user}")
        except Exception:
            pass

    def job(self, business_id: str, user: str, job_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            row = conn.execute("SELECT * FROM pos_dlv_jobs WHERE id = ? AND business_id = ?", (job_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "job", "Job not found.")
            return self._view(conn, dict(row), user)

    def jobs(self, business_id: str, user: str) -> Dict[str, Any]:
        since = (self._now() - timedelta(days=2)).isoformat()
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            rows = conn.execute("SELECT * FROM pos_dlv_jobs WHERE business_id = ? AND (status IN ('asking','given',"
                                "'picked') OR created_at >= ?) ORDER BY created_at DESC LIMIT 60",
                                (business_id, since)).fetchall()
            return {"jobs": [self._view(conn, dict(r), user) for r in rows]}

    def give(self, business_id: str, user: str, job_id: str, person: str, *, by_rule: bool = False) -> Dict[str, Any]:
        with self.store._tx() as conn:
            if not by_rule:
                self.store._require(conn, business_id, user, "sell")
            row = conn.execute("SELECT * FROM pos_dlv_jobs WHERE id = ? AND business_id = ?", (job_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "job", "Job not found.")
            if row["status"] != "asking":
                raise PosError(409, "taken", "This job is already given.")
            if person not in {p["id"] for p in self._people(conn, business_id)}:
                raise PosError(400, "person", "Choose a person of this shop.")
            conn.execute("UPDATE pos_dlv_jobs SET status = 'given', assignee_user = ?, updated_at = ? WHERE id = ?",
                         (person, self._now().isoformat(), job_id))
            self._set_status(conn, person, "busy", "job")
            others = [a["user_id"] for a in conn.execute("SELECT user_id FROM pos_dlv_asks WHERE job_id = ? AND user_id != ?",
                                                          (job_id, person))]
            no, to_text = row["order_no"], row["to_text"]
        self._push(person, f"#{no} మీకే · It's yours", f"→ {to_text}", "/me/jobs", f"dlv:{job_id}:given")
        for other in others:
            self._push(other, f"#{no} వేరే వాళ్ళకి ఇచ్చారు · Given to someone else", "", "/me/jobs", f"dlv:{job_id}:closed")
        return self.job(business_id, user if not by_rule else person, job_id)

    # ------------------------------------------------------------------ the person's side
    def _member_job(self, conn: sqlite3.Connection, user: str, job_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_dlv_jobs WHERE id = ?", (job_id,)).fetchone()
        if row is None:
            raise PosError(404, "job", "Job not found.")
        asked = conn.execute("SELECT 1 FROM pos_dlv_asks WHERE job_id = ? AND user_id = ?", (job_id, user)).fetchone()
        if not asked and row["assignee_user"] != user:
            raise PosError(404, "job", "Job not found.")
        return dict(row)

    def mine(self, user: str) -> Dict[str, Any]:
        """Offers waiting for my answer and my own running jobs, from every shop I work for."""
        with self.store._connect() as conn:
            offers = conn.execute("SELECT j.* FROM pos_dlv_jobs j JOIN pos_dlv_asks a ON a.job_id = j.id WHERE"
                                  " a.user_id = ? AND j.status = 'asking' ORDER BY j.created_at DESC LIMIT 20",
                                  (user,)).fetchall()
            running = conn.execute("SELECT * FROM pos_dlv_jobs WHERE assignee_user = ? AND status IN ('given','picked')"
                                   " ORDER BY created_at", (user,)).fetchall()
            today = self._now().astimezone(IST).replace(hour=0, minute=0, second=0, microsecond=0)
            cash = conn.execute("SELECT business_id, COALESCE(SUM(collect_paise), 0) AS paise, COUNT(*) AS n FROM"
                                " pos_dlv_jobs WHERE assignee_user = ? AND status = 'done' AND money_mode = 'cash' AND"
                                " done_at >= ? GROUP BY business_id", (user, today.astimezone(timezone.utc).isoformat())
                                ).fetchall()
            out = {"offers": [], "running": [self._view(conn, dict(r), user) for r in running],
                   "status": self.status_of(conn, user),
                   "cash_today": [{"business_id": c["business_id"], "paise": c["paise"], "jobs": c["n"]} for c in cash]}
            for r in offers:
                view = self._view(conn, dict(r), user)
                view["my_answer"] = next((a["answer"] for a in view["asks"] if a["user"] == user), "waiting")
                view.pop("asks", None)  # a person never sees the others' answers
                out["offers"].append(view)
            return out

    def answer(self, user: str, job_id: str, answer: str) -> Dict[str, Any]:
        if answer not in ANSWERS:
            raise PosError(400, "answer", "Answer now, 10, 20, 30 minutes or can't.")
        with self.store._tx() as conn:
            row = self._member_job(conn, user, job_id)
            if row["status"] != "asking":
                raise PosError(409, "taken", "This job is already given.")
            conn.execute("UPDATE pos_dlv_asks SET answer = ?, answered_at = ? WHERE job_id = ? AND user_id = ?",
                         (answer, self._now().isoformat(), job_id, user))
            label = next((p["label"] for p in self._people(conn, row["business_id"]) if p["id"] == user), "")
            owner = self.store._business_row(conn, row["business_id"])["owner_user_id"]
        words = {"now": "వెంటనే · now", "no": "కుదరదు · can't"}.get(answer, f"{answer} ని. · {answer} min")
        self._push(row["created_by"], f"#{row['order_no']} {label} – {words}", "", f"/pos/{row['business_id']}/jobs",
                   f"dlv:{job_id}:ans:{answer}")
        if owner and owner != row["created_by"]:
            self._push(owner, f"#{row['order_no']} {label} – {words}", "", f"/pos/{row['business_id']}/jobs",
                       f"dlv:{job_id}:ans:{answer}")
        if answer == "now" and row["auto_first"]:
            try:
                self.give(row["business_id"], user, job_id, user, by_rule=True)
            except PosError:
                pass  # someone else was first
        with self.store._connect() as conn:
            view = self._view(conn, dict(conn.execute("SELECT * FROM pos_dlv_jobs WHERE id = ?", (job_id,)).fetchone()), user)
        view.pop("asks", None)
        return view

    def step(self, user: str, job_id: str, step: str, money: str = "") -> Dict[str, Any]:
        """picked -> done (money cash / upi / prepaid) or cancelled. Done turns the person green again."""
        with self.store._tx() as conn:
            row = self._member_job(conn, user, job_id)
            if row["assignee_user"] != user:
                raise PosError(403, "not_yours", "This job is not given to you.")
            if step not in STEPS.get(row["status"], ()):
                raise PosError(409, "step", f"A {row['status']} job cannot go to {step}.")
            fields = {"status": step, "updated_at": self._now().isoformat()}
            if step == "done":
                if row["collect_paise"] and money not in MONEY:
                    raise PosError(400, "money", "How was it paid: cash, UPI or paid before?")
                if money == "upi" and row["request_id"]:
                    got = conn.execute("SELECT status FROM pos_payment_requests WHERE id = ?", (row["request_id"],)).fetchone()
                    fields["note"] = (row["note"] + " · UPI: owner check pending").strip(" ·") \
                        if not got or got["status"] != "confirmed" else row["note"]
                fields["money_mode"] = money or "prepaid"
                fields["done_at"] = self._now().isoformat()
                self._set_status(conn, user, "free", "job_done")
            if step == "cancelled":
                self._set_status(conn, user, "free", "job_cancelled")
            sets = ", ".join(f"{k} = ?" for k in fields)
            conn.execute(f"UPDATE pos_dlv_jobs SET {sets} WHERE id = ?", (*fields.values(), job_id))
            owner = self.store._business_row(conn, row["business_id"])["owner_user_id"]
            label = next((p["label"] for p in self._people(conn, row["business_id"]) if p["id"] == user), "")
        if step == "done":
            money_words = {"cash": f"₹{row['collect_paise'] // 100} క్యాష్ {label} దగ్గర",
                           "upi": "UPI – మీ phone లో చూడండి", "prepaid": "ముందే కట్టారు"}.get(fields.get("money_mode", ""), "")
            for target in dict.fromkeys([row["created_by"], owner]):
                self._push(target, f"#{row['order_no']} అయింది · Delivered", money_words,
                           f"/pos/{row['business_id']}/jobs", f"dlv:{job_id}:done")
        with self.store._connect() as conn:
            view = self._view(conn, dict(conn.execute("SELECT * FROM pos_dlv_jobs WHERE id = ?", (job_id,)).fetchone()), user)
        return view

    def collect_upi(self, user: str, job_id: str) -> Dict[str, Any]:
        """The person taps "UPI / QR": the OWNER's own UPI QR with the bill amount and the order number in the note.
        A notice of that money on the owner's phone tells BOTH (pos_payment_alerts)."""
        if self.collect is None:
            raise PosError(503, "collect", "UPI collect is not available.")
        with self.store._connect() as conn:
            row = self._member_job(conn, user, job_id)
        if row["assignee_user"] != user or not row["collect_paise"]:
            raise PosError(409, "collect", "Nothing to collect on this job.")
        if row["request_id"]:
            with self.store._connect() as conn:
                got = conn.execute("SELECT * FROM pos_payment_requests WHERE id = ?", (row["request_id"],)).fetchone()
            if got is not None and got["status"] in ("pending", "matched", "confirmed"):
                return self.collect._request_out(got)
        request = self.collect.create_request(row["business_id"], user, {
            "amount_paise": row["collect_paise"], "label": f"#{row['order_no']} {row['item']}".strip()[:60]}, any_member=True)
        with self.store._tx() as conn:
            conn.execute("UPDATE pos_dlv_jobs SET request_id = ?, updated_at = ? WHERE id = ?",
                         (request["id"], self._now().isoformat(), job_id))
        return request

    def day(self, business_id: str, user: str, day: str = "") -> Dict[str, Any]:
        """Day report per person: jobs done, cash each one is holding, UPI, paid before -- by order number."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            start = self._now().astimezone(IST).replace(hour=0, minute=0, second=0, microsecond=0)
            if day:
                try:
                    start = datetime.fromisoformat(day[:10]).replace(tzinfo=IST)
                except ValueError:
                    raise PosError(400, "day", "Day must be YYYY-MM-DD.")
            end = start + timedelta(days=1)
            rows = conn.execute("SELECT * FROM pos_dlv_jobs WHERE business_id = ? AND status = 'done' AND done_at >= ?"
                                " AND done_at < ? ORDER BY done_at", (business_id, start.astimezone(timezone.utc).isoformat(),
                                                                      end.astimezone(timezone.utc).isoformat())).fetchall()
            names = {p["id"]: p["label"] for p in self._people(conn, business_id)}
        per: Dict[str, Dict[str, Any]] = {}
        for r in rows:
            p = per.setdefault(r["assignee_user"], {"user": r["assignee_user"], "label": names.get(r["assignee_user"], ""),
                                                    "jobs": 0, "cash_paise": 0, "upi_paise": 0, "prepaid": 0,
                                                    "fee_paise": 0, "orders": []})
            p["jobs"] += 1
            p["fee_paise"] += r["fee_paise"]
            p["orders"].append(f"#{r['order_no']}")
            if r["money_mode"] == "cash":
                p["cash_paise"] += r["collect_paise"]
            elif r["money_mode"] == "upi":
                p["upi_paise"] += r["collect_paise"]
            else:
                p["prepaid"] += 1
        return {"day": start.date().isoformat(), "people": list(per.values())}
