"""ASKODOX Video Study: what is actually INSIDE a short video, grounded.

A study is made only when a customer asks for it (never for every search
result), only for videos up to ``study_max_seconds()`` (V1: 180 s, set by
``ASKODOX_VIDEO_STUDY_MAX_SECONDS``) and cached by video reference, so a
second question never re-processes the video.

Sources of evidence, all legitimate:

* YouTube videos: the multimodal model reads the public video itself
  (speech + frames + on-screen text) from its YouTube URL.
* Uploaded videos: the same model call the chat attachment already makes
  (``UniversalImageService.analyze_video``) also returns the study fields,
  so an upload costs ONE model call.

Every fact carries its basis (shown on screen = confirmed from the video;
said by the speaker = seller claim), a timestamp and the evidence. Answers
come only from the stored study; an answer that cites nothing in it is
replaced by "not confirmed in this video". External market information is
built elsewhere and always labelled as external.
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import statistics
import struct
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional

DEFAULT_MAX_SECONDS = 180

# Basis labels the app shows next to every value.
BASIS_CONFIRMED = "confirmed_from_video"
BASIS_CLAIM = "seller_claim"
BASIS_EXTERNAL = "externally_verified"
BASIS_MISSING = "not_confirmed"


def study_max_seconds() -> int:
    """The hard study cap (configuration, not code)."""
    try:
        value = int(str(os.environ.get("ASKODOX_VIDEO_STUDY_MAX_SECONDS", "") or DEFAULT_MAX_SECONDS).strip())
    except ValueError:
        return DEFAULT_MAX_SECONDS
    return value if 10 <= value <= 3600 else DEFAULT_MAX_SECONDS


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# -- durations ---------------------------------------------------------------

_CLOCK = re.compile(r"^\s*(?:(\d{1,2}):)?(\d{1,3}):(\d{2})\s*$")
_ISO = re.compile(r"^P(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$")


def duration_seconds(text: Any) -> Optional[int]:
    """'0:15', '05:52', '1:02:03', 'PT2M10S' or a number of seconds."""
    if text is None:
        return None
    if isinstance(text, (int, float)):
        return int(text) if text >= 0 else None
    raw = str(text).strip()
    if not raw:
        return None
    if raw.isdigit():
        return int(raw)
    clock = _CLOCK.match(raw)
    if clock:
        hours, minutes, seconds = int(clock.group(1) or 0), int(clock.group(2)), int(clock.group(3))
        return hours * 3600 + minutes * 60 + seconds
    iso = _ISO.match(raw.upper())
    if iso and any(iso.groups()):
        h, m, s = (int(g or 0) for g in iso.groups())
        return h * 3600 + m * 60 + s
    return None


def mp4_duration_seconds(data: bytes) -> Optional[float]:
    """Duration from the ISO-BMFF ``mvhd`` box (mp4 / mov / m4v / 3gp) --
    read from the header only, before any expensive processing."""
    if not data:
        return None
    index = data.find(b"mvhd")
    while index >= 4:
        try:
            version = data[index + 4]
            if version == 1:
                timescale, duration = struct.unpack(">IQ", data[index + 24:index + 36])
            else:
                timescale, duration = struct.unpack(">II", data[index + 16:index + 24])
        except (struct.error, IndexError):
            return None
        if timescale > 0 and duration > 0:
            return duration / timescale
        index = data.find(b"mvhd", index + 4)
    return None


def clock(seconds: Optional[float]) -> str:
    if seconds is None:
        return ""
    total = int(round(seconds))
    return f"{total // 3600}:{total % 3600 // 60:02d}:{total % 60:02d}" if total >= 3600 else f"{total // 60}:{total % 60:02d}"


# -- messages (user language) -------------------------------------------------

def _pick(language: str, en: str, te: str, hi: str) -> str:
    return {"te": te, "hi": hi}.get((language or "en")[:2].lower(), en)


def too_long_message(language: str = "en") -> str:
    limit = study_max_seconds()
    minutes = limit // 60
    span_en = f"{minutes} minutes" if limit % 60 == 0 else f"{limit} seconds"
    span_te = f"{minutes} నిమిషాల" if limit % 60 == 0 else f"{limit} సెకన్ల"
    span_hi = f"{minutes} मिनट" if limit % 60 == 0 else f"{limit} सेकंड"
    return _pick(language,
                 f"ASKODOX Video Study is currently available for videos up to {span_en}.",
                 f"ASKODOX వీడియో స్టడీ ప్రస్తుతం {span_te} వరకు ఉన్న వీడియోలకు మాత్రమే అందుబాటులో ఉంది.",
                 f"ASKODOX वीडियो स्टडी अभी {span_hi} तक के वीडियो के लिए उपलब्ध है।")


def unknown_length_message(language: str = "en") -> str:
    return _pick(language,
                 "ASKODOX could not confirm this video's length, so Video Study is not available for it.",
                 "ఈ వీడియో నిడివిని ASKODOX నిర్ధారించలేకపోయింది, కాబట్టి వీడియో స్టడీ అందుబాటులో లేదు.",
                 "ASKODOX इस वीडियो की लंबाई की पुष्टि नहीं कर सका, इसलिए वीडियो स्टडी उपलब्ध नहीं है।")


def unavailable_message(language: str = "en") -> str:
    return _pick(language, "Video content analysis unavailable.",
                 "వీడియో కంటెంట్ విశ్లేషణ అందుబాటులో లేదు.",
                 "वीडियो कंटेंट विश्लेषण उपलब्ध नहीं है।")


def not_in_video_message(language: str = "en") -> str:
    return _pick(language, "This video does not have the information to confirm that.",
                 "ఈ వీడియోలో ఆ వివరాన్ని నిర్ధారించడానికి సమాచారం లేదు.",
                 "इस वीडियो में इसकी पुष्टि करने के लिए जानकारी नहीं है।")


def eligibility(duration: Optional[float], language: str = "en") -> Dict[str, Any]:
    limit = study_max_seconds()
    if duration is None:
        return {"eligible": False, "reason": "unknown_duration", "max_seconds": limit,
                "duration_seconds": None, "message": unknown_length_message(language)}
    if duration > limit:
        return {"eligible": False, "reason": "too_long", "max_seconds": limit,
                "duration_seconds": int(duration), "message": too_long_message(language)}
    return {"eligible": True, "reason": None, "max_seconds": limit, "duration_seconds": int(duration),
            "message": ""}


# -- Shorts -------------------------------------------------------------------

def is_short(url: str = "", duration: Optional[int] = None, title: str = "", text: str = "") -> bool:
    """Confidently a YouTube Short: a /shorts/ link, or a vertical-length
    clip (<= 60 s) that tags itself #shorts. Otherwise a normal video."""
    if "/shorts/" in str(url or ""):
        return True
    tagged = "#short" in f"{title} {text}".lower()
    return bool(tagged and duration is not None and duration <= 60)


