"""Small universal gate for uncertain requests before matching begins."""
from __future__ import annotations

from app.services.universal_category_flow_brain import UniversalCategoryFlowBrain
from app.services.universal_category_schema import UniversalCategorySchemaRegistry


class DecisionDiscoveryService:
    """Ask one category-relevant decision question only when the user is unsure."""

    UNCERTAINTY_MARKERS = (
        "what should", "which should", "which one", "what is best", "best option",
        "should i", "ఏది మంచిది", "ఏది తీసుకోవాలి", "ఏది కొనాలి", "ఏది సరైనది",
    )

    def __init__(self, category_brain: UniversalCategoryFlowBrain | None = None) -> None:
        self.category_brain = category_brain or UniversalCategoryFlowBrain()

    def question_for(self, message: str) -> str | None:
        text = " ".join(str(message or "").strip().split())
        lowered = text.casefold()
        if not text or not any(marker in lowered for marker in self.UNCERTAINTY_MARKERS):
            return None
        decision = self.category_brain.classify(text)
        schema = UniversalCategorySchemaRegistry.resolve(decision.category)
        focus = ", ".join(schema.decision_focus[:3])
        return f"I can compare suitable {schema.result_kind} options. What matters most here: {focus}?"

    @staticmethod
    def start_state(message: str, question: str) -> dict:
        return {
            "original_request": " ".join(str(message or "").split()),
            "question": str(question),
            "attempts": 1,
        }