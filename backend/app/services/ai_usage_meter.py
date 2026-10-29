"""ASKODOX AI usage metering -- what each AI feature REALLY uses, so AI Credit rates are set from evidence.

One hook on ``httpx.Client.send`` (every provider call in the backend goes through httpx: the google-genai SDK,
OpenAI, Sarvam, Brave) records, per day / feature / provider / model, the provider's OWN usage numbers:

* Gemini ``usageMetadata`` (prompt / candidates / thoughts tokens) and OpenAI ``usage`` (input / output tokens);
* Sarvam speech-to-text: audio seconds (WAV header or byte-size estimate -- labelled ``estimated_seconds``);
* Sarvam text-to-speech: characters sent;
* Brave: one search per call.

Nothing about the user or the content is stored (no text, no ids) -- only counts. Recording never raises into the
caller and never reads a streamed body. Cost = counts x a staff-editable price table (``prices``) -> an ESTIMATE until
it is compared with the provider's bill; the suggested rate per use = cost x markup for the target net margin after
GST and gateway fee (owner target 25%).
"""
from __future__ import annotations

import json
import logging
import math
import sqlite3
import threading
from contextlib import closing
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

_log = logging.getLogger(__name__)

SCHEMA = [
    "CREATE TABLE IF NOT EXISTS ai_usage_daily (day TEXT NOT NULL, feature TEXT NOT NULL, provider TEXT NOT NULL,"
    " model TEXT NOT NULL, calls INTEGER NOT NULL DEFAULT 0, errors INTEGER NOT NULL DEFAULT 0,"
    " input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,"
    " chars INTEGER NOT NULL DEFAULT 0, seconds REAL NOT NULL DEFAULT 0, PRIMARY KEY (day, feature, provider, model))",
    "CREATE TABLE IF NOT EXISTS ai_usage_prices (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL,"
    " updated_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)",
]

# Published list prices (2026-10-27; third-party price pages + Sarvam's own page) -- staff correct them in the console.
DEFAULT_PRICES: Dict[str, Any] = {
    "usd_inr": 88.0,
    "tokens_usd_per_million": {  # model prefix -> [input, output]
        "gemini-3.6-flash": [0.75, 3.75],
        "gemini-3.5-flash": [0.75, 3.75],
        "gpt-5": [1.25, 10.0],
        "claude-haiku-5-5": [0.10, 0.50],
        "claude-sonnet-5-5": [2.0, 10.0],
        "default": [1.0, 5.0],
    },
    "stt_inr_per_minute": 0.49,
    "tts_inr_per_1000_chars": 3.0,
    "elevenlabs_usd_per_1000_chars": 0.15,  # ESTIMATE -- set from the ElevenLabs plan actually bought
    "search_usd_per_1000": 5.0,
    "serper_usd_per_1000": 1.0,      # ESTIMATE -- Serper prepaid credits (set from the pack actually bought)
    "gst_on_imports_pct": 18.0,      # foreign AI services (reverse charge) -- input credit if GST-registered
    "sale_gst_pct": 18.0,            # credits sold to users, price includes GST
    "gateway_fee_pct": 2.36,         # ~2% + GST on the fee (Razorpay, card / UPI mix -- check the contract)
    "overhead_pct": 15.0,            # servers, support, refunds -- share of net revenue
    "target_margin_pct": 25.0,
}

_HOSTS = {
    "generativelanguage.googleapis.com": "gemini",
    "api.openai.com": "openai",
    "api.anthropic.com": "anthropic",
    "api.sarvam.ai": "sarvam",
    "api.search.brave.com": "brave",
    "google.serper.dev": "serper",
    "api.elevenlabs.io": "elevenlabs",
}

_state: Dict[str, Any] = {"db": None, "lock": threading.Lock(), "installed": False}


