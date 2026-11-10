"""ASKODOX self-correction loop (owner 2026-11-10: "Autonomous Intelligence & Self-Correction System").

How a wrong answer gets fixed for everyone, without a new app or a code change:

1. CATCH -- a reply is marked wrong two ways:
   * the user taps "Wrong answer" on a reply (``source=button``), or
   * the user's next message corrects it ("that's wrong", "తప్పు") -- caught by
     ``live_lookup.is_user_correction`` (``source=typed``).
   Both become an ``answer_corrections`` row (schema resource, Command Center ->
   Customers): the question and the reply, masked by ``pii_mask`` -- never who asked.
2. REVIEW -- staff read it, write the correct answer in ``corrected`` and Approve.
   Nothing a user says changes answers by itself (a user can be wrong too).
3. LEARN -- every later question that shares its content words with an APPROVED
   correction carries it into the brain prompt (``lessons_for`` -> ``decide(lessons=)``)
   as a fact that wins over the model's memory. Same mistake, not again.
4. PROVE -- ``regression_cases`` lists every approved correction as a test case
   (question -> what the answer must follow), for the staff check-list / CI.
5. WATCH -- the brain giving no answer is recorded (``brain_failure`` event); the
   15-minute owner-alert job pushes staff when it keeps happening (``owner_alerts``).
"""
from __future__ import annotations

import re
import time
from typing import Any

from app.services.pii_mask import mask_sensitive

RESOURCE = "answer_corrections"
REASONS = ("wrong", "outdated", "not_helpful", "other")
SOURCES = ("button", "typed")
MAX_LESSONS = 3
_CACHE_SECONDS = 60

# Words that carry no subject (English + common Telugu glue words); everything else is content.
_STOP = {
    "the", "a", "an", "is", "are", "was", "were", "be", "to", "of", "in", "on", "for", "and", "or", "with", "what",
    "which", "who", "how", "why", "when", "where", "me", "my", "i", "you", "your", "it", "this", "that", "do", "does",
    "can", "please", "tell", "about", "give", "show", "want", "need", "best", "good", "now", "today", "price", "rate",
    "ఏది", "ఏమి", "ఏం", "ఎంత", "ఎలా", "ఎక్కడ", "నాకు", "నా", "ఈ", "ఆ", "కావాలి", "చెప్పు", "చెప్పండి", "గురించి", "లో",
    "ఉంది", "ఉందా", "అంటే", "ఇప్పుడు",
}
_WORD = re.compile(r"[\wఀ-౿]+", re.UNICODE)

_cache: dict[str, Any] = {"at": 0.0, "db": None, "rows": []}


def content_words(text: Any) -> set[str]:
    out = set()
    for raw in _WORD.findall(str(text or "").casefold()):
        word = raw.rstrip("s") if raw.isascii() and len(raw) > 4 else raw
        if len(word) >= 3 and word not in _STOP and not word.isdigit():
            out.add(word)
    return out


def _resources(pf: Any) -> Any:
    return pf.resources


def report(pf: Any, *, question: str, answer: str, reason: str = "wrong", note: str = "", language: str = "",
           source: str = "button", user_ref: str = "") -> dict[str, Any]:
    """One wrong-answer report, masked. Returns the stored row."""
    q = mask_sensitive(str(question or "").strip())[:1000]
    a = mask_sensitive(str(answer or "").strip())[:3000]
    data = {
        "summary": (q or a)[:90] or "(empty)",
        "question": q,
        "answer": a,
        "reason": reason if reason in REASONS else "other",
        "note": mask_sensitive(str(note or "").strip())[:1000],
        "language": str(language or "")[:10],
        "source": source if source in SOURCES else "button",
        "user_ref": str(user_ref or "")[:40],
        "corrected": "",
    }
    row = _resources(pf).create(RESOURCE, data, actor="app")
    try:
        pf.repo.record_event("answer_reported", detail={"reason": data["reason"], "source": data["source"]})
    except Exception:
        pass
    return row


def _approved(pf: Any) -> list[dict[str, Any]]:
    db = getattr(pf.repo, "db_path", None)
    now = time.monotonic()
    if _cache["db"] == db and now - _cache["at"] < _CACHE_SECONDS:
        return _cache["rows"]
    rows = []
    try:
        for row in pf.repo.list(RESOURCE, status="APPROVED"):
            data = row.get("data") or {}
            corrected = str(data.get("corrected") or "").strip()
            if row.get("status") == "APPROVED" and corrected and not row.get("archived"):
                rows.append({"id": row.get("id"), "question": str(data.get("question") or ""), "corrected": corrected,
                             "words": content_words(data.get("question"))})
    except Exception:
        rows = []
    _cache.update(at=now, db=db, rows=rows)
    return rows


def clear_cache() -> None:
    _cache.update(at=0.0, db=None, rows=[])


def lessons_for(pf: Any, question: str, *, limit: int = MAX_LESSONS) -> list[str]:
    """Approved corrections that are about the same thing as ``question`` (shared content words),
    best match first -- as short lines for the brain prompt."""
    asked = content_words(question)
    if not asked:
        return []
    scored = []
    for row in _approved(pf):
        shared = asked & row["words"]
        if not shared:
            continue
        need = 1 if min(len(asked), len(row["words"])) <= 2 else 2
        if len(shared) < need:
            continue
        scored.append((len(shared) / max(1, len(row["words"])), len(shared), row))
    scored.sort(key=lambda s: (-s[0], -s[1]))
    return [f"Q: {r['question'][:200]} -> correct answer: {r['corrected'][:400]}" for _, _, r in scored[:limit]]


def prompt_block(lessons: list[str] | None) -> str:
    if not lessons:
        return ""
    lines = "\n".join(f"- {line}" for line in lessons[:MAX_LESSONS])
    return ("STAFF-CHECKED CORRECTIONS (an earlier ASKODOX answer was wrong; staff wrote the right one). When the user "
            "asks about the same thing, follow these over your own memory and do not repeat the old mistake:\n"
            f"{lines}\n")


def regression_cases(pf: Any) -> list[dict[str, str]]:
    return [{"id": str(r["id"]), "question": r["question"], "must_follow": r["corrected"]} for r in _approved(pf)]


def capture_typed(pf: Any, *, message: str, history: list[Any], language: str = "", user_ref: str = "") -> bool:
    """The user's message says the last reply was wrong -> a ``typed`` report of that reply. Never raises."""
    try:
        from app.services import live_lookup

        text = str(message or "").split("\n\n")[0]
        if not live_lookup.is_user_correction(text):
            return False
        answer = question = ""
        for turn in reversed(list(history or [])[-8:]):
            role = getattr(turn, "role", None) or (turn.get("role") if isinstance(turn, dict) else "")
            body = getattr(turn, "text", None) or (turn.get("text") if isinstance(turn, dict) else "")
            if not answer and role == "assistant":
                answer = str(body or "")
            elif answer and role == "user":
                question = str(body or "")
                break
        if not answer:
            return False
        report(pf, question=question, answer=answer, reason="wrong", note=text, language=language, source="typed",
               user_ref=user_ref)
        return True
    except Exception:
        return False


def brain_failed(pf: Any, *, reason: str = "no_answer") -> None:
    """The brain gave no answer for a turn (counted for the owner alert). Never raises."""
    try:
        pf.repo.record_event("brain_failure", detail={"reason": str(reason)[:40]})
    except Exception:
        pass
