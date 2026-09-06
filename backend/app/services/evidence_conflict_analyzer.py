"""Conservative structured conflict detection for research evidence.

This analyzer never decides which source is true. It only flags likely disagreements
when independent sources make same-topic numeric/date/status claims with different
values and enough nearby lexical overlap to avoid broad false positives.
"""
from __future__ import annotations

import re
from typing import Any


class EvidenceConflictAnalyzer:
    _STOP = {
        "the", "a", "an", "and", "or", "of", "to", "for", "in", "on", "at", "by",
        "from", "with", "is", "was", "were", "are", "be", "this", "that", "as", "it",
        "its", "their", "latest", "report", "says", "said", "source", "data",
    }
    _PERCENT = re.compile(r"(?<!\w)(\d+(?:\.\d+)?)\s*%")
    _CURRENCY = re.compile(r"(?:₹|\$|€|£)\s*\d[\d,]*(?:\.\d+)?")
    _DATE = re.compile(
        r"\b(?:20\d{2}-\d{1,2}-\d{1,2}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+20\d{2})\b",
        re.IGNORECASE,
    )
    _STATUS = (
        (re.compile(r"\bnot\s+approved\b|\brejected\b|\bdenied\b", re.I), "not_approved"),
        (re.compile(r"\bapproved\b|\bauthorized\b", re.I), "approved"),
        (re.compile(r"\bunavailable\b|\bnot\s+available\b", re.I), "unavailable"),
        (re.compile(r"\bavailable\b", re.I), "available"),
        (re.compile(r"\bdecreased\b|\bdeclined\b|\bfell\b", re.I), "decreased"),
        (re.compile(r"\bincreased\b|\brose\b|\bgrew\b", re.I), "increased"),
    )

    def analyze(self, sources: list[dict[str, Any]]) -> dict[str, Any]:
        claims: list[dict[str, Any]] = []
        for index, source in enumerate(sources):
            text = " ".join(
                str(source.get(k) or "").strip() for k in ("title", "snippet") if source.get(k)
            )
            if not text:
                continue
            for claim in self._claims(text):
                claim.update({
                    "source_index": index,
                    "url": str(source.get("url") or ""),
                    "domain": str(source.get("domain") or "").casefold(),
                })
                claims.append(claim)

        conflicts: list[dict[str, Any]] = []
        seen: set[tuple[Any, ...]] = set()
        for i, left in enumerate(claims):
            for right in claims[i + 1:]:
                if left["source_index"] == right["source_index"]:
                    continue
                if left["domain"] and left["domain"] == right["domain"]:
                    continue
                if left["type"] != right["type"] or left["value"] == right["value"]:
                    continue
                overlap = sorted(set(left["anchors"]) & set(right["anchors"]))
                if len(overlap) < 2:
                    continue
                key = (left["type"], left["value"], right["value"], left["url"], right["url"])
                reverse = (left["type"], right["value"], left["value"], right["url"], left["url"])
                if key in seen or reverse in seen:
                    continue
                seen.add(key)
                conflicts.append({
                    "claim_type": left["type"],
                    "left_value": left["value"],
                    "right_value": right["value"],
                    "left_url": left["url"],
                    "right_url": right["url"],
                    "shared_anchors": overlap[:6],
                })

        return {
            "conflicts_present": bool(conflicts),
            "conflict_count": len(conflicts),
            "conflicts": conflicts,
            "rule": "Potential disagreement only; do not infer which source is correct without further evidence.",
        }

    def _claims(self, text: str) -> list[dict[str, Any]]:
        claims: list[dict[str, Any]] = []
        for match in self._PERCENT.finditer(text):
            claims.append(self._claim("percentage", match.group(1) + "%", text, match.start(), match.end()))
        for match in self._CURRENCY.finditer(text):
            value = re.sub(r"\s+", "", match.group(0))
            claims.append(self._claim("currency", value, text, match.start(), match.end()))
        for match in self._DATE.finditer(text):
            claims.append(self._claim("date", match.group(0).casefold(), text, match.start(), match.end()))
        for pattern, value in self._STATUS:
            for match in pattern.finditer(text):
                claims.append(self._claim("status", value, text, match.start(), match.end()))
        return claims

    def _claim(self, claim_type: str, value: str, text: str, start: int, end: int) -> dict[str, Any]:
        before = re.findall(r"[A-Za-z0-9]+", text[max(0, start - 90):start].casefold())[-7:]
        after = re.findall(r"[A-Za-z0-9]+", text[end:end + 90].casefold())[:7]
        anchors = [w for w in before + after if len(w) > 2 and w not in self._STOP and not w.isdigit()]
        return {"type": claim_type, "value": value, "anchors": anchors}