def install(db_path: str) -> None:
    """Point the meter at ``db_path`` and hook httpx once (idempotent; safe in tests)."""
    import httpx

    with closing(sqlite3.connect(db_path)) as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        conn.commit()
    _state["db"] = db_path
    if _state["installed"]:
        return
    original = httpx.Client.send

    def send(self, request, *args, **kwargs):  # type: ignore[no-untyped-def]
        response = original(self, request, *args, **kwargs)
        try:
            provider = _HOSTS.get(request.url.host or "")
            if provider:
                observe(provider, request, response, streamed=bool(kwargs.get("stream")))
        except Exception:  # metering must never break a provider call
            _log.debug("ai_usage_meter.observe failed", exc_info=True)
        return response

    httpx.Client.send = send  # type: ignore[assignment]
    _state["installed"] = True


def _json(raw: bytes) -> Dict[str, Any]:
    try:
        out = json.loads(raw.decode("utf-8", "ignore") or "{}")
        return out if isinstance(out, dict) else {}
    except ValueError:
        return {}


def _request_bytes(request: Any) -> bytes:
    try:
        return bytes(request.content or b"")
    except Exception:  # streaming request body: not available
        return b""


def _wav_seconds(raw: bytes) -> Optional[float]:
    idx = raw.find(b"RIFF")
    if idx < 0 or raw[idx + 8: idx + 12] != b"WAVE":
        return None
    try:
        byte_rate = int.from_bytes(raw[idx + 28: idx + 32], "little")
        data_at = raw.find(b"data", idx + 12)
        size = int.from_bytes(raw[data_at + 4: data_at + 8], "little")
        return round(size / byte_rate, 2) if byte_rate > 0 else None
    except Exception:
        return None


def observe(provider: str, request: Any, response: Any, *, streamed: bool = False) -> Optional[Dict[str, Any]]:
    """Turns one provider round trip into counts (public for tests)."""
    path = urlparse(str(request.url)).path
    body = _request_bytes(request)
    ok = 200 <= int(getattr(response, "status_code", 0) or 0) < 300
    reply = {} if streamed else _json(getattr(response, "content", b"") or b"")
    row: Dict[str, Any] = {"provider": provider, "model": "", "feature": "chat", "input_tokens": 0,
                           "output_tokens": 0, "chars": 0, "seconds": 0.0, "ok": ok}
    lowered = body[:200_000].lower()
    media = b"inline_data" in lowered or b"inlinedata" in lowered or b"filedata" in lowered \
        or b"file_data" in lowered or b"input_image" in lowered
    if provider == "gemini":
        if "/upload/" in path or ":generate" not in path and ":stream" not in path:
            return None  # file uploads / model listing: not an AI answer
        row["model"] = path.split("/models/", 1)[-1].split(":", 1)[0]
        usage = reply.get("usageMetadata") or {}
        row["input_tokens"] = int(usage.get("promptTokenCount") or 0)
        row["output_tokens"] = int(usage.get("candidatesTokenCount") or 0) + int(usage.get("thoughtsTokenCount") or 0)
        if media:
            row["feature"] = "voice_in" if b"audio/" in lowered else "image"
    elif provider in ("openai", "anthropic"):
        sent = _json(body)
        row["model"] = str(sent.get("model") or "")
        usage = reply.get("usage") or {}
        row["input_tokens"] = int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0)
        row["output_tokens"] = int(usage.get("output_tokens") or usage.get("completion_tokens") or 0)
        if media or b'"type": "image"' in lowered or b'"type":"image"' in lowered:
            row["feature"] = "image"
    elif provider == "sarvam":
        if "speech-to-text" in path:
            row["feature"], row["model"] = "voice_in", "stt"
            seconds = _wav_seconds(body)
            row["seconds"] = seconds if seconds is not None else round(len(body) / 4000, 1)  # ~32 kbps estimate
        elif "text-to-speech" in path:
            sent = _json(body)
            text = sent.get("text") or sent.get("inputs") or ""
            row["feature"], row["model"] = "voice_out", str(sent.get("model") or "tts")
            row["chars"] = len("".join(text) if isinstance(text, list) else str(text))
        else:
            row["model"] = path.strip("/").split("/")[0] or "other"
            usage = reply.get("usage") or {}
            row["input_tokens"] = int(usage.get("prompt_tokens") or 0)
            row["output_tokens"] = int(usage.get("completion_tokens") or 0)
    elif provider == "elevenlabs":
        if "text-to-speech" not in path:
            return None
        sent = _json(body)
        row["feature"], row["model"] = "voice_out", str(sent.get("model_id") or "tts")
        row["chars"] = len(str(sent.get("text") or ""))
    elif provider == "brave":
        row["feature"], row["model"] = "web_search", path.rsplit("/", 2)[-2] if path.count("/") >= 2 else "search"
    elif provider == "serper":
        row["feature"], row["model"] = "web_search", path.strip("/") or "search"
    record(**row)
    return row


