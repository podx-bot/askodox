"""Serper (Google results) as the PRIMARY web-search provider (owner decision
2026-10-29: Serper first, Brave second -- about 5x cheaper per search and
Google's index finds new launches / India pages quickly).

Same interface as ``BraveWebSearchProvider`` so ``WebSearchChain`` and every
caller stay unchanged: callable ``(query, limit) -> rows``, ``videos``,
``configured``, per-thread ``last_error`` / ``last_error_kind`` /
``last_stale_at``, ``health`` and ``health_snapshot()``. Rows are never
fabricated: a failure returns [] with ``last_error`` set, so the chain moves on
to Brave. Calls go through ``external_call_budget`` (shared cache + usage).

Key: ``SERPER_API_KEY`` (backend only, read via ``commerce_finance.env_value``).
"""
from __future__ import annotations

import re
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, List, Optional

from app.services import external_call_budget

_REL = re.compile(r"(\d+)\s+(minute|min|hour|day|week|month|year)s?\s+ago", re.IGNORECASE)
_UNIT_DAYS = {"minute": 1 / 1440, "min": 1 / 1440, "hour": 1 / 24, "day": 1, "week": 7, "month": 30, "year": 365}


def parse_date(text: Any, now: Optional[datetime] = None) -> Optional[str]:
    """'3 days ago' / 'Oct 22, 2026' / ISO -> ISO UTC, else None (never guessed)."""
    value = str(text or "").strip()
    if not value:
        return None
    moment = now or datetime.now(timezone.utc)
    match = _REL.search(value)
    if match:
        days = int(match.group(1)) * _UNIT_DAYS[match.group(2).lower()]
        return (moment - timedelta(days=days)).replace(microsecond=0).isoformat()
    for fmt in ("%b %d, %Y", "%d %b %Y", "%B %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt).replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            continue
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).isoformat()
    except ValueError:
        return None


