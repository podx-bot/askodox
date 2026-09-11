"""WhatsApp support-only gate for ASKODOX.

This gate intentionally prevents WhatsApp from entering ASKODOX's primary
business, matching, commerce, job, ride, or general AI flows. WhatsApp is a
secondary support/escalation channel only.

Case creation/admin sync is deliberately not claimed here; those remain a
separate Point 51 implementation requirement.
"""
from __future__ import annotations


class WhatsAppSupportOnlyGate:
    """Deterministic guard used by the WhatsApp webhook text path."""

    _SUPPORT_HINTS = (
        "support",
        "help",
        "customer care",
        "complaint",
        "issue",
        "problem",
        "escalate",
        "verification",
        "verify",
        "account",
        "hr",
        "recruitment",
        "staff",
        "సపోర్ట్",
        "హెల్ప్",
        "ఫిర్యాదు",
        "సమస్య",
        "కస్టమర్ కేర్",
        "వెరిఫికేషన్",
        "అకౌంట్",
    )

    def process_text(self, sender_mobile: str, message: str) -> str:
        text = " ".join(str(message or "").strip().split())
        lowered = text.casefold()
        support_request = any(hint in lowered for hint in self._SUPPORT_HINTS)

        if support_request:
            return (
                "ASKODOX WhatsApp support channelకి మీ message వచ్చింది. "
                "ఇది customer-care / complaint / verification / HR / admin support కోసం మాత్రమే. "
                "Support Case ID మరియు admin history sync ఇంకా implementationలో ఉన్నాయి; "
                "అవి create అయ్యాయని నేను చెప్పను."
            )

        return (
            "ASKODOX main AI, product/service search, matching, jobs, rides, deals మరియు daily assistant flows "
            "appలోనే ఉపయోగించండి. ఈ WhatsApp channel customer-care, complaints, verification, HR లేదా "
            "unresolved support కోసం మాత్రమే."
        )
