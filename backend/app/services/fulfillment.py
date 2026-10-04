"""Who moves an order, and where that movement is -- kept SEPARATE from the
order's commerce state (deal_lifecycle). A seller accepting an order never
means a driver accepted the delivery.

Responsibility (one per order): SELLER_DELIVERY, CUSTOMER_PICKUP,
ASKODOX_NETWORK_DRIVER, THIRD_PARTY_PROVIDER, CUSTOMER_ARRANGED_DRIVER,
SELLER_ARRANGED_DRIVER, COURIER_PARCEL_PROVIDER, NOT_REQUIRED, TO_BE_DECIDED.

Delivery state is DERIVED, never stored twice: from the linked delivery job
(ASKODOX network driver) or, for movements someone else handles, from the
seller's own dispatch / delivered steps.
"""
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Dict, Optional

MODES = ("SELLER_DELIVERY", "CUSTOMER_PICKUP", "ASKODOX_NETWORK_DRIVER", "THIRD_PARTY_PROVIDER",
         "CUSTOMER_ARRANGED_DRIVER", "SELLER_ARRANGED_DRIVER", "COURIER_PARCEL_PROVIDER", "NOT_REQUIRED",
         "TO_BE_DECIDED")
DELIVERY_STATES = ("NOT_REQUIRED", "TO_BE_DECIDED", "NOT_STARTED", "NEEDS_DRIVER", "SEARCHING", "OFFERED",
                   "DRIVER_ACCEPTED", "EN_ROUTE_PICKUP", "ARRIVED_PICKUP", "PICKED_UP", "IN_TRANSIT", "ARRIVED_DROP",
                   "DELIVERED", "CANCELLED", "FAILED")

# delivery_jobs status -> delivery state
_JOB_STATE = {
    "REQUESTED": "SEARCHING", "NEEDS_CONFIGURATION": "NEEDS_DRIVER", "NEEDS_PARTNER": "NEEDS_DRIVER",
    "PARTNER_SEARCH": "OFFERED", "PARTNER_ACCEPTED": "DRIVER_ACCEPTED", "EN_ROUTE_PICKUP": "EN_ROUTE_PICKUP",
    "ARRIVED_PICKUP": "ARRIVED_PICKUP", "PICKED_UP": "PICKED_UP", "IN_TRANSIT": "IN_TRANSIT",
    "ARRIVED_DROP": "ARRIVED_DROP", "DELIVERED": "DELIVERED", "CONFIRMED": "DELIVERED", "CANCELLED": "CANCELLED",
}
_ORDER_DONE = {"DELIVERED", "FULFILLED", "SERVICE_COMPLETED", "CLOSED", "RESOLVED"}
_ORDER_STOPPED = {"CANCELLED", "REJECTED"}


def delivery_state(mode: str, order_status: str, job: Optional[Dict[str, Any]] = None) -> str:
    status = str(order_status or "").upper()
    if mode in ("NOT_REQUIRED", "CUSTOMER_PICKUP"):
        return "NOT_REQUIRED"
    if mode == "TO_BE_DECIDED":
        return "TO_BE_DECIDED"
    if status in _ORDER_STOPPED:
        return "CANCELLED"
    if mode == "ASKODOX_NETWORK_DRIVER":
        if job:
            return _JOB_STATE.get(job.get("status") or "", "NEEDS_DRIVER")
        return "NEEDS_DRIVER"
    # Someone else moves it (seller / courier / their own driver): only the
    # seller's own steps tell us where it is.
    if status in _ORDER_DONE:
        return "DELIVERED"
    if status == "DISPATCHED":
        return "IN_TRANSIT"
    return "NOT_STARTED"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class FulfillmentStore:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS order_fulfillment (
                    order_id INTEGER PRIMARY KEY, mode TEXT NOT NULL, delivery_job_id TEXT,
                    provider_name TEXT, tracking_ref TEXT, set_by TEXT NOT NULL, updated_at TEXT NOT NULL)""")

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def get(self, order_id: int) -> Dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM order_fulfillment WHERE order_id=?", (int(order_id),)).fetchone()
        return dict(row) if row else {"order_id": int(order_id), "mode": "TO_BE_DECIDED", "delivery_job_id": None,
                                      "provider_name": None, "tracking_ref": None}

    def set(self, order_id: int, *, mode: str, by: str, delivery_job_id: str | None = None,
            provider_name: str = "", tracking_ref: str = "") -> Dict[str, Any]:
        if mode not in MODES:
            raise ValueError("unknown fulfillment mode")
        current = self.get(order_id)
        job_id = delivery_job_id if delivery_job_id is not None else (
            current.get("delivery_job_id") if current.get("mode") == mode else None)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO order_fulfillment(order_id,mode,delivery_job_id,provider_name,tracking_ref,set_by,"
                "updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(order_id) DO UPDATE SET mode=excluded.mode, "
                "delivery_job_id=excluded.delivery_job_id, provider_name=excluded.provider_name, "
                "tracking_ref=excluded.tracking_ref, set_by=excluded.set_by, updated_at=excluded.updated_at",
                (int(order_id), mode, job_id, provider_name[:80] or None, tracking_ref[:80] or None, by, _now()))
        return self.get(order_id)
