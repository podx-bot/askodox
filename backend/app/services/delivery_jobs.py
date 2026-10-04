"""Mobility + delivery jobs: ONE reusable lifecycle for rides (taxi, auto,
bike taxi, outstation, airport, driver-only), parcel / documents / local
delivery and seller-order deliveries, plus carpool seat requests.

request (Party A) -> PARTNER_SEARCH (offered to matching approved partners,
Party B) -> PARTNER_ACCEPTED -> PICKED_UP -> IN_TRANSIT -> DELIVERED (partner)
-> CONFIRMED (customer). CANCELLED is allowed before pickup.

No partner is ever invented: with no approved partner and no configured
logistics integration the job is NEEDS_PARTNER (or NEEDS_CONFIGURATION when
matching is switched off) and says so. Contact details are not part of a job;
the existing consent rule for order contacts still applies.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional

from app.services.owner_os import _km, match_delivery

RIDE_KINDS = ("ride_taxi", "ride_auto", "ride_bike", "ride_outstation", "ride_airport", "driver_only")
KINDS = ("parcel", "food", "grocery", "product", "pickup_drop", "documents", "local_delivery", "other") + RIDE_KINDS
SERVICE_FOR_KIND = {"pickup_drop": "pickup_drop", "documents": "documents", "local_delivery": "product"}

REQUESTED, NEEDS_CONFIGURATION, NEEDS_PARTNER = "REQUESTED", "NEEDS_CONFIGURATION", "NEEDS_PARTNER"
PARTNER_SEARCH, PARTNER_ACCEPTED, PICKED_UP = "PARTNER_SEARCH", "PARTNER_ACCEPTED", "PICKED_UP"
IN_TRANSIT, DELIVERED, CONFIRMED, CANCELLED = "IN_TRANSIT", "DELIVERED", "CONFIRMED", "CANCELLED"

EN_ROUTE_PICKUP, ARRIVED_PICKUP, ARRIVED_DROP = "EN_ROUTE_PICKUP", "ARRIVED_PICKUP", "ARRIVED_DROP"
# The partner moves FORWARD along this path; the optional steps may be skipped
# (a parcel rider rarely reports "arrived"), the others never.
TRIP_PATH = (PARTNER_ACCEPTED, EN_ROUTE_PICKUP, ARRIVED_PICKUP, PICKED_UP, IN_TRANSIT, ARRIVED_DROP, DELIVERED)
OPTIONAL_STEPS = {EN_ROUTE_PICKUP, ARRIVED_PICKUP, ARRIVED_DROP}
PARTNER_STEPS = {PARTNER_ACCEPTED: PICKED_UP, PICKED_UP: IN_TRANSIT, IN_TRANSIT: DELIVERED}  # legacy shape
CANCELLABLE = {REQUESTED, NEEDS_CONFIGURATION, NEEDS_PARTNER, PARTNER_SEARCH, PARTNER_ACCEPTED, EN_ROUTE_PICKUP,
               ARRIVED_PICKUP}
ACCEPTED_STATES = set(TRIP_PATH) | {CONFIRMED}
# Contact / sensitive trip details are released to the assigned partner only
# after acceptance (Round-8 consent rule), and never to other partners.
PRIVATE_DETAIL_KEYS = ("contact_phone", "recipient_name", "recipient_phone", "notes_private")


def allowed_step(current: str, to: str) -> bool:
    if current not in TRIP_PATH or to not in TRIP_PATH:
        return False
    i, j = TRIP_PATH.index(current), TRIP_PATH.index(to)
    return j > i and all(step in OPTIONAL_STEPS for step in TRIP_PATH[i + 1:j])


def fare_quote(rule: Optional[Dict[str, Any]], distance_km: float) -> Optional[Dict[str, Any]]:
    """A quote ONLY from a configured fare rule (Command Center); never guessed."""
    if not rule:
        return None
    try:
        base, per_km = float(rule.get("base_fare") or 0), float(rule.get("per_km") or 0)
        minimum = float(rule.get("minimum_fare") or 0)
    except (TypeError, ValueError):
        return None
    if base <= 0 and per_km <= 0:
        return None
    amount = max(minimum, base + per_km * float(distance_km or 0))
    return {"amount": round(amount), "currency": "INR", "basis": "configured_rate",
            "note": "Estimate from the configured rate; the partner confirms the final fare."}


class DeliveryError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class DeliveryJobs:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS delivery_jobs (
                    id TEXT PRIMARY KEY, requester TEXT NOT NULL, order_id TEXT, kind TEXT NOT NULL,
                    pickup_json TEXT NOT NULL, drop_json TEXT NOT NULL, distance_km REAL,
                    status TEXT NOT NULL, partner_id TEXT, partner_user TEXT, offered_json TEXT NOT NULL,
                    history_json TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
            cols = {r[1] for r in conn.execute("PRAGMA table_info(delivery_jobs)").fetchall()}
            for col, ddl in (("details_json", "TEXT NOT NULL DEFAULT '{}'"), ("declined_json", "TEXT NOT NULL DEFAULT '[]'"),
                             ("schedule_at", "TEXT"), ("quote_json", "TEXT"), ("accepted_at", "TEXT")):
                if col not in cols:
                    conn.execute(f"ALTER TABLE delivery_jobs ADD COLUMN {col} {ddl}")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS carpool_rides (
                    id TEXT PRIMARY KEY, host TEXT NOT NULL, origin_json TEXT NOT NULL, dest_json TEXT NOT NULL,
                    depart_at TEXT NOT NULL, seats INTEGER NOT NULL, seats_left INTEGER NOT NULL,
                    contribution REAL, preferences TEXT, contact_phone TEXT, status TEXT NOT NULL,
                    created_at TEXT NOT NULL)""")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS carpool_requests (
                    id TEXT PRIMARY KEY, ride_id TEXT NOT NULL, passenger TEXT NOT NULL, seats INTEGER NOT NULL,
                    contact_phone TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS mobility_reports (
                    id TEXT PRIMARY KEY, subject_type TEXT NOT NULL, subject_id TEXT NOT NULL, reporter TEXT NOT NULL,
                    reason TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL)""")

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    @staticmethod
    def _row(row: sqlite3.Row) -> Dict[str, Any]:
        data = dict(row)
        for key in ("pickup_json", "drop_json", "offered_json", "history_json", "details_json", "declined_json",
                    "quote_json"):
            if key in data:
                data[key[:-5]] = json.loads(data.pop(key) or "null")
        return data

    def get(self, job_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM delivery_jobs WHERE id=?", (job_id,)).fetchone()
        return self._row(row) if row else None

    def _save(self, job: Dict[str, Any], status: str, actor: str, note: str = "", **fields: Any) -> Dict[str, Any]:
        history = list(job.get("history") or []) + [{"status": status, "by": actor, "at": _now(), "note": note}]
        sets = {"status": status, "history_json": json.dumps(history), "updated_at": _now(), **fields}
        with self._connect() as conn:
            conn.execute(f"UPDATE delivery_jobs SET {', '.join(f'{k}=?' for k in sets)} WHERE id=?",
                         (*sets.values(), job["id"]))
        return self.get(job["id"]) or {}

    def create(self, *, requester: str, kind: str, pickup: Dict[str, Any], drop: Dict[str, Any],
               partners: Iterable[Dict[str, Any]], matching_enabled: bool,
               integration_ready: Callable[[str], bool], order_id: str = "", details: Dict[str, Any] | None = None,
               schedule_at: str = "", fare_rule: Dict[str, Any] | None = None) -> Dict[str, Any]:
        if kind not in KINDS:
            raise DeliveryError("bad_kind", "Unknown delivery type")
        for point in (pickup, drop):
            if point.get("latitude") is None or point.get("longitude") is None:
                raise DeliveryError("needs_location", "Pickup and drop need a location")
        distance = round(_km(float(pickup["latitude"]), float(pickup["longitude"]),
                             float(drop["latitude"]), float(drop["longitude"])), 2)
        job_id = "dj_" + uuid.uuid4().hex[:16]
        now = _now()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO delivery_jobs(id,requester,order_id,kind,pickup_json,drop_json,distance_km,status,"
                "offered_json,history_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (job_id, requester, order_id or None, kind, json.dumps(pickup), json.dumps(drop), distance,
                 REQUESTED, "[]", json.dumps([{"status": REQUESTED, "by": requester, "at": now, "note": ""}]),
                 now, now))
            quote = fare_quote(fare_rule, distance)
            conn.execute("UPDATE delivery_jobs SET details_json=?, schedule_at=?, quote_json=? WHERE id=?",
                         (json.dumps(details or {}), schedule_at or None, json.dumps(quote) if quote else None,
                          job_id))
        job = self.get(job_id) or {}
        if not matching_enabled:
            return self._save(job, NEEDS_CONFIGURATION, "system", "Delivery matching is switched off.")
        match = match_delivery(partners, service=SERVICE_FOR_KIND.get(kind, kind),
                               latitude=float(pickup["latitude"]), longitude=float(pickup["longitude"]),
                               integration_ready=integration_ready)
        offered = [{"partner_id": c["id"], "name": c["name"], "distance_km": c["distance_km"], "kind": "independent"}
                   for c in match["independent"]]
        offered += [{"partner_id": c["id"], "name": c["name"], "kind": "external"} for c in match["external"]]
        if not offered:
            return self._save(job, NEEDS_PARTNER, "system", "No approved, available partner serves this area yet.",
                              offered_json=json.dumps([]))
        return self._save(job, PARTNER_SEARCH, "system", f"Offered to {len(offered)} partner(s).",
                          offered_json=json.dumps(offered))

    def offers_for(self, partner_ids: Iterable[str]) -> List[Dict[str, Any]]:
        ids = set(partner_ids)
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM delivery_jobs WHERE status=?", (PARTNER_SEARCH,)).fetchall()
        return [j for j in map(self._row, rows) if ids & {o["partner_id"] for o in j["offered"] or []}]

    def accept(self, job_id: str, *, partner_id: str, partner_user: str) -> Dict[str, Any]:
        job = self._require(job_id)
        if job["status"] != PARTNER_SEARCH:
            raise DeliveryError("not_open", "This delivery is no longer open")
        if partner_id not in {o["partner_id"] for o in job["offered"] or []}:
            raise DeliveryError("not_offered", "This delivery was not offered to you")
        if partner_id in set(job.get("declined") or []):
            raise DeliveryError("declined", "You declined this request")
        return self._save(job, PARTNER_ACCEPTED, partner_user, partner_id=partner_id, partner_user=partner_user,
                          accepted_at=_now())

    def decline(self, job_id: str, *, partner_id: str, partner_user: str, reason: str = "") -> Dict[str, Any]:
        """A partner says no. When every offered partner declined, the
        request honestly becomes NEEDS_PARTNER ("no driver found")."""
        job = self._require(job_id)
        if job["status"] != PARTNER_SEARCH:
            raise DeliveryError("not_open", "This request is no longer open")
        offered = {o["partner_id"] for o in job.get("offered") or []}
        if partner_id not in offered:
            raise DeliveryError("not_offered", "This request was not offered to you")
        declined = sorted(set(job.get("declined") or []) | {partner_id})
        if offered <= set(declined):
            return self._save(job, NEEDS_PARTNER, "system", "Every offered partner declined -- no driver found.",
                              declined_json=json.dumps(declined))
        with self._connect() as conn:
            conn.execute("UPDATE delivery_jobs SET declined_json=?, updated_at=? WHERE id=?",
                         (json.dumps(declined), _now(), job_id))
        return self.get(job_id) or {}

    def advance(self, job_id: str, *, partner_user: str, to: str) -> Dict[str, Any]:
        job = self._require(job_id)
        if job.get("partner_user") != partner_user:
            raise DeliveryError("not_assigned", "Only the assigned partner can update this delivery")
        if not allowed_step(job["status"], to):
            raise DeliveryError("bad_step", f"Cannot go from {job['status']} to {to}")
        return self._save(job, to, partner_user)

    def release(self, job_id: str, *, partner_user: str, reason: str = "") -> Dict[str, Any]:
        """The assigned partner backs out before pickup: the request goes back
        to the other offered partners (never silently lost)."""
        job = self._require(job_id)
        if job.get("partner_user") != partner_user:
            raise DeliveryError("not_assigned", "Only the assigned partner can release this request")
        if job["status"] not in (PARTNER_ACCEPTED, EN_ROUTE_PICKUP, ARRIVED_PICKUP):
            raise DeliveryError("bad_step", "Cannot release after pickup")
        declined = sorted(set(job.get("declined") or []) | {job.get("partner_id") or ""})
        remaining = [o for o in job.get("offered") or [] if o["partner_id"] not in declined]
        status = PARTNER_SEARCH if remaining else NEEDS_PARTNER
        return self._save(job, status, "partner", f"Partner released: {reason[:120]}", partner_id=None,
                          partner_user=None, declined_json=json.dumps(declined))

    def for_requester(self, requester: str, limit: int = 50) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM delivery_jobs WHERE requester=? ORDER BY created_at DESC LIMIT ?",
                                (requester, limit)).fetchall()
        return [self._row(r) for r in rows]

    def for_partner(self, partner_user: str, limit: int = 50) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM delivery_jobs WHERE partner_user=? ORDER BY updated_at DESC LIMIT ?",
                                (partner_user, limit)).fetchall()
        return [self._row(r) for r in rows]

    def all_jobs(self, limit: int = 500) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM delivery_jobs ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [self._row(r) for r in rows]

    # ------------------------------------------------------------ carpool --
    def carpool_offer(self, *, host: str, origin: Dict[str, Any], dest: Dict[str, Any], depart_at: str,
                      seats: int, contribution: float | None, preferences: str = "",
                      contact_phone: str = "") -> Dict[str, Any]:
        if seats < 1 or seats > 8:
            raise DeliveryError("bad_seats", "Seats must be between 1 and 8")
        for point in (origin, dest):
            if point.get("latitude") is None or point.get("longitude") is None:
                raise DeliveryError("needs_location", "Origin and destination need a location")
        ride_id = "cp_" + uuid.uuid4().hex[:14]
        with self._connect() as conn:
            conn.execute("INSERT INTO carpool_rides VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                         (ride_id, host, json.dumps(origin), json.dumps(dest), depart_at, seats, seats, contribution,
                          preferences[:300], contact_phone[:20], "OPEN", _now()))
        return self.carpool_get(ride_id) or {}

    def carpool_get(self, ride_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM carpool_rides WHERE id=?", (ride_id,)).fetchone()
        if not row:
            return None
        ride = dict(row)
        ride["origin"], ride["dest"] = json.loads(ride.pop("origin_json")), json.loads(ride.pop("dest_json"))
        return ride

    def carpool_search(self, *, origin: Dict[str, Any], dest: Dict[str, Any], date: str = "",
                       within_km: float = 5.0) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT id FROM carpool_rides WHERE status='OPEN' AND seats_left>0 "
                                "ORDER BY depart_at").fetchall()
        out = []
        for (ride_id,) in rows:
            ride = self.carpool_get(ride_id) or {}
            if date and not str(ride.get("depart_at") or "").startswith(date):
                continue
            d1 = _km(float(origin["latitude"]), float(origin["longitude"]),
                     float(ride["origin"]["latitude"]), float(ride["origin"]["longitude"]))
            d2 = _km(float(dest["latitude"]), float(dest["longitude"]),
                     float(ride["dest"]["latitude"]), float(ride["dest"]["longitude"]))
            if d1 <= within_km and d2 <= within_km:
                out.append({**ride, "origin_km": round(d1, 2), "dest_km": round(d2, 2)})
        return sorted(out, key=lambda r: r["origin_km"] + r["dest_km"])

    def carpool_request(self, ride_id: str, *, passenger: str, seats: int = 1,
                        contact_phone: str = "") -> Dict[str, Any]:
        ride = self.carpool_get(ride_id)
        if not ride or ride["status"] != "OPEN":
            raise DeliveryError("not_open", "This ride is not open")
        if ride["host"] == passenger:
            raise DeliveryError("own_ride", "You cannot book your own ride")
        if seats < 1 or seats > ride["seats_left"]:
            raise DeliveryError("bad_seats", "Not enough seats left")
        req_id = "cpr_" + uuid.uuid4().hex[:14]
        now = _now()
        with self._connect() as conn:
            conn.execute("INSERT INTO carpool_requests VALUES(?,?,?,?,?,?,?,?)",
                         (req_id, ride_id, passenger, seats, contact_phone[:20], "REQUESTED", now, now))
        return self.carpool_request_get(req_id) or {}

    def carpool_request_get(self, req_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM carpool_requests WHERE id=?", (req_id,)).fetchone()
        return dict(row) if row else None

    def carpool_requests_for(self, ride_id: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM carpool_requests WHERE ride_id=? ORDER BY created_at",
                                                  (ride_id,)).fetchall()]

    def carpool_decide(self, req_id: str, *, host: str, accept: bool) -> Dict[str, Any]:
        req = self.carpool_request_get(req_id)
        if not req:
            raise DeliveryError("not_found", "Request not found")
        ride = self.carpool_get(req["ride_id"]) or {}
        if ride.get("host") != host:
            raise DeliveryError("not_host", "Only the ride host can decide")
        if req["status"] != "REQUESTED":
            raise DeliveryError("bad_step", "Already decided")
        status = "ACCEPTED" if accept else "DECLINED"
        with self._connect() as conn:
            if accept:
                left = int(ride["seats_left"]) - int(req["seats"])
                if left < 0:
                    raise DeliveryError("bad_seats", "Not enough seats left")
                conn.execute("UPDATE carpool_rides SET seats_left=?, status=? WHERE id=?",
                             (left, "FULL" if left == 0 else "OPEN", ride["id"]))
            conn.execute("UPDATE carpool_requests SET status=?, updated_at=? WHERE id=?", (status, _now(), req_id))
        return self.carpool_request_get(req_id) or {}

    def carpool_for_host(self, host: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            ids = [r[0] for r in conn.execute("SELECT id FROM carpool_rides WHERE host=? ORDER BY depart_at DESC",
                                              (host,)).fetchall()]
        return [self.carpool_get(i) or {} for i in ids]

    def carpool_requests_by(self, passenger: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM carpool_requests WHERE passenger=? ORDER BY created_at DESC", (passenger,)).fetchall()]

    def carpool_close(self, ride_id: str, *, host: str) -> Dict[str, Any]:
        ride = self.carpool_get(ride_id)
        if not ride or ride["host"] != host:
            raise DeliveryError("not_host", "Only the ride host can close it")
        with self._connect() as conn:
            conn.execute("UPDATE carpool_rides SET status='CLOSED' WHERE id=?", (ride_id,))
        return self.carpool_get(ride_id) or {}

    def set_carpool_status(self, ride_id: str, status: str) -> None:
        """Moderation (staff): HIDDEN rides leave search; OPEN restores."""
        with self._connect() as conn:
            conn.execute("UPDATE carpool_rides SET status=? WHERE id=?", (status, ride_id))

    def set_report_status(self, report_id: str, status: str) -> Dict[str, Any]:
        with self._connect() as conn:
            conn.execute("UPDATE mobility_reports SET status=? WHERE id=?", (status, report_id))
            row = conn.execute("SELECT id,subject_type,subject_id,reason,status,created_at FROM mobility_reports "
                               "WHERE id=?", (report_id,)).fetchone()
        if not row:
            raise DeliveryError("not_found", "Report not found")
        return dict(row)

    def report(self, *, subject_type: str, subject_id: str, reporter: str, reason: str) -> Dict[str, Any]:
        rid = "mr_" + uuid.uuid4().hex[:12]
        with self._connect() as conn:
            conn.execute("INSERT INTO mobility_reports VALUES(?,?,?,?,?,?,?)",
                         (rid, subject_type[:20], subject_id[:40], reporter, reason[:500], "OPEN", _now()))
        return {"id": rid, "status": "OPEN"}

    def reports(self, limit: int = 100) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT id,subject_type,subject_id,reason,status,created_at FROM mobility_reports "
                "ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()]

    def analytics(self) -> Dict[str, Any]:
        """Privacy-safe counts: no names, no phones, areas rounded to ~10 km."""
        jobs = self.all_jobs(limit=5000)
        by_status: Dict[str, int] = {}
        by_kind: Dict[str, int] = {}
        unmet: Dict[str, int] = {}
        match_secs: List[float] = []
        for j in jobs:
            by_status[j["status"]] = by_status.get(j["status"], 0) + 1
            by_kind[j["kind"]] = by_kind.get(j["kind"], 0) + 1
            if j["status"] == NEEDS_PARTNER:
                p = j.get("pickup") or {}
                area = f"{round(float(p.get('latitude') or 0), 1)},{round(float(p.get('longitude') or 0), 1)}"
                unmet[area] = unmet.get(area, 0) + 1
            if j.get("accepted_at"):
                try:
                    start = datetime.fromisoformat(j["created_at"])
                    match_secs.append((datetime.fromisoformat(j["accepted_at"]) - start).total_seconds())
                except ValueError:
                    pass
        total = len(jobs)
        accepted = sum(v for k, v in by_status.items() if k in ACCEPTED_STATES)
        with self._connect() as conn:
            carpool = {r[0]: r[1] for r in conn.execute(
                "SELECT status, COUNT(*) FROM carpool_requests GROUP BY status").fetchall()}
        return {"requests": total, "by_status": by_status, "by_kind": by_kind,
                "acceptance_rate": round(accepted / total, 3) if total else None,
                "no_provider_found": by_status.get(NEEDS_PARTNER, 0), "cancelled": by_status.get(CANCELLED, 0),
                "completed": by_status.get(DELIVERED, 0) + by_status.get(CONFIRMED, 0),
                "avg_match_seconds": round(sum(match_secs) / len(match_secs)) if match_secs else None,
                "unmet_by_area": dict(sorted(unmet.items(), key=lambda kv: -kv[1])[:20]),
                "carpool_requests": carpool}

    def confirm(self, job_id: str, *, requester: str) -> Dict[str, Any]:
        job = self._require(job_id)
        if job["requester"] != requester:
            raise DeliveryError("not_requester", "Only the customer can confirm the delivery")
        if job["status"] != DELIVERED:
            raise DeliveryError("bad_step", "Delivery is not marked delivered yet")
        return self._save(job, CONFIRMED, requester)

    def cancel(self, job_id: str, *, requester: str, reason: str = "") -> Dict[str, Any]:
        job = self._require(job_id)
        if job["requester"] != requester:
            raise DeliveryError("not_requester", "Only the customer can cancel")
        if job["status"] not in CANCELLABLE:
            raise DeliveryError("bad_step", "Cannot cancel after pickup")
        return self._save(job, CANCELLED, requester, reason[:200])

    def _require(self, job_id: str) -> Dict[str, Any]:
        job = self.get(job_id)
        if job is None:
            raise DeliveryError("not_found", "Delivery not found")
        return job
