"""Regression coverage for a round-15 CI investigation finding.

ConversationOSRuntimeService._planned_message() builds an internal,
LLM-facing routing prompt for every non-GENERAL domain (e.g. "OASAT
domain=FOOD; ...; Do not force commerce/seller logic into non-commerce
domains. User request: <the real message>"). UniversalAIAssistantService
.process() only calls the Gemini classifier when that prompt's domain is
GENERAL; for every other domain it forwards the raw prompt text straight
down the legacy delegate chain -- including when no Gemini/OpenAI key is
configured at all, which is exactly what happens in CI.

UniversalCorrectionService sits further down that same chain. Its
detect() used naive substring checks (a "correction marker" word, then a
role keyword) with no way to tell an internal planned-message prompt from
a genuine user reply. The boilerplate phrase "Do not force commerce/
seller logic" happens to contain both a marker ("not ") and a role
keyword ("seller"), so any non-GENERAL-domain message with no configured
AI key was misread as "the user wants to switch role to Seller" -- which
silently swallowed the real request and broke round 15's rewritten
in-app-e2e-smoke.yml CI test (a real 2kg-rice request came back 422
instead of creating the deal).

Fixed by having detect() refuse to look at any message that starts with
the internal "OASAT domain=" prefix -- a real user never types that.
"""
from app.services.universal_correction_service import UniversalCorrectionService


def _service() -> UniversalCorrectionService:
    return UniversalCorrectionService(delegate=None)


def test_oasat_planned_message_is_never_treated_as_a_correction():
    planned_message = (
        "OASAT domain=FOOD; adapter=food; intent=SOLVE_FOOD_NEED; "
        "stages=SITUATION,REQUIREMENTS,REASONING,SUGGESTIONS,COMPARISON,APPROVAL,ACTION. "
        "Domain questions=people_or_quantity,meal_timing,preferences,budget_if_relevant; "
        "reason about=quantity,menu_or_item_fit,freshness,price,distance,delivery; "
        "allowed actions=suggest_food_plan,compare_sources,match_provider,order_after_approval; "
        "never force=. Do not use one global answer template. Ask only relevant missing "
        "questions and reason/action according to this domain and the user's actual "
        "requirement. Do not force commerce/seller logic into non-commerce domains. "
        "User request: I need 2kg rice delivered to Vijayawada"
    )
    assert _service().detect(planned_message) is None


def test_oasat_planned_message_for_a_different_domain_is_also_ignored():
    planned_message = (
        "OASAT domain=COMMERCE; adapter=commerce; intent=SOLVE_PRODUCT_NEED; "
        "Do not force commerce/seller logic into non-commerce domains. "
        "User request: I want to sell my old bicycle"
    )
    assert _service().detect(planned_message) is None


def test_legit_role_correction_still_works():
    intent = _service().detect("change my role to seller, I want to sell products")
    assert intent is not None
    assert intent.target == "roles"
    assert intent.value == "SELLER"


def test_ordinary_message_with_a_bare_digit_is_not_treated_as_a_role_command():
    assert _service().detect("I need 2kg rice delivered to Vijayawada") is None
    assert _service().detect("sorry, I need 2 more boxes") is None
    assert _service().detect("wrong, 2 boxes needed") is None


def test_ordinary_message_with_no_markers_at_all_is_ignored():
    assert _service().detect("2kg rice for tomorrow please") is None
