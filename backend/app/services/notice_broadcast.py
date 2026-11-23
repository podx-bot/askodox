"""Paid notifications (owner 2026-11-24): ANY signed-in person -- buyer or seller -- sends a notification with a
picture (their photo, or one ASKODOX designs from a subject) to their shop's followers and / or people nearby, at a
few paise per person reached, taken from their AI Credits (free while AI Credits charging is OFF).

Receivers stay in control: the push is the "offers" kind (Settings -> Notifications switches it off), a person gets at
most ``notices.per_day_receiver`` such notifications a day and one a day from the same sender, and unfollowing a shop
stops its notifications. Rude words are masked (``talk_moderation``), links / phone numbers are not allowed in the
text (the notification opens the sender's own ASKODOX page instead), and nothing is sent between 21:00 and 08:00 IST.
The charge covers only the phones the notification can actually reach; what is not delivered is given back.
"""
from __future__ import annotations

import math
import re
import sqlite3
import threading
import uuid
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

IST = timezone(timedelta(hours=5, minutes=30))
AUDIENCES = ("followers", "nearby", "both")
MAX_TITLE = 60
MAX_BODY = 200
MAX_IMAGE_BYTES = 3_000_000  # an AI-made 1024 px PNG fits
QUIET_FROM, QUIET_TO = 21, 8  # IST hours: no notification between 21:00 and 08:00
_LINK_OR_PHONE = re.compile(r"(https?://|www\.|\b[\w.-]+\.(?:com|in|net|org|xyz|link|ly)\b|(?:\+?91[\s-]?)?[6-9]\d{9})",
                            re.IGNORECASE)

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS notices (id TEXT PRIMARY KEY, sender TEXT NOT NULL, business_id TEXT,"
    " title TEXT NOT NULL, body TEXT NOT NULL, image BLOB, image_mime TEXT NOT NULL DEFAULT '', audience TEXT NOT NULL,"
    " radius_km REAL NOT NULL DEFAULT 0, reached INTEGER NOT NULL DEFAULT 0, opened INTEGER NOT NULL DEFAULT 0,"
    " cost_paise INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, client_txn_id TEXT NOT NULL,"
    " created_at TEXT NOT NULL, UNIQUE (sender, client_txn_id))",
    "CREATE INDEX IF NOT EXISTS notices_sender ON notices (sender, created_at)",
    "CREATE TABLE IF NOT EXISTS notice_deliveries (notice_id TEXT NOT NULL, user_id TEXT NOT NULL, sender TEXT NOT NULL,"
    " day TEXT NOT NULL, opened_at TEXT, PRIMARY KEY (notice_id, user_id))",
    "CREATE INDEX IF NOT EXISTS notice_deliveries_user_day ON notice_deliveries (user_id, day)",
)


class NoticeError(Exception):
    def __init__(self, status: int, code: str, message: str, **extra: Any) -> None:
        super().__init__(message)
        self.status, self.code, self.message, self.extra = status, code, message, extra


def _now() -> datetime:
    return datetime.now(timezone.utc)


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def clean_text(text: Any, limit: int) -> str:
    """One line of the sender's own words: rude words masked, links / phone numbers refused."""
    from app.services.talk_moderation import mask_words

    plain = " ".join(str(text or "").split())[:limit]
    if _LINK_OR_PHONE.search(plain):
        raise NoticeError(400, "no_links", "Links and phone numbers are not allowed -- the notification opens your "
                                           "own ASKODOX page.")
    masked, _hits = mask_words(plain)
    return masked


