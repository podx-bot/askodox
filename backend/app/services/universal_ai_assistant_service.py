"""Universal AI understanding layer for ASKODOX conversations.

The model is responsible for natural-language understanding and emits a small,
structured decision. Deterministic business modules still execute the action and
remain the source of truth for payments, bookings, matching and safety checks.
"""
from __future__ import annotations

import json
import logging
import re
import time
from typing import Any

import httpx
from google import genai
from google.genai import errors as genai_errors
from google.genai import types

from app.services.runtime_time_context import grounded_search_query, needs_live_verification, runtime_context_block
from app.services.conversation_relation import ConversationRelationEngine
from app.services import advice_memory

logger = logging.getLogger(__name__)


def _observe_ai(provider: str, *, ok: bool = False, error: Exception | None = None) -> None:
    """Provider health from the real call: only the HTTP status and the
    exception type / a quota marker are kept -- never the prompt, user text,
    response or any credential."""
    try:
        from app.services import provider_health

        if ok:
            provider_health.record(provider, ok=True)
            return
        code = getattr(error, "code", None) or getattr(getattr(error, "response", None), "status_code", None)
        text = str(error or "")
        try:  # OpenAI puts the machine code (e.g. insufficient_quota) in the body
            body = getattr(error, "response", None).json()
            text += " " + str(((body or {}).get("error") or {}).get("code") or "")
        except Exception:
            pass
        quota = "QUOTA" if re.search(r"quota|RESOURCE_EXHAUSTED|insufficient_quota|billing|credit", text, re.I) else ""
        provider_health.record(provider, status_code=code if isinstance(code, int) else None,
                               reason=f"{type(error).__name__} {quota}".strip())
    except Exception:
        pass



_LANGUAGE_NAMES = {
    "en": "English", "te": "Telugu", "hi": "Hindi", "ta": "Tamil", "kn": "Kannada", "ml": "Malayalam",
    "bn": "Bengali", "mr": "Marathi", "gu": "Gujarati", "pa": "Punjabi", "or": "Odia", "ur": "Urdu",
    "as": "Assamese", "mni": "Manipuri", "sat": "Santali",
}


def _reply_language_rule(locale: str) -> str:
    """The app sends the CONVERSATION language (the user's Preferred Language,
    or the one they have been using). It is authoritative: a short reply
    such as 'yes', 'ok', 'go' or '?' must never switch the reply to English."""
    code = str(locale or "").strip().lower().split("-")[0].split("_")[0]
    name = _LANGUAGE_NAMES.get(code)
    if not name:
        return "Locale hint: auto\n"
    return (
        f"Reply language: {name} ({code}). Write reply in {name}{'' if code == 'en' else ' (native script)'} for EVERY turn, including short "
        "answers like yes / ok / go / ? and messages that contain English words, brand names or numbers. "
        "Only a clear request to change language changes this. Keep brand names, product names and source "
        "titles as they are.\n"
    )

# The Conversation Decision Brain's state + search-readiness rules. Generic
# for every domain (products, services, jobs, travel, finance, unknown
# categories): no category scripts, no fixed questionnaire, no keyword ->
# question lists. The app searches only when ``search_ready`` is true.
# Reasoning before results (APK 1311): result cards SUPPORT the answer, they
# never replace it. One rule for every domain -- products, services, business,
# finance, personal decisions -- never a per-category script.
DECISION_GUIDANCE_RULES = (
    "Decision guidance (every domain, every language; you are a personal advisor and decision partner, not a "
    "search box): the reply must first genuinely help with what the user asked, whether or not options will be "
    "shown. Answer the actual question. When the user gave numbers (area, size, quantity, duration, people, "
    "budget, income, distance), do the practical working with THEIR numbers: quantities needed including the usual "
    "extra / wastage / margin, and an approximate cost breakdown or budget fit -- label every figure as a general "
    "estimate ('approx.', 'typically', 'varies by place and brand') and never present it as a verified local price, "
    "stock, rating or availability (verified listings are shown separately by the app, only from real sources). Add "
    "the 2-3 selection or decision points that matter most for THIS need, and any meaningful risk or better "
    "alternative once (one-time advice rule). Then ask at most ONE question, only if its answer materially changes "
    "the recommendation. Keep it short and scannable (a few lines or bullets, under about 120 words). Never name "
    "specific shops or providers from memory and never say results are being shown. Ordinary chat, greetings and "
    "simple facts get a natural direct answer -- no forced guidance, no commerce. "
)

