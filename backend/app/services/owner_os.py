"""Owner OS engines on top of the generic Command Center resources.

* Priority Notification Credits: referrals earn credits under the ACTIVE
  ``referral_credit_rules`` record (every number is configurable; nothing is
  hard-coded). Own ledger with expiry; balance never goes below zero.
* Greetings: chosen from ``greeting_templates`` by the user's local hour,
  language (any BCP-47 tag) and context, rotated and throttled so the same
  greeting is not repeated.
* Delivery matching: Party B candidates for a delivery request from approved
  ``delivery_partners`` -- independent partners by distance / service /
  availability; external logistics partners only when their integration is
  configured. No provider is hard-wired.
"""
from __future__ import annotations

import math
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional

from app.services import platform_schema as ps


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _live(records: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [r for r in records if ps.is_live(r)]


# ----------------------------------------------------------- credits --
class PriorityCredits:
    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS priority_credits (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    delta INTEGER NOT NULL,
                    reason TEXT NOT NULL,
                    notification_type TEXT NOT NULL DEFAULT '',
                    ref TEXT NOT NULL DEFAULT '',
                    expires_at TEXT,
                    created_at TEXT NOT NULL)""")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_priority_credits_user ON priority_credits(user_id)")
            conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_priority_credits_ref ON priority_credits(ref) "
                         "WHERE ref <> ''")

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
    def active_rule(rules: Iterable[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        live = _live(rules)
        if not live:
            return None
        return max(live, key=lambda r: int((r.get("data") or {}).get("priority") or 0))

    def balance(self, user_id: str, *, now: datetime | None = None) -> int:
        at = (now or _now()).isoformat()
        with self._connect() as conn:
            grants = conn.execute("SELECT COALESCE(SUM(delta),0) FROM priority_credits WHERE user_id=? AND delta>0 "
                                  "AND (expires_at IS NULL OR expires_at > ?)", (user_id, at)).fetchone()[0]
            spent = conn.execute("SELECT COALESCE(SUM(-delta),0) FROM priority_credits WHERE user_id=? AND delta<0",
                                 (user_id,)).fetchone()[0]
        return max(0, int(grants) - int(spent))

    def _earned_since(self, user_id: str, since: datetime) -> int:
        with self._connect() as conn:
            return int(conn.execute("SELECT COALESCE(SUM(delta),0) FROM priority_credits WHERE user_id=? AND delta>0 "
                                    "AND created_at >= ?", (user_id, since.isoformat())).fetchone()[0])

    def history(self, user_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT delta, reason, notification_type, expires_at, created_at FROM priority_credits "
                                "WHERE user_id=? ORDER BY id DESC LIMIT ?", (user_id, limit)).fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    def award_amount(rule: Dict[str, Any], referral_count: int) -> int:
        d = rule.get("data") or {}
        every = max(1, int(d.get("referrals_required") or 1))
        amount = int(d.get("credits_awarded") or 0) if referral_count % every == 0 else 0
        slabs = d.get("bonus_slabs") or {}
        for at, extra in (slabs.items() if isinstance(slabs, dict) else ()):
            try:
                if int(at) == referral_count:
                    amount += max(0, int(extra))
            except (TypeError, ValueError):
                continue
        return amount

    def award_referral(self, user_id: str, *, referral_count: int, rule: Optional[Dict[str, Any]],
                       roles: Iterable[str] = (), ref: str = "", now: datetime | None = None) -> Dict[str, Any]:
        """Credits for the referrer's ``referral_count``-th registered referral.
        Returns {"granted": n, "reason": ...}; idempotent per ``ref``."""
        if rule is None:
            return {"granted": 0, "reason": "no_active_rule"}
        d = rule.get("data") or {}
        eligible = [r for r in d.get("eligible_roles") or [] if r]
        if eligible and "any" not in eligible and not set(eligible) & set(roles):
            return {"granted": 0, "reason": "role_not_eligible"}
        amount = self.award_amount(rule, referral_count)
        now = now or _now()
        day = now.replace(hour=0, minute=0, second=0, microsecond=0)
        if int(d.get("daily_limit") or 0):
            amount = min(amount, max(0, int(d["daily_limit"]) - self._earned_since(user_id, day)))
        if int(d.get("monthly_limit") or 0):
            amount = min(amount, max(0, int(d["monthly_limit"]) - self._earned_since(user_id, day.replace(day=1))))
        if int(d.get("max_balance") or 0):
            amount = min(amount, max(0, int(d["max_balance"]) - self.balance(user_id, now=now)))
        if amount <= 0:
            return {"granted": 0, "reason": "limit_or_not_due"}
        expiry_days = int(d.get("expiry_days") or 0)
        expires = (now + timedelta(days=expiry_days)).isoformat() if expiry_days else None
        try:
            with self._connect() as conn:
                conn.execute("INSERT INTO priority_credits(user_id,delta,reason,ref,expires_at,created_at) "
                             "VALUES(?,?,?,?,?,?)", (user_id, amount, "referral", ref, expires, now.isoformat()))
        except sqlite3.IntegrityError:
            return {"granted": 0, "reason": "already_awarded"}
        return {"granted": amount, "reason": "referral", "expires_at": expires}

    def spend(self, user_id: str, notification_type: str, *, rule: Optional[Dict[str, Any]], ref: str = "",
              now: datetime | None = None) -> Dict[str, Any]:
        """One credit boosts one eligible priority notification."""
        if rule is None:
            return {"ok": False, "reason": "no_active_rule"}
        d = rule.get("data") or {}
        types = d.get("eligible_notification_types") or []
        if types and notification_type not in types:
            return {"ok": False, "reason": "type_not_eligible"}
        now = now or _now()
        limit = int(d.get("spend_daily_limit") or 0)
        if limit:
            day = now.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
            with self._connect() as conn:
                used = conn.execute("SELECT COUNT(*) FROM priority_credits WHERE user_id=? AND delta<0 AND "
                                    "created_at >= ?", (user_id, day)).fetchone()[0]
            if used >= limit:
                return {"ok": False, "reason": "daily_limit"}
        if self.balance(user_id, now=now) < 1:
            return {"ok": False, "reason": "no_credits"}
        try:
            with self._connect() as conn:
                conn.execute("INSERT INTO priority_credits(user_id,delta,reason,notification_type,ref,created_at) "
                             "VALUES(?,?,?,?,?,?)", (user_id, -1, "priority_send", notification_type, ref,
                                                     now.isoformat()))
        except sqlite3.IntegrityError:
            return {"ok": False, "reason": "already_spent"}
        return {"ok": True, "balance": self.balance(user_id, now=now)}


# ---------------------------------------------------------- greetings --
MIN_GAP = timedelta(hours=4)


def greeting_kind(local_hour: int, *, returning: bool = False) -> str:
    if returning:
        return "returning"
    if 5 <= local_hour < 12:
        return "morning"
    if 12 <= local_hour < 17:
        return "afternoon"
    if 17 <= local_hour < 22:
        return "evening"
    return "night"


def _lang_rank(template_lang: str, language: str) -> int:
    t, l = (template_lang or "").strip().lower(), (language or "").strip().lower()
    if not t:
        return 1                     # language-neutral fallback
    if t == l:
        return 3
    if t.split("-")[0] == l.split("-")[0]:
        return 2
    return 0


def pick_greeting(templates: Iterable[Dict[str, Any]], *, kind: str, language: str, name: str = "",
                  avoid: str = "") -> Optional[Dict[str, Any]]:
    """Best-language ACTIVE template of ``kind``; rotates away from ``avoid``."""
    live = _live(templates)
    for k in (kind,):
        pool = [(t, _lang_rank((t.get("data") or {}).get("language", ""), language)) for t in live
                if (t.get("data") or {}).get("kind") == k]
        pool = [(t, r) for t, r in pool if r > 0]
        if not pool:
            continue
        best = max(r for _, r in pool)
        choices = [t for t, r in pool if r == best]
        def render(t: Dict[str, Any]) -> str:
            text = (t["data"].get("text") or "").replace("{name}", name).replace(" !", "!").replace(" ,", ",")
            return " ".join(text.split())

        ordered = sorted(choices, key=lambda t: t["id"])
        chosen = next((t for t in ordered if render(t) != avoid), ordered[0])
        text = render(chosen)
        return {"kind": k, "text": " ".join(text.split()), "language": chosen["data"].get("language") or "",
                "language_matched": best >= 2, "template_id": chosen["id"]}
    return None


class GreetingLog:
    """Last greeting per user -- the anti-repetition memory."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS greeting_log (user_id TEXT PRIMARY KEY, text TEXT, at TEXT)")

    def last(self, user_id: str) -> Optional[Dict[str, Any]]:
        with sqlite3.connect(self.db_path) as conn:
            row = conn.execute("SELECT text, at FROM greeting_log WHERE user_id=?", (user_id,)).fetchone()
        return {"text": row[0], "at": row[1]} if row else None

    def remember(self, user_id: str, text: str, at: datetime) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT INTO greeting_log(user_id,text,at) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE "
                         "SET text=excluded.text, at=excluded.at", (user_id, text, at.isoformat()))


