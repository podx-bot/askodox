"""Small universal gate for uncertain requests before matching begins."""
from __future__ import annotations

from app.services.universal_category_flow_brain import UniversalCategoryFlowBrain


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
        category = str(decision.category or "GENERAL").upper()
        if category == "COMMERCE":
            return "I can compare suitable options. What matters most here: lower price, better quality, or longer-term value?"
        if category in {"SERVICES", "APPOINTMENT"}:
            return "I can compare suitable providers. What matters most: fastest availability, lower cost, or strongest experience?"
        if category == "JOBS":
            return "I can compare suitable opportunities. What matters most: the role, location, schedule, or pay?"
        if category == "DELIVERY":
            return "I can compare delivery options. What matters most: speed, price, or vehicle/capacity?"
        return "I can help you decide. What outcome matters most for this request?"

    @staticmethod
    def start_state(message: str, question: str) -> dict:
        return {
            "original_request": " ".join(str(message or "").split()),
            "question": str(question),
            "attempts": 1,
        }