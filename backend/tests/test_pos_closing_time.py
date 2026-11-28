"""Closing time: the owner's own clock time per shop; one push to the owner when it comes; a time only, never a quantity."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_closing_time import PosClosingTime, reminder_text
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000301"
STAFF = "app-phone-9400000302"
T0 = datetime(2026, 11, 28, 16, 0, tzinfo=timezone.utc)  # 21:30 IST


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    biz = store.create_business(OWNER, {"name": "Sample Shop", "template": "general", "invoice_prefix": "SS",
                                         "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000302", "manager")
    return PosClosingTime(store), biz, now


def test_only_the_owner_sets_and_reads(env):
    c, biz, now = env
    assert c.get(biz, OWNER) == {"closing_time": None}
    assert c.set(biz, OWNER, "22:30") == {"closing_time": "22:30"}
    with pytest.raises(PosError) as e:
        c.set(biz, STAFF, "21:00")
    assert e.value.status == 403
    with pytest.raises(PosError):
        c.set(biz, OWNER, "25:00")
    assert c.set(biz, OWNER, "") == {"closing_time": None}


def test_one_push_when_the_time_comes_then_not_again_that_day(env):
    c, biz, now = env
    c.set(biz, OWNER, "22:30")
    assert c.due() == []                       # 21:30 IST: not yet
    now[0] = T0 + timedelta(minutes=65)        # 22:35 IST
    got = c.due()
    assert [g["business_id"] for g in got] == [biz] and got[0]["owner"] == OWNER
    assert c.due() == []                       # once
    now[0] = T0 + timedelta(days=1, minutes=65)
    assert len(c.due()) == 1                   # the next day again
    t = reminder_text(got[0])
    assert t["route"] == f"/pos/{biz}/yield" and not any(ch.isdigit() for ch in t["body"])


def test_a_long_missed_time_is_not_pushed_late(env):
    c, biz, now = env
    c.set(biz, OWNER, "22:30")
    now[0] = T0 + timedelta(hours=5)           # 02:30 IST next day's early hours: far past, marked but silent
    assert c.due() == []