def signoff(templates: Iterable[Dict[str, Any]], *, local_hour: int, language: str, name: str = "",
            last_text: str = "") -> Dict[str, Any]:
    """Closing line when the customer ends the conversation: 'signoff_night'
    late in the day when configured, else 'signoff'. Never throttled (it
    answers the customer) and never counted as a greeting."""
    templates = list(templates)
    kinds = (["signoff_night"] if local_hour % 24 >= 20 or local_hour % 24 < 5 else []) + ["signoff"]
    for kind in kinds:
        chosen = pick_greeting(templates, kind=kind, language=language, name=name, avoid=last_text)
        if chosen is not None:
            return {"greeting": chosen}
    return {"greeting": None, "reason": "no_template"}


def greet(templates: Iterable[Dict[str, Any]], log: Optional[GreetingLog], *, user_id: str, local_hour: int,
          language: str, name: str = "", returning: bool = False, last_text: str = "",
          now: datetime | None = None) -> Dict[str, Any]:
    now = now or _now()
    previous = log.last(user_id) if (log and user_id) else None
    if previous:
        try:
            if now - datetime.fromisoformat(previous["at"]) < MIN_GAP:
                return {"greeting": None, "reason": "recently_greeted"}
        except ValueError:
            pass
    templates = list(templates)
    avoid = last_text or (previous or {}).get("text") or ""
    kind = greeting_kind(local_hour % 24, returning=returning)
    chosen = pick_greeting(templates, kind=kind, language=language, name=name, avoid=avoid)
    if chosen is None and kind == "returning":
        chosen = pick_greeting(templates, kind=greeting_kind(local_hour % 24), language=language, name=name,
                               avoid=avoid)
    if chosen is None:
        return {"greeting": None, "reason": "no_template"}
    if log and user_id:
        log.remember(user_id, chosen["text"], now)
    return {"greeting": chosen}