# -- the study prompt ------------------------------------------------------

STUDY_SCHEMA = (
    "ASKODOX VIDEO STUDY. Watch the WHOLE video: listen to the speech (any language -- Telugu, Hindi, English or "
    "mixed) and look at the frames and on-screen text. Report ONLY what is actually said or shown in the video. "
    "Never fill a value from the title, the channel, the description or general knowledge. Keep names, model "
    "numbers and prices exactly as said/shown. If you cannot access or understand the video content, set "
    "content_accessible=false and leave the lists empty.\n"
    "Study fields: {\"content_accessible\":bool,\"category\":\"vehicle|property|product|service|food|job|other\","
    "\"subject\":\"the item/service as said or shown\",\"summary\":\"2-3 factual sentences\","
    "\"spoken_language\":string,\"facts\":[{\"key\":\"snake_case field\",\"label\":\"short English label\","
    "\"value\":\"exactly as said/shown\",\"basis\":\"shown|said\",\"timestamp\":\"m:ss\","
    "\"evidence\":\"the exact words, or what is visible\"}],\"transcript\":[{\"t\":\"m:ss\",\"text\":\"verbatim speech "
    "in its original language\"}],\"visible_text\":[{\"t\":\"m:ss\",\"text\":string}],"
    "\"missing\":[\"important fields for this category that the video does NOT state\"],"
    "\"suggested_questions\":[\"5-8 short buyer questions about THIS video\"]}.\n"
    "basis: shown = clearly visible on screen; said = a statement or claim by the speaker/seller. "
    "Use only the fields that fit the category, e.g. vehicle: make, model, variant, year, asking_price, kilometres, "
    "fuel, transmission, ownership, registration, location, features, condition; property: type, location, area, "
    "bedrooms, price_or_rent, amenities; product: product, brand, model, specifications, price, condition, "
    "warranty, features; service: service, location, quoted_price, inclusions, exclusions."
)

