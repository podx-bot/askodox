"""Table reservation ahead of time (owner 2026-11-19)."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.pos_reservations import HOLD_MINUTES, PosReservations
from app.services.pos_restaurant import PosRestaurant
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9300000031"
RAVI = "app-phone-9300000032"
SITA = "app-phone-9300000033"


@pytest.fixture()
def env(tmp_path):
    clock = {"now": datetime(2026, 10, 24, 6, 0, tzinfo=timezone.utc)}
    now = lambda: clock["now"]  # noqa: E731
    store = PosStore(str(tmp_path / "pos.db"), clock=now)
    biz = store.create_business(OWNER, {"name": "Sai Tiffins", "registration_type": "unregistered", "state_code": "37",
                                        "template": "restaurant", "invoice_prefix": "ST"})["id"]
    rest = PosRestaurant(store)
    t2 = rest.add_table(biz, OWNER, {"name": "T1", "seats": 2})
    t6 = rest.add_table(biz, OWNER, {"name": "T2", "seats": 6})
    pushes = []
    return PosReservations(store, notify=lambda *a: pushes.append(a), clock=now), biz, t2["id"], t6["id"], pushes, clock


def test_free_tables_book_once_and_the_owner_is_told(env):
    res, biz, t2, t6, pushes, clock = env
    at = (clock["now"] + timedelta(hours=2)).isoformat()
    free = res.free_tables(biz, at, 4)
    assert [t["id"] for t in free["tables"]] == [t6], "only a table with enough seats"
    booked = res.book(RAVI, biz, {"table_id": t6, "at": at, "people": 4, "name": "Ravi", "client_txn_id": "res-0001"})
    assert booked["status"] == "booked" and booked["table_name"] == "T2" and pushes[-1][0] == OWNER
    assert res.book(RAVI, biz, {"table_id": t6, "at": at, "people": 4, "client_txn_id": "res-0001"})["id"] == booked["id"]
    assert res.free_tables(biz, at, 4)["tables"] == [], "the same table is not offered around that time"
    with pytest.raises(PosError) as e:
        res.book(SITA, biz, {"table_id": t6, "at": (clock["now"] + timedelta(hours=2, minutes=30)).isoformat(), "people": 2})
    assert e.value.code == "table"
    later = (clock["now"] + timedelta(hours=5)).isoformat()
    assert t6 in [t["id"] for t in res.free_tables(biz, later, 2)["tables"]], "free again outside the slot"
    assert [r["id"] for r in res.for_business(biz, OWNER)] == [booked["id"]]
    with pytest.raises(PosError):
        res.free_tables(biz, (clock["now"] - timedelta(hours=1)).isoformat(), 2)


def test_no_show_frees_the_table_and_either_side_can_cancel(env):
    res, biz, t2, _t6, pushes, clock = env
    at = clock["now"] + timedelta(minutes=30)
    booked = res.book(RAVI, biz, {"table_id": t2, "at": at.isoformat(), "people": 2})
    clock["now"] = at + timedelta(minutes=HOLD_MINUTES + 1)
    assert res.mine(RAVI)[0]["status"] == "no_show"
    again = res.book(SITA, biz, {"table_id": t2, "at": (clock["now"] + timedelta(minutes=10)).isoformat(), "people": 2})
    assert res.cancel_mine(SITA, again["id"])["status"] == "cancelled" and pushes[-1][0] == OWNER
    third = res.book(SITA, biz, {"table_id": t2, "at": (clock["now"] + timedelta(minutes=20)).isoformat(), "people": 2})
    assert res.set_status(biz, OWNER, third["id"], "cancelled")["status"] == "cancelled" and pushes[-1][0] == SITA
    with pytest.raises(PosError):
        res.cancel_mine(RAVI, third["id"])
    assert booked["id"] != third["id"]
