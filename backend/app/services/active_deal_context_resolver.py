from __future__ import annotations

import re
from typing import Any, Dict


class ActiveDealContextResolver:
    """Pure resolver for deciding whether an incoming request revises the active deal.

    This intentionally performs only conservative same-context detection. A different
    subject is not force-merged; the Conversation Kernel must decide whether that is a
    true new deal or an explicit replacement before the old active deal is superseded.
    """

    _SPACE_RE = re.compile(r"\s+")
    _PUNCT_RE = re.compile(r"[^\w\s]+", re.UNICODE)

    @classmethod
    def normalize_subject(cls, value: Any) -> str:
        text = str(value or "").strip().casefold()
        text = cls._PUNCT_RE.sub(" ", text)
        return cls._SPACE_RE.sub(" ", text).strip()

    @classmethod
    def same_context(cls, active: Dict[str, Any] | None, incoming: Dict[str, Any] | None) -> bool:
        if not active or not incoming:
            return False
        active_side = str(active.get("side") or "").upper()
        incoming_side = str(incoming.get("side") or "").upper()
        active_domain = str(active.get("domain") or "").upper()
        incoming_domain = str(incoming.get("domain") or "").upper()
        if not active_side or active_side != incoming_side:
            return False
        if not active_domain or active_domain != incoming_domain:
            return False
        active_subject = cls.normalize_subject(active.get("subject"))
        incoming_subject = cls.normalize_subject(incoming.get("subject"))
        return bool(active_subject and active_subject == incoming_subject)

    @classmethod
    def merge_fields(cls, active: Dict[str, Any], incoming: Dict[str, Any]) -> Dict[str, Any]:
        """Return non-empty revision fields while preserving earlier known facts.

        Constraints are merged key-by-key so a new image/text/voice hint cannot erase
        previously collected preferences.
        """
        allowed = (
            "side", "domain", "subject", "quantity", "unit", "price", "currency",
            "when_text", "latitude", "longitude", "location_text", "source", "media_ref",
        )
        merged: Dict[str, Any] = {}
        for key in allowed:
            value = incoming.get(key)
            if value not in (None, "", [], {}):
                merged[key] = value

        previous_constraints = active.get("constraints")
        incoming_constraints = incoming.get("constraints")
        constraints: Dict[str, Any] = {}
        if isinstance(previous_constraints, dict):
            constraints.update(previous_constraints)
        if isinstance(incoming_constraints, dict):
            constraints.update(incoming_constraints)
        if constraints:
            merged["constraints"] = constraints
        return merged
