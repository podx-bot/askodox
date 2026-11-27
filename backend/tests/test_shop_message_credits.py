"""Paid AUTOMATIC sending (owner 2026-11-27): one `shop_message` use from the shop owner's credits per message.

Manual sending stays free; automatic = one price per message, never under 5 paise while charging is ON;
too few credits -> nothing is sent and the owner keeps his own one-tap list; a refused send is given back."""
from datetime import datetime, timezone

from app.services.ai_credits import MIN_RATE_PAISE, AiCredits
from tests.test_pos_dues_auto_whatsapp import OWNER, _env, _skip_if_paid

NO_PLAN = {"daily_free_paise": 0, "first_bonus_pct": 0, "daily_bonus_pct": 0}


def _credits(tmp_path, *, rate=0, funds=0, charging=True):
    tmp_path.mkdir(parents=True, exist_ok=True)
    svc = AiCredits(str(tmp_path / "credits.db"), clock=lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc))
    settings = {"plan": NO_PLAN}
    if charging:
        settings.update({"charging": True, "rates_paise": {"chat": 50, "shop_message": rate}})
    svc.update_settings(settings, actor="staff:1")
    if funds:
        svc.topup(OWNER, paise=funds, purchase_id="p1", mode="live")
    return svc


def _wire(follow, credits):
    follow.credits = credits
    return follow


def test_price_is_zero_off_and_never_under_the_floor_on(tmp_path):
    off = _credits(tmp_path / "a", charging=False)
    assert off.price("shop_message") == 0
    on = _credits(tmp_path / "b", rate=0)
    assert on.price("shop_message") == MIN_RATE_PAISE["shop_message"] == 5, "staff left 0 -> still 5 paise"
    dearer = _credits(tmp_path / "c", rate=12)
    assert dearer.price("shop_message") == 12
    assert dearer.price("chat") == 50


def test_each_automatic_send_costs_one_price_from_the_owner(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path / "e")
    _skip_if_paid(bills, invoices)
    credits = _credits(tmp_path / "c", rate=0, funds=1000)
    _wire(follow, credits)
    follow.set_auto(biz, OWNER, True)
    out = follow.run()
    assert out["auto_whatsapp"] == 2 and len(sent) == 2
    assert credits.balance(OWNER)["live"] == 1000 - 2 * 5
    assert follow.run()["auto_whatsapp"] == 0 and credits.balance(OWNER)["live"] == 990, "never charged twice a day"


def test_too_few_credits_sends_nothing_and_the_owner_keeps_the_list(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path / "e")
    _skip_if_paid(bills, invoices)
    credits = _credits(tmp_path / "c", rate=0, funds=0)
    _wire(follow, credits)
    follow.set_auto(biz, OWNER, True)
    out = follow.run()
    assert out["auto_whatsapp"] == 0 and out["owners"] == 1 and sent == []
    assert follow.reminders(biz, OWNER)["to_send"] == 2, "the one-tap manual list is untouched"


def test_a_refused_send_is_given_back(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path / "e", answer=(False, "HTTP 400"))
    _skip_if_paid(bills, invoices)
    credits = _credits(tmp_path / "c", rate=0, funds=1000)
    _wire(follow, credits)
    follow.set_auto(biz, OWNER, True)
    follow.run()
    assert len(sent) == 2 and credits.balance(OWNER)["live"] == 1000, "provider said no -> nothing kept"


def test_charging_off_stays_free(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path / "e")
    _skip_if_paid(bills, invoices)
    credits = _credits(tmp_path / "c", charging=False)
    _wire(follow, credits)
    follow.set_auto(biz, OWNER, True)
    assert follow.run()["auto_whatsapp"] == 2 and credits.balance(OWNER) == {"live": 0, "test": 0}
