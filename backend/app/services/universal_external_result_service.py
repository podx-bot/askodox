"""Resolve user-facing online results from normal and affiliate mappings."""
from __future__ import annotations

from urllib.parse import quote_plus, urlparse
from typing import Any, Iterable


class UniversalExternalResultService:
    """Convert configured external mappings into source-neutral online results.

    Mapping order and explicit relevance metadata are preserved; commission data
    is never read or used for ranking.
    """

    @staticmethod
    def resolve(
        *,
        category: str,
        subject: str,
        providers: Iterable[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        wanted = {str(category or "").strip().casefold(), str(subject or "").strip().casefold()}
        wanted.discard("")
        results: list[dict[str, Any]] = []
        for provider in providers:
            if not provider.get("active", True):
                continue
            provider_category = str(provider.get("category") or "").strip().casefold()
            if provider_category and provider_category not in wanted and provider_category not in {"general", "product"}:
                continue

            normal_url = UniversalExternalResultService._http_url(
                provider.get("normal_url") or provider.get("destination_url") or provider.get("base_url")
            )
            affiliate_url = UniversalExternalResultService._template_url(
                provider.get("affiliate_url") or provider.get("affiliate_url_template"),
                subject,
            )
            destination = affiliate_url or normal_url
            if not destination:
                continue

            is_affiliate = bool(affiliate_url)
            results.append(
                {
                    "id": f"online-{provider.get('provider_id') or provider.get('name') or len(results)}",
                    "match_id": f"online-{provider.get('provider_id') or provider.get('name') or len(results)}",
                    "provider_id": str(provider.get("provider_id") or provider.get("name") or "online-provider"),
                    "title": str(provider.get("name") or provider.get("provider_id") or "Online option"),
                    "subtitle": str(provider.get("description") or "Verified online destination"),
                    "score": float(provider.get("relevance_score") or 0.35),
                    "match_source": "online",
                    "source": "online",
                    "destination_url": destination,
                    "affiliate": is_affiliate,
                    "disclosure": str(provider.get("disclosure") or ("Affiliate link" if is_affiliate else "")),
                    "demo": False,
                }
            )
        return results

    @staticmethod
    def _template_url(value: Any, subject: str) -> str | None:
        if not value:
            return None
        return UniversalExternalResultService._http_url(
            str(value).replace("{query}", quote_plus(str(subject or "").strip()))
        )

    @staticmethod
    def _http_url(value: Any) -> str | None:
        url = str(value or "").strip()
        if url.startswith("https://") or url.startswith("http://"):
            return url
        return None


# Domains where a "watch a video about it" result is not meaningful (a ride,
# a parcel run or a job opening is not something people review on video).
_NO_VIDEO_DOMAINS = {
    "RIDE", "MOBILITY", "DELIVERY", "COURIER", "PARCEL", "WORK", "WORKERS", "JOBS", "JOB",
}

_VIDEO_HOSTS = ("youtube.com", "youtu.be", "instagram.com", "facebook.com", "fb.watch")


def _host(url: str) -> str:
    try:
        return (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""


def _is_video_host(url: str) -> bool:
    host = _host(url)
    return any(host == item or host.endswith("." + item) for item in _VIDEO_HOSTS)


class UniversalOnlineFallbackService:
    """Online + video results shown in chat when no genuine local match exists.

    Uses the already-configured Brave web provider (the same one Live
    Research uses) when it has an API key, so results are real pages. When
    the provider is not configured or returns nothing, it falls back to plain,
    clearly-labelled search links -- never fabricated products, prices or
    sellers.
    """

    def __init__(self, web_search=None) -> None:
        self.web_search = web_search

    @property
    def _search_configured(self) -> bool:
        return callable(self.web_search) and bool(getattr(self.web_search, "configured", True))

    def online(self, *, category: str, subject: str, limit: int = 4) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject:
            return []
        results: list[dict[str, Any]] = []
        if self._search_configured:
            for row in self._search(f"{subject} price buy online", limit * 2):
                url = UniversalExternalResultService._http_url(row.get("url"))
                if not url or _is_video_host(url):
                    continue
                results.append(self._row("online", len(results), row.get("title"), row.get("snippet"), url))
                if len(results) >= limit:
                    break
        if results:
            return results
        return [
            self._row(
                "online",
                0,
                f"Search online for {subject}",
                "No verified local match yet -- compare prices and sellers online.",
                f"https://www.google.com/search?q={quote_plus(subject + ' price')}",
            )
        ]

    def videos(self, *, category: str, subject: str, limit: int = 3) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject or str(category or "").strip().upper() in _NO_VIDEO_DOMAINS:
            return []
        results: list[dict[str, Any]] = []
        if self._search_configured:
            for row in self._search(f"{subject} review video", limit * 4):
                url = UniversalExternalResultService._http_url(row.get("url"))
                if not url or not _is_video_host(url):
                    continue
                results.append(self._row("video", len(results), row.get("title"), row.get("snippet"), url))
                if len(results) >= limit:
                    break
        if results:
            return results
        query = quote_plus(f"{subject} review")
        return [
            self._row("video", 0, f"{subject} reviews on YouTube", "Watch video reviews and demos.",
                      f"https://www.youtube.com/results?search_query={query}"),
            self._row("video", 1, f"{subject} on Instagram", "Reels and creator posts.",
                      f"https://www.instagram.com/explore/search/keyword/?q={quote_plus(subject)}"),
        ][:limit]

    def _search(self, query: str, limit: int) -> list[dict[str, Any]]:
        try:
            rows = self.web_search(query, limit)
        except Exception:  # provider failures must never break matching
            return []
        return [row for row in rows or [] if isinstance(row, dict)]

    @staticmethod
    def _row(kind: str, index: int, title: Any, subtitle: Any, url: str) -> dict[str, Any]:
        host = _host(url).removeprefix("www.")
        return {
            "id": f"{kind}-{index}-{host or 'link'}",
            "match_id": f"{kind}-{index}-{host or 'link'}",
            "provider_id": host,
            "title": str(title or host or "Online option").strip()[:160],
            "subtitle": str(subtitle or "").strip()[:280],
            "score": None,
            "match_source": kind,
            "source": kind,
            "destination_url": url,
            "affiliate": False,
            "disclosure": "",
            "fallback": True,
            "demo": False,
        }
