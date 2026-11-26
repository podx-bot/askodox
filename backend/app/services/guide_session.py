"""The guide session: a helper that gets to know a new person, one adaptive question at a time (owner 2026-11-26).

* The questions are NOT a fixed script. ``turn`` gives the model the topic list, what is done and what the person just
  said; it returns what it understood and the next question (or a simpler / fuller explanation when the person did not
  understand or asked "why"). With no model a plain fallback question per topic is used. The topics (``TOPICS``) are
  the fixed part: what must be covered. Their order and depth follow the person and the time they have.
* Time: ``start(minutes)`` picks the topics that matter most for that time (``plan``). A short time is never refused:
  ``pause`` says what is done and what is left, and the rest is offered later (``reminders``).
* Data: nothing about the person is kept unless ``consent`` is true (``set_consent``). Kept facts are masked
  (``pii_mask``), never include ID / card / account numbers / OTPs, can be listed and deleted (one topic or all), and are
  deleted with the account.
* Feature gaps: a thing the person needs that the app does not have is sent only with their consent, without any name
  (``FeatureRequests``). Staff approve / build / decline; people who asked to be told are told when it is ready.
"""
from __future__ import annotations

import json
import re
import sqlite3
import time
from contextlib import closing
from typing import Any, Callable, Dict, List, Optional

from app.services.pii_mask import mask_sensitive

# (key, English, Telugu). The order is the default order; ``plan`` trims it by the person's time.
TOPICS: List[tuple] = [
    ("who", "About you", "మీ గురించి"),
    ("work", "Your work", "మీ పని"),
    ("wants", "What you need from the app", "యాప్ లో మీకు కావాల్సినవి"),
    ("pages", "Arranging your pages", "మీ పేజీల అమరిక"),
    ("team", "Your team", "మీ టీమ్"),
    ("routine", "Your day", "మీ రోజు"),
    ("things", "Vehicles and things you own", "మీ వాహనాలు, వస్తువులు"),
    ("menu", "Items and prices", "వస్తువులు, ధరలు"),
    ("photos", "Photos, videos and links", "ఫోటోలు, వీడియోలు, లింకులు"),
    ("money", "Earnings, loans and assets (only if you wish)", "ఆదాయం, అప్పులు, ఆస్తులు (మీకు ఇష్టమైతే)"),
]
TOPIC_KEYS = [t[0] for t in TOPICS]
OPTIONAL_TOPICS = {"money"}
# What matters most when time is short: ten minutes get the first group, half an hour the first two ...
SHORT = ["who", "work", "wants", "pages"]
MEDIUM = SHORT + ["team", "routine", "menu"]

FALLBACK = {
    "who": {"en": "What is your name, and what do you like to be called?", "te": "మీ పేరు ఏమిటి? మిమ్మల్ని ఎలా పిలవాలి?"},
    "work": {"en": "What work do you do?", "te": "మీరు ఏం పని చేస్తారు?"},
    "wants": {"en": "What would you like this app to do for you first?", "te": "ఈ యాప్ మీకోసం ముందు ఏం చేయాలని మీరు కోరుకుంటున్నారు?"},
    "pages": {"en": "Which things do you use most, so I can put those pages first?", "te": "మీరు ఎక్కువగా వాడేవి ఏవి? ఆ పేజీలను ముందు పెడతాను."},
    "team": {"en": "Does anyone help you with your work?", "te": "మీ పనిలో ఎవరైనా సహాయం చేస్తారా?"},
    "routine": {"en": "How does your day go: morning, afternoon, evening?", "te": "మీ రోజు ఎలా గడుస్తుంది: పొద్దున, మధ్యాహ్నం, సాయంత్రం?"},
    "things": {"en": "Which vehicles or things do you have: bike, car, phone, fridge?", "te": "మీకు ఏఏ వాహనాలు, వస్తువులు ఉన్నాయి: బైక్, కారు, ఫోన్, ఫ్రిడ్జ్?"},
    "menu": {"en": "What do you sell or offer? Tell me the prices yourself, I will not guess them.", "te": "మీరు ఏం అమ్ముతారు, ఏం ఇస్తారు? ధరలు మీరే చెప్పండి, నేను ఊహించను."},
    "photos": {"en": "Do you have photos, videos or a Facebook page link of your work?", "te": "మీ పనికి సంబంధించిన ఫోటోలు, వీడియోలు, ఫేస్‌బుక్ పేజీ లింక్ ఉన్నాయా?"},
    "money": {"en": "If you wish, tell me about loans, earnings or assets so my advice fits you.", "te": "మీకు ఇష్టమైతే, అప్పులు, ఆదాయం, ఆస్తుల గురించి చెప్పండి. అప్పుడు సలహా మీకు సరిపోతుంది."},
}
# Features a person may not have tried; the reminder names one only when it fits what they said (``wants`` / ``work`` facts).
FEATURE_HINTS: List[Dict[str, Any]] = [
    {"key": "dues_reminder", "route": "/me/dues", "en": "Reminders for money people owe you", "te": "మీకు రావాల్సిన బాకీల రిమైండర్", "words": ["baaki", "due", "credit", "bakaya", "బాకీ", "అప్పు"]},
    {"key": "shop_link", "route": "/me/business", "en": "Your free shop page with a link to share", "te": "షేర్ చేయడానికి మీ షాప్ పేజీ లింక్", "words": ["link", "share", "facebook", "lింక్", "లింక్", "షేర్"]},
    {"key": "day_report", "route": "/me/business", "en": "Your day's report", "te": "రోజు రిపోర్ట్", "words": ["report", "sales", "లెక్క", "రిపోర్ట్"]},
    {"key": "family_list", "route": "/me/family-list", "en": "A shopping list shared with your family", "te": "ఇంటి వాళ్లతో షేర్ చేసే సరుకుల లిస్ట్", "words": ["family", "home", "grocery", "ఇల్లు", "సరుకు"]},
]
_URL = re.compile(r"https?://\S+|www\.\S+", re.I)
_LONG_NUMBER = re.compile(r"\b\d{10,16}\b")
_SECRET_ASK = re.compile(r"otp|pin\b|cvv|password|aadhaar|aadhar|pan\s*(no|number|card)|card\s*number|account\s*number", re.I)