class SerperWebSearchProvider:
    API_URL = "https://google.serper.dev/search"
    VIDEO_URL = "https://google.serper.dev/videos"
    name = "serper"

    def __init__(self, api_key: str, *, country: str = "IN", timeout_seconds: int = 8,
                 http_post: Optional[Callable[..., Any]] = None) -> None:
        self.api_key = str(api_key or "").strip()
        self.country = str(country or "").strip().lower()
        self.timeout_seconds = max(1, int(timeout_seconds))
        self._http_post = http_post
        self._local = threading.local()
        self._open_until = 0.0
        self.health: dict[str, Any] = {"state": "unknown" if self.configured else "not_configured"}

    # ------------------------------------------------------------- state --
    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    @property
    def last_error(self) -> bool:
        return bool(getattr(self._local, "error", False))

    @last_error.setter
    def last_error(self, value: bool) -> None:
        self._local.error = bool(value)

    @property
    def last_error_kind(self) -> Optional[str]:
        return getattr(self._local, "error_kind", None)

    last_stale_at = None

    def health_snapshot(self) -> dict[str, Any]:
        snap = dict(self.health)
        if self._open_until > time.monotonic():
            snap["paused_for_seconds"] = int(self._open_until - time.monotonic())
        return snap

    def _fail(self, state: str, http_status: Optional[int] = None, pause: float = 0.0) -> None:
        self.last_error = True
        self._local.error_kind = state
        self.health = {"state": state, "http_status": http_status, "at": datetime.now(timezone.utc).isoformat(),
                       "last_ok_at": self.health.get("last_ok_at")}
        if pause:
            self._open_until = time.monotonic() + pause

    # -------------------------------------------------------------- http --
    def _post(self, url: str, body: dict[str, Any]) -> Optional[dict[str, Any]]:
        self.last_error = False
        self._local.error_kind = None
        if not self.configured:
            return None
        if self._open_until > time.monotonic():
            self.last_error = True
            self._local.error_kind = str(self.health.get("state") or "error")
            external_call_budget.record_error("serper")
            return None

        def fetch() -> Any:
            if self._http_post is not None:
                response = self._http_post(url, json=body, headers={"X-API-KEY": self.api_key},
                                           timeout=self.timeout_seconds)
            else:
                import httpx

                response = httpx.post(url, json=body, timeout=self.timeout_seconds,
                                      headers={"X-API-KEY": self.api_key, "Content-Type": "application/json",
                                               "User-Agent": "ASKODOX/2.0"})
            status = int(getattr(response, "status_code", 200) or 200)
            if status >= 400:
                text = ""
                try:
                    text = str(response.text or "")[:200].lower()
                except Exception:
                    pass
                if status == 402 or "credit" in text or "quota" in text:
                    self._fail("quota_exhausted", status, pause=3600)
                elif status in (401, 403):
                    self._fail("auth_failed", status, pause=600)
                elif status == 429:
                    self._fail("rate_limited", status)
                elif status in (400, 422):
                    self._fail("bad_request", status)
                else:
                    self._fail("error", status)
                raise RuntimeError(f"serper HTTP {status}")
            payload = response.json()
            self.health = {"state": "ok", "http_status": status, "at": datetime.now(timezone.utc).isoformat(),
                           "last_ok_at": datetime.now(timezone.utc).isoformat(),
                           **({"credits_left": payload.get("credits")} if isinstance(payload, dict)
                              and payload.get("credits") is not None else {})}
            return payload

        key = (url, tuple(sorted((k, str(v)) for k, v in body.items())))
        try:
            payload = external_call_budget.cached_call("serper", key, fetch)
        except Exception as error:
            if not self.last_error:  # network / parse problem, not an HTTP answer
                self._fail("error")
                self.health["error"] = type(error).__name__
            return None
        return payload if isinstance(payload, dict) else None

    def _body(self, query: str, limit: int) -> dict[str, Any]:
        body: dict[str, Any] = {"q": query, "num": max(1, min(int(limit), 20))}
        if self.country:
            body["gl"] = self.country
        return body

    # ----------------------------------------------------------- results --
    def __call__(self, query: str, limit: int) -> List[dict]:
        q = " ".join(str(query or "").split())
        if not q or not self.configured:
            self.last_error = False
            return []
        count = max(1, min(int(limit), 20))
        payload = self._post(self.API_URL, self._body(q, count))
        if payload is None:
            return []
        rows: List[dict] = []
        seen: set[str] = set()

        def add(item: dict, source_type: str) -> None:
            url = str(item.get("link") or "").strip()
            title = str(item.get("title") or "").strip()
            snippet = str(item.get("snippet") or item.get("source") or "").strip()
            if not (url and title and snippet) or url in seen:
                return
            seen.add(url)
            host = re.sub(r"^https?://(www\.)?", "", url).split("/")[0] or None
            rows.append({"title": title, "url": url, "snippet": snippet,
                         "published_at": parse_date(item.get("date")), "source_type": source_type,
                         "thumbnail": item.get("imageUrl") or None, "host": host, "provider": self.name})

        for item in payload.get("organic") or []:
            if isinstance(item, dict):
                add(item, "web")
        # Fresh news (launches, leaks) Google shows above the results.
        for item in payload.get("topStories") or []:
            if isinstance(item, dict):
                add(item, "news")
        return rows[:count]

    def videos(self, query: str, limit: int) -> List[dict]:
        q = " ".join(str(query or "").split())
        if not q or not self.configured:
            self.last_error = False
            return []
        count = max(1, min(int(limit), 20))
        payload = self._post(self.VIDEO_URL, self._body(q, count))
        if payload is None:
            return []
        out: List[dict] = []
        for row in payload.get("videos") or []:
            if not isinstance(row, dict):
                continue
            url, title = str(row.get("link") or "").strip(), str(row.get("title") or "").strip()
            if not (url and title):
                continue
            out.append({"title": title, "url": url, "snippet": str(row.get("snippet") or "").strip(),
                        "thumbnail": row.get("imageUrl") or None,
                        "creator": str(row.get("channel") or "").strip() or None,
                        "publisher": str(row.get("source") or "").strip() or None,
                        "duration": str(row.get("duration") or "").strip() or None,
                        "host": re.sub(r"^https?://(www\.)?", "", url).split("/")[0] or None})
        return out[:count]
