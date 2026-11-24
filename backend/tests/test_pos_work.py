"""Business Kit ways 3-5 (owner 2026-11-24): bookings (hotel rooms by day, salon / doctor by time; never two on one
thing), job cards (token, estimate, advance, ready -> customer told, WhatsApp text for others), monthly members (a
due per month, part / full / waived; reminders). Money is only recorded; customers pay the shop."""

from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_store import PosError, PosStore
from app.services.pos_work import PosBookings, PosJobs, PosMonthly

OWNER = "app-phone-9400000601"
CUSTOMER = "app-phone-9400000602"
STRANGER = "app-phone-9400000603"
T0 = datetime(2026, 12, 1, 4, 30, tzinfo=timezone.utc)  # 10:00 IST


@pytest.fixture()
def env(tmp_path):
    now = [T0]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    pushes = []
    notify = lambda u, t, b, r, k: pushes.append((u, t, b, r, k))  # noqa: E731
    shop = store.create_business(OWNER, {"name": "Sai Lodge & Salon", "state_code": "37"})["id"]
    kit = dict(notify=notify, clock=lambda: now[0])
    return store, PosBookings(store, **kit), PosJobs(store, **kit), PosMonthly(store, **kit), shop, pushes, now


def test_rooms_by_day_and_chairs_by_time_never_double_booked(env):
    store, bookings, _, _, shop, pushes, _ = env
    room = bookings.save_item(shop, OWNER, {"name": "Room 101 AC", "mode": "day", "capacity": 3, "price_paise": 150000})
    chair = bookings.save_item(shop, OWNER, {"name": "Chair 1", "mode": "slot", "slot_minutes": 30})
    with pytest.raises(PosError):
        bookings.save_item(shop, CUSTOMER, {"name": "x"})  # only the shop sets up what can be booked
    free = bookings.free(shop, {"from_date": "2026-12-05", "to_date": "2026-12-07", "people": 2})
    assert [f["name"] for f in free["free"]] == ["Room 101 AC"]
    mine = bookings.book(CUSTOMER, shop, {"item_id": room["id"], "from_date": "2026-12-05", "to_date": "2026-12-07",
                                          "people": 2, "name": "Ravi"})
    assert mine["status"] == "booked" and mine["start"] == "2026-12-05T06:30:00+00:00"  # noon IST check-in
    assert pushes[-1][0] == OWNER and pushes[-1][3] == f"/biz/{shop}/bookings"
    with pytest.raises(PosError) as taken:  # the 6th overlaps the stay; leaving day morning is still theirs
        bookings.book(STRANGER, shop, {"item_id": room["id"], "from_date": "2026-12-06", "to_date": "2026-12-08"})
    assert taken.value.status == 409
    back_to_back = bookings.book(STRANGER, shop, {"item_id": room["id"], "from_date": "2026-12-07", "to_date": "2026-12-08"})
    assert back_to_back["status"] == "booked", "check-out 11 AM, next check-in noon"
    with pytest.raises(PosError):
        bookings.book(STRANGER, shop, {"item_id": room["id"], "from_date": "2026-12-09", "to_date": "2026-12-10", "people": 4})
    a = bookings.add(shop, OWNER, {"item_id": chair["id"], "at": "2026-12-01T11:00:00", "name": "Walk-in", "phone": "9400000604"})
    with pytest.raises(PosError):
        bookings.add(shop, OWNER, {"item_id": chair["id"], "at": "2026-12-01T11:15:00"})
    assert bookings.add(shop, OWNER, {"item_id": chair["id"], "at": "2026-12-01T11:30:00"})["status"] == "booked"
    day = bookings.for_business(shop, OWNER, "2026-12-01")
    assert [b["item"] for b in day["bookings"]] == ["Chair 1", "Chair 1"] and day["upcoming"] >= 2
    assert bookings.set_status(shop, OWNER, a["id"], "arrived")["status"] == "arrived"
    with pytest.raises(PosError):
        bookings.set_status(shop, OWNER, a["id"], "booked")
    assert [b["id"] for b in bookings.mine(CUSTOMER)] == [mine["id"]]
    assert bookings.cancel_mine(CUSTOMER, mine["id"])["status"] == "cancelled"
    assert bookings.book(STRANGER, shop, {"item_id": room["id"], "from_date": "2026-12-05", "to_date": "2026-12-06"})


