"""WhatsApp support-only gate for ASKODOX.

This gate intentionally prevents WhatsApp from entering ASKODOX's primary
business, matching, commerce, job, ride, or general AI flows. WhatsApp is a
secondary support/escalation channel only.

Case creation/admin sync is deliberately not claimed here; those remain a
separate Point 51 implementation requirement.
"""
from __future__ import annotations


class WhatsAppSupportOnlyGate:
    """Deterministic guard used by the WhatsApp webhook text, audio and location paths."""

    _LOCATION_REDIRECT_REPLY = (
        "ASKODOX WhatsApp channel customer-care/support కోసం మాత్రమే. "
        "Worker/employer registration, job location tracking మరియు matching వంటి పనులన్నీ "
        "ASKODOX appలో పూర్తి చేయండి — ఈ location ని WhatsApp business flow కోసం save/use చేయడం లేదు."
    )

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

    def process_location(self, sender_mobile: str) -> str:
        """Deterministically reject shared-location-driven business flows.

        Worker/employer registration completion, job-location tracking and
        job matching must not run off a WhatsApp location share — those are
        primary business flows that belong in the ASKODOX app. This never
        inspects or persists the coordinates; it only produces the redirect
        reply, mirroring the text gate's default behaviour.
        """
        del sender_mobile  # unused: this is a stateless deterministic reply
        return self._LOCATION_REDIRECT_REPLY
