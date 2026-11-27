"""Automatic WhatsApp baaki reminders (owner 2026-11-25): staff setting + approved template + the OWNER's switch."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_bills import PosBills
from app.services.pos_dues_followup import PosDuesFollowup
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300000031"
CASHIER = "app-phone-9300000033"


def _env(tmp_path, *, enabled=True, daily=30, sender=True, answer=(True, "")):
    clock = {"now": datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)}
    now = lambda: clock["now"]  # noqa: E731
    tmp_path.mkdir(parents=True, exist_ok=True)
    store = PosStore(str(tmp_path / "pos.db"), clock=now)
    biz = store.create_business(OWNER, {"name": "Sai Kirana", "registration_type": "unregistered", "state_code": "37",
                                        "template": "pharmacy", "invoice_prefix": "SK"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Rice 1kg", "unit": "pcs", "price_paise": 6000, "rate_bp": 0})
    pushes, sent = [], []

    def send(phone, values):
        sent.append((phone, values))
        return answer

    bills = PosBills(store, clock=now)
    follow = PosDuesFollowup(store, bills, notify=lambda *a: pushes.append(a), clock=now,
                             whatsapp=send if sender else None, auto=lambda: {"enabled": enabled, "daily": daily},
                             base_url="https://askodox.example")
    invoices = []
    for n, name in enumerate(["Ravi", "Lakshmi"]):
        cust = store.add_customer(biz, OWNER, {"name": name, "phone": f"930000004{n}"})  # not on ASKODOX
        invoices.append(store.create_invoice(biz, OWNER, {
            "client_txn_id": f"auto-bill-000{n}", "lines": [{"product_id": item["id"], "qty_milli": 2000}],
            "payments": [], "customer_id": cust["id"]}))
    clock["now"] += timedelta(days=4)  # 3 days before the default pay date
    return store, bills, follow, biz, invoices, pushes, sent


def _skip_if_paid(bills, invoices):
    if bills.due_of(invoices[0]["id"]) <= 0:
        pytest.skip("this store issues a bill without payments as paid")


def test_off_by_default_the_owner_gets_the_one_tap_list(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path)
    _skip_if_paid(bills, invoices)
    out = follow.run()
    assert sent == [] and out["auto_whatsapp"] == 0 and out["owners"] == 1, "the owner never switched it on"
    assert follow.reminders(biz, OWNER)["auto"] == {"available": True, "on": False, "owner": True, "price_paise": 0}


def test_owner_switch_sends_once_a_day_and_clears_the_owner_list(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path)
    _skip_if_paid(bills, invoices)
    with pytest.raises(PosError):
        follow.set_auto(biz, CASHIER, True)  # not a member -> refused
    assert follow.set_auto(biz, OWNER, True) == {"available": True, "on": True}
    out = follow.run()
    assert out["auto_whatsapp"] == 2 and out["owners"] == 0, "nothing left for the owner to tap"
    phone, values = sent[0]
    assert len(values) == 5 and values[1] == "Sai Kirana" and values[4].startswith("https://askodox.example/b/")
    assert follow.run()["auto_whatsapp"] == 0 and len(sent) == 2, "never twice on one day"
    rows = follow.reminders(biz, OWNER)["items"]
    assert all(r["sent_today"] and r["sent_auto"] for r in rows) and follow.reminders(biz, OWNER)["to_send"] == 0


def test_daily_cap_and_a_failed_send_stay_with_the_owner(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path, daily=1)
    _skip_if_paid(bills, invoices)
    follow.set_auto(biz, OWNER, True)
    out = follow.run()
    assert out["auto_whatsapp"] == 1 and out["owners"] == 1, "the second bill is over today's cap -> the owner's list"

    store2, bills2, follow2, biz2, invoices2, pushes2, sent2 = _env(tmp_path / "b", answer=(False, "HTTP 400"))
    follow2.set_auto(biz2, OWNER, True)
    out2 = follow2.run()
    assert out2["auto_whatsapp"] == 0 and out2["owners"] == 1 and len(sent2) == 2
    assert follow2.reminders(biz2, OWNER)["to_send"] == 2, "a failed send is never marked as sent"


def test_not_available_without_the_staff_setting_or_the_template(tmp_path):
    store, bills, follow, biz, invoices, pushes, sent = _env(tmp_path, enabled=False)
    with pytest.raises(PosError) as refused:
        follow.set_auto(biz, OWNER, True)
    assert refused.value.code == "auto_unavailable"
    store2, bills2, follow2, biz2, invoices2, pushes2, sent2 = _env(tmp_path / "c", sender=False)
    assert follow2.reminders(biz2, OWNER)["auto"]["available"] is False
