"""Brave Search API provider for ASKODOX live research."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx

from app.services import external_call_budget


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
        # True when the most recent call failed at the provider (HTTP/auth/
        # quota), so callers can report "error" instead of "no results".
        self.last_error = False

    def _locale_params(self) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if self.country:
            params["country"] = self.country
        if self.search_lang:
            params["search_lang"] = self.search_lang
        return params

    def _get(self, url: str, headers: dict[str, str], params: dict[str, Any]) -> Any:
        """One real HTTP call, de-duplicated through the shared TTL cache."""
        def fetch() -> Any:
            if self.client is not None:
                response = self.client.get(url, headers=headers, params=params)
            else:
                with httpx.Client(timeout=self.timeout_seconds, follow_redirects=True) as client:
                    response = client.get(url, headers=headers, params=params)
            response.raise_for_status()
            return response.json()

        key = (url, tuple(sorted((k, str(v)) for k, v in params.items())))
        self.last_error = False
        try:
            return external_call_budget.cached_call("brave", key, fetch)
        except (httpx.HTTPError, ValueError, TypeError):
            self.last_error = True
            return None

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
