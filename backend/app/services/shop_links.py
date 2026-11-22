"""Shop link (owner 2026-11-22, design artifact GyGuSkNsVrf6cxXQBZk7h4): ONE free public page per shop,
``askodox.com/s/<slug>`` -- menu with prices, order on WhatsApp (a ready message), call, map, the shop's OWN UPI,
offer line, stars, follow / app banner, and "get the app" after an order. Proxied on askodox.com (website Caddyfile).

Rules:
- Only the shop OWNER (signed in with their own OTP) turns a link on: a page in a shop's name never exists without
  them. Managers / accountants (``reports``) may read it and its counts; other staff never.
- The money goes straight to the shop's own UPI (``payment_methods``); ASKODOX never holds it.
- No customer identity is stored: the page counts views / taps per day only (``shop_link_counts``).
- An old slug keeps working (``shop_link_aliases`` -> 301 to the new one) so printed posters never break.
- Offer / about lines refuse web links (a shop page must never carry a phishing link).
"""
from __future__ import annotations

import json
import re
import secrets
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional
from urllib.parse import quote

from app.services.pos_store import PosError, PosStore

PUBLIC_BASE = "https://askodox.com/s/"
PLAY_URL = "https://play.google.com/store/apps/details?id=com.askodox.askodox"
IST = timezone(timedelta(hours=5, minutes=30))

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS shop_links (business_id TEXT PRIMARY KEY, slug TEXT NOT NULL UNIQUE,"
    " enabled INTEGER NOT NULL DEFAULT 1, settings TEXT NOT NULL DEFAULT '{}', created_by TEXT NOT NULL,"
    " created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS shop_link_aliases (slug TEXT PRIMARY KEY, business_id TEXT NOT NULL, at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS shop_link_counts (business_id TEXT NOT NULL, day TEXT NOT NULL, kind TEXT NOT NULL,"
    " n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (business_id, day, kind))",
]

# What the page counts (no person, only how many): a page view, the two order ways, call / map / pay taps,
# a WhatsApp chat, the app banner, follow (opens the app page) and "a free link for my shop too".
COUNT_KINDS = ("view", "order_wa", "order_app", "call", "chat", "map", "pay", "app", "follow", "join")

COLORS: Dict[str, str] = {"green": "#0B7A4B", "blue": "#1D4ED8", "maroon": "#9D1D5A", "orange": "#C2410C",
                          "purple": "#6D28D9", "dark": "#1E293B"}

DEFAULTS: Dict[str, Any] = {"show_menu": True, "show_prices": True, "show_call": True, "show_map": True,
                            "show_pay": True, "offer": "", "about": "", "color": "green", "whatsapp": ""}

RESERVED = {"admin", "api", "app", "askodox", "help", "support", "login", "signin", "www", "shop", "shops", "static",
            "staff", "official", "pay", "bill", "bills", "order", "orders", "play", "store", "s", "p", "b", "go",
            "about", "terms", "privacy", "contact", "news", "jobs", "test", "demo", "null", "none", "undefined"}

KIND_LABELS: Dict[str, tuple] = {
    "general": ("Shop", "షాప్"), "kirana": ("Kirana store", "కిరాణా షాప్"), "supermarket": ("Supermarket", "సూపర్ మార్కెట్"),
    "meat_fish": ("Meat & fish", "చికెన్ / మటన్ / చేపలు"), "restaurant": ("Hotel & food", "హోటల్ / ఫుడ్"),
    "pharmacy": ("Medical shop", "మెడికల్ షాప్"), "salon": ("Salon", "సెలూన్"), "repair": ("Repairs", "రిపేర్ షాప్"),
    "wholesale": ("Wholesale", "హోల్‌సేల్"), "clothing": ("Clothes", "బట్టల షాప్"), "electronics": ("Electronics", "ఎలక్ట్రానిక్స్"),
    "jewellery": ("Jewellery", "నగల షాప్"), "bakery": ("Bakery", "బేకరీ"), "vegetables": ("Vegetables", "కూరగాయలు"),
    "hardware": ("Hardware", "హార్డ్‌వేర్"), "stationery": ("Stationery", "స్టేషనరీ"),
}

