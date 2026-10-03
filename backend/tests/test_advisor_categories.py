"""Universal Advisor v2: questions come from the matched advisor CATEGORY
(AI category -> head noun -> alias) and its configurable decision fields,
never from a raw keyword. Scenario matrix across 14 groups, English and
Telugu, plus the one-time v2 seed that retires the v1 keyword defaults."""
import pytest

from app.services import advisor_defaults as defaults
from app.services import advisor_engine as ae


def _rows(items, prefix):
    return [{"id": f"{prefix}{i}", "status": "ACTIVE", "archived": False, "data": dict(d)}
            for i, d in enumerate(items)]


CATS = _rows(defaults.category_records(), "c")
QS = _rows(defaults.question_records(), "q")
RULES = _rows(ae.DEFAULT_RULES, "r")


def _advise(text, language="en", **demand):
    body = {"side": "NEED", "subject": text, "raw_text": text, **demand}
    return ae.advise(body, QS, RULES, language=language, limit=1, category_records=CATS)


# (group, text, language, category, first question field, required?, ready?)
MATRIX = [
    ("ecommerce", "car phone holder", "en", "accessories", "model", False, True),
    ("ecommerce", "phone holder for car", "en", "accessories", "model", False, True),
    ("ecommerce", "కారు ఫోన్ హోల్డర్", "te", "accessories", "model", False, True),
    ("ecommerce", "43 inch tv", "en", "tv", "budget", True, False),
    ("ecommerce", "టీవీ కావాలి", "te", "tv", "budget", True, False),
    ("fashion", "shoes for standing all day", "en", "footwear", "budget", True, False),
    ("fashion", "చీర", "te", "fashion", "budget", True, False),
    ("grocery_food", "rice", "en", "grocery", "quantity", True, False),
    ("grocery_food", "చికెన్ బిర్యానీ", "te", "food", "quantity", False, True),
    ("travel", "hotel in goa", "en", "hotel", "travel_dates", True, False),
    ("travel", "bus ticket to hyderabad", "en", "travel", "travel_dates", True, False),
    ("finance", "health insurance", "en", "insurance", "coverage", True, False),
    ("finance", "loan", "te", "loans", "goal", True, False),
    ("finance", "home loan", "en", "loans", "income", False, True),
    ("finance", "mutual fund", "en", "investment", "duration", False, True),
    ("finance", "పెట్టుబడి", "te", "investment", "goal", True, False),
    ("health", "doctor", "en", "healthcare", "requirement", True, False),
    ("health", "dentist", "en", "healthcare", "timing", False, True),
    ("health", "blood test", "en", "diagnostics", "timing", False, True),
    ("education", "IIT coaching", "en", "education", "timing", False, True),
    ("education", "coaching", "en", "education", "goal", True, False),
    ("jobs", "driver jobs", "en", "jobs", "experience", True, False),
    ("jobs", "ఉద్యోగం", "te", "jobs", "experience", True, False),
    ("real_estate", "2 bhk flat for rent", "en", "real_estate", "budget", True, False),
    ("home_services", "AC repair", "en", "home_services", "timing", True, False),
    ("home_services", "ప్లంబర్", "te", "home_services", "timing", True, False),
    ("logistics", "parcel to delhi", "en", "logistics", "timing", True, False),
    ("automobile_used", "car", "en", "automobile", "budget", True, False),
    ("automobile_used", "కారు కావాలి", "te", "automobile", "budget", True, False),
    ("b2b", "bulk cement supplier", "en", "b2b", "quantity", True, False),
    ("saas_entertainment", "billing software", "en", "saas", "guests", False, True),
    ("saas_entertainment", "movie tickets", "en", "entertainment", "timing", True, False),
]


@pytest.mark.parametrize("group,text,language,key,field,required,ready", MATRIX,
                         ids=[f"{m[0]}:{m[1]}" for m in MATRIX])
def test_scenario_matrix(group, text, language, key, field, required, ready):
    view = _advise(text, language)
    assert view["category"]["key"] == key
    assert view["questions"][0]["field"] == field
    assert view["questions"][0]["required"] is required
    assert view["ready"] is ready
    if language == "te":  # asked in the conversation's language
        assert any("ఀ" <= ch <= "౿" for ch in view["questions"][0]["question"])


def test_groups_cover_fourteen_kinds_of_need():
    assert len({m[0] for m in MATRIX}) == 14


def test_car_accessory_never_inherits_car_budget_rules():
    holder = _advise("car phone holder")
    car = _advise("car")
    assert holder["category"]["matched_by"] == "head_noun" and holder["category"]["alias"] == "holder"
    assert "budget" not in holder["category"]["required_fields"]
    assert car["category"]["required_fields"][:2] == ["budget", "condition"]
    # The subject echoed back as "category_detected" is not an AI signal.
    echo = _advise("phone holder for car", constraints={"category_detected": "phone holder for car"})
    assert echo["category"]["key"] == "accessories"
    # A broad AI group gives way to the specific head noun in the same group.
    assert _advise("running shoes", category="fashion")["category"]["key"] == "footwear"
    assert _advise("43 inch tv", category="Electronics")["category"]["key"] == "tv"
    # ...but not across groups: the AI's specific category stays.
    assert _advise("car phone holder", category="automotive")["category"]["key"] == "accessories"
    # The AI category wins when it names the thing.
    ai = _advise("car phone holder", category="Car accessories")
    assert ai["category"]["key"] == "accessories" and ai["category"]["matched_by"] == "ai_category"


