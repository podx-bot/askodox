"""Branches (owner 2026-11-24): one owner links his own shops -> shared delivery pool + all-branches view."""
from datetime import datetime, timezone

import pytest

from app.services.pos_branches import PosBranches, sibling_ids
from app.services.pos_delivery_jobs import PosDeliveryJobs
from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000901"
OTHER = "app-phone-9400000909"
T0 = datetime(2026, 12, 1, 6, 30, tzinfo=timezone.utc)


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: T0)
    a = store.create_business(OWNER, {"name": "Sai Sweets Vuyyuru", "state_code": "37"})["id"]
    b = store.create_business(OWNER, {"name": "Sai Sweets Gudivada", "state_code": "37"})["id"]
    c = store.create_business(OTHER, {"name": "Someone Else", "state_code": "37"})["id"]
    store.set_member(a, OWNER, "9400000902", "delivery", label="Ravi")
    store.set_member(b, OWNER, "9400000903", "delivery", label="Suresh")
    return store, PosBranches(store), a, b, c


def test_link_pool_and_overview(env):
    store, branches, a, b, c = env
    jobs = PosDeliveryJobs(store, notify=lambda *x: None, clock=lambda: T0)
    assert {p["id"] for p in jobs.people(a, OWNER)["people"]} >= {"app-phone-9400000902"}
    assert "app-phone-9400000903" not in {p["id"] for p in jobs.people(a, OWNER)["people"]}
    out = branches.save(OWNER, "Sai Sweets", [a, b])
    assert [x["name"] for x in out["groups"][0]["branches"]] == ["Sai Sweets Vuyyuru", "Sai Sweets Gudivada"]
    with store._connect() as conn:
        assert sibling_ids(conn, a) == [b]
    pool = {p["id"]: p["label"] for p in jobs.people(a, OWNER)["people"]}
    assert "app-phone-9400000903" in pool and "Gudivada" in pool["app-phone-9400000903"]
    job = jobs.create(a, OWNER, {"to": "Param", "ask": ["app-phone-9400000903"]})
    jobs.give(a, OWNER, job["id"], "app-phone-9400000903")
    ov = branches.overview(OWNER, out["groups"][0]["id"], "2026-12-01")
    assert len(ov["branches"]) == 2 and ov["total"]["invoices"] == 0


def test_only_own_shops_and_owner_overview(env):
    store, branches, a, b, c = env
    with pytest.raises(PosError):
        branches.save(OWNER, "x", [a, c])
    with pytest.raises(PosError):
        branches.save(OWNER, "x", [a])
    gid = branches.save(OWNER, "g", [a, b])["groups"][0]["id"]
    with pytest.raises(PosError):
        branches.overview(OTHER, gid, "2026-12-01")
    assert branches.leave(OWNER, b)["groups"] == []
