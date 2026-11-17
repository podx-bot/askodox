import uuid
from datetime import datetime

import pytest

from app.services.pos_reports import PosReports
from app.services.pos_store import IST, PosError
from tests.test_pos_frontdesk import CASHIER, COOK, OWNER, env  # noqa: F401  (fixture)

DAY = "2026-11-15"  # the fixture clock: 2026-11-15 11:30 IST


def _sell(store, biz, cashier, items, method="cash"):
    total = sum(p * q for _, q, p in items)
    return store.create_invoice(biz, cashier, {"client_txn_id": "t-" + uuid.uuid4().hex,
                                                "lines": [{"product_id": i, "qty_milli": q * 1000} for i, q, _ in items],
                                                "payments": [{"method": method, "amount_paise": total}]})


def _order(conn, biz, table, placed, accepted=None, ready=None, stage="done", reason=""):
    oid = "dsk_" + uuid.uuid4().hex[:10]
    conn.execute("INSERT INTO pos_desk_orders (id, business_id, source, kind, table_id, items_json, stage, reason,"
                 " client_txn_id, placed_at, updated_at) VALUES (?, ?, 'qr', 'dine_in', ?, '[]', ?, ?, ?, ?, ?)",
                 (oid, biz, table, stage, reason, oid, placed, placed))
    for st, at in (("accepted", accepted), ("ready", ready)):
        if at:
            conn.execute("INSERT INTO pos_desk_events (order_id, business_id, stage, actor, at) VALUES (?, ?, ?, 'x', ?)",
                         (oid, biz, st, at))
    return oid


def test_day_report_counts_problems_with_reasons_and_a_face(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    reports = PosReports(store)
    _sell(store, biz, CASHIER, [(biryani, 2, 16000)])
    _sell(store, biz, OWNER, [(fry, 1, 30000)], method="upi")
    with store._connect() as conn:
        _order(conn, biz, table, "2026-11-15T12:00:00+05:30", "2026-11-15T12:09:00+05:30", "2026-11-15T12:45:00+05:30")
        oid = _order(conn, biz, table, "2026-11-15T13:00:00+05:30", "2026-11-15T13:01:00+05:30", "2026-11-15T13:15:00+05:30")
        _order(conn, biz, table, "2026-11-15T14:00:00+05:30", stage="rejected", reason="biryani finished")
        for minute in (5, 9, 14):  # the same table asks three times
            conn.execute("INSERT INTO pos_desk_requests (id, business_id, order_id, table_id, kind, label, status,"
                         " created_at, done_at) VALUES (?, ?, ?, ?, 'water', 'Water', 'done', ?, ?)",
                         (uuid.uuid4().hex, biz, oid, table, f"2026-11-15T13:{minute:02d}:00+05:30",
                          f"2026-11-15T13:{minute + 2:02d}:00+05:30"))
    r = reports.day(biz, OWNER, DAY)
    assert r["sales"]["paise"] == 62000 and r["sales"]["bills"] == 2
    assert r["money"]["cash_paise"] == 32000 and r["money"]["online_paise"] == 30000
    assert r["peak_hour"] == 11
    assert [i["name"] for i in r["items"]["top"]] == ["Chicken Biryani", "Chicken Fry"] or r["items"]["top"][0]["paise"] == 32000
    o = r["orders"]
    assert o["count"] == 3 and o["slow_accept"][0]["minutes"] == 9 and o["slow_ready"][0]["minutes"] == 45
    assert o["repeat_calls"][0]["times"] == 3 and o["lost"][0]["reason"] == "biryani finished"
    keys = [p["key"] for p in r["problems"]]
    assert {"repeat_calls", "slow_food", "slow_accept", "lost_orders"} <= set(keys)
    assert all(p["text_te"] and p["do_te"] and p["page"] for p in r["problems"])
    assert r["problems"][0]["level"] == "high"
    assert r["mood"] in ("ok", "bad") and "బిల్లులు" in r["say_te"]
    by = {p["name"]: p for p in r["staff"]["by_person"]}
    assert by["Owner"]["paise"] == 30000
    with pytest.raises(PosError):
        reports.day(biz, COOK, DAY)  # the kitchen cannot read reports
    with pytest.raises(PosError):
        reports.day(biz, OWNER, "15-11-2026")


def test_range_has_series_items_and_weekdays(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    _sell(store, biz, CASHIER, [(biryani, 1, 16000)])
    rng = PosReports(store).range(biz, OWNER, 30)
    assert rng["days"] == 30 and len(rng["series"]) == 30 and len(rng["weekdays"]) == 7 and len(rng["hours"]) == 24


def test_night_report_once_per_day_to_owner_and_report_readers(env):  # noqa: F811
    desk, store, rest, biz, table, biryani, fry, now, _ = env
    _sell(store, biz, CASHIER, [(biryani, 1, 16000)])
    store.set_member(biz, OWNER, "9400000104", "accountant")
    pushes = []
    reports = PosReports(store, notify=lambda *a: pushes.append(a))
    assert reports.run_night(datetime(2026, 11, 15, 23, 0, tzinfo=IST))["sent"] == 0 or not pushes  # not yet midnight
    out = reports.run_night(datetime(2026, 11, 16, 0, 5, tzinfo=IST))
    assert out["sent"] >= 1 and pushes and pushes[0][0] == OWNER
    assert any("/reports/day?date=2026-11-15" in p[3] for p in pushes)
    count = len(pushes)
    reports.run_night(datetime(2026, 11, 16, 0, 15, tzinfo=IST))
    assert len(pushes) == count  # once only
    reports.save_settings(biz, OWNER, False, "22:30")
    assert reports.settings(biz, OWNER) == {"night_push": False, "send_time": "22:30"}
    assert PosReports.due_date("22:30", datetime(2026, 11, 16, 22, 40, tzinfo=IST)).isoformat() == "2026-11-16"
    assert PosReports.due_date("00:00", datetime(2026, 11, 16, 0, 1, tzinfo=IST)).isoformat() == "2026-11-15"
