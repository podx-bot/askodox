"""Background push notifications (Firebase Cloud Messaging HTTP v1).

Status: server side is complete; it sends ONLY when configured.
* ``FIREBASE_SERVICE_ACCOUNT_JSON`` (Railway variable) -- the Firebase
  service-account key JSON (project_id, client_email, private_key). Absent
  -> ``configured`` is False and nothing is sent (the app keeps its
  in-app / while-open silent notifications). Never faked as delivered.
* Devices register their FCM token via ``POST /api/me/push-token``.
* Every event is sent at most once per user (``push_sent`` keyed by the
  event), on the silent ``askodox_updates`` Android channel, with the
  in-app route to open when tapped.
"""
from __future__ import annotations

import base64
import json
import os
import sqlite3
import threading
import time
from contextlib import closing
from typing import Any

import httpx

TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class PushService:
    def __init__(self, database_path: str, *, service_account_json: str | None = None, client=None) -> None:
        self.database_path = database_path
        raw = service_account_json if service_account_json is not None else os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "")
        try:
            self._account = json.loads(raw) if raw.strip() else None
        except ValueError:
            self._account = None
        self.client = client or httpx.Client(timeout=10)
        self._access: tuple[str, float] | None = None
        self._lock = threading.Lock()
        with closing(sqlite3.connect(self.database_path)) as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS push_tokens (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, "
                         "platform TEXT, updated_at INTEGER NOT NULL)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id)")
            conn.execute("CREATE TABLE IF NOT EXISTS push_sent (user_id TEXT NOT NULL, event_key TEXT NOT NULL, "
                         "sent_at INTEGER NOT NULL, PRIMARY KEY(user_id, event_key))")
            conn.commit()

    @property
    def configured(self) -> bool:
        account = self._account or {}
        return all(account.get(k) for k in ("project_id", "client_email", "private_key"))

    # ---------------------------------------------------------- tokens --

    def register(self, user_id: str, token: str, platform: str = "android") -> None:
        with closing(sqlite3.connect(self.database_path)) as conn:
            conn.execute("INSERT OR REPLACE INTO push_tokens(token, user_id, platform, updated_at) VALUES(?,?,?,?)",
                         (token, user_id, platform[:20], int(time.time())))
            conn.commit()

    def unregister(self, user_id: str, token: str | None = None) -> None:
        with closing(sqlite3.connect(self.database_path)) as conn:
            if token:
                conn.execute("DELETE FROM push_tokens WHERE user_id=? AND token=?", (user_id, token))
            else:
                conn.execute("DELETE FROM push_tokens WHERE user_id=?", (user_id,))
            conn.commit()

    def tokens(self, user_id: str) -> list[str]:
        with closing(sqlite3.connect(self.database_path)) as conn:
            return [r[0] for r in conn.execute("SELECT token FROM push_tokens WHERE user_id=?", (user_id,))]

    # ------------------------------------------------------------ send --

    def _access_token(self) -> str | None:
        with self._lock:
            if self._access and self._access[1] > time.time() + 60:
                return self._access[0]
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        account = self._account or {}
        now = int(time.time())
        header = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
        claims = _b64(json.dumps({"iss": account["client_email"], "scope": SCOPE, "aud": TOKEN_URL,
                                  "iat": now, "exp": now + 3600}).encode())
        key = serialization.load_pem_private_key(account["private_key"].encode(), password=None)
        signature = key.sign(f"{header}.{claims}".encode(), padding.PKCS1v15(), hashes.SHA256())
        response = self.client.post(TOKEN_URL, data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": f"{header}.{claims}.{_b64(signature)}",
        })
        if response.status_code != 200:
            return None
        data = response.json()
        with self._lock:
            self._access = (data["access_token"], time.time() + int(data.get("expires_in", 3600)))
        return self._access[0]

    def notify(self, user_id: str, *, title: str, body: str, route: str, event_key: str) -> int:
        """Send one silent update to all of the user's devices, once per
        event. Returns the number of devices it was delivered to (0 when not
        configured, no device, already sent, or FCM refused)."""
        if not self.configured or not user_id:
            return 0
        with closing(sqlite3.connect(self.database_path)) as conn:
            fresh = conn.execute("INSERT OR IGNORE INTO push_sent(user_id, event_key, sent_at) VALUES(?,?,?)",
                                 (user_id, event_key[:120], int(time.time()))).rowcount
            conn.commit()
        if not fresh:
            return 0  # the same event never notifies twice
        tokens = self.tokens(user_id)
        if not tokens:
            return 0
        access = self._access_token()
        if not access:
            return 0
        url = f"https://fcm.googleapis.com/v1/projects/{self._account['project_id']}/messages:send"
        sent = 0
        for token in tokens:
            message = {"message": {
                "token": token,
                "notification": {"title": title[:80], "body": body[:180]},
                "data": {"route": route},
                "android": {"priority": "normal", "notification": {
                    "channel_id": "askodox_updates", "notification_priority": "PRIORITY_LOW", "tag": event_key[:60]}},
            }}
            response = self.client.post(url, json=message, headers={"Authorization": f"Bearer {access}"})
            if response.status_code == 200:
                sent += 1
            elif response.status_code in (400, 404) and "UNREGISTERED" in response.text:
                self.unregister(user_id, token)  # app uninstalled / token rotated
        return sent

    def notify_async(self, user_id: str, **kwargs: Any) -> None:
        """Fire and forget: a push never slows down or breaks the request."""
        if not self.configured:
            return

        def run() -> None:
            try:
                self.notify(user_id, **kwargs)
            except Exception:
                pass

        threading.Thread(target=run, daemon=True).start()


def push_service(container) -> PushService:
    service = getattr(container, "push_service", None)
    if service is None:
        service = PushService(container.settings.database_path)
        container.push_service = service
    return service
