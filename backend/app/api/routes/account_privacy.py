"""Customer privacy actions that really work (no mock workflows).

* GET  /api/me/export  -- everything ASKODOX stores against the signed-in
  user's id, as JSON (listings, requests/orders, requirements, referrals,
  rewards, subscriptions...). Found generically across the database by the
  user-id columns, so new features are included automatically.
* DELETE /api/me       -- delete the account (explicit confirmation):
  listings are taken down, open requirements closed, and every session
  issued before now stops working. Orders already made with another person
  stay on record for them (and for fraud/dispute duties) -- stated plainly
  in the app before the user confirms.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import closing

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user

router = APIRouter(prefix="/api/me", tags=["privacy"])

_USER_COLUMNS = ("user_id", "app_user_id", "seller_user_id", "buyer_user_id", "owner_user_id",
                 "provider_user_id", "referrer_user_id", "referred_user_id", "participant_user_id",
                 "requester_user_id", "responder_user_id")
# Internal/staff tables are not the customer's data export.
_SKIP_TABLES = {"flow_traces", "admin_audit_log", "admin_staff", "admin_notifications", "feature_flags",
                "integration_checks", "growth_api_usage", "account_deletions"}
_SECRET_COLUMNS = {"token", "password", "otp", "otp_hash", "secret", "photo_jpeg", "jpeg"}


def _db(request: Request) -> str:
    return request.app.state.container.settings.database_path


def _ensure(conn) -> None:
    conn.execute("CREATE TABLE IF NOT EXISTS account_deletions (user_id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL)")


def deleted_before(database_path: str, user_id: str, issued_at: int) -> bool:
    with closing(sqlite3.connect(database_path)) as conn:
        _ensure(conn)
        row = conn.execute("SELECT deleted_at FROM account_deletions WHERE user_id=?", (user_id,)).fetchone()
    return bool(row) and issued_at <= int(row[0])


def _user_tables(conn) -> list[tuple[str, list[str]]]:
    found = []
    for (table,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
        if table in _SKIP_TABLES or table.startswith("sqlite_"):
            continue
        columns = [row[1] for row in conn.execute(f'PRAGMA table_info("{table}")').fetchall()]
        user_cols = [c for c in columns if c in _USER_COLUMNS]
        if user_cols:
            found.append((table, user_cols))
    return found


class PushTokenRequest(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: str = "android"


@router.post("/push-token")
def register_push_token(payload: PushTokenRequest, request: Request) -> dict:
    """This phone's FCM token, so request updates reach it in the
    background (only sent when push is configured on the server)."""
    from app.services.push_service import push_service

    user_id = _authenticated_app_user(request)
    service = push_service(request.app.state.container)
    service.register(user_id, payload.token.strip(), payload.platform)
    return {"registered": True, "push_configured": service.configured}


@router.delete("/push-token")
def remove_push_tokens(request: Request) -> dict:
    from app.services.push_service import push_service

    push_service(request.app.state.container).unregister(_authenticated_app_user(request))
    return {"removed": True}


@router.get("/export")
def export_my_data(request: Request) -> dict:
    user_id = _authenticated_app_user(request)
    data: dict[str, list[dict]] = {}
    with closing(sqlite3.connect(_db(request))) as conn:
        conn.row_factory = sqlite3.Row
        for table, cols in _user_tables(conn):
            where = " OR ".join(f'"{c}"=?' for c in cols)
            rows = conn.execute(f'SELECT * FROM "{table}" WHERE {where} LIMIT 500', [user_id] * len(cols)).fetchall()
            if rows:
                data[table] = [{k: row[k] for k in row.keys() if k.lower() not in _SECRET_COLUMNS} for row in rows]
    return {"user_id": user_id, "exported_at": int(time.time()), "data": data}


@router.delete("")
def delete_my_account(request: Request, confirm: str = "") -> dict:
    """DELETE /api/me?confirm=DELETE (the typed confirmation from the app)."""
    user_id = _authenticated_app_user(request)
    if confirm.strip().upper() != "DELETE":
        raise HTTPException(status_code=422, detail="Type DELETE to confirm account deletion")
    now = int(time.time())
    done: dict[str, int] = {}
    with closing(sqlite3.connect(_db(request))) as conn:
        _ensure(conn)
        tables = {t for t, _ in _user_tables(conn)}
        if "seller_products" in tables:
            done["listings_removed"] = conn.execute(
                "UPDATE seller_products SET active=0 WHERE seller_user_id=? AND active=1", (user_id,)).rowcount
        if "universal_need_offer_records" in tables:
            done["requirements_closed"] = conn.execute(
                "UPDATE universal_need_offer_records SET status='CLOSED' WHERE user_id=? AND status='ACTIVE'",
                (user_id,)).rowcount
        if "user_profiles" in tables:
            conn.execute("DELETE FROM user_profiles WHERE user_id=?", (user_id,))  # name, photo, addresses
        if "catalog_item_photos" in tables:
            conn.execute("DELETE FROM catalog_item_photos WHERE seller_user_id=?", (user_id,))
        if "push_tokens" in tables:
            conn.execute("DELETE FROM push_tokens WHERE user_id=?", (user_id,))  # no more notifications
        conn.execute("INSERT OR REPLACE INTO account_deletions(user_id, deleted_at) VALUES(?,?)", (user_id, now))
        conn.commit()
    return {"deleted": True, **done,
            "kept": "Orders already made with another person stay on record for them."}
