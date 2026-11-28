"""School / tuition / college register (owner 2026-11-28): the day's register by absent list, three days in a row raised
with a parent draft, the gate checks the parent's own pickup list, the health room keeps a follow-up, and ``today``
shows ONLY problems. Same engine for a school, a tuition and a college (no per-category code)."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_school import PosSchool, _same_name
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300004001"
STRANGER = "app-phone-9300004099"
IST = timezone(timedelta(hours=5, minutes=30))
START = datetime(2026, 11, 23, 9, 0, tzinfo=IST)  # a Monday


@pytest.fixture()
def env(tmp_path):
    now = [START]
    clock = lambda: now[0].astimezone(timezone.utc)  # noqa: E731
    store = PosStore(str(tmp_path / "s.db"), clock=clock)
    biz = store.create_business(OWNER, {"name": "Sample School", "state_code": "37"})["id"]
    school = PosSchool(store, clock=clock)
    cls = school.add_class(biz, OWNER, {"name": "5-A", "teacher": "Teacher One"})["id"]
    kids = [school.add_student(biz, OWNER, {"class_id": cls, "name": n, "parent_name": p, "parent_phone": ph,
                                            "pickups": [{"name": "Uncle One", "relation": "uncle"}]})["id"]
            for n, p, ph in (("Child One", "Parent One", "9300004011"), ("Child Two", "Parent Two", "9300004012"),
                             ("Child Three", "Parent Three", "9300004013"))]
    return school, biz, cls, kids, now


def test_names_match_by_words_not_case_or_order():
    assert _same_name("Ravi Kumar", "kumar ravi") and not _same_name("Ravi Kumar", "Ravi")


def test_an_unmarked_class_is_a_problem_and_marking_it_clears_it(env):
    school, biz, cls, kids, _ = env
    today = school.today(biz, OWNER)
    assert [p["key"] for p in today["problems"]] == ["unmarked"] and today["all_clear"] is False
    done = school.register(biz, OWNER, cls, [kids[0]])
    assert done["present"] == 2 and done["absent"] == 1 and done["draft_only"] is True
    assert done["drafts"][0]["whatsapp_url"].startswith("https://wa.me/919300004011?text=")
    after = school.today(biz, OWNER)
    assert [p["key"] for p in after["problems"]] == ["absent_today"]
    assert school.register(biz, OWNER, cls, [])["absent"] == 0  # saving again replaces the day
    assert school.today(biz, OWNER)["all_clear"] is True


def test_register_refuses_a_name_from_another_class(env):
    school, biz, cls, kids, _ = env
    other = school.add_class(biz, OWNER, {"name": "6-A"})["id"]
    stranger = school.add_student(biz, OWNER, {"class_id": other, "name": "Child Four"})["id"]
    with pytest.raises(PosError) as error:
        school.register(biz, OWNER, cls, [stranger])
    assert error.value.status == 400


def test_three_marked_days_absent_in_a_row_is_raised_and_sunday_does_not_break_it(env):
    school, biz, cls, kids, now = env
    for offset in range(0, 3):  # Mon, Tue, Wed
        now[0] = START + timedelta(days=offset)
        school.register(biz, OWNER, cls, [kids[1]])
    keys = [p["key"] for p in school.today(biz, OWNER)["problems"]]
    assert "absent_streak" in keys
    streak = next(p for p in school.today(biz, OWNER)["problems"] if p["key"] == "absent_streak")["items"][0]
    assert streak["name"] == "Child Two" and streak["days"] == 3 and "wa.me/919300004012" in streak["whatsapp_url"]
    assert "bunk" not in streak["message"].lower()
    # a present day breaks the run
    now[0] = START + timedelta(days=3)
    school.register(biz, OWNER, cls, [])
    assert "absent_streak" not in [p["key"] for p in school.today(biz, OWNER)["problems"]]


def test_gate_checks_the_parents_list_and_raises_an_unlisted_person(env):
    school, biz, _, kids, _ = env
    ok = school.gate(biz, OWNER, kids[0], {"kind": "pickup", "who_name": "uncle one"})
    assert ok["listed"] is True and "warning" not in ok
    parent = school.gate(biz, OWNER, kids[0], {"kind": "early", "who_name": "Parent One", "reason": "doctor"})
    assert parent["listed"] is True
    bad = school.gate(biz, OWNER, kids[1], {"kind": "pickup", "who_name": "Unknown Person"})
    assert bad["listed"] is False and "warning" in bad and bad["call_parent"] == "tel:9300004012"
    problems = school.today(biz, OWNER)["problems"]
    assert problems[0]["key"] == "unlisted_pickup" and problems[0]["items"][0]["who"] == "Unknown Person"
    school.set_pickups(biz, OWNER, kids[1], [{"name": "Unknown Person", "relation": "friend"}])
    assert school.gate(biz, OWNER, kids[1], {"kind": "pickup", "who_name": "Unknown Person"})["listed"] is True
    with pytest.raises(PosError):
        school.gate(biz, OWNER, kids[1], {"kind": "pickup", "who_name": " "})


def test_health_follow_up_comes_after_a_day_and_the_draft_never_names_the_illness(env):
    school, biz, _, kids, now = env
    sick = school.sick(biz, OWNER, kids[2], {"complaint": "high fever", "action": "rest + parent called", "outcome": "home"})
    assert sick["follow_up"] == "2026-11-24"
    assert "health_follow_up" not in [p["key"] for p in school.today(biz, OWNER)["problems"]]
    now[0] = START + timedelta(days=1)
    item = next(p for p in school.today(biz, OWNER)["problems"] if p["key"] == "health_follow_up")["items"][0]
    assert item["student"] == "Child Three" and "fever" not in item["message"].lower() and "wa.me/919300004013" in item["whatsapp_url"]
    school.recovered(biz, OWNER, item["health_id"])
    assert "health_follow_up" not in [p["key"] for p in school.today(biz, OWNER)["problems"]]
    with pytest.raises(PosError):
        school.sick(biz, OWNER, kids[2], {"complaint": "", "outcome": "home"})
    with pytest.raises(PosError):
        school.sick(biz, OWNER, kids[2], {"complaint": "cold", "outcome": "ambulance"})


def test_report_has_no_health_detail_and_a_stranger_is_a_404(env):
    school, biz, cls, kids, now = env
    school.register(biz, OWNER, cls, [kids[0]])
    school.sick(biz, OWNER, kids[2], {"complaint": "high fever"})
    report = school.report(biz, OWNER, "2026-11")
    row = report["classes"][0]
    assert row["days_marked"] == 1 and row["absences"] == 1 and row["attendance_percent"] == 67
    assert "fever" not in str(report)
    for call in (lambda: school.today(biz, STRANGER), lambda: school.classes(biz, STRANGER),
                 lambda: school.register(biz, STRANGER, cls, [])):
        with pytest.raises(PosError) as error:
            call()
        assert error.value.status == 404


def test_the_kit_has_the_class_register_way_of_working():
    from app.services import business_kit

    assert "7" in business_kit.FLOWS
    subs = {s["key"]: s for c in business_kit.DEFAULT_CATEGORIES for s in c["subs"]}
    for key in ("school", "tuition", "coaching", "play_school_daycare"):
        assert "7" in subs[key]["flows"], key