_SLUG_OK = re.compile(r"^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){2,29}$")
_WEB_LINK = re.compile(r"(https?://|www\.|\b[a-z0-9-]+\.(?:com|in|net|org|ly|io|co|me|xyz|top|link|site|app)\b)", re.I)
_WEIGHED = {"kg", "g", "l", "ml", "m"}


def clean_slug(text: str) -> str:
    """Lower-case letters, digits and single hyphens; spaces / dots / underscores -> hyphen; others dropped."""
    s = re.sub(r"[\s._/]+", "-", str(text or "").strip().lower())
    s = re.sub(r"[^a-z0-9-]", "", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s[:30].strip("-")


def slug_problem(slug: str) -> str:
    """'' = fine; else a short reason key (too_short / format / reserved)."""
    if len(slug) < 3:
        return "too_short"
    if not _SLUG_OK.match(slug):
        return "format"
    if slug in RESERVED or slug.startswith("askodox"):
        return "reserved"
    return ""


def ten_digits(phone: Any) -> str:
    d = re.sub(r"\D", "", str(phone or ""))
    if len(d) == 12 and d.startswith("91"):
        d = d[2:]
    elif len(d) == 11 and d.startswith("0"):
        d = d[1:]
    return d if len(d) == 10 and d[0] in "6789" else ""


def _rupees(paise: int) -> str:
    paise = int(paise or 0)
    return f"₹{paise // 100:,}" if paise % 100 == 0 else f"₹{paise / 100:,.2f}"


def _qty_text(qty: float) -> str:
    return f"{qty:g}"


def play_link(slug: str, source: str = "shop_link") -> str:
    """The Play Store page with the shop in the install referrer (read by the app in phase 2)."""
    return PLAY_URL + "&referrer=" + quote(f"utm_source={source}&utm_campaign={slug}", safe="")


class ShopLinks:
    def __init__(self, store: PosStore, *,
                 menu: Optional[Callable[[sqlite3.Connection, str], List[Dict[str, Any]]]] = None,
                 upi: Optional[Callable[[str], Optional[Dict[str, Any]]]] = None,
                 clock: Optional[Callable[[], datetime]] = None) -> None:
        """``menu(conn, business_id)`` = the shop's live menu (the front desk's own list); ``upi(owner_user_id)`` =
        {"upi_id", "payee_name", "upi_link"} of the owner's default UPI or None."""
        self.store = store
        self.menu = menu or (lambda conn, business_id: [])
        self.upi = upi or (lambda owner: None)
        self.clock = clock or (lambda: datetime.now(IST))
        with closing(store._connect()) as conn:
            for statement in SCHEMA:
                conn.execute(statement)

    # ------------------------------------------------------------------ helpers
    def _now(self) -> str:
        return self.clock().isoformat(timespec="seconds")

    def _day(self, delta: int = 0) -> str:
        return (self.clock().astimezone(IST) + timedelta(days=delta)).date().isoformat()

    @staticmethod
    def _settings(raw: Any) -> Dict[str, Any]:
        try:
            data = json.loads(raw) if isinstance(raw, str) else dict(raw or {})
        except (TypeError, ValueError):
            data = {}
        return {**DEFAULTS, **{k: v for k, v in data.items() if k in DEFAULTS}}

    def _link_row(self, conn: sqlite3.Connection, business_id: str) -> Optional[sqlite3.Row]:
        return conn.execute("SELECT * FROM shop_links WHERE business_id = ?", (business_id,)).fetchone()

    def _taken(self, conn: sqlite3.Connection, slug: str, business_id: str) -> bool:
        row = conn.execute("SELECT business_id FROM shop_links WHERE slug = ?", (slug,)).fetchone()
        if row and row["business_id"] != business_id:
            return True
        alias = conn.execute("SELECT business_id FROM shop_link_aliases WHERE slug = ?", (slug,)).fetchone()
        return bool(alias and alias["business_id"] != business_id)

    def suggest(self, conn: sqlite3.Connection, business_id: str, name: str, template: str) -> str:
        """A free slug from the shop's English letters; a Telugu-only name -> the shop kind + a short number."""
        base = clean_slug(name)
        if slug_problem(base):
            kind = clean_slug(KIND_LABELS.get(template, ("shop",))[0]) or "shop"
            base = f"{kind}-{secrets.randbelow(9000) + 1000}"
        base = base[:26].strip("-")
        if slug_problem(base) == "reserved":
            base = f"{base}-shop"
        slug, n = base, 2
        while self._taken(conn, slug, business_id):
            slug = f"{base}-{n}"
            n += 1
        return slug

    def _out(self, row: sqlite3.Row) -> Dict[str, Any]:
        return {"slug": row["slug"], "enabled": bool(row["enabled"]), "url": PUBLIC_BASE + row["slug"],
                **self._settings(row["settings"]), "updated_at": row["updated_at"]}

    # ------------------------------------------------------------------ owner side
    def get(self, business_id: str, user: str) -> Dict[str, Any]:
        with closing(self.store._connect()) as conn:
            role = self.store._require(conn, business_id, user, "reports")
            biz = self.store._business_row(conn, business_id)
            row = self._link_row(conn, business_id)
            suggested = row["slug"] if row else self.suggest(conn, business_id, biz["name"], biz["template"])
            stats = self._stats(conn, business_id)
        upi = self.upi(biz["owner_user_id"]) or {}
        return {"link": self._out(row) if row else None, "suggested_slug": suggested, "base": PUBLIC_BASE,
                "my_role": role, "can_change": role == "owner", "has_upi": bool(upi.get("upi_id")),
                "upi_id": upi.get("upi_id", ""), "shop": {"name": biz["name"], "phone": biz["phone"],
                                                          "template": biz["template"], "address": biz["address"]},
                "colors": COLORS, "stats": stats}

    def check_slug(self, business_id: str, user: str, slug: str) -> Dict[str, Any]:
        cleaned = clean_slug(slug)
        with closing(self.store._connect()) as conn:
            self.store._require(conn, business_id, user, "reports")
            problem = slug_problem(cleaned) or ("taken" if self._taken(conn, cleaned, business_id) else "")
        return {"slug": cleaned, "ok": not problem, "problem": problem, "url": PUBLIC_BASE + cleaned}

    def save(self, business_id: str, user: str, body: Dict[str, Any]) -> Dict[str, Any]:
        with self.store._tx() as conn:
            role = self.store._require(conn, business_id, user, "settings")
            if role != "owner":
                raise PosError(403, "owner_only", "Only the shop owner can make or change the shop link.")
            biz = self.store._business_row(conn, business_id)
            row = self._link_row(conn, business_id)
            current = self._settings(row["settings"]) if row else dict(DEFAULTS)
            slug = clean_slug(body.get("slug") or (row["slug"] if row else ""))
            if not slug:
                slug = self.suggest(conn, business_id, biz["name"], biz["template"])
            problem = slug_problem(slug)
            if problem:
                raise PosError(422, f"slug_{problem}", "Link name: 3-30 English letters / numbers / hyphens.")
            if self._taken(conn, slug, business_id):
                raise PosError(409, "slug_taken", "Another shop already has this link name. Try another.")
            settings = dict(current)
            for key in ("show_menu", "show_prices", "show_call", "show_map", "show_pay"):
                if key in body:
                    settings[key] = bool(body[key])
            for key, limit in (("offer", 80), ("about", 120)):
                if key in body:
                    text = re.sub(r"\s+", " ", str(body.get(key) or "")).strip()[:limit]
                    if _WEB_LINK.search(text):
                        raise PosError(422, "no_links", "Web links are not allowed on the shop page.")
                    settings[key] = text
            if "color" in body:
                color = str(body.get("color") or "")
                if color not in COLORS:
                    raise PosError(422, "color", "Choose one of the colours.")
                settings["color"] = color
            if "whatsapp" in body:
                raw = str(body.get("whatsapp") or "").strip()
                number = ten_digits(raw)
                if raw and not number:
                    raise PosError(422, "whatsapp", "WhatsApp number: 10 digits starting with 6-9.")
                settings["whatsapp"] = number
            if not row and not settings["whatsapp"]:
                settings["whatsapp"] = ten_digits(biz["phone"])
            enabled = bool(body.get("enabled", row["enabled"] if row else True))
            now = self._now()
            if row is None:
                conn.execute("INSERT INTO shop_links (business_id, slug, enabled, settings, created_by, created_at, updated_at)"
                             " VALUES (?, ?, ?, ?, ?, ?, ?)",
                             (business_id, slug, 1 if enabled else 0, json.dumps(settings), user, now, now))
            else:
                if row["slug"] != slug:  # the old name keeps working (printed posters)
                    conn.execute("INSERT OR REPLACE INTO shop_link_aliases (slug, business_id, at) VALUES (?, ?, ?)",
                                 (row["slug"], business_id, now))
                    conn.execute("DELETE FROM shop_link_aliases WHERE slug = ?", (slug,))
                conn.execute("UPDATE shop_links SET slug = ?, enabled = ?, settings = ?, updated_at = ? WHERE business_id = ?",
                             (slug, 1 if enabled else 0, json.dumps(settings), now, business_id))
            saved = self._link_row(conn, business_id)
        return {"link": self._out(saved)}

    def _stats(self, conn: sqlite3.Connection, business_id: str) -> Dict[str, Any]:
        today, week, month = self._day(), self._day(-6), self._day(-29)
        out: Dict[str, Dict[str, int]] = {"today": {}, "week": {}, "month": {}}
        for r in conn.execute("SELECT day, kind, n FROM shop_link_counts WHERE business_id = ? AND day >= ?",
                              (business_id, month)):
            for span, since in (("today", today), ("week", week), ("month", month)):
                if r["day"] >= since:
                    out[span][r["kind"]] = out[span].get(r["kind"], 0) + int(r["n"])
        return out

    def stats(self, business_id: str, user: str) -> Dict[str, Any]:
        with closing(self.store._connect()) as conn:
            self.store._require(conn, business_id, user, "reports")
            return self._stats(conn, business_id)

    # ------------------------------------------------------------------ public side
    def resolve(self, slug: str) -> Dict[str, Any]:
        """{"business_id", "slug"} for a live link; {"moved": new} for an old name; {} when unknown."""
        cleaned = clean_slug(slug)
        if not cleaned:
            return {}
        with closing(self.store._connect()) as conn:
            row = conn.execute("SELECT business_id, slug, enabled FROM shop_links WHERE slug = ?", (cleaned,)).fetchone()
            if row is None:
                alias = conn.execute("SELECT l.slug FROM shop_link_aliases a JOIN shop_links l ON l.business_id = a.business_id"
                                     " WHERE a.slug = ?", (cleaned,)).fetchone()
                return {"moved": alias["slug"]} if alias else {}
        if not row["enabled"]:
            return {"off": True}
        return {"business_id": row["business_id"], "slug": row["slug"]}

    def count(self, business_id: str, kind: str) -> None:
        if kind not in COUNT_KINDS:
            return
        try:
            with closing(self.store._connect()) as conn:
                conn.execute("INSERT INTO shop_link_counts (business_id, day, kind, n) VALUES (?, ?, ?, 1)"
                             " ON CONFLICT(business_id, day, kind) DO UPDATE SET n = n + 1", (business_id, self._day(), kind))
        except sqlite3.Error:
            pass  # a count never fails a page

    def public(self, slug: str) -> Optional[Dict[str, Any]]:
        found = self.resolve(slug)
        if not found.get("business_id"):
            return None
        business_id = found["business_id"]
        with closing(self.store._connect()) as conn:
            biz = self.store._business_row(conn, business_id)
            settings = self._settings(self._link_row(conn, business_id)["settings"])
            keys = biz.keys()
            status = (biz["status"] if "status" in keys else "open") or "open"
            items: List[Dict[str, Any]] = []
            if settings["show_menu"]:
                try:
                    items = [i for i in self.menu(conn, business_id) if i.get("name")]
                except Exception:
                    items = []
            rating: Dict[str, Any] = {"average": None, "count": 0}
            try:
                from app.services.pos_ratings import PosRatings

                rating = PosRatings.summary(conn, business_id)
            except Exception:
                pass
            followers = 0
            try:
                followers = int(conn.execute("SELECT COUNT(*) AS n FROM shop_follows WHERE business_id = ?",
                                             (business_id,)).fetchone()["n"])
            except Exception:
                pass
        upi = (self.upi(biz["owner_user_id"]) or {}) if settings["show_pay"] else {}
        kind_en, kind_te = KIND_LABELS.get(biz["template"], KIND_LABELS["general"])
        return {"business_id": business_id, "slug": found["slug"], "url": PUBLIC_BASE + found["slug"],
                "name": biz["name"], "kind_en": kind_en, "kind_te": kind_te, "address": biz["address"] or "",
                "phone": ten_digits(biz["phone"]) if settings["show_call"] else "",
                "whatsapp": settings["whatsapp"], "status": status, "settings": settings,
                "color": COLORS.get(settings["color"], COLORS["green"]), "items": items, "rating": rating,
                "followers": followers, "upi_id": upi.get("upi_id", ""), "upi_link": upi.get("upi_link", ""),
                "can_order": status == "open" and bool(items) and settings["show_menu"],
                "play": play_link(found["slug"]), "join": play_link(found["slug"], "shop_link_join")}

    def order(self, page: Dict[str, Any], quantities: Dict[str, Any], name: str = "", note: str = "") -> Dict[str, Any]:
        """The customer's picks -> lines, a rough total and the WhatsApp message (nothing is saved)."""
        menu = {str(i.get("id")): i for i in page.get("items") or [] if i.get("available", True)}
        lines: List[Dict[str, Any]] = []
        total = 0
        for item_id, raw in list(quantities.items())[:120]:
            item = menu.get(str(item_id))
            if item is None:
                continue
            try:
                qty = float(str(raw).replace(",", ".").strip() or 0)
            except ValueError:
                continue
            weighed = str(item.get("unit") or "") in _WEIGHED
            qty = round(qty * 4) / 4 if weighed else float(int(qty))
            if qty <= 0:
                continue
            qty = min(qty, 50.0)
            amount = int(round(int(item.get("price_paise") or 0) * qty))
            total += amount
            lines.append({"id": item.get("id"), "name": item.get("name"), "qty": qty, "unit": item.get("unit") or "",
                          "amount_paise": amount})
            if len(lines) >= 40:
                break
        name = re.sub(r"\s+", " ", str(name or "")).strip()[:40]
        note = re.sub(r"\s+", " ", str(note or "")).strip()[:160]
        show_prices = bool(page.get("settings", {}).get("show_prices", True))
        text_lines = [f"నమస్తే {page.get('name', '')} 🙏", "ASKODOX లింక్ నుండి ఆర్డర్:"]
        for line in lines:
            unit = f" {line['unit']}" if line["unit"] in _WEIGHED else ""
            price = f" — {_rupees(line['amount_paise'])}" if show_prices else ""
            text_lines.append(f"• {_qty_text(line['qty'])}{unit} × {line['name']}{price}")
        if show_prices and lines:
            text_lines.append(f"మొత్తం సుమారు {_rupees(total)}")
        if name:
            text_lines.append(f"పేరు: {name}")
        if note:
            text_lines.append(f"గమనిక: {note}")
        text_lines.append(page.get("url", ""))
        text = "\n".join(text_lines)
        wa = ""
        if page.get("whatsapp") and lines:
            wa = f"https://wa.me/91{page['whatsapp']}?text={quote(text, safe='')}"
        return {"lines": lines, "total_paise": total, "text": text, "whatsapp_url": wa}