STUDY_PROMPT = "Return exactly one JSON object and no markdown.\n" + STUDY_SCHEMA

_TS = re.compile(r"^\d{1,2}:\d{2}(?::\d{2})?$")


def _ts(value: Any) -> str:
    text = str(value or "").strip()
    return text if _TS.match(text) else ""


def _clean(value: Any, limit: int = 400) -> str:
    text = " ".join(str(value or "").split())
    return "" if text.casefold() in {"", "null", "none", "unknown", "n/a", "not mentioned"} else text[:limit]


def normalize_study(payload: Dict[str, Any] | None, *, ref: str, source: str, duration: Optional[float],
                    language: str = "en") -> Dict[str, Any]:
    """Model output -> the stored study. Values without evidence are dropped;
    an empty or inaccessible study is honestly 'unavailable'."""
    data = dict(payload or {})
    facts: List[Dict[str, Any]] = []
    seen = set()
    for raw in data.get("facts") or []:
        if not isinstance(raw, dict):
            continue
        key = re.sub(r"[^a-z0-9_]", "_", _clean(raw.get("key"), 40).lower()).strip("_")
        value = _clean(raw.get("value"))
        evidence = _clean(raw.get("evidence"))
        if not key or not value or not evidence or (key, value) in seen:
            continue
        seen.add((key, value))
        facts.append({
            "key": key, "label": _clean(raw.get("label"), 60) or key.replace("_", " ").title(), "value": value,
            "basis": BASIS_CONFIRMED if str(raw.get("basis") or "").lower() == "shown" else BASIS_CLAIM,
            "timestamp": _ts(raw.get("timestamp")), "evidence": evidence,
        })
    transcript = [{"t": _ts(s.get("t")), "text": _clean(s.get("text"), 500)}
                  for s in (data.get("transcript") or []) if isinstance(s, dict) and _clean(s.get("text"))][:80]
    visible = [{"t": _ts(s.get("t")), "text": _clean(s.get("text"), 300)}
               for s in (data.get("visible_text") or []) if isinstance(s, dict) and _clean(s.get("text"))][:40]
    accessible = data.get("content_accessible") is not False and bool(facts or transcript or visible)
    study = {
        "ref": ref, "source": source, "status": "ready" if accessible else "unavailable",
        "duration_seconds": int(duration) if duration is not None else None,
        "category": _clean(data.get("category"), 20).lower() or "other",
        "subject": _clean(data.get("subject"), 120), "summary": _clean(data.get("summary"), 700),
        "spoken_language": _clean(data.get("spoken_language"), 30),
        "facts": facts, "transcript": transcript, "visible_text": visible,
        "missing": [m for m in (_clean(x, 60) for x in (data.get("missing") or [])) if m][:12],
        "suggested_questions": [q for q in (_clean(x, 120) for x in (data.get("suggested_questions") or [])) if q][:8],
        "studied_at": _now(),
    }
    if not accessible:
        study.update({"facts": [], "transcript": [], "visible_text": [], "summary": "",
                      "message": unavailable_message(language)})
    return study


# -- cache -------------------------------------------------------------------

