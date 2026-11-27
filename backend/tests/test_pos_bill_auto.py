"""Bills sent by ASKODOX itself (owner 2026-11-27): paid automatic option; manual send stays free."""
from datetime import datetime, timedelta, timezone

from app.services.pos_bill_auto import PosBillAuto
from tests.test_pos_dues_auto_whatsapp import OWNER, _env
from tests.test_shop_message_credits import _credits


def _auto(store, bills, follow, credits, *, enabled=True, daily=100, answer=(True, "")):
    sent = []

    def send(phone, values):
        sent.append((phone, values))
        return answer

    job = PosBillAuto(store, bills, follow, whatsapp=send, auto=lambda: {"enabled": enabled, "daily": daily},
                      credits=credits, base_url="https://askodox.example")
    return job, sent


def _fresh(tmp_path, **kw):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path, **kw)
    follow.clock = lambda: datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc) + timedelta(days=0)
    return store, bills, follow, biz, invoices


def test_owner_switch_required_then_one_price_per_bill(tmp_path):
    store, bills, follow, biz, invoices = _fresh(tmp_path / "e")
    # the invoices were issued 4 days before "now" in _env; make the job see them as just issued
    now = follow.clock()
    with store._tx() as conn:
        conn.execute("UPDATE pos_invoices SET issued_at = ?", (now.isoformat(),))
    credits = _credits(tmp_path / "c", rate=0, funds=1000)
    job, sent = _auto(store, bills, follow, credits)
    assert job.run()["sent"] == 0 and sent == [], "the owner never switched it on"
    follow.set_auto(biz, OWNER, True)
    out = job.run()
    assert out["sent"] == 2 and len(sent) == 2
    phone, values = sent[0]
    assert len(values) == 5 and values[1] == "Sai Kirana" and values[4].startswith("https://askodox.example/b/")
    assert credits.balance(OWNER)["live"] == 1000 - 2 * 5
    assert job.run()["sent"] == 0 and len(sent) == 2, "a bill is sent once"


def test_no_credits_or_refused_send_costs_nothing(tmp_path):
    store, bills, follow, biz, invoices = _fresh(tmp_path / "e")
    with store._tx() as conn:
        conn.execute("UPDATE pos_invoices SET issued_at = ?", (follow.clock().isoformat(),))
    follow.set_auto(biz, OWNER, True)
    broke = _credits(tmp_path / "c1", rate=0, funds=0)
    job, sent = _auto(store, bills, follow, broke)
    out = job.run()
    assert out["sent"] == 0 and sent == [] and out["kept_for_owner"] == 2

    store2, bills2, follow2, biz2, _inv = _fresh(tmp_path / "e2")
    with store2._tx() as conn:
        conn.execute("UPDATE pos_invoices SET issued_at = ?", (follow2.clock().isoformat(),))
    follow2.set_auto(biz2, OWNER, True)
    funded = _credits(tmp_path / "c2", rate=0, funds=1000)
    job2, sent2 = _auto(store2, bills2, follow2, funded, answer=(False, "HTTP 400"))
    assert job2.run()["sent"] == 0 and len(sent2) == 2 and funded.balance(OWNER)["live"] == 1000


def test_off_by_staff_setting_does_nothing(tmp_path):
    store, bills, follow, biz, invoices = _fresh(tmp_path / "e")
    follow.set_auto(biz, OWNER, True)
    job, sent = _auto(store, bills, follow, _credits(tmp_path / "c", funds=1000), enabled=False)
    assert job.run() == {"bills": 0, "sent": 0, "in_app": 0, "kept_for_owner": 0} and sent == []
