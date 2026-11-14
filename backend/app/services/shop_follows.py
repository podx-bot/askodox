"""Follow a shop. Any signed-in person can follow a shop, shop owners included (they can follow other shops).

One row per (shop, person) in ``shop_follows``. Follower identities are never returned: a shop sees only a count.
A shop cannot be followed by its own owner. Following never sends anything by itself: the shop's posts reach the
people who follow it through the Updates feed (a later step).
"""

from __future__ import annotations

import base64
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List

from app.services.pos_store import PosError

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS shop_follows (business_id TEXT NOT NULL, app_user_id TEXT NOT NULL,"
    " created_at TEXT NOT NULL, PRIMARY KEY (business_id, app_user_id))",
    "CREATE INDEX IF NOT EXISTS shop_follows_user ON shop_follows (app_user_id, created_at)",
    # One branded picture per shop per day (the owner's), kept on the server so followers can open it later.
    "CREATE TABLE IF NOT EXISTS shop_posts (id TEXT PRIMARY KEY, business_id TEXT NOT NULL, caption TEXT NOT NULL,"
    " day TEXT NOT NULL, created_at TEXT NOT NULL, image BLOB NOT NULL)",
    "CREATE INDEX IF NOT EXISTS shop_posts_business ON shop_posts (business_id, created_at)",
    "CREATE TABLE IF NOT EXISTS shop_profiles (business_id TEXT PRIMARY KEY, data TEXT NOT NULL,"
    " updated_at TEXT NOT NULL, verified_at TEXT)",
)
# The shop's own details (owner 2026-11-14): shown before anything from Google. Text only, the owner's own words.
PROFILE_FIELDS = {  # field -> max length
    "category": 80, "subcategory": 80, "description": 600, "address": 200, "landmark": 120, "hours": 120, "website": 200,
    "facebook": 200, "instagram": 200, "youtube": 200, "whatsapp": 20, "offers": 300, "delivery": 120,
    "extra": 600, "reg_number": 40,
}
PROFILE_REQUIRED = ("category", "description", "address", "hours")

