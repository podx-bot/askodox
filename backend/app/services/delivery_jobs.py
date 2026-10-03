"""Delivery jobs: one reusable lifecycle for parcel, food, grocery, product and
pickup/drop deliveries.

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

KINDS = ("parcel", "food", "grocery", "product", "pickup_drop", "documents", "other")
SERVICE_FOR_KIND = {"pickup_drop": "pickup_drop", "documents": "documents"}

REQUESTED, NEEDS_CONFIGURATION, NEEDS_PARTNER = "REQUESTED", "NEEDS_CONFIGURATION", "NEEDS_PARTNER"
PARTNER_SEARCH, PARTNER_ACCEPTED, PICKED_UP = "PARTNER_SEARCH", "PARTNER_ACCEPTED", "PICKED_UP"
IN_TRANSIT, DELIVERED, CONFIRMED, CANCELLED = "IN_TRANSIT", "DELIVERED", "CONFIRMED", "CANCELLED"

# Who may move a job from which state to which.
PARTNER_STEPS = {PARTNER_ACCEPTED: PICKED_UP, PICKED_UP: IN_TRANSIT, IN_TRANSIT: DELIVERED}
CANCELLABLE = {REQUESTED, NEEDS_CONFIGURATION, NEEDS_PARTNER, PARTNER_SEARCH, PARTNER_ACCEPTED}


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
        for key in ("pickup_json", "drop_json", "offered_json", "history_json"):
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
               integration_ready: Callable[[str], bool], order_id: str = "") -> Dict[str, Any]:
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
        return self._save(job, PARTNER_ACCEPTED, partner_user, partner_id=partner_id, partner_user=partner_user)

    def advance(self, job_id: str, *, partner_user: str, to: str) -> Dict[str, Any]:
        job = self._require(job_id)
        if job.get("partner_user") != partner_user:
            raise DeliveryError("not_assigned", "Only the assigned partner can update this delivery")
        if PARTNER_STEPS.get(job["status"]) != to:
            raise DeliveryError("bad_step", f"Cannot go from {job['status']} to {to}")
        return self._save(job, to, partner_user)

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