# ----------------------------------------------------------- delivery --
def _km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (math.sin((p2 - p1) / 2) ** 2
         + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2)
    return 6371.0 * 2 * math.asin(math.sqrt(min(1.0, a)))


def match_delivery(partners: Iterable[Dict[str, Any]], *, service: str, latitude: float | None,
                   longitude: float | None, integration_ready: Callable[[str], bool] = lambda key: False,
                   limit: int = 10) -> Dict[str, Any]:
    """Party B candidates for one delivery request (Party A)."""
    independents: List[Dict[str, Any]] = []
    external: List[Dict[str, Any]] = []
    skipped: Dict[str, int] = {}

    def skip(why: str) -> None:
        skipped[why] = skipped.get(why, 0) + 1

    for p in partners:
        d = p.get("data") or {}
        if p.get("status") != "ACTIVE" or p.get("archived"):
            skip("not_approved")
            continue
        if service not in (d.get("services") or []):
            skip("service")
            continue
        if d.get("kind") == "external":
            key = d.get("integration_key") or ""
            (external if key and integration_ready(key) else []).append(
                {"id": p["id"], "name": p["name"], "integration_key": key})
            if not (key and integration_ready(key)):
                skip("integration_not_configured")
            continue
        if not d.get("available"):
            skip("unavailable")
            continue
        if latitude is None or longitude is None or d.get("latitude") is None or d.get("longitude") is None:
            skip("no_location")
            continue
        dist = _km(latitude, longitude, float(d["latitude"]), float(d["longitude"]))
        if dist > float(d.get("radius_km") or 5):
            skip("out_of_range")
            continue
        independents.append({"id": p["id"], "name": p["name"], "distance_km": round(dist, 2),
                             "vehicle": d.get("vehicle") or "", "verified": bool(d.get("verified"))})
    independents.sort(key=lambda c: (not c["verified"], c["distance_km"]))
    return {"service": service, "independent": independents[:limit], "external": external, "skipped": skipped}