# Ready-to-pick shop categories (owner 2026-11-14): category -> sub-categories, English + Telugu. The app shows them as
# two dropdowns; "other" lets the owner type their own. Stored values are the keys below (or "other:<their words>").
SHOP_CATEGORIES: List[Dict[str, Any]] = [
    {"key": "meat_fish", "en": "Meat & fish", "te": "మాంసం & చేపలు", "subs": [
        ("chicken", "Chicken", "చికెన్"), ("mutton", "Mutton", "మటన్"), ("fish", "Fish", "చేపలు"),
        ("prawns", "Prawns", "రొయ్యలు"), ("eggs", "Eggs", "గుడ్లు")]},
    {"key": "grocery", "en": "Grocery", "te": "కిరాణా", "subs": [
        ("kirana", "Kirana store", "కిరాణా షాప్"), ("supermarket", "Supermarket", "సూపర్ మార్కెట్"),
        ("rice_grains", "Rice & grains", "బియ్యం & ధాన్యాలు"), ("oil_ghee", "Oil & ghee", "నూనె & నెయ్యి"),
        ("dry_fruits", "Dry fruits", "డ్రై ఫ్రూట్స్")]},
    {"key": "veg_fruits", "en": "Vegetables & fruits", "te": "కూరగాయలు & పండ్లు", "subs": [
        ("vegetables", "Vegetables", "కూరగాయలు"), ("fruits", "Fruits", "పండ్లు"), ("flowers", "Flowers", "పూలు")]},
    {"key": "dairy_bakery", "en": "Dairy, sweets & bakery", "te": "పాలు, స్వీట్లు & బేకరీ", "subs": [
        ("milk", "Milk & curd", "పాలు & పెరుగు"), ("sweets", "Sweets", "స్వీట్లు"), ("bakery", "Bakery", "బేకరీ"),
        ("tea_snacks", "Tea & snacks", "టీ & స్నాక్స్")]},
    {"key": "food", "en": "Restaurant & food", "te": "హోటల్ & ఆహారం", "subs": [
        ("tiffin", "Tiffin centre", "టిఫిన్ సెంటర్"), ("meals", "Meals / restaurant", "భోజనం / రెస్టారెంట్"),
        ("biryani", "Biryani", "బిర్యానీ"), ("fast_food", "Fast food", "ఫాస్ట్ ఫుడ్"),
        ("juice", "Juice & ice cream", "జ్యూస్ & ఐస్ క్రీం"), ("catering", "Catering", "క్యాటరింగ్")]},
    {"key": "clothing", "en": "Clothes & tailoring", "te": "బట్టలు & టైలరింగ్", "subs": [
        ("clothes", "Clothes", "బట్టలు"), ("sarees", "Sarees", "చీరలు"), ("readymade", "Readymade", "రెడీమేడ్"),
        ("footwear", "Footwear", "చెప్పులు"), ("tailor", "Tailor", "టైలర్")]},
    {"key": "mobile_electronics", "en": "Mobile & electronics", "te": "మొబైల్ & ఎలక్ట్రానిక్స్", "subs": [
        ("mobile_shop", "Mobile shop", "మొబైల్ షాప్"), ("mobile_repair", "Mobile repair", "మొబైల్ రిపేర్"),
        ("electronics", "Electronics", "ఎలక్ట్రానిక్స్"), ("computer", "Computer & printing", "కంప్యూటర్ & ప్రింటింగ్")]},
    {"key": "home_hardware", "en": "Home & hardware", "te": "ఇల్లు & హార్డ్‌వేర్", "subs": [
        ("hardware", "Hardware", "హార్డ్‌వేర్"), ("paints", "Paints", "పెయింట్స్"),
        ("electrical", "Electrical items", "ఎలక్ట్రికల్ సామాన్లు"), ("plumbing_items", "Plumbing items", "ప్లంబింగ్ సామాన్లు"),
        ("furniture", "Furniture", "ఫర్నిచర్")]},
    {"key": "beauty", "en": "Beauty & personal care", "te": "అందం & వ్యక్తిగత సంరక్షణ", "subs": [
        ("salon", "Salon", "సెలూన్"), ("beauty_parlour", "Beauty parlour", "బ్యూటీ పార్లర్"),
        ("cosmetics", "Cosmetics", "కాస్మెటిక్స్")]},
    {"key": "health", "en": "Health", "te": "ఆరోగ్యం", "subs": [
        ("medical_shop", "Medical shop", "మెడికల్ షాప్"), ("clinic", "Clinic", "క్లినిక్"),
        ("lab", "Diagnostic lab", "ల్యాబ్"), ("optical", "Optical", "కళ్ళద్దాలు")]},
    {"key": "vehicles", "en": "Vehicles", "te": "వాహనాలు", "subs": [
        ("bike_repair", "Bike repair", "బైక్ రిపేర్"), ("car_repair", "Car repair", "కార్ రిపేర్"),
        ("spare_parts", "Spare parts", "స్పేర్ పార్ట్స్"), ("tyres", "Tyres", "టైర్లు"),
        ("wash", "Car / bike wash", "కార్ / బైక్ వాష్")]},
    {"key": "farming", "en": "Farming", "te": "వ్యవసాయం", "subs": [
        ("fertilizers", "Fertilizers & seeds", "ఎరువులు & విత్తనాలు"), ("pesticides", "Pesticides", "పురుగు మందులు"),
        ("farm_tools", "Farm tools", "వ్యవసాయ పనిముట్లు"), ("dairy_farm", "Dairy farm", "డెయిరీ ఫామ్")]},
    {"key": "services", "en": "Home services", "te": "ఇంటి సేవలు", "subs": [
        ("electrician", "Electrician", "ఎలక్ట్రీషియన్"), ("plumber", "Plumber", "ప్లంబర్"),
        ("carpenter", "Carpenter", "కార్పెంటర్"), ("cleaning", "Cleaning", "క్లీనింగ్"),
        ("laundry", "Laundry", "లాండ్రీ"), ("photography", "Photography", "ఫోటోగ్రఫీ")]},
    {"key": "education", "en": "Education", "te": "విద్య", "subs": [
        ("tuition", "Tuition", "ట్యూషన్"), ("coaching", "Coaching", "కోచింగ్"),
        ("school", "School / college", "స్కూల్ / కాలేజ్"), ("stationery", "Stationery & books", "స్టేషనరీ & పుస్తకాలు")]},
    {"key": "transport", "en": "Travel & transport", "te": "ప్రయాణం & రవాణా", "subs": [
        ("cab", "Taxi / cab", "టాక్సీ / క్యాబ్"), ("auto", "Auto", "ఆటో"), ("travels", "Travels", "ట్రావెల్స్"),
        ("goods", "Goods transport", "సరుకు రవాణా")]},
    {"key": "events", "en": "Events", "te": "ఈవెంట్లు", "subs": [
        ("function_hall", "Function hall", "ఫంక్షన్ హాల్"), ("decoration", "Decoration", "డెకరేషన్"),
        ("tent_house", "Tent house", "టెంట్ హౌస్"), ("sound_light", "Sound & lighting", "సౌండ్ & లైటింగ్")]},
]
_CATEGORY_BY_KEY = {c["key"]: c for c in SHOP_CATEGORIES}