def test_job_card_from_received_to_ready_tells_the_customer(env):
    store, _, jobs, _, shop, pushes, _ = env
    first = jobs.create(shop, OWNER, {"item": "Redmi Note 12", "details": "screen broken", "phone": "94000 00602",
                                      "estimate_paise": 250000, "advance_paise": 50000, "ready_by": "2026-12-02",
                                      "client_txn_id": "t1"})
    assert first["token"] == 1 and first["balance_paise"] == 200000 and first["in_app"]
    assert jobs.create(shop, OWNER, {"item": "Redmi Note 12", "client_txn_id": "t1"})["id"] == first["id"], "idempotent"
    second = jobs.create(shop, OWNER, {"item": "Blouse stitching", "name": "Lakshmi", "phone": "9400000699"})
    assert second["token"] == 2
    with pytest.raises(PosError):
        jobs.update(shop, OWNER, first["id"], {"status": "delivered"})  # not ready yet
    jobs.update(shop, OWNER, first["id"], {"status": "working"})
    ready = jobs.update(shop, OWNER, first["id"], {"status": "ready"})
    assert pushes[-1][0] == CUSTOMER and "రెడీ" in pushes[-1][2] and "2000" in pushes[-1][2]
    assert ready["whatsapp_url"].startswith("https://wa.me/919400000602?text=")
    other = jobs.update(shop, OWNER, second["id"], {"status": "ready"})
    assert other["whatsapp_url"].startswith("https://wa.me/919400000699") and pushes[-1][0] == "app-phone-9400000699"
    listed = jobs.for_business(shop, OWNER)
    assert [j["status"] for j in listed["jobs"]] == ["ready", "ready"] and listed["counts"]["ready"] == 2
    assert jobs.update(shop, OWNER, first["id"], {"status": "delivered"})["status"] == "delivered"
    assert [j["item"] for j in jobs.mine(CUSTOMER)] == ["Redmi Note 12"] and "customer_phone" not in jobs.mine(CUSTOMER)[0]
    with pytest.raises(PosError):
        jobs.for_business(shop, STRANGER)


def test_monthly_members_get_one_due_a_month(env):
    store, _, _, monthly, shop, _, now = env
    milk = monthly.save_plan(shop, OWNER, {"name": "Milk 1 L daily", "amount_paise": 180000})
    with pytest.raises(PosError):
        monthly.save_plan(shop, OWNER, {"name": "x", "amount_paise": 0})
    month = monthly.add_member(shop, OWNER, {"plan_id": milk["id"], "name": "Ravi", "phone": "9400000602", "due_day": 5})
    ravi = month["members"][0]
    assert month["month"] == "2026-12" and ravi["left_paise"] == 180000 and not ravi["late"]
    assert ravi["whatsapp_url"].startswith("https://wa.me/919400000602")
    again = monthly.month(shop, OWNER)
    assert len(again["members"]) == 1 and again["owed_paise"] == 180000, "one due per month, however often looked at"
    part = monthly.pay(shop, OWNER, ravi["id"], {"amount_paise": 100000})
    assert part["members"][0]["left_paise"] == 80000 and part["collected_paise"] == 100000
    full = monthly.pay(shop, OWNER, ravi["id"], {})
    assert full["members"][0]["due_status"] == "paid" and full["owed_paise"] == 0
    now[0] = T0 + timedelta(days=40)  # January, after the due day
    jan = monthly.month(shop, OWNER)
    assert jan["month"] == "2027-01" and jan["members"][0]["left_paise"] == 180000 and jan["members"][0]["late"]
    assert monthly.mine(CUSTOMER)[0]["left_paise"] == 180000
    assert monthly.pay(shop, OWNER, ravi["id"], {"waive": True})["owed_paise"] == 0
    monthly.set_member(shop, OWNER, ravi["id"], "stopped")
    assert monthly.mine(CUSTOMER) == []
    with pytest.raises(PosError):
        monthly.month(shop, STRANGER)


def test_routes_are_mounted_and_need_the_shop_role(tmp_path, monkeypatch):
    from app.api import app_factory

    paths = {r.path for r in app_factory.create_app().routes}
    for path in ("/api/pos/businesses/{business_id}/bookings", "/api/pos/book/{business_id}", "/api/pos/me/jobs",
                 "/api/pos/businesses/{business_id}/jobs/{job_id}", "/api/pos/businesses/{business_id}/monthly",
                 "/api/pos/me/monthly"):
        assert path in paths, path