class VideoStudyStore:
    """One study per video reference (yt_<id> / up_<sha>), reused for every
    later question."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with self._connect() as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS video_studies (ref TEXT PRIMARY KEY, status TEXT NOT NULL, "
                         "source TEXT NOT NULL, study_json TEXT NOT NULL, created_at TEXT NOT NULL)")

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def get(self, ref: str) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT study_json FROM video_studies WHERE ref=?", (ref,)).fetchone()
        return json.loads(row["study_json"]) if row else None

    def save(self, study: Dict[str, Any]) -> None:
        with self._connect() as conn:
            conn.execute("INSERT OR REPLACE INTO video_studies (ref, status, source, study_json, created_at) "
                         "VALUES (?, ?, ?, ?, ?)",
                         (study["ref"], study["status"], study["source"], json.dumps(study, ensure_ascii=False),
                          _now()))


# -- the service ---------------------------------------------------------------

_LANG_NAMES = {"te": "Telugu", "hi": "Hindi", "en": "English"}

# Question words -> fact keys (deterministic fallback when the reasoning
# model is unavailable; it can only ever return a stored fact).
_ALIASES = [
    (r"price|cost|rate|asking|how much|₹|lakh|rupee|ధర|ఎంత|రేటు|कीमत|दाम|कितने", ("price", "asking", "rent", "quoted")),
    (r"year|model year|సంవత్సరం|ఏ సంవత్సర|साल", ("year",)),
    (r"\bkm\b|kilomet|mileage|driven|కిలోమీటర్|కి\.మీ|किलोमीटर", ("kilomet", "km", "odometer", "mileage")),
    (r"variant|వేరియంట్|वेरिएंट", ("variant",)),
    (r"model|మోడల్|मॉडल", ("model", "variant")),
    (r"make|brand|company|బ్రాండ్|कंपनी|ब्रांड", ("make", "brand")),
    (r"feature|ఫీచర్|सुविधा|फीचर", ("feature",)),
    (r"where|location|place|city|ఎక్కడ|ప్రాంతం|कहां|कहाँ|जगह", ("location", "registration", "city")),
    (r"fuel|diesel|petrol|ఇంధనం|डीजल|पेट्रोल", ("fuel",)),
    (r"transmission|automatic|manual|गियर", ("transmission",)),
    (r"owner|ownership|యజమాని|मालिक", ("owner",)),
    (r"accident|damage|condition|ప్రమాదం|కండిషన్|हादसा|हालत", ("accident", "condition", "damage")),
    (r"warranty|వారంటీ|वारंटी", ("warranty",)),
    (r"area|sq|size|bedroom|bhk", ("area", "bedroom", "size")),
]
_SUMMARY = re.compile(r"summar|overview|సారాంశం|సంక్షిప్తం|सार|सारांश", re.IGNORECASE)
_MISSING = re.compile(r"missing|not mention|left out|ఏమి లేదు|లేని|తెలియని|छूट|नहीं बताया", re.IGNORECASE)


def _keys_in(study: Dict[str, Any]) -> set:
    return {f["key"] for f in study.get("facts") or []}


def _timestamps_in(study: Dict[str, Any]) -> set:
    stamps = {f.get("timestamp") for f in study.get("facts") or []}
    stamps |= {s.get("t") for s in study.get("transcript") or []}
    stamps |= {s.get("t") for s in study.get("visible_text") or []}
    return {s for s in stamps if s}


def suggested_questions(study: Dict[str, Any], language: str = "en") -> List[str]:
    """Category-aware follow-ups from what THIS study found (never a fixed
    car-only list): its own questions, then one per found field, then
    market / missing / contact."""
    # The study's own questions are kept only when they are in the
    # conversation language (a cached study serves every language).
    own = [q for q in study.get("suggested_questions") or [] if q]
    lang = (language or "en")[:2].lower()
    script = {"te": r"[\u0C00-\u0C7F]", "hi": r"[\u0900-\u097F]"}.get(lang)
    out = [q for q in own if (re.search(script, q) if script else not re.search(r"[\u0900-\u0D7F]", q))]
    for fact in (study.get("facts") or [])[:5]:
        label = fact["label"].lower()
        out.append(_pick(language, f"What {label} did the video mention?", f"వీడియోలో {fact['label']} ఏమిటి?",
                         f"वीडियो में {fact['label']} क्या बताया?"))
    if study.get("missing"):
        out.append(_pick(language, "What important information is missing?", "ముఖ్యమైన ఏ సమాచారం లేదు?",
                         "कौन सी ज़रूरी जानकारी नहीं है?"))
    out.append(_pick(language, "Compare this with the market price.", "మార్కెట్ ధరతో పోల్చండి.",
                     "बाज़ार कीमत से तुलना करें।"))
    unique: List[str] = []
    for q in out:
        if q.casefold() not in {u.casefold() for u in unique}:
            unique.append(q)
    return unique[:8]


class VideoStudyService:
    def __init__(self, store: VideoStudyStore, client: Any = None,
                 models: tuple = ("gemini-3.6-flash", "gemini-3.5-flash"),
                 log: Callable[[str], None] | None = None) -> None:
        self.store = store
        self.client = client
        self.models = models
        self.log = log or (lambda message: print(message, flush=True))

    # studies

    def cached(self, ref: str) -> Optional[Dict[str, Any]]:
        study = self.store.get(ref)
        if not study:
            return None
        if study.get("status") == "unavailable":
            # An unavailable result is retried at most every 6 hours.
            try:
                age = datetime.now(timezone.utc) - datetime.fromisoformat(study["studied_at"])
            except (KeyError, ValueError):
                age = timedelta(days=1)
            if age > timedelta(hours=6):
                return None
        return study

    def study_youtube(self, ref: str, url: str, duration: Optional[float], language: str = "en") -> Dict[str, Any]:
        """Study a public YouTube video (only when eligible; cached)."""
        gate = eligibility(duration, language)
        if not gate["eligible"]:
            return {"ref": ref, "status": "not_eligible", **gate}
        cached = self.cached(ref)
        if cached:
            return {**cached, "cached": True}
        payload = self._generate_from_url(url)
        study = normalize_study(payload, ref=ref, source="youtube", duration=duration, language=language)
        self.store.save(study)
        self.log(f"ASKODOX VIDEO STUDY: ref={ref} source=youtube status={study['status']} "
                 f"facts={len(study['facts'])} transcript={len(study['transcript'])}")
        return {**study, "cached": False}

    def study_from_upload(self, ref: str, analysis: Dict[str, Any] | None, duration: Optional[float],
                          language: str = "en") -> Dict[str, Any]:
        """The study an upload's single model call already returned."""
        cached = self.cached(ref)
        if cached:
            return cached
        study = normalize_study(analysis, ref=ref, source="upload", duration=duration, language=language)
        self.store.save(study)
        return study

    def _generate_from_url(self, url: str) -> Dict[str, Any]:
        if self.client is None:
            return {}
        try:
            from google.genai import types

            part = types.Part(file_data=types.FileData(file_uri=url, mime_type="video/*"))
        except Exception:
            return {}
        for model in self.models:
            try:
                response = self.client.models.generate_content(
                    model=model, contents=[part, STUDY_PROMPT],
                    config=types.GenerateContentConfig(response_mime_type="application/json"))
                return _json(str(getattr(response, "text", "") or ""))
            except Exception as error:
                self.log(f"ASKODOX VIDEO STUDY: model={model} status=failed error={type(error).__name__}")
        return {}

    # grounded answers

    def answer(self, study: Dict[str, Any], question: str, language: str = "en") -> Dict[str, Any]:
        """An answer ONLY from the stored study: which facts it used, their
        basis and timestamps. Nothing found -> 'not confirmed'."""
        question = str(question or "").strip()[:300]
        base = {"ref": study.get("ref"), "question": question, "language": language, "from": "video"}
        if study.get("status") != "ready":
            return {**base, "found": False, "answer": unavailable_message(language), "facts": [], "timestamps": []}
        result = self._answer_with_model(study, question, language) if self.client is not None else None
        if result is None:
            result = self._answer_from_facts(study, question, language)
        if not result.get("found"):
            return {**base, "found": False, "answer": not_in_video_message(language), "facts": [], "timestamps": []}
        used = [f for f in study["facts"] if f["key"] in set(result.get("fact_keys") or [])]
        stamps = [t for t in result.get("timestamps") or [] if t in _timestamps_in(study)]
        stamps += [f["timestamp"] for f in used if f.get("timestamp") and f["timestamp"] not in stamps]
        return {**base, "found": True, "answer": str(result.get("answer") or "")[:900], "facts": used,
                "timestamps": stamps[:5]}

    def _answer_with_model(self, study: Dict[str, Any], question: str, language: str) -> Optional[Dict[str, Any]]:
        evidence = {k: study.get(k) for k in ("category", "subject", "summary", "facts", "transcript",
                                              "visible_text", "missing")}
        prompt = (
            "You answer a buyer's question about ONE video using ONLY the VIDEO STUDY below (what was actually "
            "said/shown). Never use outside knowledge, the title or guesses. Keep names, model numbers and prices "
            f"exactly as in the study. Reply in {_LANG_NAMES.get(language[:2], 'English')}. When the study does "
            "not contain the answer, set found=false. Say 'the seller says' for claims (basis seller_claim).\n"
            "Return JSON only: {\"found\":bool,\"answer\":string,\"fact_keys\":[keys used],"
            "\"timestamps\":[m:ss used]}.\n"
            f"VIDEO STUDY: {json.dumps(evidence, ensure_ascii=False)[:24000]}\nQUESTION: {question}"
        )
        from google.genai import types

        for model in self.models:
            try:
                response = self.client.models.generate_content(
                    model=model, contents=[prompt],
                    config=types.GenerateContentConfig(response_mime_type="application/json"))
                data = _json(str(getattr(response, "text", "") or ""))
            except Exception as error:
                self.log(f"ASKODOX VIDEO ASK: model={model} status=failed error={type(error).__name__}")
                continue
            if not data:
                continue
            found = bool(data.get("found"))
            keys = [k for k in data.get("fact_keys") or [] if k in _keys_in(study)]
            stamps = [t for t in data.get("timestamps") or [] if t in _timestamps_in(study)]
            missing_q = bool(_MISSING.search(question)) or bool(_SUMMARY.search(question))
            # Hallucination guard: a "found" answer must cite the study.
            if found and not keys and not stamps and not missing_q:
                found = False
            return {"found": found and bool(str(data.get("answer") or "").strip()),
                    "answer": data.get("answer"), "fact_keys": keys, "timestamps": stamps}
        return None

    @staticmethod
    def _answer_from_facts(study: Dict[str, Any], question: str, language: str) -> Dict[str, Any]:
        text = question.lower()
        if _MISSING.search(text) and study.get("missing"):
            return {"found": True, "fact_keys": [], "timestamps": [],
                    "answer": _pick(language, "Not stated in the video: ", "వీడియోలో చెప్పనివి: ",
                                    "वीडियो में नहीं बताया: ") + ", ".join(study["missing"])}
        if _SUMMARY.search(text) and study.get("summary"):
            return {"found": True, "fact_keys": [], "timestamps": [], "answer": study["summary"]}
        for pattern, hints in _ALIASES:
            if not re.search(pattern, text, re.IGNORECASE):
                continue
            hits = [f for f in study["facts"] if any(h in f["key"] for h in hints)]
            if hits:
                said = _pick(language, "the seller says", "విక్రేత చెప్పారు", "विक्रेता का कहना है")
                parts = [f"{f['label']}: {f['value']}" + (f" ({said})" if f["basis"] == BASIS_CLAIM else "")
                         + (f" [{f['timestamp']}]" if f.get("timestamp") else "") for f in hits[:3]]
                return {"found": True, "fact_keys": [f["key"] for f in hits[:3]], "timestamps": [],
                        "answer": "; ".join(parts)}
        return {"found": False}