class GuideError(Exception):
    def __init__(self, code: str, message: str = "", status: int = 400) -> None:
        super().__init__(code)
        self.code, self.message, self.status = code, message or code, status


def plan(minutes: int) -> List[str]:
    """The topics worth doing in this many minutes, most important first. Never empty: any time is accepted."""
    if minutes <= 12:
        order = list(SHORT)
    elif minutes <= 35:
        order = list(MEDIUM)
    else:
        order = list(TOPIC_KEYS)
    return order


def _now() -> float:
    return time.time()


def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""CREATE TABLE IF NOT EXISTS guide_sessions (
        user_id TEXT PRIMARY KEY, consent INTEGER NOT NULL DEFAULT 0, consent_at REAL, minutes INTEGER NOT NULL DEFAULT 10,
        plan_json TEXT NOT NULL DEFAULT '[]', done_json TEXT NOT NULL DEFAULT '[]', skipped_json TEXT NOT NULL DEFAULT '[]',
        current TEXT, status TEXT NOT NULL DEFAULT 'new', started_at REAL, updated_at REAL NOT NULL)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS guide_facts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, topic TEXT NOT NULL, fact_key TEXT NOT NULL,
        value TEXT NOT NULL, at REAL NOT NULL, UNIQUE(user_id, topic, fact_key))""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_guide_facts_user ON guide_facts(user_id)")
    conn.execute("""CREATE TABLE IF NOT EXISTS guide_reminder_dismissals (
        user_id TEXT NOT NULL, ref TEXT NOT NULL, forever INTEGER NOT NULL DEFAULT 0, at REAL NOT NULL,
        PRIMARY KEY (user_id, ref))""")
    conn.execute("""CREATE TABLE IF NOT EXISTS guide_feature_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT, canonical TEXT NOT NULL UNIQUE, text TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'new', note TEXT, push_similar INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL, updated_at REAL NOT NULL)""")
    # Only "tell me when it is ready" people are kept here, apart from the request text, so staff never see who asked.
    conn.execute("""CREATE TABLE IF NOT EXISTS guide_feature_waiters (
        request_id INTEGER NOT NULL, user_id TEXT NOT NULL, at REAL NOT NULL, told_at REAL,
        PRIMARY KEY (request_id, user_id))""")
    return conn


def _canonical(text: str) -> str:
    words = re.sub(r"[^\wऀ-෿ ]+", " ", (text or "").lower()).split()
    return " ".join(words)[:160]


def _safe_text(value: Any, limit: int) -> str:
    text = mask_sensitive(str(value or ""))
    text = _URL.sub("", text)
    text = _LONG_NUMBER.sub("", text)
    return re.sub(r"\s+", " ", text).strip()[:limit]


