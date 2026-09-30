"""Targeted notifications & promotions (Command Center -> Growth).

A campaign is a ``promotion_campaigns`` record (platform_schema) that went
through review (submit -> approve by someone else). This engine:

* builds the audience ONLY from data ASKODOX legitimately holds: the user's
  own profile (roles, address, map point), their own requests (category,
  intent, subject words) and their orders / listings -- no scraping, no
  bought lists;
* respects consent: in-app promotions can be switched off by the customer;
  promotional SMS / WhatsApp / e-mail / push need the customer's explicit
  opt-in (and the channel's own opt-out still wins);
* enforces frequency caps per campaign and a global anti-spam cap per user;
* delivers in-app cards (compact / quarter / half screen -- never full
  screen) and hands other channels to the one Messenger (on staging those
  are NEEDS_CONFIGURATION or MOCK -- nothing real is sent);
* measures sent / delivered / opened / clicked / lead / conversion / revenue
  with the campaign id on every event, and records a paid campaign's fee as
  an EXPECTED ledger entry (no gateway: an admin confirms it).
"""
from __future__ import annotations

import json
import math
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional

PROMO_CHANNELS = ("in_app", "push", "email", "sms", "whatsapp")
EXTERNAL_CHANNELS = ("push", "email", "sms", "whatsapp")
GLOBAL_DAILY_CAP = 3          # promotions per user per day across all campaigns
DEFAULT_CAP_DAY = 1
SIZES = ("compact", "quarter", "half")
ROLES = ("buyers", "sellers", "service_providers", "job_seekers", "delivery_ride")
INTENTS = ("buy", "sell", "hire", "work", "rent", "book", "service", "deliver", "ride")
_PIN = re.compile(r"\b[1-9]\d{5}\b")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(h))


def run_key(campaign: Dict[str, Any], now: datetime | None = None) -> Optional[str]:
    """The current delivery window for the schedule, or None if not due."""
    now = now or _now()
    d = campaign.get("data") or {}
    start, end = _parse(d.get("start_at")), _parse(d.get("end_at"))
    if start and now < start:
        return None
    if end and now > end:
        return None
    schedule = d.get("schedule") or "immediate"
    if schedule in ("immediate", "one_time"):
        return "once"
    if schedule == "hourly":
        return now.strftime("h%Y%m%d%H")
    if schedule == "daily":
        return now.strftime("d%Y%m%d")
    if schedule == "weekly":
        iso = now.isocalendar()
        return f"w{iso[0]}-{iso[1]:02d}"
    if schedule == "monthly":
        return now.strftime("m%Y%m")
    if schedule == "yearly":
        return now.strftime("y%Y")
    if schedule == "custom":
        hours = int(d.get("interval_hours") or 0)
        if hours <= 0:
            return None
        base = start or _parse(campaign.get("created_at")) or now
        return f"c{int((now - base).total_seconds() // (hours * 3600))}"
    return None


