"""Brave Search API provider for ASKODOX live research."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx


class BraveWebSearchProvider:
    API_URL = "https://api.search.brave.com/res/v1/web/search"

    def __init__(self, api_key: str, *, timeout_seconds: int = 8, client: httpx.Client | None = None) -> None:
        self.api_key = str(api_key or "").strip()
        self.timeout_seconds = max(1, int(timeout_seconds))
        self.client = client

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
        params = {"q": clean_query, "count": count, "text_decorations": False, "safesearch": "moderate"}
        try:
            if self.client is not None:
                response = self.client.get(self.API_URL, headers=headers, params=params)
            else:
                with httpx.Client(timeout=self.timeout_seconds, follow_redirects=True) as client:
                    response = client.get(self.API_URL, headers=headers, params=params)
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError, TypeError):
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
            })
        return results

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