CONVERSATION_STATE_RULES = (
    "Conversation state and search readiness (any domain, any category, any language; never a fixed questionnaire, "
    "never a per-category script): search is a TOOL, not the default response to a product or service noun. "
    "From the WHOLE conversation (history + current message) return state = {goal: one short line, "
    "facts: object of every requirement the user supplied or unambiguously implied so far (short snake_case keys of "
    "your choice, values as the user meant them; a later statement replaces an earlier one; a short reply such as "
    "'30-40 thousand', 'two door', 'multi use', 'yes', '150 sq ft' answers the question the assistant just asked), "
    "flexible: list of the fact keys the user is flexible about ('any', 'no preference', 'X okay, others also fine') "
    "-- only the preference being discussed, never everything, unknown_critical: list of the few still-unknown things "
    "that would MATERIALLY change which options are right for THIS user (judge it for this specific need; leave out "
    "anything that only fine-tunes)}. "
    "HARD GATE: never return result cards merely because a product/service/category was named. Conversation controls "
    "retrieval, never the reverse. search_ready = true only when searching now would give this user genuinely useful, "
    "well-targeted options: the need is clear and unknown_critical is empty, OR the user explicitly asks to see options "
    "now (show me / search / any is fine), OR asks where to buy or get it, OR asks for videos/reviews. A broad first message that only names a "
    "product, service or category is usually NOT ready. A message that already contains what matters IS ready -- "
    "never ask for anything already known and never ask just to fill a form. "
    "When search_ready is false for a request that needs options: next_question = the ONE most useful question "
    "(the unknown that most changes the decision), natural and in the user's language; reply must end with exactly "
    "that question and must not mention results; ask only one question per turn. "
    "When search_ready is true: next_question = null; search_subject = one concise consolidated search phrase for "
    "the wanted thing built from the accumulated facts (the item or service plus its defining attributes such as "
    "type, size, capacity, material, firm brand; no budget, no location, no filler words); reply = the decision "
    "guidance below (never a bare acknowledgement) and it never claims results. "
    "Genuinely ambiguous intent (for example 'delivery cheyali' = a delivery job vs sending a parcel): ask which, "
    "search_ready false. Advice / decision questions, general chat and questions about options already shown: "
    "search_ready false, next_question null unless a question is genuinely needed. "
    "Only real decision criteria block a search: what the thing or service is (its kind/type), its primary intended use "
    "when that materially changes the right options, its size/capacity/variant when that changes which options fit, the "
    "budget when prices span widely, condition (new/used/refurbished) when the market mixes them and the user has not "
    "made it open, and for a service the job itself (and the date when it must be booked). Taste preferences -- brand, colour, finish, style, design, extras -- NEVER block a "
    "search when the user did not state them: leave them open (flexible) and refine after the user sees options. "
    "Internal layout, compartments, features and add-ons are refinements too: once the kind of thing, its main "
    "size/capacity/variant (when it has one) and the budget are known, the need IS ready -- ask about refinements only "
    "after options are shown. Likewise for a service or job: once the work itself, the place and (when it must be "
    "booked) the date are known, it IS ready -- tools, method, worker details and extras are for the provider to "
    "settle. On a ready turn the reply asks nothing (no brand or taste question). "
    "If 'Already searched for' is given and the message continues the SAME need: search_ready = true only when the new "
    "facts change which options fit (a different kind/type, size/capacity, budget range, a firm brand, another place); "
    "a brand the user is flexible about ('X okay, others also okay') is NOT a firm brand and never re-searches; "
    "a detail that does not change them (delivery wish, relaxed or open preference, usage note, timing for a service "
    "already found) keeps search_ready false with next_question null, and the reply relates it to the current options. "
    "ready_reason = one short phrase explaining the readiness decision. "
    "new_need = true only when the current message starts a DIFFERENT need from the one being discussed (a new item "
    "or service, not an answer, correction or refinement of the current one); then state describes the new need only. "
    "A short message that only adds a budget, place, time, quantity, a channel or platform (online, local, a "
    "marketplace or shop name) or picks from the options already shown is NEVER a new need. "
)


