"""Multi-step deep research orchestration for ASKODOX OASAT.

This service decomposes a broad research request into deterministic sub-queries,
executes each through the existing live-research service, merges/de-duplicates
citation-ready evidence, and reports partial failures without fabricating coverage.
"""
from __future__ import annotations

from typing import Any


class OASATDeepResearchService:
    """Run bounded multi-query research on top of OASAT live research."""

    def __init__(self, live_research_service) -> None:
        self.live_research_service = live_research_service

    def research(
        self,
        query: str,
        *,
        limit_per_query: int = 5,
        max_queries: int = 4,
        max_age_days: int | None = None,
    ) -> dict[str, Any]:
        clean = " ".join(str(query or "").strip().split())
        if not clean:
            raise ValueError("query is required")

        queries = self.plan_queries(clean, max_queries=max_queries)
        merged: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        query_results: list[dict[str, Any]] = []
        failures: list[dict[str, str]] = []

        for sub_query in queries:
            try:
                result = self.live_research_service.research(
                    sub_query,
                    limit=limit_per_query,
                    max_age_days=max_age_days,
                )
            except Exception as exc:
                failures.append({"query": sub_query, "error": type(exc).__name__})
                continue

            query_results.append(
                {
                    "query": sub_query,
                    "source_count": int(result.get("source_count") or 0),
                    "conflicts_present": bool(result.get("conflicts_present")),
                }
            )
            for source in result.get("sources") or []:
                url = str(source.get("url") or "").strip()
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)
                enriched = dict(source)
                enriched["discovered_by_query"] = sub_query
                merged.append(enriched)

        merged.sort(
            key=lambda s: (
                float(s.get("evidence_score") or 0.0),
                float(s.get("quality_score") or 0.0),
                float(s.get("freshness_score") or 0.0),
            ),
            reverse=True,
        )

        citation_map = {f"S{i+1}": source.get("url") for i, source in enumerate(merged)}
        domains = {str(source.get("domain") or "") for source in merged if source.get("domain")}
        successful_queries = len(query_results)
        coverage_ratio = round(successful_queries / len(queries), 3) if queries else 0.0

        return {
            "query": clean,
            "deep_research": True,
            "planned_queries": queries,
            "query_results": query_results,
            "failed_queries": failures,
            "coverage_ratio": coverage_ratio,
            "source_count": len(merged),
            "sources": merged,
            "citation_map": citation_map,
            "multi_source": len(domains) > 1,
            "partial_failure": bool(failures),
            "synthesis_rule": (
                "Answer only from collected evidence; compare sources across sub-queries, "
                "state evidence gaps and partial failures, prefer primary/high-trust/fresh sources, "
                "and cite source ids for current factual claims."
            ),
        }

    @classmethod
    def plan_queries(cls, query: str, *, max_queries: int = 4) -> list[str]:
        clean = " ".join(str(query or "").strip().split())
        if not clean:
            return []
        requested = max(1, min(int(max_queries), 6))

        candidates = [clean]
        folded = clean.casefold()
        if any(marker in folded for marker in ("compare", "versus", " vs ", "difference", "best")):
            candidates.extend([
                f"{clean} official sources",
                f"{clean} independent analysis",
                f"{clean} recent evidence",
            ])
        elif any(marker in folded for marker in ("latest", "current", "today", "recent", "news")):
            candidates.extend([
                f"{clean} official update",
                f"{clean} latest reporting",
                f"{clean} primary source",
            ])
        else:
            candidates.extend([
                f"{clean} official sources",
                f"{clean} evidence and data",
                f"{clean} independent analysis",
            ])

        result: list[str] = []
        seen: set[str] = set()
        for candidate in candidates:
            normalized = " ".join(candidate.split())
            key = normalized.casefold()
            if key in seen:
                continue
            seen.add(key)
            result.append(normalized)
            if len(result) >= requested:
                break
        return result
