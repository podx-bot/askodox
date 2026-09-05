"""Provider-neutral live research evidence runtime for ASKODOX OASAT.

This layer deliberately separates research reasoning from any one web-search vendor.
A provider only has to return dictionaries containing title/url/snippet plus optional
published_at/source_type fields. The service then normalizes, scores, de-duplicates,
and exposes citation-ready evidence without pretending stale or weak sources are live.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import Any, Callable, Iterable
from urllib.parse import urlparse


@dataclass(frozen=True)
class ResearchSource:
    title: str
    url: str
    snippet: str
    published_at: str | None
    source_type: str
    domain: str
    quality_score: float
    freshness_score: float
    evidence_score: float

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


class OASATLiveResearchService:
    """Normalize and rank live-web evidence before OASAT synthesis."""

    HIGH_TRUST_TYPES = {"official", "government", "primary", "documentation", "paper"}
    MEDIUM_TRUST_TYPES = {"news", "reference", "industry"}

    def __init__(self, provider: Callable[[str, int], Iterable[dict[str, Any]]]) -> None:
        if not callable(provider):
            raise TypeError("provider must be callable")
        self.provider = provider

    def research(self, query: str, *, limit: int = 8, max_age_days: int | None = None) -> dict[str, Any]:
        clean_query = " ".join(str(query or "").strip().split())
        if not clean_query:
            raise ValueError("query is required")
        requested = max(1, min(int(limit), 20))
        raw = list(self.provider(clean_query, requested))
        sources = self._normalize_sources(raw, max_age_days=max_age_days)
        sources.sort(key=lambda s: (s.evidence_score, s.quality_score, s.freshness_score), reverse=True)
        selected = sources[:requested]
        return {
            "query": clean_query,
            "live_research": True,
            "source_count": len(selected),
            "sources": [s.as_dict() for s in selected],
            "citation_map": {f"S{i+1}": s.url for i, s in enumerate(selected)},
            "conflicts_present": self._conflicts_present(selected),
            "freshness_policy_days": max_age_days,
            "synthesis_rule": "Prefer primary/high-trust and fresher evidence; surface material conflicts instead of hiding them.",
        }

    def _normalize_sources(self, rows: Iterable[dict[str, Any]], *, max_age_days: int | None) -> list[ResearchSource]:
        seen: set[str] = set()
        result: list[ResearchSource] = []
        for row in rows:
            url = str(row.get("url") or "").strip()
            title = " ".join(str(row.get("title") or "").strip().split())
            snippet = " ".join(str(row.get("snippet") or row.get("summary") or "").strip().split())
            if not url or not title or not snippet or url in seen:
                continue
            parsed = urlparse(url)
            if parsed.scheme not in {"http", "https"} or not parsed.netloc:
                continue
            seen.add(url)
            source_type = str(row.get("source_type") or "web").strip().lower()
            published_at = self._clean_timestamp(row.get("published_at"))
            quality = self._quality_score(source_type, parsed.netloc)
            freshness = self._freshness_score(published_at, max_age_days=max_age_days)
            if max_age_days is not None and freshness <= 0:
                continue
            evidence = round((quality * 0.6) + (freshness * 0.4), 3)
            result.append(
                ResearchSource(
                    title=title,
                    url=url,
                    snippet=snippet,
                    published_at=published_at,
                    source_type=source_type,
                    domain=parsed.netloc.lower(),
                    quality_score=quality,
                    freshness_score=freshness,
                    evidence_score=evidence,
                )
            )
        return result

    @classmethod
    def _quality_score(cls, source_type: str, domain: str) -> float:
        if source_type in cls.HIGH_TRUST_TYPES or domain.endswith(".gov") or domain.endswith(".gov.in"):
            return 1.0
        if source_type in cls.MEDIUM_TRUST_TYPES:
            return 0.8
        return 0.6

    @staticmethod
    def _clean_timestamp(value: Any) -> str | None:
        if value in {None, ""}:
            return None
        text = str(value).strip()
        try:
            dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).isoformat()
        except ValueError:
            return None

    @classmethod
    def _freshness_score(cls, published_at: str | None, *, max_age_days: int | None) -> float:
        if published_at is None:
            return 0.5 if max_age_days is None else 0.0
        dt = datetime.fromisoformat(published_at)
        age_days = max(0.0, (datetime.now(timezone.utc) - dt).total_seconds() / 86400)
        if max_age_days is not None and age_days > max_age_days:
            return 0.0
        if age_days <= 1:
            return 1.0
        if age_days <= 7:
            return 0.9
        if age_days <= 30:
            return 0.8
        if age_days <= 365:
            return 0.65
        return 0.5

    @staticmethod
    def _conflicts_present(sources: list[ResearchSource]) -> bool:
        # A deterministic conservative signal for the synthesis layer: if multiple
        # distinct domains survive ranking, OASAT must compare them rather than
        # collapsing to a single-source answer.
        return len({s.domain for s in sources}) > 1
