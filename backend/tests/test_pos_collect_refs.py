"""One owner-UPI QR rule for every way of working (owner 2026-11-24): job card balance, booking price, monthly due.
Both the owner and the person who showed the QR are told; the owner's confirmation records the money on the card."""
from datetime import datetime, timezone

import pytest

from app.services import pos_collect_refs
from app.services.pos_payment_alerts import PosPaymentAlerts
from app.services.pos_store import PosError, PosStore
from app.services.pos_work import PosJobs, PosMonthly

OWNER = "app-phone-9400000801"
CASHIER = "app-phone-9400000802"


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    pushes = []
    notify = lambda u, t, b, r, k, *rest: pushes.append((u, t, b, r, k))  # noqa: E731
    shop = store.create_business(OWNER, {"name": "Sai Tailors", "state_code": "37"})["id"]
    store.set_member(shop, OWNER, "9400000802", "cashier", label="Lakshmi")
    alerts = PosPaymentAlerts(store, notify=notify)
    alerts._collect_method = lambda conn, biz: {"upi_id": "sai@okhdfcbank", "payee_name": "Sai Tailors"}
    return store, alerts, shop, pushes, PosJobs(store, notify=notify), PosMonthly(store, notify=notify)


def test_job_card_balance_qr_both_told_and_recorded(env):
    store, alerts, shop, pushes, jobs, _ = env
    job = jobs.create(shop, OWNER, {"item": "Blouse", "estimate_paise": 80000, "advance_paise": 20000})
    qr = pos_collect_refs.ask(store, alerts, shop, CASHIER, "job", job["id"])
    assert qr["amount_paise"] == 60000 and qr["label"].startswith("టోకెన్")
    assert pos_collect_refs.ask(store, alerts, shop, CASHIER, "job", job["id"])["id"] == qr["id"], "one open QR per thing"
    with store._tx() as conn:
        alerts._match_request(conn, shop, "ppe_1", 60000)
    told = [p for p in pushes if "వచ్చింది" in p[1]]
    assert {p[0] for p in told} == {OWNER, CASHIER} and told[0][3] == f"/pos/{shop}/payment-alerts"
    alerts.decide_request(shop, OWNER, qr["id"], "confirm")
    got = [j for j in jobs.for_business(shop, OWNER)["jobs"] if j["id"] == job["id"]][0]
    assert got["balance_paise"] == 0, "the confirmed money is recorded on the job card"
    with pytest.raises(PosError):
        pos_collect_refs.ask(store, alerts, shop, CASHIER, "job", job["id"])  # nothing left


def test_monthly_due_qr_marks_the_month_paid(env):
    store, alerts, shop, _, _, monthly = env
    plan = monthly.save_plan(shop, OWNER, {"name": "Gym", "amount_paise": 50000})
    plan_id = plan["id"] if isinstance(plan, dict) and "id" in plan else monthly.plans(shop, OWNER)[0]["id"]
    month = monthly.add_member(shop, OWNER, {"name": "Ravi", "phone": "9400000899", "plan_id": plan_id})
    member = month["members"][0]
    qr = pos_collect_refs.ask(store, alerts, shop, OWNER, "member", member["id"], month["month"])
    assert qr["amount_paise"] == 50000
    with store._tx() as conn:
        alerts._match_request(conn, shop, "ppe_2", 50000)
    alerts.decide_request(shop, OWNER, qr["id"], "confirm")
    paid = monthly.month(shop, OWNER, month["month"])["members"][0]
    assert paid["left_paise"] == 0 and paid["due_status"] == "paid"


def test_unknown_kind_and_strangers_refused(env):
    store, alerts, shop, _, jobs, _ = env
    job = jobs.create(shop, OWNER, {"item": "Cake", "estimate_paise": 1000})
    with pytest.raises(PosError):
        pos_collect_refs.ask(store, alerts, shop, OWNER, "nope", job["id"])
    with pytest.raises(PosError):
        pos_collect_refs.ask(store, alerts, shop, "app-phone-9400000999", "job", job["id"])
