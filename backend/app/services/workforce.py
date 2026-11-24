"""Workers under an authority (owner-approved plan 2026-11-24, design 73xSUHd4dbqVsLgRfCuX9X, steps 3-6).

ASKODOX cannot verify or follow up people; the AUTHORITY does (a shop / manpower consultancy / HR / travels / company
with a GST or Udyam number). ASKODOX never holds money.

Step 3 -- worker card -> authorities -> invite / accept:
  * A worker signs up ("నేను పని చేస్తా"): work types, area + km, when free, self-declared 18+ (mandatory).
  * The card goes to EVERY authority of a matching business category (owner 11:49: category-wide, not one shop):
    name, work, town, real ASKODOX jobs + rating -- NEVER the phone number.
  * The authority taps "invite" with what it asks for; the worker joins ONLY if he accepts; then his phone goes to
    THAT authority only. Documents are shown only with the worker's one-time code (OTP), VIEW only, 10 minutes.
  * Only GST / Udyam businesses browse cards and take orders (format checked; the certificate address = where a
    customer can go). A small shop without either adds only its own known staff by phone (POS staff) -- no browsing.
  * Checklists are the authority's own (suggested per work type); pay / terms are between them.
  * A worker may join many authorities; each sees only its own jobs and money; "leave" any time; old records stay.

Step 4 -- customer order -> authority: the customer sees AUTHORITIES with their prices, books one; the order reaches the
authority AND its free workers. A worker who accepts himself goes -- the authority cannot stop him, it is told at once,
and the money is CASH with the worker (owner 11:17). An order the authority assigns: money as the authority chose
(own UPI / cash). Worker's share = a record the worker confirms ("అందింది"). Complaints go to the authority with the
order number. Worker name + number reach the customer only after booking. A worker who is FREE (green) and refuses an
order gets a negative point (owner 11:49); refusing while OFF never counts.

Step 5 -- work types per business (Command Center resource ``work_types``, staff add rows) + monthly postings ("రాజు ->
ABC factory, night shift, December") with attendance at that site (live face check on the phone), seen by the agency.

Step 6 -- ratings + స్వతంత్రుడు badge: ratings only for completed + paid orders, one per order, the same customer counts
once a month per worker; each negative point counts as a 1-star. Badge = N days under an authority + N completed jobs +
average >= X + zero open complaints + own Udyam number; first N independent jobs capped at ₹N. Numbers = Command Center
settings. Lost below Y or with an open complaint.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import secrets
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services.pos_store import IST, PosError

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS wf_workers (user_id TEXT PRIMARY KEY, name TEXT NOT NULL, work_types TEXT NOT NULL,"
    " town TEXT NOT NULL DEFAULT '', lat REAL, lon REAL, km INTEGER NOT NULL DEFAULT 10, free_when TEXT NOT NULL"
    " DEFAULT '[]', adult INTEGER NOT NULL DEFAULT 0, udyam TEXT NOT NULL DEFAULT '', upi TEXT NOT NULL DEFAULT '',"
    " active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wf_authorities (business_id TEXT PRIMARY KEY, kind TEXT NOT NULL, gstin TEXT NOT NULL"
    " DEFAULT '', udyam TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', agency INTEGER NOT NULL DEFAULT 0,"
    " assigned_money TEXT NOT NULL DEFAULT 'cash', lat REAL, lon REAL, created_by TEXT NOT NULL, created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wf_links (business_id TEXT NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL,"
    " asks TEXT NOT NULL DEFAULT '', checks TEXT NOT NULL DEFAULT '{}', invited_by TEXT NOT NULL DEFAULT '',"
    " joined_at TEXT, updated_at TEXT NOT NULL, PRIMARY KEY (business_id, user_id))",
    "CREATE TABLE IF NOT EXISTS wf_prices (business_id TEXT NOT NULL, work_type TEXT NOT NULL, price_paise INTEGER"
    " NOT NULL, unit TEXT NOT NULL DEFAULT 'job', PRIMARY KEY (business_id, work_type))",
    "CREATE TABLE IF NOT EXISTS wf_docs (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, image BLOB"
    " NOT NULL, mime TEXT NOT NULL, created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wf_doc_codes (business_id TEXT NOT NULL, user_id TEXT NOT NULL, code_hash TEXT"
    " NOT NULL, expires_at TEXT NOT NULL, opened_until TEXT, PRIMARY KEY (business_id, user_id))",
    "CREATE TABLE IF NOT EXISTS wf_orders (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, order_no INTEGER NOT NULL,"
    " customer_user TEXT NOT NULL, work_type TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', place TEXT NOT NULL"
    " DEFAULT '', at_text TEXT NOT NULL DEFAULT '', price_paise INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL,"
    " worker_user TEXT NOT NULL DEFAULT '', taken_by TEXT NOT NULL DEFAULT '', money_mode TEXT NOT NULL DEFAULT '',"
    " paid INTEGER NOT NULL DEFAULT 0, share_paise INTEGER NOT NULL DEFAULT 0, share_ack INTEGER NOT NULL DEFAULT 0,"
    " independent INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, done_at TEXT)",
    "CREATE INDEX IF NOT EXISTS idx_wf_orders_biz ON wf_orders(business_id, status)",
    "CREATE INDEX IF NOT EXISTS idx_wf_orders_worker ON wf_orders(worker_user, status)",
    "CREATE TABLE IF NOT EXISTS wf_offers (order_id TEXT NOT NULL, user_id TEXT NOT NULL, answer TEXT NOT NULL"
    " DEFAULT 'waiting', status_when_asked TEXT NOT NULL DEFAULT '', at TEXT, PRIMARY KEY (order_id, user_id))",
    "CREATE TABLE IF NOT EXISTS wf_penalties (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL,"
    " order_id TEXT NOT NULL, reason TEXT NOT NULL, at TEXT NOT NULL, UNIQUE (user_id, order_id))",
    "CREATE TABLE IF NOT EXISTS wf_complaints (id TEXT PRIMARY KEY, order_id TEXT NOT NULL, business_id TEXT NOT NULL,"
    " worker_user TEXT NOT NULL DEFAULT '', customer_user TEXT NOT NULL, text TEXT NOT NULL, status TEXT NOT NULL"
    " DEFAULT 'open', reply TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, closed_at TEXT)",
    "CREATE TABLE IF NOT EXISTS wf_ratings (order_id TEXT PRIMARY KEY, worker_user TEXT NOT NULL, customer_user TEXT"
    " NOT NULL, stars INTEGER NOT NULL, month TEXT NOT NULL, counts INTEGER NOT NULL DEFAULT 1, at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wf_postings (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, user_id TEXT NOT NULL,"
    " site TEXT NOT NULL, shift TEXT NOT NULL DEFAULT 'day', month TEXT NOT NULL, lat REAL, lon REAL,"
    " status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS wf_post_attendance (posting_id TEXT NOT NULL, day TEXT NOT NULL, at TEXT NOT NULL,"
    " method TEXT NOT NULL, lat REAL, lon REAL, PRIMARY KEY (posting_id, day))",
]

# Step 5 defaults (seeded ONCE into the Command Center resource ``work_types``; staff add rows, no code).
# categories = Business Kit category keys whose shops need this work; "agency" = manpower consultancy / HR (any).
DEFAULT_WORK_TYPES: List[Dict[str, Any]] = [
    {"key": "delivery", "en": "Delivery", "te": "డెలివరీ", "categories": ["transport", "food", "grocery", "meat_fish",
     "veg_fruits", "dairy_bakery", "clothing", "mobile_electronics", "home_needs", "home_hardware", "jewellery",
     "health", "beauty"], "needs": ["licence"]},
    {"key": "car_driver", "en": "Car driver", "te": "కార్ డ్రైవర్", "categories": ["transport", "education"],
     "needs": ["licence"]},
    {"key": "bike_taxi", "en": "Bike taxi", "te": "బైక్ టాక్సీ", "categories": ["transport"],
     "needs": ["licence", "rc"]},
    {"key": "carpool", "en": "Carpool", "te": "కార్‌పూల్", "categories": ["transport"], "needs": ["licence", "rc", "seats"]},
    {"key": "parcel", "en": "Parcel / courier", "te": "పార్సిల్ / కొరియర్", "categories": ["transport"], "needs": []},
    {"key": "cook", "en": "Cook", "te": "వంటవాళ్ళు", "categories": ["food", "events"], "needs": []},
    {"key": "waiter", "en": "Waiter", "te": "వెయిటర్", "categories": ["food", "events"], "needs": []},
    {"key": "cleaner", "en": "Cleaning", "te": "క్లీనింగ్", "categories": ["food", "services", "events", "real_estate"],
     "needs": []},
    {"key": "sales", "en": "Sales", "te": "సేల్స్", "categories": ["grocery", "clothing", "mobile_electronics",
     "home_needs", "home_hardware", "jewellery", "vehicles"], "needs": []},
    {"key": "helper", "en": "Helper", "te": "హెల్పర్", "categories": ["grocery", "wholesale", "real_estate", "events",
     "farming", "home_hardware", "services"], "needs": []},
    {"key": "factory_worker", "en": "Company / factory worker", "te": "కంపెనీ / ఫ్యాక్టరీ వర్కర్",
     "categories": ["wholesale"], "needs": [], "posting": True},
    {"key": "supervisor", "en": "Supervisor", "te": "సూపర్‌వైజర్", "categories": ["wholesale", "real_estate"],
     "needs": [], "posting": True},
    {"key": "security", "en": "Security guard", "te": "సెక్యూరిటీ గార్డ్", "categories": ["wholesale", "education",
     "real_estate", "events", "services"], "needs": ["police_verification"], "posting": True},
    {"key": "ayah", "en": "Ayah / child care", "te": "ఆయా / పిల్లల సంరక్షణ", "categories": ["education", "services"],
     "needs": ["police_verification"], "home_entry": True},
    {"key": "elder_care", "en": "Elder care", "te": "వృద్ధుల సంరక్షణ", "categories": ["services", "health"],
     "needs": ["police_verification"], "home_entry": True},
    {"key": "house_help", "en": "House help / maid", "te": "ఇంటి పని", "categories": ["services"],
     "needs": ["police_verification"], "home_entry": True},
    {"key": "home_nursing", "en": "Home nursing", "te": "హోమ్ నర్సింగ్", "categories": ["health", "services"],
     "needs": ["police_verification", "nursing_certificate"], "home_entry": True},
]

NEED_NAMES = {"licence": ("Driving licence", "డ్రైవింగ్ లైసెన్స్"), "rc": ("Vehicle RC", "వాహనం RC"),
              "seats": ("Seats", "సీట్లు"), "police_verification": ("Police verification", "పోలీస్ వెరిఫికేషన్"),
              "nursing_certificate": ("Nursing certificate", "నర్సింగ్ సర్టిఫికేట్"),
              "aadhaar": ("Aadhaar (masked)", "ఆధార్ (మాస్క్)"), "passbook": ("Bank passbook", "బ్యాంక్ పాస్‌బుక్")}
DOC_KINDS = tuple(NEED_NAMES)
FREE_WHEN = ("day", "night", "sundays")
LINK_STATUSES = ("invited", "joined", "declined", "left", "removed")
ORDER_OPEN = ("open", "taken", "assigned")
SETTINGS = {  # Command Center settings (platform_settings) and their built-in values
    "workforce.badge_days": 90, "workforce.badge_jobs": 50, "workforce.badge_min_rating": 4.5,
    "workforce.badge_lose_below": 4.0, "workforce.first_jobs_capped": 20, "workforce.first_jobs_cap_rupees": 2000,
}
CODE_MINUTES, VIEW_MINUTES = 10, 10
ADDING_NOTE = ("ఈ వ్యక్తి మీ తరపున పని చేస్తారు. డబ్బు, కస్టమర్ విషయాలు మీ బాధ్యత. ASKODOX వెరిఫై చేయదు. · "
               "This person works on your behalf. Money and customers are your responsibility. ASKODOX does not verify.")
REJECT_NOTE = ("ఖాళీ (ఆకుపచ్చ) గా ఉండి పని వద్దంటే మైనస్ పాయింట్ పడుతుంది – స్వతంత్రుడు badge కి అడ్డం. ఖాళీ లేకపోతే ఆఫ్ చేసుకోండి. · "
               "Saying no while green (free) gives a minus point and blocks the independent badge. Not free? Turn OFF.")

_GSTIN = re.compile(r"^[0-3][0-9][A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")
_UDYAM = re.compile(r"^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$")
_GST_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

_SOURCE: Optional[Callable[[], list]] = None
_CACHE: Dict[str, Any] = {"at": 0.0, "value": None, "key": None}


def gstin_ok(value: str) -> bool:
    """Format + check digit (free, offline). A live government check needs a paid API (later)."""
    g = str(value or "").strip().upper()
    if not _GSTIN.match(g):
        return False
    total = 0
    for i, ch in enumerate(g[:14]):
        product = _GST_CHARS.index(ch) * (2 if i % 2 else 1)
        total += product // 36 + product % 36
    return _GST_CHARS[(36 - total % 36) % 36] == g[14]


def udyam_ok(value: str) -> bool:
    return bool(_UDYAM.match(str(value or "").strip().upper()))


def set_source(reader: Optional[Callable[[], list]], key: Any = None) -> None:
    global _SOURCE
    _SOURCE = reader
    if reader is None or key != _CACHE["key"]:
        _CACHE.update(at=0.0, value=None, key=key)


def seed_defaults(resources: Any) -> int:
    """Seed the Command Center resource ``work_types`` once (never over staff edits)."""
    if resources.repo.list("work_types", include_archived=True):
        return 0
    for i, w in enumerate(DEFAULT_WORK_TYPES):
        resources.create("work_types", {"key": w["key"], "label_en": w["en"], "label_te": w["te"],
                                        "categories": w["categories"], "needs": w.get("needs", []),
                                        "home_entry": bool(w.get("home_entry")), "posting": bool(w.get("posting")),
                                        "order": i}, actor="system:seed", status="ACTIVE")
    return len(DEFAULT_WORK_TYPES)


def work_types() -> List[Dict[str, Any]]:
    """The work types: code defaults, overridden / extended by the Command Center rows (30 s cache)."""
    now = time.monotonic()
    if _CACHE["value"] is not None and now - _CACHE["at"] < 30:
        return _CACHE["value"]
    by_key = {w["key"]: copy.deepcopy(w) for w in DEFAULT_WORK_TYPES}
    rows: list = []
    if _SOURCE is not None:
        try:
            rows = list(_SOURCE() or [])
        except Exception:
            rows = []
    for row in rows:
        data = row.get("data") or {}
        key = re.sub(r"[^a-z0-9_]", "", str(data.get("key") or "").strip().lower())
        if not key:
            continue
        if row.get("archived") or str(row.get("status") or "ACTIVE").upper() != "ACTIVE":
            by_key.pop(key, None)
            continue

        def as_list(v: Any) -> List[str]:
            if isinstance(v, str):
                v = re.split(r"[\n,]", v)
            return [str(x).strip() for x in (v or []) if str(x).strip()]

        by_key[key] = {"key": key, "en": str(data.get("label_en") or key), "te": str(data.get("label_te") or ""),
                       "categories": as_list(data.get("categories")), "needs": as_list(data.get("needs")),
                       "home_entry": bool(data.get("home_entry")), "posting": bool(data.get("posting"))}
    value = list(by_key.values())
    _CACHE.update(at=now, value=value)
    return value


def _types() -> Dict[str, Dict[str, Any]]:
    return {w["key"]: w for w in work_types()}


def types_for_category(category: str, agency: bool = False) -> List[str]:
    return [w["key"] for w in work_types() if agency or category in w["categories"]]


def _setting(key: str) -> float:
    try:
        from app.services import platform_settings

        return float(platform_settings.get(key, SETTINGS[key]))
    except Exception:
        return float(SETTINGS[key])


def _km(a: tuple, b: tuple) -> Optional[float]:
    if None in a or None in b:
        return None
    from math import asin, cos, radians, sin, sqrt

    lat1, lon1, lat2, lon2 = map(radians, (a[0], a[1], b[0], b[1]))
    h = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 6371 * 2 * asin(sqrt(h))


def _clean(value: Any, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _phone_of(user: str) -> str:
    digits = re.sub(r"\D", "", str(user or ""))[-10:]
    return digits if len(digits) == 10 and str(user).startswith("app-phone-") else ""


class Workforce:
    def __init__(self, store: Any, *, notify: Optional[Callable[..., Any]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        self.store = store
        self.notify = notify or (lambda *a, **k: None)
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        with store._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _now(self) -> datetime:
        return self.clock()

    def _push(self, user: str, title: str, body: str, route: str, key: str) -> None:
        if not user:
            return
        try:
            self.notify(user, title, body, route, f"{key}:{user}")
        except Exception:
            pass

    # ================================================================ step 3: the worker
    def save_worker(self, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        if data.get("adult") is not True:
            raise PosError(400, "adult", "You must be 18 or older to work (child labour is illegal).")
        types = [t for t in (data.get("work_types") or []) if t in _types()]
        if not types:
            raise PosError(400, "work_types", "Choose at least one work type.")
        name = _clean(data.get("name"), 60)
        if not name:
            raise PosError(400, "name", "Your name, please.")
        free = [w for w in (data.get("free_when") or []) if w in FREE_WHEN] or ["day"]
        udyam = _clean(data.get("udyam"), 25).upper()
        if udyam and not udyam_ok(udyam):
            raise PosError(400, "udyam", "Udyam number looks wrong (UDYAM-AP-00-0000000).")
        now = self._now().isoformat()
        lat, lon = data.get("lat"), data.get("lon")
        with self.store._tx() as conn:
            conn.execute(
                "INSERT INTO wf_workers (user_id, name, work_types, town, lat, lon, km, free_when, adult, udyam, upi,"
                " created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,1,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET"
                " name = excluded.name, work_types = excluded.work_types, town = excluded.town, lat = excluded.lat,"
                " lon = excluded.lon, km = excluded.km, free_when = excluded.free_when, udyam = excluded.udyam,"
                " upi = excluded.upi, active = 1, updated_at = excluded.updated_at",
                (user, name, json.dumps(types), _clean(data.get("town"), 60),
                 float(lat) if isinstance(lat, (int, float)) else None,
                 float(lon) if isinstance(lon, (int, float)) else None,
                 max(1, min(int(data.get("km") or 10), 100)), json.dumps(free), udyam,
                 _clean(data.get("upi"), 60), now, now))
        return self.me(user)

    def _stats(self, conn: sqlite3.Connection, user: str) -> Dict[str, Any]:
        jobs = conn.execute("SELECT COUNT(*) AS n FROM wf_orders WHERE worker_user = ? AND status = 'done'",
                            (user,)).fetchone()["n"]
        jobs += conn.execute("SELECT COUNT(*) AS n FROM pos_dlv_jobs WHERE assignee_user = ? AND status = 'done'",
                             (user,)).fetchone()["n"] if self._has(conn, "pos_dlv_jobs") else 0
        stars = [r["stars"] for r in conn.execute("SELECT stars FROM wf_ratings WHERE worker_user = ? AND counts = 1",
                                                  (user,))]
        minus = conn.execute("SELECT COUNT(*) AS n FROM wf_penalties WHERE user_id = ?", (user,)).fetchone()["n"]
        all_stars = stars + [1] * minus  # owner 11:49: a refusal while free counts like a 1-star
        rating = round(sum(all_stars) / len(all_stars), 2) if all_stars else None
        open_c = conn.execute("SELECT COUNT(*) AS n FROM wf_complaints WHERE worker_user = ? AND status = 'open'",
                              (user,)).fetchone()["n"]
        return {"jobs": jobs, "rating": rating, "ratings": len(stars), "minus_points": minus, "open_complaints": open_c}

    @staticmethod
    def _has(conn: sqlite3.Connection, table: str) -> bool:
        return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", (table,)).fetchone() is not None

    def _card(self, conn: sqlite3.Connection, row: sqlite3.Row) -> Dict[str, Any]:
        """What an authority sees before the worker joins: never the phone number."""
        types = _types()
        stats = self._stats(conn, row["user_id"])
        return {"user": row["user_id"], "name": row["name"], "town": row["town"],
                "work_types": [{"key": t, "en": types.get(t, {}).get("en", t), "te": types.get(t, {}).get("te", "")}
                               for t in json.loads(row["work_types"] or "[]")],
                "free_when": json.loads(row["free_when"] or "[]"), **stats,
                "badge": self._badge(conn, row["user_id"])["has"]}

    def me(self, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM wf_workers WHERE user_id = ?", (user,)).fetchone()
            links = [dict(r) for r in conn.execute(
                "SELECT l.business_id, l.status, l.asks, l.joined_at, b.name FROM wf_links l JOIN pos_businesses b ON"
                " b.id = l.business_id WHERE l.user_id = ? AND l.status IN ('invited','joined')", (user,))]
            docs = [{"id": d["id"], "kind": d["kind"]} for d in conn.execute(
                "SELECT id, kind FROM wf_docs WHERE user_id = ? ORDER BY created_at", (user,))]
            postings = [dict(p) for p in conn.execute(
                "SELECT p.*, b.name AS agency FROM wf_postings p JOIN pos_businesses b ON b.id = p.business_id WHERE"
                " p.user_id = ? AND p.status = 'active'", (user,))]
            if row is None:
                return {"worker": None, "links": links, "docs": docs, "postings": postings, "reject_note": REJECT_NOTE,
                        "work_types": work_types()}
            card = self._card(conn, row)
            card.update({"km": row["km"], "udyam": row["udyam"], "upi": row["upi"], "lat": row["lat"], "lon": row["lon"]})
            badge = self._badge(conn, user)
        return {"worker": card, "links": links, "docs": docs, "postings": postings, "badge": badge,
                "reject_note": REJECT_NOTE, "work_types": work_types()}

    # ---------------------------------------------------------------- authorities
    def set_authority(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Owner only. GST or Udyam number (format checked) + the certificate address; agency = manpower / HR."""
        gstin = _clean(data.get("gstin"), 15).upper()
        udyam = _clean(data.get("udyam"), 25).upper()
        if gstin and not gstin_ok(gstin):
            raise PosError(400, "gstin", "GST number looks wrong. Check the 15 letters / digits.")
        if udyam and not udyam_ok(udyam):
            raise PosError(400, "udyam", "Udyam number looks wrong (UDYAM-AP-00-0000000).")
        kind = "gst" if gstin else "udyam" if udyam else "small"
        address = _clean(data.get("address"), 200)
        if kind != "small" and not address:
            raise PosError(400, "address", "The address on the certificate (where a customer can come and ask).")
        money = data.get("assigned_money") if data.get("assigned_money") in ("cash", "upi", "both") else "cash"
        now = self._now().isoformat()
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "view")
            if role != "owner":
                raise PosError(403, "permission", "Only the owner sets the business registration.")
            conn.execute(
                "INSERT INTO wf_authorities (business_id, kind, gstin, udyam, address, agency, assigned_money, lat, lon,"
                " created_by, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(business_id) DO"
                " UPDATE SET kind = excluded.kind, gstin = excluded.gstin, udyam = excluded.udyam, address ="
                " excluded.address, agency = excluded.agency, assigned_money = excluded.assigned_money, lat ="
                " excluded.lat, lon = excluded.lon, updated_at = excluded.updated_at",
                (business_id, kind, gstin, udyam, address, 1 if data.get("agency") else 0, money,
                 data.get("lat") if isinstance(data.get("lat"), (int, float)) else None,
                 data.get("lon") if isinstance(data.get("lon"), (int, float)) else None, user, now, now))
            for wt, price in (data.get("prices") or {}).items():
                if wt in _types() and isinstance(price, int) and price >= 0:
                    conn.execute("INSERT OR REPLACE INTO wf_prices (business_id, work_type, price_paise) VALUES (?,?,?)",
                                 (business_id, wt, price))
        return self.authority(business_id, user)

    def _authority_row(self, conn: sqlite3.Connection, business_id: str) -> Optional[sqlite3.Row]:
        return conn.execute("SELECT * FROM wf_authorities WHERE business_id = ?", (business_id,)).fetchone()

    def _category(self, conn: sqlite3.Connection, business_id: str) -> str:
        try:
            from app.services.shop_follows import ShopFollows

            return str(ShopFollows._fields(conn, business_id).get("category", "") or "")
        except Exception:
            return ""

    def _wanted_types(self, conn: sqlite3.Connection, business_id: str) -> List[str]:
        auth = self._authority_row(conn, business_id)
        return types_for_category(self._category(conn, business_id), bool(auth and auth["agency"]))

    def authority(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            auth = self._authority_row(conn, business_id)
            prices = {r["work_type"]: r["price_paise"] for r in conn.execute(
                "SELECT work_type, price_paise FROM wf_prices WHERE business_id = ?", (business_id,))}
            team = [self._team_row(conn, business_id, dict(r)) for r in conn.execute(
                "SELECT * FROM wf_links WHERE business_id = ? AND status IN ('invited','joined') ORDER BY updated_at DESC",
                (business_id,))]
            wanted = self._wanted_types(conn, business_id)
        types = _types()
        return {"authority": dict(auth) if auth else None,
                "can_browse": bool(auth and auth["kind"] in ("gst", "udyam")),
                "work_types": [{"key": k, "en": types[k]["en"], "te": types[k]["te"], "needs": types[k]["needs"],
                                "price_paise": prices.get(k)} for k in wanted if k in types],
                "team": team, "adding_note": ADDING_NOTE,
                "udyam_help": "Udyam registration is free (Aadhaar based): udyamregistration.gov.in -> 'For New "
                              "Entrepreneurs' -> Aadhaar + OTP -> PAN -> business details. ఉచితం, ఆధార్ తో."}

    def _team_row(self, conn: sqlite3.Connection, business_id: str, link: Dict[str, Any]) -> Dict[str, Any]:
        worker = conn.execute("SELECT * FROM wf_workers WHERE user_id = ?", (link["user_id"],)).fetchone()
        out = {"user": link["user_id"], "status": link["status"], "asks": link["asks"],
               "checks": json.loads(link["checks"] or "{}"), "joined_at": link["joined_at"]}
        if worker is not None:
            out.update(self._card(conn, worker))
        if link["status"] == "joined":  # the phone only after the worker joined THIS authority
            out["phone"] = _phone_of(link["user_id"])
        out["status_colour"] = self._colour(conn, link["user_id"])
        types = _types()
        needs = sorted({n for t in (json.loads(worker["work_types"]) if worker else []) for n in types.get(t, {}).get("needs", [])})
        out["suggested_checks"] = [{"key": n, "en": NEED_NAMES.get(n, (n, n))[0], "te": NEED_NAMES.get(n, (n, n))[1]}
                                   for n in needs]
        return out

    def _colour(self, conn: sqlite3.Connection, user: str) -> str:
        if not self._has(conn, "pos_work_status"):
            return "unknown"
        from app.services.pos_delivery_jobs import PosDeliveryJobs

        return PosDeliveryJobs.status_of(_ColourOnly(self.clock), conn, user)["colour"]  # type: ignore[arg-type]

    def cards(self, business_id: str, user: str, work_type: str = "") -> Dict[str, Any]:
        """Worker cards for a GST / Udyam authority: every worker of a work type this business category needs, in
        the area (the worker's own km), not yet in this team. Never a phone number."""
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "members")
            auth = self._authority_row(conn, business_id)
            if not auth or auth["kind"] not in ("gst", "udyam"):
                raise PosError(403, "gate", "Only a business with a GST or Udyam number can see worker cards. Small shop? "
                               "Add your own staff by phone on the Staff page (Udyam registration is free).")
            wanted = set(self._wanted_types(conn, business_id))
            if work_type:
                wanted &= {work_type}
            taken = {r["user_id"] for r in conn.execute(
                "SELECT user_id FROM wf_links WHERE business_id = ? AND status IN ('invited','joined')", (business_id,))}
            out = []
            for row in conn.execute("SELECT * FROM wf_workers WHERE active = 1 AND adult = 1"):
                if row["user_id"] in taken or row["user_id"] == user or not wanted & set(json.loads(row["work_types"])):
                    continue
                dist = _km((auth["lat"], auth["lon"]), (row["lat"], row["lon"]))
                if dist is not None and dist > row["km"]:
                    continue
                card = self._card(conn, row)
                card["km_away"] = round(dist, 1) if dist is not None else None
                out.append(card)
        out.sort(key=lambda c: (c["km_away"] is None, c["km_away"] or 0, -(c["rating"] or 0)))
        return {"cards": out[:100]}

    def invite(self, business_id: str, user: str, worker: str, asks: str = "") -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            auth = self._authority_row(conn, business_id)
            if not auth or auth["kind"] not in ("gst", "udyam"):
                raise PosError(403, "gate", "Only a business with a GST or Udyam number can invite workers.")
            if conn.execute("SELECT 1 FROM wf_workers WHERE user_id = ? AND active = 1", (worker,)).fetchone() is None:
                raise PosError(404, "worker", "Worker not found.")
            now = self._now().isoformat()
            conn.execute("INSERT INTO wf_links (business_id, user_id, status, asks, invited_by, updated_at) VALUES"
                         " (?,?,?,?,?,?) ON CONFLICT(business_id, user_id) DO UPDATE SET status = 'invited', asks ="
                         " excluded.asks, invited_by = excluded.invited_by, updated_at = excluded.updated_at",
                         (business_id, worker, "invited", _clean(asks, 300), user, now))
            name = self.store._business_row(conn, business_id)["name"]
        self._push(worker, f"{name} మిమ్మల్ని చేర్చుకోవాలనుకుంటోంది · wants you in their team",
                   f"వాళ్ళు అడుగుతున్నవి: {asks}" if asks else "", "/me/work", f"wf:{business_id}:invite")
        return {"invited": True}

    def answer_invite(self, user: str, business_id: str, accept: bool) -> Dict[str, Any]:
        with self.store._tx() as conn:
            link = conn.execute("SELECT * FROM wf_links WHERE business_id = ? AND user_id = ?", (business_id, user)).fetchone()
            if link is None or link["status"] != "invited":
                raise PosError(404, "invite", "No invite from this business.")
            now = self._now().isoformat()
            conn.execute("UPDATE wf_links SET status = ?, joined_at = ?, updated_at = ? WHERE business_id = ? AND user_id = ?",
                         ("joined" if accept else "declined", now if accept else None, now, business_id, user))
            owner = self.store._business_row(conn, business_id)["owner_user_id"]
            name = conn.execute("SELECT name FROM wf_workers WHERE user_id = ?", (user,)).fetchone()["name"]
            phone = _phone_of(user)
            if accept and phone:
                # The worker becomes this shop's delivery / work person, so step-1 jobs reach him too.
                conn.execute("INSERT INTO pos_members (business_id, phone_key, app_user_id, role, active, added_by,"
                             " created_at, label) VALUES (?,?,?,?,1,?,?,?) ON CONFLICT(business_id, phone_key) DO"
                             " UPDATE SET active = 1, app_user_id = excluded.app_user_id",
                             (business_id, phone, user, "delivery", owner, now, name[:40]))
        self._push(owner, f"{name} {'చేరారు · joined' if accept else 'చేరలేదు · declined'}", "",
                   f"/pos/{business_id}/team", f"wf:{business_id}:{user}:answer")
        return {"status": "joined" if accept else "declined"}

    def leave(self, user: str, business_id: str, *, by_authority: str = "") -> Dict[str, Any]:
        with self.store._tx() as conn:
            if by_authority:
                self.store._require(conn, business_id, by_authority, "members")
            status = "removed" if by_authority else "left"
            conn.execute("UPDATE wf_links SET status = ?, updated_at = ? WHERE business_id = ? AND user_id = ? AND"
                         " status IN ('invited','joined')", (status, self._now().isoformat(), business_id, user))
            phone = _phone_of(user)
            if phone:
                conn.execute("UPDATE pos_members SET active = 0 WHERE business_id = ? AND phone_key = ? AND role ="
                             " 'delivery'", (business_id, phone))
        return {"status": status}  # old records stay with the authority

    def set_checks(self, business_id: str, user: str, worker: str, checks: Dict[str, bool]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            clean = {str(k)[:30]: bool(v) for k, v in (checks or {}).items()}
            conn.execute("UPDATE wf_links SET checks = ?, updated_at = ? WHERE business_id = ? AND user_id = ?",
                         (json.dumps(clean), self._now().isoformat(), business_id, worker))
        return {"checks": clean}

    # ---------------------------------------------------------------- documents: worker's OTP, view only
    def add_doc(self, user: str, kind: str, image: bytes, mime: str) -> Dict[str, Any]:
        if kind not in DOC_KINDS:
            raise PosError(400, "kind", "Unknown document.")
        if mime not in ("image/jpeg", "image/png") or not image or len(image) > 600_000:
            raise PosError(400, "image", "A JPEG / PNG photo under 600 KB.")
        did = f"wfd_{uuid.uuid4().hex[:16]}"
        with self.store._tx() as conn:
            conn.execute("DELETE FROM wf_docs WHERE user_id = ? AND kind = ?", (user, kind))
            conn.execute("INSERT INTO wf_docs (id, user_id, kind, image, mime, created_at) VALUES (?,?,?,?,?,?)",
                         (did, user, kind, image, mime, self._now().isoformat()))
        return {"id": did, "kind": kind}

    def doc_code(self, user: str, business_id: str) -> Dict[str, Any]:
        """The worker makes a one-time code for ONE authority he joined (or was invited by); he tells it to them."""
        with self.store._tx() as conn:
            link = conn.execute("SELECT status FROM wf_links WHERE business_id = ? AND user_id = ?", (business_id, user)).fetchone()
            if link is None or link["status"] not in ("invited", "joined"):
                raise PosError(404, "link", "Not in this business.")
            code = f"{secrets.randbelow(1_000_000):06d}"
            conn.execute("INSERT OR REPLACE INTO wf_doc_codes (business_id, user_id, code_hash, expires_at) VALUES (?,?,?,?)",
                         (business_id, user, hashlib.sha256(code.encode()).hexdigest(),
                          (self._now() + timedelta(minutes=CODE_MINUTES)).isoformat()))
        return {"code": code, "minutes": CODE_MINUTES}

    def open_docs(self, business_id: str, user: str, worker: str, code: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            row = conn.execute("SELECT * FROM wf_doc_codes WHERE business_id = ? AND user_id = ?", (business_id, worker)).fetchone()
            now = self._now()
            if (row is None or datetime.fromisoformat(row["expires_at"]) < now
                    or hashlib.sha256(str(code).strip().encode()).hexdigest() != row["code_hash"]):
                raise PosError(403, "code", "Wrong or old code. Ask the worker for a new one.")
            until = (now + timedelta(minutes=VIEW_MINUTES)).isoformat()
            conn.execute("UPDATE wf_doc_codes SET code_hash = '', opened_until = ? WHERE business_id = ? AND user_id = ?",
                         (until, business_id, worker))
            docs = [{"id": d["id"], "kind": d["kind"]} for d in conn.execute(
                "SELECT id, kind FROM wf_docs WHERE user_id = ?", (worker,))]
        self._push(worker, "మీ documents చూస్తున్నారు · Your documents were opened", "", "/me/work", f"wf:{business_id}:docs")
        return {"docs": docs, "until": until, "view_only": True}

    def doc_image(self, business_id: str, user: str, worker: str, doc_id: str) -> tuple:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "members")
            row = conn.execute("SELECT opened_until FROM wf_doc_codes WHERE business_id = ? AND user_id = ?",
                               (business_id, worker)).fetchone()
            if row is None or not row["opened_until"] or datetime.fromisoformat(row["opened_until"]) < self._now():
                raise PosError(403, "code", "Ask the worker for a code first.")
            doc = conn.execute("SELECT image, mime FROM wf_docs WHERE id = ? AND user_id = ?", (doc_id, worker)).fetchone()
            if doc is None:
                raise PosError(404, "doc", "Not found.")
            return bytes(doc["image"]), doc["mime"]

    # ================================================================ step 4: customer orders
    def authorities_for(self, work_type: str, lat: Optional[float] = None, lon: Optional[float] = None) -> Dict[str, Any]:
        """What a customer sees: AUTHORITIES (and స్వతంత్రుడు workers) with their prices -- never loose workers."""
        if work_type not in _types():
            raise PosError(400, "work_type", "Unknown work.")
        out = []
        with self.store._connect() as conn:
            for a in conn.execute("SELECT a.*, b.name FROM wf_authorities a JOIN pos_businesses b ON b.id = a.business_id"
                                  " WHERE a.kind IN ('gst','udyam') AND COALESCE(b.status, 'open') = 'open'"):
                if work_type not in self._wanted_types(conn, a["business_id"]):
                    continue
                team = conn.execute("SELECT COUNT(*) AS n FROM wf_links WHERE business_id = ? AND status = 'joined'",
                                    (a["business_id"],)).fetchone()["n"]
                if not team:
                    continue
                price = conn.execute("SELECT price_paise FROM wf_prices WHERE business_id = ? AND work_type = ?",
                                     (a["business_id"], work_type)).fetchone()
                dist = _km((lat, lon), (a["lat"], a["lon"]))
                out.append({"kind": "authority", "business_id": a["business_id"], "name": a["name"],
                            "address": a["address"], "price_paise": price["price_paise"] if price else None,
                            "team": team, "km_away": round(dist, 1) if dist is not None else None})
            for w in conn.execute("SELECT * FROM wf_workers WHERE active = 1"):
                if work_type in json.loads(w["work_types"]) and self._badge(conn, w["user_id"])["has"]:
                    stats = self._stats(conn, w["user_id"])
                    out.append({"kind": "independent", "worker": w["user_id"], "name": w["name"],
                                "label": f"స్వతంత్రుడు · {stats['rating'] or '-'} ⭐ · {stats['jobs']} పనులు · ఏ షాప్ కిందా కాదు",
                                "price_paise": None, "km_away": _km((lat, lon), (w["lat"], w["lon"]))})
        out.sort(key=lambda x: (x["km_away"] is None, x["km_away"] or 0))
        return {"options": out}

    def place(self, customer: str, data: Dict[str, Any]) -> Dict[str, Any]:
        work_type = str(data.get("work_type") or "")
        if work_type not in _types():
            raise PosError(400, "work_type", "Unknown work.")
        business_id = str(data.get("business_id") or "")
        independent = str(data.get("worker") or "")
        now = self._now().isoformat()
        with self.store._tx() as conn:
            if independent:
                if not self._badge(conn, independent)["has"]:
                    raise PosError(409, "badge", "This worker is not independent; book through a business.")
                cap = self._first_cap(conn, independent)
                price = int(data.get("price_paise") or 0)
                if cap and price > cap:
                    raise PosError(409, "cap", f"New independent worker: up to ₹{cap // 100} a job for now.")
                business_id = f"ind:{independent}"
            else:
                auth = self._authority_row(conn, business_id)
                if not auth or auth["kind"] not in ("gst", "udyam"):
                    raise PosError(404, "authority", "Business not found.")
            from app.services.pos_delivery_jobs import PosDeliveryJobs

            no = PosDeliveryJobs.next_order_no(conn, business_id)
            price_row = None if independent else conn.execute(
                "SELECT price_paise FROM wf_prices WHERE business_id = ? AND work_type = ?", (business_id, work_type)).fetchone()
            oid = f"wfo_{uuid.uuid4().hex[:16]}"
            conn.execute("INSERT INTO wf_orders (id, business_id, order_no, customer_user, work_type, details, place, at_text,"
                         " price_paise, status, independent, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                         (oid, business_id, no, customer, work_type, _clean(data.get("details"), 300),
                          _clean(data.get("place"), 120), _clean(data.get("at"), 60),
                          int(data.get("price_paise") or 0) if independent else (price_row["price_paise"] if price_row else 0),
                          "open", 1 if independent else 0, now, now))
            asked: List[str] = []
            if independent:
                asked = [independent]
            else:
                types = _types()
                home = types[work_type].get("home_entry")
                for link in conn.execute("SELECT user_id, checks FROM wf_links WHERE business_id = ? AND status = 'joined'",
                                         (business_id,)):
                    w = conn.execute("SELECT work_types FROM wf_workers WHERE user_id = ?", (link["user_id"],)).fetchone()
                    if not w or work_type not in json.loads(w["work_types"]):
                        continue
                    if home and not json.loads(link["checks"] or "{}").get("police_verification"):
                        continue  # home-entry work: only workers with police verification ticked get it by themselves
                    if self._colour(conn, link["user_id"]) == "free":
                        asked.append(link["user_id"])
            for u in asked:
                conn.execute("INSERT OR IGNORE INTO wf_offers (order_id, user_id, status_when_asked) VALUES (?,?,?)",
                             (oid, u, "free"))
            owner = None if independent else self.store._business_row(conn, business_id)["owner_user_id"]
        title = f"#{no} {_types()[work_type]['te'] or work_type} · {_clean(data.get('place'), 40)}"
        if owner:
            self._push(owner, title, "కొత్త ఆర్డర్ · New order", f"/pos/{business_id}/team", f"wf:{oid}:new")
        for u in asked:
            self._push(u, title, "ఒప్పుకుంటారా? · Will you take it?", "/me/work", f"wf:{oid}:ask")
        return self.order(customer, oid)

    def _first_cap(self, conn: sqlite3.Connection, worker: str) -> int:
        done = conn.execute("SELECT COUNT(*) AS n FROM wf_orders WHERE worker_user = ? AND independent = 1 AND status = 'done'",
                            (worker,)).fetchone()["n"]
        return int(_setting("workforce.first_jobs_cap_rupees") * 100) if done < _setting("workforce.first_jobs_capped") else 0

    def _order_view(self, conn: sqlite3.Connection, row: Dict[str, Any], viewer: str) -> Dict[str, Any]:
        types = _types()
        out = {k: row[k] for k in ("id", "business_id", "order_no", "work_type", "details", "place", "at_text",
                                   "price_paise", "status", "taken_by", "money_mode", "share_paise", "created_at", "done_at")}
        out["label"] = f"#{row['order_no']}"
        out["work_en"], out["work_te"] = types.get(row["work_type"], {}).get("en", ""), types.get(row["work_type"], {}).get("te", "")
        out["share_ack"] = bool(row["share_ack"])
        out["independent"] = bool(row["independent"])
        if not row["independent"]:
            biz = conn.execute("SELECT name FROM pos_businesses WHERE id = ?", (row["business_id"],)).fetchone()
            out["authority"] = biz["name"] if biz else ""
        worker = conn.execute("SELECT name, upi FROM wf_workers WHERE user_id = ?", (row["worker_user"],)).fetchone() \
            if row["worker_user"] else None
        if worker is not None and viewer in (row["customer_user"],) and row["status"] != "open":
            out["worker_name"], out["worker_phone"] = worker["name"], _phone_of(row["worker_user"])  # after booking only
            if row["independent"]:
                out["pay_upi"] = worker["upi"]  # a స్వతంత్రుడు's own UPI
        elif worker is not None:
            out["worker_name"] = worker["name"]
        out["rated"] = conn.execute("SELECT 1 FROM wf_ratings WHERE order_id = ?", (row["id"],)).fetchone() is not None
        out["complaints"] = [dict(c) for c in conn.execute(
            "SELECT id, text, status, reply, created_at FROM wf_complaints WHERE order_id = ?", (row["id"],))]
        return out

    def order(self, viewer: str, order_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ?", (order_id,)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            row = dict(row)
            allowed = viewer in (row["customer_user"], row["worker_user"]) or conn.execute(
                "SELECT 1 FROM wf_offers WHERE order_id = ? AND user_id = ?", (order_id, viewer)).fetchone() is not None
            if not allowed and not row["independent"]:
                try:
                    self.store._require(conn, row["business_id"], viewer, "view")
                    allowed = True
                except PosError:
                    pass
            if not allowed:
                raise PosError(404, "order", "Order not found.")
            return self._order_view(conn, row, viewer)

    def my_orders(self, customer: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            rows = conn.execute("SELECT * FROM wf_orders WHERE customer_user = ? ORDER BY created_at DESC LIMIT 50", (customer,))
            return {"orders": [self._order_view(conn, dict(r), customer) for r in rows]}

    def worker_orders(self, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            offers = conn.execute("SELECT o.* FROM wf_orders o JOIN wf_offers f ON f.order_id = o.id WHERE f.user_id = ?"
                                  " AND o.status = 'open' AND f.answer = 'waiting' ORDER BY o.created_at DESC", (user,)).fetchall()
            mine = conn.execute("SELECT * FROM wf_orders WHERE worker_user = ? AND status IN ('taken','assigned','done')"
                                " ORDER BY created_at DESC LIMIT 30", (user,)).fetchall()
            return {"offers": [self._order_view(conn, dict(r), user) for r in offers],
                    "mine": [self._order_view(conn, dict(r), user) for r in mine]}

    def authority_orders(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            rows = conn.execute("SELECT * FROM wf_orders WHERE business_id = ? ORDER BY created_at DESC LIMIT 80", (business_id,))
            return {"orders": [self._order_view(conn, dict(r), user) for r in rows]}

    def worker_answer(self, user: str, order_id: str, accept: bool) -> Dict[str, Any]:
        """A worker takes an order himself (the authority cannot stop him; it is told) or says no. Saying no while
        FREE (green) = a minus point (owner 11:49); while OFF it never counts."""
        with self.store._tx() as conn:
            offer = conn.execute("SELECT * FROM wf_offers WHERE order_id = ? AND user_id = ?", (order_id, user)).fetchone()
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ?", (order_id,)).fetchone()
            if offer is None or row is None:
                raise PosError(404, "order", "Order not found.")
            now = self._now().isoformat()
            conn.execute("UPDATE wf_offers SET answer = ?, at = ? WHERE order_id = ? AND user_id = ?",
                         ("yes" if accept else "no", now, order_id, user))
            if not accept:
                if self._colour(conn, user) == "free":
                    conn.execute("INSERT OR IGNORE INTO wf_penalties (user_id, order_id, reason, at) VALUES (?,?,?,?)",
                                 (user, order_id, "refused_while_free", now))
                return {"answer": "no", "minus_point": self._colour(conn, user) == "free", "note": REJECT_NOTE}
            if row["status"] != "open":
                raise PosError(409, "taken", "Someone already took this order.")
            # Owner 11:17: an order the worker takes HIMSELF is settled in cash with him.
            conn.execute("UPDATE wf_orders SET status = 'taken', worker_user = ?, taken_by = 'worker', money_mode = 'cash',"
                         " updated_at = ? WHERE id = ?", (user, now, order_id))
            if self._has(conn, "pos_work_status"):
                conn.execute("INSERT OR REPLACE INTO pos_work_status (user_id, colour, reason, set_at) VALUES (?,?,?,?)",
                             (user, "busy", "job", now))
            name = conn.execute("SELECT name FROM wf_workers WHERE user_id = ?", (user,)).fetchone()["name"]
            owner = None if row["independent"] else self.store._business_row(conn, row["business_id"])["owner_user_id"]
        if owner:
            self._push(owner, f"{name} #{row['order_no']} ఒప్పుకుంది, పనికి వెళ్ళింది · took it", "",
                       f"/pos/{row['business_id']}/team", f"wf:{order_id}:taken")
        self._push(row["customer_user"], f"#{row['order_no']} {name} వస్తున్నారు · is coming", "", "/me/hire",
                   f"wf:{order_id}:coming")
        return self.order(user, order_id)

    def assign(self, business_id: str, user: str, order_id: str, worker: str, money: str = "") -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            auth = self._authority_row(conn, business_id)
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if row["status"] != "open":
                raise PosError(409, "taken", "Already taken.")
            if conn.execute("SELECT 1 FROM wf_links WHERE business_id = ? AND user_id = ? AND status = 'joined'",
                            (business_id, worker)).fetchone() is None:
                raise PosError(400, "worker", "Choose a worker of your team.")
            home = _types().get(row["work_type"], {}).get("home_entry")
            checks = json.loads(conn.execute("SELECT checks FROM wf_links WHERE business_id = ? AND user_id = ?",
                                             (business_id, worker)).fetchone()["checks"] or "{}")
            if home and not checks.get("police_verification") and money != "confirm_home":
                # Plan rule 10: home-entry work without police verification ticked -> asked ONCE before sending.
                raise PosError(409, "home_entry", "This work goes inside a home and this person's police verification is "
                               "not ticked. Send anyway?", ask_once=True)
            mode = money if money in ("cash", "upi") else (auth["assigned_money"] if auth else "cash")
            now = self._now().isoformat()
            conn.execute("UPDATE wf_orders SET status = 'assigned', worker_user = ?, taken_by = 'authority', money_mode = ?,"
                         " updated_at = ? WHERE id = ?", (worker, "cash" if mode == "both" else mode, now, order_id))
        self._push(worker, f"#{row['order_no']} మీకు ఇచ్చారు · assigned to you", row["place"], "/me/work", f"wf:{order_id}:assigned")
        return self.order(user, order_id)

    def done(self, user: str, order_id: str, paid: bool = True) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ? AND worker_user = ?", (order_id, user)).fetchone()
            if row is None or row["status"] not in ("taken", "assigned"):
                raise PosError(404, "order", "Order not found.")
            now = self._now().isoformat()
            conn.execute("UPDATE wf_orders SET status = 'done', paid = ?, done_at = ?, updated_at = ? WHERE id = ?",
                         (1 if paid else 0, now, now, order_id))
            if self._has(conn, "pos_work_status"):
                conn.execute("INSERT OR REPLACE INTO pos_work_status (user_id, colour, reason, set_at) VALUES (?,?,?,?)",
                             (user, "free", "job_done", now))
        self._push(row["customer_user"], f"#{row['order_no']} అయింది · done", "రేటింగ్ ఇవ్వండి · Please rate", "/me/hire",
                   f"wf:{order_id}:done")
        return self.order(user, order_id)

    def record_share(self, business_id: str, user: str, order_id: str, paise: int) -> Dict[str, Any]:
        """The authority records "#32: లక్ష్మికి ₹X ఇచ్చాను" -- a record only, no money moves through ASKODOX."""
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ? AND business_id = ?", (order_id, business_id)).fetchone()
            if row is None or not row["worker_user"]:
                raise PosError(404, "order", "Order not found.")
            conn.execute("UPDATE wf_orders SET share_paise = ?, share_ack = 0, updated_at = ? WHERE id = ?",
                         (max(0, int(paise)), self._now().isoformat(), order_id))
        self._push(row["worker_user"], f"#{row['order_no']} ₹{int(paise) // 100} ఇచ్చారు · paid you", "అందిందా? · Received?",
                   "/me/work", f"wf:{order_id}:share")
        return self.order(user, order_id)

    def ack_share(self, user: str, order_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            done = conn.execute("UPDATE wf_orders SET share_ack = 1, updated_at = ? WHERE id = ? AND worker_user = ? AND"
                                " share_paise > 0", (self._now().isoformat(), order_id, user)).rowcount
            if not done:
                raise PosError(404, "order", "Nothing to confirm.")
        return self.order(user, order_id)

    def complain(self, customer: str, order_id: str, text: str) -> Dict[str, Any]:
        text = _clean(text, 500)
        if not text:
            raise PosError(400, "text", "Say what went wrong.")
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ? AND customer_user = ?", (order_id, customer)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            cid = f"wfc_{uuid.uuid4().hex[:12]}"
            conn.execute("INSERT INTO wf_complaints (id, order_id, business_id, worker_user, customer_user, text, created_at)"
                         " VALUES (?,?,?,?,?,?,?)", (cid, order_id, row["business_id"], row["worker_user"], customer, text,
                                                     self._now().isoformat()))
            owner = None if row["independent"] else self.store._business_row(conn, row["business_id"])["owner_user_id"]
        target = owner or row["worker_user"]
        self._push(target, f"#{row['order_no']} ఫిర్యాదు · Complaint", text[:80], f"/pos/{row['business_id']}/team"
                   if owner else "/me/work", f"wf:{cid}:complaint")
        return {"id": cid, "order": f"#{row['order_no']}"}

    def answer_complaint(self, business_id: str, user: str, complaint_id: str, reply: str, close: bool) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "sell")
            row = conn.execute("SELECT * FROM wf_complaints WHERE id = ? AND business_id = ?", (complaint_id, business_id)).fetchone()
            if row is None:
                raise PosError(404, "complaint", "Not found.")
            conn.execute("UPDATE wf_complaints SET reply = ?, status = ?, closed_at = ? WHERE id = ?",
                         (_clean(reply, 500), "closed" if close else "open", self._now().isoformat() if close else None,
                          complaint_id))
        self._push(row["customer_user"], "ఫిర్యాదుకి జవాబు · Reply to your complaint", _clean(reply, 80), "/me/hire",
                   f"wf:{complaint_id}:reply")
        return {"status": "closed" if close else "open"}

    # ================================================================ step 6: ratings + badge
    def rate(self, customer: str, order_id: str, stars: int) -> Dict[str, Any]:
        if stars not in (1, 2, 3, 4, 5):
            raise PosError(400, "stars", "1 to 5 stars.")
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM wf_orders WHERE id = ? AND customer_user = ?", (order_id, customer)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if row["status"] != "done" or not row["paid"]:
                raise PosError(409, "not_done", "Rate after the work is done and paid.")
            month = self._now().astimezone(IST).strftime("%Y-%m")
            again = conn.execute("SELECT 1 FROM wf_ratings WHERE worker_user = ? AND customer_user = ? AND month = ? AND"
                                 " counts = 1", (row["worker_user"], customer, month)).fetchone()
            try:
                conn.execute("INSERT INTO wf_ratings (order_id, worker_user, customer_user, stars, month, counts, at) VALUES"
                             " (?,?,?,?,?,?,?)", (order_id, row["worker_user"], customer, stars, month, 0 if again else 1,
                                                  self._now().isoformat()))
            except sqlite3.IntegrityError:
                raise PosError(409, "rated", "Already rated.")
        return {"rated": True, "counted": not again}

    def _badge(self, conn: sqlite3.Connection, user: str) -> Dict[str, Any]:
        first = conn.execute("SELECT MIN(joined_at) AS d FROM wf_links WHERE user_id = ? AND joined_at IS NOT NULL",
                             (user,)).fetchone()["d"]
        days = (self._now() - datetime.fromisoformat(first)).days if first else 0
        stats = self._stats(conn, user)
        worker = conn.execute("SELECT udyam FROM wf_workers WHERE user_id = ?", (user,)).fetchone()
        need = {"days": int(_setting("workforce.badge_days")), "jobs": int(_setting("workforce.badge_jobs")),
                "rating": _setting("workforce.badge_min_rating")}
        rating = stats["rating"] or 0
        steps = {"days": days >= need["days"], "jobs": stats["jobs"] >= need["jobs"], "rating": rating >= need["rating"],
                 "complaints": stats["open_complaints"] == 0, "udyam": bool(worker and worker["udyam"])}
        has = all(steps.values())
        lost = bool(stats["rating"] is not None and rating < _setting("workforce.badge_lose_below")) or stats["open_complaints"] > 0
        return {"has": has and not lost, "steps": steps, "need": need, "days": days, **stats}

    def badge(self, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            return self._badge(conn, user)

    # ================================================================ step 5: monthly postings + site attendance
    def post(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        worker = str(data.get("worker") or "")
        site = _clean(data.get("site"), 80)
        month = str(data.get("month") or self._now().astimezone(IST).strftime("%Y-%m"))[:7]
        if not site or not re.match(r"^\d{4}-\d{2}$", month):
            raise PosError(400, "posting", "Site and month (YYYY-MM), please.")
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "members")
            if conn.execute("SELECT 1 FROM wf_links WHERE business_id = ? AND user_id = ? AND status = 'joined'",
                            (business_id, worker)).fetchone() is None:
                raise PosError(400, "worker", "Choose a worker of your team.")
            pid = f"wfp_{uuid.uuid4().hex[:12]}"
            conn.execute("INSERT INTO wf_postings (id, business_id, user_id, site, shift, month, lat, lon, created_at)"
                         " VALUES (?,?,?,?,?,?,?,?,?)",
                         (pid, business_id, worker, site, "night" if data.get("shift") == "night" else "day", month,
                          data.get("lat") if isinstance(data.get("lat"), (int, float)) else None,
                          data.get("lon") if isinstance(data.get("lon"), (int, float)) else None,
                          self._now().isoformat()))
        self._push(worker, f"{site} · {month}", "నెలవారీ పోస్టింగ్ · Monthly posting", "/me/work", f"wf:{pid}:posted")
        return {"id": pid, "site": site, "month": month}

    def mark_site(self, user: str, posting_id: str, method: str, lat: Optional[float], lon: Optional[float]) -> Dict[str, Any]:
        """Attendance at the posted site: the phone's live face check ('face_live'); far from the site = refused."""
        if method not in ("face_live", "kiosk_live"):
            raise PosError(400, "method", "Use the live face check.")
        with self.store._tx() as conn:
            p = conn.execute("SELECT * FROM wf_postings WHERE id = ? AND user_id = ? AND status = 'active'",
                             (posting_id, user)).fetchone()
            if p is None:
                raise PosError(404, "posting", "Posting not found.")
            dist = _km((p["lat"], p["lon"]), (lat, lon))
            if dist is not None and dist > 0.5:
                raise PosError(409, "far", f"You are {dist:.1f} km from {p['site']}.")
            day = self._now().astimezone(IST).date().isoformat()
            conn.execute("INSERT OR IGNORE INTO wf_post_attendance (posting_id, day, at, method, lat, lon) VALUES (?,?,?,?,?,?)",
                         (posting_id, day, self._now().isoformat(), method, lat, lon))
        return {"day": day, "site": p["site"]}

    def postings(self, business_id: str, user: str, month: str = "") -> Dict[str, Any]:
        with self.store._connect() as conn:
            self.store._require(conn, business_id, user, "view")
            month = month or self._now().astimezone(IST).strftime("%Y-%m")
            out = []
            for p in conn.execute("SELECT p.*, w.name FROM wf_postings p LEFT JOIN wf_workers w ON w.user_id = p.user_id"
                                  " WHERE p.business_id = ? AND p.month = ?", (business_id, month)):
                days = [a["day"] for a in conn.execute("SELECT day FROM wf_post_attendance WHERE posting_id = ? ORDER BY day",
                                                        (p["id"],))]
                out.append({"id": p["id"], "worker": p["user_id"], "name": p["name"], "site": p["site"],
                            "shift": p["shift"], "month": p["month"], "days_present": days})
        return {"month": month, "postings": out}


class _ColourOnly:
    """Lets the colour rules of PosDeliveryJobs run on an open connection without its constructor."""

    def __init__(self, clock: Callable[[], datetime]) -> None:
        self.clock = clock

    def _now(self) -> datetime:
        return self.clock()
