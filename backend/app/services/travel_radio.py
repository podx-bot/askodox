"""ASKODOX Travel Radio -- a paid ADD-ON (separate from the base Free / Plus /
Pro plan): short, location-aware audio segments while the user travels.

Truth rules (same as the rest of ASKODOX):
- A segment only says what a real source returned: the place name from
  reverse geocoding, nearby places from Google Places, and staff-approved
  LIVE news / content rows. Nothing is invented; with no facts there is no
  segment ("nothing_new"), never filler.
- Audio comes from the ONE Sarvam pipeline (``voice_assistant_service.
  synthesize``); identical text is synthesized once and cached
  (``radio_audio_cache``), so a repeat costs nothing.
- Duplicate prevention: a user never gets the same segment again within
  ``radio.repeat_hours``.
- Metering: every segment records characters synthesized vs served from
  cache and the Places calls it needed (``radio_usage``); a daily minute cap
  (``radio.daily_minutes``) bounds cost per user.

Billing: the add-on plans (``RADIO_PLANS``: 1 / 7 / 30 days, the owner's
PROPOSED ₹29 / ₹149 / ₹399) are stored INACTIVE in ``growth_plans`` with
audience ``addon_radio``. A pass bought for money needs a payment gateway,
which does not exist -- a paid pass stays PENDING_PAYMENT and never grants
access. Only staff may grant a PROMOTIONAL pass (no money moves), and only
while the ``radio.enabled`` flag (default OFF) is on.

Cost model: ``cost_model`` simulates light / medium / heavy listeners from
the bounded settings; every rupee figure is a labelled ESTIMATE from
admin-set unit costs, never a provider bill.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

from app.services import platform_settings

ADDON_AUDIENCE = "addon_radio"
# Owner PROPOSAL (2026-10-12): configurable in Growth -> Plans, INACTIVE.
RADIO_PLANS: List[Dict[str, Any]] = [
    {"code": "radio_1d", "name": "Travel Radio · 1 day", "price": 29, "period_days": 1},
    {"code": "radio_7d", "name": "Travel Radio · 7 days", "price": 149, "period_days": 7},
    {"code": "radio_30d", "name": "Travel Radio · 30 days", "price": 399, "period_days": 30},
]
PASS_STATES = ("ACTIVE", "PENDING_PAYMENT", "CANCELLED", "EXPIRED")

# Listener profiles for the cost simulation: km travelled per day (each new
# area = one place-name lookup + optionally one nearby-places lookup), share
# of areas already in the shared cache because another listener passed
# there, and new news / content segments heard per day.
PROFILES: Dict[str, Dict[str, float]] = {
    "light": {"km_per_day": 15, "shared_cache": 0.2, "news_per_day": 2},
    "medium": {"km_per_day": 60, "shared_cache": 0.3, "news_per_day": 4},
    "heavy": {"km_per_day": 200, "shared_cache": 0.4, "news_per_day": 5},
}

_LINES = {
    "en": {"here": "You are near {place}.", "nearby": "Places close by: {names}.",
           "news": "Update: {title}.", "none": ""},
    "te": {"here": "మీరు ఇప్పుడు {place} దగ్గర ఉన్నారు.", "nearby": "దగ్గరలో ఉన్న ప్రదేశాలు: {names}.",
           "news": "తాజా సమాచారం: {title}.", "none": ""},
    "hi": {"here": "आप अभी {place} के पास हैं।", "nearby": "पास की जगहें: {names}।",
           "news": "ताज़ा जानकारी: {title}।", "none": ""},
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _cell(lat: float, lng: float) -> str:
    """Grid cell of ``radio.cell_km``: facts are fetched once per cell and
    shared by every listener in it (the main cost lever)."""
    import math

    step = max(0.005, platform_settings.get("radio.cell_km") / 111.0)
    return f"{math.floor(lat / step)}:{math.floor(lng / step)}:{step:.3f}"


def setting(key: str) -> float:
    return platform_settings.get(key)


class TravelRadio:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS radio_passes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL, plan_code TEXT NOT NULL, status TEXT NOT NULL,
                    source TEXT NOT NULL, starts_at TEXT, ends_at TEXT,
                    granted_by TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS ix_radio_passes_user ON radio_passes(user_id, status);
                CREATE TABLE IF NOT EXISTS radio_area_cache (
                    cell TEXT PRIMARY KEY, facts_json TEXT NOT NULL, fetched_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS radio_audio_cache (
                    text_hash TEXT PRIMARY KEY, mime TEXT NOT NULL, audio BLOB NOT NULL,
                    chars INTEGER NOT NULL, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS radio_played (
                    user_id TEXT NOT NULL, segment_key TEXT NOT NULL, played_at TEXT NOT NULL,
                    PRIMARY KEY (user_id, segment_key));
                CREATE TABLE IF NOT EXISTS radio_testers (
                    user_id TEXT PRIMARY KEY, added_by TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS radio_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, day TEXT NOT NULL,
                    segment_key TEXT, chars INTEGER NOT NULL DEFAULT 0, synthesized_chars INTEGER NOT NULL DEFAULT 0,
                    places_calls INTEGER NOT NULL DEFAULT 0, seconds REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS ix_radio_usage_user_day ON radio_usage(user_id, day);
                """
            )

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # ------------------------------------------------------------ plans --
    @staticmethod
    def seed_plans(growth: Any) -> None:
        """Store the proposed add-on plans ONCE, INACTIVE (staff edit price /
        days / active in Growth -> Plans; an edit is never overwritten)."""
        for plan in RADIO_PLANS:
            if growth.plan(plan["code"]) is None:
                growth.upsert_plan(plan["code"], name=plan["name"], audience=ADDON_AUDIENCE,
                                   price=plan["price"], period_days=plan["period_days"],
                                   entitlements={"travel_radio": True}, active=False)

    @staticmethod
    def plans(growth: Any) -> List[Dict[str, Any]]:
        return [p for p in growth.plans() if p.get("audience") == ADDON_AUDIENCE]

    # ----------------------------------------------------------- passes --
    def _pass(self, row) -> Dict[str, Any]:
        return dict(row)

    def current_pass(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM radio_passes WHERE user_id=? AND status IN ('ACTIVE','PENDING_PAYMENT')"
                               " ORDER BY id DESC LIMIT 1", (user_id,)).fetchone()
        if not row:
            return None
        item = dict(row)
        if item.get("ends_at") and datetime.fromisoformat(item["ends_at"]) < _now():
            with self._connect() as conn:
                conn.execute("UPDATE radio_passes SET status='EXPIRED', updated_at=? WHERE id=?",
                             (_now().isoformat(), item["id"]))
            return None
        return item

    def request_pass(self, user_id: str, plan: Dict[str, Any]) -> Dict[str, Any]:
        """A customer asks for a paid pass: there is no gateway, so it waits
        for payment and grants NOTHING (never faked ACTIVE)."""
        return self._insert(user_id, plan, status="PENDING_PAYMENT", source="app", ends=None)

    def grant_promotional(self, user_id: str, plan: Dict[str, Any], *, granted_by: str) -> Dict[str, Any]:
        days = int(plan.get("period_days") or 1)
        return self._insert(user_id, plan, status="ACTIVE", source="promotional",
                            ends=_now() + timedelta(days=days), granted_by=granted_by)

    def _insert(self, user_id: str, plan: Dict[str, Any], *, status: str, source: str,
                ends: Optional[datetime], granted_by: str = "") -> Dict[str, Any]:
        now = _now().isoformat()
        with self._connect() as conn:
            if status == "ACTIVE":
                conn.execute("UPDATE radio_passes SET status='CANCELLED', updated_at=? WHERE user_id=? AND "
                             "status='PENDING_PAYMENT'", (now, user_id))
            elif conn.execute("SELECT 1 FROM radio_passes WHERE user_id=? AND status='ACTIVE' AND "
                              "(ends_at IS NULL OR ends_at > ?)", (user_id, now)).fetchone():
                raise ValueError("ALREADY_ACTIVE")
            else:
                conn.execute("UPDATE radio_passes SET status='CANCELLED', updated_at=? WHERE user_id=? AND "
                             "status='PENDING_PAYMENT'", (now, user_id))
            cur = conn.execute(
                "INSERT INTO radio_passes(user_id,plan_code,status,source,starts_at,ends_at,granted_by,created_at,"
                "updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
                (user_id, plan["code"], status, source, now if status == "ACTIVE" else None,
                 ends.isoformat() if ends else None, granted_by or None, now, now))
            return dict(conn.execute("SELECT * FROM radio_passes WHERE id=?", (cur.lastrowid,)).fetchone())

    def activate_paid(self, user_id: str, plan: Dict[str, Any], *, payment_id: str) -> Dict[str, Any]:
        """A gateway-confirmed payment starts the pass now (separate from the
        base plan)."""
        days = int(plan.get("period_days") or 1)
        return self._insert(user_id, plan, status="ACTIVE", source="payment",
                            ends=_now() + timedelta(days=days), granted_by=f"payment:{payment_id}")

    def cancel_pass(self, pass_id: int) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE radio_passes SET status='CANCELLED', updated_at=? WHERE id=?",
                         (_now().isoformat(), int(pass_id)))

    def has_access(self, user_id: str) -> bool:
        current = self.current_pass(user_id)
        return bool(current and current["status"] == "ACTIVE") or self.is_tester(user_id)

    # -------------------------------------------------- internal testing --
    # Staff-chosen internal testers hear Radio while the customer flag stays
    # OFF: no pass, no price, no billing (usage is still metered + capped).
    def is_tester(self, user_id: str) -> bool:
        """Same account however the number was typed at sign-in; never the
        public demo account (see tester_identity)."""
        from app.services import tester_identity

        with self._connect() as conn:
            ids = [r["user_id"] for r in conn.execute("SELECT user_id FROM radio_testers")]
        return tester_identity.matches(ids, user_id)

    def add_tester(self, user_id: str, *, added_by: str, note: str = "") -> Dict[str, Any]:
        with self._connect() as conn:
            conn.execute("INSERT INTO radio_testers(user_id,added_by,note,created_at) VALUES(?,?,?,?) "
                         "ON CONFLICT(user_id) DO UPDATE SET note=excluded.note",
                         (user_id, added_by, note[:200], _now().isoformat()))
        return {"user_id": user_id, "tester": True}

    def remove_tester(self, user_id: str) -> bool:
        from app.services import tester_identity

        with self._connect() as conn:
            ids = tester_identity.same_person(
                [r["user_id"] for r in conn.execute("SELECT user_id FROM radio_testers")], user_id)
            for uid in ids:
                conn.execute("DELETE FROM radio_testers WHERE user_id=?", (uid,))
        return bool(ids)

    def testers(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM radio_testers ORDER BY created_at DESC")]

    def passes(self, limit: int = 200) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM radio_passes ORDER BY id DESC LIMIT ?",
                                                  (int(limit),)).fetchall()]

    # ------------------------------------------------------------ usage --
    def seconds_today(self, user_id: str) -> float:
        with self._connect() as conn:
            row = conn.execute("SELECT COALESCE(SUM(seconds),0) s FROM radio_usage WHERE user_id=? AND day=?",
                               (user_id, _now().date().isoformat())).fetchone()
        return float(row["s"] or 0)

    def usage_summary(self, days: int = 30) -> Dict[str, Any]:
        since = (_now() - timedelta(days=days)).date().isoformat()
        with self._connect() as conn:
            row = conn.execute(
                "SELECT COUNT(*) n, COUNT(DISTINCT user_id) users, COALESCE(SUM(chars),0) chars,"
                " COALESCE(SUM(synthesized_chars),0) synth, COALESCE(SUM(places_calls),0) places,"
                " COALESCE(SUM(seconds),0) secs FROM radio_usage WHERE day>=?", (since,)).fetchone()
        tts_rate = setting("radio.tts_inr_per_10k_chars")
        # Map calls are a place-name + (optional) nearby pair: price both.
        per_call = (setting("radio.geocode_inr_per_call") + setting("radio.places_inr_per_call")
                    * setting("radio.nearby_places")) / (1 + setting("radio.nearby_places"))
        estimate = row["synth"] / 10000 * tts_rate + row["places"] * per_call
        return {"days": days, "segments": row["n"], "listeners": row["users"], "chars": row["chars"],
                "synthesized_chars": row["synth"], "cached_chars": row["chars"] - row["synth"],
                "places_calls": row["places"], "minutes": round(row["secs"] / 60, 1),
                "cost_estimate_inr": round(estimate, 2), "cost_basis": "ESTIMATE"}

    # ---------------------------------------------------------- content --
    def area_facts(self, maps: Any, lat: float, lng: float) -> tuple[Dict[str, Any], int]:
        """Real facts for the cell (cached ``radio.area_cache_hours``).
        Returns (facts, Places/Geocoding calls made)."""
        cell = _cell(lat, lng)
        fresh_after = _now() - timedelta(hours=setting("radio.area_cache_hours"))
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM radio_area_cache WHERE cell=?", (cell,)).fetchone()
        if row and datetime.fromisoformat(row["fetched_at"]) > fresh_after:
            return json.loads(row["facts_json"]), 0
        facts: Dict[str, Any] = {"place": "", "nearby": []}
        calls = 0
        if maps is not None and getattr(maps, "enabled", False):
            try:
                place = maps.reverse_geocode(lat, lng) or {}
                calls += 1
                facts["place"] = str(place.get("area") or place.get("city") or place.get("district") or place.get("label") or "")[:60]
            except Exception:
                pass
            try:
                if setting("radio.nearby_places") < 1:
                    raise LookupError("nearby lookups switched off")
                found = maps.search_places("tourist attractions and landmarks", latitude=lat, longitude=lng,
                                           radius_m=5000, limit=4) or []
                calls += 1
                facts["nearby"] = [str(p.get("name"))[:50] for p in found if p.get("name")][:3]
            except Exception:
                pass
        if facts["place"] or facts["nearby"]:
            with self._connect() as conn:
                conn.execute("INSERT INTO radio_area_cache(cell,facts_json,fetched_at) VALUES(?,?,?) ON CONFLICT(cell)"
                             " DO UPDATE SET facts_json=excluded.facts_json, fetched_at=excluded.fetched_at",
                             (cell, json.dumps(facts), _now().isoformat()))
        return facts, calls

    @staticmethod
    def segments(facts: Dict[str, Any], news: List[Dict[str, Any]], lang: str, cell: str) -> List[Dict[str, Any]]:
        """Candidate segments, each built ONLY from the facts it names."""
        lines = _LINES.get(lang, _LINES["en"])
        out: List[Dict[str, Any]] = []
        if facts.get("place") or facts.get("nearby"):
            parts = []
            if facts.get("place"):
                parts.append(lines["here"].format(place=facts["place"]))
            if facts.get("nearby"):
                parts.append(lines["nearby"].format(names=", ".join(facts["nearby"])))
            out.append({"key": f"area:{cell}:{lang}", "kind": "area", "title": facts.get("place") or "Nearby",
                        "text": " ".join(parts), "sources": ["google_geocoding", "google_places"]})
        for row in news[:5]:
            title = str(row.get("title") or "").strip()[:140]
            if title:
                out.append({"key": f"news:{row.get('id')}:{lang}", "kind": "news", "title": title,
                            "text": lines["news"].format(title=title), "sources": ["askodox_live_content"],
                            "url": row.get("source_url") or row.get("url") or None})
        return out

    def next_segment(self, user_id: str, candidates: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        since = (_now() - timedelta(hours=setting("radio.repeat_hours"))).isoformat()
        with self._connect() as conn:
            played = {r["segment_key"] for r in conn.execute(
                "SELECT segment_key FROM radio_played WHERE user_id=? AND played_at>?", (user_id, since))}
        return next((c for c in candidates if c["key"] not in played), None)

    def audio_for(self, text: str, synthesize: Optional[Callable[..., Dict[str, Any]]],
                  voice: str = "automatic") -> tuple[Optional[bytes], str, int]:
        """(audio, mime, chars synthesized now). Identical text is synthesized
        once; a provider failure returns no audio (the app reads the text)."""
        digest = hashlib.sha256(f"{voice}|{text}".encode()).hexdigest()
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM radio_audio_cache WHERE text_hash=?", (digest,)).fetchone()
        if row:
            return bytes(row["audio"]), row["mime"], 0
        if not callable(synthesize):
            return None, "", 0
        try:
            try:
                result = synthesize(text, voice=voice) or {}
            except TypeError:
                result = synthesize(text) or {}
        except Exception:
            return None, "", 0
        audio = result.get("content")
        if not result.get("success") or not str(result.get("tts_path") or "").startswith("sarvam") or not audio:
            return None, "", 0
        mime = str(result.get("mime_type") or "audio/ogg")
        with self._connect() as conn:
            # Bounded: audio older than the repeat window is never replayed to
            # the same listener, so the shared cache keeps one week at most.
            conn.execute("DELETE FROM radio_audio_cache WHERE created_at < ?",
                         ((_now() - timedelta(days=7)).isoformat(),))
            conn.execute("INSERT OR IGNORE INTO radio_audio_cache(text_hash,mime,audio,chars,created_at)"
                         " VALUES(?,?,?,?,?)", (digest, mime, bytes(audio), len(text), _now().isoformat()))
        return bytes(audio), mime, len(text)

    def record(self, user_id: str, segment: Dict[str, Any], *, synthesized_chars: int, places_calls: int) -> float:
        seconds = len(segment["text"]) / max(1.0, setting("radio.chars_per_minute")) * 60
        now = _now()
        with self._connect() as conn:
            conn.execute("INSERT INTO radio_played(user_id,segment_key,played_at) VALUES(?,?,?) ON CONFLICT"
                         "(user_id,segment_key) DO UPDATE SET played_at=excluded.played_at",
                         (user_id, segment["key"], now.isoformat()))
            conn.execute("INSERT INTO radio_usage(user_id,day,segment_key,chars,synthesized_chars,places_calls,"
                         "seconds,created_at) VALUES(?,?,?,?,?,?,?,?)",
                         (user_id, now.date().isoformat(), segment["key"], len(segment["text"]),
                          int(synthesized_chars), int(places_calls), seconds, now.isoformat()))
        return seconds


def cost_model(plans: List[Dict[str, Any]] | None = None) -> Dict[str, Any]:
    """Light / medium / heavy simulation per listener. Every rupee figure is
    an ESTIMATE from the admin-set unit costs (Command Center settings)."""
    cell_km = setting("radio.cell_km")
    segment_chars = setting("radio.segment_chars")
    chars_per_min = setting("radio.chars_per_minute")
    tts_rate = setting("radio.tts_inr_per_10k_chars")
    geo_rate = setting("radio.geocode_inr_per_call")
    places_rate = setting("radio.places_inr_per_call") if setting("radio.nearby_places") >= 1 else 0.0
    cap = setting("radio.daily_minutes")
    rows = []
    for name, p in PROFILES.items():
        areas = p["km_per_day"] / max(0.1, cell_km)
        fresh = areas * (1 - p["shared_cache"])
        segments = areas + p["news_per_day"]
        chars = min(segments * segment_chars, cap * chars_per_min)
        tts = chars * (1 - p["shared_cache"]) / 10000 * tts_rate
        maps = fresh * (geo_rate + places_rate)
        per_day = tts + maps
        per_plan = []
        for plan in plans or RADIO_PLANS:
            days = int(plan.get("period_days") or 1)
            cost = per_day * days
            price = float(plan.get("price") or 0)
            per_plan.append({"code": plan["code"], "price": price, "days": days,
                             "cost_estimate_inr": round(cost, 2),
                             "margin_estimate_inr": round(price - cost, 2),
                             "covers_cost": price >= cost})
        rows.append({"profile": name, "km_per_day": p["km_per_day"], "areas_per_day": round(areas, 1),
                     "segments_per_day": round(segments, 1), "minutes_per_day": round(chars / chars_per_min, 1),
                     "tts_inr_per_day": round(tts, 2), "maps_inr_per_day": round(maps, 2),
                     "total_inr_per_day": round(per_day, 2), "plans": per_plan})
    return {"basis": "ESTIMATE", "assumptions": {
        "cell_km": cell_km, "segment_chars": segment_chars, "chars_per_minute": chars_per_min,
        "tts_inr_per_10k_chars": tts_rate, "geocode_inr_per_call": geo_rate,
        "places_inr_per_call": places_rate, "daily_minutes_cap": cap, "profiles": PROFILES,
        "note": "Unit costs are admin-set estimates (Command Center -> Platform settings), not provider bills."},
        "profiles": rows}
