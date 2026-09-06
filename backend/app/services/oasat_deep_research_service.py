"""Multi-step deep research orchestration for ASKODOX OASAT.

The service decomposes a broad request into bounded sub-queries, merges citation-
ready evidence, measures evidence sufficiency, performs at most one follow-up
search when the first pass is weak, and reports structured evidence conflicts.
"""
from __future__ import annotations

from typing import Any

from app.services.evidence_conflict_analyzer import EvidenceConflictAnalyzer


class OASATDeepResearchService:
    """Run bounded multi-query research on top of OASAT live research."""

    def __init__(self, live_research_service, conflict_analyzer=None) -> None:
        self.live_research_service = live_research_service
        self.conflict_analyzer = conflict_analyzer or EvidenceConflictAnalyzer()

    def research(self, query: str, *, limit_per_query: int = 5,
                 max_queries: int = 4, max_age_days: int | None = None) -> dict[str, Any]:
        clean = " ".join(str(query or "").strip().split())
        if not clean:
            raise ValueError("query is required")

        queries = self.plan_queries(clean, max_queries=max_queries)
        merged: list[dict[str, Any]] = []
        seen_urls: set[str] = set()
        query_results: list[dict[str, Any]] = []
        failures: list[dict[str, str]] = []

        def execute(sub_query: str, *, follow_up: bool = False) -> None:
            try:
                result = self.live_research_service.research(
                    sub_query, limit=limit_per_query, max_age_days=max_age_days)
            except Exception as exc:
                failures.append({"query": sub_query, "error": type(exc).__name__})
                return
            query_results.append({
                "query": sub_query,
                "source_count": int(result.get("source_count") or 0),
                "conflicts_present": bool(result.get("conflicts_present")),
                "follow_up": follow_up,
            })
            for source in result.get("sources") or []:
                url = str(source.get("url") or "").strip()
                if not url or url in seen_urls:
                    continue
                seen_urls.add(url)
                enriched = dict(source)
                enriched["discovered_by_query"] = sub_query
                merged.append(enriched)

        for sub_query in queries:
            execute(sub_query)

        first_pass = self._sufficiency(merged, len(query_results), len(queries))
        follow_up_query = None
        if not first_pass["sufficient"]:
            follow_up_query = self._follow_up_query(clean, first_pass)
            execute(follow_up_query, follow_up=True)

        merged.sort(key=lambda s: (
            float(s.get("evidence_score") or 0.0),
            float(s.get("quality_score") or 0.0),
            float(s.get("freshness_score") or 0.0)), reverse=True)

        citation_map = {f"S{i+1}": source.get("url") for i, source in enumerate(merged)}
        domains = {str(source.get("domain") or "").strip().casefold()
                   for source in merged if source.get("domain")}
        successful_primary_queries = sum(1 for r in query_results if not r.get("follow_up"))
        coverage_ratio = round(successful_primary_queries / len(queries), 3) if queries else 0.0
        sufficiency = self._sufficiency(merged, successful_primary_queries, len(queries))
        try:
            conflict_analysis = self.conflict_analyzer.analyze(merged)
        except Exception:
            conflict_analysis = {
                "conflicts_present": False,
                "conflict_count": 0,
                "conflicts": [],
                "analysis_failed": True,
            }

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
            "citation_integrity": all(url and url in seen_urls for url in citation_map.values()),
            "multi_source": len(domains) > 1,
            "partial_failure": bool(failures),
            "evidence_sufficiency": sufficiency,
            "follow_up_triggered": follow_up_query is not None,
            "follow_up_query": follow_up_query,
            "evidence_conflicts": conflict_analysis,
            "conflicts_present": bool(conflict_analysis.get("conflicts_present")),
            "synthesis_rule": (
                "Answer only from collected evidence; cite only ids present in citation_map; "
                "state evidence gaps, structured conflicts and partial failures; do not choose a side in a conflict "
                "without stronger evidence; prefer primary/high-trust/fresh sources; never present an uncited current "
                "factual claim as established fact."
            ),
        }

    @staticmethod
    def _sufficiency(sources: list[dict[str, Any]], successful_queries: int,
                     planned_queries: int) -> dict[str, Any]:
        domains = {str(s.get("domain") or "").strip().casefold() for s in sources if s.get("domain")}
        primary = any(
            str(s.get("source_type") or "").casefold() in {"official", "government", "primary", "documentation", "paper"}
            or float(s.get("quality_score") or 0.0) >= 0.95
            for s in sources)
        coverage = (successful_queries / planned_queries) if planned_queries else 0.0
        enough_sources = len(sources) >= 3
        independent = len(domains) >= 2
        sufficient = enough_sources and independent and primary and coverage >= 0.5
        return {
            "sufficient": sufficient,
            "source_count": len(sources),
            "independent_domain_count": len(domains),
            "has_primary_source": primary,
            "query_coverage": round(coverage, 3),
            "gaps": [name for name, ok in (
                ("source_count", enough_sources), ("independent_sources", independent),
                ("primary_source", primary), ("query_coverage", coverage >= 0.5)) if not ok],
        }

    @staticmethod
    def _follow_up_query(query: str, sufficiency: dict[str, Any]) -> str:
        gaps = set(sufficiency.get("gaps") or [])
        if "primary_source" in gaps:
            suffix = "official primary source documentation"
        elif "independent_sources" in gaps:
            suffix = "independent corroborating evidence"
        else:
            suffix = "additional authoritative evidence"
        return f"{query} {suffix}"

    @classmethod
    def plan_queries(cls, query: str, *, max_queries: int = 4) -> list[str]:
        clean = " ".join(str(query or "").strip().split())
        if not clean:
            return []
        requested = max(1, min(int(max_queries), 6))
        candidates = [clean]
        folded = clean.casefold()
        if any(marker in folded for marker in ("compare", "versus", " vs ", "difference", "best")):
            candidates.extend([f"{clean} official sources", f"{clean} independent analysis", f"{clean} recent evidence"])
        elif any(marker in folded for marker in ("latest", "current", "today", "recent", "news")):
            candidates.extend([f"{clean} official update", f"{clean} latest reporting", f"{clean} primary source"])
        else:
            candidates.extend([f"{clean} official sources", f"{clean} evidence and data", f"{clean} independent analysis"])
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
