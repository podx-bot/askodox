"""Brave Search API provider for ASKODOX live research.

Resilience (one search provider reaching its limit must not break ASKODOX):

* Every failure is recorded with what Brave actually said -- HTTP status,
  Brave's error code and its rate-limit headers -- in ``health`` (no
  secrets), so "quota exhausted" is never confused with "bad key".
* Errors are tracked per thread: discovery runs sources in parallel and a
  shared flag let one source's failure mark another as failed.
* Calls are paced to the plan's per-second limit (learned from Brave's
  ``X-RateLimit-Limit`` header) and a per-second 429 is retried once.
* A circuit breaker stops calling Brave while a monthly quota is exhausted
  (until Brave's reset) or the key is rejected -- no wasted latency.
* While Brave is unavailable, the last REAL response for the same query (if
  one was fetched in the last few days) is returned and marked stale with
  its fetch time; nothing is ever invented.
"""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx

from app.services import external_call_budget

STALE_MAX_AGE = timedelta(days=3)
STALE_MAX_ROWS = 3000


class LastGoodStore:
    """Last successful Brave payload per query (sqlite, survives deploys)."""

    def __init__(self, db_path: str) -> None:
        self.db_path = db_path
        with sqlite3.connect(db_path) as conn:
            conn.execute("CREATE TABLE IF NOT EXISTS search_last_good (cache_key TEXT PRIMARY KEY, "
                         "payload_json TEXT NOT NULL, fetched_at TEXT NOT NULL)")

    def save(self, key: str, payload: Any) -> None:
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("INSERT OR REPLACE INTO search_last_good VALUES (?,?,?)",
                             (key, json.dumps(payload)[:400_000], datetime.now(timezone.utc).isoformat()))
                conn.execute("DELETE FROM search_last_good WHERE cache_key NOT IN (SELECT cache_key FROM "
                             "search_last_good ORDER BY fetched_at DESC LIMIT ?)", (STALE_MAX_ROWS,))
        except (sqlite3.Error, TypeError, ValueError):
            pass

    def load(self, key: str) -> tuple[Any, str] | None:
        try:
            with sqlite3.connect(self.db_path) as conn:
                row = conn.execute("SELECT payload_json, fetched_at FROM search_last_good WHERE cache_key=?",
                                   (key,)).fetchone()
        except sqlite3.Error:
            return None
        if not row:
            return None
        fetched = datetime.fromisoformat(row[1])
        if datetime.now(timezone.utc) - fetched > STALE_MAX_AGE:
            return None
        return json.loads(row[0]), row[1]


def _rate_headers(headers: Any) -> dict[str, Any]:
    """Brave sends ``X-RateLimit-Limit: 1, 2000`` (per second, per month) and
    matching Remaining / Reset (seconds) headers."""
    out: dict[str, Any] = {}
    for name, key in (("x-ratelimit-limit", "limit"), ("x-ratelimit-remaining", "remaining"),
                      ("x-ratelimit-reset", "reset")):
        raw = str((headers or {}).get(name) or "").strip()
        if raw:
            try:
                out[key] = [int(float(x)) for x in raw.split(",") if x.strip()]
            except ValueError:
                out[key] = raw
    return out