def _json(raw: str) -> Dict[str, Any]:
    text = str(raw or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            return {}
        try:
            data = json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            return {}
    return data if isinstance(data, dict) else {}


# -- market comparison (external, never mixed with video facts) -----------------

_MONEY = re.compile(r"(?:₹|rs\.?|inr)?\s*([\d][\d,]*(?:\.\d+)?)\s*(lakh|lakhs|lac|l\b|crore|cr\b|k\b|thousand)?",
                    re.IGNORECASE)


def parse_money(text: Any) -> Optional[float]:
    """'₹12.5 lakh' -> 1250000; '12,50,000' -> 1250000; 'Rs 1.2 crore'."""
    match = _MONEY.search(str(text or ""))
    if not match:
        return None
    try:
        number = float(match.group(1).replace(",", ""))
    except ValueError:
        return None
    unit = (match.group(2) or "").lower()
    if unit in {"lakh", "lakhs", "lac", "l"}:
        number *= 100_000
    elif unit in {"crore", "cr"}:
        number *= 10_000_000
    elif unit in {"k", "thousand"}:
        number *= 1_000
    return number if number > 0 else None


_SUBJECT_KEYS = {
    "vehicle": ("year", "make", "model", "variant"),
    "property": ("bedrooms", "type", "location"),
    "product": ("brand", "product", "model"),
    "service": ("service", "location"),
}

_FACTORS = {
    "vehicle": ["kilometres driven", "number of owners", "service history", "insurance validity", "accident history",
                "exact variant and transmission", "registration state"],
    "property": ["exact location", "carpet vs built-up area", "floor and facing", "age of the building",
                 "approvals and documents"],
    "product": ["condition and age", "warranty left", "original bill and box", "exact model/storage"],
    "service": ["what is included", "spare parts cost", "warranty on the work", "visit charges"],
}


def market_subject(study: Dict[str, Any]) -> str:
    """What to look up in the market: the identifying fields the video
    gave (matched by part of the key -- the model may say make_model), and
    the study's subject when they do not name the item itself."""
    facts = study.get("facts") or []
    parts: List[str] = []
    for hint in _SUBJECT_KEYS.get(study.get("category") or "", ()):
        for fact in facts:
            if hint in fact["key"] and fact["value"] not in parts and not any(fact["value"] in p for p in parts):
                parts.append(fact["value"])
                break
    subject = str(study.get("subject") or "")
    named = [p for p in parts if not re.fullmatch(r"[\d\s]+|[A-Z0-9]{1,4}", p)]
    if not named and subject:
        parts = [p for p in parts if p.lower() not in subject.lower()] + [subject]
    text = " ".join(parts).strip() or subject
    words: List[str] = []
    for word in text.split():
        if word.lower() not in {w.lower() for w in words}:
            words.append(word)
    return " ".join(words)[:120]


def asking_price(study: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    for fact in study.get("facts") or []:
        if any(h in fact["key"] for h in ("asking", "price", "rent", "quoted")):
            value = parse_money(fact["value"])
            if value:
                return {"text": fact["value"], "value": value, "basis": fact["basis"],
                        "timestamp": fact.get("timestamp") or ""}
    return None


def market_comparison(study: Dict[str, Any], rows: List[Dict[str, Any]], language: str = "en") -> Dict[str, Any]:
    """Video facts and external market rows, kept apart. Prices from pages
    are unverified; a negotiation range is only suggested with >= 3
    comparable prices."""
    asking = asking_price(study)
    market_rows = [r for r in rows if str(r.get("match_source") or r.get("source") or "") != "video"][:8]
    prices = [float(r["price"]) for r in market_rows if isinstance(r.get("price"), (int, float)) and r["price"] > 0]
    if asking:
        prices = [p for p in prices if asking["value"] * 0.2 <= p <= asking["value"] * 5]
    summary = None
    negotiation = None
    if prices:
        summary = {"count": len(prices), "min": min(prices), "median": statistics.median(prices),
                   "max": max(prices), "verified": False}
        if asking and len(prices) >= 3:
            low = max(summary["min"], round(asking["value"] * 0.9))
            if low < asking["value"]:
                negotiation = {"low": low, "high": asking["value"], "estimate": True,
                               "note": _pick(language,
                                             "Estimate from comparable listings -- not a valuation.",
                                             "పోల్చదగిన లిస్టింగ్‌ల ఆధారంగా అంచనా -- విలువ నిర్ధారణ కాదు.",
                                             "तुलनीय लिस्टिंग से अनुमान -- मूल्यांकन नहीं।")}
    return {
        "video_facts": {"subject": study.get("subject"), "asking_price": asking,
                        "facts": study.get("facts") or [], "basis_note": "from the video"},
        "market": {
            "source": "external", "basis": BASIS_EXTERNAL,
            "label": _pick(language, "External market information -- not from the video",
                           "బయటి మార్కెట్ సమాచారం -- వీడియోలోనిది కాదు",
                           "बाहरी बाज़ार जानकारी -- वीडियो से नहीं"),
            "query": market_subject(study), "rows": market_rows, "prices": summary, "negotiation": negotiation,
            "factors": _FACTORS.get(study.get("category") or "", []),
        },
    }
