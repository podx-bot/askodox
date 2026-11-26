"""AI plan (owner 2026-11-26): Rs 10 free every India day (use it or lose it), the day's free part before the pack,
first recharge double once, first recharge of a day +10%, friend refill once a day, percent bars, shop core free."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.ai_credits import AiCredits, CreditsError

USER = "app-phone-9400000801"
IST = timezone(timedelta(hours=5, minutes=30))


class Clock:
    def __init__(self):
        self.now = datetime(2026, 11, 26, 9, 0, tzinfo=IST)

    def __call__(self):
        return self.now.astimezone(timezone.utc)

    def at(self, day, hour, minute=0):
        self.now = datetime(2026, 11, day, hour, minute, tzinfo=IST)


def _svc(tmp_path, **plan):
    clock = Clock()
    svc = AiCredits(str(tmp_path / "p.db"), clock=clock)
    svc.update_settings({"charging": True, "rates_paise": {"chat": 100, "image": 400}, "plan": plan}, actor="staff:1")
    return svc, clock


def test_owner_numbers_are_the_defaults(tmp_path):
    plan = AiCredits(str(tmp_path / "d.db")).settings()["plan"]
    assert plan == {"daily_free_paise": 1000, "daily_free_days": 0, "first_bonus_pct": 100, "daily_bonus_pct": 10,
                    "friend_refill": True, "play_fee_pct": 15}


def test_ten_rupees_free_a_day_without_any_recharge_then_stops_until_midnight(tmp_path):
    svc, clock = _svc(tmp_path)
    for n in range(10):
        assert svc.reserve(USER, "chat", f"a{n}") == {"charged": True, "paise": 100, "mode": "free", "pack_paise": 0}
    assert svc.status(USER)["free"]["percent_left"] == 0
    with pytest.raises(CreditsError) as err:
        svc.reserve(USER, "chat", "a10")
    assert err.value.status == 402
    assert svc.balance(USER) == {"live": 0, "test": 0}, "the free part is never a balance"
    assert svc.history(USER) == [], "free use is not a money row"
    clock.at(26, 23, 59)
    with pytest.raises(CreditsError):
        svc.reserve(USER, "chat", "late")
    clock.at(27, 0, 1)  # India midnight, not UTC midnight
    assert svc.status(USER)["free"]["percent_left"] == 100
    assert svc.reserve(USER, "chat", "b0")["mode"] == "free"


def test_unused_free_part_is_lost_at_midnight(tmp_path):
    svc, clock = _svc(tmp_path)
    svc.reserve(USER, "chat", "a")
    clock.at(27, 8)
    for n in range(10):
        svc.reserve(USER, "chat", f"b{n}")
    with pytest.raises(CreditsError):
        svc.reserve(USER, "chat", "b10")  # yesterday's unused Rs 9 did not carry over


def test_free_first_then_pack_and_a_use_can_take_from_both(tmp_path):
    svc, clock = _svc(tmp_path, first_bonus_pct=0)
    svc.topup(USER, paise=1000, purchase_id="p1", mode="live")
    for n in range(2):
        assert svc.reserve(USER, "image", f"i{n}")["mode"] == "free"
    assert svc.balance(USER)["live"] == 1000, "the pack is untouched while today's free part lasts"
    svc.reserve(USER, "chat", "c")  # Rs 1 left free
    both = svc.reserve(USER, "image", "i2")
    assert both == {"charged": True, "paise": 400, "mode": "live", "pack_paise": 300}
    assert svc.balance(USER)["live"] == 700
    assert svc.release(USER, "i2") and svc.balance(USER)["live"] == 1000
    assert svc.reserve(USER, "chat", "c2")["mode"] == "free", "the released free rupee is back too"
    assert svc.reserve(USER, "chat", "c3") == {"charged": True, "paise": 100, "mode": "live"}
    assert svc.reserve(USER, "chat", "c3")["repeat"]


def test_people_who_paid_have_no_limit(tmp_path):
    svc, clock = _svc(tmp_path)
    svc.topup(USER, paise=10000, purchase_id="p1", mode="live")
    for n in range(150):
        svc.reserve(USER, "chat", f"u{n}")
    assert svc.balance(USER)["live"] == 20000 - 14000


def test_first_recharge_doubles_once_then_ten_percent_on_the_first_of_each_day(tmp_path):
    svc, clock = _svc(tmp_path)
    assert svc.status(USER)["bonus"] == {"percent": 100, "kind": "first_recharge", "left_today": True}
    assert svc.topup(USER, paise=10000, purchase_id="p1", mode="live")
    assert svc.balance(USER)["live"] == 20000
    assert not svc.topup(USER, paise=10000, purchase_id="p1", mode="live"), "a repeated webhook adds nothing"
    assert svc.balance(USER)["live"] == 20000
    assert svc.status(USER)["bonus"] == {"percent": 0, "kind": "used_today", "left_today": False}
    svc.topup(USER, paise=10000, purchase_id="p2", mode="live")  # same day: 1:1
    assert svc.balance(USER)["live"] == 30000
    clock.at(27, 10)
    assert svc.status(USER)["bonus"] == {"percent": 10, "kind": "daily_first", "left_today": True}
    svc.topup(USER, paise=10000, purchase_id="p3", mode="live")
    assert svc.balance(USER)["live"] == 41000
    svc.topup(USER, paise=10000, purchase_id="p4", mode="live")
    assert svc.balance(USER)["live"] == 51000
    assert [h["kind"] for h in svc.history(USER)] == ["topup", "bonus", "topup", "topup", "bonus", "topup"]


def test_refund_takes_the_extra_back_and_never_gives_a_second_double(tmp_path):
    svc, clock = _svc(tmp_path)
    svc.topup(USER, paise=10000, purchase_id="p1", mode="live")
    assert svc.reverse_topup(USER, purchase_id="p1") and not svc.reverse_topup(USER, purchase_id="p1")
    assert svc.balance(USER)["live"] == 0
    clock.at(27, 10)
    svc.topup(USER, paise=10000, purchase_id="p2", mode="live")
    assert svc.balance(USER)["live"] == 11000, "the double is once per account, a refund does not bring it back"


def test_free_only_for_the_first_days_when_staff_set_a_number(tmp_path):
    svc, clock = _svc(tmp_path, daily_free_days=2)
    assert svc.reserve(USER, "chat", "d1")["mode"] == "free"
    clock.at(27, 9)
    assert svc.reserve(USER, "chat", "d2")["mode"] == "free"
    clock.at(28, 9)
    assert svc.status(USER)["free"]["on"] is False
    with pytest.raises(CreditsError):
        svc.reserve(USER, "chat", "d3")
    svc.update_settings({"plan": {"daily_free_days": ""}}, actor="staff:1")  # empty box = for ever
    assert svc.reserve(USER, "chat", "d4")["mode"] == "free"


def test_friend_joined_refills_today_once(tmp_path):
    svc, clock = _svc(tmp_path)
    for n in range(10):
        svc.reserve(USER, "chat", f"a{n}")
    assert svc.friend_joined(USER) is True
    assert svc.status(USER)["free"]["percent_left"] == 100
    for n in range(10):
        svc.reserve(USER, "chat", f"b{n}")
    assert svc.friend_joined(USER) is False, "once a day"
    assert svc.status(USER)["free"]["percent_left"] == 0
    clock.at(27, 9)
    svc.reserve(USER, "chat", "c")
    assert svc.friend_joined(USER) is True
    svc.update_settings({"plan": {"friend_refill": False}}, actor="staff:1")
    assert svc.friend_joined("app-phone-9400000802") is False


def test_bars_are_percent_with_a_pace_warning_and_no_rupees(tmp_path):
    svc, clock = _svc(tmp_path)
    svc.topup(USER, paise=10000, purchase_id="p1", mode="live")
    clock.at(26, 12)
    for n in range(5):
        svc.reserve(USER, "chat", f"a{n}")
    status = svc.status(USER)
    assert status["free"]["percent_left"] == 50 and status["free"]["resets_at"].startswith("2026-11-27T00:00:00")
    assert status["free"]["runs_out_at"] is None, "half used by noon lasts the day"
    for n in range(4):
        svc.reserve(USER, "chat", f"b{n}")
    assert svc.status(USER)["free"]["runs_out_at"].startswith("2026-11-26T13:")
    for n in range(41):
        svc.reserve(USER, "chat", f"c{n}")
    status = svc.status(USER)
    assert status["pack"]["percent_left"] == 80 and status["pack"]["has"] and status["pack"]["days_left"] == 4
    assert "paise" not in str(status) and "rupee" not in str(status)


def test_shop_core_stays_free_whatever_the_plan(tmp_path):
    svc, clock = _svc(tmp_path, daily_free_paise=0)
    for tool in ("payment_voice", "quick_bill", "dues", "sales_reports"):
        assert svc.reserve(USER, tool, f"s-{tool}") == {"charged": False, "reason": "free_forever", "paise": 0}
    with pytest.raises(CreditsError):
        svc.reserve(USER, "chat", "x")


def test_plan_numbers_are_checked_and_the_estimate_reads_the_ledger(tmp_path):
    svc, clock = _svc(tmp_path)
    with pytest.raises(CreditsError):
        svc.update_settings({"plan": {"daily_bonus_pct": 500}}, actor="staff:1")
    with pytest.raises(CreditsError):
        svc.update_settings({"plan": {"surprise": 1}}, actor="staff:1")
    svc.reserve(USER, "chat", "a")
    svc.reserve("app-phone-9400000802", "image", "b")
    svc.topup(USER, paise=10000, purchase_id="p1", mode="live")
    out = svc.plan_estimate(days=7)
    assert out["free"] == {"people": 2, "used_paise": 500, "most_paise": 2 * 1000 * 7, "refills": 0}
    assert out["recharges"] == {"count": 1, "paid_paise": 10000, "extra_given_paise": 10000, "refunded_paise": 0,
                                "store_fee_paise": 1500}
    assert svc.summary()["negative_balances"] == 0, "the free part is not a negative balance"


def test_app_gets_percent_bars_and_staff_plan_page_needs_staff(monkeypatch):
    from fastapi.testclient import TestClient

    from app.api.routes import ai_credits as routes
    from app.services import rate_limit
    from app.services.ai_credits import PLAN_DEFAULTS
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "ai_credits", None, raising=False)
    user = "app-phone-9411100811"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    svc = routes.ai_credits(container)
    svc.update_settings({"charging": True, "rates_paise": {"chat": 100}, "plan": dict(PLAN_DEFAULTS)}, actor="test")
    try:
        svc.reserve(user, "chat", "http-1")
        mine = client.get("/api/me/ai-credits", headers=auth).json()
        assert mine["status"]["free"]["percent_left"] == 90 and mine["status"]["free"]["on"] is True
        assert mine["status"]["pack"] == {"percent_left": 0, "has": False, "test": False, "days_left": None}
        assert mine["status"]["bonus"] == {"percent": 100, "kind": "first_recharge", "left_today": True}
        assert mine["history"] == [] and mine["balance_paise"] == {"live": 0, "test": 0}
        assert client.get("/admin/cc/ai-credits/plan").status_code in (401, 403)
        assert client.put("/admin/cc/ai-credits/settings", json={"plan": {"daily_free_paise": 0}}).status_code in (401, 403)
    finally:
        svc.update_settings({"charging": False, "plan": dict(PLAN_DEFAULTS)}, actor="test")