class UniversalAIAssistantService:
    GENERAL_MARKER = "OASAT domain=GENERAL;"
    ALLOWED_DOMAINS = {
        "GENERAL", "JOB_SEEKER", "STAFFING", "SERVICE", "PARCEL", "RIDE",
        "PRODUCT", "FOOD", "EVENT", "APPOINTMENT", "LEDGER", "UNKNOWN",
    }
    ALLOWED_ENTITY_KEYS = {
        "subject", "category", "role", "skill", "quantity", "unit", "headcount",
        "date", "time", "timing", "location", "from", "to", "budget", "price",
        "salary", "pay", "pay_basis", "duration", "shift", "context", "variant",
        "quality", "size", "model", "brand", "fulfilment", "availability", "specialist",
        "service_type", "job_type", "seats", "notes", "clarify_options",
    }
    # Phrases that indicate the model's reply is asking the user for their
    # location/address, in the language mixes ASKODOX users actually type in.
    _LOCATION_ASK_KEYWORDS = (
        "location", "your address", "delivery address", "delivery location",
        "which area", "which place",
        "లొకేషన్", "లొకేషన", "చిరునామా", "ఎక్కడ ఉన్నారు", "ఎక్కడ నుండి",
        "ఎక్కడ తెలియ", "ఎక్కడ చెప్ప", "ఎక్కడో", "పిన్ కోడ్", "పిన్‌కోడ్",
    )
    _LOCATION_FALLBACK_REPLY = {
        "te": "సరే, మీ సేవ్ చేసిన లొకేషన్ ఉపయోగించి కొనసాగిస్తున్నాను.",
        "en": "Got it — continuing with your saved location.",
    }

    def __init__(
        self,
        delegate,
        *,
        api_key: str,
        model: str,
        client: Any | None = None,
        openai_api_key: str = "",
        openai_model: str = "gpt-5",
        http_client: Any | None = None,
        research_service: Any | None = None,
        clock: Any | None = None,
    ) -> None:
        self.delegate = delegate
        # Live evidence for time-sensitive facts (OASATLiveResearchService) and
        # the runtime clock used for "today / this year / now" grounding.
        self.research_service = research_service
        self.clock = clock
        self.api_key = str(api_key or "").strip()
        self.model = str(model or "gemini-3.6-flash").strip()
        self.client = client or (genai.Client(api_key=self.api_key) if self.api_key else None)
        self.openai_api_key = str(openai_api_key or "").strip()
        self.openai_model = str(openai_model or "gpt-5").strip()
        self.http = http_client or httpx.Client(timeout=20.0)
        # APK 1305: deterministic conversation-relation layer. Corrects the
        # model's probabilistic new_need judgment and anchors result-deck
        # retirement to the ACTIVE need instead of message order.
        self.relation_engine = ConversationRelationEngine()

    @property
    def configured(self) -> bool:
        return bool(self.client or self.api_key)

    @classmethod
    def _clean_entities(cls, raw: Any) -> dict[str, Any]:
        """Keep only portable semantic values safe for deterministic app logic."""
        if not isinstance(raw, dict):
            return {}
        result: dict[str, Any] = {}
        for key, value in raw.items():
            clean_key = str(key or "").strip().lower()
            if clean_key not in cls.ALLOWED_ENTITY_KEYS or value is None:
                continue
            if isinstance(value, bool):
                result[clean_key] = value
            elif isinstance(value, (int, float)):
                result[clean_key] = value
            elif isinstance(value, str):
                clean_value = value.strip()
                if clean_value:
                    result[clean_key] = clean_value[:500]
            elif isinstance(value, list):
                items = [str(item).strip()[:200] for item in value if str(item).strip()]
                if items:
                    result[clean_key] = items[:20]
        return result


    # ------------------------------------------------------------------
    # Decision brain: what the USER said vs what the app appended.
    # The app appends context after the user's words (the options already
    # shown, the option asked about, attachment / sign-off guidance). That
    # context mentions "reviews", "rating" etc., so deterministic checks
    # must look only at the user's own words -- reading the context turned
    # every question about shown options into "looking for real videos and
    # reviews" (APK 1302 phone test).
    _APP_CONTEXT_MARKERS = (
        "Options already shown to the user:",
        "Option the user is asking about:",
        "Compare for the user.",
        "The customer shared attachment",
        "The customer is ending the conversation",
    )
    _ABOUT_SHOWN_MARKERS = _APP_CONTEXT_MARKERS[:3]

    @staticmethod
    def reconcile_relation(relation, model_new_need: bool, brain: dict, active_subject: str,
                           said_subject: str = "") -> tuple[str, bool]:
        """Combine the deterministic relation with the model's own judgment.

        A confident relation (>= 0.7) stands. A WEAK new-topic / return signal
        (e.g. one new word: a brand of the same need, or a new thing?) counts
        only when the model also says this is a new need. When the relation
        layer cannot tell (cross-script, thin text) but the model says new
        need and the model's own description of the need shares nothing with
        the active one, the old results retire too.
        """
        from app.services.conversation_relation import _overlap, _scripts
        name = relation.relation
        changed = bool(relation.subject_replaced)
        if relation.confidence < 0.7 and name in {"new_topic", "return_to_previous"}:
            if not model_new_need:
                return "unknown", False
            return name, changed
        if name == "unknown" and model_new_need and relation.has_active_deck and active_subject:
            state = brain.get("state") or {}
            facts = state.get("facts") or {}
            described = " ".join(
                [str(brain.get("search_subject") or ""), str(state.get("goal") or "")]
                + [str(v) for v in facts.values()][:12])
            subjects = [s for s in (active_subject, said_subject) if s.strip()]
            comparable = any(_scripts(described) & _scripts(s) for s in subjects)
            if described.strip() and comparable and max(_overlap(described, s) for s in subjects) == 0:
                return "new_topic", True
        return name, changed

    @staticmethod
    def _short(value: Any, limit: int) -> Any:
        if isinstance(value, bool) or isinstance(value, (int, float)):
            return value
        if isinstance(value, list):
            return [str(v)[:limit] for v in value[:10] if str(v).strip()]
        return str(value or "").strip()[:limit]

    @classmethod
    def brain_state(cls, data: dict[str, Any], *, transactional: bool, mode: str, action: str) -> dict[str, Any]:
        """The Conversation Decision Brain's state for this turn, normalized:
        accumulated facts / flexible preferences / decision-critical unknowns,
        whether a search is justified now, the ONE next question and the
        consolidated search subject. ``search_ready`` is None only when the
        model gave no readiness (the app then keeps its offline rule)."""
        raw_state = data.get("state") if isinstance(data.get("state"), dict) else {}
        facts_in = raw_state.get("facts") if isinstance(raw_state.get("facts"), dict) else {}
        facts = {}
        for key, value in list(facts_in.items())[:30]:
            name = re.sub(r"[^a-z0-9_]+", "_", str(key).strip().lower()).strip("_")[:40]
            clean_value = cls._short(value, 200)
            if name and clean_value not in ("", [], None):
                facts[name] = clean_value
        def names(raw: Any) -> list[str]:
            items = raw if isinstance(raw, list) else []
            return [str(x).strip()[:80] for x in items[:12] if str(x).strip()]
        state = {
            "goal": str(raw_state.get("goal") or "").strip()[:200],
            "facts": facts,
            "flexible": [re.sub(r"[^a-z0-9_]+", "_", f.lower()).strip("_") for f in names(raw_state.get("flexible"))],
            "unknown_critical": names(raw_state.get("unknown_critical")),
        }
        raw_ready = data.get("search_ready")
        if isinstance(raw_ready, str):
            raw_ready = {"true": True, "false": False}.get(raw_ready.strip().lower())
        ready: bool | None = raw_ready if isinstance(raw_ready, bool) else None
        question = str(data.get("next_question") or "").strip()[:300] or None
        subject = str(data.get("search_subject") or "").strip()[:120] or None
        if mode in {"advice", "follow_up"} or not transactional:
            # Reasoning / options already shown / chat: never a search.
            ready = False
            question = question if mode == "chat" and transactional else None
        elif action in {"search_videos", "find_local"}:
            ready = True  # the user asked to see videos / where to get it
        if ready:
            question = None
        else:
            subject = None
        return {
            "state": state,
            "search_ready": ready,
            "next_question": question,
            "search_subject": subject,
            "ready_reason": str(data.get("ready_reason") or "").strip()[:200],
            "new_need": data.get("new_need") is True or str(data.get("new_need")).strip().lower() == "true",
        }

    @classmethod
    def split_app_context(cls, message: str) -> tuple[str, str, bool]:
        """(user_text, app_context, about_shown_options)."""
        text = str(message or "")
        cut = len(text)
        for marker in cls._APP_CONTEXT_MARKERS:
            at = text.find(marker)
            if at >= 0:
                cut = min(cut, at)
        user = text[:cut].strip()
        context = text[cut:].strip()
        about = any(m in context for m in cls._ABOUT_SHOWN_MARKERS)
        return (user or text.strip()), context, about

    # Advice / decision questions get reasoning, not result cards.
    _ADVICE_ASK = re.compile(
        r"\bshould (i|we)\b|\bis (it|this|that) (a )?(good|bad|wise|safe|sensible|worth)\b|\bworth it\b"
        r"|\b(what are|any) (the )?(risks?|pros|cons|downsides?)\b|\bpros (and|&) cons\b|\brisks? (of|in)\b"
        r"|\bwhich (business|model|loan|plan|option|policy|scheme|investment|course|career|is (safer|better|suitable|right))\b"
        r"|\bhow (much|many)\b.{0,40}\b(do|would|will) (i|we) need\b|\bwhat\b.{0,25}\b(capacity|size|tonnage|ton|wattage|amount|budget|coverage|cover)\b.{0,40}\bneed\b"
        r"|\b(can|could) (i|we) afford\b|\bfinancially\b|\bhelp me (decide|choose|plan)\b|\b(advice|advise|guidance)\b"
        r"|\b(is|are) .{0,40}\b(profitable|viable|feasible)\b|\bbusiness (plan|idea|model)\b|\bstart (a|an|my) .{0,40}business\b"
        r"|చేయాలా|చేయవచ్చా|మంచిదా|సరైనదా|రిస్క్|లాభనష్టాలు|నష్టాలు|సలహా|ఏది (మంచిది|సురక్షితం)|ఎంత .{0,20}కావాలి"
        r"|करना चाहिए|सलाह|जोखिम|फायदे.{0,10}नुकसान|कितना .{0,20}चाहिए",
        re.IGNORECASE)
    # ... unless the user plainly asks to see / buy / find things now.
    _COMMERCE_NOW = re.compile(
        r"\b(show|find|list|search|book|order|buy now|near me|nearby|shops?|stores?|dealers?|sellers?|price list|deals?|offers?)\b"
        r"|చూపించు|చూపండి|కొనాలి|దగ్గర|షాప్|दिखाओ|दिखाइए|खरीदना|दुकान",
        re.IGNORECASE)

    @classmethod
    def wants_advice(cls, user_text: str) -> bool:
        text = user_text or ""
        return (bool(cls._ADVICE_ASK.search(text)) and not cls._COMMERCE_NOW.search(text)
                and not cls._asks_where_to_get(text) and not cls._asks_for_videos(text))

    def _advise(self, user_text: str, history: list[dict[str, str]], locale: str, location: str,
                advice_ledger: list[dict[str, Any]] | None = None) -> tuple[str, Any]:
        """A full advisory answer (decision mode): goal, decision-critical
        gaps, reasoning, numbers, risks, alternatives, recommendation, why,
        next steps. Returns ("", None) when no model answered; otherwise the
        answer and the concern it raised (one-time advice memory)."""
        prompt = (
            "You are ASKODOX's decision advisor for people in India. The user wants ADVICE / a DECISION, not a "
            "list of shops. Think like an experienced, honest advisor.\n"
            "Answer in this order, using short headings and bullet points, in the user's language:\n"
            "1. Your goal (one line: what they are really trying to decide).\n"
            "2. What I still need to know -- ONLY the 1-3 facts that would change the recommendation, and only if "
            "not already known from the conversation. Never re-ask anything already given.\n"
            "3. Analysis -- reason step by step; when numbers help (capacity, EMI, margin, break-even, running "
            "cost), calculate with the user's own numbers and show the formula briefly; say clearly when a number is "
            "an assumption.\n"
            "4. Risks and what could go wrong (be specific; challenge unsafe or unrealistic assumptions politely).\n"
            "5. Options compared (pros / cons of 2-3 realistic alternatives).\n"
            "6. My recommendation and WHY.\n"
            "7. Next steps (concrete actions; you may offer: 'Say \"show me options\" to see real sellers / offers').\n"
            "Rules: never invent prices, laws, interest rates, product specs or shop names as facts -- give typical "
            "ranges and say they vary; recommend verifying regulated matters (loans, insurance, licences, tax, "
            "health) with a qualified professional; no result cards are shown for this answer.\n"
            "If the user has already decided, do not argue again: help them do it well (one line on any concern "
            "that is still critical, then practical steps for the option they chose).\n"
            + advice_memory.prompt_block(advice_ledger or [])
            + "After the answer, end with ONE last line exactly like ADVICE_META: {\"key\": ..., \"summary\": ..., "
            "\"severity\": ..., \"repeat_reason\": ...} (or ADVICE_META: null). It is removed before display.\n"
            + _reply_language_rule(locale)
            + (f"Known user location: {location}\n" if location else "")
            + f"Conversation so far JSON: {json.dumps(history, ensure_ascii=False)}\n"
            + f"User's question: {user_text}"
        )
        text = ""
        if self.configured:
            try:
                client = self.client or genai.Client(api_key=self.api_key)
                config = types.GenerateContentConfig(
                    temperature=0.3, max_output_tokens=3072,
                    thinking_config=types.ThinkingConfig(thinking_budget=0))
                response = self._generate_with_retry(client, prompt, config)
                text = str(getattr(response, "text", "") or "").strip()
            except Exception:
                logger.exception("universal_ai_assistant.advise: gemini call failed (len=%d)", len(user_text))
        if not text and self.openai_api_key:
            try:
                response = self.http.post(
                    "https://api.openai.com/v1/responses",
                    headers={"Authorization": f"Bearer {self.openai_api_key}", "Content-Type": "application/json"},
                    json={"model": self.openai_model,
                          "input": [{"role": "user", "content": [{"type": "input_text", "text": prompt}]}]})
                response.raise_for_status()
                text = self._openai_output_text(response.json())
            except Exception:
                logger.exception("universal_ai_assistant.advise: openai fallback failed (len=%d)", len(user_text))
        if text.startswith("{"):
            try:  # a model that answered JSON anyway
                parsed = json.loads(text)
                return str(parsed.get("reply") or "").strip(), parsed.get("advice")
            except (ValueError, AttributeError):
                pass
        return advice_memory.split_meta(text)

    @classmethod
    def _reply_asks_for_location(cls, sentence: str) -> bool:
        """True if a sentence looks like it is asking the user for a location.

        Only a sentence that both mentions a location-ish keyword AND reads
        as a question is treated as an ask -- this avoids stripping a
        sentence that merely mentions "location" in passing.
        """
        if "?" not in sentence and "గలరా" not in sentence and "చెప్పగలరా" not in sentence:
            return False
        lowered = sentence.lower()
        return any(keyword.lower() in lowered for keyword in cls._LOCATION_ASK_KEYWORDS)

    _VIDEO_ASK = re.compile(
        r"\b(videos?|reviews?|youtube|unboxing|demo|comparison|reels?|shorts|clips?)\b|(వీడియో|విడియో|రివ్యూ|రివ్యు|సమీక్ష|పోలిక|యూట్యూబ్|వీడియోలు|वीडियो|रिव्यू|समीक्षा)",
        re.IGNORECASE)

    # Platform / channel / setup words: talking ABOUT a video platform or its
    # setup is conversation, not a request to search videos of something.
    _PLATFORM_TALK = re.compile(
        r"\b(facebook|fb|instagram|insta|ig|meta|whatsapp|youtube|yt|reels?|shorts?|tiktok|snapchat|twitter|"
        r"threads|api|apis|sdk|app|apps|account|accounts|page|pages|profile|handle|setup|set\s*up|integration|"
        r"integrate|configure|configuration|config|login|channel|business\s+suite|creator\s+studio|token|"
        r"webhook|permission|permissions|review\s+process|app\s+review)\b"
        r"|ఫేస్‌?బుక్|ఇన్‌?స్టా(?:గ్రామ్)?|యూట్యూబ్|వాట్సాప్|फेसबुक|इंस्टाग्राम|यूट्यूब",
        re.IGNORECASE)
    _VIDEO_WORDS = re.compile(
        r"\b(videos?|reviews?|youtube|unboxing|demo|demos|comparison|clips?|reels?|shorts?)\b"
        r"|వీడియో\S*|విడియో\S*|రివ్యూ\S*|రివ్యు\S*|సమీక్ష\S*|పోలిక\S*|यूट्यूब|वीडियो|रिव्यू|समीक्षा",
        re.IGNORECASE)

    @classmethod
    def _video_subject(cls, text: str) -> set[str]:
        """What the videos would be ABOUT, once video / platform / grammar
        words are removed (empty = no searchable subject)."""
        from app.services.conversation_relation import _content_tokens
        stripped = cls._PLATFORM_TALK.sub(" ", cls._VIDEO_WORDS.sub(" ", text or ""))
        return _content_tokens(stripped)

    def _video_search_wanted(self, user_text: str, entities: dict, model_transactional: bool,
                             searched_for: dict | None) -> bool:
        """A video ask is a search only when there is something to search
        videos OF. "facebook and instagram videos kuda chupinchali" while
        setting up Meta is conversation; "Samsung S23 review videos" or
        "show videos" about the need on screen is a search."""
        if self._video_subject(user_text):
            return True
        subject = str((entities or {}).get("subject") or "")
        if subject and self._video_subject(subject) and not self._PLATFORM_TALK.search(user_text or ""):
            return True
        # "show me videos" about the options / need already on screen.
        active = str((searched_for or {}).get("subject") or "")
        return bool(active) and not self._PLATFORM_TALK.search(user_text or "")

    @classmethod
    def _asks_for_videos(cls, text: str) -> bool:
        return bool(cls._VIDEO_ASK.search(text or ""))

    _WHERE_TO_GET = re.compile(
        r"\bwhere (can|do|should|could) (i|we) (get|buy|find|purchase|book)\b|\bwhere to (get|buy|find|book)\b"
        r"|\b(shops?|stores?|dealers?|showrooms?) (near|nearby|around)\b"
        r"|ఎక్కడ (దొరుకు|కొన|లభి)|ఎక్కడ దొరుకుతుంది|कहाँ मिल|कहां मिल|कहाँ से खरीद|कहां से खरीद",
        re.IGNORECASE)

    @classmethod
    def _asks_where_to_get(cls, text: str) -> bool:
        return bool(cls._WHERE_TO_GET.search(text or ""))

    @staticmethod
    def _local_search_reply(locale: str) -> str:
        if str(locale or "").lower().startswith("te"):
            return "సరే, మీ దగ్గర నిజంగా ఉన్న షాపులు, విక్రేతలు, ఆన్‌లైన్ ఆప్షన్లు వెతుకుతున్నాను."
        if str(locale or "").lower().startswith("hi"):
            return "ठीक है, आपके पास असली दुकानें, विक्रेता और ऑनलाइन विकल्प देखता हूं।"
        return "Let me check real sellers, shops and online options near you."

    @staticmethod
    def _video_search_reply(locale: str) -> str:
        if str(locale or "").lower().startswith("te"):
            return "సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను."
        if str(locale or "").lower().startswith("hi"):
            return "ठीक है, असली वीडियो और रिव्यू ढूंढ रहा हूं -- नतीजे नीचे दिखेंगे।"
        return "Sure -- looking for real videos and reviews."

    @classmethod
    def _strip_location_question(cls, reply: str, locale: str) -> str:
        """Deterministically remove any location question from a reply.

        The prompt instructs the model never to re-ask for a known location,
        but LLM instruction-following is probabilistic, not guaranteed --
        live testing showed the same known-location input sometimes still
        produced a location question. This code-level guard makes the
        behaviour deterministic regardless of what the model does.
        """
        sentences = re.split(r"(?<=[.?!])\s+", reply.strip())
        kept = [s for s in sentences if s.strip() and not cls._reply_asks_for_location(s)]
        if kept:
            return " ".join(kept).strip()
        # The whole reply was a location question -- fall back to a short,
        # honest continuation rather than showing the user an empty bubble.
        return cls._LOCATION_FALLBACK_REPLY["te" if locale == "te" else "en"]

    def _generate_with_retry(
        self, client: Any, prompt: str, config: Any, *, attempts: int = 3, base_delay: float = 0.6
    ) -> Any:
        """Call generate_content with a short retry for transient server overload.

        Production logs showed Gemini occasionally answering with a 503
        ServerError ("This model is currently experiencing high demand ...
        usually temporary") that clears within a second or two -- the very
        next identical request often succeeds. The SDK's own internal retry
        already exhausts before raising, so this adds one more short,
        ASKODOX-side retry for that specific transient case instead of
        immediately giving up and showing the user a generic fallback reply.
        Any other exception type is not retried here; it propagates to the
        caller's exception handler as before.
        """
        last_error: Exception | None = None
        for attempt in range(attempts):
            try:
                return client.models.generate_content(model=self.model, contents=prompt, config=config)
            except genai_errors.ServerError as exc:
                last_error = exc
                if attempt < attempts - 1:
                    time.sleep(base_delay * (attempt + 1))
                    continue
        raise last_error

    def _call_openai(self, prompt: str) -> dict[str, Any]:
        response = self.http.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {self.openai_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": self.openai_model,
                "input": [{"role": "user", "content": [{"type": "input_text", "text": prompt}]}],
            },
        )
        response.raise_for_status()
        return self._parse_json(self._openai_output_text(response.json()))

    def provider_health_check(self, provider: str) -> dict[str, Any]:
        """One tiny real call to ONE provider (Command Center "Check now").

        LIVE only when that provider itself answers successfully -- a Gemini
        check never falls back to OpenAI (or the reverse). The result holds a
        state, the HTTP status and a short safe detail: never the prompt, the
        response body or a credential."""
        from app.services import provider_health

        if provider == "gemini":
            if not self.api_key and self.client is None:
                return {"ok": False, "state": provider_health.NEEDS_CONFIGURATION, "status_code": None,
                        "detail": "Gemini API key is not set on this deployment"}
            try:
                client = self.client or genai.Client(api_key=self.api_key)
                config = types.GenerateContentConfig(
                    temperature=0, max_output_tokens=8, thinking_config=types.ThinkingConfig(thinking_budget=0))
                client.models.generate_content(model=self.model, contents="Reply with OK.", config=config)
            except Exception as exc:
                return self._health_failure("gemini", exc)
            _observe_ai("gemini", ok=True)
            return {"ok": True, "state": provider_health.LIVE, "status_code": 200,
                    "detail": f"Gemini answered ({self.model})"}
        if provider == "openai":
            if not self.openai_api_key:
                return {"ok": False, "state": provider_health.NEEDS_CONFIGURATION, "status_code": None,
                        "detail": "OpenAI API key is not set on this deployment"}
            try:
                response = self.http.post(
                    "https://api.openai.com/v1/responses",
                    headers={"Authorization": f"Bearer {self.openai_api_key}", "Content-Type": "application/json"},
                    json={"model": self.openai_model, "input": "Reply with OK.", "max_output_tokens": 16},
                )
                response.raise_for_status()
            except Exception as exc:
                return self._health_failure("openai", exc)
            _observe_ai("openai", ok=True)
            return {"ok": True, "state": provider_health.LIVE, "status_code": 200,
                    "detail": f"OpenAI answered ({self.openai_model})"}
        raise ValueError(f"unknown AI provider: {provider}")

    @staticmethod
    def _health_failure(provider: str, exc: Exception) -> dict[str, Any]:
        from app.services import provider_health

        _observe_ai(provider, error=exc)
        observed = provider_health.state(provider, configured=True)
        code = observed.get("last_status_code")
        name = {"gemini": "Gemini", "openai": "OpenAI"}[provider]
        if observed["state"] == provider_health.QUOTA_EXHAUSTED:
            detail = f"{name} refused for quota / credit" + (f" (HTTP {code})" if code else "")
        elif code in (401, 403):
            detail = f"{name} rejected the credentials (HTTP {code})"
        else:
            detail = f"{name} call failed: " + (f"HTTP {code}" if code else type(exc).__name__)
        return {"ok": False, "state": observed["state"], "status_code": code, "detail": detail}

    @staticmethod
    def _openai_output_text(data: dict[str, Any]) -> str:
        direct = data.get("output_text")
        if isinstance(direct, str) and direct.strip():
            return direct.strip()
        chunks: list[str] = []
        for item in data.get("output") or []:
            if not isinstance(item, dict):
                continue
            for content in item.get("content") or []:
                if isinstance(content, dict) and content.get("type") == "output_text" and content.get("text"):
                    chunks.append(str(content["text"]))
        return "\n".join(chunks).strip()

    @staticmethod
    def _parse_json(raw: str) -> dict[str, Any]:
        text = str(raw or "").strip()
        if text.startswith("```"):
            text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.I)
            text = re.sub(r"\s*```$", "", text)
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            start, end = text.find("{"), text.rfind("}")
            if start < 0 or end <= start:
                raise ValueError("no json object found in model reply")
            data = json.loads(text[start : end + 1])
        if not isinstance(data, dict):
            raise ValueError("model reply JSON was not an object")
        return data

    def decide(
        self,
        message: str,
        *,
        history: list[dict[str, str]] | None = None,
        locale: str = "",
        location: str = "",
        searched_for: dict[str, Any] | None = None,
        advice_given: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any] | None:
        """Return a semantic decision for the in-app conversation.

        The AI extracts reusable semantic entities so downstream business logic does
        not need to re-infer the primary intent from keyword-prefixed text.

        ``location`` is the user's saved/default location, when the app already
        knows one. When supplied, the model must treat location as already
        satisfied and must not ask the user for it again.
        """
        clean = str(message or "").strip()
        if not clean or not (self.configured or self.openai_api_key):
            return None
        clean_location = str(location or "").strip()[:300]
        ledger = advice_memory.sanitize_ledger(advice_given)

        compact_history = []
        for turn in (history or [])[-12:]:
            role = str(turn.get("role", "") or "").strip().lower()
            text = str(turn.get("text", "") or "").strip()
            if role in {"user", "assistant"} and text:
                compact_history.append({"role": role, "text": text[:1200]})

        runtime_block = runtime_context_block(clean, self.clock)
        grounding, grounding_block = self._live_grounding(clean)
        prompt = (
            "You are the semantic routing brain for ASKODOX, a natural AI assistant with optional local business actions. "
            "Understand meaning from the full conversation, not keyword matching. Return ONLY one JSON object with keys: "
            "reply, domain, transactional, action, confidence, entities, state, search_ready, next_question, search_subject, "
            "ready_reason, new_need, advice. domain must be one of GENERAL, JOB_SEEKER, STAFFING, SERVICE, "
            "PARCEL, RIDE, PRODUCT, FOOD, EVENT, APPOINTMENT, LEDGER, UNKNOWN. transactional is boolean. action is a short snake_case string. "
            "entities must be a JSON object containing only facts actually supplied or unambiguously inherited from the conversation. "
            "Useful entity keys include subject, category, role, skill, quantity, unit, headcount, date, time, timing, location, from, to, budget, price, salary, pay, pay_basis, duration, shift, context, variant, quality, size, model, brand, fulfilment, availability, specialist, service_type, job_type, seats, notes. "
            "brand = the maker/brand/company the user named for the thing wanted (any category, e.g. Tata, Voltas, a local shop brand); "
            "a later message naming another brand replaces it. "
            "Genuine ambiguity (any category): only when the wanted thing could mean clearly different kinds of things "
            "(e.g. 'tablet' = a device or medicine), set action to clarify_need, put 2-4 short precise alternatives "
            "(each usable as a search subject, in the user's language) in entities.clarify_options, and make reply ONE short question. "
            "Never use clarify_need for brand, budget, size, quantity or anything a normal follow-up can ask. "
            "Never invent a missing entity. Keep values concise. reply must answer naturally in the user's language or language mix. "
            "Do not claim a booking, payment, message, search or match happened, and never say you are showing, finding "
            "or have found options -- the app says that only when real results exist. "
            "Explicit constraints are sacred: repeat a size, budget, quantity, brand, colour or date EXACTLY as the user "
            "gave it (size 9 stays 'size 9' -- never 'size 8 or 9', never rounded or widened). "
            "Decision brain: if the message asks for advice or a decision (should I, risks, pros/cons, which is safer, how much do I need, is it worth it), it is NOT a search: transactional false, action advise. "
            "If the app lists options already shown to the user, the message is a follow-up about THOSE options (compare, which is best, reviews, deals, details, why): answer it from the listed facts only -- compare side by side, write Not verified for any fact not listed -- transactional false, action answer_about_options, never a new search. "
            "Otherwise, if the user asks for videos, reviews, unboxing, comparisons or demos of something, that is a search: "
            "set transactional true, action search_videos, entities.subject = the thing itself (without the words "
            "video/review), and never say 'here are' results or describe specs -- the app shows the real results. "
            "Never name specific shops, stores, dealers, showrooms or service companies from memory: if the user asks where "
            "to get or buy something, that is a search (transactional true) and the app shows real sellers. "
            "Important distinction: 'delivery job kavali' is JOB_SEEKER; 'delivery boys/staff kavali na shop ki' is STAFFING; "
            "'parcel/courier pampali' is PARCEL; temporary catering/function workers are STAFFING. General planning/chat is GENERAL. "
            "Conversation continuity rule: if the current message supplies a missing detail, correction, quantity, date, time, location, budget, salary, "
            "price or other parameter for the immediately preceding transactional request, KEEP the same transactional domain and action family and return the new entity in entities. "
            "Do not downgrade a short follow-up such as 'salary 800 estha', '10 members', 'repu 11 am', 'Vijayawada', or 'one person' to GENERAL when the prior context is staffing or another transaction. "
            "If a new request clearly changes intent, switch domains. Example: staffing follow-up -> parcel request must switch from STAFFING to PARCEL. "
            "Use previous turns as authoritative context for ellipsis and follow-ups. "
            + CONVERSATION_STATE_RULES
            + DECISION_GUIDANCE_RULES
            + advice_memory.prompt_block(ledger) +
            "Known user location rule: if a known location is given below, treat the location "
            "requirement as already satisfied for this request. Do NOT ask the user for their "
            "location again, and do not include a location question in reply. Only ask about "
            "location if the user is explicitly asking to use a different/new location than the "
            "known one. You may still copy the known location into entities.location when relevant.\n"
            + _reply_language_rule(locale) +
            f"Known user location: {clean_location or 'none (ask if the request needs it)'}\n"
            f"Conversation history JSON: {json.dumps(compact_history, ensure_ascii=False)}\n"
            + (f"Already searched for (the options now on screen): "
               f"{json.dumps(searched_for, ensure_ascii=False)[:1500]}\n" if searched_for else "")
            + (
                f"FINAL REMINDER (highest priority, overrides anything above if in conflict): the "
                f"user's location is already known as '{clean_location}'. Your reply text must NOT "
                f"contain any question asking for location, address, or delivery place. Skip that "
                f"topic entirely and move to the next missing detail (such as product variant, "
                f"quantity, date or budget) instead.\n"
                if clean_location else ""
            )
            + runtime_block + "\n"
            + grounding_block
            + f"Current user message: {clean}"
        )
        data: dict[str, Any] | None = None
        if self.configured:
            try:
                client = self.client or genai.Client(api_key=self.api_key)
                config = types.GenerateContentConfig(
                    temperature=0.15,
                    max_output_tokens=2048,
                    response_mime_type="application/json",
                    # Structured extraction does not need deep reasoning. Keep
                    # thinking from consuming the visible JSON response budget.
                    thinking_config=types.ThinkingConfig(thinking_budget=0),
                )
                response = self._generate_with_retry(client, prompt, config)
                _observe_ai("gemini", ok=True)
                data = self._parse_json(str(getattr(response, "text", "") or "").strip())
            except Exception as exc:
                _observe_ai("gemini", error=exc)
                logger.exception(
                    "universal_ai_assistant.decide: gemini call failed%s (message_len=%d, has_known_location=%s)",
                    "; trying openai fallback" if self.openai_api_key else "; no openai fallback configured",
                    len(clean),
                    bool(clean_location),
                )
        if data is None and self.openai_api_key:
            try:
                data = self._call_openai(prompt)
                _observe_ai("openai", ok=True)
            except Exception as exc:
                _observe_ai("openai", error=exc)
                logger.exception(
                    "universal_ai_assistant.decide: openai fallback also failed "
                    "(message_len=%d, has_known_location=%s)",
                    len(clean),
                    bool(clean_location),
                )
        if not isinstance(data, dict):
            return None
        try:
            if not isinstance(data, dict):
                return None
            domain = str(data.get("domain", "UNKNOWN") or "UNKNOWN").upper().strip()
            if domain not in self.ALLOWED_DOMAINS:
                domain = "UNKNOWN"
            reply = str(data.get("reply", "") or "").strip()
            action = str(data.get("action", "") or "").strip().lower()[:80]
            confidence = float(data.get("confidence", 0.0) or 0.0)
            confidence = max(0.0, min(1.0, confidence))
            transactional = bool(data.get("transactional", domain not in {"GENERAL", "UNKNOWN"}))
            entities = self._clean_entities(data.get("entities"))
            # Defensive fallback: guarantee the known location survives even if the
            # model's JSON omits it, so downstream capture never re-asks for it.
            if clean_location and not entities.get("location"):
                entities["location"] = clean_location
            # Deterministic safety net: the prompt instructs the model to never
            # re-ask for a known location, but that instruction is probabilistic.
            # Strip any location question the model asked anyway so the user
            # never sees the re-ask regardless of the model's behaviour.
            if clean_location:
                reply = self._strip_location_question(reply, locale)
            if not reply:
                return None
            user_text, _app_context, about_shown = self.split_app_context(clean)
            mode = "commerce" if transactional else "chat"
            if about_shown:
                # A follow-up about options already on screen: answer it from
                # those options; never a new search, never a canned reply.
                mode = "follow_up"
                transactional = False
                action = "answer_about_options"
            elif self.wants_advice(user_text):
                mode = "advice"
                transactional = False
                action = "advise"
                advice, advice_meta = self._advise(user_text, compact_history, locale, clean_location, ledger)
                if advice:
                    reply = advice
                    data["advice"] = advice_meta
            elif self._asks_for_videos(user_text) and self._video_search_wanted(
                    user_text, entities, transactional, searched_for):
                # Deterministic: a video / review ask is a real search. The
                # app shows the real videos; the reply never claims results
                # or describes specs it did not get from a source.
                transactional = True
                action = "search_videos"
                if domain in {"GENERAL", "UNKNOWN"}:
                    domain = "PRODUCT"
                reply = self._video_search_reply(locale)
            elif self._asks_where_to_get(user_text):
                # Deterministic: "where can I get it here" is a real search.
                # Shop / dealer names come only from real results, never
                # from the model's memory.
                transactional = True
                if action not in {"search", "find_local", "order", "book"}:
                    action = "find_local"
                if domain in {"GENERAL", "UNKNOWN"}:
                    domain = "PRODUCT"
                reply = self._local_search_reply(locale)
            brain = self.brain_state(data, transactional=transactional, mode=mode, action=action)
            # APK 1305: deterministic conversation-relation layer. The model
            # stays the primary judge; this engine corrects its probabilistic
            # new_need with same/new-topic signals from the ACTIVE need.
            shown = searched_for or {}
            active_subject = str(shown.get("subject") or "")
            relation = self.relation_engine.classify(
                user_text=user_text,
                active_subject=active_subject,
                active_facts=shown.get("facts") or {},
                shown_sources=shown.get("sources") or shown.get("source_names") or [],
                recent_user_turns=[
                    t["text"] for t in compact_history if t.get("role") == "user"
                ][-8:],
                subject_aliases=[str(shown.get("said_subject") or "")],
                location_labels=[str(shown.get("location") or "")],
            )
            model_new_need = bool(brain["new_need"])
            brain["new_need"] = relation.resolve_new_need(model_new_need)
            relation_name, subject_changed = self.reconcile_relation(
                relation, model_new_need, brain, active_subject, str(shown.get("said_subject") or ""))
            if relation_name == "new_topic":
                brain["new_need"] = True
            if (
                relation.has_active_deck
                and relation.confidence >= 0.7
                and relation.relation in {"result_action", "comparison"}
                and not relation.subject_replaced
            ):
                # A question about the options already on screen is answered
                # from those options -- never a fresh search.
                mode = "follow_up"
                transactional = False
                action = "answer_about_options"
                brain["search_ready"] = False
                brain["search_subject"] = None
                brain["next_question"] = None
            if brain["search_ready"] is False and brain["next_question"] and "?" not in reply:
                # Not ready yet: the turn ends with the ONE next question.
                reply = f"{reply.rstrip()}\n\n{brain['next_question']}".strip()
            advice_review, advice_ledger = advice_memory.review(data.get("advice"), ledger)
            if advice_review is not None and not advice_review["allowed"]:
                # The model repeated a concern without new information, an
                # explicit ask or a critical risk: flagged + counted, never silent.
                logger.warning("universal_ai_assistant.decide: advice repeated without reason (key=%s)",
                               advice_review["key"])
                from app.services import assistant_health
                assistant_health.record("advice_repeat_violation")
            if grounding is not None and not grounding["verified"]:
                # Deterministic honesty: never let an unverified current fact look checked.
                reply = f"{reply}\n\n{self._unverified_note(clean, locale)}"
            return {
                **brain,
                "conversation_relation": relation_name,
                "subject_changed": subject_changed,
                "reply": reply,
                "domain": domain,
                "transactional": transactional,
                "action": action,
                "confidence": confidence,
                "entities": entities,
                "mode": mode,
                "advice": advice_review,
                "advice_ledger": advice_ledger,
                **({"grounding": grounding} if grounding is not None else {}),
            }
        except Exception:
            # Previously silent -- this made every AI-call failure (bad API
            # response, quota, malformed JSON, network hiccup) indistinguishable
            # from "model unavailable" in production, with no way to diagnose
            # why a given request fell back to the app's generic reply.
            logger.exception(
                "universal_ai_assistant.decide failed; falling back to deterministic reply "
                "(message_len=%d, has_known_location=%s)",
                len(clean),
                bool(clean_location),
            )
            return None

    _UNVERIFIED_NOTE = {
        "te": "(గమనిక: ప్రస్తుతం దీన్ని లైవ్ సోర్సులతో ధృవీకరించలేకపోయాను — దయచేసి అధికారిక క్యాలెండర్/సోర్స్‌తో సరిచూసుకోండి.)",
        "en": "(Note: I couldn't verify this with live sources right now — please confirm with an official source.)",
    }

    def _unverified_note(self, message: str, locale: str) -> str:
        telugu = str(locale or "").lower().startswith("te") or bool(re.search(r"[\u0C00-\u0C7F]", message))
        return self._UNVERIFIED_NOTE["te" if telugu else "en"]

    def _live_grounding(self, message: str) -> tuple[dict[str, Any] | None, str]:
        """Live evidence for time-sensitive/changeable facts. Returns
        (grounding summary or None when not needed, prompt block)."""
        if message.startswith("OASAT ") or not needs_live_verification(message):
            return None, ""
        query = grounded_search_query(message, self.clock)
        evidence: dict[str, Any] = {}
        if self.research_service is not None:
            try:
                evidence = self.research_service.research(query, limit=5) or {}
            except Exception:
                logger.exception("universal_ai_assistant: live research failed (query_len=%d)", len(query))
                evidence = {}
        sources = list(evidence.get("sources") or [])[:5]
        if not sources:
            grounding = {"required": True, "verified": False, "query": query, "sources": []}
            block = (
                "LIVE VERIFICATION REQUIRED BUT UNAVAILABLE: this question depends on current or date-specific facts and no "
                "live web evidence could be retrieved. Do NOT claim the answer was checked or is verified, do NOT present a "
                "specific current date/price/policy as confirmed, and say plainly that it could not be verified right now.\n"
            )
            return grounding, block
        lines = [
            f"[S{i}] {src.get('title')} | {src.get('url')} | published={src.get('published_at')} | {src.get('snippet')}"
            for i, src in enumerate(sources, start=1)
        ]
        grounding = {
            "required": True,
            "verified": True,
            "query": query,
            "sources": [{"id": f"S{i}", "title": src.get("title"), "url": src.get("url")} for i, src in enumerate(sources, start=1)],
        }
        block = (
            "LIVE WEB EVIDENCE (retrieved now for this question). Answer current/date-specific facts ONLY from this evidence, "
            "for the runtime year above; cite source ids like [S1]; if the evidence does not settle it, say so instead of guessing.\n"
            + "\n".join(lines) + "\n"
        )
        return grounding, block

    def process(self, sender_mobile: str, message: str) -> str:
        clean = str(message or "").strip()
        if self.GENERAL_MARKER not in clean:
            return self._delegate(sender_mobile, clean)
        decision = self.decide(clean)
        if decision is not None and not decision["transactional"]:
            return str(decision["reply"])
        return self._delegate(sender_mobile, clean)

    def _delegate(self, sender_mobile: str, message: str) -> str:
        try:
            return self.delegate.process(sender_mobile=sender_mobile, message=message)
        except TypeError:
            return self.delegate.process(sender_mobile, message)