def _lang(language: Optional[str]) -> str:
    code = (language or "en").strip().lower()[:2]
    return code if code in ("te", "en", "hi") else "en"


class GuideSessions:
    def __init__(self, db_path: str, *, write_text: Optional[Callable[[str], str]] = None) -> None:
        self.db_path = db_path
        self.write_text = write_text
        with closing(_connect(db_path)):
            pass

    # ------------------------------------------------------------------ state --
    def _row(self, conn: sqlite3.Connection, user: str) -> Optional[sqlite3.Row]:
        return conn.execute("SELECT * FROM guide_sessions WHERE user_id=?", (user,)).fetchone()

    def status(self, user: str, lang: Optional[str] = None) -> Dict[str, Any]:
        out = self._status(user)
        cur = out.get("current")
        if lang is not None and cur in FALLBACK:
            code = _lang(lang)
            out["question"] = FALLBACK[cur][code if code in ("te", "en") else "en"]
        return out

    def _status(self, user: str) -> Dict[str, Any]:
        with closing(_connect(self.db_path)) as conn:
            row = self._row(conn, user)
            facts = conn.execute("SELECT COUNT(*) FROM guide_facts WHERE user_id=?", (user,)).fetchone()[0]
        if row is None:
            return {"status": "new", "consent": False, "minutes": 0, "plan": [], "done": [], "remaining": [], "facts": 0,
                    "topics": [self._topic(k) for k in TOPIC_KEYS]}
        plan_keys = json.loads(row["plan_json"] or "[]")
        done = json.loads(row["done_json"] or "[]")
        skipped = json.loads(row["skipped_json"] or "[]")
        remaining = [k for k in TOPIC_KEYS if k not in done and k not in skipped]
        return {"status": row["status"], "consent": bool(row["consent"]), "minutes": row["minutes"], "plan": plan_keys,
                "done": done, "skipped": skipped, "remaining": remaining, "current": row["current"], "facts": facts,
                "topics": [self._topic(k) for k in TOPIC_KEYS]}

    @staticmethod
    def _topic(key: str) -> Dict[str, str]:
        for k, en, te in TOPICS:
            if k == key:
                return {"key": k, "en": en, "te": te, "optional": k in OPTIONAL_TOPICS}
        return {"key": key, "en": key, "te": key, "optional": False}

    def start(self, user: str, minutes: int) -> Dict[str, Any]:
        minutes = max(1, min(int(minutes or 10), 240))
        keys = plan(minutes)
        now = _now()
        with closing(_connect(self.db_path)) as conn, conn:
            row = self._row(conn, user)
            done = json.loads(row["done_json"]) if row else []
            order = [k for k in keys if k not in done] or [k for k in TOPIC_KEYS if k not in done]
            first = order[0] if order else None
            conn.execute(
                """INSERT INTO guide_sessions (user_id, consent, minutes, plan_json, done_json, skipped_json, current, status, started_at, updated_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(user_id) DO UPDATE SET minutes=excluded.minutes, plan_json=excluded.plan_json, current=excluded.current,
                       status='running', updated_at=excluded.updated_at, started_at=COALESCE(guide_sessions.started_at, excluded.started_at)""",
                (user, int(row["consent"]) if row else 0, minutes, json.dumps(order), json.dumps(done), "[]", first, "running", now, now))
        return self.status(user)

    def set_consent(self, user: str, consent: bool) -> Dict[str, Any]:
        now = _now()
        with closing(_connect(self.db_path)) as conn, conn:
            conn.execute(
                """INSERT INTO guide_sessions (user_id, consent, consent_at, status, updated_at) VALUES (?,?,?,?,?)
                   ON CONFLICT(user_id) DO UPDATE SET consent=excluded.consent, consent_at=excluded.consent_at, updated_at=excluded.updated_at""",
                (user, 1 if consent else 0, now if consent else None, "new", now))
            if not consent:  # taking the permission back takes the kept details back too
                conn.execute("DELETE FROM guide_facts WHERE user_id=?", (user,))
        return self._status(user)

    # ------------------------------------------------------------------- turn --
    def turn(self, user: str, answer: str, language: str = "te", *, asked_why: bool = False, not_understood: bool = False,
             skip: bool = False) -> Dict[str, Any]:
        st = self.status(user)
        if st["status"] == "new":
            raise GuideError("not_started", "start the session first", 409)
        lang = _lang(language)
        topic = st.get("current") or (st["remaining"][0] if st["remaining"] else None)
        if topic is None:
            return self._finished(user, lang)
        said = _safe_text(answer, 600)
        if skip or (not said and not not_understood and not asked_why):
            self._mark(user, topic, skipped=True)
            return self._next(user, lang, understood=False, facts=[], topic_done=topic, explanation="")
        if _SECRET_ASK.search(said) and re.search(r"\d{4,}", said):
            said = ""  # a secret typed by mistake is never kept or sent to the model
        ahead = [k for k in st["plan"] if k in st["remaining"] and k != topic]
        result = self._ask_model(st, topic, said, lang, asked_why=asked_why, not_understood=not_understood,
                                 next_topic=ahead[0] if ahead else None)
        facts = result["facts"] if st["consent"] else []
        if facts:
            self._save_facts(user, topic, facts)
        if result["understood"] and not asked_why and not not_understood:
            self._mark(user, topic, skipped=False)
            return self._next(user, lang, understood=True, facts=facts, topic_done=topic, explanation="", question=result["question"])
        return {"understood": False, "topic": topic, "question": result["question"], "explanation": result["explanation"],
                "facts": facts, "done": st["done"], "remaining": st["remaining"], "status": st["status"], "finished": False}

    def _next(self, user: str, lang: str, *, understood: bool, facts: List[Dict[str, str]], topic_done: str, explanation: str,
              question: str = "") -> Dict[str, Any]:
        st = self.status(user)
        order = [k for k in st["plan"] if k in st["remaining"]]
        if not order:
            return self._finished(user, lang, facts=facts)
        nxt = order[0]
        with closing(_connect(self.db_path)) as conn, conn:
            conn.execute("UPDATE guide_sessions SET current=?, updated_at=? WHERE user_id=?", (nxt, _now(), user))
        text = question or FALLBACK[nxt][lang if lang in ("te", "en") else "en"]
        return {"understood": understood, "topic": nxt, "question": text, "explanation": explanation, "facts": facts,
                "done": st["done"], "remaining": st["remaining"], "status": "running", "finished": False}

    def _finished(self, user: str, lang: str, facts: Optional[List[Dict[str, str]]] = None) -> Dict[str, Any]:
        with closing(_connect(self.db_path)) as conn, conn:
            conn.execute("UPDATE guide_sessions SET status='finished', current=NULL, updated_at=? WHERE user_id=?", (_now(), user))
        st = self.status(user)
        return {"understood": True, "topic": None, "question": "", "explanation": "", "facts": facts or [], "done": st["done"],
                "remaining": st["remaining"], "status": "finished", "finished": True}

    def _mark(self, user: str, topic: str, *, skipped: bool) -> None:
        with closing(_connect(self.db_path)) as conn, conn:
            row = self._row(conn, user)
            if row is None:
                return
            key = "skipped_json" if skipped else "done_json"
            items = json.loads(row[key] or "[]")
            if topic not in items:
                items.append(topic)
            conn.execute(f"UPDATE guide_sessions SET {key}=?, updated_at=? WHERE user_id=?", (json.dumps(items), _now(), user))

    def pause(self, user: str) -> Dict[str, Any]:
        """Time is up: what is done, what is left, and that the rest can wait. Never an error."""
        with closing(_connect(self.db_path)) as conn, conn:
            conn.execute("UPDATE guide_sessions SET status='paused', updated_at=? WHERE user_id=? AND status!='finished'", (_now(), user))
        st = self.status(user)
        return {"status": st["status"], "done": [self._topic(k) for k in st["done"]], "remaining": [self._topic(k) for k in st["remaining"]]}

    # ------------------------------------------------------------------ model --
    def _ask_model(self, st: Dict[str, Any], topic: str, said: str, lang: str, *, asked_why: bool, not_understood: bool,
                   next_topic: Optional[str] = None) -> Dict[str, Any]:
        understood_now = bool(said) and not asked_why and not not_understood
        target = next_topic if (understood_now and next_topic) else topic
        fallback_q = FALLBACK[target][lang if lang in ("te", "en") else "en"]
        base = {"understood": bool(said) and not asked_why and not not_understood, "facts": [], "question": fallback_q, "explanation": ""}
        if self.write_text is None:
            return base
        label = {"te": "Telugu", "en": "English", "hi": "Hindi"}[lang]
        prompt = (
            "You are a warm, patient woman helper getting a new person ready to use a shopping / small-business app. "
            f"Write in {label}, short and simple, like talking to a neighbour. Return ONLY JSON: "
            '{"understood": true|false, "facts": [{"key": "short_snake_case", "value": "what the person said"}], '
            '"question": "ONE next question", "explanation": "plain explanation or empty"}.\n'
            f"Topics to cover (never reorder what is done): {', '.join(TOPIC_KEYS)}. Done: {', '.join(st['done']) or 'none'}. "
            f"Current topic: {topic}. Topic of the NEXT question if the person was understood: {next_topic or 'none'}. "
            f"Minutes the person has: {st['minutes']}.\n"
            f"The person said: {said or '(nothing)'}\n"
            f"They asked why we ask: {asked_why}. They did not understand: {not_understood}.\n"
            "Rules: facts only from the person's own words, never guessed. Never invent prices; ask the person to say them. "
            "Never ask for OTP, PIN, password, card, account, Aadhaar or PAN numbers. Debts, loans, assets and earnings only if "
            "the person chose to speak about them. If they did not understand or asked why, put a simpler explanation in "
            "'explanation' (what the app does with this answer and that they can delete it any time) and repeat the question in "
            "different words (same topic). If the person was understood, 'question' is for the NEXT topic and follows from what they said. "
            "No links, no phone numbers."
        )
        try:
            raw = self.write_text(prompt) or ""
            match = re.search(r"\{.*\}", raw, re.S)
            data = json.loads(match.group(0)) if match else {}
        except Exception:
            return base
        facts: List[Dict[str, str]] = []
        for item in (data.get("facts") or [])[:8]:
            if not isinstance(item, dict):
                continue
            key = re.sub(r"[^a-z0-9_]", "", str(item.get("key") or "").lower())[:40]
            value = _safe_text(item.get("value"), 200)
            if key and value:
                facts.append({"key": key, "value": value})
        question = _safe_text(data.get("question"), 300) or fallback_q
        return {"understood": bool(data.get("understood", base["understood"])) and bool(said),
                "facts": facts, "question": question, "explanation": _safe_text(data.get("explanation"), 500)}

    # ------------------------------------------------------------------ facts --
    def _save_facts(self, user: str, topic: str, facts: List[Dict[str, str]]) -> None:
        now = _now()
        with closing(_connect(self.db_path)) as conn, conn:
            for f in facts:
                conn.execute(
                    """INSERT INTO guide_facts (user_id, topic, fact_key, value, at) VALUES (?,?,?,?,?)
                       ON CONFLICT(user_id, topic, fact_key) DO UPDATE SET value=excluded.value, at=excluded.at""",
                    (user, topic, f["key"], f["value"], now))

    def facts(self, user: str) -> List[Dict[str, Any]]:
        with closing(_connect(self.db_path)) as conn:
            rows = conn.execute("SELECT topic, fact_key, value, at FROM guide_facts WHERE user_id=? ORDER BY topic, id", (user,)).fetchall()
        return [{"topic": r["topic"], "key": r["fact_key"], "value": r["value"], "at": r["at"]} for r in rows]

    def delete_facts(self, user: str, topic: Optional[str] = None) -> int:
        with closing(_connect(self.db_path)) as conn, conn:
            if topic:
                cur = conn.execute("DELETE FROM guide_facts WHERE user_id=? AND topic=?", (user, topic))
            else:
                cur = conn.execute("DELETE FROM guide_facts WHERE user_id=?", (user,))
        return cur.rowcount

    def delete_all(self, user: str) -> None:
        """Account deletion and "delete my data": facts, session, dismissals, waiting-for-feature rows."""
        with closing(_connect(self.db_path)) as conn, conn:
            for table in ("guide_facts", "guide_sessions", "guide_reminder_dismissals", "guide_feature_waiters"):
                conn.execute(f"DELETE FROM {table} WHERE user_id=?", (user,))

    # -------------------------------------------------------------- reminders --
    def reminders(self, user: str, lang: str = "te", *, tried: Optional[List[str]] = None) -> List[Dict[str, Any]]:
        """Unfinished setup first, then ONE feature that fits what the person said. Dismissed ones never come back."""
        lang = _lang(lang)
        tried = set(tried or [])
        with closing(_connect(self.db_path)) as conn:
            gone = {r["ref"] for r in conn.execute("SELECT ref FROM guide_reminder_dismissals WHERE user_id=?", (user,))}
        out: List[Dict[str, Any]] = []
        st = self.status(user)
        if st["status"] in ("paused", "running") and st["remaining"] and "setup" not in gone:
            out.append({"ref": "setup", "kind": "setup", "route": "/guide-session",
                        "text": (self._topic(st["remaining"][0]).get("te" if lang == "te" else "en"))})
        said = " ".join(f["value"].lower() for f in self.facts(user))
        for hint in FEATURE_HINTS:
            ref = "feature:" + hint["key"]
            if ref in gone or hint["key"] in tried:
                continue
            if any(w in said for w in hint["words"]):
                out.append({"ref": ref, "kind": "feature", "route": hint["route"], "text": hint["te" if lang == "te" else "en"]})
                break
        return out

    def dismiss(self, user: str, ref: str, forever: bool = False) -> None:
        with closing(_connect(self.db_path)) as conn, conn:
            conn.execute(
                "INSERT OR REPLACE INTO guide_reminder_dismissals (user_id, ref, forever, at) VALUES (?,?,?,?)",
                (user, _safe_text(ref, 80), 1 if forever else 0, _now()))


