"""Table watch: the table's QR says someone sat; the floor sees seated / unseen / waiting / eating; staff told once."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_frontdesk import QR_PREFIX, PosFrontDesk
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore
from app.services.pos_table_watch import MAX_ALERTS_PER_TABLE_DAY, UNSEEN_MINUTES, PosTableWatch, alert_text

OWNER = "app-phone-9400000201"
WAITER = "app-phone-9400000202"
COOK = "app-phone-9400000203"
RIDER = "app-phone-9400000204"
CUSTOMER = "app-phone-9876500001"
STRANGER = "app-phone-9876500002"
T0 = datetime(2026, 11, 27, 6, 0, tzinfo=timezone.utc)


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    rest = PosRestaurant(store)
    desk = PosFrontDesk(store, rest, notify=lambda u, t, b, r, k: None)
    watch = PosTableWatch(store)
    biz = store.create_business(OWNER, {"name": "Sample Hotel", "template": "restaurant", "invoice_prefix": "SH",
                                         "state_code": "37"})["id"]
    store.set_member(biz, OWNER, "9400000202", "waiter")
    store.set_member(biz, OWNER, "9400000203", "kitchen", accepts_orders=True)
    store.set_member(biz, OWNER, "9400000204", "delivery")
    t1 = rest.add_table(biz, OWNER, {"name": "T1"})["id"]
    t2 = rest.add_table(biz, OWNER, {"name": "T2"})["id"]
    item = store.add_product(biz, OWNER, {"name": "Idli", "unit": "plate", "price_paise": 4000})["id"]
    watch.watch(biz, WAITER)  # the waiter has opened ASKODOX once: the staff row is linked to their account
    return watch, desk, store, rest, biz, t1, t2, item, now


def _state(watch, biz, table):
    return next(t for t in watch.watch(biz, OWNER)["tables"] if t["id"] == table)


def test_sat_then_unseen_then_staff_told_once(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    assert _state(watch, biz, t1)["state"] == "empty"
    assert watch.sat(biz, t1) is True
    assert watch.sat(biz, t1) is False  # a second person at the table, or the menu opened again
    assert watch.sat(biz, "tbl_unknown") is False
    now[0] = T0 + timedelta(minutes=3)
    seen = _state(watch, biz, t1)
    assert seen["state"] == "seated" and seen["minutes"] == 3
    assert watch.due_alerts() == []
    now[0] = T0 + timedelta(minutes=UNSEEN_MINUTES)
    view = watch.watch(biz, OWNER)
    assert _state(watch, biz, t1)["state"] == "unseen" and view["counts"] == {
        "empty": 1, "seated": 0, "unseen": 1, "waiting": 0, "eating": 0}
    assert view["alerts"] == [{"table_id": t1, "table_name": "T1", "minutes": UNSEEN_MINUTES}]
    due = watch.due_alerts()
    assert len(due) == 1 and due[0]["table_name"] == "T1" and due[0]["minutes"] == UNSEEN_MINUTES
    # the owner and the waiter hear it; the kitchen and the delivery person are left alone
    assert due[0]["users"] == [OWNER, WAITER]
    text = alert_text(due[0])
    assert text["route"] == f"/pos/{biz}/tables/watch" and "T1" in text["title"] and "లేదు" not in text["title"] + text["body"]
    assert watch.due_alerts() == []  # once per sitting


def test_i_am_there_and_they_left(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    watch.sat(biz, t1)
    watch.sat(biz, t2)
    now[0] = T0 + timedelta(minutes=2)
    assert watch.seen(biz, WAITER, t1) == {"ok": True, "changed": True}
    assert watch.seen(biz, WAITER, t1) == {"ok": True, "changed": False}
    now[0] = T0 + timedelta(minutes=9)
    one = _state(watch, biz, t1)
    assert one["state"] == "seated" and one["seen"] is True and one["minutes"] == 9
    assert _state(watch, biz, t2)["state"] == "unseen"
    assert [d["table_name"] for d in watch.due_alerts()] == ["T2"]  # T1 was attended: silent
    assert watch.free(biz, WAITER, t2) == {"ok": True, "changed": True}
    assert _state(watch, biz, t2)["state"] == "empty"
    assert watch.free(biz, WAITER, t2) == {"ok": True, "changed": False}
    assert watch.sat(biz, t2) is True  # the next people sit down


def test_order_makes_it_waiting_then_eating_then_empty(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    code = f"{QR_PREFIX}{biz}:{t1}"
    watch.sat(biz, t1)
    now[0] = T0 + timedelta(minutes=2)
    order = desk.place(CUSTOMER, code, {"items": [{"product_id": item, "qty": 2}], "client_txn_id": "txn-w1a2b3c4"})
    now[0] = T0 + timedelta(minutes=8)
    waiting = _state(watch, biz, t1)
    assert waiting["state"] == "waiting" and waiting["minutes"] == 6 and waiting["desk_order_id"] == order["id"]
    assert watch.due_alerts() == []  # they ordered: nobody is rung about the sitting
    assert watch.sat(biz, t1) is False  # opening the menu again while an order runs is not a new sitting
    desk.confirm(biz, COOK, order["id"], {})
    desk.advance(biz, COOK, order["id"], "preparing")
    desk.advance(biz, COOK, order["id"], "ready")
    assert _state(watch, biz, t1)["state"] == "waiting"
    now[0] = T0 + timedelta(minutes=15)
    desk.advance(biz, OWNER, order["id"], "served")
    now[0] = T0 + timedelta(minutes=40)
    eating = _state(watch, biz, t1)
    assert eating["state"] == "eating" and eating["minutes"] == 25
    desk.bill(biz, OWNER, order["id"], [{"method": "cash", "amount_paise": 8000}])
    desk.advance(biz, OWNER, order["id"], "done")
    assert _state(watch, biz, t1)["state"] == "empty"  # the old sitting does not come back


def test_staff_made_table_order_counts_too(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    order = rest.open_order(biz, WAITER, {"table_id": t2, "kind": "dine_in"})
    rest.add_items(biz, WAITER, order["id"], [{"product_id": item, "qty": 1}])
    now[0] = T0 + timedelta(minutes=4)
    assert _state(watch, biz, t2)["state"] == "waiting" and _state(watch, biz, t2)["pos_order_id"] == order["id"]
    kot = rest.send_kot(biz, WAITER, order["id"])["kot"]
    for status in ("preparing", "ready", "served"):
        rest.set_kot_status(biz, OWNER, kot["id"], status)
    now[0] = T0 + timedelta(minutes=10)
    assert _state(watch, biz, t2)["state"] == "eating" and _state(watch, biz, t2)["minutes"] == 6


def test_old_sitting_ends_by_itself_and_who_may_look(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    watch.sat(biz, t1)
    now[0] = T0 + timedelta(hours=3, minutes=1)
    assert _state(watch, biz, t1)["state"] == "empty"
    assert watch.due_alerts() == []
    assert watch.watch(biz, WAITER)["unseen_minutes"] == UNSEEN_MINUTES
    assert watch.watch(biz, COOK)["tables"]
    with pytest.raises(PosError) as e:
        watch.watch(biz, RIDER)
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        watch.watch(biz, STRANGER)
    assert e.value.status == 404
    with pytest.raises(PosError):
        watch.free(biz, STRANGER, t1)


def test_a_qr_scanned_again_and_again_cannot_ring_all_day(env):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    told = 0
    for i in range(MAX_ALERTS_PER_TABLE_DAY + 5):
        now[0] = T0 + timedelta(minutes=10 * i)
        assert watch.sat(biz, t1) is True
        now[0] = T0 + timedelta(minutes=10 * i + UNSEEN_MINUTES)
        told += len(watch.due_alerts())
        watch.free(biz, OWNER, t1)
    assert told == MAX_ALERTS_PER_TABLE_DAY


def test_periodic_job_pushes_once(env, monkeypatch):
    watch, desk, store, rest, biz, t1, t2, item, now = env
    from app.services import periodic_jobs, push_service as push_module

    sent = []

    class _Push:
        def notify(self, user, *, title, body, route, event_key):
            sent.append((user, route, event_key))
            return 1

    monkeypatch.setattr(push_module, "push_service", lambda container: _Push())

    class _Container:
        pos_store = store
        pos_table_watch = watch

    watch.sat(biz, t1)
    now[0] = T0 + timedelta(minutes=6)
    assert periodic_jobs._table_watch(_Container()) == {"due": 1, "pushed": 2}
    assert {u for u, _, _ in sent} == {OWNER, WAITER} and all(r == f"/pos/{biz}/tables/watch" for _, r, _ in sent)
    assert periodic_jobs._table_watch(_Container()) == {"due": 0, "pushed": 0}
    assert any(name == "table_watch" for name, _, _ in periodic_jobs.default_jobs())