class PromotionEngine:
    def __init__(self, db_path: str, repo: Any, *, messenger: Any = None, outbox: Any = None,
                 user_ref: Callable[[str], str] | None = None) -> None:
        self.db_path = db_path
        self.repo = repo              # PlatformRepository (records, events, ledger)
        self.messenger = messenger
        self.outbox = outbox          # channel opt-outs (customer's own switch)
        self.user_ref = user_ref or (lambda u: u)
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS pf_promo_consent (
                    user_ref TEXT NOT NULL, channel TEXT NOT NULL, granted INTEGER NOT NULL, at TEXT NOT NULL,
                    PRIMARY KEY(user_ref, channel)
                );
                CREATE TABLE IF NOT EXISTS pf_promo_deliveries (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, campaign_id TEXT NOT NULL, user_ref TEXT NOT NULL,
                    channel TEXT NOT NULL, run_key TEXT NOT NULL, status TEXT NOT NULL, at TEXT NOT NULL,
                    opened_at TEXT, clicked_at TEXT, dismissed_at TEXT,
                    UNIQUE(campaign_id, user_ref, channel, run_key)
                );
                CREATE INDEX IF NOT EXISTS idx_promo_deliveries_user ON pf_promo_deliveries(user_ref, at);
                """
            )

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _rows(self, sql: str, params: tuple = ()) -> List[Dict[str, Any]]:
        try:
            with self._connect() as conn:
                return [dict(r) for r in conn.execute(sql, params).fetchall()]
        except sqlite3.Error:
            return []  # table not present in this deployment

    # ------------------------------------------------------------- consent --

    def consent(self, user_ref: str) -> Dict[str, bool]:
        rows = {r["channel"]: bool(r["granted"]) for r in
                self._rows("SELECT channel, granted FROM pf_promo_consent WHERE user_ref=?", (user_ref,))}
        # In-app promotions: on unless switched off. Other channels: opt-in.
        return {c: rows.get(c, c == "in_app") for c in PROMO_CHANNELS}

    def set_consent(self, user_ref: str, channel: str, granted: bool) -> None:
        if channel not in PROMO_CHANNELS:
            raise ValueError(f"unknown channel {channel}")
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO pf_promo_consent VALUES (?, ?, ?, ?)",
                         (user_ref, channel, int(bool(granted)), _now().isoformat()))

    def allowed(self, user_ref: str, channel: str) -> bool:
        if not self.consent(user_ref).get(channel):
            return False
        if channel in EXTERNAL_CHANNELS and self.outbox is not None:
            try:
                if self.outbox.opted_out(user_ref, channel):
                    return False
            except Exception:
                return False
        return True

    # ------------------------------------------------------------ audience --

    def people(self) -> Dict[str, Dict[str, Any]]:
        """Per-user facts from ASKODOX's own tables (never external data)."""
        out: Dict[str, Dict[str, Any]] = {}

        def person(uid: Any) -> Optional[Dict[str, Any]]:
            uid = str(uid or "").strip()
            if not uid or uid == "guest":
                return None
            return out.setdefault(uid, {"user_id": uid, "roles": set(), "party": set(), "categories": set(),
                                        "intents": set(), "interests": set(), "texts": [], "points": []})

        for r in self._rows("SELECT user_id, address, latitude, longitude, roles_json, business_category "
                            "FROM user_profiles"):
            p = person(r["user_id"])
            if not p:
                continue
            if r.get("address"):
                p["texts"].append(str(r["address"]))
            if r.get("latitude") is not None and r.get("longitude") is not None:
                p["points"].append((float(r["latitude"]), float(r["longitude"])))
            try:
                for role in json.loads(r.get("roles_json") or "[]"):
                    role = str(role).lower()
                    p["roles"].add({"seller": "sellers", "buyer": "buyers", "provider": "service_providers",
                                    "service_provider": "service_providers", "worker": "job_seekers"}.get(role, role))
            except (TypeError, ValueError):
                pass
            if r.get("business_category"):
                p["categories"].add(str(r["business_category"]).lower())
        for r in self._rows("SELECT user_id, side, domain, subject, location_text, latitude, longitude "
                            "FROM universal_need_offer_records"):
            p = person(r["user_id"])
            if not p:
                continue
            side, domain = str(r.get("side") or "").upper(), str(r.get("domain") or "").lower()
            p["party"].add("party_a" if side == "NEED" else "party_b")
            p["intents"].add("buy" if side == "NEED" else "sell")
            if domain in ("job", "jobs", "work", "workers"):
                p["intents"].add("hire" if side == "NEED" else "work")
                p["roles"].add("job_seekers" if side != "NEED" else "buyers")
            elif domain in ("services", "service"):
                p["intents"].add("service")
                p["roles"].add("buyers" if side == "NEED" else "service_providers")
            else:
                p["roles"].add("buyers" if side == "NEED" else "sellers")
            if domain:
                p["categories"].add(domain)
            for word in re.findall(r"[a-z0-9]{3,}", str(r.get("subject") or "").lower()):
                p["interests"].add(word)
            if r.get("subject"):
                p["categories"].add(str(r["subject"]).lower()[:80])
            if r.get("location_text"):
                p["texts"].append(str(r["location_text"]))
            if r.get("latitude") is not None and r.get("longitude") is not None:
                p["points"].append((float(r["latitude"]), float(r["longitude"])))
        for r in self._rows("SELECT buyer_user_id FROM orders"):
            p = person(r.get("buyer_user_id"))
            if p:
                p["roles"].add("buyers")
                p["party"].add("party_a")
        for r in self._rows("SELECT DISTINCT seller_user_id FROM seller_products"):
            p = person(r.get("seller_user_id"))
            if p:
                p["roles"].add("sellers")
                p["party"].add("party_b")
        return out

    @staticmethod
    def _norm(values: Iterable[Any]) -> List[str]:
        return [str(v).strip().lower() for v in values or [] if str(v).strip()]

    def matches(self, person: Dict[str, Any], d: Dict[str, Any]) -> bool:
        audience = d.get("audience") or "all"
        if audience == "users":
            refs = set(self._norm(d.get("user_refs")))
            if self.user_ref(person["user_id"]).lower() not in refs:
                return False
        elif audience == "roles":
            if not set(self._norm(d.get("roles"))) & person["roles"]:
                return False
        elif audience in ("party_a", "party_b") and audience not in person["party"]:
            return False
        cats = self._norm(d.get("categories"))
        if cats and not any(c in pc or pc in c for c in cats for pc in person["categories"]):
            return False
        intents = self._norm(d.get("intents"))
        if intents and not set(intents) & person["intents"]:
            return False
        interests = self._norm(d.get("interests"))
        if interests and not any(i in person["interests"] or any(i in c for c in person["categories"])
                                 for i in interests):
            return False
        text = " | ".join(person["texts"]).lower()
        for key in ("town", "district", "state"):
            want = str(d.get(key) or "").strip().lower()
            if want and want not in text:
                return False
        pin = str(d.get("pincode") or "").strip()
        if pin and pin not in _PIN.findall(text):
            return False
        country = str(d.get("country") or "").strip().lower()
        if country and country not in ("in", "india") and country not in text:
            return False  # ASKODOX is India-first; other countries must be named in the address
        radius = d.get("radius_km")
        lat, lng = d.get("latitude"), d.get("longitude")
        if radius and lat is not None and lng is not None:
            if not any(haversine_km((float(lat), float(lng)), pt) <= float(radius) for pt in person["points"]):
                return False
        return True

    def audience(self, campaign: Dict[str, Any]) -> List[Dict[str, Any]]:
        d = campaign.get("data") or {}
        blocked = set()
        try:
            blocked = self.repo.blocked_refs("user")
        except Exception:
            pass
        return [p for p in self.people().values()
                if self.matches(p, d) and self.user_ref(p["user_id"]) not in blocked]

    def estimate(self, campaign: Dict[str, Any]) -> Dict[str, Any]:
        d = campaign.get("data") or {}
        people = self.audience(campaign)
        channels = [c for c in (d.get("channels") or ["in_app"]) if c in PROMO_CHANNELS]
        reach = {c: 0 for c in channels}
        no_consent = {c: 0 for c in channels}
        for p in people:
            ref = self.user_ref(p["user_id"])
            for c in channels:
                if self.allowed(ref, c):
                    reach[c] += 1
                else:
                    no_consent[c] += 1
        return {"matched": len(people), "reachable": reach, "excluded_no_consent": no_consent,
                "note": "Audience from ASKODOX profiles, requests, orders and listings only. Promotional "
                        "SMS / WhatsApp / e-mail / push reach only customers who opted in."}

    def preview(self, campaign: Dict[str, Any]) -> Dict[str, Any]:
        d = campaign.get("data") or {}
        return {"card": self._card(campaign, delivery_id=0), "size": d.get("size") or "compact",
                "channels": d.get("channels") or ["in_app"], "schedule": d.get("schedule") or "immediate",
                "due_now": run_key(campaign) is not None}

    # ------------------------------------------------------------ delivery --

    def _sent_count(self, user_ref: str, *, campaign_id: str | None, since: datetime) -> int:
        sql = "SELECT COUNT(*) n FROM pf_promo_deliveries WHERE user_ref=? AND at>=? AND status IN " \
              "('DELIVERED','SENT','MOCK_DELIVERED')"
        params: list = [user_ref, since.isoformat()]
        if campaign_id:
            sql += " AND campaign_id=?"
            params.append(campaign_id)
        rows = self._rows(sql, tuple(params))
        return int(rows[0]["n"]) if rows else 0

    def run(self, campaign: Dict[str, Any], *, now: datetime | None = None, enabled: bool = True) -> Dict[str, Any]:
        """Deliver the current window once (idempotent per user/channel/window)."""
        now = now or _now()
        if campaign.get("status") != "ACTIVE" or campaign.get("archived"):
            return {"ran": False, "reason": "campaign is not active (approve it first)"}
        if not enabled:
            return {"ran": False, "reason": "promotions are switched off (feature flag)"}
        key = run_key(campaign, now)
        if key is None:
            return {"ran": False, "reason": "not due (outside the schedule window)"}
        d = campaign["data"]
        cid = campaign["id"]
        cap_day = int(d.get("cap_per_user_day") or DEFAULT_CAP_DAY)
        cap_week = int(d.get("cap_per_user_week") or 0)
        max_sends = int(d.get("max_sends") or 0)
        total = self._rows("SELECT COUNT(*) n FROM pf_promo_deliveries WHERE campaign_id=?", (cid,))[0]["n"]
        stats: Dict[str, int] = {}
        for person in self.audience(campaign):
            ref = self.user_ref(person["user_id"])
            if self._sent_count(ref, campaign_id=cid, since=now - timedelta(days=1)) >= cap_day or (
                    cap_week and self._sent_count(ref, campaign_id=cid, since=now - timedelta(days=7)) >= cap_week):
                stats["capped"] = stats.get("capped", 0) + 1
                continue
            if self._sent_count(ref, campaign_id=None, since=now - timedelta(days=1)) >= GLOBAL_DAILY_CAP:
                stats["global_cap"] = stats.get("global_cap", 0) + 1
                continue
            for channel in d.get("channels") or ["in_app"]:
                if max_sends and total >= max_sends:
                    stats["max_sends_reached"] = 1
                    break
                if not self.allowed(ref, channel):
                    stats["no_consent"] = stats.get("no_consent", 0) + 1
                    continue
                status = "DELIVERED" if channel == "in_app" else self._external(channel, campaign, person, ref)
                try:
                    with self._connect() as conn:
                        conn.execute("INSERT INTO pf_promo_deliveries(campaign_id,user_ref,channel,run_key,status,at) "
                                     "VALUES(?,?,?,?,?,?)", (cid, ref, channel, key, status, now.isoformat()))
                except sqlite3.IntegrityError:
                    stats["already_sent"] = stats.get("already_sent", 0) + 1
                    continue
                total += 1
                stats[status.lower()] = stats.get(status.lower(), 0) + 1
                self.repo.record_event("notification_delivery", campaign_id=cid, user_ref=ref, source=channel,
                                       detail={"status": status, "run": key})
        if (d.get("pricing") or "free") not in ("free",) and float(d.get("price") or 0) > 0:
            self.repo.ledger_add(idempotency_key=f"promo:{cid}", kind="campaign_revenue",
                                 amount=float(d["price"]), state="EXPECTED", campaign_id=cid,
                                 note=f"{d.get('pricing')} promotion fee ({d.get('advertiser') or 'advertiser'})")
        return {"ran": True, "run_key": key, **stats}

    def _external(self, channel: str, campaign: Dict[str, Any], person: Dict[str, Any], ref: str) -> str:
        if self.messenger is None:
            return "SKIPPED_NO_SENDER"
        d = campaign["data"]
        try:
            result = self.messenger.send(channel, title=d.get("title") or "", body=self._text(d), user_ref=ref,
                                         event="promotion", contact_id=person["user_id"])
            return str(result.get("status") or "FAILED").upper()
        except Exception:
            return "FAILED"

    @staticmethod
    def _text(d: Dict[str, Any]) -> str:
        label = "Sponsored · " if d.get("sponsored") or (d.get("pricing") or "free") != "free" else ""
        return f"{label}{d.get('body') or ''}"[:1000]

    def run_due(self, campaigns: List[Dict[str, Any]], *, enabled: bool = True) -> Dict[str, Any]:
        return {c["id"]: self.run(c, enabled=enabled) for c in campaigns}

    # ---------------------------------------------------------------- feed --

    def _card(self, campaign: Dict[str, Any], *, delivery_id: int) -> Dict[str, Any]:
        d = campaign.get("data") or {}
        paid = bool(d.get("sponsored")) or (d.get("pricing") or "free") != "free"
        size = d.get("size") if d.get("size") in SIZES else "compact"
        return {"delivery_id": delivery_id, "campaign_id": campaign["id"], "title": d.get("title"),
                "body": d.get("body"), "image_url": d.get("image_url"), "size": size,
                "cta_label": d.get("cta_label"), "deep_link": d.get("deep_link"),
                "disclosure": "Sponsored" if paid else None, "advertiser": d.get("advertiser") if paid else None}

    def feed(self, user_ref: str, campaigns: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
        now = _now()
        items = []
        for r in self._rows("SELECT * FROM pf_promo_deliveries WHERE user_ref=? AND channel='in_app' AND "
                            "dismissed_at IS NULL ORDER BY id DESC LIMIT 20", (user_ref,)):
            c = campaigns.get(r["campaign_id"])
            if not c or c.get("status") != "ACTIVE" or c.get("archived"):
                continue
            end = _parse((c.get("data") or {}).get("end_at"))
            if end and now > end:
                continue
            items.append(self._card(c, delivery_id=r["id"]))
        return items[:5]  # a short list, never a wall of ads

    def track(self, delivery_id: int, user_ref: str, action: str) -> bool:
        column = {"open": "opened_at", "click": "clicked_at", "dismiss": "dismissed_at"}.get(action)
        if not column:
            raise ValueError("action must be open, click or dismiss")
        rows = self._rows("SELECT * FROM pf_promo_deliveries WHERE id=? AND user_ref=?", (int(delivery_id), user_ref))
        if not rows:
            return False  # someone else's delivery: nothing recorded, nothing revealed
        row = rows[0]
        with self._connect() as conn:
            conn.execute(f"UPDATE pf_promo_deliveries SET {column}=COALESCE({column}, ?) WHERE id=?",
                         (_now().isoformat(), row["id"]))
        if not row.get(column):
            event = {"open": "notification_open", "click": "campaign_click", "dismiss": "campaign_dismiss"}[action]
            self.repo.record_event(event, campaign_id=row["campaign_id"], user_ref=user_ref, source="in_app",
                                   detail={"delivery": row["id"]})
        return True

    # ------------------------------------------------------------- metrics --

    def metrics(self, campaign_id: str) -> Dict[str, Any]:
        rows = self._rows("SELECT status, channel, opened_at, clicked_at FROM pf_promo_deliveries WHERE campaign_id=?",
                          (campaign_id,))
        by_status: Dict[str, int] = {}
        for r in rows:
            by_status[r["status"]] = by_status.get(r["status"], 0) + 1
        delivered = sum(n for s, n in by_status.items() if s in ("DELIVERED", "SENT", "MOCK_DELIVERED"))
        events = {r["event"]: r["n"] for r in self.repo.event_counts(where={"campaign_id": campaign_id})}
        revenue = sum(float(e["amount"]) for e in self.repo.ledger() if e.get("campaign_id") == campaign_id
                      and e["state"] in ("CONFIRMED", "PAID"))
        expected = sum(float(e["amount"]) for e in self.repo.ledger() if e.get("campaign_id") == campaign_id
                       and e["state"] in ("EXPECTED", "PENDING"))
        return {"sent": len(rows), "delivered": delivered, "by_status": by_status,
                "opened": sum(1 for r in rows if r["opened_at"]), "clicked": sum(1 for r in rows if r["clicked_at"]),
                "leads": int(events.get("lead", 0)), "conversions": int(events.get("conversion", 0)),
                "revenue_confirmed": round(revenue, 2), "revenue_expected": round(expected, 2)}