def shop_categories() -> List[Dict[str, Any]]:
    return [{"key": c["key"], "en": c["en"], "te": c["te"],
             "subs": [{"key": k, "en": en, "te": te} for k, en, te in c["subs"]]} for c in SHOP_CATEGORIES]


def category_labels(category: str, subcategory: str) -> Dict[str, Dict[str, str]]:
    """Readable names for the stored keys ("other:<words>" shows the words as typed)."""
    out: Dict[str, Dict[str, str]] = {}
    top = _CATEGORY_BY_KEY.get(category)
    if top:
        out["category"] = {"en": top["en"], "te": top["te"]}
    elif category:
        words = category.split(":", 1)[1] if category.startswith("other:") else category
        out["category"] = {"en": words, "te": words}
    if subcategory:
        match = next(((en, te) for k, en, te in (top or {}).get("subs", ()) if k == subcategory), None)
        words = subcategory.split(":", 1)[1] if subcategory.startswith("other:") else subcategory
        out["subcategory"] = {"en": match[0], "te": match[1]} if match else {"en": words, "te": words}
    return out
PROFILE_PRIVATE = ("reg_number",)  # GST / Udyam number: for ASKODOX's check only, never shown to others
MAX_IMAGE_BYTES = 900_000
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
MAX_CAPTION = 300


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class ShopFollows:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=15, isolation_level=None)
        conn.row_factory = sqlite3.Row
        return conn

    def _shop(self, conn: sqlite3.Connection, business_id: str) -> sqlite3.Row:
        row = conn.execute(
            "SELECT id, owner_user_id, name, address, template FROM pos_businesses WHERE id = ?",
            (business_id,)).fetchone()
        if row is None:
            raise PosError(404, "shop_not_found", "Shop not found.")
        return row

    def _state(self, conn: sqlite3.Connection, shop: sqlite3.Row, user: str) -> Dict[str, Any]:
        following = conn.execute(
            "SELECT 1 FROM shop_follows WHERE business_id = ? AND app_user_id = ?",
            (shop["id"], user)).fetchone() is not None
        followers = conn.execute(
            "SELECT COUNT(*) AS n FROM shop_follows WHERE business_id = ?", (shop["id"],)).fetchone()["n"]
        is_owner = shop["owner_user_id"] == user
        profile = self._profile(conn, shop["id"], private=is_owner)
        return {
            "business_id": shop["id"],
            "name": shop["name"],
            "address": profile["fields"].get("address") or shop["address"],
            "category": (profile["labels"].get("category") or {}).get("en") or shop["template"],
            "followers": int(followers),
            "following": following,
            "is_owner": is_owner,
            "profile": profile,
        }

    def _profile(self, conn: sqlite3.Connection, business_id: str, private: bool) -> Dict[str, Any]:
        row = conn.execute("SELECT data, verified_at FROM shop_profiles WHERE business_id = ?",
                           (business_id,)).fetchone()
        fields: Dict[str, str] = {}
        if row is not None:
            try:
                fields = {k: str(v) for k, v in json.loads(row["data"]).items() if k in PROFILE_FIELDS and v}
            except ValueError:
                fields = {}
        missing = [k for k in PROFILE_REQUIRED if not fields.get(k)]
        # "verified" only after ASKODOX staff check it (verified_at); filling the form never verifies by itself.
        status = "verified" if row is not None and row["verified_at"] and not missing else (
            "incomplete" if missing else "submitted")
        shown = fields if private else {k: v for k, v in fields.items() if k not in PROFILE_PRIVATE}
        return {"fields": shown, "missing": missing, "status": status,
                "labels": category_labels(fields.get("category", ""), fields.get("subcategory", ""))}

    def save_profile(self, business_id: str, user: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """The owner's own details. Unknown fields are dropped; a changed profile needs a fresh check."""
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            if shop["owner_user_id"] != user:
                raise PosError(403, "not_owner", "Only the shop owner can change these details.")
            fields = {}
            for key, limit in PROFILE_FIELDS.items():
                value = " ".join(str(data.get(key) or "").split())[:limit]
                if value:
                    fields[key] = value
            conn.execute(
                "INSERT INTO shop_profiles (business_id, data, updated_at, verified_at) VALUES (?, ?, ?, NULL)"
                " ON CONFLICT(business_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at,"
                " verified_at = NULL", (business_id, json.dumps(fields, ensure_ascii=False), _now()))
            return self._state(conn, shop, user)

    def get(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            return self._state(conn, self._shop(conn, business_id), user)

    def follow(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            if shop["owner_user_id"] == user:
                raise PosError(409, "own_shop", "A shop cannot be followed by its own owner.")
            conn.execute(
                "INSERT OR IGNORE INTO shop_follows (business_id, app_user_id, created_at) VALUES (?, ?, ?)",
                (business_id, user, _now()))
            return self._state(conn, shop, user)

    def unfollow(self, business_id: str, user: str) -> Dict[str, Any]:
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            conn.execute("DELETE FROM shop_follows WHERE business_id = ? AND app_user_id = ?", (business_id, user))
            return self._state(conn, shop, user)

    def my_follows(self, user: str) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT b.id, b.name, b.address, b.template, f.created_at FROM shop_follows f"
                " JOIN pos_businesses b ON b.id = f.business_id WHERE f.app_user_id = ?"
                " ORDER BY f.created_at DESC LIMIT 200", (user,)).fetchall()
        return [{"business_id": r["id"], "name": r["name"], "address": r["address"],
                 "category": r["template"], "followed_at": r["created_at"]} for r in rows]

    # ---- the owner's daily picture (the picture is made on the phone, with the shop name and ASKODOX brand burned in)

    def post(self, business_id: str, user: str, caption: str, image: bytes) -> Dict[str, Any]:
        caption = (caption or "").strip()
        if not caption or len(caption) > MAX_CAPTION:
            raise PosError(400, "caption", "Caption is required (up to 300 characters).")
        if not image.startswith(PNG_MAGIC) or len(image) > MAX_IMAGE_BYTES:
            raise PosError(400, "image", "Send a PNG picture up to 900 KB.")
        with self._connect() as conn:
            shop = self._shop(conn, business_id)
            if shop["owner_user_id"] != user:
                raise PosError(403, "not_owner", "Only the shop owner can post for this shop.")
            now = datetime.now(timezone.utc)
            day = now.strftime("%Y-%m-%d")
            if conn.execute("SELECT 1 FROM shop_posts WHERE business_id = ? AND day = ?",
                            (business_id, day)).fetchone():
                raise PosError(409, "already_posted_today", "This shop already posted today. Try tomorrow.")
            post_id = f"spost_{uuid.uuid4().hex[:20]}"
            conn.execute("INSERT INTO shop_posts (id, business_id, caption, day, created_at, image)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (post_id, business_id, caption, day, now.isoformat(),
                                                        sqlite3.Binary(image)))
            return {"id": post_id, "business_id": business_id, "caption": caption, "day": day,
                    "created_at": now.isoformat()}

    def feed(self, user: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Pictures from the shops this person follows, newest first (never the followers themselves).
        The picture comes as base64 so the app needs no second request (at most 10 at a time)."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT p.id, p.caption, p.created_at, p.image, b.id AS business_id, b.name FROM shop_posts p"
                " JOIN shop_follows f ON f.business_id = p.business_id AND f.app_user_id = ?"
                " JOIN pos_businesses b ON b.id = p.business_id"
                " ORDER BY p.created_at DESC LIMIT ?", (user, max(1, min(int(limit), 10)))).fetchall()
        return [{"id": r["id"], "caption": r["caption"], "created_at": r["created_at"],
                 "business_id": r["business_id"], "shop_name": r["name"],
                 "credit": f"Created by {r['name']} · ASKODOX",
                 "image_base64": base64.b64encode(bytes(r["image"])).decode("ascii")} for r in rows]

    def image(self, post_id: str, user: str) -> bytes:
        """The picture. Only the owner and people who follow the shop can open it."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT p.image, p.business_id, b.owner_user_id FROM shop_posts p"
                " JOIN pos_businesses b ON b.id = p.business_id WHERE p.id = ?", (post_id,)).fetchone()
            if row is None:
                raise PosError(404, "post_not_found", "Post not found.")
            allowed = row["owner_user_id"] == user or conn.execute(
                "SELECT 1 FROM shop_follows WHERE business_id = ? AND app_user_id = ?",
                (row["business_id"], user)).fetchone() is not None
            if not allowed:
                raise PosError(403, "not_follower", "Follow this shop to open its picture.")
            return bytes(row["image"])
