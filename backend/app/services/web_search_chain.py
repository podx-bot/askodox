"""Web search that does not depend on ONE provider.

``WebSearchChain`` calls its providers in order and moves to the next one
only when a provider FAILS (error / quota / breaker open) -- never because a
provider honestly found nothing. Every provider keeps the same interface as
``BraveWebSearchProvider`` (callable ``(query, limit) -> rows``, ``videos``,
``configured``, per-thread ``last_error`` / ``last_stale_at``), so discovery
code is unchanged. Rows are never fabricated: a chain where every provider
failed returns [] with ``last_error`` set, exactly like a single provider.

``GoogleCseProvider`` = Google Programmable Search (Custom Search JSON API),
configured with ``GOOGLE_CSE_API_KEY`` + ``GOOGLE_CSE_ID`` (backend-only).
"""
from __future__ import annotations

import threading
from typing import Any, Callable, Iterable, List, Optional

from app.services.provider_failure import failure_kind


class GoogleCseProvider:
    API_URL = "https://www.googleapis.com/customsearch/v1"
    name = "google_cse"

    def __init__(self, api_key: str, cx: str, *, country: str = "IN", timeout_seconds: int = 8,
                 http_get: Optional[Callable[..., Any]] = None) -> None:
        self.api_key = str(api_key or "").strip()
        self.cx = str(cx or "").strip()
        self.country = str(country or "").strip().lower()
        self.timeout_seconds = max(1, int(timeout_seconds))
        self._http_get = http_get
        self._local = threading.local()
        self.health: dict[str, Any] = {"state": "unknown" if self.configured else "not_configured"}

    @property
    def configured(self) -> bool:
        return bool(self.api_key and self.cx)

    @property
    def last_error(self) -> bool:
        return bool(getattr(self._local, "error", False))

    @last_error.setter
    def last_error(self, value: bool) -> None:
        self._local.error = bool(value)

    last_stale_at = None

    def _get(self, params: dict) -> Any:
        if self._http_get is not None:
            return self._http_get(self.API_URL, params=params, timeout=self.timeout_seconds)
        import httpx

        response = httpx.get(self.API_URL, params=params, timeout=self.timeout_seconds,
                             headers={"User-Agent": "ASKODOX/2.0"})
        if response.status_code != 200:
            raise RuntimeError(f"HTTP {response.status_code}")
        return response.json()

    def __call__(self, query: str, limit: int) -> List[dict]:
        self.last_error = False
        if not self.configured:
            return []
        q = " ".join(str(query or "").split())
        if not q:
            return []
        params = {"key": self.api_key, "cx": self.cx, "q": q, "num": max(1, min(int(limit), 10))}
        if self.country:
            params["gl"] = self.country
        try:
            payload = self._get(params) or {}
        except Exception as error:  # quota / network / auth: a FAILURE, never "no results"
            self.last_error = True
            self.health = {"state": "error", "error": type(error).__name__}
            return []
        self.health = {"state": "ok"}
        rows = []
        for item in payload.get("items") or []:
            if not isinstance(item, dict):
                continue
            url, title = str(item.get("link") or "").strip(), str(item.get("title") or "").strip()
            snippet = str(item.get("snippet") or "").strip()
            if not (url and title and snippet):
                continue
            thumbs = ((item.get("pagemap") or {}).get("cse_thumbnail") or [{}])
            rows.append({"title": title, "url": url, "snippet": snippet,
                         "thumbnail": (thumbs[0] or {}).get("src") if thumbs else None,
                         "host": item.get("displayLink") or None, "source_type": "web",
                         "provider": self.name})
        return rows

    def videos(self, query: str, limit: int) -> List[dict]:
        return []  # videos come from YouTube Data / Brave; CSE is web only


class WebSearchChain:
    """Providers in order; the next one is used only when the previous FAILED."""

    def __init__(self, providers: Iterable[Any]) -> None:
        self.providers = [p for p in providers if p is not None]
        self._local = threading.local()

    @property
    def primary(self) -> Any:
        return self.providers[0] if self.providers else None

    @property
    def configured(self) -> bool:
        return any(getattr(p, "configured", True) for p in self.providers)

    @property
    def last_error(self) -> bool:
        return bool(getattr(self._local, "error", False))

    @last_error.setter
    def last_error(self, value: bool) -> None:
        self._local.error = bool(value)

    @property
    def last_error_kind(self) -> Optional[str]:
        return getattr(self._local, "error_kind", None)

    @property
    def last_stale_at(self) -> Optional[str]:
        return getattr(self._local, "stale_at", None)

    @property
    def last_provider(self) -> Optional[str]:
        return getattr(self._local, "provider", None)

    def _run(self, method: str, query: str, limit: int) -> List[dict]:
        self.last_error = False
        self._local.error_kind = None
        self._local.stale_at = None
        self._local.provider = None
        failed = False
        kind = None
        for provider in self.providers:
            if not getattr(provider, "configured", True):
                continue
            call = provider if method == "__call__" else getattr(provider, method, None)
            if not callable(call):
                continue
            try:
                rows = call(query, limit) or []
            except Exception:
                rows, failed = [], True
                kind = kind or "error"
                continue
            stale = getattr(provider, "last_stale_at", None)
            if getattr(provider, "last_error", False) or (stale and method == "__call__" and not rows):
                failed = True
                # The primary's reason wins (the fallback only filled in).
                kind = kind or failure_kind(provider) or "error"
                continue
            if stale and rows and method == "__call__":
                # A stale copy from one provider: prefer a LIVE answer from the next.
                live = self._next_live(provider, query, limit)
                if live is not None:
                    return live
                self._local.stale_at = stale
            self._local.provider = getattr(provider, "name", type(provider).__name__)
            return rows
        self.last_error = failed
        self._local.error_kind = kind if failed else None
        return []

    def _next_live(self, after: Any, query: str, limit: int) -> Optional[List[dict]]:
        seen = False
        for provider in self.providers:
            if provider is after:
                seen = True
                continue
            if not seen or not getattr(provider, "configured", True):
                continue
            try:
                rows = provider(query, limit) or []
            except Exception:
                continue
            if not getattr(provider, "last_error", False) and rows:
                self._local.provider = getattr(provider, "name", type(provider).__name__)
                return rows
        return None

    def __call__(self, query: str, limit: int) -> List[dict]:
        return self._run("__call__", query, limit)

    def videos(self, query: str, limit: int) -> List[dict]:
        return self._run("videos", query, limit)

    def health_snapshot(self) -> dict:
        snap = dict(self.primary.health_snapshot()) if hasattr(self.primary, "health_snapshot") else {}
        snap["fallbacks"] = {getattr(p, "name", type(p).__name__): (getattr(p, "health", {}) or {}).get("state")
                             for p in self.providers[1:]}
        return snap


def build_chain(primary: Any, env: Optional[dict] = None, *, country: str = "IN") -> WebSearchChain:
    import os

    from app.services.commerce_finance import env_value

    env = dict(os.environ) if env is None else env
    cse = GoogleCseProvider(env_value(env, "google_cse", "api_key"), env_value(env, "google_cse", "cx"),
                            country=country)
    return WebSearchChain([primary, cse])
