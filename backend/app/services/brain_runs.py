"""Per-turn brain trace (Brain foundation, 2026-11-10): what one chat turn cost and how it went.

One row per assistant turn: mode, whether the brain answered, latency, model calls, tokens, web
searches and an estimated rupee cost. NO message text, NO reasoning, NO user identity -- only numbers,
so the Brain Dashboard can show cost / latency / failure rate and compare the old and new brain.
Provider calls are picked up from the existing usage-meter hook (same thread as the turn); calls a
turn makes in other threads (parallel web sources) are not attributed to it.
"""
from __future__ import annotations

import contextvars
import sqlite3
import threading
import time
import uuid
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

RETENTION_DAYS = 30
_current: contextvars.ContextVar[Optional["Run"]] = contextvars.ContextVar("askodox_brain_run", default=None)
_lock = threading.Lock()
_ready: set[str] = set()
_last_cleanup: Dict[str, float] = {}

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS brain_runs (turn_id TEXT PRIMARY KEY, at TEXT NOT NULL, mode TEXT NOT NULL,"
    " source TEXT NOT NULL, ok INTEGER NOT NULL, latency_ms INTEGER NOT NULL, model_calls INTEGER NOT NULL,"
    " models TEXT NOT NULL, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,"
    " searches INTEGER NOT NULL, cost_inr REAL NOT NULL, lessons INTEGER NOT NULL, grounded INTEGER NOT NULL,"
    " language TEXT NOT NULL, reported INTEGER NOT NULL DEFAULT 0)",
    "CREATE INDEX IF NOT EXISTS idx_brain_runs_at ON brain_runs(at)",
)


class Run:
    def __init__(self) -> None:
        self.turn_id = "t_" + uuid.uuid4().hex[:20]
        self.started = time.monotonic()
        self.calls: List[Dict[str, Any]] = []

    def note(self, row: Dict[str, Any]) -> None:
        self.calls.append(dict(row))


def begin() -> Run:
    run = Run()
    _current.set(run)
    return run


def note_provider_call(row: Dict[str, Any]) -> None:
    """Called by the usage meter for every provider round trip. Never raises."""
    try:
        run = _current.get()
        if run is not None:
            run.note(row)
    except Exception:
        pass


def _ensure(db_path: str) -> None:
    if db_path in _ready:
        return
    with _lock, closing(sqlite3.connect(db_path, timeout=5)) as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        conn.commit()
    _ready.add(db_path)


def finish(db_path: str, run: Run, *, mode: str, source: str, ok: bool, lessons: int = 0, grounded: bool = False,
           language: str = "", prices: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
    """Stores the turn. Never raises (a trace must not break an answer)."""
    try:
        _current.set(None)
        from app.services import ai_usage_meter

        llm = [c for c in run.calls if c.get("feature") in ("chat", "reasoning", "image") and c.get("provider") in
               ("gemini", "openai", "anthropic")]
        searches = [c for c in run.calls if c.get("feature") == "web_search"]
        table = prices or ai_usage_meter.prices(db_path)
        cost = 0.0
        for call in run.calls:
            try:
                cost += ai_usage_meter.cost_inr(table, {**call, "calls": 1})
            except Exception:
                pass
        row = {
            "turn_id": run.turn_id, "at": datetime.now(timezone.utc).isoformat(), "mode": str(mode or "")[:20],
            "source": str(source or "")[:20], "ok": 1 if ok else 0,
            "latency_ms": int((time.monotonic() - run.started) * 1000), "model_calls": len(llm),
            "models": ",".join(sorted({str(c.get("model") or "") for c in llm}))[:120],
            "input_tokens": sum(int(c.get("input_tokens") or 0) for c in llm),
            "output_tokens": sum(int(c.get("output_tokens") or 0) for c in llm), "searches": len(searches),
            "cost_inr": round(cost, 4), "lessons": int(lessons), "grounded": 1 if grounded else 0,
            "language": str(language or "")[:10],
        }
        _ensure(db_path)
        with _lock, closing(sqlite3.connect(db_path, timeout=5)) as conn:
            conn.execute(
                "INSERT OR REPLACE INTO brain_runs (turn_id, at, mode, source, ok, latency_ms, model_calls, models,"
                " input_tokens, output_tokens, searches, cost_inr, lessons, grounded, language)"
                " VALUES (:turn_id, :at, :mode, :source, :ok, :latency_ms, :model_calls, :models, :input_tokens,"
                " :output_tokens, :searches, :cost_inr, :lessons, :grounded, :language)", row)
            now = time.monotonic()
            if now - _last_cleanup.get(db_path, 0.0) > 3600:
                _last_cleanup[db_path] = now
                cutoff = (datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)).isoformat()
                conn.execute("DELETE FROM brain_runs WHERE at < ?", (cutoff,))
            conn.commit()
        return row
    except Exception:
        return None