def test_no_repeats_any_and_budget_rules():
    # Budget known -> the next required decision field (condition), not budget again.
    view = _advise("car", constraints={"dynamic_fields": {"budget_max": 500000}})
    assert view["questions"][0]["field"] == "condition" and view["ready"] is False
    # "any" settles only the field just asked; budget is still asked.
    view = _advise("car", constraints={"dynamic_fields": {"no_preference": ["condition"]}})
    assert view["field_states"]["condition"] == "no_preference"
    assert view["questions"][0]["field"] == "budget"
    # Already asked (even unanswered) -> never asked again; required hold lifts.
    view = ae.advise({"side": "NEED", "subject": "car", "raw_text": "car"}, QS, RULES,
                     asked=["budget", "condition", "model"], category_records=CATS)
    assert view["questions"] == []
    # Every field answered -> ready, nothing asked.
    view = _advise("car", constraints={"dynamic_fields": {"budget": "5 lakh", "condition": "used", "model": "swift"}})
    assert view["ready"] is True and view["questions"] == []
    # Show me now never waits.
    assert ae.advise({"side": "NEED", "subject": "tv", "raw_text": "tv"}, QS, RULES, show_now=True,
                     category_records=CATS)["ready"] is True


def test_specific_requests_settle_requirement_goal_and_type():
    assert _advise("dentist")["field_states"]["requirement"] == "known"
    assert _advise("doctor")["field_states"]["requirement"] == "unknown"
    assert _advise("doctor in Vijayawada", location_text="Vijayawada")["field_states"]["requirement"] == "unknown"
    assert _advise("knee pain doctor")["field_states"]["requirement"] == "known"
    assert _advise("home loan")["field_states"]["goal"] == "known"
    assert _advise("2 bhk flat")["field_states"]["property_type"] == "known"
    assert _advise("property")["field_states"]["property_type"] == "unknown"


def test_high_stakes_categories_carry_a_boundary():
    for text in ("dentist", "blood test", "mutual fund", "health insurance"):
        guidance = _advise(text)["guidance"]
        assert guidance and guidance[0]["high_stakes"] is True, text
    assert all(not g["high_stakes"] for g in _advise("43 inch tv")["guidance"])
    te = _advise("blood test", "te")["guidance"][0]["advice"]
    assert any("ఀ" <= ch <= "౿" for ch in te)


def test_unknown_need_asks_nothing_and_offers_never_ask():
    view = _advise("zorblax widget")
    assert view["category"] is None and view["questions"] == [] and view["ready"] is True
    assert ae.next_questions({"side": "OFFER", "subject": "tv"}, QS, category_records=CATS) == []


def test_staff_disabling_wording_or_category_is_respected():
    disabled = [dict(r, status="DISABLED") if r["data"]["field"] == "budget" and r["data"]["category"] == "any"
                else r for r in QS]
    view = ae.advise({"side": "NEED", "subject": "tv", "raw_text": "tv"}, disabled, RULES, category_records=CATS)
    assert view["questions"][0]["field"] == "size"
    cats = [dict(c, status="DISABLED") if c["data"]["key"] == "tv" else c for c in CATS]
    view = ae.advise({"side": "NEED", "subject": "tv", "raw_text": "tv"}, QS, RULES, category_records=cats)
    assert view["category"] is None or view["category"]["key"] != "tv"
    # Budget can be switched off globally (platform setting) without touching categories.
    view = ae.advise({"side": "NEED", "subject": "tv", "raw_text": "tv"}, QS, RULES, category_records=CATS,
                     skip_fields=["budget"])
    assert view["questions"][0]["field"] == "size" and view["ready"] is True


def test_v2_seed_archives_untouched_v1_keyword_questions(tmp_path):
    from app.repositories.platform_repository import PlatformRepository
    from app.services.platform_service import ResourceService

    repo = PlatformRepository(str(tmp_path / "pf.db"))
    resources = ResourceService(repo)
    v1 = [resources.create("advisor_questions", dict(q), actor="system") for q in ae.LEGACY_QUESTIONS]
    edited = v1[1]
    resources.update("advisor_questions", edited["id"], {"priority": 801}, actor="owner")
    staff_made = resources.create("advisor_questions", {"category": "any", "keywords": ["drone"], "field": "budget",
                                                        "question_en": "Drone budget?"}, actor="owner")
    created = ae.seed_defaults(resources)
    assert created > len(defaults.DEFAULT_CATEGORIES)
    live = {r["id"] for r in repo.list("advisor_questions")}
    assert v1[0]["id"] not in live  # untouched v1 default -> archived (history kept)
    assert edited["id"] in live and staff_made["id"] in live
    assert len(repo.list("advisor_categories")) == len(defaults.DEFAULT_CATEGORIES)
    assert repo.history(v1[0]["id"])[-1]["action"] == "archive"
    # Runs once: a second call changes nothing.
    assert ae.seed_defaults(resources) == 0
    # Legacy keyword questions still work for needs no category covers.
    view = ae.advise({"side": "NEED", "subject": "drone", "raw_text": "drone"}, repo.list("advisor_questions"), [],
                     category_records=repo.list("advisor_categories"))
    assert view["category"] is None and view["questions"][0]["question"] == "Drone budget?"