# ------------------------------------------------- staging defaults --
OPEN_FINDINGS = (
    ("Camera / attachment flow incomplete", "attachments"),
    ("Multi-photo selection missing", "attachments"),
    ("Photo understanding unreliable", "attachments"),
    ("Video understanding unreliable / not demonstrated", "attachments"),
    ("Current location wrong / not detected", "location"),
    ("Female voice preference not respected", "voice"),
    ("Unrelated referral / join prompts", "growth"),
    ("Self-healing relevance recovery problem", "selfheal"),
    ("Universal Master Profile missing / incomplete", "profile"),
    ("Screen Guide incomplete / not fully phone-verified", "companion"),
    ("Delivery / driver / order / map end-to-end flow not phone-tested", "delivery"),
    ("Greetings not working", "conversation"),
    ("Location-based notifications not phone-tested", "notifications"),
    ("Referral Priority Notification Credits not phone-tested", "growth"),
)

# Results the OWNER reported from real phones (evidence = that report).
PHONE_EVIDENCE = (
    ("Male voice preference plays a male voice", "voice", "1274", "Male selected -> male voice.", "PHONE VERIFIED"),
    ("Female voice preference plays a female voice", "voice", "1274", "Female selected -> female voice.",
     "PHONE VERIFIED"),
    ("Female voice preference persists after app restart", "voice", "1274",
     "Closed and reopened the app; female voice kept.", "PHONE VERIFIED"),
    ("Conversation history persists after app restart", "conversation", "1274",
     "Closed and reopened the app; chat history kept.", "PHONE VERIFIED"),
    ("Orders page blank / white-on-white", "ui", "1274", "Orders screen looked blank (faint text).", "OPEN"),
    ("Repeated generic follow-up after every reply", "conversation", "1274",
     "\"Anything else? Just ask\" appeared after every reply.", "OPEN"),
)