def mark_reported(db_path: str, turn_id: str) -> None:
    """A user marked this turn's answer wrong (self-correction). Never raises."""
    try:
        if not turn_id:
            return
        _ensure(db_path)
        with _lock, closing(sqlite3.connect(db_path, timeout=5)) as conn:
            conn.execute("UPDATE brain_runs SET reported = 1 WHERE turn_id = ?", (str(turn_id)[:40],))
            conn.commit()
    except Exception:
        pass


def summary(db_path: str, *, days: int = 7) -> Dict[str, Any]:
    """Numbers for the Brain Dashboard: per mode and overall."""
    _ensure(db_path)
    since = (datetime.now(timezone.utc) - timedelta(days=max(1, min(int(days), RETENTION_DAYS)))).isoformat()
    with closing(sqlite3.connect(db_path, timeout=5)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT mode, COUNT(*) AS turns, SUM(ok) AS answered, AVG(latency_ms) AS avg_latency_ms,"
            " SUM(model_calls) AS model_calls, SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens,"
            " SUM(searches) AS searches, SUM(cost_inr) AS cost_inr, SUM(reported) AS reported, SUM(grounded) AS grounded,"
            " SUM(CASE WHEN lessons > 0 THEN 1 ELSE 0 END) AS used_lessons"
            " FROM brain_runs WHERE at >= ? GROUP BY mode ORDER BY turns DESC", (since,)).fetchall()
        slow = conn.execute(
            "SELECT latency_ms FROM brain_runs WHERE at >= ? ORDER BY latency_ms", (since,)).fetchall()
    modes = []
    total = {"turns": 0, "answered": 0, "cost_inr": 0.0, "reported": 0, "model_calls": 0}
    for r in rows:
        item = {k: r[k] for k in r.keys()}
        item["avg_latency_ms"] = int(item["avg_latency_ms"] or 0)
        item["cost_inr"] = round(float(item["cost_inr"] or 0), 2)
        item["cost_per_turn_inr"] = round(item["cost_inr"] / item["turns"], 3) if item["turns"] else 0.0
        modes.append(item)
        for key in total:
            total[key] += item[key] or 0
    latencies = [int(r["latency_ms"]) for r in slow]
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))] if latencies else 0
    turns = total["turns"]
    return {
        "days": days, "turns": turns, "answered": total["answered"],
        "failure_rate_pct": round(100.0 * (turns - total["answered"]) / turns, 1) if turns else 0.0,
        "cost_inr": round(total["cost_inr"], 2),
        "cost_per_turn_inr": round(total["cost_inr"] / turns, 3) if turns else 0.0,
        "wrong_answer_reports": total["reported"],
        "wrong_answer_rate_pct": round(100.0 * total["reported"] / turns, 2) if turns else 0.0,
        "p95_latency_ms": p95, "modes": modes,
        "note": "Costs are estimates from the staff-editable price table; calls made in other threads are not included.",
    }
