"""Live text/image capture -> match/hold -> target -> notify orchestration."""

from __future__ import annotations

import re
from typing import Any, Dict, Optional

from app.services.active_deal_context_resolver import ActiveDealContextResolver


class UniversalLiveCaptureService:
    GREETINGS = {"hi", "hello", "hey", "హాయ్", "హలో", "నమస్తే", "menu", "మెనూ"}
    COMMAND_PREFIXES = (
        "status ", "accept ", "confirm ", "decline ", "reject ", "cancel ",
        "interested ", "start ", "complete ", "arrived ", "manage ",
        "buy_interested ", "buy_not_interested ", "seller_confirm ",
        "seller_decline ", "order_continue ", "direct_talk ",
    )
    QUANTITY_FOLLOWUP_RE = re.compile(
        r"(?<![\w.])(?P<quantity>\d+(?:\.\d+)?)\s*"
        r"(?P<unit>kg|kgs|kilo(?:gram)?s?|కిలోలు?|కిలో|కేజీలు?|కేజీ|किलो)",
        re.IGNORECASE,
    )
    QUANTITY_FOLLOWUP_FILLERS = {
        "", "కావాలి", "నాకు కావాలి", "చాలు", "సరిపోతుంది",
        "please", "want", "need", "i want", "i need", "want it", "need it",
        "चाहिए", "मुझे चाहिए",
    }
    VARIANT_FOLLOWUPS = {
        "boneless": "boneless",
        "బోన్లెస్": "boneless",
        "బోన్‌లెస్": "boneless",
        "बोनलेस": "boneless",
        "skinless": "skinless",
        "స్కిన్‌లెస్": "skinless",
        "స్కిన్లెస్": "skinless",
        "स्किनलेस": "skinless",
    }
    VARIANT_FOLLOWUP_FILLERS = {
        "", "కావాలి", "నాకు కావాలి", "చాలు", "సరిపోతుంది",
        "please", "want", "need", "i want", "i need", "want it", "need it",
        "చేయండి", "ఉండాలి", "चाहिए", "मुझे चाहिए",
    }
    LOCATION_PREFIXES = ("in ", "at ", "near ", "around ", "area ")
    LOCATION_BLOCK_WORDS = {
        "want", "need", "buy", "sell", "job", "work", "service", "ride",
        "price", "budget", "delivery", "today", "tomorrow", "urgent",
        "available", "availability", "quantity", "size", "weight",
        "కావాలి", "కొనాలి", "అమ్మాలి", "పని", "ఉద్యోగం", "సర్వీస్",
        "ధర", "రేట్", "ఈరోజు", "రేపు", "అర్జెంట్",
    }

    def __init__(self, extractor, demand_repository, matcher, targeting_service,
                 notification_service, notification_repository, user_repository,
                 session_registry, min_confidence: float = 0.62, demand_intelligence=None) -> None:
        self.extractor = extractor
        self.demands = demand_repository
        self.matcher = matcher
        self.targeting = targeting_service
        self.notifications = notification_service
        self.notification_repository = notification_repository
        self.users = user_repository
        self.sessions = session_registry
        self.min_confidence = float(min_confidence)
        self.demand_intelligence = demand_intelligence

    def process_text(self, sender_mobile: str, message: str) -> Optional[str]:
        text = " ".join(str(message or "").strip().split())
        if not text or self._skip_text(text):
            return None
        if not self._can_capture(sender_mobile):
            return None

        quantity_followup = self._quantity_followup(text)
        if quantity_followup is not None:
            reply = self._revise_latest_quantity(
                sender_mobile=sender_mobile,
                quantity=quantity_followup[0],
                unit=quantity_followup[1],
            )
            if reply is not None:
                return reply

        variant_followup = self._variant_followup(text)
        if variant_followup is not None:
            reply = self._revise_latest_constraint(
                sender_mobile=sender_mobile,
                key="variant",
                value=variant_followup,
            )
            if reply is not None:
                return reply

        location_reply = self._merge_location_text_followup(sender_mobile, text)
        if location_reply is not None:
            return location_reply

        extracted = self.extractor.extract(text)
        if not extracted.get("success"):
            return None
        request = dict(extracted.get("request") or {})
        if not request:
            return None
        return self.process_structured(sender_mobile=sender_mobile, request=request, source="text")

    def process_structured(self, sender_mobile: str, request: Dict[str, Any],
                           source: str = "text", media_ref: str | None = None) -> Optional[str]:
        if not self._can_capture(sender_mobile):
            return None
        request = dict(request or {})
        if str(request.get("side") or "").upper() not in {"NEED", "OFFER"}:
            return None
        if str(request.get("domain") or "OTHER").upper() == "OTHER":
            return None
        if not str(request.get("subject") or "").strip():
            return None
        if float(request.get("confidence") or 0.0) < self.min_confidence:
            return None

        user = self.users.find_by_whatsapp_mobile(sender_mobile) or {}
        request["user_id"] = str(sender_mobile)
        request["source"] = str(source or "text")
        request["media_ref"] = media_ref
        request["when"] = request.get("when") or request.get("when_text")
        if user.get("latitude") is not None and user.get("longitude") is not None:
            request["latitude"] = user.get("latitude")
            request["longitude"] = user.get("longitude")
            request["location_text"] = request.get("location_text") or user.get("location_name") or user.get("area")

        latest = getattr(self.demands, "latest_active_for_user", None)
        active = latest(sender_mobile) if callable(latest) else None
        if ActiveDealContextResolver.same_context(active, request):
            merged_fields = ActiveDealContextResolver.merge_fields(active, request)
            stored = self._update_latest_active(active, merged_fields)
            if stored is not None:
                if stored.get("latitude") is None or stored.get("longitude") is None:
                    subject = stored.get("subject") or "మీ requirement"
                    return (
                        f"🔄 '{subject}' requirementని కొత్త {request['source']} detailsతో update చేశాను. "
                        "ముందు చెప్పిన details అలాగే ఉంచాను. Match కోసం Current Location share చేయండి."
                    )
                self._trigger_demand_intelligence(stored)
                return self._match_target_notify(stored)

        request_id = self.demands.create(request)
        stored = self.demands.get(request_id) or {**request, "id": request_id}
        if stored.get("latitude") is None or stored.get("longitude") is None:
            subject = stored.get("subject") or "మీ requirement"
            return f"✅ '{subject}' requirement save చేశాను. మీకు దగ్గరలో సరైన match వెతకడానికి Current Location share చేయండి."
        self._trigger_demand_intelligence(stored)
        return self._match_target_notify(stored)

    def handle_location(self, sender_mobile: str, latitude: float, longitude: float,
                        location_name: str | None = None, location_address: str | None = None) -> Optional[str]:
        pending = self.demands.latest_active_for_user_missing_location(sender_mobile)
        if pending is None:
            return None
        location_text = location_name or location_address
        self.users.save_location(whatsapp_mobile=sender_mobile, latitude=latitude, longitude=longitude,
                                 location_name=location_name, location_address=location_address)
        self.demands.update_location(demand_id=int(pending["id"]), latitude=latitude, longitude=longitude,
                                     location_text=location_text)
        stored = self.demands.get(int(pending["id"])) or pending
        self._trigger_demand_intelligence(stored)
        return self._match_target_notify(stored, location_saved=True)

    def _merge_location_text_followup(self, sender_mobile: str, text: str) -> Optional[str]:
        pending = self.demands.latest_active_for_user_missing_location(sender_mobile)
        if pending is None:
            return None
        location_text = self._location_text_followup(text)
        if location_text is None:
            return None
        updater = getattr(self.demands, "update_location_text", None)
        if not callable(updater):
            return None
        updater(int(pending["id"]), location_text)
        stored = self.demands.get(int(pending["id"])) or {**pending, "location_text": location_text}
        subject = str(stored.get("subject") or "మీ requirement")
        self._trigger_demand_intelligence(stored)
        result = self._match_target_notify(stored)
        return (
            f"📍 {location_text} locationని '{subject}' requirementకి add చేశాను. "
            "ముందు చెప్పిన requirement అలాగే ఉంచాను.\n"
            f"{result}\n"
            "Exact distance ranking కోసం కావాలంటే Current Location కూడా share చేయండి."
        )

    def _update_latest_active(self, previous: Dict[str, Any], fields: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        updater = getattr(self.demands, "update_active_fields", None)
        if not callable(updater):
            return None
        demand_id = int(previous["id"])
        if not updater(demand_id, fields):
            return None
        return self.demands.get(demand_id) or {**previous, **fields, "id": demand_id}

    def _revise_latest_quantity(self, sender_mobile: str, quantity: float, unit: str) -> Optional[str]:
        latest = getattr(self.demands, "latest_active_for_user", None)
        if not callable(latest):
            return None
        previous = latest(sender_mobile)
        if previous is None:
            return None

        stored = self._update_latest_active(previous, {
            "quantity": float(quantity),
            "unit": unit,
            "source": "text",
        })
        if stored is None:
            return None
        subject = str(stored.get("subject") or "మీ requirement")
        quantity_text = f"{float(quantity):g} {unit}"

        if stored.get("latitude") is None or stored.get("longitude") is None:
            return (
                f"🔄 {subject} quantity {quantity_text}కి update చేశాను. "
                "మీకు దగ్గరలో సరైన match వెతకడానికి Current Location share చేయండి."
            )

        self._trigger_demand_intelligence(stored)
        result = self._match_target_notify(stored)
        return f"🔄 {subject} quantity {quantity_text}కి update చేశాను.\n{result}"

    def _revise_latest_constraint(self, sender_mobile: str, key: str, value: str) -> Optional[str]:
        latest = getattr(self.demands, "latest_active_for_user", None)
        if not callable(latest):
            return None
        previous = latest(sender_mobile)
        if previous is None or str(previous.get("domain") or "").upper() != "PRODUCT":
            return None

        raw_constraints = previous.get("constraints")
        if isinstance(raw_constraints, dict):
            constraints = dict(raw_constraints)
        elif isinstance(raw_constraints, list):
            constraints = {"preferences": list(raw_constraints)} if raw_constraints else {}
        else:
            constraints = {}
        constraints[str(key)] = str(value)

        stored = self._update_latest_active(previous, {
            "constraints": constraints,
            "source": "text",
        })
        if stored is None:
            return None
        subject = str(stored.get("subject") or "మీ requirement")

        if stored.get("latitude") is None or stored.get("longitude") is None:
            return (
                f"🔄 {subject} requestకి {value} preference add చేశాను. "
                "ముందు చెప్పిన quantity/details అలాగే ఉంచాను. Match కోసం Current Location share చేయండి."
            )

        self._trigger_demand_intelligence(stored)
        result = self._match_target_notify(stored)
        return (
            f"🔄 {subject} requestకి {value} preference add చేశాను. "
            f"ముందు చెప్పిన quantity/details అలాగే ఉంచాను.\n{result}"
        )

    def _trigger_demand_intelligence(self, request: Dict[str, Any]) -> None:
        if self.demand_intelligence is None:
            return
        if str(request.get("side") or "").upper() != "NEED":
            return
        try:
            self.demand_intelligence.trigger_async()
        except Exception:
            return

    def _can_capture(self, sender_mobile: str) -> bool:
        user = self.users.find_by_whatsapp_mobile(sender_mobile) or {}
        if not user or not int(user.get("registration_complete") or 0):
            return False
        session = self.sessions.get(sender_mobile)
        step_name = getattr(getattr(session, "step", None), "name", "")
        return step_name == "MAIN_MENU"

    def _skip_text(self, text: str) -> bool:
        lowered = text.casefold()
        if lowered in self.GREETINGS:
            return True
        return any(lowered.startswith(prefix) for prefix in self.COMMAND_PREFIXES)

    def _quantity_followup(self, text: str) -> Optional[tuple[float, str]]:
        match = self.QUANTITY_FOLLOWUP_RE.search(text)
        if match is None:
            return None
        remaining = (text[:match.start()] + " " + text[match.end():]).strip().casefold()
        remaining = " ".join(remaining.split())
        if remaining not in self.QUANTITY_FOLLOWUP_FILLERS:
            return None
        return float(match.group("quantity")), str(match.group("unit")).strip()

    def _variant_followup(self, text: str) -> Optional[str]:
        lowered = " ".join(text.casefold().split())
        for token, normalized in self.VARIANT_FOLLOWUPS.items():
            if token not in lowered:
                continue
            remaining = lowered.replace(token, " ", 1)
            remaining = " ".join(remaining.split())
            if remaining in self.VARIANT_FOLLOWUP_FILLERS:
                return normalized
        return None

    def _location_text_followup(self, text: str) -> Optional[str]:
        cleaned = " ".join(str(text or "").strip().split())
        if not cleaned or len(cleaned) > 80:
            return None
        lowered = cleaned.casefold()
        for prefix in self.LOCATION_PREFIXES:
            if lowered.startswith(prefix):
                candidate = cleaned[len(prefix):].strip(" ,.-")
                return candidate if self._looks_like_location(candidate) else None
        if self._looks_like_location(cleaned):
            return cleaned
        return None

    def _looks_like_location(self, value: str) -> bool:
        candidate = " ".join(str(value or "").strip().split())
        if not candidate or len(candidate) < 2 or len(candidate) > 60:
            return False
        lowered = candidate.casefold()
        if any(word in lowered.split() for word in self.LOCATION_BLOCK_WORDS):
            return False
        if any(ch.isdigit() for ch in candidate):
            return False
        return len(candidate.split()) <= 5

    def _match_target_notify(self, stored: Dict[str, Any], location_saved: bool = False) -> str:
        matches = self.matcher.find_matches(stored, limit=10)
        if matches:
            return self.notifications.notify_matches(stored, matches, location_saved=location_saved)
        return self.targeting.handle_no_match(stored)
