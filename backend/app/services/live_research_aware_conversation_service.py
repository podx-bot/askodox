"""Conversation wrapper that supplies live-web evidence for OASAT research requests."""
from __future__ import annotations

from app.services.oasat_domain_router import OASATDomainRouter


class LiveResearchAwareConversationService:
    def __init__(
        self,
        delegate,
        research_service,
        router: OASATDomainRouter | None = None,
        deep_research_service=None,
    ) -> None:
        self.delegate = delegate
        self.research_service = research_service
        self.router = router or OASATDomainRouter()
        self.deep_research_service = deep_research_service

    def process(self, sender_mobile: str, message: str) -> str:
        clean = " ".join(str(message or "").strip().split())
        plan = self.router.route(clean)
        if str(plan.get("domain") or "").upper() != "RESEARCH":
            return self._delegate(sender_mobile, clean)

        use_deep = self.deep_research_service is not None and self._needs_deep_research(clean)
        try:
            if use_deep:
                evidence = self.deep_research_service.research(
                    clean,
                    limit_per_query=5,
                    max_queries=4,
                    max_age_days=self._freshness_days(clean),
                )
            else:
                evidence = self.research_service.research(
                    clean,
                    limit=8,
                    max_age_days=self._freshness_days(clean),
                )
        except Exception:
            evidence = {"live_research": False, "source_count": 0, "sources": [], "citation_map": {}}

        if not evidence.get("source_count"):
            mode = "deep research" if use_deep else "live web research"
            routed = (
                f"OASAT {mode.upper()}: live web evidence is currently unavailable or no usable sources were returned. "
                "Do not claim that current web results were checked. Be transparent about the limitation. "
                f"User request: {clean}"
            )
            return self._delegate(sender_mobile, routed)

        source_lines = []
        for index, source in enumerate(evidence.get("sources") or [], start=1):
            discovered_by = source.get("discovered_by_query")
            source_lines.append(
                f"[S{index}] title={source.get('title')}; url={source.get('url')}; "
                f"published_at={source.get('published_at')}; quality={source.get('quality_score')}; "
                f"freshness={source.get('freshness_score')}; "
                + (f"discovered_by={discovered_by}; " if discovered_by else "")
                + f"snippet={source.get('snippet')}"
            )

        if use_deep:
            routed = (
                "OASAT DEEP RESEARCH EVIDENCE. Synthesize across the supplied sub-query evidence. "
                "Use only supplied source facts for current-web claims; cite source ids like [S1]; "
                "compare independent evidence, state evidence gaps and partial failures, prefer primary/high-quality/fresh sources, "
                "and never invent a source, publication date, or live fact. "
                f"coverage_ratio={evidence.get('coverage_ratio')}; partial_failure={bool(evidence.get('partial_failure'))}; "
                f"planned_queries={evidence.get('planned_queries')}. "
                + " ".join(source_lines)
                + f" User request: {clean}"
            )
        else:
            routed = (
                "OASAT LIVE RESEARCH EVIDENCE. Use only the supplied source facts for current-web claims; "
                "cite source ids like [S1], prefer primary/high-quality/fresh evidence, and explicitly surface material conflicts. "
                "Never invent a source, publication date, or live fact. "
                f"conflicts_present={bool(evidence.get('conflicts_present'))}. "
                + " ".join(source_lines)
                + f" User request: {clean}"
            )
        return self._delegate(sender_mobile, routed)

    def _delegate(self, sender_mobile: str, message: str) -> str:
        try:
            return self.delegate.process(sender_mobile=sender_mobile, message=message)
        except TypeError:
            return self.delegate.process(sender_mobile, message)

    @staticmethod
    def _needs_deep_research(message: str) -> bool:
        text = str(message or "").casefold()
        markers = (
            "deep research",
            "research deeply",
            "comprehensive research",
            "detailed research",
            "investigate",
            "compare",
            "versus",
            " vs ",
            "pros and cons",
            "in depth",
            "in-depth",
            "డీప్ రీసెర్చ్",
            "వివరంగా పరిశోధించు",
        )
        return any(marker in text for marker in markers)

    @staticmethod
    def _freshness_days(message: str) -> int | None:
        text = str(message or "").casefold()
        if any(marker in text for marker in ("today", "latest", "breaking", "current", "ఈరోజు", "లేటెస్ట్")):
            return 7
        if any(marker in text for marker in ("this month", "recent", "recently", "ఈ నెల")):
            return 30
        return None