class FeatureRequests:
    """Needs the app cannot meet yet. The text is name-less; who wants to be told is kept apart and never shown to staff."""

    STATUSES = ("new", "approved", "building", "done", "declined")

    def __init__(self, db_path: str, *, notify: Optional[Callable[[str, str], None]] = None) -> None:
        self.db_path = db_path
        self.notify = notify
        with closing(_connect(db_path)):
            pass

    def submit(self, user: str, text: str, *, consent: bool, tell_me: bool = False) -> Dict[str, Any]:
        if not consent:
            raise GuideError("consent_required", "nothing is sent without permission", 400)
        clean = _safe_text(text, 400)
        if len(clean) < 4:
            raise GuideError("too_short", "say a little more", 422)
        canon = _canonical(clean)
        now = _now()
        with closing(_connect(self.db_path)) as conn, conn:
            row = conn.execute("SELECT id FROM guide_feature_requests WHERE canonical=?", (canon,)).fetchone()
            if row:
                rid = row["id"]
                conn.execute("UPDATE guide_feature_requests SET count=count+1, updated_at=? WHERE id=?", (now, rid))
            else:
                rid = conn.execute("INSERT INTO guide_feature_requests (canonical, text, created_at, updated_at) VALUES (?,?,?,?)",
                                   (canon, clean, now, now)).lastrowid
            if tell_me:
                conn.execute("INSERT OR IGNORE INTO guide_feature_waiters (request_id, user_id, at) VALUES (?,?,?)", (rid, user, now))
        return {"id": rid, "tell_me": bool(tell_me)}

    def list(self) -> List[Dict[str, Any]]:
        with closing(_connect(self.db_path)) as conn:
            rows = conn.execute(
                """SELECT r.*, (SELECT COUNT(*) FROM guide_feature_waiters w WHERE w.request_id=r.id) AS waiting
                   FROM guide_feature_requests r ORDER BY (r.status='new') DESC, r.count DESC, r.id DESC LIMIT 300""").fetchall()
        return [{"id": r["id"], "text": r["text"], "count": r["count"], "status": r["status"], "note": r["note"] or "",
                 "push_similar": bool(r["push_similar"]), "waiting": r["waiting"], "created_at": r["created_at"]} for r in rows]

    def set_status(self, request_id: int, status: str, *, note: str = "", push_similar: Optional[bool] = None) -> Dict[str, Any]:
        if status not in self.STATUSES:
            raise GuideError("bad_status", "unknown status", 422)
        told = 0
        with closing(_connect(self.db_path)) as conn, conn:
            row = conn.execute("SELECT id FROM guide_feature_requests WHERE id=?", (request_id,)).fetchone()
            if row is None:
                raise GuideError("not_found", "no such request", 404)
            conn.execute("UPDATE guide_feature_requests SET status=?, note=?, push_similar=COALESCE(?, push_similar), updated_at=? WHERE id=?",
                         (status, _safe_text(note, 300), None if push_similar is None else int(push_similar), _now(), request_id))
            waiters = []
            if status == "done":
                waiters = [r["user_id"] for r in conn.execute(
                    "SELECT user_id FROM guide_feature_waiters WHERE request_id=? AND told_at IS NULL", (request_id,))]
                conn.execute("UPDATE guide_feature_waiters SET told_at=? WHERE request_id=? AND told_at IS NULL", (_now(), request_id))
        if waiters and self.notify is not None:
            text = next((r["text"] for r in self.list() if r["id"] == request_id), "")
            for user in waiters:
                try:
                    self.notify(user, text)
                    told += 1
                except Exception:
                    pass
        return {"id": request_id, "status": status, "told": told}
