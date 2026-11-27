"""Term memberships + attendance (owner 2026-11-27, phase 3): end day worked out, a fee moves it on, reminders are
drafts, attendance once a day by tap or by today's counter code, the month's report from real records only."""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.services.pos_memberships import ENDING_DAYS, PosMemberships, add_months, visit_code
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300003001"
STAFF = "app-phone-9300003002"
MEMBER = "app-phone-9300003050"
STRANGER = "app-phone-9300003099"
IST = timezone(timedelta(hours=5, minutes=30))
START = datetime(2026, 11, 27, 6, 0, tzinfo=IST)


@pytest.fixture()
def env(tmp_path):
    now = [START]
    clock = lambda: now[0].astimezone(timezone.utc)  # noqa: E731
    store = PosStore(str(tmp_path / "m.db"), clock=clock)
    biz = store.create_business(OWNER, {"name": "Sample Fitness", "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9300003002", "cashier")
    return PosMemberships(store, clock=clock), store, biz, now


def test_month_arithmetic_keeps_the_day_or_takes_the_last_day():
    assert add_months(date(2026, 11, 27), 1) == date(2026, 12, 27)
    assert add_months(date(2026, 11, 27), 3) == date(2027, 2, 27)
    assert add_months(date(2027, 1, 31), 1) == date(2027, 2, 28)
    assert add_months(date(2028, 1, 31), 1) == date(2028, 2, 29)  # leap year
    assert add_months(date(2026, 12, 15), 12) == date(2027, 12, 15)


def test_a_new_member_gets_the_end_day_and_a_paid_join_is_recorded(env):
    terms, _, biz, _ = env
    member = terms.add(biz, OWNER, {"name": "Member One", "phone": "93000 03050", "months": 3, "fee_paise": 450000,
                                    "paid": True, "method": "upi"})
    assert member["start_date"] == "2026-11-27" and member["end_date"] == "2027-02-27" and member["state"] == "ok"
    with pytest.raises(PosError) as error:
        terms.add(biz, OWNER, {"name": "Same Phone", "phone": "9300003050", "months": 1, "fee_paise": 150000})
    assert error.value.status == 409
    report = terms.report(biz, OWNER)
    assert report["new"] == 1 and report["renewed"] == 0 and report["collected_paise"] == 450000
    assert report["weeks_paise"] == [0, 0, 0, 450000]  # the 27th falls in the last part of the month


def test_ending_members_carry_a_reminder_draft_and_a_fee_moves_the_end_day(env):
    terms, _, biz, now = env
    member = terms.add(biz, OWNER, {"name": "Member One", "phone": "9300003050", "months": 1, "fee_paise": 150000})
    assert terms.overview(biz, OWNER)["ending"] == []
    now[0] = START + timedelta(days=30 - ENDING_DAYS)  # 22 Dec: 5 days before 27 Dec
    view = terms.overview(biz, OWNER)
    row = view["ending"][0]
    assert row["state"] == "ending" and row["days_left"] == ENDING_DAYS and view["draft_only"] is True
    assert "Sample Fitness" in row["reminder"] and row["whatsapp_url"].startswith("https://wa.me/919300003050?text=")
    assert "లేదు" not in row["reminder"]
    assert terms.ending_count(biz, OWNER) == 1
    renewed = terms.renew(biz, OWNER, member["id"], {})
    assert renewed["renewed"] == {"from": "2026-12-27", "to": "2027-01-27", "amount_paise": 150000, "months": 1}
    assert terms.ending_count(biz, OWNER) == 0


def test_a_late_renewal_starts_from_today_not_from_the_old_end_day(env):
    terms, _, biz, now = env
    member = terms.add(biz, OWNER, {"name": "Member One", "phone": "9300003050", "months": 1, "fee_paise": 150000})
    now[0] = datetime(2027, 1, 10, 9, 0, tzinfo=IST)  # two weeks after the end day
    view = terms.overview(biz, OWNER)
    assert view["ending"][0]["state"] == "ended" and view["counts"]["fee_due"] == 1 and view["counts"]["members"] == 0
    renewed = terms.renew(biz, OWNER, member["id"], {"months": 3, "amount_paise": 400000})
    assert renewed["renewed"]["to"] == "2027-04-10" and renewed["months"] == 3 and renewed["fee_paise"] == 400000
    assert terms.report(biz, OWNER)["renewed"] == 1


def test_attendance_once_a_day_by_tap_and_by_todays_code_only(env):
    terms, store, biz, now = env
    member = terms.add(biz, OWNER, {"name": "Member One", "phone": "9300003050", "months": 3, "fee_paise": 450000})
    other = terms.add(biz, OWNER, {"name": "Member Two", "months": 1, "fee_paise": 150000})
    today = terms.attendance(biz, STAFF)
    assert today["came_count"] == 0 and len(today["code"]) == 4 and today["qr"] == f"ASKODOX-VISIT:{biz}:{today['code']}"
    assert terms.mark(biz, STAFF, other["id"])["changed"] is True
    assert terms.mark(biz, STAFF, other["id"])["changed"] is False  # the same day again: still one visit
    wrong = "0000" if today["code"] != "0000" else "1111"
    with pytest.raises(PosError) as error:
        terms.check_in(MEMBER, biz, wrong)
    assert error.value.status == 400
    with pytest.raises(PosError) as error:
        terms.check_in(STRANGER, biz, today["code"])
    assert error.value.status == 404
    assert terms.check_in(MEMBER, biz, today["code"]) == {"ok": True, "day": "2026-11-27", "already": False,
                                                          "shop": "Sample Fitness"}
    assert terms.check_in(MEMBER, biz, today["code"])["already"] is True
    assert terms.attendance(biz, STAFF)["came_count"] == 2 and terms.overview(biz, OWNER)["counts"]["came_today"] == 2
    assert terms.mine(MEMBER)[0]["came_today"] is True
    yesterday_code = today["code"]
    now[0] = START + timedelta(days=1)
    with store._connect() as conn:
        salt = str(store._business_row(conn, biz)["created_at"])
    assert terms.attendance(biz, STAFF)["code"] == visit_code(biz, salt, "2026-11-28")
    if terms.attendance(biz, STAFF)["code"] != yesterday_code:
        with pytest.raises(PosError):
            terms.check_in(MEMBER, biz, yesterday_code)
    assert member["id"] != other["id"]


def test_a_week_away_shows_with_a_message_draft_and_a_wrong_tap_comes_off(env):
    terms, _, biz, now = env
    member = terms.add(biz, OWNER, {"name": "Member One", "phone": "9300003050", "months": 3, "fee_paise": 450000})
    terms.mark(biz, OWNER, member["id"])
    assert terms.mark(biz, OWNER, member["id"], came=False)["changed"] is True
    terms.mark(biz, OWNER, member["id"])
    assert terms.attendance(biz, OWNER)["absent"] == []
    now[0] = START + timedelta(days=8)
    away = terms.attendance(biz, OWNER)["absent"]
    assert [a["id"] for a in away] == [member["id"]] and away[0]["days"] == 8
    assert away[0]["whatsapp_url"].startswith("https://wa.me/91") and "లేదు" not in away[0]["message"]


def test_the_month_report_counts_who_ended_with_a_come_back_draft(env):
    terms, _, biz, now = env
    terms.add(biz, OWNER, {"name": "Member One", "phone": "9300003050", "months": 1, "fee_paise": 150000,
                           "start_date": "2026-11-01", "paid": True})
    now[0] = datetime(2026, 12, 20, 10, 0, tzinfo=IST)
    report = terms.report(biz, OWNER, "2026-12")
    assert report["left"] == 1 and report["left_members"][0]["end_date"] == "2026-12-01" and report["draft_only"] is True
    assert report["new"] == 0 and report["collected_paise"] == 0
    assert terms.report(biz, OWNER, "2026-11")["collected_paise"] == 150000


def test_permissions_staff_without_reports_and_people_outside_the_shop(env):
    terms, _, biz, _ = env
    terms.add(biz, OWNER, {"name": "Member One", "months": 1, "fee_paise": 150000})
    assert terms.overview(biz, STAFF)["counts"]["members"] == 1
    with pytest.raises(PosError) as error:
        terms.report(biz, STAFF)
    assert error.value.status == 403
    with pytest.raises(PosError) as error:
        terms.overview(biz, STRANGER)
    assert error.value.status == 404
    with pytest.raises(PosError):
        terms.add(biz, OWNER, {"name": "", "months": 1, "fee_paise": 100})
    with pytest.raises(PosError):
        terms.add(biz, OWNER, {"name": "X", "months": 40, "fee_paise": 100})
