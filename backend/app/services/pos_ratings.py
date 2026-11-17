"""Ratings, reviews, the shop page and the welcome (owner 2026-11-17).

- Ratings = stars only, from people who really bought (a finished desk order or a bill sent to their number): one for the
  shop + one per item of that order. Asked once after the order ends ("later" = asked once more the next day, then never).
- Reviews = written words (+ up to 3 photos) for the SHOP only, like Google: one per person (editable), shown with the
  owner's reply; words / numbers that should not be public are masked by the Talk filter; reported 3 times -> hidden for
  staff review.
- The shop page = the shop's own details (shop_profiles), photos, follow, rating summary, item ratings and reviews.
- Welcome = the customer's own name + how often they came + their usual item, for a greeting on the QR scan; the shop
  writes its own words (or turns it off).
"""

from __future__ import annotations

import base64
import json
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from app.services.pos_store import PosError, PosStore, phone_key

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS pos_ratings (business_id TEXT NOT NULL, user_id TEXT NOT NULL, ref TEXT NOT NULL,"
    " product_id TEXT NOT NULL DEFAULT '', stars INTEGER NOT NULL, at TEXT NOT NULL,"
    " PRIMARY KEY (user_id, ref, product_id))",
    "CREATE INDEX IF NOT EXISTS idx_pos_ratings_biz ON pos_ratings(business_id, product_id)",
    "CREATE TABLE IF NOT EXISTS pos_rating_asks (user_id TEXT NOT NULL, ref TEXT NOT NULL, state TEXT NOT NULL,"
    " at TEXT NOT NULL, PRIMARY KEY (user_id, ref))",
    "CREATE TABLE IF NOT EXISTS pos_reviews (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, user_id TEXT NOT NULL,"
    " stars INTEGER NOT NULL, text TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'shown',"
    " reply TEXT NOT NULL DEFAULT '', reply_at TEXT, reports TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL,"
    " updated_at TEXT NOT NULL, UNIQUE (business_id, user_id))",
    "CREATE TABLE IF NOT EXISTS pos_review_photos (id TEXT PRIMARY KEY, review_id TEXT NOT NULL, business_id TEXT NOT NULL,"
    " mime TEXT NOT NULL, image BLOB NOT NULL, created_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS pos_welcome (business_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 1,"
    " hello TEXT NOT NULL DEFAULT '', again TEXT NOT NULL DEFAULT '', thanks TEXT NOT NULL DEFAULT '',"
    " updated_at TEXT NOT NULL)",
)

FINISHED = ("served", "handed", "delivered", "done")
MAX_PHOTO = 400_000
REPORTS_TO_HIDE = 3

