from __future__ import annotations

import re
from typing import Any


class ScheduledTaskConditionEvaluator:
    """Evaluate condition-watch tasks from live ASKODOX research evidence.

    The evaluator is intentionally conservative: missing/weak evidence raises so the
    worker records a retryable failure instead of incorrectly treating the condition
    as false. Supported deterministic operators are contains/not_contains and
    numeric lt/lte/gt/gte/eq.
    """

    _NUMERIC_OPERATORS = {"lt", "lte", "gt", "gte", "eq"}

    def __init__(self, research_service) -> None:
        self.research_service = research_service

    def __call__(self, task: dict[str, Any]) -> bool:
        condition = task.get("condition") or {}
        if not isinstance(condition, dict):
            raise ValueError("condition must be an object")

        operator = str(condition.get("operator") or "").strip().lower()
        if operator not in {"contains", "not_contains", *self._NUMERIC_OPERATORS}:
            raise ValueError(f"Unsupported condition operator: {operator or 'missing'}")

        query = " ".join(
            str(condition.get("query") or task.get("prompt") or task.get("title") or "").split()
        )
        if not query:
            raise ValueError("condition watch requires a research query")

        research = self.research_service.research(query, limit=8, max_age_days=7)
        sources = research.get("sources") or []
        if not sources:
            raise RuntimeError("No fresh evidence available for condition evaluation")

        evidence = "\n".join(
            f"{row.get('title') or ''} {row.get('snippet') or ''}" for row in sources if isinstance(row, dict)
        ).strip()
        if not evidence:
            raise RuntimeError("Live research returned no usable evidence text")

        if operator in {"contains", "not_contains"}:
            needle = str(condition.get("value") or "").strip().casefold()
            if not needle:
                raise ValueError("text condition requires a non-empty value")
            found = needle in evidence.casefold()
            return found if operator == "contains" else not found

        target = self._number(condition.get("value"))
        values = self._extract_numeric_evidence(evidence, field=str(condition.get("field") or ""))
        if not values:
            raise RuntimeError("No comparable numeric evidence found")

        if operator == "lt":
            return any(value < target for value in values)
        if operator == "lte":
            return any(value <= target for value in values)
        if operator == "gt":
            return any(value > target for value in values)
        if operator == "gte":
            return any(value >= target for value in values)
        return any(abs(value - target) < 1e-9 for value in values)

    @staticmethod
    def _number(value: Any) -> float:
        try:
            return float(str(value).replace(",", "").strip())
        except (TypeError, ValueError) as error:
            raise ValueError("numeric condition requires a numeric value") from error

    @classmethod
    def _extract_numeric_evidence(cls, text: str, *, field: str) -> list[float]:
        clean_field = field.strip().casefold()
        candidates: list[str] = []

        # Prefer currency-looking values for price watches.
        if clean_field in {"price", "cost", "rate"}:
            candidates.extend(
                match.group(1)
                for match in re.finditer(
                    r"(?:₹|rs\.?|inr|\$|usd|€|eur|£|gbp)\s*([0-9][0-9,]*(?:\.[0-9]+)?)",
                    text,
                    flags=re.IGNORECASE,
                )
            )

        # If a named field exists, capture numbers close to that field label.
        if clean_field:
            pattern = re.compile(
                rf"{re.escape(clean_field)}[^0-9]{{0,24}}([0-9][0-9,]*(?:\.[0-9]+)?)",
                flags=re.IGNORECASE,
            )
            candidates.extend(match.group(1) for match in pattern.finditer(text))

        values: list[float] = []
        for raw in candidates:
            try:
                values.append(float(raw.replace(",", "")))
            except ValueError:
                continue
        return values