def record(*, provider: str, model: str, feature: str, input_tokens: int = 0, output_tokens: int = 0,
           chars: int = 0, seconds: float = 0.0, ok: bool = True, day: Optional[str] = None) -> None:
    db = _state.get("db")
    if not db:
        return
    day = day or datetime.now(timezone.utc).date().isoformat()
    with _state["lock"], closing(sqlite3.connect(db, timeout=5)) as conn:
        conn.execute(
            "INSERT INTO ai_usage_daily(day, feature, provider, model, calls, errors, input_tokens, output_tokens,"
            " chars, seconds) VALUES(?,?,?,?,1,?,?,?,?,?) ON CONFLICT(day, feature, provider, model) DO UPDATE SET"
            " calls = calls + 1, errors = errors + excluded.errors, input_tokens = input_tokens + excluded.input_tokens,"
            " output_tokens = output_tokens + excluded.output_tokens, chars = chars + excluded.chars,"
            " seconds = seconds + excluded.seconds",
            (day, feature, provider, (model or "-")[:60], 0 if ok else 1, int(input_tokens), int(output_tokens),
             int(chars), float(seconds)))
        conn.commit()


# ------------------------------------------------------------------ prices / report --
def prices(db_path: str) -> Dict[str, Any]:
    with closing(sqlite3.connect(db_path)) as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        row = conn.execute("SELECT data, updated_by, updated_at FROM ai_usage_prices WHERE id = 1").fetchone()
    data = json.loads(row[0]) if row else {}
    out = json.loads(json.dumps(DEFAULT_PRICES))
    for key, value in data.items():
        if key in out:
            out[key] = value
    out["updated_by"], out["updated_at"] = (row[1], row[2]) if row else ("", "")
    return out


def save_prices(db_path: str, data: Dict[str, Any], *, actor: str) -> Dict[str, Any]:
    current = {k: v for k, v in prices(db_path).items() if k in DEFAULT_PRICES}
    for key, value in data.items():
        if key not in DEFAULT_PRICES:
            raise ValueError(f"unknown price key {key}")
        if isinstance(DEFAULT_PRICES[key], (int, float)):
            number = float(value)
            if number < 0 or number > 100_000:
                raise ValueError(f"{key} out of range")
            current[key] = number
        elif key == "tokens_usd_per_million":
            table = {}
            for model, pair in dict(value).items():
                a, b = (float(pair[0]), float(pair[1]))
                if a < 0 or b < 0 or a > 1000 or b > 1000:
                    raise ValueError(f"price for {model} out of range")
                table[str(model)[:60]] = [a, b]
            table.setdefault("default", DEFAULT_PRICES[key]["default"])
            current[key] = table
    with closing(sqlite3.connect(db_path)) as conn:
        conn.execute("INSERT INTO ai_usage_prices(id, data, updated_by, updated_at) VALUES(1, ?, ?, ?) ON CONFLICT(id)"
                     " DO UPDATE SET data = excluded.data, updated_by = excluded.updated_by,"
                     " updated_at = excluded.updated_at",
                     (json.dumps(current), actor, datetime.now(timezone.utc).isoformat()))
        conn.commit()
    return prices(db_path)