class NoticeBroadcast:
    def __init__(self, db_path: str, *, setting: Callable[[str], float], clock: Callable[[], datetime] = _now) -> None:
        self.db_path = db_path
        self.setting = setting
        self.clock = clock
        with closing(self._connect()) as conn:
            for sql in SCHEMA:
                conn.execute(sql)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        return conn

    def _day(self) -> str:
        return self.clock().astimezone(IST).strftime("%Y-%m-%d")

    def quiet_now(self) -> bool:
        hour = self.clock().astimezone(IST).hour
        return hour >= QUIET_FROM or hour < QUIET_TO

    # ----------------------------------------------------------------- who --

    @staticmethod
    def _table(conn: sqlite3.Connection, name: str) -> bool:
        return bool(conn.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (name,)).fetchone())

    def _owns(self, conn: sqlite3.Connection, business_id: str, user: str) -> bool:
        if not self._table(conn, "pos_businesses"):
            return False
        row = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        return bool(row) and row["owner_user_id"] == user

    def _followers(self, conn: sqlite3.Connection, business_id: str) -> List[str]:
        if not business_id or not self._table(conn, "shop_follows"):
            return []
        return [r[0] for r in conn.execute("SELECT app_user_id FROM shop_follows WHERE business_id = ?", (business_id,))]

    def _centre(self, conn: sqlite3.Connection, user: str, lat: Optional[float], lon: Optional[float]):
        if lat is not None and lon is not None:
            return float(lat), float(lon)
        if self._table(conn, "user_profiles"):
            row = conn.execute("SELECT latitude, longitude FROM user_profiles WHERE user_id = ?", (user,)).fetchone()
            if row and row["latitude"] is not None and row["longitude"] is not None:
                return float(row["latitude"]), float(row["longitude"])
        return None

    def _nearby(self, conn: sqlite3.Connection, centre, radius_km: float) -> List[str]:
        if not centre or radius_km <= 0 or not self._table(conn, "user_profiles"):
            return []
        lat, lon = centre
        d_lat = radius_km / 111.0
        d_lon = radius_km / max(1e-6, 111.0 * math.cos(math.radians(lat)))
        rows = conn.execute("SELECT user_id, latitude, longitude FROM user_profiles WHERE latitude BETWEEN ? AND ? AND"
                            " longitude BETWEEN ? AND ?", (lat - d_lat, lat + d_lat, lon - d_lon, lon + d_lon))
        return [r["user_id"] for r in rows if distance_km(lat, lon, r["latitude"], r["longitude"]) <= radius_km]

    def _reachable(self, conn: sqlite3.Connection, users: List[str]) -> List[str]:
        """People who can get it today: a phone registered, under their daily cap, not already sent one by this
        sender today. (Their own notification switches are checked again by the push service at send time.)"""
        if not users or not self._table(conn, "push_tokens"):
            return []
        with_phone = {r[0] for r in conn.execute("SELECT DISTINCT user_id FROM push_tokens")}
        return [u for u in users if u in with_phone]

    def audience(self, user: str, *, audience: str, business_id: str = "", radius_km: float = 0,
                 lat: Optional[float] = None, lon: Optional[float] = None) -> List[str]:
        if audience not in AUDIENCES:
            raise NoticeError(400, "audience", "Choose followers, nearby or both.")
        day = self._day()
        cap = int(self.setting("notices.per_day_receiver"))
        with closing(self._connect()) as conn:
            people: Dict[str, None] = {}
            if audience in ("followers", "both"):
                if not business_id or not self._owns(conn, business_id, user):
                    if audience == "followers":
                        raise NoticeError(403, "not_owner", "Only the shop owner can notify the shop's followers.")
                else:
                    people.update(dict.fromkeys(self._followers(conn, business_id)))
            if audience in ("nearby", "both"):
                centre = self._centre(conn, user, lat, lon)
                if not centre:
                    raise NoticeError(409, "no_location", "Set your location first to reach people nearby.")
                people.update(dict.fromkeys(self._nearby(conn, centre, max(0.5, min(float(radius_km or 3), 20.0)))))
            people.pop(user, None)
            reachable = self._reachable(conn, list(people))
            out = []
            for person in reachable:
                today = conn.execute("SELECT COUNT(*), SUM(sender = ?) FROM notice_deliveries WHERE user_id = ? AND day = ?",
                                     (user, person, day)).fetchone()
                if int(today[0] or 0) >= cap or int(today[1] or 0) >= 1:
                    continue
                out.append(person)
        return out[: int(self.setting("notices.max_recipients"))]

    def preview(self, user: str, **kw: Any) -> Dict[str, Any]:
        people = self.audience(user, **kw)
        rate = int(self.setting("notices.rate_paise"))
        return {"people": len(people), "rate_paise": rate, "cost_paise": rate * len(people),
                "quiet_now": self.quiet_now(), "sent_today": self._sent_today(user),
                "per_day": int(self.setting("notices.per_day_sender"))}

    def _sent_today(self, user: str) -> int:
        start = self.clock().astimezone(IST).replace(hour=0, minute=0, second=0, microsecond=0)
        with closing(self._connect()) as conn:
            return int(conn.execute("SELECT COUNT(*) FROM notices WHERE sender = ? AND status != 'failed' AND"
                                    " created_at >= ?", (user, start.astimezone(timezone.utc).isoformat())).fetchone()[0])

    # ----------------------------------------------------------------- send --

    def create(self, user: str, *, title: str, body: str, image: bytes = b"", image_mime: str = "",
               audience: str, business_id: str = "", radius_km: float = 0, lat: Optional[float] = None,
               lon: Optional[float] = None, client_txn_id: str, charge: Callable[[str, int], Dict[str, Any]]) -> Dict[str, Any]:
        """Checks, charges (``charge(ref, paise)``) and stores the notification; ``deliver`` then sends it."""
        title, body = clean_text(title, MAX_TITLE), clean_text(body, MAX_BODY)
        if not title:
            raise NoticeError(400, "title", "Write a short heading.")
        if image and (len(image) > MAX_IMAGE_BYTES or image_mime not in ("image/png", "image/jpeg", "image/webp")):
            raise NoticeError(400, "image", "Send a PNG / JPEG / WebP picture up to 3 MB.")
        txn = str(client_txn_id or "")[:64]
        if not txn:
            raise NoticeError(400, "client_txn_id", "client_txn_id is required.")
        with closing(self._connect()) as conn:
            old = conn.execute("SELECT * FROM notices WHERE sender = ? AND client_txn_id = ?", (user, txn)).fetchone()
        if old:  # the same tap twice is the same notification
            return self._row(old)
        if self.quiet_now():
            raise NoticeError(409, "quiet_hours", "Notifications go out between 8 am and 9 pm. Send it in the morning.")
        if self._sent_today(user) >= int(self.setting("notices.per_day_sender")):
            raise NoticeError(429, "daily_limit", "You have sent today's notifications. Send more tomorrow.")
        people = self.audience(user, audience=audience, business_id=business_id, radius_km=radius_km, lat=lat, lon=lon)
        if not people:
            raise NoticeError(409, "nobody", "Nobody can be reached right now (no followers / nobody nearby with ASKODOX).")
        notice_id = f"ntc_{uuid.uuid4().hex[:20]}"
        cost = int(self.setting("notices.rate_paise")) * len(people)
        paid = charge(notice_id, cost)  # raises when the credits are not enough
        now = self.clock().isoformat()
        with closing(self._connect()) as conn:
            conn.execute("INSERT INTO notices (id, sender, business_id, title, body, image, image_mime, audience,"
                         " radius_km, reached, cost_paise, status, client_txn_id, created_at) VALUES"
                         " (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                         (notice_id, user, business_id or None, title, body, sqlite3.Binary(image) if image else None,
                          image_mime if image else "", audience, float(radius_km or 0), 0,
                          int(paid.get("paise") or 0) if paid.get("charged") else 0, "sending", txn, now))
            day = self._day()
            conn.executemany("INSERT OR IGNORE INTO notice_deliveries (notice_id, user_id, sender, day) VALUES (?,?,?,?)",
                             [(notice_id, p, user, day) for p in people])
            conn.commit()
        return {**self.get_own(notice_id, user), "people": people}

    def deliver(self, notice_id: str, push: Any, *, on_unused: Optional[Callable[[int], None]] = None) -> int:
        """Send to every person stored for it (push obeys each person's switches). Records how many phones took it;
        the charge for people it could not reach goes back through ``on_unused(paise)``."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM notices WHERE id = ?", (notice_id,)).fetchone()
            people = [r[0] for r in conn.execute("SELECT user_id FROM notice_deliveries WHERE notice_id = ?", (notice_id,))]
        if not row:
            return 0
        reached = 0
        for person in people:
            try:
                sent = push.notify(person, title=row["title"], body=row["body"], route=f"/notice/{notice_id}",
                                   event_key=f"notice:{notice_id}") if push is not None else 0
            except Exception:
                sent = 0
            if sent:
                reached += 1
            else:
                with closing(self._connect()) as conn:
                    conn.execute("DELETE FROM notice_deliveries WHERE notice_id = ? AND user_id = ?", (notice_id, person))
                    conn.commit()
        rate = int(self.setting("notices.rate_paise"))
        unused = (len(people) - reached) * rate if row["cost_paise"] else 0
        with closing(self._connect()) as conn:
            conn.execute("UPDATE notices SET reached = ?, status = 'sent', cost_paise = MAX(0, cost_paise - ?) WHERE id = ?",
                         (reached, unused, notice_id))
            conn.commit()
        if unused and on_unused:
            on_unused(unused)
        return reached

    def deliver_async(self, notice_id: str, push: Any, **kw: Any) -> None:
        threading.Thread(target=lambda: self.deliver(notice_id, push, **kw), daemon=True).start()

    # ----------------------------------------------------------------- read --

    @staticmethod
    def _row(row: sqlite3.Row) -> Dict[str, Any]:
        return {"id": row["id"], "title": row["title"], "body": row["body"], "has_image": row["image"] is not None,
                "business_id": row["business_id"], "audience": row["audience"], "reached": row["reached"],
                "opened": row["opened"], "cost_paise": row["cost_paise"], "status": row["status"],
                "created_at": row["created_at"]}

    def get_own(self, notice_id: str, user: str) -> Dict[str, Any]:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM notices WHERE id = ? AND sender = ?", (notice_id, user)).fetchone()
        if not row:
            raise NoticeError(404, "not_found", "Notification not found.")
        return self._row(row)

    def mine(self, user: str, limit: int = 30) -> List[Dict[str, Any]]:
        with closing(self._connect()) as conn:
            rows = conn.execute("SELECT * FROM notices WHERE sender = ? ORDER BY created_at DESC LIMIT ?",
                                (user, int(limit))).fetchall()
        return [self._row(r) for r in rows]

    def open(self, notice_id: str, user: str) -> Dict[str, Any]:
        """A receiver (or the sender) opens it: counted once per receiver."""
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT * FROM notices WHERE id = ?", (notice_id,)).fetchone()
            if not row:
                raise NoticeError(404, "not_found", "Notification not found.")
            if row["sender"] != user:
                got = conn.execute("SELECT opened_at FROM notice_deliveries WHERE notice_id = ? AND user_id = ?",
                                   (notice_id, user)).fetchone()
                if not got:
                    raise NoticeError(404, "not_found", "Notification not found.")
                if got["opened_at"] is None:
                    conn.execute("UPDATE notice_deliveries SET opened_at = ? WHERE notice_id = ? AND user_id = ?",
                                 (self.clock().isoformat(), notice_id, user))
                    conn.execute("UPDATE notices SET opened = opened + 1 WHERE id = ?", (notice_id,))
                    conn.commit()
            name = ""
            if row["business_id"] and self._table(conn, "pos_businesses"):
                shop = conn.execute("SELECT name FROM pos_businesses WHERE id = ?", (row["business_id"],)).fetchone()
                name = shop["name"] if shop else ""
        out = {**self._row(row), "from_shop": name, "mine": row["sender"] == user}
        if row["image"] is not None:
            import base64

            out["image_base64"] = base64.b64encode(bytes(row["image"])).decode("ascii")
            out["image_mime"] = row["image_mime"]
        return out

    def image(self, notice_id: str, user: str) -> tuple:
        with closing(self._connect()) as conn:
            row = conn.execute("SELECT sender, image, image_mime FROM notices WHERE id = ?", (notice_id,)).fetchone()
            if not row or row["image"] is None:
                raise NoticeError(404, "not_found", "No picture.")
            if row["sender"] != user and not conn.execute(
                    "SELECT 1 FROM notice_deliveries WHERE notice_id = ? AND user_id = ?", (notice_id, user)).fetchone():
                raise NoticeError(404, "not_found", "No picture.")
            return bytes(row["image"]), row["image_mime"]