class BraveWebSearchProvider:
    API_URL = "https://api.search.brave.com/res/v1/web/search"
    VIDEO_URL = "https://api.search.brave.com/res/v1/videos/search"

    def __init__(
        self,
        api_key: str,
        *,
        timeout_seconds: int = 8,
        client: httpx.Client | None = None,
        country: str = "IN",
        search_lang: str = "en",
    ) -> None:
        self.api_key = str(api_key or "").strip()
        self.timeout_seconds = max(1, int(timeout_seconds))
        self.client = client
        # ASKODOX serves India first: without a country Brave answers from
        # its default (US) index -- Home Depot for "AC service Vijayawada".
        self.country = str(country or "").strip().upper()
        self.search_lang = str(search_lang or "").strip().lower()
        self._local = threading.local()
        self._lock = threading.Lock()
        self._next_slot = 0.0
        self._min_interval = 0.0  # learned from X-RateLimit-Limit (per second)
        self._open_until = 0.0
        self.store: LastGoodStore | None = None
        self.health: dict[str, Any] = {"state": "unknown" if self.api_key else "not_configured"}

    # Per-thread: discovery runs sources in parallel.
    @property
    def last_error(self) -> bool:
        return bool(getattr(self._local, "error", False))

    @last_error.setter
    def last_error(self, value: bool) -> None:
        self._local.error = bool(value)

    @property
    def last_stale_at(self) -> str | None:
        """Fetch time of the stored result returned instead of a live one."""
        return getattr(self._local, "stale_at", None)

    def attach_store(self, store: "LastGoodStore | None") -> None:
        self.store = store

    def health_snapshot(self) -> dict[str, Any]:
        with self._lock:
            snap = dict(self.health)
        if self._open_until > time.monotonic():
            snap["paused_for_seconds"] = int(self._open_until - time.monotonic())
        return snap

    def _record(self, **fields: Any) -> None:
        with self._lock:
            self.health.update(fields, at=datetime.now(timezone.utc).isoformat())

    def _pace(self) -> None:
        if self._min_interval <= 0:
            return
        with self._lock:
            now = time.monotonic()
            wait = max(0.0, self._next_slot - now)
            self._next_slot = max(now, self._next_slot) + self._min_interval
        if wait:
            time.sleep(min(wait, 3.0))

    def _learn(self, rate: dict[str, Any]) -> None:
        limits = rate.get("limit")
        if isinstance(limits, list) and limits and limits[0] > 0:
            self._min_interval = 1.0 / limits[0] + 0.05

    def _locale_params(self) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if self.country:
            params["country"] = self.country
        if self.search_lang:
            params["search_lang"] = self.search_lang
        return params

    def _get(self, url: str, headers: dict[str, str], params: dict[str, Any]) -> Any:
        """One real HTTP call, de-duplicated through the shared TTL cache,
        paced, retried once on a per-second 429, short-circuited while a
        quota / auth failure lasts, with the last real result as fallback."""
        key = (url, tuple(sorted((k, str(v)) for k, v in params.items())))
        store_key = json.dumps(key)
        self.last_error = False
        self._local.stale_at = None

        def fetch() -> Any:
            for attempt in (1, 2):
                self._pace()
                if self.client is not None:
                    response = self.client.get(url, headers=headers, params=params)
                else:
                    with httpx.Client(timeout=self.timeout_seconds, follow_redirects=True) as client:
                        response = client.get(url, headers=headers, params=params)
                rate = _rate_headers(getattr(response, "headers", {}))
                self._learn(rate)
                status = int(getattr(response, "status_code", 200) or 200)
                if status == 429 and attempt == 1 and not self._monthly_exhausted(rate):
                    resets = rate.get("reset") if isinstance(rate.get("reset"), list) else []
                    time.sleep(min(max(resets[0] if resets else 1, 1), 2))
                    continue
                if status >= 400:
                    self._failure(response, rate)
                response.raise_for_status()
                payload = response.json()
                self._record(state="ok", http_status=status, rate=rate,
                             last_ok_at=datetime.now(timezone.utc).isoformat(), provider_code=None)
                return payload
            return None

        if self._open_until > time.monotonic():
            self.last_error = True
            external_call_budget.record_error("brave")
            return self._stale(store_key)
        try:
            payload = external_call_budget.cached_call("brave", key, fetch)
        except (httpx.HTTPError, ValueError, TypeError) as error:
            if not isinstance(error, httpx.HTTPStatusError):
                self._record(state="error", http_status=None, provider_code=type(error).__name__)
            self.last_error = True
            return self._stale(store_key)
        if payload and self.store is not None:
            self.store.save(store_key, payload)
        return payload

    @staticmethod
    def _monthly_exhausted(rate: dict[str, Any]) -> bool:
        remaining = rate.get("remaining")
        return isinstance(remaining, list) and len(remaining) > 1 and remaining[1] <= 0

    def _failure(self, response: Any, rate: dict[str, Any]) -> None:
        code = None
        try:
            body = response.json()
            err = (body or {}).get("error") or {}
            code = err.get("code") or (body or {}).get("type")
            detail = str(err.get("detail") or "")[:160] or None
        except Exception:
            detail = None
        status = response.status_code
        upper = str(code or "").upper()
        # Brave answers a used-up monthly plan with 402 CREDIT_EXHAUSTED (seen in
        # production 2026-10-04), older plans with 429 + a USAGE/QUOTA code.
        if status == 402 or (status == 429 and (self._monthly_exhausted(rate) or "USAGE" in upper
                                                or "QUOTA" in upper or "CREDIT" in upper)):
            state = "quota_exhausted"
            resets = rate.get("reset") if isinstance(rate.get("reset"), list) else []
            pause = resets[1] if len(resets) > 1 else 3600
            self._open_until = time.monotonic() + min(max(pause, 60), 6 * 3600)
        elif status == 429:
            state = "rate_limited"
        elif status in (401, 403):
            state = "auth_failed"
            self._open_until = time.monotonic() + 600
        elif status in (400, 422):
            state = "bad_request"
        else:
            state = "error"
        self._record(state=state, http_status=status, provider_code=code, detail=detail, rate=rate)

    def _stale(self, store_key: str) -> Any:
        if self.store is None:
            return None
        found = self.store.load(store_key)
        if not found:
            return None
        payload, fetched_at = found
        # A real earlier result: not an error, but marked stale for callers.
        self.last_error = False
        self._local.stale_at = fetched_at
        return payload

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    def __call__(self, query: str, limit: int) -> list[dict[str, Any]]:
        if not self.configured:
            return []
        clean_query = " ".join(str(query or "").strip().split())
        if not clean_query:
            return []
        count = max(1, min(int(limit), 20))
        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "X-Subscription-Token": self.api_key,
            "User-Agent": "ASKODOX/2.0",
        }
        params = {"q": clean_query, "count": count, "text_decorations": False, "safesearch": "moderate",
                  **self._locale_params()}
        payload = self._get(self.API_URL, headers, params)
        if payload is None:
            return []

        rows = ((payload or {}).get("web") or {}).get("results") or []
        results: list[dict[str, Any]] = []
        for row in rows[:count]:
            if not isinstance(row, dict):
                continue
            url = str(row.get("url") or "").strip()
            title = str(row.get("title") or "").strip()
            snippet = str(row.get("description") or "").strip()
            if not (url and title and snippet):
                continue
            published_at = self._published_at(row)
            results.append({
                "title": title,
                "url": url,
                "snippet": snippet,
                "published_at": published_at,
                "source_type": self._source_type(url),
                # Real page thumbnail (Brave-proxied, key-free) and site name
                # for chat result cards; absent when Brave returns none.
                "thumbnail": ((row.get("thumbnail") or {}).get("src") or None),
                "host": ((row.get("meta_url") or {}).get("hostname") or None),
            })
        return results

    def videos(self, query: str, limit: int) -> list[dict[str, Any]]:
        """Actual videos (title, url, thumbnail, creator, duration) for chat.

        Returns [] when not configured or on any provider failure -- never
        placeholder search links.
        """
        if not self.configured:
            return []
        clean_query = " ".join(str(query or "").strip().split())
        if not clean_query:
            return []
        count = max(1, min(int(limit), 20))
        headers = {
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "X-Subscription-Token": self.api_key,
            "User-Agent": "ASKODOX/2.0",
        }
        params = {"q": clean_query, "count": count, "safesearch": "moderate", **self._locale_params()}
        payload = self._get(self.VIDEO_URL, headers, params)
        if payload is None:
            return []
        videos: list[dict[str, Any]] = []
        for row in ((payload or {}).get("results") or [])[:count]:
            if not isinstance(row, dict):
                continue
            url = str(row.get("url") or "").strip()
            title = str(row.get("title") or "").strip()
            if not (url and title):
                continue
            video = row.get("video") or {}
            videos.append({
                "title": title,
                "url": url,
                "snippet": str(row.get("description") or "").strip(),
                "thumbnail": ((row.get("thumbnail") or {}).get("src") or None),
                "creator": str(video.get("creator") or video.get("publisher") or "").strip() or None,
                "publisher": str(video.get("publisher") or "").strip() or None,
                "duration": str(video.get("duration") or "").strip() or None,
                "host": ((row.get("meta_url") or {}).get("hostname") or None),
            })
        return videos

    @staticmethod
    def _published_at(row: dict[str, Any]) -> str | None:
        value = row.get("page_age") or row.get("age")
        if not value:
            return None
        text = str(value).strip()
        try:
            dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).isoformat()
        except ValueError:
            return None

    @staticmethod
    def _source_type(url: str) -> str:
        host = url.lower()
        if ".gov/" in host or ".gov.in/" in host or host.endswith(".gov") or host.endswith(".gov.in"):
            return "government"
        if "docs." in host or "/docs/" in host or "developer." in host:
            return "documentation"
        return "web"
