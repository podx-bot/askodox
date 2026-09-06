"""Conversation wrapper that supplies live-web evidence for OASAT research requests."""
from __future__ import annotations

from typing import Any

from app.services.oasat_domain_router import OASATDomainRouter


class LiveResearchAwareConversationService:
    def __init__(self, delegate, research_service, router: OASATDomainRouter | None = None) -> None:
        self.delegate = delegate
        self.research_service = research_service
        self.router = router or OASATDomainRouter()

    def process(self, sender_mobile: str, message: str) -> str:
        clean = " ".join(str(message or "").strip().split())
        plan = self.router.route(clean)
        if str(plan.get("domain") or "").upper() != "RESEARCH":
            return self._delegate(sender_mobile, clean)

        try:
            evidence = self.research_service.research(clean, limit=8, max_age_days=self._freshness_days(clean))
        except Exception:
            evidence = {"live_research": False, "source_count": 0, "sources": [], "citation_map": {}}

        if not evidence.get("source_count"):
            routed = (
                "OASAT LIVE RESEARCH: live web evidence is currently unavailable or no usable sources were returned. "
                "Do not claim that current web results were checked. Be transparent about the limitation. "
                f"User request: {clean}"
            )
            return self._delegate(sender_mobile, routed)

        source_lines = []
        for index, source in enumerate(evidence.get("sources") or [], start=1):
            source_lines.append(
                f"[S{index}] title={source.get('title')}; url={source.get('url')}; "
                f"published_at={source.get('published_at')}; quality={source.get('quality_score')}; "
                f"freshness={source.get('freshness_score')}; snippet={source.get('snippet')}"
            )
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
    def _freshness_days(message: str) -> int | None:
        text = str(message or "").casefold()
        if any(marker in text for marker in ("today", "latest", "breaking", "current", "ఈరోజు", "లేటెస్ట్")):
            return 7
        if any(marker in text for marker in ("this month", "recent", "recently", "ఈ నెల")):
            return 30
        return None
