"""Default real-user intent families for ASKODOX.

These rules are intentionally kept outside the Universal Deal Brain and outside
individual domain handlers. They provide a patch-safe catalog of common ways
people ask for help, so phrasing can evolve without rewriting domain logic.
"""
from __future__ import annotations

from backend.app.core.intent_domain_router import IntentRule, RealUserIntentRouter


DEFAULT_INTENT_RULES: tuple[IntentRule, ...] = (
    IntentRule(
        domain="commerce",
        action="buy",
        phrases=("want to buy", "need to buy", "looking to buy", "where can i buy", "కొనాలి", "ఎక్కడ కొనాలి"),
        keywords=("buy", "purchase", "కొనాలి", "కొనడం"),
    ),
    IntentRule(
        domain="commerce",
        action="sell",
        phrases=("want to sell", "need to sell", "looking to sell", "అమ్మాలి", "ఎక్కడ అమ్మాలి"),
        keywords=("sell", "selling", "అమ్మాలి", "అమ్మడం"),
    ),
    IntentRule(
        domain="rental",
        action="rent",
        phrases=("for rent", "need on rent", "want to rent", "rent near me", "అద్దెకు కావాలి", "రెంట్ కావాలి"),
        keywords=("rent", "rental", "lease", "అద్దె", "రెంట్"),
    ),
    IntentRule(
        domain="appointment",
        action="book",
        phrases=("book appointment", "need appointment", "appointment with", "అపాయింట్మెంట్ కావాలి", "అపాయింట్మెంట్ బుక్"),
        keywords=("appointment", "అపాయింట్మెంట్"),
    ),
    IntentRule(
        domain="parcel",
        action="send",
        phrases=("send parcel", "parcel delivery", "courier this", "పార్సెల్ పంపాలి", "కొరియర్ పంపాలి"),
        keywords=("parcel", "courier", "పార్సెల్", "కొరియర్"),
    ),
    IntentRule(
        domain="assistance",
        action="complaint",
        phrases=("file a complaint", "raise a complaint", "make a complaint", "complaint about", "ఫిర్యాదు చేయాలి", "కంప్లైంట్ చేయాలి"),
        keywords=("complaint", "grievance", "ఫిర్యాదు", "కంప్లైంట్"),
        priority=1,
    ),
    IntentRule(
        domain="assistance",
        action="application",
        phrases=("how to apply", "apply for", "application form", "submit application", "ఎలా అప్లై చేయాలి", "అప్లికేషన్ పెట్టాలి"),
        keywords=("application", "apply", "అప్లికేషన్", "అప్లై"),
        priority=1,
    ),
    IntentRule(
        domain="assistance",
        action="doubt",
        phrases=("i have a doubt", "have a question", "can you explain", "how does this work", "నాకు డౌట్", "ఇది ఎలా పని చేస్తుంది"),
        keywords=("doubt", "question", "explain", "డౌట్", "సందేహం"),
    ),
)


def build_default_intent_router(*, minimum_score: int = 2) -> RealUserIntentRouter:
    """Return a router preloaded with ASKODOX's baseline real-user patterns."""
    router = RealUserIntentRouter(minimum_score=minimum_score)
    router.register_many(DEFAULT_INTENT_RULES)
    return router