def _token_price(table: Dict[str, List[float]], model: str) -> List[float]:
    best = ""
    for prefix in table:
        if prefix != "default" and model.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    return table[best] if best else table.get("default", [1.0, 5.0])


def cost_inr(p: Dict[str, Any], row: Dict[str, Any]) -> float:
    """Estimated rupees for an aggregate row, including GST on imported AI services."""
    fx = float(p["usd_inr"])
    if row["provider"] == "sarvam" and row["feature"] == "voice_in":
        base = row["seconds"] / 60.0 * float(p["stt_inr_per_minute"])
    elif row["provider"] == "sarvam" and row["feature"] == "voice_out":
        base = row["chars"] / 1000.0 * float(p["tts_inr_per_1000_chars"])
    elif row["provider"] == "elevenlabs":
        base = row["chars"] / 1000.0 * float(p.get("elevenlabs_usd_per_1000_chars", 0.15)) * fx
    elif row["provider"] == "brave":
        base = row["calls"] / 1000.0 * float(p["search_usd_per_1000"]) * fx
    elif row["provider"] == "serper":
        base = row["calls"] / 1000.0 * float(p.get("serper_usd_per_1000", 1.0)) * fx
    else:
        price_in, price_out = _token_price(p["tokens_usd_per_million"], row["model"])
        base = (row["input_tokens"] * price_in + row["output_tokens"] * price_out) / 1e6 * fx
    imported = row["provider"] in ("gemini", "openai", "anthropic", "brave", "serper", "elevenlabs")
    return base * (1 + float(p["gst_on_imports_pct"]) / 100.0 if imported else 1)


def markup(p: Dict[str, Any]) -> float:
    """User price / our AI cost so that the target margin is left after sale GST, gateway fee and overheads."""
    net = 1 / (1 + float(p["sale_gst_pct"]) / 100.0)                       # of every rupee the user pays
    after_fee = net - float(p["gateway_fee_pct"]) / 100.0
    ai_share = after_fee - net * (float(p["target_margin_pct"]) + float(p["overhead_pct"])) / 100.0
    return round(1 / ai_share, 2) if ai_share > 0 else float("inf")


def report(db_path: str, *, days: int = 7) -> Dict[str, Any]:
    p = prices(db_path)
    since = (datetime.now(timezone.utc).date() - timedelta(days=max(1, days) - 1)).isoformat()
    with closing(sqlite3.connect(db_path)) as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        conn.row_factory = sqlite3.Row
        rows = [dict(r) for r in conn.execute(
            "SELECT feature, provider, model, SUM(calls) AS calls, SUM(errors) AS errors, SUM(input_tokens) AS"
            " input_tokens, SUM(output_tokens) AS output_tokens, SUM(chars) AS chars, SUM(seconds) AS seconds FROM"
            " ai_usage_daily WHERE day >= ? GROUP BY feature, provider, model ORDER BY feature, calls DESC",
            (since,)).fetchall()]
    factor = markup(p)
    by_feature: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        r["cost_inr"] = round(cost_inr(p, r), 2)
        f = by_feature.setdefault(r["feature"], {"feature": r["feature"], "calls": 0, "cost_inr": 0.0})
        f["calls"] += r["calls"]
        f["cost_inr"] += r["cost_inr"]
    for f in by_feature.values():
        per = f["cost_inr"] / f["calls"] if f["calls"] else 0.0
        f["cost_inr"] = round(f["cost_inr"], 2)
        f["cost_per_use_paise"] = round(per * 100, 2)
        f["suggested_rate_paise"] = int(math.ceil(per * 100 * factor)) if per > 0 and factor != float("inf") else 0
    return {"since": since, "days": days, "rows": rows, "features": sorted(by_feature.values(), key=lambda x: x["feature"]),
            "markup": factor, "prices": p,
            "basis": "ESTIMATE: provider-reported usage x the price table below; compare with the provider's bill."}