DEFAULT_WELCOME = {
    "hello": "నమస్కారం {name} గారు, {shop} కి స్వాగతం!",
    "again": "నమస్కారం {name} గారు, మళ్ళీ వచ్చినందుకు ధన్యవాదాలు!",
    "thanks": "ధన్యవాదాలు {name} గారు! మళ్ళీ రండి.",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _clean(text: Any, limit: int) -> str:
    return " ".join(str(text or "").split())[:limit]


class PosRatings:
    def __init__(self, store: PosStore, clock=None) -> None:
        self.store = store
        self.clock = clock or _now
        with self.store._tx() as conn:
            for sql in SCHEMA:
                conn.execute(sql)

    # ------------------------------------------------------------------ who may rate
    def _name(self, conn: sqlite3.Connection, user: str) -> str:
        try:
            row = conn.execute("SELECT name FROM user_profiles WHERE user_id = ?", (user,)).fetchone()
        except sqlite3.Error:
            return ""
        return _clean(row["name"], 40) if row and row["name"] else ""

    def _bought(self, conn: sqlite3.Connection, business_id: str, user: str) -> bool:
        if conn.execute("SELECT 1 FROM pos_desk_orders WHERE business_id = ? AND customer_user = ? AND stage IN"
                        f" ({','.join('?' * len(FINISHED))}) LIMIT 1", (business_id, user, *FINISHED)).fetchone():
            return True
        key = phone_key(user)
        if len(key) >= 10:
            try:
                if conn.execute("SELECT 1 FROM pos_invoices i JOIN pos_customers c ON c.id = i.customer_id WHERE"
                                " i.business_id = ? AND c.phone LIKE ? LIMIT 1", (business_id, "%" + key[-10:])).fetchone():
                    return True
            except sqlite3.Error:
                pass
        return False

    # ------------------------------------------------------------------ ratings (stars only)
    def ask(self, user: str, order_id: str) -> Optional[Dict[str, Any]]:
        """What to rate for this finished order, or None (not finished / not theirs / already rated / asked twice)."""
        with self.store._connect() as conn:
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
            if row is None or row["stage"] not in FINISHED:
                return None
            if conn.execute("SELECT 1 FROM pos_ratings WHERE user_id = ? AND ref = ? LIMIT 1", (user, order_id)).fetchone():
                return None
            asked = conn.execute("SELECT state, at FROM pos_rating_asks WHERE user_id = ? AND ref = ?", (user, order_id)).fetchone()
            if asked is not None:
                if asked["state"] != "later":
                    return None
                at = datetime.fromisoformat(asked["at"])
                if self.clock() - at < timedelta(hours=20):
                    return None
            items = [{"product_id": i["product_id"], "name": i["name"]} for i in json.loads(row["items_json"])
                     if i.get("status") != "unavailable"]
            shop = conn.execute("SELECT name FROM pos_businesses WHERE id = ?", (row["business_id"],)).fetchone()
            return {"order_id": order_id, "business_id": row["business_id"], "shop": shop["name"] if shop else "",
                    "name": self._name(conn, user), "items": list({i["product_id"]: i for i in items}.values())}

    def rate(self, user: str, order_id: str, shop_stars: Optional[int], items: Dict[str, int], later: bool = False) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT * FROM pos_desk_orders WHERE id = ? AND customer_user = ?", (order_id, user)).fetchone()
            if row is None:
                raise PosError(404, "order", "Order not found.")
            if row["stage"] not in FINISHED:
                raise PosError(409, "stage", "You can rate once the order is finished.")
            now = self.clock().isoformat()
            if later:
                prev = conn.execute("SELECT state FROM pos_rating_asks WHERE user_id = ? AND ref = ?", (user, order_id)).fetchone()
                state = "later" if prev is None else "never"  # asked once more the next day, then never again
                conn.execute("INSERT OR REPLACE INTO pos_rating_asks (user_id, ref, state, at) VALUES (?, ?, ?, ?)",
                             (user, order_id, state, now))
                return {"saved": 0, "later": True}
            ordered = {i["product_id"] for i in json.loads(row["items_json"])}
            saved = 0
            rows = [("", shop_stars)] + [(pid, s) for pid, s in (items or {}).items() if pid in ordered]
            for pid, stars in rows:
                if stars is None:
                    continue
                stars = int(stars)
                if not 1 <= stars <= 5:
                    raise PosError(400, "stars", "Stars must be 1 to 5.")
                conn.execute("INSERT OR REPLACE INTO pos_ratings (business_id, user_id, ref, product_id, stars, at)"
                             " VALUES (?, ?, ?, ?, ?, ?)", (row["business_id"], user, order_id, pid, stars, now))
                saved += 1
            conn.execute("INSERT OR REPLACE INTO pos_rating_asks (user_id, ref, state, at) VALUES (?, ?, 'done', ?)",
                         (user, order_id, now))
        return {"saved": saved, "later": False}

    @staticmethod
    def summary(conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        """Shop stars from ratings + reviews (each person's latest view counts once per order / review)."""
        stars = [r["stars"] for r in conn.execute(
            "SELECT stars FROM pos_ratings WHERE business_id = ? AND product_id = ''", (business_id,))]
        stars += [r["stars"] for r in conn.execute(
            "SELECT stars FROM pos_reviews WHERE business_id = ? AND status = 'shown'", (business_id,))]
        dist = {str(n): stars.count(n) for n in range(5, 0, -1)}
        return {"average": round(sum(stars) / len(stars), 1) if stars else None, "count": len(stars), "by_stars": dist}

    @staticmethod
    def item_ratings(conn: sqlite3.Connection, business_id: str) -> Dict[str, Dict[str, Any]]:
        return {r["product_id"]: {"average": round(r["avg"], 1), "count": r["n"]} for r in conn.execute(
            "SELECT product_id, AVG(stars) AS avg, COUNT(*) AS n FROM pos_ratings WHERE business_id = ? AND product_id != ''"
            " GROUP BY product_id", (business_id,))}

    # ------------------------------------------------------------------ reviews (shop only, words + photos)
    def write_review(self, user: str, business_id: str, stars: int, text: str, photos: List[Dict[str, Any]]) -> Dict[str, Any]:
        from app.services.talk_moderation import mask_words

        stars = int(stars or 0)
        if not 1 <= stars <= 5:
            raise PosError(400, "stars", "Stars must be 1 to 5.")
        from app.services.pii_mask import mask_sensitive

        words, _ = mask_words(mask_sensitive(_clean(text, 800)))
        with self.store._tx() as conn:
            biz = conn.execute("SELECT owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
            if biz is None:
                raise PosError(404, "business", "Shop not found.")
            if biz["owner_user_id"] == user:
                raise PosError(403, "own_shop", "You cannot review your own shop.")
            if not self._bought(conn, business_id, user):
                raise PosError(403, "not_customer", "Only people who bought here can write a review.")
            now = self.clock().isoformat()
            old = conn.execute("SELECT id FROM pos_reviews WHERE business_id = ? AND user_id = ?", (business_id, user)).fetchone()
            rid = old["id"] if old else f"rev_{uuid.uuid4().hex[:16]}"
            if old:
                conn.execute("UPDATE pos_reviews SET stars = ?, text = ?, updated_at = ? WHERE id = ?", (stars, words, now, rid))
            else:
                conn.execute("INSERT INTO pos_reviews (id, business_id, user_id, stars, text, created_at, updated_at)"
                             " VALUES (?, ?, ?, ?, ?, ?, ?)", (rid, business_id, user, stars, words, now, now))
            for p in (photos or [])[:3]:
                try:
                    raw = base64.b64decode(str(p.get("data") or ""), validate=True)
                except Exception:
                    raise PosError(400, "photo", "That photo could not be read.")
                mime = str(p.get("mime") or "image/jpeg")
                if mime not in ("image/jpeg", "image/png") or not raw or len(raw) > MAX_PHOTO:
                    raise PosError(400, "photo", "Photos must be JPEG / PNG under 400 KB.")
                conn.execute("INSERT INTO pos_review_photos (id, review_id, business_id, mime, image, created_at)"
                             " VALUES (?, ?, ?, ?, ?, ?)", (f"rph_{uuid.uuid4().hex[:16]}", rid, business_id, mime, raw, now))
        return {"id": rid, "stars": stars, "text": words}

    def delete_review(self, user: str, business_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT id FROM pos_reviews WHERE business_id = ? AND user_id = ?", (business_id, user)).fetchone()
            if row:
                conn.execute("DELETE FROM pos_review_photos WHERE review_id = ?", (row["id"],))
                conn.execute("DELETE FROM pos_reviews WHERE id = ?", (row["id"],))
        return {"deleted": bool(row)}

    def reply(self, business_id: str, user: str, review_id: str, text: str) -> Dict[str, Any]:
        from app.services.talk_moderation import mask_words

        with self.store._tx() as conn:
            if self.store.role_of(conn, business_id, user) not in ("owner", "manager"):
                raise PosError(403, "permission", "Only the owner or a manager can reply.")
            words, _ = mask_words(_clean(text, 400))
            n = conn.execute("UPDATE pos_reviews SET reply = ?, reply_at = ? WHERE id = ? AND business_id = ?",
                             (words, self.clock().isoformat(), review_id, business_id)).rowcount
            if not n:
                raise PosError(404, "review", "Review not found.")
        return {"id": review_id, "reply": words}

    def report(self, user: str, review_id: str) -> Dict[str, Any]:
        with self.store._tx() as conn:
            row = conn.execute("SELECT reports, status FROM pos_reviews WHERE id = ?", (review_id,)).fetchone()
            if row is None:
                raise PosError(404, "review", "Review not found.")
            who = set(json.loads(row["reports"] or "[]")) | {user}
            status = "held" if len(who) >= REPORTS_TO_HIDE else row["status"]
            conn.execute("UPDATE pos_reviews SET reports = ?, status = ? WHERE id = ?", (json.dumps(sorted(who)), status, review_id))
        return {"reported": True, "hidden": status == "held"}

    def photo(self, photo_id: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            row = conn.execute("SELECT p.mime, p.image FROM pos_review_photos p JOIN pos_reviews r ON r.id = p.review_id"
                               " WHERE p.id = ? AND r.status = 'shown'", (photo_id,)).fetchone()
        if row is None:
            raise PosError(404, "photo", "Photo not found.")
        return {"mime": row["mime"], "image": bytes(row["image"])}

    def _reviews(self, conn: sqlite3.Connection, business_id: str, user: str, limit: int = 20) -> List[Dict[str, Any]]:
        out = []
        for r in conn.execute("SELECT * FROM pos_reviews WHERE business_id = ? AND (status = 'shown' OR user_id = ?)"
                              " ORDER BY updated_at DESC LIMIT ?", (business_id, user, limit)):
            name = self._name(conn, r["user_id"]) or "ASKODOX customer"
            out.append({"id": r["id"], "stars": r["stars"], "text": r["text"], "name": name.split(" ")[0],
                        "mine": r["user_id"] == user, "at": r["updated_at"], "reply": r["reply"], "reply_at": r["reply_at"],
                        "photos": [p["id"] for p in conn.execute(
                            "SELECT id FROM pos_review_photos WHERE review_id = ? ORDER BY created_at", (r["id"],))]})
        return out

    # ------------------------------------------------------------------ the shop page
    def shop_page(self, business_id: str, user: str) -> Dict[str, Any]:
        with self.store._connect() as conn:
            b = conn.execute("SELECT * FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
            if b is None:
                raise PosError(404, "business", "Shop not found.")
            profile: Dict[str, Any] = {}
            try:
                p = conn.execute("SELECT data FROM shop_profiles WHERE business_id = ?", (business_id,)).fetchone()
                profile = json.loads(p["data"]) if p else {}
            except (sqlite3.Error, ValueError):
                profile = {}
            followers = following = 0
            try:
                followers = conn.execute("SELECT COUNT(*) AS n FROM shop_follows WHERE business_id = ?", (business_id,)).fetchone()["n"]
                following = 1 if conn.execute("SELECT 1 FROM shop_follows WHERE business_id = ? AND app_user_id = ?",
                                              (business_id, user)).fetchone() else 0
            except sqlite3.Error:
                pass
            items = self.item_ratings(conn, business_id)
            names = {r["id"]: r["name"] for r in conn.execute("SELECT id, name FROM pos_products WHERE business_id = ?", (business_id,))}
            top = sorted(((pid, v) for pid, v in items.items() if pid in names), key=lambda x: (-x[1]["count"], -x[1]["average"]))[:6]
            photos: List[Dict[str, str]] = []
            try:
                for r in conn.execute("SELECT product_id FROM pos_product_photos WHERE business_id = ? LIMIT 8", (business_id,)):
                    photos.append({"kind": "item", "id": r["product_id"], "product_id": r["product_id"]})
            except sqlite3.Error:
                pass
            for r in conn.execute("SELECT p.id FROM pos_review_photos p JOIN pos_reviews v ON v.id = p.review_id"
                                  " WHERE p.business_id = ? AND v.status = 'shown' ORDER BY p.created_at DESC LIMIT 12", (business_id,)):
                photos.append({"kind": "review", "id": r["id"]})
            status = (b["status"] if "status" in b.keys() else "open") or "open"
            return {
                "business": {"id": b["id"], "name": b["name"], "address": b["address"], "phone": b["phone"], "status": status,
                             "gst": b["registration_type"] != "unregistered"},
                "profile": {k: profile.get(k, "") for k in ("category", "subcategory", "description", "hours", "landmark",
                                                            "website", "facebook", "instagram", "youtube", "whatsapp",
                                                            "lat", "lng")},
                "followers": followers, "following": bool(following),
                "rating": self.summary(conn, business_id),
                "item_ratings": [{"product_id": pid, "name": names[pid], **v} for pid, v in top],
                "photos": photos, "reviews": self._reviews(conn, business_id, user),
                "can_review": self._bought(conn, business_id, user) and b["owner_user_id"] != user,
                "code": f"ASKODOX-ORDER:{b['id']}",
            }

    # ------------------------------------------------------------------ welcome / thank you
    def welcome_settings(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        row = conn.execute("SELECT * FROM pos_welcome WHERE business_id = ?", (business_id,)).fetchone()
        return {"enabled": bool(row["enabled"]) if row else True,
                **{k: (row[k] if row and row[k] else "") for k in ("hello", "again", "thanks")},
                "defaults": DEFAULT_WELCOME}

    def set_welcome(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            self.store._require(conn, business_id, user, "settings")
            cur = self.welcome_settings(conn, business_id)
            enabled = cur["enabled"] if data.get("enabled") is None else bool(data["enabled"])
            vals = {k: _clean(data[k], 160) if data.get(k) is not None else cur[k] for k in ("hello", "again", "thanks")}
            conn.execute("INSERT OR REPLACE INTO pos_welcome (business_id, enabled, hello, again, thanks, updated_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (business_id, 1 if enabled else 0, vals["hello"], vals["again"],
                                                       vals["thanks"], self.clock().isoformat()))
            return self.welcome_settings(conn, business_id)

    def welcome(self, conn: sqlite3.Connection, business_id: str, user: str) -> Optional[Dict[str, Any]]:
        """The greeting for THIS person at THIS shop (on their own phone only): their name, visits this month, usual item."""
        if not user or not user.startswith("app-"):
            return None
        cfg = self.welcome_settings(conn, business_id)
        if not cfg["enabled"]:
            return None
        b = conn.execute("SELECT name, owner_user_id FROM pos_businesses WHERE id = ?", (business_id,)).fetchone()
        if b is None or b["owner_user_id"] == user:
            return None
        name = self._name(conn, user)
        month = self.clock().strftime("%Y-%m")
        orders = [r for r in conn.execute("SELECT placed_at, items_json FROM pos_desk_orders WHERE business_id = ? AND"
                                          " customer_user = ? AND stage NOT IN ('rejected', 'cancelled')", (business_id, user))]
        counts: Dict[str, int] = {}
        for o in orders:
            for i in json.loads(o["items_json"]):
                counts[i["name"]] = counts.get(i["name"], 0) + 1
        favourite = max(counts, key=counts.get) if counts else ""
        returning = bool(orders)
        fill = lambda t: t.replace("{name}", name or "").replace("{shop}", b["name"]).replace(" గారు", " గారు" if name else "")
        text = cfg["again" if returning else "hello"] or DEFAULT_WELCOME["again" if returning else "hello"]
        thanks = cfg["thanks"] or DEFAULT_WELCOME["thanks"]
        if not name:
            text = text.replace("{name} గారు, ", "").replace("{name} గారు", "").replace("{name}", "")
            thanks = thanks.replace(" {name} గారు", "").replace("{name}", "")
        return {"name": name, "returning": returning, "visits_this_month": sum(1 for o in orders if o["placed_at"][:7] == month),
                "favourite": favourite, "text": fill(text).strip(), "thanks": fill(thanks).strip()}
