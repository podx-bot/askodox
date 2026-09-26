"""Resolve user-facing online results from normal and affiliate mappings."""
from __future__ import annotations

import re
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


_PRICE = re.compile(r"(?:₹|rs\.?|inr)\s*([0-9][0-9,]{2,})(?:\.\d+)?", re.IGNORECASE)


def price_from_text(*texts: Any) -> float | None:
    """A rupee price literally present in the returned page text, if any."""
    for text in texts:
        match = _PRICE.search(str(text or ""))
        if match:
            try:
                return float(match.group(1).replace(",", ""))
            except ValueError:
                return None
    return None


def _tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", str(text or "").casefold()) if len(token) > 1}


def relevant_to(subject: str, *texts: Any) -> bool:
    """A returned row is relevant only if it mentions the requirement's key words."""
    wanted = {token for token in _tokens(subject) if not token.isdigit()} or _tokens(subject)
    if not wanted:
        return False
    hay = _tokens(" ".join(str(text or "") for text in texts))
    return len(wanted & hay) >= max(1, -(-len(wanted) // 2))


STATUS_OK = "ok"
STATUS_NO_RESULTS = "no_results"
STATUS_UNAVAILABLE = "unavailable"


class UniversalOnlineFallbackService:
    """Real online product pages and actual videos for a requirement.

    2026-09-26 (Build 1238): the earlier version returned placeholder links
    ("Search online for TV", "TV reviews on YouTube") whenever the web
    provider was unconfigured or empty. Those are gone: only rows the Brave
    provider actually returned are shown, and ``status`` records per source
    whether it returned results, returned nothing, or is unavailable, so the
    chat can say so honestly instead of faking a section.
    """

    def __init__(self, web_search=None) -> None:
        self.web_search = web_search
        self.status: dict[str, str] = {}

    @property
    def _search_configured(self) -> bool:
        return callable(self.web_search) and bool(getattr(self.web_search, "configured", True))

    def online(self, *, category: str, subject: str, limit: int = 4) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject:
            return []
        if not self._search_configured:
            self.status["online"] = STATUS_UNAVAILABLE
            return []
        results: list[dict[str, Any]] = []
        for row in self._search(f"{subject} price buy online", limit * 3):
            url = UniversalExternalResultService._http_url(row.get("url"))
            if not url or _is_video_host(url):
                continue
            if not relevant_to(subject, row.get("title"), row.get("snippet")):
                continue
            item = self._row("online", len(results), row.get("title"), row.get("snippet"), url)
            item["image_url"] = row.get("thumbnail") or None
            item["source_name"] = row.get("host") or item["provider_id"]
            item["price"] = price_from_text(row.get("title"), row.get("snippet"))
            results.append(item)
            if len(results) >= limit:
                break
        self.status["online"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

    def videos(self, *, category: str, subject: str, limit: int = 4) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject or str(category or "").strip().upper() in _NO_VIDEO_DOMAINS:
            return []
        if not self._search_configured:
            self.status["videos"] = STATUS_UNAVAILABLE
            return []
        query = f"{subject} review"
        video_search = getattr(self.web_search, "videos", None)
        rows: list[dict[str, Any]] = []
        if callable(video_search):
            try:
                rows = [row for row in (video_search(query, limit * 3) or []) if isinstance(row, dict)]
            except Exception:
                rows = []
        if not rows:
            rows = [row for row in self._search(f"{subject} review video", limit * 4)
                    if _is_video_host(str(row.get("url") or ""))]
        results: list[dict[str, Any]] = []
        for row in rows:
            url = UniversalExternalResultService._http_url(row.get("url"))
            if not url or not relevant_to(subject, row.get("title"), row.get("snippet")):
                continue
            item = self._row("video", len(results), row.get("title"), row.get("snippet"), url)
            item["image_url"] = row.get("thumbnail") or None
            item["source_name"] = row.get("creator") or row.get("publisher") or row.get("host") or item["provider_id"]
            item["duration"] = row.get("duration") or None
            results.append(item)
            if len(results) >= limit:
                break
        self.status["videos"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

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
