"""Universal conversational adapter with matched-product FAQ context."""
from __future__ import annotations

from datetime import datetime
import re
from zoneinfo import ZoneInfo


class UniversalAwareConversationService:
    GREETING_WORDS = {"hi", "hello", "hey", "హాయ్", "హలో", "नमस्ते", "हाय"}
    PRODUCT_QUESTION_WORDS = (
        "?", "ధర", "price", "ఎంత", "available", "availability", "stock",
        "size", "weight", "quantity", "delivery", "warranty", "return",
        "expiry", "feature", "features", "original", "color", "colour",
        "variant", "దొరుకుతుందా", "ఉందా", "ఎలా", "ఏమిటి", "doubt", "details",
        "quality", "క్వాలిటీ", "రేట్",
    )

    def __init__(
        self,
        response_commands,
        base_conversation,
        live_capture=None,
        image_service=None,
        product_runtime=None,
        seller_escalation=None,
        grocery_runtime=None,
        grocery_order_runtime=None,
        catering_runtime=None,
        catering_menu_ai=None,
        event_runtime=None,
        event_provider_runtime=None,
        hybrid_support=None,
        ride_runtime=None,
        ledger_runtime=None,
        creator_runtime=None,
        alert_preference_runtime=None,
        service_decision_assistant=None,
        buyer_decision_assistant=None,
        affiliate_provider_config=None,
        party_ai_orchestrator=None,
        profile_source=None,
        catalog_repository=None,
        live_lead_service=None,
    ) -> None:
        self.response_commands = response_commands
        self.live_capture = live_capture
        self.image_service = image_service
        self.base_conversation = base_conversation
        self.product_runtime = product_runtime
        self.seller_escalation = seller_escalation
        self.grocery_runtime = grocery_runtime
        self.grocery_order_runtime = grocery_order_runtime
        self.catering_runtime = catering_runtime
        self.catering_menu_ai = catering_menu_ai
        self.event_runtime = event_runtime
        self.event_provider_runtime = event_provider_runtime
        self.hybrid_support = hybrid_support or getattr(product_runtime, "hybrid_support", None)
        self.ride_runtime = ride_runtime
        self.service_decision_assistant = service_decision_assistant
        self.buyer_decision_assistant = buyer_decision_assistant
        self.affiliate_provider_config = affiliate_provider_config
        self.party_ai_orchestrator = party_ai_orchestrator
        self.profile_source = profile_source
        self.catalog_repository = catalog_repository or getattr(product_runtime, "catalog", None)
        self.live_lead_service = live_lead_service
        self.ledger_runtime = ledger_runtime or self._auto_ledger_runtime()
        self.creator_runtime = creator_runtime or self._auto_creator_runtime()
        self.alert_preference_runtime = alert_preference_runtime or self._auto_alert_preference_runtime()

    def process(self, sender_mobile: str, message: str) -> str:
        clean = str(message or "").strip()
        normalized = clean.casefold()
        if self.live_lead_service is not None:
            live_lead = self.live_lead_service.process(sender_mobile, clean)
            if live_lead is not None:
                return live_lead
        if self.alert_preference_runtime is not None:
            alert_reply = self.alert_preference_runtime.process(sender_mobile, clean)
            if alert_reply is not None:
                return alert_reply
        if self.hybrid_support is not None and normalized.startswith(("admin answer ", "support answer ")):
            admin_reply = self.hybrid_support.process(sender_mobile, clean)
            if admin_reply is not None:
                return admin_reply
        if self.creator_runtime is not None:
            creator_reply = self.creator_runtime.process(sender_mobile, clean)
            if creator_reply is not None:
                return creator_reply
        if self.ledger_runtime is not None:
            ledger_reply = self.ledger_runtime.process(sender_mobile, clean)
            if ledger_reply is not None:
                return ledger_reply
        if self.ride_runtime is not None:
            ride_reply = self.ride_runtime.process(sender_mobile, clean)
            if ride_reply is not None:
                return ride_reply
        if self.event_provider_runtime is not None:
            provider_reply = self.event_provider_runtime.process(sender_mobile, clean)
            if provider_reply is not None:
                return provider_reply
        if self.event_runtime is not None:
            event_reply = self.event_runtime.process(sender_mobile, clean)
            if event_reply is not None:
                return event_reply
        if self.catering_menu_ai is not None:
            menu_reply = self.catering_menu_ai.process_text(sender_mobile, clean)
            if menu_reply is not None:
                return menu_reply
        if self.catering_runtime is not None:
            catering = self.catering_runtime.process(sender_mobile, clean)
            if catering is not None:
                return catering
        if self.grocery_order_runtime is not None:
            order_reply = self.grocery_order_runtime.process(sender_mobile, clean)
            if order_reply is not None:
                return order_reply
        if self.grocery_runtime is not None:
            grocery = self.grocery_runtime.process(sender_mobile, clean)
            if grocery is not None:
                return grocery
        if self.seller_escalation is not None:
            learned = self.seller_escalation.consume_seller_reply(sender_mobile, clean)
            if learned is not None:
                return learned
        if normalized in self.GREETING_WORDS:
            welcome = self._registered_welcome_back(sender_mobile)
            if welcome is not None:
                return welcome

        response = self.response_commands.process_text(sender_mobile=sender_mobile, message=clean)
        if response is not None:
            return response
        if self.service_decision_assistant is not None and self._looks_like_service_request(clean):
            category = self._infer_service_category(clean)
            candidates = self._service_candidates(category)
            if candidates:
                service_plan = self.service_decision_assistant.decide(
                    {
                        "request": clean,
                        "category": category,
                        "location": self._infer_location(clean),
                        "budget": self._infer_budget(clean),
                        "urgency": "urgent" if any(token in clean.lower() for token in ("urgent", "today", "asap", "today", "పెద్దవాడు", "ఇప్పుడే")) else "normal",
                    },
                    candidates,
                )
            else:
                service_plan = {}
            if service_plan.get("best"):
                best = service_plan["best"]
                flow = self._orchestrate(
                    local_matches=[best],
                    category=category,
                )
                return f"ASKODOX AI recommendation: {best['name']} matches your {best.get('category', 'service')} request. Why: {best.get('why', 'best fit')}{self._flow_suffix(flow)}"
        if self.buyer_decision_assistant is not None and self._looks_like_buyer_intent(clean):
            category = self._infer_buyer_category(clean)
            options = self._buyer_options(category)
            affiliate_matches = self._affiliate_matches(category)
            if options:
                buying_plan = self.buyer_decision_assistant.decide(
                    {
                        "category": category,
                        "budget": self._infer_budget(clean),
                        "location": self._infer_location(clean),
                        "urgency": "urgent" if any(token in clean.lower() for token in ("urgent", "today", "asap", "ఇప్పుడే")) else "normal",
                        "must_have": ["warranty", "delivery"],
                    },
                    options,
                )
            else:
                buying_plan = {}
            if not buying_plan.get("best") and affiliate_matches:
                flow = self._orchestrate(
                    local_matches=[],
                    affiliate_matches=affiliate_matches,
                    category=category,
                )
                providers = ", ".join(
                    str(provider.get("provider_id") or provider.get("name") or "external provider")
                    for provider in affiliate_matches[:3]
                )
                return f"No confirmed local match is available yet. Verified external options: {providers}. I will show them only after both parties confirm.{self._flow_suffix(flow)}"
            if buying_plan.get("best"):
                best = buying_plan["best"]
                flow = self._orchestrate(
                    local_matches=[best] if best.get("channel") == "local" else [],
                    affiliate_matches=affiliate_matches,
                    category=category,
                )
                return f"ASKODOX buyer guide: {best['name']} is the best fit. Reasoning: {', '.join(best.get('reasoning', []))}.{self._flow_suffix(flow)}"
        if self.product_runtime is not None:
            intelligent = self.product_runtime.process(sender_mobile=sender_mobile, message=clean)
            if intelligent is not None:
                return intelligent
        faq = self._matched_product_faq(sender_mobile, clean)
        if faq is not None:
            return faq
        if self.image_service is not None:
            image_reply = self.image_service.process_text(sender_mobile=sender_mobile, message=clean)
            if image_reply is not None:
                return image_reply
        if self.live_capture is not None:
            capture = self.live_capture.process_text(sender_mobile=sender_mobile, message=clean)
            if capture is not None:
                return capture
        if self.hybrid_support is not None:
            support = self.hybrid_support.process(sender_mobile, clean)
            if support is not None:
                return support
        return self.base_conversation.process(sender_mobile=sender_mobile, message=clean)

    @staticmethod
    def _looks_like_service_request(text: str) -> bool:
        lowered = text.lower()
        keywords = (
            "plumber", "electrician", "repair", "service", "doctor", "salon",
            "mechanic", "cleaning", "service కావాలి", "సర్వీస్", "ప్లంబర్",
            "ఎలక్ట్రిషియన్", "రిపేర్",
        )
        return any(keyword in lowered for keyword in keywords)

    @staticmethod
    def _looks_like_buyer_intent(text: str) -> bool:
        lowered = text.lower()
        keywords = (
            "buy", "purchase", "price", "rate", "compare", "best", "recommend",
            "కొనాలి", "ధర", "రేట్", "సరైనది", "బెస్ట్",
        )
        return any(keyword in lowered for keyword in keywords)

    @staticmethod
    def _infer_service_category(text: str) -> str:
        lowered = text.lower()
        if "plumb" in lowered or "plumber" in lowered:
            return "plumbing"
        if "electric" in lowered or "electrician" in lowered:
            return "electrical"
        if "doctor" in lowered or "clinic" in lowered or "hospital" in lowered:
            return "medical"
        return "service"

    @staticmethod
    def _infer_buyer_category(text: str) -> str:
        lowered = text.lower()
        if "washing" in lowered or "machine" in lowered:
            return "washing machine"
        if "mobile" in lowered or "phone" in lowered:
            return "mobile phone"
        return "product"

    @staticmethod
    def _infer_location(text: str) -> str:
        lowered = text.lower()
        for token in ("vijayawada", "guntur", "vizag", "hyderabad", "bangalore", "chennai"):
            if token in lowered:
                return token
        return "local area"

    @staticmethod
    def _infer_budget(text: str) -> float:
        match = re.search(r"(?:rs\.?\s*|inr\s*|₹\s*)?(\d{3,7})", text, flags=re.IGNORECASE)
        if match:
            return float(match.group(1))
        return 0.0

    def _service_candidates(self, category: str) -> list[dict]:
        source = self.profile_source
        if source is None and self.live_capture is not None:
            source = getattr(getattr(self.live_capture, "targeting", None), "profile_source", None)
        if not callable(source):
            return []
        candidates = []
        wanted = str(category or "service").casefold()
        for profile in source() or []:
            role = str(profile.get("role") or profile.get("profile_type") or "").upper()
            service = str(profile.get("service") or profile.get("category") or profile.get("skill") or "")
            if role not in {"SERVICE_PROVIDER", "PROVIDER", "BUSINESS", "BOTH"} or wanted not in service.casefold():
                continue
            candidates.append({
                "name": str(profile.get("name") or profile.get("user_id") or "Service provider"),
                "location": str(profile.get("location") or profile.get("area") or "local area"),
                "distance_km": profile.get("distance_km"),
                "price": profile.get("price"),
                "verified": str(profile.get("id_verification_status") or "").upper() == "VERIFIED",
                "available": bool(profile.get("available", True)),
                "rating": profile.get("rating", 0),
            })
        return candidates

    def _buyer_options(self, category: str) -> list[dict]:
        search = getattr(self.catalog_repository, "search_active", None)
        if not callable(search):
            return []
        options = []
        for product in search(category, limit=10) or []:
            options.append({
                "name": str(product.get("seller_name") or product.get("subject") or "Local seller"),
                "channel": "local",
                "price": product.get("price"),
                "verified": str(product.get("id_verification_status") or "").upper() == "VERIFIED",
                "warranty": bool(product.get("warranty")),
                "returns": bool(product.get("cancellation_policy")),
                "exact_variant": bool(product.get("variant")),
                "service_available": bool(product.get("delivery_available")),
                "delivery_minutes": product.get("delivery_minutes", 100000),
            })
        return options

    def _affiliate_matches(self, category: str) -> list[dict]:
        if self.affiliate_provider_config is None:
            return []
        return self.affiliate_provider_config.active_for_category(category)

    def _orchestrate(self, *, local_matches: list[dict], affiliate_matches: list[dict] | None = None, category: str) -> dict:
        if self.party_ai_orchestrator is None:
            return {}
        return self.party_ai_orchestrator.orchestrate({
            "intent": "buy" if local_matches and local_matches[0].get("channel") == "local" else "service",
            "category": category,
            "local_matches": local_matches,
            "affiliate_matches": affiliate_matches or [],
        })

    @staticmethod
    def _flow_suffix(flow: dict) -> str:
        if not flow:
            return ""
        if any(step.get("kind") == "affiliate_fallback" for step in flow.get("steps", [])):
            return " ASKODOX can also show verified external options; both parties confirm before contact sharing."
        return " Both parties confirm before contact sharing."

    def _database_path(self) -> str:
        try:
            users = getattr(self.base_conversation, "user_repository", None)
            database = getattr(users, "database", None)
            if database is None:
                return ""
            row = database.fetchone("PRAGMA database_list")
            return str(row["file"] or "") if row else ""
        except Exception:
            return ""

    def _auto_alert_preference_runtime(self):
        try:
            db_path = self._database_path()
            if not db_path:
                return None
            from app.repositories.proactive_alert_preference_repository import ProactiveAlertPreferenceRepository
            from app.services.proactive_alert_preference_service import ProactiveAlertPreferenceService
            return ProactiveAlertPreferenceService(ProactiveAlertPreferenceRepository(db_path))
        except Exception:
            return None

    def _auto_creator_runtime(self):
        try:
            catalog = getattr(self.product_runtime, "catalog", None)
            price_list = getattr(self.product_runtime, "price_list_ai", None)
            users = getattr(price_list, "users", None)
            db_path = str(getattr(catalog, "db_path", "") or "")
            if catalog is None or not db_path:
                return None
            from app.repositories.creator_commerce_repository import CreatorCommerceRepository
            from app.services.creator_commerce_runtime_service import CreatorCommerceRuntimeService
            return CreatorCommerceRuntimeService(CreatorCommerceRepository(db_path), catalog, user_repository=users)
        except Exception:
            return None

    def _auto_ledger_runtime(self):
        try:
            users = getattr(self.base_conversation, "user_repository", None)
            database = getattr(users, "database", None)
            if database is None:
                return None
            row = database.fetchone("PRAGMA database_list")
            db_path = str(row["file"] or "") if row else ""
            if not db_path:
                return None
            from app.repositories.business_ledger_repository import BusinessLedgerRepository
            from app.services.business_ledger_runtime_service import BusinessLedgerRuntimeService
            return BusinessLedgerRuntimeService(BusinessLedgerRepository(db_path), user_repository=users)
        except Exception:
            return None

    def _recover_accepted_deal(self, sender_mobile: str, message: str, interest: dict, request: dict) -> str | None:
        """Bridge matches accepted before Deal Discussion existed into the new state machine."""
        if str(interest.get("requester_status") or "").upper() != "ACCEPTED":
            return None
        same_context = getattr(self.response_commands, "_same_deal_context", None)
        if callable(same_context):
            try:
                if not same_context(request, message):
                    return None
            except Exception:
                pass
        if not getattr(self.response_commands, "_looks_like_deal_change", lambda _text: False)(message):
            return None
        deals = getattr(self.response_commands, "deals", None)
        if deals is None:
            return None
        seller = str(interest.get("responder_user_id") or "")
        if not seller:
            return None
        request_id = int(request["id"])
        try:
            existing = deals.repository.get(request_id, seller)
            if existing is None:
                deals.start(request, sender_mobile, seller)
            prompt = deals.ask_for_change(request, sender_mobile, seller)
            if "readyగా లేదు" in str(prompt):
                return None
            return deals.consume_buyer_change(request, sender_mobile, seller, message)
        except Exception:
            return None

    def _same_product_context(self, request: dict, message: str) -> bool:
        """Keep legacy matched-product FAQ answers scoped to the active subject."""
        same_context = getattr(self.response_commands, "_same_deal_context", None)
        if callable(same_context):
            try:
                return bool(same_context(request, message))
            except Exception:
                pass
        router = getattr(self.product_runtime, "context_router", None)
        if router is not None:
            try:
                return not bool(router.introduces_new_subject(request, message))
            except Exception:
                pass
        return True

    def _matched_product_faq(self, sender_mobile: str, message: str) -> str | None:
        lowered = message.casefold()
        repo = getattr(self.response_commands, "notification_repository", None)
        demands = getattr(self.response_commands, "demands", None)
        if (
            not any(word in lowered for word in self.PRODUCT_QUESTION_WORDS)
            or repo is None
            or demands is None
            or not hasattr(repo, "latest_interest_for_buyer")
        ):
            return None
        interest = repo.latest_interest_for_buyer(sender_mobile)
        if not interest:
            return None
        request = demands.get(int(interest["request_id"]))
        if not request or str(request.get("domain") or "").upper() != "PRODUCT":
            return None
        if not self._same_product_context(request, message):
            return None

        recovered = self._recover_accepted_deal(sender_mobile, message, interest, request)
        if recovered is not None:
            return recovered

        subject = str(request.get("subject") or "Product")
        side = str(request.get("side") or "").upper()
        seller_status = str(interest.get("requester_status") or "PENDING").upper()
        if "ధర" in lowered or "price" in lowered or "ఎంత" in lowered or "రేట్" in lowered:
            if side == "OFFER" and request.get("price") is not None:
                return f"💰 {subject} seller listed price ₹{self._money(request.get('price'))}."
            return f"💰 {subject} seller final price ఇంకా confirm కాలేదు. Price తెలియకుండా PODX order continue చేయదు."
        if any(w in lowered for w in ("available", "availability", "stock", "దొరుకుతుందా", "ఉందా")):
            if seller_status == "ACCEPTED":
                return f"✅ Seller {subject} available అని confirm చేశారు."
            if seller_status == "REJECTED":
                return f"ఈ seller దగ్గర {subject} ప్రస్తుతం available లేదు."
            return f"⏳ {subject} availability seller confirmation కోసం wait చేస్తున్నాను."
        if any(w in lowered for w in ("quantity", "weight", "size")):
            if request.get("quantity") is not None:
                return f"📦 ప్రస్తుతం requestలో quantity: {request.get('quantity')} {request.get('unit') or ''}.".strip()
            return f"📦 {subject} exact size/quantity seller-confirmed dataలో ఇంకా లేదు."
        if "delivery" in lowered:
            return "🚚 Seller confirm తర్వాత Order Continue ఎంచుకుంటే delivery address తీసుకుని order process చేస్తాను."
        if any(w in lowered for w in ("warranty", "return", "expiry", "feature", "features", "original", "color", "colour", "variant", "details", "ఎలా", "ఏమిటి", "doubt")):
            return f"🤖 {subject} గురించి ఈ detail seller-confirmed product profileలో ఇంకా లేదు. నేను ఊహించి చెప్పను; seller-confirmed సమాచారం వచ్చిన తర్వాతనే చెప్తాను."
        return None

    @staticmethod
    def _money(value) -> str:
        try:
            n = float(value)
            return f"{n:,.0f}" if n.is_integer() else f"{n:,.2f}"
        except (TypeError, ValueError):
            return str(value)

    def _registered_welcome_back(self, sender_mobile: str) -> str | None:
        users = getattr(self.base_conversation, "user_repository", None)
        sessions = getattr(self.base_conversation, "session_registry", None)
        if users is None:
            return None
        user = users.find_by_whatsapp_mobile(sender_mobile)
        if not user or user.get("registration_complete") != 1:
            return None
        if sessions is not None:
            session = sessions.get(sender_mobile)
            try:
                from app.models.session import ConversationStep
                session.step = ConversationStep.MAIN_MENU
                session.data.clear()
                sessions.save(sender_mobile)
            except Exception:
                pass
        name = str(user.get("name") or "").strip()
        language = str(user.get("language") or "English").strip().casefold()
        hour = datetime.now(ZoneInfo("Asia/Kolkata")).hour
        period = "morning" if hour < 12 else ("afternoon" if hour < 17 else "evening")
        if language == "telugu":
            wish = {"morning": "శుభోదయం", "afternoon": "శుభ మధ్యాహ్నం", "evening": "శుభ సాయంత్రం"}[period]
            person = f", {name} గారు" if name else ""
            return f"👋 {wish}{person}! PODXకి మళ్లీ స్వాగతం.\n\nఈరోజు మీకు ఎలా సహాయం చేయగలను? మీకు కావాల్సింది మీ మాటల్లో 🎙️ voiceగా లేదా ⌨️ textగా చెప్పండి."
        if language == "hindi":
            wish = {"morning": "सुप्रभात", "afternoon": "शुभ दोपहर", "evening": "शुभ संध्या"}[period]
            person = f", {name} जी" if name else ""
            return f"👋 {wish}{person}! PODX में आपका फिर से स्वागत है।\n\nआज मैं आपकी कैसे मदद कर सकता हूँ? जो चाहिए उसे अपनी भाषा में 🎙️ voice या ⌨️ text में बताइए।"
        wish = {"morning": "Good morning", "afternoon": "Good afternoon", "evening": "Good evening"}[period]
        person = f", {name}" if name else ""
        return f"👋 {wish}{person}! Welcome back to PODX.\n\nHow may I help you today? Tell me what you need in your own words by 🎙️ voice or ⌨️ text."