STAGING_GREETINGS = (
    ("morning", "en", "Good morning{name_sep}! What can I find for you today?"),
    ("afternoon", "en", "Good afternoon{name_sep}! What do you need?"),
    ("evening", "en", "Good evening{name_sep}! How can I help?"),
    ("night", "en", "Hello{name_sep}! Still up? Tell me what you need."),
    ("returning", "en", "Welcome back{name_sep}! Shall we continue?"),
    ("morning", "", "Hello{name_sep}!"),
    ("afternoon", "", "Hello{name_sep}!"),
    ("evening", "", "Hello{name_sep}!"),
    ("night", "", "Hello{name_sep}!"),
    ("signoff", "en", "Thank you{name_sep}! Come back any time."),
    ("signoff_night", "en", "Good night{name_sep}! Talk to you soon."),
    ("signoff", "", "Thank you{name_sep}!"),
    ("morning", "te", "శుభోదయం{name_sep}! ఈ రోజు మీకు ఏం కావాలి?"),
    ("afternoon", "te", "నమస్కారం{name_sep}! ఏం కావాలో చెప్పండి."),
    ("evening", "te", "శుభ సాయంత్రం{name_sep}! ఎలా సహాయం చేయగలను?"),
    ("night", "te", "నమస్తే{name_sep}! ఏం కావాలో చెప్పండి."),
    ("returning", "te", "మళ్లీ స్వాగతం{name_sep}! కొనసాగిద్దామా?"),
    ("signoff", "te", "ధన్యవాదాలు{name_sep}! ఎప్పుడైనా మళ్లీ రండి."),
    ("signoff_night", "te", "శుభరాత్రి{name_sep}! మళ్లీ కలుద్దాం."),
    ("morning", "hi", "सुप्रभात{name_sep}! आज आपको क्या चाहिए?"),
    ("afternoon", "hi", "नमस्ते{name_sep}! बताइए, क्या चाहिए?"),
    ("evening", "hi", "शुभ संध्या{name_sep}! मैं कैसे मदद करूँ?"),
    ("night", "hi", "नमस्ते{name_sep}! बताइए, क्या चाहिए?"),
    ("returning", "hi", "फिर से स्वागत है{name_sep}! आगे बढ़ें?"),
    ("signoff", "hi", "धन्यवाद{name_sep}! फिर आइए।"),
    ("signoff_night", "hi", "शुभ रात्रि{name_sep}! फिर मिलेंगे।"),
)

STAGING_EMAIL_ROLES = (
    ("support", "forwarding", True, True), ("admin", "forwarding", True, False),
    ("partners", "forwarding", True, False), ("notifications", "send_only", False, True),
    ("no_reply", "send_only", False, True), ("security", "forwarding", True, False),
)


def seed_staging_defaults(resources: Any, *, actor: str, domain: str = "askodox.com") -> Dict[str, int]:
    """Idempotent test data for STAGING only (caller refuses production)."""
    created: Dict[str, int] = {}

    def empty(name: str) -> bool:
        return not resources.repo.list(name, include_archived=True)

    def add(name: str, data: Dict[str, Any], status: Optional[str] = None) -> None:
        resources.create(name, data, actor=actor, status=status)
        created[name] = created.get(name, 0) + 1

    if empty("qa_checks"):
        for title, area in OPEN_FINDINGS:
            add("qa_checks", {"title": title, "area": area, "build": "1273",
                              "result": "Open finding from the owner's phone test."})
    titles = {r["name"] for r in resources.repo.list("qa_checks", include_archived=True)}
    for title, area, build, result, status in PHONE_EVIDENCE:
        if title not in titles:
            add("qa_checks", {"title": title, "area": area, "build": build, "result": result,
                              "evidence": "Reported by the owner from a real-phone test of build " + build + "."},
                status=status)
    if empty("referral_credit_rules"):
        add("referral_credit_rules", {
            "name": "Staging test rule", "priority": 1, "referrals_required": 1, "credits_awarded": 2,
            "bonus_slabs": {"5": 5, "10": 10},
            "expiry_days": 90, "max_balance": 100, "eligible_roles": ["any"],
            "eligible_notification_types": ["nearby_request", "opportunity", "offer", "lead"],
            "daily_limit": 20, "monthly_limit": 200, "spend_daily_limit": 5}, status="ACTIVE")
    # Greeting kinds/languages added in later rounds are filled in without
    # touching texts the Owner already edited.
    have = {((r.get("data") or {}).get("kind"), (r.get("data") or {}).get("language") or "")
            for r in resources.repo.list("greeting_templates", include_archived=True)}
    for kind, lang, text in STAGING_GREETINGS:
        if (kind, lang) not in have:
            add("greeting_templates", {"kind": kind, "language": lang, "text": text.replace("{name_sep}", " {name}")})
    if empty("email_roles"):
        for role, mode, inbound, outbound in STAGING_EMAIL_ROLES:
            add("email_roles", {"role": role, "address": f"{role.replace('_', '-')}@{domain}", "mode": mode,
                                "needs_inbound": inbound, "needs_outbound": outbound,
                                "notes": "Staging placeholder -- not verified. Configure forwarding / DNS, then "
                                         "record the verification date."})
    return created
