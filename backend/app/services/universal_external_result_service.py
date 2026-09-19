"""Resolve user-facing online results from normal and affiliate mappings."""
from __future__ import annotations

from urllib.parse import quote_plus
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
