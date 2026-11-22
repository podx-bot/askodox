import base64
from datetime import datetime

import pytest

from app.services.pos_attendance import PosAttendance
from app.services.pos_cashbook import PosCashbook
from app.services.pos_store import IST, PosError
from tests.test_pos_frontdesk import CASHIER, COOK, OWNER, env  # noqa: F401  (fixture)


def _att(store, at):
    clock = [at]
    pushes = []
    return PosAttendance(store, notify=lambda *a: pushes.append(a), clock=lambda: clock[0]), clock, pushes


def test_check_in_late_far_out_overtime_and_owner_sees_everyone(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    with store._connect() as conn:  # the shop's map pin
        conn.execute("CREATE TABLE IF NOT EXISTS shop_profiles (business_id TEXT PRIMARY KEY, data TEXT NOT NULL,"
                     " updated_at TEXT, verified_at TEXT)")
        conn.execute("INSERT INTO shop_profiles (business_id, data, updated_at) VALUES (?, ?, '')",
                     (biz, '{"lat": "16.3650", "lng": "80.8470"}'))
    att, clock, _ = _att(store, datetime(2026, 11, 18, 9, 41, tzinfo=IST))
    row = att.check(biz, CASHIER, "in", lat=16.3651, lng=80.8471)
    assert row["status"] == "P" and row["late_min"] == 26 and row["far"] is False and row["distance_m"] < 50
    assert att.check(biz, CASHIER, "in")["already"] is True  # a second tap changes nothing
    far = att.check(biz, COOK, "in", lat=16.40, lng=80.90)
    assert far["far"] is True
    clock[0] = datetime(2026, 11, 18, 23, 0, tzinfo=IST)
    out = att.check(biz, CASHIER, "out")
    assert out["status"] == "OT" and out["ot_min"] >= 30
    today = att.today(biz, OWNER)
    assert {p["ref"] for p in today["people"]} == {"0102", "0103"} and today["counts"]["present"] == 2
    assert today["counts"]["late"] == 2 and today["counts"]["far"] == 1
    mine = att.today(biz, CASHIER)  # staff see only themselves
    assert [p["ref"] for p in mine["people"]] == ["0103"]
    with pytest.raises(PosError):
        att.check(biz, "app-phone-9000000009", "in")  # not on the staff list


def test_kiosk_needs_a_photo_and_only_bosses_see_it(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    att, clock, _ = _att(store, datetime(2026, 11, 18, 9, 0, tzinfo=IST))
    with pytest.raises(PosError):
        att.check(biz, OWNER, "in", for_ref="0102")  # no photo
    photo = base64.b64encode(b"\xff\xd8jpeg").decode()
    row = att.check(biz, OWNER, "in", for_ref="0102", photo_b64=photo)
    assert row["method"] == "kiosk"
    assert att.photo(biz, OWNER, row["id"])[0] == b"\xff\xd8jpeg"
    with pytest.raises(PosError):
        att.photo(biz, CASHIER, row["id"])
    with pytest.raises(PosError):
        att.check(biz, CASHIER, "in", for_ref="0102", photo_b64=photo)  # a cashier is not a kiosk


def test_month_salary_advance_and_paid_goes_to_the_cashbook(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    att, clock, _ = _att(store, datetime(2026, 11, 30, 20, 0, tzinfo=IST))
    att.set_pay(biz, OWNER, "0103", {"salary_kind": "month", "salary_paise": 1200000, "ot_rate_paise": 10000})
    for d in range(1, 16):
        att.mark(biz, OWNER, "0103", f"2026-11-{d:02d}", "P")
    att.mark(biz, OWNER, "0103", "2026-11-16", "A")
    att.mark(biz, OWNER, "0103", "2026-11-17", "OT", ot_min=240)
    att.advance(biz, OWNER, "0103", 150000, "festival")
    month = att.month(biz, OWNER, "0103", "2026-11")
    s = month["salary"]
    assert month["counts"]["present"] == 16 and month["counts"]["absent"] == 1
    assert s["per_day_paise"] == 40000 and s["base_paise"] == 640000 and s["ot_paise"] == 40000
    assert s["net_paise"] == 640000 + 40000 - 150000
    paid = att.pay_salary(biz, OWNER, "0103", "2026-11")
    assert paid["amount_paise"] == s["net_paise"]
    assert att.pay_salary(biz, OWNER, "0103", "2026-11")["already"] is True
    book = PosCashbook(store).month(biz, OWNER, "2026-11")
    assert book["expense_by_category"]["salary"] == 150000 + s["net_paise"]
    with pytest.raises(PosError):
        att.mark(biz, CASHIER, "0102", "2026-11-18", "A")  # only the owner / manager marks


def test_tasks_ring_the_assignee_and_only_they_finish_it(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    with store._connect() as conn:
        conn.execute("UPDATE pos_members SET app_user_id = ? WHERE business_id = ? AND phone_key LIKE '%0103'", (CASHIER, biz))
    att, clock, pushes = _att(store, datetime(2026, 11, 18, 10, 0, tzinfo=IST))
    task = att.add_task(biz, OWNER, "Clean tables", "0103", "2026-11-18T15:00:00+05:30")
    assert pushes and pushes[0][0] == CASHIER
    with pytest.raises(PosError):
        att.task_done(biz, COOK, task["id"])
    att.task_done(biz, CASHIER, task["id"])
    assert att.tasks(biz, OWNER)["counts"]["done"] == 1


def test_staff_mark_their_own_half_day_and_a_short_day_becomes_half(env):  # noqa: F811
    _desk, store, _rest, biz, *_ = env
    att, clock, _ = _att(store, datetime(2026, 11, 18, 9, 5, tzinfo=IST))
    assert att.check(biz, CASHIER, "half")["status"] == "half", "the staff member says half day themselves"
    assert att.check(biz, COOK, "in")["status"] == "P"
    clock[0] = datetime(2026, 11, 18, 12, 0, tzinfo=IST)  # under half of the 09:00-21:00 shift
    assert att.check(biz, COOK, "out")["status"] == "half"


def test_holiday_is_a_paid_day_and_bonus_adds_to_the_month(env):  # noqa: F811
    _desk, store, _rest, biz, *_ = env
    att, clock, _ = _att(store, datetime(2026, 11, 18, 9, 0, tzinfo=IST))
    ref = CASHIER[-10:]
    att.set_pay(biz, OWNER, ref, {"salary_kind": "month", "salary_paise": 30 * 50000})
    att.check(biz, CASHIER, "in")
    before = att.month(biz, OWNER, ref)["salary"]
    assert att.set_holiday(biz, OWNER, "2026-11-17", "Festival") == [{"date": "2026-11-17", "name": "Festival"}]
    att.bonus(biz, OWNER, ref, 100000, "festival")
    after = att.month(biz, OWNER, ref)["salary"]
    assert after["holiday_days"] == 1 and after["bonus_paise"] == 100000
    assert after["net_paise"] == before["net_paise"] + 50000 + 100000
    assert att.set_holiday(biz, OWNER, "2026-11-17", remove=True) == []


def test_today_carries_the_callers_own_day_so_the_owner_can_check_out(env):  # noqa: F811
    """Owner 2026-11-22 ("3 steps" check-in): the owner marks their own attendance too; today() lists the staff for
    the owner, so the caller's own record comes back as ``me`` (the big button turns into "I'm leaving")."""
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    att, clock, _ = _att(store, datetime(2026, 11, 18, 9, 5, tzinfo=IST))
    assert att.today(biz, OWNER)["me"] is None
    att.check(biz, OWNER, "in")
    me = att.today(biz, OWNER)["me"]
    assert me is not None and me["in_at"] and me["out_at"] is None
    assert all(p["ref"] != OWNER[-4:] for p in att.today(biz, OWNER)["people"])  # the staff list stays staff only
    att.check(biz, CASHIER, "in")
    assert att.today(biz, CASHIER)["me"]["in_at"]
    clock[0] = datetime(2026, 11, 18, 21, 30, tzinfo=IST)
    att.check(biz, OWNER, "out")
    assert att.today(biz, OWNER)["me"]["out_at"]
